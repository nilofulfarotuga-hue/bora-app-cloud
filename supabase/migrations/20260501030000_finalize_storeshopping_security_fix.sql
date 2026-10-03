-- ============================================================================
-- BORA — RPC finalize_storeshopping_purchase: SECURITY HARDENING
-- ============================================================================
-- Vector preventido: estafeta podia inflar prices via payload.
--
-- Versão anterior somava `bought_total_cents` a partir de `price`/`price_cents`
-- vindos no payload — estafeta inflava +X% e o sistema cobrava extra ao
-- cliente (auditoria detectava após o facto, mas não prevenia).
--
-- FIX:
--   • Prices canónicos lidos APENAS de `orders.items` (gravado imutavelmente
--     no checkout). Payload `p_items_status` só transporta `id`/`productId`
--     + `purchase_status`. Tudo o resto do payload é ignorado.
--   • `p_items_added` mantém-se: items NOVOS não existem em orders.items,
--     então precisam de `price_base_cents` no payload. Markup +15% server-side.
--   • Validações: payload sem id → erro; id desconhecido (não está em
--     orders.items) → erro.
--   • Audit log details inclui 'item_price_source': 'orders.items_canonical'.
--
-- BUG colateral co-fixed (refund/extra column consistency):
--   • `refund_amount = 0` violava check constraint refund_consistency.
--     Agora: NULL quando não há refund.
--   • `_enforce_refund_cap` exige refund <= paid_cents
--     (stripe + wallet + tokens). RPC agora cap refund a paid_cents.
--   • Cash não tem refund/extra (driver collects diff at delivery).
--     Card/MBWay → set refund_method='stripe' / extra_charge_amount > 0.
--     Cash + wallet_applied > 0 → refund_method='wallet' (apenas a porção paga).
-- ============================================================================

BEGIN;

