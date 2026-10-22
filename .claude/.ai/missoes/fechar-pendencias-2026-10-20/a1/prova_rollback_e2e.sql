-- PROVA A1 (ponta a ponta) — corre DEPOIS de supabase/migrations/20261021083257+083355+083510 (encomendas_*) no MESMO lote e acaba em
-- RAISE EXCEPTION: tudo volta atrás. Uma ENCOMENDA demo em DINHEIRO do pedido ao
-- fim: oferta (motor de sempre) -> aceitar -> cheguei -> recolhi -> entreguei,
-- com o ganho do estafeta e o acerto da semana. Os motoristas reais são postos
-- offline SÓ dentro da transacção (memória prova-em-rollback-armadilhas-tvde, 4.ª
-- armadilha) e os pg_net não saem (transacção desfeita).
do $e2e$
declare
  c_cli constant uuid := 'e3c166d2-5e20-4d2d-b4d9-fcd4867805a5';
  c_drv constant uuid := 'dede0000-0000-4000-8000-000000000001';
  c_adm constant uuid := '00000000-0000-4000-8000-00000000a001';
  r public.tvde_rides;
  v_id uuid;
  v_out jsonb := '{}'::jsonb;
  v_estados jsonb := '[]'::jsonb;
  v_set_antes jsonb; v_set_depois jsonb; v_acertos jsonb; v_lista jsonb;
