-- Prova em ROLLBACK (termina sempre em RAISE EXCEPTION 'RESULT ...').
-- Motoristas de TESTE (nunca pessoas reais): A = Rui Teste E2E, B = Estafeta Demo.
-- Cliente das corridas sintéticas: demo@bora.app. Nada fica gravado.
DO $prova$
DECLARE
  a_uid uuid := '320d716e-0dd8-4c7f-a5e7-009426319efd'; -- Rui Teste E2E (drivers.id = user_id)
  b_uid uuid := 'dede0000-0000-4000-8000-000000000001'; -- Estafeta Demo user_id
  b_did uuid := 'dede0000-0000-4000-8000-000000000002'; -- Estafeta Demo drivers.id
  cli   uuid := 'd5b0c0a1-f49e-4593-a919-147edfc069c2'; -- demo@bora.app
  s_id  uuid := gen_random_uuid();  -- corrida nova (Intermarché → R. Francisco de Passos)
  rb_id uuid := gen_random_uuid();  -- corrida activa do B (Campo de Ténis → Garden Shopping)
  s2_id uuid := gen_random_uuid();  -- segunda corrida nova (para provar queue_full)
  r public.tvde_rides; r2 public.tvde_rides;
  ev jsonb; out jsonb := '[]'::jsonb; n int; d_km numeric; ok boolean;
  err text;
