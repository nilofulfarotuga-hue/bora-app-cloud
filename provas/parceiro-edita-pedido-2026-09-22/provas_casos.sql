-- ===== PROVAS em rollback (nada fica gravado) =====
CREATE TEMP TABLE _res (n serial, caso text, ok boolean, det jsonb);

CREATE OR REPLACE FUNCTION pg_temp.claims(u uuid) RETURNS void LANGUAGE sql AS $$
  SELECT set_config('request.jwt.claims', json_build_object('sub', u, 'role', 'authenticated', 'email','teste@bora.app')::text, true);
  SELECT set_config('request.jwt.claim.sub', u::text, true); $$;

-- pedido de teste nascido pelo mesmo caminho do create_order (pricing_calculate + gatilhos de INSERT)
CREATE OR REPLACE FUNCTION pg_temp.novo_pedido(p_rid text, p_user uuid, p_metodo text, p_items jsonb, p_pi text) RETURNS text
LANGUAGE plpgsql AS $$
DECLARE v_sub numeric; pc record; v_id text := gen_random_uuid()::text; v_price numeric;
BEGIN
  SELECT ROUND(SUM((i->>'price')::numeric * (i->>'quantity')::int), 2) INTO v_sub FROM jsonb_array_elements(p_items) i;
  SELECT * INTO pc FROM public.pricing_calculate('restaurant', v_sub, 2.3, true, false, false, 1);
  v_price := pc.customer_total;
  INSERT INTO public.orders (id, user_id, status, service_type, is_partner_store, restaurant_id, vendor_name,
     payment_method, payment_status, payment_intent_id, items, subtotal, delivery_fee, service_fee, bag_fee, bag_count,
     platform_commission, partner_commission_visible, partner_markup_hidden, partner_service_fee_client,
     driver_earnings, distance_km, price, final_total, payment_buffer_total, small_order_fee, is_test_order,
     pickup_address, dropoff_address)
  VALUES (v_id, p_user, 'preparing', 'restaurant', true, p_rid, 'TESTE', p_metodo,
     CASE WHEN p_metodo = 'cash' THEN 'pending' ELSE 'paid' END, p_pi, p_items, v_sub, pc.delivery_fee, pc.service_fee, pc.bag_fee, 1,
     pc.platform_commission, pc.platform_commission, pc.partner_markup_hidden, pc.service_fee,
     pc.driver_earnings, 2.3, v_price, v_price, v_price, 0, true, 'x', 'y');
  RETURN v_id;
END $$;

CREATE OR REPLACE FUNCTION pg_temp.dinheiro(p_id text) RETURNS jsonb LANGUAGE sql AS $$
  SELECT jsonb_build_object('subtotal', subtotal, 'service_fee', service_fee, 'psf', partner_service_fee_client,
    'markup', partner_markup_hidden, 'comm_vis', partner_commission_visible, 'plat', platform_commission,
    'small', small_order_fee, 'delivery', delivery_fee, 'bag', bag_fee, 'driver', driver_earnings,
    'price', price, 'total', total, 'customer_total', customer_total, 'final_total', final_total, 'buffer', payment_buffer_total)
  FROM public.orders WHERE id = p_id $$;

-- soma dos pedaços = total cobrado; e loja + markup + comissão = subtotal
CREATE OR REPLACE FUNCTION pg_temp.bate(p_id text) RETURNS jsonb LANGUAGE sql AS $$
  SELECT jsonb_build_object(
    'pedacos', subtotal + service_fee + delivery_fee + bag_fee + small_order_fee,
    'total', final_total,
    'soma_bate', (subtotal + service_fee + delivery_fee + bag_fee + small_order_fee) = final_total
                 AND price = final_total AND total = final_total AND customer_total = final_total,
    'loja', public.partner_store_share(subtotal, restaurant_id),
    'split_bate', public.partner_store_share(subtotal, restaurant_id) + partner_markup_hidden + platform_commission = subtotal,
    'tudo_ao_centimo', (subtotal * 100) = round(subtotal * 100))
  FROM public.orders WHERE id = p_id $$;