begin
  update public.platform_settings set value = 'true'::jsonb where key = 'tvde_encomendas_enabled';

  -- reais fora (só nesta transacção); demo dentro, na Guarda, com sinal agora
  update public.drivers set is_online = false, last_heartbeat_at = now() - interval '1 day'
   where user_id is distinct from c_drv
     and (is_online or last_heartbeat_at > now() - interval '15 minutes');
  update public.driver_locations set is_online = false, last_updated = now() - interval '1 day'
   where driver_id not in (c_drv, 'dede0000-0000-4000-8000-000000000002'::uuid)
     and (is_online or last_updated > now() - interval '15 minutes');
  update public.drivers set vehicle_type = 'carro_passageiros', is_online = true, last_heartbeat_at = now()
   where user_id = c_drv;
  update public.driver_locations set is_online = true, last_updated = now(), latitude = 40.5380, longitude = -7.2680
   where driver_id = c_drv;

  -- acerto da semana do demo ANTES
  perform set_config('request.jwt.claim.sub', c_drv::text, true);
  perform set_config('request.jwt.claims', json_build_object('sub', c_drv, 'role', 'authenticated')::text, true);
  v_set_antes := public.compute_driver_settlement(c_drv, now(), false);

  -- 1. o cliente pede a ENCOMENDA (dinheiro, 4 km)
  perform set_config('request.jwt.claim.sub', c_cli::text, true);
  perform set_config('request.jwt.claims', json_build_object('sub', c_cli, 'role', 'authenticated')::text, true);
  perform set_config('role', 'authenticated', true);
  r := public.tvde_request_ride(40.5373, -7.2675, 'Sé da Guarda (caixa)', 40.5650, -7.2675, 'Bairro da Luz',
         4.0, 'cash', 0, 'encomendas');
  v_id := r.id;
  perform set_config('role', 'postgres', true);
  select * into r from public.tvde_rides where id = v_id;
  v_estados := v_estados || jsonb_build_object('passo', 'pedido', 'status', r.status, 'ride_kind', r.ride_kind,
                 'oferta_a', r.current_offer_driver_id, 'cliente_cents', r.est_fare_cents, 'estafeta_cents', r.driver_earn_cents);
  if r.current_offer_driver_id is distinct from c_drv then
    raise exception 'RESULT %', jsonb_build_object('erro', 'a oferta nao foi ao demo', 'estados', v_estados)::text;
  end if;

  -- 2. o estafeta demo aceita, chega, recolhe, entrega
  perform set_config('request.jwt.claim.sub', c_drv::text, true);
  perform set_config('request.jwt.claims', json_build_object('sub', c_drv, 'role', 'authenticated')::text, true);
  perform set_config('role', 'authenticated', true);
  perform public.tvde_accept_ride(v_id);
  select status into r.status from public.tvde_rides where id = v_id;
  v_estados := v_estados || jsonb_build_object('passo', 'aceitar', 'status', r.status);
  perform public.tvde_driver_arrived(v_id);
  select status into r.status from public.tvde_rides where id = v_id;
  v_estados := v_estados || jsonb_build_object('passo', 'cheguei', 'status', r.status);
  perform public.tvde_start_ride(v_id);
  select status into r.status from public.tvde_rides where id = v_id;
  v_estados := v_estados || jsonb_build_object('passo', 'recolhi', 'status', r.status);
  perform public.tvde_finish_ride(v_id, 4.0, 'prova_a1', 0);
  perform set_config('role', 'postgres', true);
  select * into r from public.tvde_rides where id = v_id;
  v_estados := v_estados || jsonb_build_object('passo', 'entreguei', 'status', r.status, 'ride_kind', r.ride_kind,
                 'final_fare_cents', r.final_fare_cents, 'driver_earn_cents', r.driver_earn_cents,
                 'bora_cut_cents', r.bora_cut_cents, 'cash_in_hand_cents', r.cash_in_hand_cents,
                 'payment_method', r.payment_method, 'payment_status', r.payment_status);

  -- 3. o acerto da semana do estafeta DEPOIS
  perform set_config('request.jwt.claim.sub', c_drv::text, true);
  perform set_config('request.jwt.claims', json_build_object('sub', c_drv, 'role', 'authenticated')::text, true);
  v_set_depois := public.compute_driver_settlement(c_drv, now(), false);

  -- 4. o painel (admin) vê a encomenda e o acerto partido por tipo
  perform set_config('request.jwt.claim.sub', c_adm::text, true);
  perform set_config('request.jwt.claims', json_build_object('sub', c_adm, 'role', 'authenticated',
    'email', 'admin-prova@bora.app', 'app_metadata', json_build_object('role', 'admin'))::text, true);
  v_acertos := public.admin_tvde_acertos_por_tipo(now());
  select x into v_lista from jsonb_array_elements(public.admin_tvde_rides_list_v2('history', 50)) x
   where x->>'id' = v_id::text;

  v_out := jsonb_build_object(
    'estados', v_estados,
    'acerto_antes', jsonb_build_object('tvde_rides', v_set_antes->'tvde_rides_count', 'tvde_earnings', v_set_antes->'tvde_earnings',
                                       'cru', v_set_antes),
    'acerto_depois', jsonb_build_object('tvde_rides', v_set_depois->'tvde_rides_count', 'tvde_earnings', v_set_depois->'tvde_earnings',
                                        'cru', v_set_depois),
    'painel_acerto_encomendas_demo', (select jsonb_agg(l) from jsonb_array_elements(v_acertos->'linhas') l
                                       where l->>'driver_id' = c_drv::text),
    'painel_lista_ride_kind', v_lista->>'ride_kind',
    'avisos_cliente', (select jsonb_agg(jsonb_build_object('status', b->>'status', 'titulo', b->>'titulo', 'corpo', b->>'corpo'))
                         from (select convert_from(q.body, 'utf8')::jsonb b from net.http_request_queue q
                                where q.url like '%notify-tvde-client%') s
                        where b->>'rideId' = v_id::text),
    'avisos_motorista', (select jsonb_agg(convert_from(q.body, 'utf8')::jsonb) from net.http_request_queue q
                          where q.url like '%notify-tvde-driver%' and convert_from(q.body, 'utf8')::jsonb->>'rideId' = v_id::text));
  raise exception 'RESULT %', v_out::text;
end $e2e$;
