-- 2026-10-21 · fechar-pendencias-2026-10-20 · BLOCO A1 · RONDA 1 do revisor (ponto 4)
-- Painel "Acertos por tipo" (só leitura): passa a somar as GORJETAS ONLINE das
-- corridas/encomendas, como o acerto real soma (compute_driver_settlement →
-- gorjetas_online_do_prestador: tips succeeded, card/mbway, paid_at na semana).
-- Aqui só as gorjetas ligadas a uma corrida do Bora Motorista (tips.tvde_ride_id),
-- partidas pelo tipo dessa corrida. Nenhuma função de dinheiro muda.

create or replace function public.admin_tvde_acertos_por_tipo(p_week_start timestamptz default null)
returns jsonb
language plpgsql
security definer
set search_path to 'public'
as $$
declare v_admin record; v_b record; v_out jsonb;
begin
  select admin_id into v_admin from public._admin_op_guard();
  select * into v_b from public.driver_settlement_week_bounds(coalesce(p_week_start, now()));

  with corridas as (
    select r.driver_id, r.ride_kind,
           count(*)                                              as corridas,
           coalesce(sum(coalesce(r.driver_earn_cents, 0)), 0)    as ganho_cents,
           coalesce(sum(coalesce(r.cash_in_hand_cents, 0)), 0)   as dinheiro_em_mao_cents,
           coalesce(sum(case when r.payment_method in ('card','mbway')
                             then coalesce(r.final_fare_cents, r.est_fare_cents, 0) else 0 end), 0) as online_cents
      from public.tvde_rides r
     where r.status = 'finalizada'
       and r.driver_id is not null
       and r.created_at >= v_b.week_start and r.created_at <= v_b.week_end
     group by 1, 2
  ), comps as (
    select c.driver_id, coalesce(r.ride_kind, 'passageiros') as ride_kind,
           coalesce(sum(c.driver_cents), 0) as compensacao_cents
      from public.tvde_cancel_compensations c
      left join public.tvde_rides r on r.id = c.ride_id
     where c.created_at >= v_b.week_start and c.created_at <= v_b.week_end
     group by 1, 2
  ), gorjetas as (
    -- mesma regra de public.gorjetas_online_do_prestador, só as do Bora Motorista
    select t.provider_user_id as driver_id, coalesce(r.ride_kind, 'passageiros') as ride_kind,
           coalesce(sum(t.amount_cents), 0) as gorjetas_cents
      from public.tips t
      join public.tvde_rides r on r.id = t.tvde_ride_id
     where t.status = 'succeeded'
       and t.method in ('card', 'mbway')
       and t.paid_at >= v_b.week_start and t.paid_at <= v_b.week_end
     group by 1, 2
  ), chaves as (
    select driver_id, ride_kind from corridas
    union select driver_id, ride_kind from comps
    union select driver_id, ride_kind from gorjetas
  ), juntos as (
    select k.driver_id, k.ride_kind,
           coalesce(a.corridas, 0) as corridas,
           coalesce(a.ganho_cents, 0) + coalesce(b.compensacao_cents, 0) + coalesce(g.gorjetas_cents, 0) as ganho_cents,
           coalesce(a.dinheiro_em_mao_cents, 0) as dinheiro_em_mao_cents,
           coalesce(a.online_cents, 0) as online_cents,
           coalesce(b.compensacao_cents, 0) as compensacao_cents,
           coalesce(g.gorjetas_cents, 0) as gorjetas_online_cents
      from chaves k
      left join corridas a on a.driver_id = k.driver_id and a.ride_kind = k.ride_kind
      left join comps b    on b.driver_id = k.driver_id and b.ride_kind = k.ride_kind
      left join gorjetas g on g.driver_id = k.driver_id and g.ride_kind = k.ride_kind
  )
  select jsonb_build_object(
           'week_start', v_b.week_start,
           'week_end',   v_b.week_end,
           'linhas', coalesce(jsonb_agg(jsonb_build_object(
               'driver_id', j.driver_id,
               'driver_name', coalesce((select nullif(trim(d.name), '') from public.drivers d
                                         where d.user_id = j.driver_id limit 1), '(sem nome)'),
               'ride_kind', j.ride_kind,
               'corridas', j.corridas,
               'ganho_cents', j.ganho_cents,
               'compensacao_cents', j.compensacao_cents,
               'gorjetas_online_cents', j.gorjetas_online_cents,
               'dinheiro_em_mao_cents', j.dinheiro_em_mao_cents,
               'online_cents', j.online_cents)
             order by j.ride_kind, j.ganho_cents desc), '[]'::jsonb))
    into v_out
    from juntos j;
  return v_out;
end $$;
revoke all on function public.admin_tvde_acertos_por_tipo(timestamptz) from public, anon;
grant execute on function public.admin_tvde_acertos_por_tipo(timestamptz) to authenticated, service_role;
comment on function public.admin_tvde_acertos_por_tipo(timestamptz) is
  'Painel (só leitura): o acerto semanal do Bora Motorista partido por tipo (passageiros/encomendas). Mesma regra do compute_driver_settlement para a parte TVDE + as gorjetas online das corridas (gorjetas_online_do_prestador, só tips com tvde_ride_id). 21/10/2026 (A1, ronda 1).';