DO $T$
DECLARE
  SAB  constant text := '12aa2cbb-01bd-443b-a17e-633c169d4864';
  KEB  constant text := 'mrkebab-guarda';
  DONO constant uuid := '033e0fef-1a93-4c1b-b738-18572a936285';
  CLI  constant uuid := 'c9fccf85-03ee-4efc-83bf-613f211a78ff';
  DONO_KEB uuid; P_KEB record; P_KEB2 record;
  it jsonb := '[{"name":"Paçoca Moreninha do Rio","price":1.17,"quantity":3,"basePrice":1.17,"productId":"94f425c1-3765-404c-98e0-4e4e195c725f","purchaseStatus":"pending"},
               {"name":"Filtro para Bomba de Chimarrão (2 un)","price":0.93,"quantity":2,"basePrice":0.93,"productId":"49b857ce-112b-4e73-88c7-034be24b2ce8","purchaseStatus":"pending"},
               {"name":"Água","price":1.17,"quantity":1,"basePrice":1.17,"productId":"06deb41d-7570-47bb-a69d-a4a7f4284465","purchaseStatus":"pending"}]';
  o1 text; o2 text; o3 text; o4 text; o5 text; ref text; r jsonb; r2 jsonb; antes jsonb; g uuid; w1 int; w2 int; t0 numeric; t1 numeric; e text;
  v_prod_opt text := '8e3e4fc8-d382-46ec-8e14-bf7c3106b24a';
