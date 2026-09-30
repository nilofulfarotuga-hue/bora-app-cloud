-- Prova A — mudar destino: os 4 exemplos do Danilo, em DINHEIRO e em CARTÃO (stub:
-- nenhum PaymentIntent real; o "pagamento confirmado" é simulado pela chamada do
-- servidor tvde_dest_change_confirm_paid com um id pi_TESTE_*), mais: duas mudanças
-- seguidas (regra 8), mudança antes da recolha (0 km feitos) e a regressão
-- "sem mudança = igual a hoje" contra a definição ANTIGA da tvde_finish_ride
-- (backup em fn_definition_backups). Tudo dentro de um DO que acaba em RAISE:
-- a transação desfaz-se, os pg_net não saem, nada fica na base.
-- Contas: cliente demo@bora.app (d5b0c0a1…), motorista demo (dede0000…0001).
DO $$
DECLARE
  c uuid := 'd5b0c0a1-f49e-4593-a919-147edfc069c2';
  m uuid := 'dede0000-0000-4000-8000-000000000001';
  o_lat double precision := 40.5373; o_lng double precision := -7.2676;  -- Guarda
  r public.tvde_rides; q jsonb; res jsonb; out jsonb := '[]'::jsonb;
  bal0 numeric; bal1 numeric; k int; old_def text;
  cases jsonb := '[
    {"n":"ex1_dinheiro","km":4,"new":10,"pm":"cash"},
    {"n":"ex2_dinheiro","km":4,"new":5,"pm":"cash"},
    {"n":"ex3_dinheiro","km":8,"new":5,"pm":"cash"},
    {"n":"ex4_dinheiro","km":8,"new":8.4,"pm":"cash"},
    {"n":"ex1_cartao","km":4,"new":10,"pm":"card"},
    {"n":"ex2_cartao","km":4,"new":5,"pm":"card"},
    {"n":"ex3_cartao","km":8,"new":5,"pm":"card"},
    {"n":"ex4_mbway","km":8,"new":8.4,"pm":"mbway"}
  ]';
  cs jsonb;
