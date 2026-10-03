-- Prova em ROLLBACK da reatribuição pelo admin, do tvde_ride_queue_info e da lista do admin.
-- Motoristas de TESTE: A = Rui Teste E2E (livre), B = Estafeta Demo (ocupado). Cliente demo@bora.app.
DO $prova$
DECLARE
  a_uid uuid := '320d716e-0dd8-4c7f-a5e7-009426319efd';
  b_uid uuid := 'dede0000-0000-4000-8000-000000000001';
  b_did uuid := 'dede0000-0000-4000-8000-000000000002';
  cli   uuid := 'd5b0c0a1-f49e-4593-a919-147edfc069c2';
  adm   uuid;
  s_id  uuid := gen_random_uuid(); rb_id uuid := gen_random_uuid(); q_id uuid := gen_random_uuid();
  r public.tvde_rides; r2 public.tvde_rides; r3 public.tvde_rides;
  res jsonb; info jsonb; lst jsonb; out jsonb := '[]'::jsonb; n int; err text; kinds text;
BEGIN
  SELECT id INTO adm FROM auth.users WHERE email = 'nilofulfarotuga@gmail.com' LIMIT 1;
  UPDATE public.drivers SET is_online = true, last_heartbeat_at = now(), approval_status='approved', vehicle_type = 'carro_passageiros' WHERE user_id IN (a_uid, b_uid);
  INSERT INTO public.driver_locations (driver_id, latitude, longitude, is_online, last_updated)
  VALUES (a_uid, 40.5370, -7.2680, true, now()), (b_uid, 40.5382, -7.2653, true, now())
  ON CONFLICT (driver_id) DO UPDATE SET latitude = EXCLUDED.latitude, longitude = EXCLUDED.longitude, is_online = true, last_updated = now();
  DELETE FROM public.driver_locations WHERE driver_id = b_did;

  -- B leva RB (a caminho); S está solicitada sem ninguém (o caso de hoje)
  INSERT INTO public.tvde_rides (id, client_id, driver_id, status, is_queued, origin_lat, origin_lng, origin_label, dest_lat, dest_lng, dest_label, est_distance_km, est_fare_cents, driver_earn_cents, payment_method, payment_status)
  VALUES (rb_id, cli, b_uid, 'motorista_a_caminho', false, 40.5396704, -7.2841737, 'Campo de Ténis (teste)', 40.5381819, -7.2653492, 'Garden Shopping (teste)', 2.96, 500, 400, 'mbway', 'succeeded');
  INSERT INTO public.tvde_rides (id, client_id, status, origin_lat, origin_lng, origin_label, dest_lat, dest_lng, dest_label, est_distance_km, est_fare_cents, driver_earn_cents, payment_method, payment_status, tried_driver_ids, no_driver_since)
  VALUES (s_id, cli, 'solicitada', 40.5285237, -7.2516061, 'Intermarché (teste)', 40.5407818, -7.2677839, 'R. Francisco de Passos (teste)', 4.54, 500, 400, 'mbway', 'succeeded', ARRAY[a_uid], now());
  UPDATE public.tvde_rides SET current_offer_driver_id = NULL, offer_expires_at = NULL WHERE id = s_id;

  -- ── D1: admin reatribui S ao B pelo drivers.ID (formato "errado") → entra em FILA, gravado com user_id ──
  PERFORM set_config('request.jwt.claims', json_build_object('sub', adm, 'role', 'authenticated', 'email', 'nilofulfarotuga@gmail.com', 'app_metadata', json_build_object('role', 'admin'))::text, true);
  PERFORM set_config('request.jwt.claim.sub', adm::text, true);
  res := public.admin_tvde_reassign_ride(s_id, b_did, 'prova: Danilo fora da Guarda');
  SELECT * INTO r FROM public.tvde_rides WHERE id = s_id;
  SELECT * INTO r2 FROM public.tvde_rides WHERE id = rb_id;
  SELECT string_agg((convert_from(body,'utf8')::jsonb->>'kind'), ',' ORDER BY id) INTO kinds FROM net.http_request_queue WHERE url LIKE '%notify-tvde-driver%' AND (convert_from(body,'utf8')::jsonb->>'rideId') = s_id::text;
  out := out || jsonb_build_object('D1_reassign_para_ocupado_pelo_drivers_id', jsonb_build_object('res', res, 'S_driver', r.driver_id, 'S_status', r.status, 'S_is_queued', r.is_queued,
      'S_tried', r.tried_driver_ids, 'S_no_driver_since', r.no_driver_since, 'RB_status', r2.status, 'pushes', kinds,
      'ok', r.driver_id = b_uid AND r.status = 'motorista_atribuido' AND r.is_queued AND r2.status = 'motorista_a_caminho' AND (res->>'queued')::boolean AND kinds = 'queued_added'));

  -- ── C1: o CLIENTE em fila pede o ETA somado ──
  PERFORM set_config('request.jwt.claims', json_build_object('sub', cli, 'role', 'authenticated')::text, true);
  PERFORM set_config('request.jwt.claim.sub', cli::text, true);
  info := public.tvde_ride_queue_info(s_id);
  out := out || jsonb_build_object('C1_queue_info_cliente', jsonb_build_object('info', info,
      'ok', (info->>'queued')::boolean AND info->>'ahead_status' = 'motorista_a_caminho' AND (info->>'eta_minutes')::int >= 1 AND (info->>'km_link')::numeric BETWEEN 1.5 AND 1.7));
  -- outro utilizador (A, que não é parte) não pode ver
  PERFORM set_config('request.jwt.claims', json_build_object('sub', a_uid, 'role', 'authenticated')::text, true);
  PERFORM set_config('request.jwt.claim.sub', a_uid::text, true);
  BEGIN
    info := public.tvde_ride_queue_info(s_id); err := 'DEVOLVEU (errado)';
  EXCEPTION WHEN OTHERS THEN err := SQLERRM; END;
  out := out || jsonb_build_object('C1b_queue_info_estranho', jsonb_build_object('erro', err, 'ok', err = 'not_ride_party'));

  -- ── D2: lista do admin diz atrás de quem está ──
  PERFORM set_config('request.jwt.claims', json_build_object('sub', adm, 'role', 'authenticated', 'email', 'nilofulfarotuga@gmail.com', 'app_metadata', json_build_object('role', 'admin'))::text, true);
  PERFORM set_config('request.jwt.claim.sub', adm::text, true);
  lst := public.admin_tvde_rides_list('live', 500);
  SELECT e INTO res FROM jsonb_array_elements(lst) e WHERE e->>'id' = s_id::text;
  SELECT e INTO info FROM jsonb_array_elements(lst) e WHERE e->>'id' = rb_id::text;
  out := out || jsonb_build_object('D2_lista_admin', jsonb_build_object('S_queued_behind', res->>'queued_behind_ride_id', 'RB_queue_next', info->>'queue_next_ride_id',
      'ok', res->>'queued_behind_ride_id' = rb_id::text AND info->>'queue_next_ride_id' = s_id::text));

  -- ── D3: admin passa S ao A (livre) → directo a_caminho; S sai da fila do B; push ride_assigned ao A e ride_reassigned_away ao B ──
  res := public.admin_tvde_reassign_ride(s_id, a_uid, 'prova: A ficou livre');
  SELECT * INTO r FROM public.tvde_rides WHERE id = s_id;
  SELECT count(*) INTO n FROM public.tvde_rides WHERE driver_id = b_uid AND is_queued = true AND status = 'motorista_atribuido';
  SELECT string_agg(((convert_from(body,'utf8')::jsonb->>'kind')) || '>' || left((convert_from(body,'utf8')::jsonb->>'driverId'), 8), ',' ORDER BY id) INTO kinds FROM net.http_request_queue WHERE url LIKE '%notify-tvde-driver%' AND (convert_from(body,'utf8')::jsonb->>'rideId') = s_id::text;
  out := out || jsonb_build_object('D3_reassign_para_livre', jsonb_build_object('res', res, 'S_driver', r.driver_id, 'S_status', r.status, 'S_is_queued', r.is_queued, 'fila_do_B', n, 'pushes', kinds,
      'ok', r.driver_id = a_uid AND r.status = 'motorista_a_caminho' AND NOT r.is_queued AND n = 0 AND NOT (res->>'queued')::boolean));

  -- ── D4: A leva S e tem Q em fila; admin tira-lhe S (dá ao B) → Q do A sobe para a_caminho ──
  INSERT INTO public.tvde_rides (id, client_id, driver_id, status, is_queued, origin_lat, origin_lng, origin_label, dest_lat, dest_lng, dest_label, est_distance_km, est_fare_cents, driver_earn_cents, payment_method, payment_status)
  VALUES (q_id, cli, a_uid, 'motorista_atribuido', true, 40.5300, -7.2600, 'Estação (teste)', 40.5370, -7.2680, 'Sé (teste)', 2.0, 500, 400, 'mbway', 'succeeded');
  res := public.admin_tvde_reassign_ride(s_id, b_uid, 'prova: volta ao B');
  SELECT * INTO r FROM public.tvde_rides WHERE id = s_id;
  SELECT * INTO r3 FROM public.tvde_rides WHERE id = q_id;
  out := out || jsonb_build_object('D4_fila_do_antigo_sobe', jsonb_build_object('res', res, 'S_driver', r.driver_id, 'S_is_queued', r.is_queued, 'Q_status', r3.status, 'Q_is_queued', r3.is_queued,
      'ok', r.driver_id = b_uid AND r.is_queued AND r3.status = 'motorista_a_caminho' AND NOT r3.is_queued AND res->>'promoted_ride_id' = q_id::text));

  -- ── D5: mesmo motorista → same_driver; corrida em andamento → ride_not_reassignable; motorista inexistente → driver_not_found ──
  BEGIN res := public.admin_tvde_reassign_ride(s_id, b_did, 'x'); err := 'ACEITOU'; EXCEPTION WHEN OTHERS THEN err := SQLERRM; END;
  out := out || jsonb_build_object('D5a_same_driver', jsonb_build_object('erro', err, 'ok', err = 'same_driver'));
  UPDATE public.tvde_rides SET status = 'em_andamento' WHERE id = rb_id;
  BEGIN res := public.admin_tvde_reassign_ride(rb_id, a_uid, 'x'); err := 'ACEITOU'; EXCEPTION WHEN OTHERS THEN err := SQLERRM; END;
  out := out || jsonb_build_object('D5b_em_andamento', jsonb_build_object('erro', err, 'ok', err LIKE 'ride_not_reassignable%'));
  BEGIN res := public.admin_tvde_reassign_ride(s_id, gen_random_uuid(), 'x'); err := 'ACEITOU'; EXCEPTION WHEN OTHERS THEN err := SQLERRM; END;
  out := out || jsonb_build_object('D5c_driver_not_found', jsonb_build_object('erro', err, 'ok', err = 'driver_not_found'));
  -- não-admin → bloqueado
  PERFORM set_config('request.jwt.claims', json_build_object('sub', a_uid, 'role', 'authenticated')::text, true);
  PERFORM set_config('request.jwt.claim.sub', a_uid::text, true);
  BEGIN res := public.admin_tvde_reassign_ride(s_id, a_uid, 'x'); err := 'ACEITOU'; EXCEPTION WHEN OTHERS THEN err := SQLERRM; END;
  out := out || jsonb_build_object('D5d_nao_admin', jsonb_build_object('erro', err, 'ok', err <> 'ACEITOU'));

  RAISE EXCEPTION 'RESULT %', out::text;
END $prova$;
