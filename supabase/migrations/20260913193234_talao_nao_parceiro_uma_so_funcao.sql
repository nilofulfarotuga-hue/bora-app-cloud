-- 2026-09-13 -- TALAO DO NAO-PARCEIRO NUMA SO FUNCAO (prioridade 1 do Danilo).
--
-- Sintoma (10/09, McDonald's, dez tentativas; 09/09, Continente, so a terceira):
-- o estafeta tira a foto do talao, escreve o valor, carrega em confirmar e o
-- ecra volta ao mesmo sitio sem dizer porque. Causa: para restaurantes
-- nao-parceiros a app gravava o talao numa funcao (registar_talao_nao_parceiro)
-- e a seguir chamava a funcao v1 dos mercados, que ou recusava o pedido ou
-- batia na imutabilidade financeira -- e o erro era engolido pela app.
--
-- Regras (todas obrigatorias, ordem de 10/09):
--   * vale para TODO o nao-parceiro (mercado, restaurante, loja, farmacia) e
--     para TODOS os meios de pagamento (dinheiro, cartao, MB Way);
--   * uma so funcao SECURITY DEFINER faz tudo: guarda o talao em
--     order_receipts_v2 (foto no bucket privado 'receipts'), actualiza os totais
--     com o bypass financeiro por dentro, deixa o acerto do estafeta pelo talao
--     (dinheiro: cash_settled; cartao/MB Way: pending_admin) e avanca o pedido
--     para onTheWay;
--   * a app deixa de escrever em colunas financeiras;
--   * o erro real chega ao ecra (codigo em maiusculas na mensagem) e a app
--     regista-o em order_lifecycle_errors (funcao registar_erro_ciclo_pedido).
--
-- Dinheiro: as regras sao EXACTAMENTE as que ja valiam nos mercados desde 09/09
-- (funcao v2): o cliente paga os precos da app; item em falta desconta
-- (dinheiro) ou volta a carteira (cartao/MB Way); item trocado ajusta a
-- diferenca; item acrescentado soma; saco de mercado ao preco de
-- bag_fee_supermarket_per_bag_cents por saco. Restaurante nao-parceiro mantem o
-- saco cobrado no checkout (0,30 EUR fixos) -- nao muda aqui, e por isso a
-- funcao v2 dos mercados nao servia (cobrava 0,10 EUR/saco a restaurantes).
-- O cliente NUNCA ve o talao real nem os precos da loja (regra de 09/09).

CREATE OR REPLACE FUNCTION public.registar_erro_ciclo_pedido(p_order_id text, p_component text, p_error_message text, p_context jsonb DEFAULT '{}'::jsonb)
 RETURNS bigint
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'auth'
AS $function$
DECLARE v_id bigint;
BEGIN
  IF auth.uid() IS NULL THEN RAISE EXCEPTION 'UNAUTHENTICATED'; END IF;
  IF p_order_id IS NOT NULL AND NOT EXISTS (SELECT 1 FROM public.orders WHERE id = p_order_id) THEN
    p_order_id := NULL;
  END IF;
  INSERT INTO public.order_lifecycle_errors (order_id, component, error_message, context)
  VALUES (p_order_id, left(COALESCE(p_component, 'app'), 120), left(COALESCE(p_error_message, '?'), 2000),
          COALESCE(p_context, '{}'::jsonb) || jsonb_build_object('reported_by', auth.uid()))
  RETURNING id INTO v_id;
  RETURN v_id;
END;
$function$;
REVOKE ALL ON FUNCTION public.registar_erro_ciclo_pedido(text, text, text, jsonb) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.registar_erro_ciclo_pedido(text, text, text, jsonb) TO authenticated;

CREATE OR REPLACE FUNCTION public.finalizar_talao_nao_parceiro(p_order_id text, p_receipt_photo_url text, p_driver_typed_total_cents integer, p_items jsonb DEFAULT NULL::jsonb, p_bag_count integer DEFAULT NULL::integer)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'net', 'auth'
AS $function$
DECLARE
  v_uid                 uuid := auth.uid();
  v_order               RECORD;
  v_loja_parceira       boolean;
  v_is_mine             boolean;
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
  v_bag_count           integer;
  v_bag_fee_cents       integer;
  v_bag_delta_cents     integer := 0;
  v_order_final_total   integer;
  v_is_cash             boolean;
  v_is_restaurant       boolean;
  v_already             boolean;
  v_rows                integer;
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'UNAUTHENTICATED'; END IF;

  SELECT id, user_id, assigned_driver_id, current_driver_offer_id, service_type,
         is_partner_store, restaurant_id, payment_method, bag_fee, bag_count,
         final_total, total, status, is_purchase_finalized
    INTO v_order FROM public.orders WHERE id = p_order_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'ORDER_NOT_FOUND: %', p_order_id; END IF;

  SELECT r.is_partner INTO v_loja_parceira
    FROM public.restaurants r WHERE r.id = v_order.restaurant_id;
  v_loja_parceira := COALESCE(v_loja_parceira, v_order.is_partner_store, false);
  IF v_loja_parceira THEN RAISE EXCEPTION 'PARTNER_STORE_NO_RECEIPT'; END IF;

  IF v_order.service_type NOT IN ('restaurant', 'storeShopping') THEN
    RAISE EXCEPTION 'WRONG_SERVICE_TYPE: %', v_order.service_type;
  END IF;
  v_is_restaurant := (v_order.service_type = 'restaurant');

  v_is_mine := v_order.assigned_driver_id = v_uid::text
    OR v_order.current_driver_offer_id = v_uid::text
    OR EXISTS (SELECT 1 FROM public.drivers d
                WHERE d.user_id = v_uid AND d.id::text = v_order.assigned_driver_id);
  IF NOT COALESCE(v_is_mine, false) THEN RAISE EXCEPTION 'NOT_ASSIGNED_DRIVER'; END IF;

  IF v_order.status IN ('delivered', 'cancelled', 'rejected') THEN
    RAISE EXCEPTION 'INVALID_STATUS: %', v_order.status;
  END IF;
  IF v_order.status NOT IN ('driverAccepted', 'pickedUp', 'onTheWay') THEN
    RAISE EXCEPTION 'INVALID_STATUS: %', v_order.status;
  END IF;

  IF p_driver_typed_total_cents IS NULL OR p_driver_typed_total_cents <= 0 THEN
    RAISE EXCEPTION 'INVALID_TOTAL: %', p_driver_typed_total_cents;
  END IF;
  IF p_receipt_photo_url IS NULL OR length(trim(p_receipt_photo_url)) = 0 THEN
    RAISE EXCEPTION 'RECEIPT_URL_REQUIRED';
  END IF;
  IF p_bag_count IS NOT NULL AND (p_bag_count < 0 OR p_bag_count > 99) THEN
    RAISE EXCEPTION 'INVALID_BAG_COUNT: % (allowed 0..99)', p_bag_count;
  END IF;

  v_is_cash := (v_order.payment_method = 'cash');
  v_already := COALESCE(v_order.is_purchase_finalized, false);
  v_reimb_status := CASE WHEN v_is_cash THEN 'cash_settled' ELSE 'pending_admin' END;

  -- 1) O talao (foto + valor escrito). Idempotente: repetir substitui.
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
        reimbursement_amount_cents = EXCLUDED.reimbursement_amount_cents,
        reimbursement_status       = CASE WHEN public.order_receipts_v2.reimbursement_status IN ('admin_paid','rejected')
                                          THEN public.order_receipts_v2.reimbursement_status
                                          ELSE EXCLUDED.reimbursement_status END;

  PERFORM set_config('app.financial_bypass', 'true', true);

  IF v_already THEN
    -- Ja finalizada antes (segunda tentativa): so o talao e o valor pago na loja
    -- mudam. Os deltas de itens e sacos NAO se aplicam duas vezes.
    UPDATE public.orders
       SET final_purchase_value = p_driver_typed_total_cents / 100.0,
           purchase_flow_version = 2
     WHERE id = p_order_id;
  ELSE
    -- 2) Sacos: mercado paga por saco (definicao); restaurante mantem o do checkout.
    IF v_is_restaurant THEN
      v_bag_count     := COALESCE(v_order.bag_count, 1);
      v_bag_fee_cents := ROUND(COALESCE(v_order.bag_fee, 0.0) * 100)::int;
      v_bag_delta_cents := 0;
    ELSE
      SELECT COALESCE((value::text)::int, 10) INTO v_bag_unit_cents
        FROM public.platform_settings WHERE key = 'bag_fee_supermarket_per_bag_cents';
      v_bag_unit_cents  := COALESCE(v_bag_unit_cents, 10);
      v_bag_count       := COALESCE(p_bag_count, GREATEST(1, COALESCE(v_order.bag_count, 1)));
      v_bag_fee_cents   := v_bag_count * v_bag_unit_cents;
      v_bag_delta_cents := v_bag_fee_cents - ROUND(COALESCE(v_order.bag_fee, 0.0) * 100)::int;
    END IF;

    -- 3) Itens (mesma regra dos mercados desde 09/09).
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
      v_final_value_cents := v_purchased_cents + v_replaced_cents + v_added_cents;
    ELSE
      -- Sem lista de itens: o valor final da compra e' o do talao.
      v_final_value_cents := p_driver_typed_total_cents;
    END IF;

    v_items_delta_cents := v_added_cents
                         + (v_replaced_cents - v_replaced_orig_cents)
                         - v_unavailable_cents;

    v_order_final_total := ROUND(COALESCE(v_order.final_total, v_order.total, 0) * 100)::int
                          + v_bag_delta_cents;

    IF v_is_cash THEN
      -- DINHEIRO: desconta na hora do valor a cobrar. Nao credita carteira.
      v_order_final_total := v_order_final_total + v_items_delta_cents;
    ELSE
      -- CARTAO/MB WAY: o cliente ja pagou. Item em falta volta como saldo na carteira.
      IF v_unavailable_cents > 0 THEN
        INSERT INTO public.wallet_transactions (user_id, amount_cents, kind, reason, related_order_id, idempotency_key)
        VALUES (v_order.user_id, v_unavailable_cents, 'refund_credit_free', 'storeshopping_v2_unavailable_items', p_order_id, 'v2_unavail_' || p_order_id)
        ON CONFLICT (idempotency_key) DO NOTHING;
      END IF;
    END IF;

    -- 4) Totais do pedido (bypass financeiro so aqui dentro).
    IF v_is_cash THEN
      UPDATE public.orders SET
        bag_count = v_bag_count,
        bag_fee = v_bag_fee_cents / 100.0,
        final_total = GREATEST(0, v_order_final_total) / 100.0,
        final_purchase_value = v_final_value_cents / 100.0,
        cash_total_due = GREATEST(0, v_order_final_total) / 100.0,
        is_purchase_finalized = true,
        purchase_flow_version = 2
      WHERE id = p_order_id;
    ELSE
      UPDATE public.orders SET
        bag_count = v_bag_count,
        bag_fee = v_bag_fee_cents / 100.0,
        final_total = GREATEST(0, COALESCE(final_total, 0) + v_bag_delta_cents::numeric / 100),
        final_purchase_value = v_final_value_cents / 100.0,
        is_purchase_finalized = true,
        purchase_flow_version = 2
      WHERE id = p_order_id;
    END IF;
  END IF;

  -- 5) Robots: reembolso ao admin (cartao/MB Way), OCR do talao, aviso ao cliente.
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
    IF NOT v_already THEN
      BEGIN
        PERFORM net.http_post(url := v_url || '/functions/v1/notify-purchase-finalized',
          headers := jsonb_build_object('Authorization','Bearer '||v_key,'Content-Type','application/json'),
          body := jsonb_build_object('order_id',p_order_id,'unavailable_credit_cents',v_unavailable_cents,'payment_method',v_order.payment_method));
      EXCEPTION WHEN OTHERS THEN RAISE NOTICE 'notify-purchase-finalized failed: %', SQLERRM; END;
    END IF;
  END IF;

  -- 6) Segue direto para a entrega.
  PERFORM set_config('app.order_transition_source', 'finalizar_talao_nao_parceiro', true);
  UPDATE public.orders SET status = 'onTheWay'
   WHERE id = p_order_id AND status IN ('driverAccepted', 'pickedUp');
  GET DIAGNOSTICS v_rows = ROW_COUNT;

  RETURN jsonb_build_object(
    'ok', true, 'success', true, 'status', 'onTheWay', 'flow_version', 2,
    'idempotent', v_already, 'status_changed', (v_rows = 1),
    'items_recorded', v_total_items,
    'unavailable_credit_cents', CASE WHEN v_is_cash THEN 0 ELSE v_unavailable_cents END,
    'unavailable_discount_cents', CASE WHEN v_is_cash THEN v_unavailable_cents ELSE 0 END,
    'items_delta_cents', CASE WHEN v_is_cash THEN v_items_delta_cents ELSE 0 END,
    'added_total_cents', v_added_cents,
    'final_purchase_value_cents', v_final_value_cents,
    'bag_count', v_bag_count, 'bag_fee_cents', v_bag_fee_cents,
    'reimbursement_status', v_reimb_status,
    'payment_method', v_order.payment_method,
    'cash_total_due_cents', GREATEST(0, COALESCE(v_order_final_total, ROUND(COALESCE(v_order.final_total, v_order.total, 0) * 100)::int))
  );
END;
$function$;
REVOKE ALL ON FUNCTION public.finalizar_talao_nao_parceiro(text, text, integer, jsonb, integer) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.finalizar_talao_nao_parceiro(text, text, integer, jsonb, integer) TO authenticated;