BEGIN
  -- ── preparação (tudo dentro da transacção) ──────────────────────────────
  UPDATE public.drivers SET is_online = true, last_heartbeat_at = now(), approval_status='approved',
         vehicle_type = 'carro_passageiros'
   WHERE user_id IN (a_uid, b_uid);
  INSERT INTO public.driver_locations (driver_id, latitude, longitude, is_online, last_updated)
  VALUES (a_uid, 40.5370, -7.2680, true, now()),
         (b_uid, 40.5382, -7.2653, true, now())
  ON CONFLICT (driver_id) DO UPDATE SET latitude = EXCLUDED.latitude, longitude = EXCLUDED.longitude,
         is_online = true, last_updated = now();
  DELETE FROM public.driver_locations WHERE driver_id = b_did; -- só uma linha viva para o B
  -- Hermético: os motoristas REAIS ficam fora da roda durante a prova (tudo volta no rollback).
  UPDATE public.drivers SET is_online = false, last_heartbeat_at = now() - interval '1 day'
   WHERE vehicle_type = 'carro_passageiros' AND user_id NOT IN (a_uid, b_uid);
  UPDATE public.driver_locations SET is_online = false, last_updated = now() - interval '1 day'
   WHERE driver_id NOT IN (a_uid, b_uid);

  -- B a caminho de um passageiro (a mesma fase do Valdemir às 15:24)
  INSERT INTO public.tvde_rides (id, client_id, driver_id, status, is_queued, origin_lat, origin_lng, origin_label,
      dest_lat, dest_lng, dest_label, est_distance_km, est_fare_cents, driver_earn_cents, payment_method, payment_status)
  VALUES (rb_id, cli, b_uid, 'motorista_a_caminho', false, 40.5396704, -7.2841737, 'Campo de Ténis do IPG (teste)',
      40.5381819, -7.2653492, 'Garden Shopping (teste)', 2.96, 500, 400, 'mbway', 'succeeded');
  -- a nova corrida, MB Way pago (o trigger de INSERT adia o despacho — chamamos nós)
  INSERT INTO public.tvde_rides (id, client_id, status, origin_lat, origin_lng, origin_label,
      dest_lat, dest_lng, dest_label, est_distance_km, est_fare_cents, driver_earn_cents, payment_method, payment_status, tried_driver_ids)
  VALUES (s_id, cli, 'solicitada', 40.5285237, -7.2516061, 'Intermarché Guarda (teste)',
      40.5407818, -7.2677839, 'Rua Francisco de Passos 75 (teste)', 4.54, 500, 400, 'mbway', 'succeeded', '{}');
  UPDATE public.tvde_rides SET current_offer_driver_id = NULL, offer_expires_at = NULL WHERE id = s_id;

  d_km := public._haversine_km(40.5381819, -7.2653492, 40.5285237, -7.2516061);
  out := out || jsonb_build_object('setup', jsonb_build_object('dist_B_dest_para_recolha_km', round(d_km, 2),
           'radius', public.get_setting('tvde_queue_pickup_radius_km'), 'enabled', public.get_setting('tvde_backtoback_enabled'),
           'max_queue', public.get_setting('tvde_backtoback_max_queue'), 'min_stage', public.get_setting('tvde_backtoback_min_stage')));

  -- ── P5a: corrida nova com A livre → oferta vai a A (prioridade 1), não em fila ──
  PERFORM public.tvde_offer_to_next(s_id);
  SELECT * INTO r FROM public.tvde_rides WHERE id = s_id;
  SELECT meta INTO ev FROM public.tvde_ride_events WHERE ride_id = s_id AND status='oferta' ORDER BY at DESC LIMIT 1;
  out := out || jsonb_build_object('P5a_livre_primeiro', jsonb_build_object('offer_driver', r.current_offer_driver_id, 'esperado', a_uid,
           'queued_candidate', ev->'queued_candidate', 'ok', r.current_offer_driver_id = a_uid AND (ev->>'queued_candidate')::boolean = false));

  -- ── P1: A larga (cenário do Danilo) → oferta seguinte vai a B EM FILA ──
  UPDATE public.tvde_rides SET tried_driver_ids = ARRAY[a_uid], current_offer_driver_id = NULL, offer_expires_at = NULL WHERE id = s_id;
  PERFORM public.tvde_offer_to_next(s_id);
  SELECT * INTO r FROM public.tvde_rides WHERE id = s_id;
  -- (dentro de uma transacção now() é constante: lê-se o evento pelo motorista, não pela hora)
  SELECT meta INTO ev FROM public.tvde_ride_events WHERE ride_id = s_id AND status='oferta' AND meta->>'driver_id' = b_uid::text LIMIT 1;
  out := out || jsonb_build_object('P1_ocupado_chamado', jsonb_build_object('offer_driver', r.current_offer_driver_id, 'esperado', b_uid,
           'queued_candidate', ev->'queued_candidate', 'ok', r.current_offer_driver_id = b_uid AND (ev->>'queued_candidate')::boolean = true));

  -- ── P1b: B recusa → ninguém (A tentado, B tentado) → no_driver_since; a pausa do sweep limpa tried → volta a A ──
  PERFORM set_config('request.jwt.claims', json_build_object('sub', b_uid, 'role', 'authenticated')::text, true);
  PERFORM set_config('request.jwt.claim.sub', b_uid::text, true);
  PERFORM public.tvde_reject_ride(s_id);
  SELECT * INTO r FROM public.tvde_rides WHERE id = s_id;
  out := out || jsonb_build_object('P1b_B_recusou', jsonb_build_object('offer_driver', r.current_offer_driver_id, 'tried', r.tried_driver_ids,
           'no_driver_since_marcado', r.no_driver_since IS NOT NULL, 'ok', r.current_offer_driver_id IS NULL AND r.no_driver_since IS NOT NULL));
  UPDATE public.tvde_rides SET tried_driver_ids = '{}' WHERE id = s_id; -- o que o sweep faz após tvde_reoffer_pause_seconds
  PERFORM public.tvde_offer_to_next(s_id);
  SELECT * INTO r FROM public.tvde_rides WHERE id = s_id;
  SELECT meta INTO ev FROM public.tvde_ride_events WHERE ride_id = s_id AND status='oferta' ORDER BY at DESC LIMIT 1;
  out := out || jsonb_build_object('P1c_volta_ao_livre', jsonb_build_object('offer_driver', r.current_offer_driver_id, 'esperado', a_uid,
           'queued_candidate', ev->'queued_candidate', 'ok', r.current_offer_driver_id = a_uid));

  -- ── P2: B aceita em fila (estando em motorista_a_caminho) ──
  UPDATE public.tvde_rides SET tried_driver_ids = ARRAY[a_uid], current_offer_driver_id = NULL, offer_expires_at = NULL WHERE id = s_id;
  PERFORM public.tvde_offer_to_next(s_id);
  SELECT * INTO r FROM public.tvde_rides WHERE id = s_id;
  IF r.current_offer_driver_id <> b_uid THEN RAISE EXCEPTION 'RESULT P2 setup falhou: oferta a %', r.current_offer_driver_id; END IF;
  r := public.tvde_accept_ride(s_id);
  SELECT * INTO r2 FROM public.tvde_rides WHERE id = rb_id;
  SELECT count(*) INTO n FROM public.tvde_rides WHERE driver_id = b_uid AND is_queued = false
     AND status IN ('motorista_atribuido','motorista_a_caminho','motorista_chegou','em_andamento');
  SELECT meta INTO ev FROM public.tvde_ride_events WHERE ride_id = s_id AND status='motorista_atribuido' ORDER BY at DESC LIMIT 1;
  out := out || jsonb_build_object('P2_aceite_em_fila', jsonb_build_object('S_status', r.status, 'S_is_queued', r.is_queued, 'S_driver', r.driver_id,
           'RB_status', r2.status, 'RB_is_queued', r2.is_queued, 'activas_nao_fila_do_B', n, 'evento', ev,
           'ok', r.status='motorista_atribuido' AND r.is_queued AND r.driver_id=b_uid AND r2.status='motorista_a_caminho' AND n = 1));

  -- ── P2b: segunda corrida forçada ao B → queue_full (max_queue=1) — nunca duas activas ──
  INSERT INTO public.tvde_rides (id, client_id, status, origin_lat, origin_lng, origin_label, dest_lat, dest_lng, dest_label,
      est_distance_km, est_fare_cents, driver_earn_cents, payment_method, payment_status, tried_driver_ids, current_offer_driver_id, offer_expires_at)
  VALUES (s2_id, cli, 'solicitada', 40.5370, -7.2680, 'Sé (teste)', 40.5300, -7.2600, 'Estação (teste)', 2.0, 500, 400, 'mbway', 'succeeded', '{}', b_uid, now() + interval '40 seconds');
  BEGIN
    r := public.tvde_accept_ride(s2_id);
    err := 'ACEITOU (errado)';
  EXCEPTION WHEN OTHERS THEN err := SQLERRM;
  END;
  SELECT count(*) INTO n FROM public.tvde_rides WHERE driver_id = b_uid AND is_queued = false
     AND status IN ('motorista_atribuido','motorista_a_caminho','motorista_chegou','em_andamento');
  out := out || jsonb_build_object('P2b_queue_full', jsonb_build_object('erro', err, 'activas_nao_fila_do_B', n, 'ok', err = 'queue_full' AND n = 1));

  -- ── Item 9: B larga SÓ a da fila → volta à roda; a que ele leva não é tocada; nada é promovido ──
  r := public.tvde_cancel_ride(s_id, 'motorista', 'teste: larga só a fila');
  SELECT * INTO r2 FROM public.tvde_rides WHERE id = rb_id;
  SELECT count(*) INTO n FROM public.tvde_ride_events WHERE ride_id IN (rb_id, s_id) AND (meta->>'queued_activation')::boolean = true;
  out := out || jsonb_build_object('I9_larga_so_fila', jsonb_build_object('S_status', r.status, 'S_driver', r.driver_id, 'S_is_queued', r.is_queued,
           'S_tried_tem_B', b_uid = ANY(r.tried_driver_ids), 'RB_status', r2.status, 'RB_is_queued', r2.is_queued, 'promocoes_indevidas', n,
           'S_oferta_seguinte', r.current_offer_driver_id,
           'ok', r.status IN ('solicitada') AND r.driver_id IS NULL AND NOT r.is_queued AND r2.status='motorista_a_caminho' AND n = 0));

  -- ── P6: interruptor desligado → volta ao comportamento de hoje (ocupado nunca é chamado) ──
  UPDATE public.platform_settings SET value = 'false'::jsonb WHERE key = 'tvde_backtoback_enabled';
  UPDATE public.tvde_rides SET tried_driver_ids = ARRAY[a_uid], current_offer_driver_id = NULL, offer_expires_at = NULL, no_driver_since = NULL WHERE id = s_id;
  ok := public.tvde_offer_to_next(s_id);
  SELECT * INTO r FROM public.tvde_rides WHERE id = s_id;
  out := out || jsonb_build_object('P6_desligado', jsonb_build_object('retorno', ok, 'offer_driver', r.current_offer_driver_id,
           'no_driver_since_marcado', r.no_driver_since IS NOT NULL, 'ok', ok = false AND r.current_offer_driver_id IS NULL AND r.no_driver_since IS NOT NULL));
  UPDATE public.platform_settings SET value = 'true'::jsonb WHERE key = 'tvde_backtoback_enabled';

  -- ── min_stage: com 'em_andamento' o B (a caminho) não conta; passa a contar quando arranca ──
  UPDATE public.platform_settings SET value = '"em_andamento"'::jsonb WHERE key = 'tvde_backtoback_min_stage';
  UPDATE public.tvde_rides SET tried_driver_ids = ARRAY[a_uid], current_offer_driver_id = NULL, offer_expires_at = NULL, no_driver_since = NULL WHERE id = s_id;
  ok := public.tvde_offer_to_next(s_id);
  SELECT * INTO r FROM public.tvde_rides WHERE id = s_id;
  UPDATE public.tvde_rides SET status = 'em_andamento' WHERE id = rb_id;
  PERFORM public.tvde_offer_to_next(s_id);
  SELECT * INTO r2 FROM public.tvde_rides WHERE id = s_id;
  out := out || jsonb_build_object('min_stage', jsonb_build_object('a_caminho_nao_conta', r.current_offer_driver_id IS NULL AND ok = false,
           'em_andamento_conta', r2.current_offer_driver_id = b_uid, 'ok', r.current_offer_driver_id IS NULL AND r2.current_offer_driver_id = b_uid));
  UPDATE public.platform_settings SET value = '"motorista_a_caminho"'::jsonb WHERE key = 'tvde_backtoback_min_stage';

  -- ── P5b: sem_motorista continua a funcionar (ninguém elegível durante mais de tvde_retry_window_seconds) ──
  UPDATE public.tvde_rides SET tried_driver_ids = ARRAY[a_uid, b_uid], current_offer_driver_id = NULL, offer_expires_at = NULL,
         no_driver_since = now() - interval '130 seconds' WHERE id = s_id;
  ok := public.tvde_offer_to_next(s_id);
  SELECT * INTO r FROM public.tvde_rides WHERE id = s_id;
  out := out || jsonb_build_object('P5b_sem_motorista', jsonb_build_object('retorno', ok, 'status', r.status, 'ok', r.status = 'sem_motorista'));

  -- ── P5c: aceite normal com motorista livre (A) continua igual: motorista_a_caminho, não fila ──
  UPDATE public.tvde_rides SET status = 'solicitada', tried_driver_ids = '{}', current_offer_driver_id = NULL, no_driver_since = NULL WHERE id = s2_id;
  PERFORM public.tvde_offer_to_next(s2_id);
  SELECT * INTO r FROM public.tvde_rides WHERE id = s2_id;
  IF r.current_offer_driver_id <> a_uid THEN RAISE EXCEPTION 'RESULT P5c setup falhou: oferta a %', r.current_offer_driver_id; END IF;
  PERFORM set_config('request.jwt.claims', json_build_object('sub', a_uid, 'role', 'authenticated')::text, true);
  PERFORM set_config('request.jwt.claim.sub', a_uid::text, true);
  r := public.tvde_accept_ride(s2_id);
  out := out || jsonb_build_object('P5c_aceite_livre', jsonb_build_object('status', r.status, 'is_queued', r.is_queued, 'driver', r.driver_id,
           'ok', r.status = 'motorista_a_caminho' AND NOT r.is_queued AND r.driver_id = a_uid));

  RAISE EXCEPTION 'RESULT %', out::text;
END $prova$;