BEGIN
  -- Origem = onde está o carro do motorista demo (a linha reta origem->carro é 0).
  -- Nenhum UPDATE em drivers. Os pg_net (ofertas/push) morrem com o rollback.
  SELECT COALESCE(lat, o_lat), COALESCE(lng, o_lng) INTO o_lat, o_lng FROM public.drivers WHERE user_id = m;

  FOR k IN 0 .. jsonb_array_length(cases) - 1 LOOP
    cs := cases -> k;
    PERFORM set_config('request.jwt.claims', json_build_object('sub', c, 'role', 'authenticated')::text, true);
    r := public.tvde_request_ride(o_lat, o_lng, 'Origem teste', o_lat, o_lng, 'Destino A',
                                  (cs->>'km')::numeric, 'cash', 0);
    UPDATE public.tvde_rides SET driver_id = m, status = 'em_andamento', payment_method = cs->>'pm'
     WHERE id = r.id;
    -- Cliente: cotação e aceitar. 3 km já feitos + resto da rota = total novo.
    q := public.tvde_dest_change_quote(r.id, o_lat, o_lng, 'Destino B', 3, (cs->>'new')::numeric - 3);
    res := public.tvde_dest_change_request(r.id, o_lat, o_lng, 'Destino B', 3, (cs->>'new')::numeric - 3,
                                           (q->>'client_diff_cents')::int);
    IF (res->>'needs_payment')::boolean THEN
      -- Cartão/MB Way: antes de pagar, o destino NÃO mudou.
      SELECT * INTO r FROM public.tvde_rides WHERE id = r.id;
      IF r.dest_label <> 'Destino A' THEN RAISE EXCEPTION 'mudou antes de pagar'; END IF;
      PERFORM public.tvde_dest_change_set_pi((res->>'change_id')::uuid, 'pi_TESTE_' || k);
      res := res || jsonb_build_object('apply', public.tvde_dest_change_confirm_paid(
               (res->>'change_id')::uuid, 'pi_TESTE_' || k, (q->>'client_diff_cents')::int));
    END IF;
    SELECT * INTO r FROM public.tvde_rides WHERE id = r.id;
    SELECT COALESCE(balance, 0) INTO bal0 FROM public.tvde_driver_balances WHERE driver_id = m;
    bal0 := COALESCE(bal0, 0);
    PERFORM set_config('request.jwt.claims', json_build_object('sub', m, 'role', 'authenticated')::text, true);
    r := public.tvde_finish_ride(r.id, (cs->>'new')::numeric, 'teste', 0);
    SELECT COALESCE(balance, 0) INTO bal1 FROM public.tvde_driver_balances WHERE driver_id = m;
    out := out || jsonb_build_array(jsonb_build_object('caso', cs->>'n',
      'cotacao_cliente_paga', q->>'client_diff_cents', 'cotacao_motorista_ganha', q->>'driver_diff_cents',
      'preco_antes', q->>'price_before_cents', 'preco_depois', q->>'price_after_cents',
      'destino', r.dest_label, 'est_km', r.est_distance_km,
      'final_cliente', r.final_fare_cents, 'final_motorista', r.driver_earn_cents, 'bora', r.bora_cut_cents,
      'acerto_motorista_eur', bal1 - bal0));
  END LOOP;

  -- Regra 8: duas mudanças na mesma corrida (4 -> 5 -> 10), dinheiro.
  PERFORM set_config('request.jwt.claims', json_build_object('sub', c, 'role', 'authenticated')::text, true);
  r := public.tvde_request_ride(o_lat, o_lng, 'Origem teste', o_lat, o_lng, 'Destino A', 4, 'cash', 0);
  UPDATE public.tvde_rides SET driver_id = m, status = 'em_andamento' WHERE id = r.id;
  res := public.tvde_dest_change_request(r.id, o_lat, o_lng, 'Destino B', 2, 3, NULL);
  q := public.tvde_dest_change_request(r.id, o_lat, o_lng, 'Destino C', 4, 6, NULL);
  SELECT COALESCE(balance, 0) INTO bal0 FROM public.tvde_driver_balances WHERE driver_id = m;
  PERFORM set_config('request.jwt.claims', json_build_object('sub', m, 'role', 'authenticated')::text, true);
  r := public.tvde_finish_ride(r.id, 10, 'teste', 0);
  SELECT COALESCE(balance, 0) INTO bal1 FROM public.tvde_driver_balances WHERE driver_id = m;
  out := out || jsonb_build_array(jsonb_build_object('caso', 'duas_mudancas_4_5_10',
    'mudanca1_paga', res->>'client_diff_cents', 'mudanca1_motorista', res->>'driver_diff_cents',
    'mudanca2_preco_antes', q->>'price_before_cents', 'mudanca2_paga', q->>'client_diff_cents',
    'mudanca2_motorista', q->>'driver_diff_cents',
    'final_cliente', r.final_fare_cents, 'final_motorista', r.driver_earn_cents, 'bora', r.bora_cut_cents,
    'acerto_motorista_eur', bal1 - bal0));

  -- Antes da recolha: km feitos contam 0 mesmo que a app mande 3.
  PERFORM set_config('request.jwt.claims', json_build_object('sub', c, 'role', 'authenticated')::text, true);
  r := public.tvde_request_ride(o_lat, o_lng, 'Origem teste', o_lat, o_lng, 'Destino A', 4, 'cash', 0);
  UPDATE public.tvde_rides SET driver_id = m, status = 'motorista_a_caminho' WHERE id = r.id;
  q := public.tvde_dest_change_quote(r.id, o_lat, o_lng, 'Destino B', 3, 7);
  out := out || jsonb_build_array(jsonb_build_object('caso', 'antes_da_recolha_app_manda_3_feitos',
    'km_feitos_contados', q->>'km_done', 'km_total', q->>'km_new_total', 'paga', q->>'client_diff_cents'));
  UPDATE public.tvde_rides SET status = 'cancelada_cliente' WHERE id = r.id;

  -- Regressão: SEM mudança, dinheiro e cartão, com e sem paragem em dinheiro:
  -- finish NOVA vs finish ANTIGA (backup), mesma corrida, mesmo saldo.
  SELECT definition INTO old_def FROM public.fn_definition_backups
   WHERE fn = 'tvde_finish_ride' AND reason = 'antes da mudanca de destino 2026-09-30' ORDER BY id DESC LIMIT 1;
  EXECUTE replace(old_def, 'FUNCTION public.tvde_finish_ride(', 'FUNCTION public.tvde_finish_ride_antiga_teste(');
  FOR k IN 1..4 LOOP
    PERFORM set_config('request.jwt.claims', json_build_object('sub', c, 'role', 'authenticated')::text, true);
    r := public.tvde_request_ride(o_lat, o_lng, 'Origem teste', o_lat, o_lng, 'Destino A',
                                  CASE WHEN k IN (1,3) THEN 4 ELSE 8.3 END, 'cash', 0);
    UPDATE public.tvde_rides SET driver_id = m, status = 'em_andamento',
       payment_method = CASE WHEN k <= 2 THEN 'cash' ELSE 'card' END WHERE id = r.id;
    IF k IN (2,4) THEN
      PERFORM public.tvde_add_stop(r.id, o_lat, o_lng, 'Paragem', 1, NULL);
    END IF;
    PERFORM set_config('request.jwt.claims', json_build_object('sub', m, 'role', 'authenticated')::text, true);
    DECLARE a_fare int; a_drv int; a_bora int; a_bal numeric; n_bal numeric; b0 numeric;
    BEGIN
      SELECT COALESCE(balance,0) INTO b0 FROM public.tvde_driver_balances WHERE driver_id = m; b0 := COALESCE(b0,0);
      BEGIN
        r := public.tvde_finish_ride_antiga_teste(r.id, 9.7, 'teste', 0);
        a_fare := r.final_fare_cents; a_drv := r.driver_earn_cents; a_bora := r.bora_cut_cents;
        SELECT COALESCE(balance,0) INTO a_bal FROM public.tvde_driver_balances WHERE driver_id = m;
        RAISE EXCEPTION 'desfaz_antiga';
      EXCEPTION WHEN raise_exception THEN
        IF SQLERRM <> 'desfaz_antiga' THEN RAISE; END IF;
      END;
      r := public.tvde_finish_ride(r.id, 9.7, 'teste', 0);
      SELECT COALESCE(balance,0) INTO n_bal FROM public.tvde_driver_balances WHERE driver_id = m;
      out := out || jsonb_build_array(jsonb_build_object('caso', 'regressao_sem_mudanca_' || k,
        'pagamento', r.payment_method, 'paragem', k IN (2,4),
        'antiga', jsonb_build_array(a_fare, a_drv, a_bora, a_bal - b0),
        'nova', jsonb_build_array(r.final_fare_cents, r.driver_earn_cents, r.bora_cut_cents, n_bal - b0),
        'igual', a_fare = r.final_fare_cents AND a_drv = r.driver_earn_cents AND a_bora = r.bora_cut_cents
                 AND a_bal = n_bal));
    END;
  END LOOP;

  RAISE EXCEPTION 'RESULT %', out::text;
END $$;
