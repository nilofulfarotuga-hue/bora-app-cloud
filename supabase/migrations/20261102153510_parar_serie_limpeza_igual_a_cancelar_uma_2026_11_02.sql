-- Missão zerar-2026-11-02, B2 (autorização do Danilo 02/11/2026 14:46, item 3). "Parar a série toda"
-- usa o caminho de cancelar uma limpeza só: cancel_cleaning_booking por limpeza (mesma taxa, mesmo
-- estado do pagamento, mesmo aviso) e a app faz o mesmo 'reverse' do cleaning-checkout. Sem valores novos.
-- Aplicada em produção pelo MCP a 02/11/2026 (schema_migrations 20261102153510); prova em rollback
-- no e2e_log (fluxo zerar-2026-11-02, passo B2-serie-limpeza-servidor).
create or replace function public.cancel_cleaning_series(p_group_id uuid)
returns integer language plpgsql security definer set search_path to 'public'
as $function$
declare
  v_uid uuid := auth.uid();
  v_count int := 0;
  v_free int := public._cleaning_setting_int('cleaning_cancel_free_hours', 24);
  v_rec record;
begin
  if not exists (select 1 from cleaning_bookings
                 where recurrence_group_id = p_group_id and client_user_id = v_uid) then
    raise exception 'series_not_yours';
  end if;
  insert into cleaning_recurrence_stops (group_id, stopped_by)
  values (p_group_id, v_uid)
  on conflict (group_id) do nothing;
  for v_rec in
    select id from cleaning_bookings
    where recurrence_group_id = p_group_id
      and client_user_id = v_uid
      and status in ('scheduled', 'accepted')
      and scheduled_at > now() + make_interval(hours => v_free)
    order by scheduled_at
  loop
    begin
      -- O mesmo cancelamento de uma limpeza só (taxa, estado do pagamento, aviso à profissional).
      perform public.cancel_cleaning_booking(v_rec.id, 'serie_terminada', false);
      v_count := v_count + 1;
    exception when others then
      -- Uma limpeza que mudou de estado entretanto não trava o resto da série.
      raise warning 'cancel_cleaning_series: % saltada (%)', v_rec.id, sqlerrm;
    end;
  end loop;
  return v_count;
end
$function$;

-- Só leitura: o que "Parar a série toda" vai cancelar e quanto volta (mesma conta da taxa do
-- cancel_cleaning_booking para o cliente). pago = cobrada na reserva (payment_status 'held').
create or replace function public.cleaning_series_preview(p_group_id uuid)
returns jsonb language plpgsql stable security definer set search_path to 'public'
as $function$
declare
  v_uid uuid := auth.uid();
  v_free int := public._cleaning_setting_int('cleaning_cancel_free_hours', 24);
  v_half int := public._cleaning_setting_int('cleaning_cancel_half_hours', 2);
  v_grace int := public._cleaning_setting_int('cleaning_cancel_grace_minutes', 5);
  v_lista jsonb;
begin
  if v_uid is null or not exists (select 1 from cleaning_bookings
                 where recurrence_group_id = p_group_id and client_user_id = v_uid) then
    raise exception 'series_not_yours';
  end if;
  with alvo as (
    select b.id, b.scheduled_at, b.total_cents, b.payment_method, b.payment_status,
           (b.payment_status = 'held') as pago,
           case
             when extract(epoch from (b.scheduled_at - now())) / 3600.0 >= v_free
                  or now() - b.created_at <= make_interval(mins => v_grace) then 0
             when extract(epoch from (b.scheduled_at - now())) / 3600.0 >= v_half
                  then round(b.total_cents * 0.5)::int
             else b.total_cents
           end as taxa_cents
    from cleaning_bookings b
    where b.recurrence_group_id = p_group_id
      and b.client_user_id = v_uid
      and b.status in ('scheduled', 'accepted')
      and b.scheduled_at > now() + make_interval(hours => v_free)
  )
  select coalesce(jsonb_agg(jsonb_build_object(
           'id', id, 'scheduled_at', scheduled_at, 'total_cents', total_cents,
           'payment_method', payment_method, 'pago', pago, 'taxa_cents', taxa_cents,
           'devolve_cents', case when pago then greatest(total_cents - taxa_cents, 0) else 0 end
         ) order by scheduled_at), '[]'::jsonb)
    into v_lista
  from alvo;
  return jsonb_build_object(
    'n', jsonb_array_length(v_lista),
    'devolve_cents', coalesce((select sum((x->>'devolve_cents')::int) from jsonb_array_elements(v_lista) x), 0),
    'limpezas', v_lista);
end
$function$;

grant execute on function public.cleaning_series_preview(uuid) to authenticated;
