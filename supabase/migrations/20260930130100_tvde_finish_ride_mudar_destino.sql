-- =============================================================================
-- tvde_finish_ride — soma a MUDANÇA DE DESTINO (missão tvde-mudar-destino, 30/09/2026)
-- Autorização do Danilo: "sim" (30/09/2026 12:51).
--
-- Só ACRESCENTA texto à definição que está no ar (patch por âncora):
--   a) variável v_dest_cash;
--   b) v_dest_cash := dest_change_cash_cents (mudanças pagas em dinheiro);
--   c) volta do pacote: desconta os km extra já pagos pela mudança da regra do
--      km a mais na volta (caso Stela 18/09) — para não cobrar duas vezes;
--   d) soma dest_change_extra_fee_cents à tarifa e dest_change_extra_driver_cents
--      ao ganho (o preço final fica exatamente o que o cliente aceitou);
--   e) acerto do motorista: a mudança paga em dinheiro entra como as paragens
--      em dinheiro (ramos do pacote em dinheiro e "resto");
--   f) quatro campos a mais no evento 'finalizada'.
-- Com todas as colunas dest_change_* a 0 (nenhuma mudança) o resultado é
-- exatamente o mesmo de antes: cada soma acrescenta 0.
-- Guarda a definição anterior em fn_definition_backups e PROVA, antes do
-- EXECUTE, que tirar os acrescentos devolve a definição antiga byte a byte.
-- =============================================================================
DO $$
DECLARE d text; n text; back text; i int;
  pairs text[][] := ARRAY[
   ARRAY['  v_price_km NUMERIC; v_fixed_on BOOLEAN; v_tokens_eff INT;
BEGIN',
         '  v_price_km NUMERIC; v_fixed_on BOOLEAN; v_tokens_eff INT;
  v_dest_cash INT;
BEGIN'],
   ARRAY['   WHERE ride_id = p_ride_id AND payment_intent_id IS NULL;
',
         '   WHERE ride_id = p_ride_id AND payment_intent_id IS NULL;
  -- 2026-09-30 MUDAR DESTINO: parte das mudanças paga em dinheiro (o motorista recolhe).
  v_dest_cash := COALESCE(v_ride.dest_change_cash_cents, 0);
'],
   ARRAY['v_extra_km_over := GREATEST(0, v_extra_km - v_outbound_extra_km);',
         'v_extra_km_over := GREATEST(0, v_extra_km - v_outbound_extra_km - COALESCE(v_ride.dest_change_paid_extra_km, 0));'],
   ARRAY['  -- SEM GUARDA (decisao 18/08): o corte gravado e o CRU.
  v_bora_raw := v_bora_cut;',
         '  -- 2026-09-30 MUDAR DESTINO (Danilo): o que a tabela pela est_distance_km nova
  -- nao da sozinha (minimo de 2 EUR / 1 EUR, plano, pacote, destino mais perto).
  -- Com a corrida sem mudancas estas colunas sao 0.
  v_fare        := v_fare + COALESCE(v_ride.dest_change_extra_fee_cents, 0);
  v_driver_earn := v_driver_earn + COALESCE(v_ride.dest_change_extra_driver_cents, 0);
  v_bora_cut    := v_bora_cut + COALESCE(v_ride.dest_change_extra_fee_cents, 0) - COALESCE(v_ride.dest_change_extra_driver_cents, 0);

  -- SEM GUARDA (decisao 18/08): o corte gravado e o CRU.
  v_bora_raw := v_bora_cut;'],
   ARRAY['#>> ''{}'')::int) + v_stops_cash) - v_driver_earn;',
         '#>> ''{}'')::int) + v_stops_cash + v_dest_cash) - v_driver_earn;'],
   ARRAY['    v_settle := v_stops_cash + v_extra_fare - v_driver_earn;',
         '    v_settle := v_stops_cash + v_dest_cash + v_extra_fare - v_driver_earn;'],
   ARRAY['      ''stops_cash_cents'', v_stops_cash,
',
         '      ''stops_cash_cents'', v_stops_cash,
      ''dest_change_fee_cents'', v_ride.dest_change_fee_cents, ''dest_change_cash_cents'', v_dest_cash,
      ''dest_change_extra_fee_cents'', v_ride.dest_change_extra_fee_cents, ''dest_change_extra_driver_cents'', v_ride.dest_change_extra_driver_cents,
']
  ];
BEGIN
  d := pg_get_functiondef('public.tvde_finish_ride(uuid,numeric,text,integer)'::regprocedure);
  IF md5(d) <> '042a6809a28681f13b71c3f0eee4f0bc' THEN
    RAISE EXCEPTION 'tvde_finish_ride no ar nao e a esperada (md5 %) — nada aplicado', md5(d);
  END IF;
  INSERT INTO public.fn_definition_backups(fn, definition, reason)
    VALUES ('tvde_finish_ride', d, 'antes da mudanca de destino 2026-09-30');
  n := d;
  FOR i IN 1..array_length(pairs,1) LOOP
    IF (length(n) - length(replace(n, pairs[i][1], ''))) / length(pairs[i][1]) <> 1 THEN
      RAISE EXCEPTION 'ancora % nao aparece exatamente uma vez: %', i, left(pairs[i][1], 60);
    END IF;
    n := replace(n, pairs[i][1], pairs[i][2]);
  END LOOP;
  -- Prova: desfazer os acrescentos devolve a definição antiga, byte a byte.
  back := n;
  FOR i IN REVERSE array_length(pairs,1)..1 LOOP
    back := replace(back, pairs[i][2], pairs[i][1]);
  END LOOP;
  IF back <> d THEN RAISE EXCEPTION 'prova de igualdade falhou — nada aplicado'; END IF;
  EXECUTE n;
END $$;
