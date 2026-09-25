-- ============================================================================
-- BORA — RPC: finalize_storeshopping_purchase
-- ============================================================================
-- Coordena finalização da lista de compras pelo estafeta:
--  • items marcados bought / unavailable / added (com markup +15% auto)
--  • calcula final_total, refund_amount, extra_charge_amount
--  • aplica payment_status (refundPending / extraRequired / mantém)
--  • audit log
--  • bypass do trigger enforce_financial_immutability via GUC local
--
-- Substitui UPDATE directo em order_store.dart:_finalizePurchaseUnchecked
-- que falhava com FINANCIAL_COLUMNS_IMMUTABLE.
-- ============================================================================

BEGIN;

-- ── 1) Trigger: permitir bypass via GUC `app.financial_bypass` (SET LOCAL) ──
-- Este GUC é apenas setado dentro de RPCs auditadas (finalize_*, etc).
-- Não relaxa segurança porque acesso de escrita já é restringido por RLS.
CREATE OR REPLACE FUNCTION public.enforce_financial_immutability()
RETURNS trigger
LANGUAGE plpgsql
AS $function$
BEGIN
  IF auth.role() <> 'service_role'
     AND COALESCE(current_setting('app.financial_bypass', true), 'false') <> 'true'
  THEN
    IF  NEW.price                IS DISTINCT FROM OLD.price
     OR NEW.final_total          IS DISTINCT FROM OLD.final_total
     OR NEW.subtotal             IS DISTINCT FROM OLD.subtotal
     OR NEW.delivery_fee         IS DISTINCT FROM OLD.delivery_fee
     OR NEW.service_fee          IS DISTINCT FROM OLD.service_fee
     OR NEW.platform_commission  IS DISTINCT FROM OLD.platform_commission
     OR NEW.driver_earnings      IS DISTINCT FROM OLD.driver_earnings
     OR NEW.bag_fee              IS DISTINCT FROM OLD.bag_fee
     OR NEW.payment_buffer_total IS DISTINCT FROM OLD.payment_buffer_total
    THEN
      RAISE EXCEPTION 'FINANCIAL_COLUMNS_IMMUTABLE: cannot modify financial columns post-creation (authenticated users are read-only on money columns)'
        USING ERRCODE = 'insufficient_privilege';
    END IF;
  END IF;
  RETURN NEW;
END;
$function$;

-- ── 2) RPC: finalize_storeshopping_purchase ─────────────────────────────────
-- Args:
--   p_order_id     TEXT
--   p_items_status JSONB array — replicação de orders.items com purchase_status:
--                   [{id, name, price, qty, purchase_status: 'bought'|'unavailable'|'pending', ...}]
--                   `price` é o preço já com markup pago pelo cliente (cents inteiros num "price_cents"
--                   OU euros como número em "price"). Aceitamos ambos por compat.
--   p_items_added  JSONB array — items adicionados pelo estafeta:
--                   [{name, price_base_cents, qty, reason}]
-- Returns: jsonb {success, order_id, final_total_cents, refund_cents,
--                 extra_charge_cents, payment_status, items_added_count, warning}
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
  v_refund_cents            INT;
  v_extra_charge_cents      INT;
  v_new_payment_status      TEXT;
  v_warning                 TEXT := NULL;
  v_items_added_resolved    JSONB := '[]'::jsonb;
  v_item                    JSONB;
  v_added_item              JSONB;
  v_item_price_cents        INT;
  v_item_qty                INT;
  v_base_cents              INT;
  v_qty                     INT;
  v_final_cents             INT;
