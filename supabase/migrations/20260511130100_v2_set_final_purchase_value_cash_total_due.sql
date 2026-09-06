-- ═══════════════════════════════════════════════════════════════════════════
-- BUG 15+12 (sessão 17-bugs 2026-05-11) — RPC v2 também actualiza
-- orders.final_purchase_value (sempre) + orders.cash_total_due (só CASH).
--
-- Acrescenta tracking: v_purchased_cents + v_replaced_cents + v_added_cents
-- → final_purchase_value (eur). cash_total_due = driver_typed_total / 100.
-- ═══════════════════════════════════════════════════════════════════════════

CREATE OR REPLACE FUNCTION public.finalize_storeshopping_purchase_v2(
  p_order_id                  text,
  p_driver_typed_total_cents  integer,
  p_receipt_photo_url         text,
  p_items                     jsonb
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, net, auth
AS $fn$
DECLARE
  v_order             RECORD;
  v_item              jsonb;
  v_unavailable_cents integer := 0;
  v_added_cents       integer := 0;
  v_purchased_cents   integer := 0;
  v_replaced_cents    integer := 0;
  v_final_value_cents integer := 0;
  v_reimb_status      text;
  v_url               text;
  v_key               text;
  v_total_items       integer := 0;
BEGIN
  IF auth.uid() IS NULL THEN RAISE EXCEPTION 'UNAUTHENTICATED'; END IF;

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
    SET photo_url                = EXCLUDED.photo_url,
        photo_taken_at           = EXCLUDED.photo_taken_at,
        driver_typed_total_cents = EXCLUDED.driver_typed_total_cents,
        reimbursement_status     = EXCLUDED.reimbursement_status,
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

  IF v_order.payment_method = 'cash' THEN
    UPDATE public.orders
       SET final_purchase_value = v_final_value_cents / 100.0,
           cash_total_due = p_driver_typed_total_cents / 100.0
     WHERE id = p_order_id;
  ELSE
    UPDATE public.orders
       SET final_purchase_value = v_final_value_cents / 100.0
     WHERE id = p_order_id;
  END IF;

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

  SELECT decrypted_secret INTO v_url FROM vault.decrypted_secrets WHERE name = 'project_url';
  SELECT decrypted_secret INTO v_key FROM vault.decrypted_secrets WHERE name = 'service_role_key';

  IF v_url IS NOT NULL AND v_url <> '' AND v_key IS NOT NULL AND v_key <> '' THEN
    IF v_order.payment_method IN ('card','stripe','mbway') THEN
      BEGIN
        PERFORM net.http_post(
          url := v_url || '/functions/v1/notify-admin-reimbursement',
          headers := jsonb_build_object('Authorization','Bearer '||v_key,'Content-Type','application/json'),
          body := jsonb_build_object('order_id',p_order_id,'driver_id',v_order.assigned_driver_id,'amount_cents',p_driver_typed_total_cents)
        );
      EXCEPTION WHEN OTHERS THEN
        RAISE NOTICE '5G v2: notify-admin-reimbursement failed: %', SQLERRM;
      END;
    END IF;
    BEGIN
      PERFORM net.http_post(
        url := v_url || '/functions/v1/ocr-receipt',
        headers := jsonb_build_object('Authorization','Bearer '||v_key,'Content-Type','application/json'),
        body := jsonb_build_object('order_id', p_order_id)
      );
    EXCEPTION WHEN OTHERS THEN
      RAISE NOTICE '5G v2: ocr-receipt failed: %', SQLERRM;
    END;
    BEGIN
      PERFORM net.http_post(
        url := v_url || '/functions/v1/notify-purchase-finalized',
        headers := jsonb_build_object('Authorization','Bearer '||v_key,'Content-Type','application/json'),
        body := jsonb_build_object('order_id',p_order_id,'unavailable_credit_cents',v_unavailable_cents)
      );
    EXCEPTION WHEN OTHERS THEN
      RAISE NOTICE '5G v2: notify-purchase-finalized failed: %', SQLERRM;
    END;
  END IF;

  UPDATE public.orders SET status = 'onTheWay' WHERE id = p_order_id;

  RETURN jsonb_build_object(
    'success', true,
    'flow_version', 2,
    'items_recorded', v_total_items,
    'unavailable_credit_cents', v_unavailable_cents,
    'added_total_cents', v_added_cents,
    'final_purchase_value_cents', v_final_value_cents,
    'reimbursement_status', v_reimb_status,
    'payment_method', v_order.payment_method
  );
END;
$fn$;

COMMENT ON FUNCTION public.finalize_storeshopping_purchase_v2(text, integer, text, jsonb) IS
  '5G v2 (BUG 15+12 fix 2026-05-11): adiciona UPDATE orders.final_purchase_value (sempre) + cash_total_due (CASH only). v1 INTACTA.';
