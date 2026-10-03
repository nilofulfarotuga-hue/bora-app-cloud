-- ═══════════════════════════════════════════════════════════════════════════
-- BUG-SACOS-V2 (2026-05-17) — finalize_storeshopping_purchase_v2
--
-- PROBLEMA: p_bag_count nunca foi adicionado à assinatura da V2 RPC.
-- Driver escolhia 5 sacos no Flutter (_bagCount=5), mas a DB ficava com
-- bag_count=1 (valor do create_order). cash_total_due não incluía sacos.
--
-- FIX:
--   A) Adiciona p_bag_count INT DEFAULT 1 à assinatura
--   B) Lê preço/saco de platform_settings (default 10c)
--   C) Bypassa enforce_financial_immutability para actualizar bag_count/bag_fee/total/final_total
--   D) cash_total_due (cash) = talão + sacos
--
-- Compatibilidade: DROP da assinatura a 4 args (substituída por 5 args).
-- Callers sem p_bag_count continuam a funcionar via DEFAULT 1.
-- ═══════════════════════════════════════════════════════════════════════════

-- Remover assinatura antiga (4 args) para evitar ambiguidade de overload.
DROP FUNCTION IF EXISTS public.finalize_storeshopping_purchase_v2(text, integer, text, jsonb);

CREATE OR REPLACE FUNCTION public.finalize_storeshopping_purchase_v2(
  p_order_id                  text,
  p_driver_typed_total_cents  integer,
  p_receipt_photo_url         text,
  p_items                     jsonb,
  p_bag_count                 integer DEFAULT 1
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, net, auth
AS $fn$
DECLARE
  v_order               RECORD;
  v_item                jsonb;
  v_unavailable_cents   integer := 0;
  v_added_cents         integer := 0;
  v_purchased_cents     integer := 0;
  v_replaced_cents      integer := 0;
  v_final_value_cents   integer := 0;
  v_reimb_status        text;
  v_url                 text;
  v_key                 text;
  v_total_items         integer := 0;
  v_bag_unit_cents      integer := 10;
  v_bag_fee_cents       integer;
  v_bag_delta_cents     integer;
BEGIN
  IF auth.uid() IS NULL THEN RAISE EXCEPTION 'UNAUTHENTICATED'; END IF;

  IF p_bag_count < 0 OR p_bag_count > 99 THEN
    RAISE EXCEPTION 'INVALID_BAG_COUNT: % (allowed 0..99)', p_bag_count;
  END IF;

  SELECT id, user_id, assigned_driver_id, service_type, is_partner_store,
         payment_method, bag_fee
    INTO v_order
    FROM public.orders
   WHERE id = p_order_id;

  IF NOT FOUND THEN RAISE EXCEPTION 'ORDER_NOT_FOUND: %', p_order_id; END IF;
  IF v_order.service_type IS DISTINCT FROM 'storeShopping' THEN
    RAISE EXCEPTION 'WRONG_SERVICE_TYPE: %', v_order.service_type;
  END IF;
  IF COALESCE(v_order.is_partner_store, false) THEN
    RAISE EXCEPTION 'PARTNER_STORE_USE_V1';
  END IF;
  IF v_order.assigned_driver_id IS DISTINCT FROM auth.uid()::text THEN
    RAISE EXCEPTION 'NOT_ASSIGNED_DRIVER';
  END IF;
  IF p_driver_typed_total_cents IS NULL OR p_driver_typed_total_cents <= 0 THEN
    RAISE EXCEPTION 'INVALID_TOTAL: %', p_driver_typed_total_cents;
  END IF;
  IF p_receipt_photo_url IS NULL OR length(trim(p_receipt_photo_url)) = 0 THEN
    RAISE EXCEPTION 'RECEIPT_URL_REQUIRED';
  END IF;

  -- Calcular bag fee a partir de platform_settings (fallback 10c).
  SELECT COALESCE((value::text)::int, 10) INTO v_bag_unit_cents
    FROM public.platform_settings
   WHERE key = 'bag_fee_supermarket_per_bag_cents';
  v_bag_unit_cents  := COALESCE(v_bag_unit_cents, 10);
  v_bag_fee_cents   := p_bag_count * v_bag_unit_cents;
  -- Delta entre nova bag_fee e a que estava gravada (base: bag_count=1 do create_order).
  v_bag_delta_cents := v_bag_fee_cents - ROUND(COALESCE(v_order.bag_fee, 0.0) * 100)::int;

  UPDATE public.orders SET purchase_flow_version = 2 WHERE id = p_order_id;

  IF v_order.payment_method = 'cash' THEN
    v_reimb_status := 'cash_settled';
  ELSE
    v_reimb_status := 'pending_admin';
  END IF;

  INSERT INTO public.order_receipts_v2 (
    order_id, photo_url, photo_taken_at, driver_typed_total_cents,
    reimbursement_status, reimbursement_amount_cents
  ) VALUES (
    p_order_id, p_receipt_photo_url, now(), p_driver_typed_total_cents,
    v_reimb_status, p_driver_typed_total_cents
  )
  ON CONFLICT (order_id) DO UPDATE
    SET photo_url                  = EXCLUDED.photo_url,
        photo_taken_at             = EXCLUDED.photo_taken_at,
        driver_typed_total_cents   = EXCLUDED.driver_typed_total_cents,
        reimbursement_status       = EXCLUDED.reimbursement_status,
        reimbursement_amount_cents = EXCLUDED.reimbursement_amount_cents;

  IF p_items IS NOT NULL AND jsonb_typeof(p_items) = 'array' THEN
    FOR v_item IN SELECT * FROM jsonb_array_elements(p_items) LOOP
      INSERT INTO public.order_purchase_items_v2 (
        order_id, original_item_id, original_name, original_price_cents,
        original_qty, status, actual_name, actual_price_cents, actual_qty,
        client_confirmed_at, client_confirmation_message_id
      ) VALUES (
        p_order_id,
        NULLIF(v_item->>'original_item_id','')::uuid,
        COALESCE(v_item->>'original_name',''),
        COALESCE((v_item->>'original_price_cents')::integer, 0),
        COALESCE((v_item->>'original_qty')::smallint, 1),
        COALESCE(v_item->>'status','pending'),
        v_item->>'actual_name',
        NULLIF(v_item->>'actual_price_cents','')::integer,
        NULLIF(v_item->>'actual_qty','')::smallint,
        CASE WHEN v_item->>'client_confirmation_message_id' IS NOT NULL THEN now() ELSE NULL END,
        NULLIF(v_item->>'client_confirmation_message_id','')::uuid
      );
      v_total_items := v_total_items + 1;

      IF v_item->>'status' = 'purchased' THEN
        v_purchased_cents := v_purchased_cents +
          (COALESCE((v_item->>'original_price_cents')::integer, 0)
           * COALESCE((v_item->>'original_qty')::integer, 1));
      END IF;
      IF v_item->>'status' = 'unavailable' THEN
        v_unavailable_cents := v_unavailable_cents +
          (COALESCE((v_item->>'original_price_cents')::integer, 0)
           * COALESCE((v_item->>'original_qty')::integer, 1));
      END IF;
      IF v_item->>'status' = 'replaced' THEN
        v_replaced_cents := v_replaced_cents +
          (COALESCE((v_item->>'actual_price_cents')::integer,
                    (v_item->>'original_price_cents')::integer)
           * COALESCE((v_item->>'actual_qty')::integer,
                      (v_item->>'original_qty')::integer));
      END IF;
      IF v_item->>'status' = 'added' THEN
        v_added_cents := v_added_cents +
          (COALESCE((v_item->>'actual_price_cents')::integer, 0)
           * COALESCE((v_item->>'actual_qty')::integer, 1));
      END IF;
    END LOOP;
  END IF;

  v_final_value_cents := v_purchased_cents + v_replaced_cents + v_added_cents;

  IF v_unavailable_cents > 0 THEN
    INSERT INTO public.wallet_transactions (
      user_id, amount_cents, kind, reason, related_order_id, idempotency_key
    ) VALUES (
      v_order.user_id, v_unavailable_cents, 'refund_credit_free',
      'storeshopping_v2_unavailable_items', p_order_id,
      'v2_unavail_' || p_order_id
    )
    ON CONFLICT (idempotency_key) DO NOTHING;
  END IF;

  -- Bypass trigger enforce_financial_immutability (igual a update_bag_count_bypass).
  -- Necessário para alterar bag_count, bag_fee, total, final_total.
  PERFORM set_config('app.financial_bypass', 'true', true);

  IF v_order.payment_method = 'cash' THEN
    UPDATE public.orders SET
      bag_count            = p_bag_count,
      bag_fee              = v_bag_fee_cents / 100.0,
      total                = GREATEST(0, COALESCE(total, 0) + v_bag_delta_cents::numeric / 100),
      final_total          = GREATEST(0, COALESCE(final_total, 0) + v_bag_delta_cents::numeric / 100),
      final_purchase_value = v_final_value_cents / 100.0,
      cash_total_due       = (p_driver_typed_total_cents + v_bag_fee_cents) / 100.0
    WHERE id = p_order_id;
  ELSE
    UPDATE public.orders SET
      bag_count            = p_bag_count,
      bag_fee              = v_bag_fee_cents / 100.0,
      total                = GREATEST(0, COALESCE(total, 0) + v_bag_delta_cents::numeric / 100),
      final_total          = GREATEST(0, COALESCE(final_total, 0) + v_bag_delta_cents::numeric / 100),
      final_purchase_value = v_final_value_cents / 100.0
    WHERE id = p_order_id;
  END IF;

  SELECT decrypted_secret INTO v_url FROM vault.decrypted_secrets WHERE name = 'project_url';
  SELECT decrypted_secret INTO v_key FROM vault.decrypted_secrets WHERE name = 'service_role_key';

  IF v_url IS NOT NULL AND v_url <> '' AND v_key IS NOT NULL AND v_key <> '' THEN
    IF v_order.payment_method IN ('card','stripe','mbway') THEN
      BEGIN
        PERFORM net.http_post(
          url     := v_url || '/functions/v1/notify-admin-reimbursement',
          headers := jsonb_build_object('Authorization','Bearer '||v_key,'Content-Type','application/json'),
          body    := jsonb_build_object('order_id',p_order_id,'driver_id',v_order.assigned_driver_id,'amount_cents',p_driver_typed_total_cents)
        );
      EXCEPTION WHEN OTHERS THEN
        RAISE NOTICE '5G v2: notify-admin-reimbursement failed: %', SQLERRM;
      END;
    END IF;
    BEGIN
      PERFORM net.http_post(
        url     := v_url || '/functions/v1/ocr-receipt',
        headers := jsonb_build_object('Authorization','Bearer '||v_key,'Content-Type','application/json'),
        body    := jsonb_build_object('order_id', p_order_id)
      );
    EXCEPTION WHEN OTHERS THEN
      RAISE NOTICE '5G v2: ocr-receipt failed: %', SQLERRM;
    END;
    BEGIN
      PERFORM net.http_post(
        url     := v_url || '/functions/v1/notify-purchase-finalized',
        headers := jsonb_build_object('Authorization','Bearer '||v_key,'Content-Type','application/json'),
        body    := jsonb_build_object('order_id',p_order_id,'unavailable_credit_cents',v_unavailable_cents)
      );
    EXCEPTION WHEN OTHERS THEN
      RAISE NOTICE '5G v2: notify-purchase-finalized failed: %', SQLERRM;
    END;
  END IF;

  UPDATE public.orders SET status = 'onTheWay' WHERE id = p_order_id;

  RETURN jsonb_build_object(
    'success',                    true,
    'flow_version',               2,
    'items_recorded',             v_total_items,
    'unavailable_credit_cents',   v_unavailable_cents,
    'added_total_cents',          v_added_cents,
    'final_purchase_value_cents', v_final_value_cents,
    'bag_count',                  p_bag_count,
    'bag_fee_cents',              v_bag_fee_cents,
    'reimbursement_status',       v_reimb_status,
    'payment_method',             v_order.payment_method
  );
END;
$fn$;

REVOKE ALL ON FUNCTION public.finalize_storeshopping_purchase_v2(text, integer, text, jsonb, integer) FROM public, anon;
GRANT EXECUTE ON FUNCTION public.finalize_storeshopping_purchase_v2(text, integer, text, jsonb, integer) TO authenticated;

COMMENT ON FUNCTION public.finalize_storeshopping_purchase_v2(text, integer, text, jsonb, integer) IS
  'BUG-SACOS-V2 (2026-05-17): adiciona p_bag_count. Actualiza bag_count/bag_fee/total/final_total/cash_total_due com bypass financeiro. cash_total_due (cash) = talão + sacos.';
