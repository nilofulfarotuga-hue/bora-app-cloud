-- A1 ronda 1 · prova em ROLLBACK (termina em RAISE EXCEPTION 'RESULT' -> nada fica gravado)
-- corrida 21/10/2026 via MCP execute_sql, projecto ojykpzwqrtusfeakzrna
create or replace function public.admin_tvde_acertos_por_tipo(p_week_start timestamptz default null)
returns jsonb language plpgsql security definer set search_path to 'public' as $$
declare v_admin record; v_b record; v_out jsonb;
begin
  select admin_id into v_admin from public._admin_op_guard();
  select * into v_b from public.driver_settlement_week_bounds(coalesce(p_week_start, now()));
  with corridas as (
    select r.driver_id, r.ride_kind, count(*) as corridas,
           coalesce(sum(coalesce(r.driver_earn_cents, 0)), 0) as ganho_cents,
           coalesce(sum(coalesce(r.cash_in_hand_cents, 0)), 0) as dinheiro_em_mao_cents,
           coalesce(sum(case when r.payment_method in ('card','mbway') then coalesce(r.final_fare_cents, r.est_fare_cents, 0) else 0 end), 0) as online_cents
      from public.tvde_rides r
     where r.status = 'finalizada' and r.driver_id is not null and r.created_at >= v_b.week_start and r.created_at <= v_b.week_end
     group by 1, 2
  ), comps as (
    select c.driver_id, coalesce(r.ride_kind, 'passageiros') as ride_kind, coalesce(sum(c.driver_cents), 0) as compensacao_cents
      from public.tvde_cancel_compensations c left join public.tvde_rides r on r.id = c.ride_id
     where c.created_at >= v_b.week_start and c.created_at <= v_b.week_end group by 1, 2
  ), gorjetas as (
    select t.provider_user_id as driver_id, coalesce(r.ride_kind, 'passageiros') as ride_kind, coalesce(sum(t.amount_cents), 0) as gorjetas_cents
      from public.tips t join public.tvde_rides r on r.id = t.tvde_ride_id
     where t.status = 'succeeded' and t.method in ('card', 'mbway') and t.paid_at >= v_b.week_start and t.paid_at <= v_b.week_end
     group by 1, 2
  ), chaves as (
    select driver_id, ride_kind from corridas union select driver_id, ride_kind from comps union select driver_id, ride_kind from gorjetas
  ), juntos as (
    select k.driver_id, k.ride_kind, coalesce(a.corridas, 0) as corridas,
           coalesce(a.ganho_cents, 0) + coalesce(b.compensacao_cents, 0) + coalesce(g.gorjetas_cents, 0) as ganho_cents,
           coalesce(a.dinheiro_em_mao_cents, 0) as dinheiro_em_mao_cents, coalesce(a.online_cents, 0) as online_cents,
           coalesce(b.compensacao_cents, 0) as compensacao_cents, coalesce(g.gorjetas_cents, 0) as gorjetas_online_cents
      from chaves k
      left join corridas a on a.driver_id = k.driver_id and a.ride_kind = k.ride_kind
      left join comps b on b.driver_id = k.driver_id and b.ride_kind = k.ride_kind
      left join gorjetas g on g.driver_id = k.driver_id and g.ride_kind = k.ride_kind
  )
  select jsonb_build_object('week_start', v_b.week_start, 'week_end', v_b.week_end,
           'linhas', coalesce(jsonb_agg(jsonb_build_object(
               'driver_id', j.driver_id,
               'driver_name', coalesce((select nullif(trim(d.name), '') from public.drivers d where d.user_id = j.driver_id limit 1), '(sem nome)'),
               'ride_kind', j.ride_kind, 'corridas', j.corridas, 'ganho_cents', j.ganho_cents,
               'compensacao_cents', j.compensacao_cents, 'gorjetas_online_cents', j.gorjetas_online_cents,
               'dinheiro_em_mao_cents', j.dinheiro_em_mao_cents, 'online_cents', j.online_cents)
             order by j.ride_kind, j.ganho_cents desc), '[]'::jsonb))
    into v_out from juntos j;
  return v_out;
end $$;
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
    'painel_demo', (select jsonb_agg(l) from jsonb_array_elements(v_ac->'linhas') l where l->>'driver_id' = c_drv::text))::text;
end $t$;