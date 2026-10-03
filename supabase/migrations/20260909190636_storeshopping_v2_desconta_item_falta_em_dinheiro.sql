CREATE OR REPLACE FUNCTION public.finalize_storeshopping_purchase_v2(p_order_id text, p_driver_typed_total_cents integer, p_receipt_photo_url text, p_items jsonb, p_bag_count integer DEFAULT 1)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'net', 'auth'
AS $function$
DECLARE
  v_order               RECORD;
  v_item                jsonb;
  v_unavailable_cents   integer := 0;
  v_added_cents         integer := 0;
  v_purchased_cents     integer := 0;
  v_replaced_cents      integer := 0;
  v_replaced_orig_cents integer := 0;
  v_items_delta_cents   integer := 0;
  v_final_value_cents   integer := 0;
  v_reimb_status        text;
  v_url                 text;
  v_key                 text;
  v_total_items         integer := 0;
  v_bag_unit_cents      integer := 10;
  v_bag_fee_cents       integer;
  v_bag_delta_cents     integer;
  v_order_final_total   integer;
  v_is_cash             boolean;
BEGIN
  IF auth.uid() IS NULL THEN RAISE EXCEPTION 'UNAUTHENTICATED'; END IF;

  IF p_bag_count < 0 OR p_bag_count > 99 THEN
    RAISE EXCEPTION 'INVALID_BAG_COUNT: % (allowed 0..99)', p_bag_count;
  END IF;

  SELECT id, user_id, assigned_driver_id, service_type, is_partner_store,
         payment_method, bag_fee, current_driver_offer_id,
         final_total, total, delivery_fee, service_fee
    INTO v_order FROM public.orders WHERE id = p_order_id;

  IF NOT FOUND THEN RAISE EXCEPTION 'ORDER_NOT_FOUND: %', p_order_id; END IF;
  IF v_order.service_type IS DISTINCT FROM 'storeShopping' THEN
    RAISE EXCEPTION 'WRONG_SERVICE_TYPE: %', v_order.service_type;
  END IF;
  IF COALESCE(v_order.is_partner_store, false) THEN
    RAISE EXCEPTION 'PARTNER_STORE_USE_V1';
  END IF;
  IF v_order.assigned_driver_id IS DISTINCT FROM auth.uid()::text
     AND v_order.current_driver_offer_id IS DISTINCT FROM auth.uid()::text THEN
    RAISE EXCEPTION 'NOT_ASSIGNED_DRIVER';
  END IF;
  IF p_driver_typed_total_cents IS NULL OR p_driver_typed_total_cents <= 0 THEN
    RAISE EXCEPTION 'INVALID_TOTAL: %', p_driver_typed_total_cents;
  END IF;
  IF p_receipt_photo_url IS NULL OR length(trim(p_receipt_photo_url)) = 0 THEN
    RAISE EXCEPTION 'RECEIPT_URL_REQUIRED';
  END IF;

  v_is_cash := (v_order.payment_method = 'cash');

  SELECT COALESCE((value::text)::int, 10) INTO v_bag_unit_cents
    FROM public.platform_settings WHERE key = 'bag_fee_supermarket_per_bag_cents';
  v_bag_unit_cents  := COALESCE(v_bag_unit_cents, 10);
  v_bag_fee_cents   := p_bag_count * v_bag_unit_cents;
  v_bag_delta_cents := v_bag_fee_cents - ROUND(COALESCE(v_order.bag_fee, 0.0) * 100)::int;

  UPDATE public.orders SET purchase_flow_version = 2 WHERE id = p_order_id;

  IF v_is_cash THEN
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
    SET photo_url = EXCLUDED.photo_url, photo_taken_at = EXCLUDED.photo_taken_at,
        driver_typed_total_cents = EXCLUDED.driver_typed_total_cents,
        reimbursement_status = EXCLUDED.reimbursement_status,
        reimbursement_amount_cents = EXCLUDED.reimbursement_amount_cents;

  IF p_items IS NOT NULL AND jsonb_typeof(p_items) = 'array' THEN
    FOR v_item IN SELECT * FROM jsonb_array_elements(p_items) LOOP
      INSERT INTO public.order_purchase_items_v2 (
        order_id, original_item_id, original_name, original_price_cents,
        original_qty, status, actual_name, actual_price_cents, actual_qty,
        client_confirmed_at, client_confirmation_message_id
      ) VALUES (
        p_order_id,
        CASE WHEN NULLIF(v_item->>'original_item_id','') ~ '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
          THEN (v_item->>'original_item_id')::uuid ELSE NULL END,
        COALESCE(v_item->>'original_name',''),
        COALESCE((v_item->>'original_price_cents')::integer, 0),
        COALESCE((v_item->>'original_qty')::smallint, 1),
        COALESCE(v_item->>'status','pending'),
        v_item->>'actual_name',
        NULLIF(v_item->>'actual_price_cents','')::integer,
        NULLIF(v_item->>'actual_qty','')::smallint,
        CASE WHEN v_item->>'client_confirmation_message_id' IS NOT NULL THEN now() ELSE NULL END,
        CASE WHEN NULLIF(v_item->>'client_confirmation_message_id','') ~ '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
          THEN (v_item->>'client_confirmation_message_id')::uuid ELSE NULL END
      );
      v_total_items := v_total_items + 1;
      IF v_item->>'status' = 'purchased' THEN
        v_purchased_cents := v_purchased_cents + (COALESCE((v_item->>'original_price_cents')::integer,0) * COALESCE((v_item->>'original_qty')::integer,1));
      END IF;
      IF v_item->>'status' = 'unavailable' THEN
        v_unavailable_cents := v_unavailable_cents + (COALESCE((v_item->>'original_price_cents')::integer,0) * COALESCE((v_item->>'original_qty')::integer,1));
      END IF;
      IF v_item->>'status' = 'replaced' THEN
        v_replaced_cents := v_replaced_cents + (COALESCE((v_item->>'actual_price_cents')::integer,(v_item->>'original_price_cents')::integer) * COALESCE((v_item->>'actual_qty')::integer,(v_item->>'original_qty')::integer));
        v_replaced_orig_cents := v_replaced_orig_cents + (COALESCE((v_item->>'original_price_cents')::integer,0) * COALESCE((v_item->>'original_qty')::integer,1));
      END IF;
      IF v_item->>'status' = 'added' THEN
        v_added_cents := v_added_cents + (COALESCE((v_item->>'actual_price_cents')::integer,0) * COALESCE((v_item->>'actual_qty')::integer,1));
      END IF;
    END LOOP;
  END IF;

  v_final_value_cents := v_purchased_cents + v_replaced_cents + v_added_cents;

  -- FIX 2026-09-09 (caso Cristina/Continente): o que o cliente paga tem de reflectir
  -- o que ele REALMENTE recebeu. Item em falta desconta, item trocado ajusta a
  -- diferenca, item acrescentado soma. Robusto quer a app envie todos os itens
  -- quer envie so os alterados.
  v_items_delta_cents := v_added_cents
                       + (v_replaced_cents - v_replaced_orig_cents)
                       - v_unavailable_cents;

  v_order_final_total := ROUND(COALESCE(v_order.final_total, v_order.total, 0) * 100)::int
                        + v_bag_delta_cents;

  IF v_is_cash THEN
    -- DINHEIRO: desconta na hora do valor a cobrar. Nao credita carteira.
    v_order_final_total := v_order_final_total + v_items_delta_cents;
  ELSE
    -- CARTAO/MBWAY: o cliente ja pagou. Item em falta volta como saldo na carteira.
    IF v_unavailable_cents > 0 THEN
      INSERT INTO public.wallet_transactions (user_id, amount_cents, kind, reason, related_order_id, idempotency_key)
      VALUES (v_order.user_id, v_unavailable_cents, 'refund_credit_free', 'storeshopping_v2_unavailable_items', p_order_id, 'v2_unavail_' || p_order_id)
      ON CONFLICT (idempotency_key) DO NOTHING;
    END IF;
  END IF;

  PERFORM set_config('app.financial_bypass', 'true', true);

  IF v_is_cash THEN
    UPDATE public.orders SET
      bag_count = p_bag_count,
      bag_fee = v_bag_fee_cents / 100.0,
      final_total = GREATEST(0, v_order_final_total) / 100.0,
      final_purchase_value = v_final_value_cents / 100.0,
      cash_total_due = GREATEST(0, v_order_final_total) / 100.0,
      is_purchase_finalized = true
    WHERE id = p_order_id;
  ELSE
    UPDATE public.orders SET
      bag_count = p_bag_count,
      bag_fee = v_bag_fee_cents / 100.0,
      final_total = GREATEST(0, COALESCE(final_total, 0) + v_bag_delta_cents::numeric / 100),
      final_purchase_value = v_final_value_cents / 100.0,
      is_purchase_finalized = true
    WHERE id = p_order_id;
  END IF;

  SELECT decrypted_secret INTO v_url FROM vault.decrypted_secrets WHERE name = 'project_url';
  SELECT decrypted_secret INTO v_key FROM vault.decrypted_secrets WHERE name = 'service_role_key';

  IF v_url IS NOT NULL AND v_url <> '' AND v_key IS NOT NULL AND v_key <> '' THEN
    IF v_order.payment_method IN ('card','stripe','mbway') THEN
      BEGIN
        PERFORM net.http_post(url := v_url || '/functions/v1/notify-admin-reimbursement',
          headers := jsonb_build_object('Authorization','Bearer '||v_key,'Content-Type','application/json'),
          body := jsonb_build_object('order_id',p_order_id,'driver_id',v_order.assigned_driver_id,'amount_cents',p_driver_typed_total_cents));
      EXCEPTION WHEN OTHERS THEN RAISE NOTICE 'notify-admin-reimbursement failed: %', SQLERRM; END;
    END IF;
    BEGIN
      PERFORM net.http_post(url := v_url || '/functions/v1/ocr-receipt',
        headers := jsonb_build_object('Authorization','Bearer '||v_key,'Content-Type','application/json'),
        body := jsonb_build_object('order_id', p_order_id));
    EXCEPTION WHEN OTHERS THEN RAISE NOTICE 'ocr-receipt failed: %', SQLERRM; END;
    BEGIN
      PERFORM net.http_post(url := v_url || '/functions/v1/notify-purchase-finalized',
        headers := jsonb_build_object('Authorization','Bearer '||v_key,'Content-Type','application/json'),
        body := jsonb_build_object('order_id',p_order_id,'unavailable_credit_cents',v_unavailable_cents,'payment_method',v_order.payment_method));
    EXCEPTION WHEN OTHERS THEN RAISE NOTICE 'notify-purchase-finalized failed: %', SQLERRM; END;
  END IF;

  UPDATE public.orders SET status = 'onTheWay' WHERE id = p_order_id;

  RETURN jsonb_build_object(
    'success', true, 'flow_version', 2, 'items_recorded', v_total_items,
    'unavailable_credit_cents', CASE WHEN v_is_cash THEN 0 ELSE v_unavailable_cents END,
    'unavailable_discount_cents', CASE WHEN v_is_cash THEN v_unavailable_cents ELSE 0 END,
    'items_delta_cents', CASE WHEN v_is_cash THEN v_items_delta_cents ELSE 0 END,
    'added_total_cents', v_added_cents,
    'final_purchase_value_cents', v_final_value_cents, 'bag_count', p_bag_count,
    'bag_fee_cents', v_bag_fee_cents, 'reimbursement_status', v_reimb_status,
    'payment_method', v_order.payment_method,
    'cash_total_due_cents', GREATEST(0, v_order_final_total)
  );
END;
$function$;