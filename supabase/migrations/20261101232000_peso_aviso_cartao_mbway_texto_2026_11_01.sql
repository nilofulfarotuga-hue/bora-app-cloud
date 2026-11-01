-- Missão app-fechar-2026-11-01 · B2 peso ao quilo, achado P2
-- (docs/propostas/revisao-casa-peso-convidado-2026-11-01.md): o aviso ao cliente dizia "Novo total: X"
-- também com cartão/MB Way, onde a Bora assume a diferença (weight_adjust_card_charge_enabled=false)
-- ou a devolve à carteira. Só muda o TEXTO do aviso; contas, limites e gravação ficam iguais.

CREATE OR REPLACE FUNCTION public.estafeta_ajustar_peso(p_order_id text, p_product_id text, p_real_base_cents integer)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'net', 'auth'
AS $function$
DECLARE
  v_uid          uuid := auth.uid();
  v_order        RECORD;
  v_parceira     boolean;
  v_is_mine      boolean;
  v_enabled      boolean;
  v_max_pct      numeric;
  v_item         jsonb;
  v_found        boolean := false;
  v_qty          integer;
  v_price        numeric;
  v_base         numeric;
  v_name         text;
  v_vw           boolean;
  v_est_client   integer;
  v_est_base     integer;
  v_new_client   integer;
  v_delta        integer;
  v_prev_delta   integer;
  v_min          integer;
  v_max          integer;
  v_total_delta  integer;
  v_novo_total   integer;
  v_title        text;
  v_body         text;
  v_url          text;
  v_key          text;
  v_avisado      boolean := false;
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'UNAUTHENTICATED'; END IF;

  SELECT COALESCE((SELECT (value #>> '{}')::boolean FROM public.platform_settings WHERE key = 'weight_adjust_enabled'), false)
    INTO v_enabled;
  IF NOT COALESCE(v_enabled, false) THEN
    RETURN jsonb_build_object('ok', false, 'erro', 'desligado');
  END IF;
  SELECT COALESCE((SELECT (value #>> '{}')::numeric FROM public.platform_settings WHERE key = 'weight_adjust_max_pct'), 0.30)
    INTO v_max_pct;
  IF v_max_pct IS NULL OR v_max_pct <= 0 OR v_max_pct >= 1 THEN v_max_pct := 0.30; END IF;

  SELECT id, user_id, assigned_driver_id, current_driver_offer_id, service_type,
         is_partner_store, restaurant_id, payment_method, status, is_purchase_finalized,
         items, total, final_total
    INTO v_order FROM public.orders WHERE id = p_order_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'ORDER_NOT_FOUND: %', p_order_id; END IF;

  SELECT r.is_partner INTO v_parceira FROM public.restaurants r WHERE r.id = v_order.restaurant_id;
  IF COALESCE(v_parceira, v_order.is_partner_store, false) THEN
    RETURN jsonb_build_object('ok', false, 'erro', 'loja_parceira');
  END IF;
  IF v_order.service_type NOT IN ('restaurant', 'storeShopping') THEN
    RETURN jsonb_build_object('ok', false, 'erro', 'tipo_de_pedido');
  END IF;

  v_is_mine := v_order.assigned_driver_id = v_uid::text
    OR v_order.current_driver_offer_id = v_uid::text
    OR EXISTS (SELECT 1 FROM public.drivers d WHERE d.user_id = v_uid AND d.id::text = v_order.assigned_driver_id)
    OR public.is_admin();
  IF NOT COALESCE(v_is_mine, false) THEN RAISE EXCEPTION 'NOT_ASSIGNED_DRIVER'; END IF;

  IF v_order.status NOT IN ('driverAccepted', 'pickedUp') OR COALESCE(v_order.is_purchase_finalized, false) THEN
    RETURN jsonb_build_object('ok', false, 'erro', 'compra_ja_fechada');
  END IF;

  SELECT p.variable_weight, p.name INTO v_vw, v_name FROM public.products p WHERE p.id = p_product_id;
  IF NOT COALESCE(v_vw, false) THEN
    RETURN jsonb_build_object('ok', false, 'erro', 'produto_sem_peso_variavel');
  END IF;

  FOR v_item IN SELECT * FROM jsonb_array_elements(COALESCE(v_order.items, '[]'::jsonb)) LOOP
    IF v_item->>'productId' = p_product_id THEN
      v_found := true;
      v_qty   := GREATEST(1, ROUND(COALESCE(NULLIF(v_item->>'quantity', '')::numeric, 1))::int);
      v_price := COALESCE(NULLIF(v_item->>'price', '')::numeric, 0);
      v_base  := COALESCE(NULLIF(v_item->>'basePrice', '')::numeric, v_price);
      v_name  := COALESCE(NULLIF(v_item->>'name', ''), v_name);
      EXIT;
    END IF;
  END LOOP;
  IF NOT v_found THEN
    RETURN jsonb_build_object('ok', false, 'erro', 'produto_fora_do_pedido');
  END IF;

  v_est_client := ROUND(v_price * v_qty * 100)::int;
  v_est_base   := ROUND(v_base  * v_qty * 100)::int;
  IF v_est_client <= 0 OR v_est_base <= 0 THEN
    RETURN jsonb_build_object('ok', false, 'erro', 'preco_estimado_invalido');
  END IF;
  IF p_real_base_cents IS NULL OR p_real_base_cents <= 0 THEN
    RETURN jsonb_build_object('ok', false, 'erro', 'valor_invalido');
  END IF;

  v_min := CEIL(v_est_base * (1 - v_max_pct))::int;
  v_max := FLOOR(v_est_base * (1 + v_max_pct))::int;
  IF p_real_base_cents < v_min OR p_real_base_cents > v_max THEN
    RETURN jsonb_build_object('ok', false, 'erro', 'fora_do_limite',
      'estimado_caixa_cents', v_est_base, 'minimo_cents', v_min, 'maximo_cents', v_max);
  END IF;

  -- Mesma margem que a linha já tinha na app (paridade Glovo incluída).
  v_new_client := ROUND(p_real_base_cents::numeric * v_est_client / v_est_base)::int;
  v_delta      := v_new_client - v_est_client;

  SELECT a.delta_client_cents INTO v_prev_delta
    FROM public.order_weight_adjustments a
   WHERE a.order_id = p_order_id AND a.product_id = p_product_id;

  INSERT INTO public.order_weight_adjustments (
    order_id, product_id, item_name, qty, est_base_cents, real_base_cents,
    est_client_cents, new_client_cents, delta_client_cents, driver_user_id, payment_method)
  VALUES (
    p_order_id, p_product_id, v_name, v_qty, v_est_base, p_real_base_cents,
    v_est_client, v_new_client, v_delta, v_uid, v_order.payment_method)
  ON CONFLICT (order_id, product_id) DO UPDATE SET
    real_base_cents    = EXCLUDED.real_base_cents,
    new_client_cents   = EXCLUDED.new_client_cents,
    delta_client_cents = EXCLUDED.delta_client_cents,
    driver_user_id     = EXCLUDED.driver_user_id,
    updated_at         = now();

  SELECT COALESCE(SUM(a.delta_client_cents), 0)::int INTO v_total_delta
    FROM public.order_weight_adjustments a WHERE a.order_id = p_order_id;
  v_novo_total := ROUND(COALESCE(v_order.final_total, v_order.total, 0) * 100)::int + v_total_delta;

  -- Aviso ao cliente (sino da app + push). Só quando o valor muda. Nunca aborta o ajuste.
  IF v_delta <> 0 OR (v_prev_delta IS NOT NULL AND v_prev_delta <> v_delta) THEN
    v_title := 'Preço ajustado ao peso';
    IF lower(COALESCE(v_order.payment_method, 'cash')) IN ('cash', 'dinheiro') THEN
      IF v_delta = 0 THEN
        v_body := format('%s: voltou ao preço previsto, %s. Novo total: %s.',
                         v_name, public._euros_pt(v_new_client), public._euros_pt(v_novo_total));
      ELSE
        v_body := format('%s: passou de %s para %s (peso real). Novo total: %s.',
                         v_name, public._euros_pt(v_est_client), public._euros_pt(v_new_client), public._euros_pt(v_novo_total));
      END IF;
    ELSE
      -- P2 (01/11/2026): cartão/MB Way. O talão não cobra mais ao cliente enquanto
      -- weight_adjust_card_charge_enabled=false (a Bora assume) e devolve a diferença à
      -- carteira quando sai mais barato — o aviso diz isso em vez de "Novo total".
      IF v_delta = 0 THEN
        v_body := format('%s: voltou ao preço previsto, %s.', v_name, public._euros_pt(v_new_client));
      ELSE
        v_body := format('%s: passou de %s para %s (peso real).',
                         v_name, public._euros_pt(v_est_client), public._euros_pt(v_new_client));
      END IF;
      IF v_total_delta > 0 AND NOT COALESCE((public.get_setting('weight_adjust_card_charge_enabled') #>> '{}')::boolean, false) THEN
        v_body := v_body || ' O peso real saiu mais caro; a diferença fica por conta do Bora.';
      ELSIF v_total_delta > 0 THEN
        v_body := v_body || format(' Diferença: %s.', public._euros_pt(v_total_delta));
      ELSIF v_total_delta < 0 THEN
        v_body := v_body || ' Saiu mais barato: a diferença vai para a tua carteira Bora no fim.';
      END IF;
    END IF;
    BEGIN
      PERFORM public._push_in_app_notification(v_order.user_id, 'order_weight_adjusted', v_title, v_body, p_order_id);
      SELECT decrypted_secret INTO v_url FROM vault.decrypted_secrets WHERE name = 'project_url';
      SELECT decrypted_secret INTO v_key FROM vault.decrypted_secrets WHERE name = 'service_role_key';
      IF v_url IS NOT NULL AND v_url <> '' AND v_key IS NOT NULL AND v_key <> '' AND v_order.user_id IS NOT NULL THEN
        PERFORM net.http_post(url := v_url || '/functions/v1/notify-client',
          headers := jsonb_build_object('Authorization', 'Bearer ' || v_key, 'Content-Type', 'application/json'),
          body := jsonb_build_object('clientId', v_order.user_id::text, 'orderId', p_order_id,
                                     'type', 'order_weight_adjusted', 'title', v_title, 'body', v_body));
      END IF;
      UPDATE public.order_weight_adjustments SET notified_at = now()
       WHERE order_id = p_order_id AND product_id = p_product_id;
      v_avisado := true;
    EXCEPTION WHEN OTHERS THEN
      RAISE NOTICE 'aviso de peso falhou: %', SQLERRM;
    END;
  END IF;

  RETURN jsonb_build_object(
    'ok', true,
    'produto', v_name,
    'qtd', v_qty,
    'estimado_caixa_cents', v_est_base,
    'real_caixa_cents', p_real_base_cents,
    'estimado_cliente_cents', v_est_client,
    'novo_cliente_cents', v_new_client,
    'diferenca_cents', v_delta,
    'diferenca_total_pedido_cents', v_total_delta,
    'novo_total_estimado_cents', v_novo_total,
    'minimo_cents', v_min,
    'maximo_cents', v_max,
    'cliente_avisado', v_avisado
  );
END;
$function$;