CREATE OR REPLACE FUNCTION public.finalize_storeshopping_purchase(
  p_order_id     TEXT,
  p_items_status JSONB,
  p_items_added  JSONB DEFAULT '[]'::jsonb
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $function$
DECLARE
  v_caller_uid              UUID;
  v_order                   RECORD;
  v_markup_pct              NUMERIC;
  v_max_extra_pct           NUMERIC;
  v_bought_total_cents      INT := 0;
  v_unavailable_total_cents INT := 0;
  v_added_total_cents       INT := 0;
  v_bag_fee_cents           INT;
  v_final_total_cents       INT;
  v_orig_total_cents        INT;
  v_paid_cents              INT;
  v_refund_cents            INT;
  v_extra_charge_cents      INT;
  v_refund_method           TEXT := NULL;
  v_new_payment_status      TEXT;
  v_warning                 TEXT := NULL;
  v_items_added_resolved    JSONB := '[]'::jsonb;
  v_payload_entry           JSONB;
  v_canonical_item          JSONB;
  v_added_item              JSONB;
  v_payload_id              TEXT;
  v_payload_status          TEXT;
  v_canon_price_cents       INT;
  v_canon_qty               INT;
  v_base_cents              INT;
  v_qty                     INT;
  v_final_cents             INT;
  v_status_by_id            JSONB := '{}'::jsonb;
  v_merged_items            JSONB := '[]'::jsonb;
  v_canon_id                TEXT;
  v_canon_status            TEXT;
  v_is_card                 BOOLEAN;
BEGIN
  -- ── Auth ─────────────────────────────────────────────────────────────────
  v_caller_uid := auth.uid();
  IF v_caller_uid IS NULL THEN
    RAISE EXCEPTION 'unauthenticated' USING ERRCODE = '42501';
  END IF;

  SELECT * INTO v_order FROM public.orders WHERE id = p_order_id FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'order_not_found: %', p_order_id USING ERRCODE = 'P0002';
  END IF;

  IF v_order.assigned_driver_id IS DISTINCT FROM v_caller_uid::text THEN
    RAISE EXCEPTION 'forbidden_not_assigned_driver: caller=% driver=%',
      v_caller_uid, v_order.assigned_driver_id
      USING ERRCODE = '42501';
  END IF;

  IF COALESCE(v_order.is_purchase_finalized, false) = true THEN
    RAISE EXCEPTION 'already_finalized' USING ERRCODE = '23514';
  END IF;

  IF v_order.service_type <> 'storeShopping' THEN
    RAISE EXCEPTION 'wrong_service_type: % (expected storeShopping)', v_order.service_type
      USING ERRCODE = '23514';
  END IF;

  -- ── Settings ─────────────────────────────────────────────────────────────
  SELECT COALESCE((value::text)::numeric, 0.15) INTO v_markup_pct
    FROM public.platform_settings WHERE key = 'non_partner_markup_pct';
  v_markup_pct := COALESCE(v_markup_pct, 0.15);

  SELECT COALESCE((value::text)::numeric, 0.30) INTO v_max_extra_pct
    FROM public.platform_settings WHERE key = 'max_extra_charge_pct';
  v_max_extra_pct := COALESCE(v_max_extra_pct, 0.30);

  -- ── Build {payload_id → status} map (status is the only payload signal) ──
  IF p_items_status IS NOT NULL AND jsonb_typeof(p_items_status) = 'array' THEN
    FOR v_payload_entry IN SELECT jsonb_array_elements(p_items_status)
    LOOP
      v_payload_id := COALESCE(
        v_payload_entry->>'id',
        v_payload_entry->>'productId',
        v_payload_entry->>'product_id'
      );
      v_payload_status := COALESCE(
        v_payload_entry->>'purchase_status',
        v_payload_entry->>'purchaseStatus'
      );

      IF v_payload_id IS NULL OR v_payload_id = '' THEN
        RAISE EXCEPTION 'missing_item_id_in_payload: %', v_payload_entry::text
          USING ERRCODE = '23514';
      END IF;

      v_status_by_id := v_status_by_id || jsonb_build_object(
        v_payload_id, COALESCE(v_payload_status, 'pending')
      );
    END LOOP;
  END IF;

  -- ── Walk canonical orders.items: source of truth for price+qty ───────────
  IF v_order.items IS NOT NULL AND jsonb_typeof(v_order.items) = 'array' THEN
    FOR v_canonical_item IN SELECT jsonb_array_elements(v_order.items)
    LOOP
      v_canon_id := COALESCE(
        v_canonical_item->>'productId',
        v_canonical_item->>'product_id',
        v_canonical_item->>'id'
      );
      v_canon_price_cents := ROUND(
        COALESCE((v_canonical_item->>'price')::numeric, 0) * 100
      )::int;
      v_canon_qty := COALESCE(
        NULLIF(v_canonical_item->>'quantity','')::int,
        NULLIF(v_canonical_item->>'qty','')::int,
        1
      );

      v_canon_status := COALESCE(
        v_status_by_id->>v_canon_id,
        v_canonical_item->>'purchaseStatus',
        v_canonical_item->>'purchase_status',
        'pending'
      );

      IF v_canon_status = 'bought' THEN
        v_bought_total_cents := v_bought_total_cents + (v_canon_price_cents * v_canon_qty);
      ELSIF v_canon_status = 'unavailable' THEN
        v_unavailable_total_cents := v_unavailable_total_cents + (v_canon_price_cents * v_canon_qty);
      END IF;

      v_merged_items := v_merged_items || jsonb_build_array(
        v_canonical_item || jsonb_build_object('purchaseStatus', v_canon_status)
      );

      v_status_by_id := v_status_by_id - v_canon_id;
    END LOOP;
  END IF;

  -- ── Validate: any payload id that did NOT match a canonical item is an error
  IF jsonb_typeof(v_status_by_id) = 'object' AND v_status_by_id <> '{}'::jsonb THEN
    RAISE EXCEPTION 'unknown_item_id: %s not in orders.items',
      (SELECT string_agg(k, ', ') FROM jsonb_object_keys(v_status_by_id) k)
      USING ERRCODE = '23514';
  END IF;

  -- ── Items added (substitutions / extras) — payload IS the source ─────────
  IF p_items_added IS NOT NULL AND jsonb_typeof(p_items_added) = 'array' THEN
    FOR v_added_item IN SELECT jsonb_array_elements(p_items_added)
    LOOP
      v_base_cents := COALESCE((v_added_item->>'price_base_cents')::int, 0);
      v_qty := COALESCE(
        NULLIF(v_added_item->>'qty','')::int,
        NULLIF(v_added_item->>'quantity','')::int,
        1
      );
      v_final_cents := ROUND(v_base_cents * (1 + v_markup_pct))::int;

      IF v_base_cents <= 0 THEN
        RAISE EXCEPTION 'invalid_added_item_price: name=%', v_added_item->>'name'
          USING ERRCODE = '23514';
      END IF;

      v_added_total_cents := v_added_total_cents + (v_final_cents * v_qty);

      v_items_added_resolved := v_items_added_resolved || jsonb_build_array(
        jsonb_build_object(
          'name',              v_added_item->>'name',
          'price_base_cents',  v_base_cents,
          'price_final_cents', v_final_cents,
          'qty',               v_qty,
          'reason',            COALESCE(v_added_item->>'reason', 'driver_substitution'),
          'added_at',          to_jsonb(now()),
          'added_by',          to_jsonb(v_caller_uid)
        )
      );
    END LOOP;
  END IF;

  -- ── Compute totals (cents) ───────────────────────────────────────────────
  v_bag_fee_cents := ROUND(COALESCE(v_order.bag_fee, 0) * 100)::int;

  v_orig_total_cents := ROUND(
    COALESCE(v_order.payment_buffer_total, v_order.final_total, 0) * 100
  )::int;

  v_paid_cents := COALESCE(v_order.stripe_charge_cents, 0)
                + COALESCE(v_order.wallet_applied_cents, 0)
                + COALESCE(v_order.tokens_applied_value_cents, 0);

  v_final_total_cents := v_bought_total_cents + v_added_total_cents + v_bag_fee_cents;
  v_is_card := v_order.payment_method IN ('card', 'mbway');

  IF v_final_total_cents < v_orig_total_cents THEN
    -- Bought less. Refund only what was actually paid (cap).
    -- Pure cash (paid_cents=0) → no refund column (driver collects less in cash).
    v_refund_cents := LEAST(v_orig_total_cents - v_final_total_cents, v_paid_cents);
    IF v_refund_cents > 0 THEN
      v_refund_method := CASE WHEN v_is_card THEN 'stripe' ELSE 'wallet' END;
      v_new_payment_status := 'refundPending';
    ELSE
      v_new_payment_status := v_order.payment_status;  -- cash collects at delivery
    END IF;
    v_extra_charge_cents := 0;
  ELSIF v_final_total_cents > v_orig_total_cents THEN
    -- Bought more. Card/MBWay → Stripe charge-extra. Cash → driver collects.
    IF v_is_card THEN
      v_extra_charge_cents := v_final_total_cents - v_orig_total_cents;
      v_new_payment_status := 'extraRequired';
    ELSE
      v_extra_charge_cents := 0;
      v_new_payment_status := v_order.payment_status;
    END IF;
    v_refund_cents := 0;
  ELSE
    v_refund_cents := 0;
    v_extra_charge_cents := 0;
    v_new_payment_status := v_order.payment_status;
  END IF;

  -- Warning if extra exceeds limit (non-blocking)
  IF v_orig_total_cents > 0
     AND v_extra_charge_cents > ROUND(v_orig_total_cents * v_max_extra_pct)::int
  THEN
    v_warning := format(
      'extra_charge exceeds %s%% limit: extra=%s orig=%s',
      ROUND(v_max_extra_pct * 100)::int, v_extra_charge_cents, v_orig_total_cents
    );
  END IF;

  -- Bypass financial trigger for this transaction
  PERFORM set_config('app.financial_bypass', 'true', true);

  -- Persist. NULLIF satisfies refund_consistency check
  -- (refund_amount IS NULL OR refund_method IS NOT NULL).
  UPDATE public.orders SET
    items                 = v_merged_items,
    items_added           = v_items_added_resolved,
    final_total           = v_final_total_cents::numeric / 100.0,
    refund_amount         = CASE WHEN v_refund_cents > 0
                                 THEN v_refund_cents::numeric / 100.0
                                 ELSE NULL END,
    refund_method         = v_refund_method,
    extra_charge_amount   = CASE WHEN v_extra_charge_cents > 0
                                 THEN v_extra_charge_cents::numeric / 100.0
                                 ELSE NULL END,
    is_purchase_finalized = true,
    payment_status        = v_new_payment_status
  WHERE id = p_order_id;

  -- Audit log (best-effort)
  BEGIN
    INSERT INTO public.admin_audit_log (
      admin_id, admin_email, action, entity_type, entity_id_text, details
    ) VALUES (
      v_caller_uid,
      (SELECT email FROM auth.users WHERE id = v_caller_uid),
      'storeshopping_finalize',
      'order',
      p_order_id,
      jsonb_build_object(
        'driver_id',                v_caller_uid,
        'bought_total_cents',       v_bought_total_cents,
        'unavailable_total_cents',  v_unavailable_total_cents,
        'added_total_cents',        v_added_total_cents,
        'bag_fee_cents',            v_bag_fee_cents,
        'final_total_cents',        v_final_total_cents,
        'orig_total_cents',         v_orig_total_cents,
        'paid_cents',               v_paid_cents,
        'refund_cents',             v_refund_cents,
        'refund_method',            v_refund_method,
        'extra_charge_cents',       v_extra_charge_cents,
        'payment_status_before',    v_order.payment_status,
        'payment_status_after',     v_new_payment_status,
        'items_added_count',        jsonb_array_length(v_items_added_resolved),
        'markup_pct',               v_markup_pct,
        'max_extra_pct',            v_max_extra_pct,
        'warning',                  v_warning,
        'payment_method',           v_order.payment_method,
        'item_price_source',        'orders.items_canonical'
      )
    );
  EXCEPTION WHEN OTHERS THEN
    RAISE WARNING 'finalize_storeshopping_purchase: audit log failed: %', SQLERRM;
  END;

  RETURN jsonb_build_object(
    'success',            true,
    'order_id',           p_order_id,
    'final_total_cents',  v_final_total_cents,
    'orig_total_cents',   v_orig_total_cents,
    'paid_cents',         v_paid_cents,
    'refund_cents',       v_refund_cents,
    'refund_method',      v_refund_method,
    'extra_charge_cents', v_extra_charge_cents,
    'payment_status',     v_new_payment_status,
    'items_added_count',  jsonb_array_length(v_items_added_resolved),
    'items_added',        v_items_added_resolved,
    'markup_pct',         v_markup_pct,
    'warning',            v_warning,
    'item_price_source',  'orders.items_canonical'
  );
END;
$function$;

COMMIT;