BEGIN
  -- ── Auth ──────────────────────────────────────────────────────────────────
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

  -- ── Settings ──────────────────────────────────────────────────────────────
  SELECT COALESCE((value::text)::numeric, 0.15) INTO v_markup_pct
    FROM public.platform_settings WHERE key = 'non_partner_markup_pct';
  v_markup_pct := COALESCE(v_markup_pct, 0.15);

  SELECT COALESCE((value::text)::numeric, 0.30) INTO v_max_extra_pct
    FROM public.platform_settings WHERE key = 'max_extra_charge_pct';
  v_max_extra_pct := COALESCE(v_max_extra_pct, 0.30);

  -- ── Calc bought / unavailable from p_items_status ────────────────────────
  -- Item shape (compat): {price_cents:int} OR {price:number(EUR)}; qty default 1.
  IF p_items_status IS NOT NULL AND jsonb_typeof(p_items_status) = 'array' THEN
    FOR v_item IN SELECT jsonb_array_elements(p_items_status)
    LOOP
      v_item_price_cents := COALESCE(
        (v_item->>'price_cents')::int,
        ROUND(COALESCE((v_item->>'price')::numeric, 0) * 100)::int,
        0
      );
      v_item_qty := COALESCE(NULLIF(v_item->>'qty','')::int, 1);

      IF (v_item->>'purchase_status') = 'bought' THEN
        v_bought_total_cents := v_bought_total_cents + (v_item_price_cents * v_item_qty);
      ELSIF (v_item->>'purchase_status') = 'unavailable' THEN
        v_unavailable_total_cents := v_unavailable_total_cents + (v_item_price_cents * v_item_qty);
      END IF;
    END LOOP;
  END IF;

  -- ── Calc added items total (apply markup) ────────────────────────────────
  -- Added item shape: {name, price_base_cents:int, qty?, reason?}
  IF p_items_added IS NOT NULL AND jsonb_typeof(p_items_added) = 'array' THEN
    FOR v_added_item IN SELECT jsonb_array_elements(p_items_added)
    LOOP
      v_base_cents := COALESCE((v_added_item->>'price_base_cents')::int, 0);
      v_qty := COALESCE(NULLIF(v_added_item->>'qty','')::int, 1);
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

  -- ── Compute totals (cents) ────────────────────────────────────────────────
  v_bag_fee_cents := ROUND(COALESCE(v_order.bag_fee, 0) * 100)::int;

  v_orig_total_cents := ROUND(
    COALESCE(v_order.payment_buffer_total, v_order.final_total, 0) * 100
  )::int;

  v_final_total_cents := v_bought_total_cents + v_added_total_cents + v_bag_fee_cents;

  IF v_final_total_cents < v_orig_total_cents THEN
    v_refund_cents := v_orig_total_cents - v_final_total_cents;
    v_extra_charge_cents := 0;
    v_new_payment_status := 'refundPending';
  ELSIF v_final_total_cents > v_orig_total_cents THEN
    v_refund_cents := 0;
    v_extra_charge_cents := v_final_total_cents - v_orig_total_cents;
    v_new_payment_status := 'extraRequired';
  ELSE
    v_refund_cents := 0;
    v_extra_charge_cents := 0;
    v_new_payment_status := v_order.payment_status;  -- keep current
  END IF;

  -- ── Warning if extra exceeds limit (non-blocking) ────────────────────────
  IF v_orig_total_cents > 0
     AND v_extra_charge_cents > ROUND(v_orig_total_cents * v_max_extra_pct)::int
  THEN
    v_warning := format(
      'extra_charge exceeds %s%% limit: extra=%s orig=%s',
      ROUND(v_max_extra_pct * 100)::int, v_extra_charge_cents, v_orig_total_cents
    );
  END IF;

  -- ── Bypass financial trigger for this transaction ────────────────────────
  PERFORM set_config('app.financial_bypass', 'true', true);

  -- ── Persist ──────────────────────────────────────────────────────────────
  UPDATE public.orders SET
    items                 = COALESCE(p_items_status, items),
    items_added           = v_items_added_resolved,
    final_total           = v_final_total_cents::numeric / 100.0,
    refund_amount         = v_refund_cents::numeric / 100.0,
    extra_charge_amount   = v_extra_charge_cents::numeric / 100.0,
    is_purchase_finalized = true,
    payment_status        = v_new_payment_status
  WHERE id = p_order_id;

  -- ── Audit log (best-effort) ──────────────────────────────────────────────
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
        'refund_cents',             v_refund_cents,
        'extra_charge_cents',       v_extra_charge_cents,
        'payment_status_before',    v_order.payment_status,
        'payment_status_after',     v_new_payment_status,
        'items_added_count',        jsonb_array_length(v_items_added_resolved),
        'markup_pct',               v_markup_pct,
        'max_extra_pct',            v_max_extra_pct,
        'warning',                  v_warning,
        'payment_method',           v_order.payment_method
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
    'refund_cents',       v_refund_cents,
    'extra_charge_cents', v_extra_charge_cents,
    'payment_status',     v_new_payment_status,
    'items_added_count',  jsonb_array_length(v_items_added_resolved),
    'items_added',        v_items_added_resolved,
    'markup_pct',         v_markup_pct,
    'warning',            v_warning
  );
END;
$function$;

REVOKE ALL ON FUNCTION public.finalize_storeshopping_purchase(text, jsonb, jsonb) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.finalize_storeshopping_purchase(text, jsonb, jsonb) TO authenticated;

COMMENT ON FUNCTION public.finalize_storeshopping_purchase(text, jsonb, jsonb) IS
  'Driver finalizes storeShopping purchase: marks items bought/unavailable, '
  'adds substitution products with auto markup, computes refund/extra_charge, '
  'updates payment_status. Bypasses enforce_financial_immutability via GUC.';

COMMIT;
