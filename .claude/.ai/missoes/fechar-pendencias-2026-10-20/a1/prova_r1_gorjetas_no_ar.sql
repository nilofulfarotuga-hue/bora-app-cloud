-- A1 ronda 1 · prova em ROLLBACK contra a função JÁ APLICADA (sem a redefinir)
-- termina em RAISE EXCEPTION 'RESULT' -> nada fica gravado; motoristas reais só desligados dentro da transacção
do $t$
declare
  c_cli constant uuid := 'e3c166d2-5e20-4d2d-b4d9-fcd4867805a5';
  c_drv constant uuid := 'dede0000-0000-4000-8000-000000000001';
  c_adm constant uuid := 'c9fccf85-03ee-4efc-83bf-613f211a78ff';
  r public.tvde_rides; v_id uuid; v_antes jsonb; v_depois jsonb; v_ac jsonb;
begin
  set constraints all immediate;
  update public.platform_settings set value = 'true'::jsonb where key = 'tvde_encomendas_enabled';
  update public.drivers set is_online = false, last_heartbeat_at = now() - interval '1 day'
   where user_id is distinct from c_drv and (is_online or last_heartbeat_at > now() - interval '15 minutes');
  update public.driver_locations set is_online = false, last_updated = now() - interval '1 day'
   where driver_id not in (c_drv, 'dede0000-0000-4000-8000-000000000002'::uuid) and (is_online or last_updated > now() - interval '15 minutes');
  update public.drivers set vehicle_type = 'carro_passageiros', is_online = true, last_heartbeat_at = now() where user_id = c_drv;
  update public.driver_locations set is_online = true, last_updated = now(), latitude = 40.5380, longitude = -7.2680 where driver_id = c_drv;
  perform set_config('request.jwt.claim.sub', c_drv::text, true);
  perform set_config('request.jwt.claims', json_build_object('sub', c_drv, 'role', 'authenticated')::text, true);
  v_antes := public.compute_driver_settlement(c_drv, now(), false);
  perform set_config('request.jwt.claim.sub', c_cli::text, true);
  perform set_config('request.jwt.claims', json_build_object('sub', c_cli, 'role', 'authenticated')::text, true);
  r := public.tvde_request_ride(40.5373, -7.2675, 'A', 40.5650, -7.2675, 'B', 4.0, 'cash', 0, 'encomendas');
  v_id := r.id;
  perform set_config('request.jwt.claim.sub', c_drv::text, true);
  perform set_config('request.jwt.claims', json_build_object('sub', c_drv, 'role', 'authenticated')::text, true);
  perform public.tvde_accept_ride(v_id); perform public.tvde_driver_arrived(v_id); perform public.tvde_start_ride(v_id);
  perform public.tvde_finish_ride(v_id, 4.0, 'prova_a1_r1', 0);
  insert into public.tips (target, tvde_ride_id, client_user_id, provider_user_id, amount_cents, method, moment, status, paid_at)
  values ('tvde', v_id, c_cli, c_drv, 150, 'card', 'after', 'succeeded', now());
  v_depois := public.compute_driver_settlement(c_drv, now(), false);
  perform set_config('request.jwt.claim.sub', c_adm::text, true);
  perform set_config('request.jwt.claims', json_build_object('sub', c_adm, 'role', 'authenticated', 'app_metadata', json_build_object('role','admin'))::text, true);
  v_ac := public.admin_tvde_acertos_por_tipo(now());
  raise exception 'RESULT %', jsonb_build_object(
    'acerto_total_earnings_antes', v_antes->'total_earnings', 'acerto_total_earnings_depois', v_depois->'total_earnings',
    'acerto_net_depois', v_depois->'net_balance',
    'md5_funcao_no_ar', (select md5(pg_get_functiondef('public.admin_tvde_acertos_por_tipo(timestamptz)'::regprocedure))),
    'painel_demo', (select jsonb_agg(l) from jsonb_array_elements(v_ac->'linhas') l where l->>'driver_id' = c_drv::text))::text;
end $t$;