BEGIN
  UPDATE public.platform_settings SET value = 'true'::jsonb WHERE key = 'order_edit_enabled';

  -- ── A. Tirar produto, pagamento em DINHEIRO ──────────────────────────
  PERFORM pg_temp.claims(CLI);
  o1 := pg_temp.novo_pedido(SAB, CLI, 'cash', it, NULL);
  antes := pg_temp.dinheiro(o1);
  PERFORM pg_temp.claims(DONO);
  r := public.partner_propose_order_edit(o1, '[{"tipo":"remove","linha_idx":0,"quantidade":2}]');
  -- pedido de referência nascido já com o que o cliente leva
  PERFORM pg_temp.claims(CLI);
  ref := pg_temp.novo_pedido(SAB, CLI, 'cash', jsonb_set(it, '{0,quantity}', '1'), NULL);
  INSERT INTO _res(caso, ok, det) VALUES ('A tirar/dinheiro: igual a pedido nascido assim',
    (pg_temp.dinheiro(o1) - 'buffer') = (pg_temp.dinheiro(ref) - 'buffer') AND (pg_temp.bate(o1)->>'soma_bate')::boolean AND (pg_temp.bate(o1)->>'split_bate')::boolean,
    jsonb_build_object('antes', antes, 'depois', pg_temp.dinheiro(o1), 'referencia', pg_temp.dinheiro(ref), 'bate', pg_temp.bate(o1), 'rpc', r,
      'edits', (SELECT jsonb_agg(to_jsonb(e2) - 'id' - 'grupo_id' - 'order_id') FROM public.order_edits e2 WHERE e2.order_id = o1)));

  -- ── B. Tirar produto, CARTÃO: reembolso parcial Stripe fica pedido ao cêntimo ─
  PERFORM pg_temp.claims(CLI);
  o2 := pg_temp.novo_pedido(SAB, CLI, 'card', it, 'pi_TESTE_B');
  t0 := (pg_temp.dinheiro(o2)->>'final_total')::numeric;
  PERFORM pg_temp.claims(DONO);
  r := public.partner_propose_order_edit(o2, '[{"tipo":"remove","linha_idx":2,"quantidade":1}]');
  g := (r->>'grupo_id')::uuid;
  t1 := (pg_temp.dinheiro(o2)->>'final_total')::numeric;
  -- a Edge Function, depois do refund Stripe, chama isto (service_role)
  r2 := public.order_edit_refund_done(g, 're_TESTE_B', ROUND((t0 - t1) * 100)::int, 0);
  INSERT INTO _res(caso, ok, det) VALUES ('B tirar/cartão: reembolso = total antes − total depois',
    (SELECT (liquidacao->>'devolver_cents')::int = ROUND((t0 - t1) * 100) AND liquidacao->>'estado' = 'feito'
       FROM public.order_edits WHERE grupo_id = g LIMIT 1) AND (pg_temp.bate(o2)->>'soma_bate')::boolean,
    jsonb_build_object('total_antes', t0, 'total_depois', t1, 'liquidacao', (SELECT liquidacao FROM public.order_edits WHERE grupo_id = g LIMIT 1),
       'pg_net_pedido', (SELECT count(*) FROM net.http_request_queue WHERE body::text LIKE '%' || g::text || '%'), 'bate', pg_temp.bate(o2)));

  -- ── C. Acrescentar, CARTÃO, cliente aceita, pago → aplica ─────────────
  PERFORM pg_temp.claims(CLI);
  o3 := pg_temp.novo_pedido(SAB, CLI, 'card', it, 'pi_TESTE_C');
  antes := pg_temp.dinheiro(o3);
  PERFORM pg_temp.claims(DONO);
  r := public.partner_propose_order_edit(o3, jsonb_build_array(jsonb_build_object('tipo','add','product_id', v_prod_opt, 'quantidade', 2,
         'opcoes', '[{"group":"Deseja Extras?","items":["Mel","Kiwi"]}]'::jsonb)));
  g := (r->>'grupo_id')::uuid;
  INSERT INTO _res(caso, ok, det) VALUES ('C1 acrescentar: fica à espera do cliente e o pedido não muda',
    r->>'estado' = 'pendente_cliente' AND pg_temp.dinheiro(o3) = antes, r);
  PERFORM pg_temp.claims(CLI);
  r := public.client_respond_order_edit(g, true);
  INSERT INTO _res(caso, ok, det) VALUES ('C2 cliente aceita (cartão): pede cobrança da diferença, ainda não aplica',
    (r->>'precisa_pagamento')::boolean AND pg_temp.dinheiro(o3) = antes, r);
  r2 := public.order_edit_mark_paid(g, 'pi_TESTE_C_extra', (r->>'cobrar_cents')::int);
  PERFORM pg_temp.claims(CLI);
  ref := pg_temp.novo_pedido(SAB, CLI, 'card',
          it || (SELECT jsonb_build_array(jsonb_build_object('name', p.name, 'price', p.price + 2, 'quantity', 2, 'productId', p.id))
                  FROM public.products p WHERE p.id = v_prod_opt), 'pi_REF');
  INSERT INTO _res(caso, ok, det) VALUES ('C3 pago → aplicado; igual a pedido nascido com o produto; cobrado = diferença',
    (pg_temp.dinheiro(o3) - 'buffer') = (pg_temp.dinheiro(ref) - 'buffer')
      AND (pg_temp.bate(o3)->>'soma_bate')::boolean AND (pg_temp.bate(o3)->>'split_bate')::boolean
      AND ROUND(((pg_temp.dinheiro(o3)->>'final_total')::numeric - (antes->>'final_total')::numeric) * 100) = (r->>'cobrar_cents')::int,
    jsonb_build_object('antes', antes, 'depois', pg_temp.dinheiro(o3), 'referencia', pg_temp.dinheiro(ref), 'mark_paid', r2,
       'itens', (SELECT items FROM public.orders WHERE id = o3)));

  -- ── D. Acrescentar, cliente RECUSA → pedido fica como estava ─────────
  PERFORM pg_temp.claims(CLI);
  o4 := pg_temp.novo_pedido(SAB, CLI, 'cash', it, NULL);
  antes := pg_temp.dinheiro(o4) || jsonb_build_object('items', (SELECT items FROM public.orders WHERE id = o4));
  PERFORM pg_temp.claims(DONO);
  r := public.partner_propose_order_edit(o4, '[{"tipo":"qty","linha_idx":1,"quantidade":1}]');
  PERFORM pg_temp.claims(CLI);
  r2 := public.client_respond_order_edit((r->>'grupo_id')::uuid, false);
  INSERT INTO _res(caso, ok, det) VALUES ('D acrescentar recusado: pedido intacto',
    pg_temp.dinheiro(o4) || jsonb_build_object('items', (SELECT items FROM public.orders WHERE id = o4)) = antes
      AND (SELECT bool_and(estado = 'recusado') FROM public.order_edits WHERE order_id = o4),
    jsonb_build_object('proposta', r, 'resposta', r2));

  -- ── E. Loja com % própria (Mr Kebab 15 %), MB Way, tirar 2 vezes → carteira 2 vezes ─
  UPDATE public.restaurants SET coming_soon = false WHERE id = KEB;
  SELECT user_id INTO DONO_KEB FROM public.restaurants WHERE id = KEB;
  SELECT id, name, price INTO P_KEB FROM public.products WHERE restaurant_id = KEB AND is_available ORDER BY price DESC LIMIT 1;
  SELECT id, name, price INTO P_KEB2 FROM public.products WHERE restaurant_id = KEB AND is_available ORDER BY price ASC LIMIT 1;
  PERFORM pg_temp.claims(CLI);
  o5 := pg_temp.novo_pedido(KEB, CLI, 'mbway', jsonb_build_array(
          jsonb_build_object('name', P_KEB.name, 'price', P_KEB.price, 'quantity', 2, 'productId', P_KEB.id),
          jsonb_build_object('name', P_KEB2.name, 'price', P_KEB2.price, 'quantity', 2, 'productId', P_KEB2.id)), 'pi_TESTE_E');
  SELECT COALESCE(SUM(amount_cents), 0) INTO w1 FROM public.wallet_transactions WHERE related_order_id = o5;
  t0 := (pg_temp.dinheiro(o5)->>'final_total')::numeric;
  PERFORM pg_temp.claims(DONO_KEB);
  r := public.partner_propose_order_edit(o5, '[{"tipo":"remove","linha_idx":1,"quantidade":1}]');
  r2 := public.partner_propose_order_edit(o5, '[{"tipo":"remove","linha_idx":0,"quantidade":1}]');
  t1 := (pg_temp.dinheiro(o5)->>'final_total')::numeric;
  SELECT COALESCE(SUM(amount_cents), 0) INTO w2 FROM public.wallet_transactions WHERE related_order_id = o5;
  PERFORM pg_temp.claims(CLI);
  ref := pg_temp.novo_pedido(KEB, CLI, 'mbway', jsonb_build_array(
          jsonb_build_object('name', P_KEB.name, 'price', P_KEB.price, 'quantity', 1, 'productId', P_KEB.id),
          jsonb_build_object('name', P_KEB2.name, 'price', P_KEB2.price, 'quantity', 1, 'productId', P_KEB2.id)), 'pi_REF2');
  INSERT INTO _res(caso, ok, det) VALUES ('E tirar 2×/MB Way/loja 15 %: carteira recebe as 2 diferenças; igual a pedido nascido assim',
    (w2 - w1) = ROUND((t0 - t1) * 100) AND (pg_temp.dinheiro(o5) - 'buffer') = (pg_temp.dinheiro(ref) - 'buffer')
      AND (pg_temp.bate(o5)->>'soma_bate')::boolean AND (pg_temp.bate(o5)->>'split_bate')::boolean,
    jsonb_build_object('total_antes', t0, 'total_depois', t1, 'carteira_cents', w2 - w1,
      'movimentos', (SELECT jsonb_agg(jsonb_build_object('kind', kind, 'cents', amount_cents, 'key', idempotency_key)) FROM public.wallet_transactions WHERE related_order_id = o5),
      'depois', pg_temp.dinheiro(o5), 'referencia', pg_temp.dinheiro(ref), 'bate', pg_temp.bate(o5)));

  -- ── F. Guardas ────────────────────────────────────────────────────────
  PERFORM pg_temp.claims(gen_random_uuid());
  BEGIN r := public.partner_propose_order_edit(o1, '[{"tipo":"remove","linha_idx":0,"quantidade":1}]'); e := 'passou';
  EXCEPTION WHEN OTHERS THEN e := SQLERRM; END;
  INSERT INTO _res(caso, ok, det) VALUES ('F1 outra conta não mexe na loja', e LIKE 'NAO_E_A_TUA_LOJA%', to_jsonb(e));
  PERFORM pg_temp.claims(DONO);
  BEGIN r := public.partner_propose_order_edit(o1, jsonb_build_array(jsonb_build_object('tipo','add','product_id', v_prod_opt, 'quantidade', 20))); e := 'passou';
  EXCEPTION WHEN OTHERS THEN e := SQLERRM; END;
  INSERT INTO _res(caso, ok, det) VALUES ('F2 dinheiro acima do limite recusado', e LIKE 'LIMITE_DINHEIRO%', to_jsonb(e));
  BEGIN r := public.partner_propose_order_edit(o1, '[{"tipo":"remove","linha_idx":0,"quantidade":1},{"tipo":"remove","linha_idx":0,"quantidade":2},{"tipo":"remove","linha_idx":0,"quantidade":1}]'); e := 'passou';
  EXCEPTION WHEN OTHERS THEN e := SQLERRM; END;
  INSERT INTO _res(caso, ok, det) VALUES ('F3 não deixa esvaziar o pedido', e LIKE 'PEDIDO_FICA_VAZIO%' OR e LIKE 'TIRA_MAIS%' OR e LIKE 'LINHA_NAO%', to_jsonb(e));
  PERFORM set_config('app.financial_bypass', 'true', true);
  UPDATE public.orders SET status = 'pickedUp' WHERE id = o4;
  PERFORM set_config('app.financial_bypass', 'false', true);
  BEGIN r := public.partner_propose_order_edit(o4, '[{"tipo":"remove","linha_idx":0,"quantidade":1}]'); e := 'passou';
  EXCEPTION WHEN OTHERS THEN e := SQLERRM; END;
  INSERT INTO _res(caso, ok, det) VALUES ('F4 depois de recolhido já não se mexe', e LIKE 'JA_RECOLHIDO%', to_jsonb(e));
  BEGIN r := public.partner_propose_order_edit(o2, '[{"tipo":"add","product_id":"mrkebab-x","quantidade":1}]'); e := 'passou';
  EXCEPTION WHEN OTHERS THEN e := SQLERRM; END;
  INSERT INTO _res(caso, ok, det) VALUES ('F5 produto de outra loja recusado', e LIKE 'PRODUTO_NAO_E_DA_LOJA%', to_jsonb(e));
  -- idempotência: aplicar o mesmo grupo 2 vezes não mexe outra vez
  r := public._order_edit_apply((SELECT grupo_id FROM public.order_edits WHERE order_id = o1 LIMIT 1));
  INSERT INTO _res(caso, ok, det) VALUES ('F6 aplicar 2× o mesmo grupo não duplica', (r->>'ja_aplicado')::boolean, r);

  RAISE EXCEPTION 'ROLLBACK_PROVAS %', (SELECT jsonb_agg(jsonb_build_object('caso', caso, 'ok', ok, 'det', det) ORDER BY n) FROM _res);
END $T$;
