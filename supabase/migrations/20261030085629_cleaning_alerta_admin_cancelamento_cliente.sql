-- 30/10/2026 (autorizado pelo Danilo: "Eu autorizo."): o Danilo só soube pela limpadora (Mayra) que o
-- cliente cancelou a limpeza de 31/10. cancel_cleaning_booking avisa a profissional pela app, mas não
-- avisava o admin. Agora, quando o cliente cancela (ou a profissional marca "cliente não apareceu"),
-- o admin recebe o mesmo aviso persistente da limpeza nova (push + Telegram + caixa do painel).
-- (Aplicada em produção a 30/10/2026 pela Claude.ai via MCP — versão 20261030085629; espelho no repo
--  escrito a 01/11/2026 na missão zona-vermelha-2026-11-01, SQL lido de schema_migrations.statements.)

create or replace function public._alerta_txt_limpeza_cancelada(b cleaning_bookings)
returns text
language plpgsql
stable
set search_path to 'public'
as $function$
declare
  v_prof  text;
  v_serie text := '';
  v_motivo text;
begin
  if b.cleaner_id is not null then
    select name into v_prof from cleaners where id = b.cleaner_id;
  end if;

  if b.recurrence_group_id is not null and b.recurrence in ('weekly', 'biweekly') then
    v_serie := E'\nSérie ' || case b.recurrence when 'weekly' then 'semanal' else 'de 15 em 15 dias' end || ': ';
    if b.cancel_reason = 'serie_terminada'
       or exists (select 1 from cleaning_recurrence_stops s where s.group_id = b.recurrence_group_id) then
      v_serie := v_serie || 'o cliente terminou a série';
    elsif b.cancelled_by = 'client'
       and not exists (select 1 from cleaning_bookings b2
                       where b2.recurrence_group_id = b.recurrence_group_id
                         and b2.scheduled_at > b.scheduled_at) then
      -- generate_recurring_bookings não cria a seguinte quando a última foi cancelada pelo cliente
      v_serie := v_serie || 'acaba aqui, não se cria a próxima';
    else
      v_serie := v_serie || 'as seguintes continuam';
    end if;
  end if;

  v_motivo := case b.cancel_reason
                when 'serie_terminada' then 'terminou a série'
                when 'no_show_cliente' then 'cliente não estava em casa'
                else b.cancel_reason end;

  return case when coalesce(b.no_show_client, false)
              then '🚫 LIMPEZA — CLIENTE NÃO APARECEU — '
              else '❌ LIMPEZA CANCELADA PELO CLIENTE — ' end
      || public._alerta_quem(b.client_user_id)
      || E'\nEra: '    || public._alerta_quando(b.scheduled_at)
      || E'\nMorada: ' || btrim(coalesce(b.address_street, '') || ' ' || coalesce(b.address_city, ''))
      || E'\nProfissional: ' || case when coalesce(b.no_show_client, false)
                                     then coalesce(v_prof, '?')
                                     else coalesce(v_prof || ' (já foi avisada pela app)', 'nenhuma atribuída') end
      || E'\nMotivo: ' || coalesce(nullif(btrim(v_motivo), ''), 'não disse')
      || E'\nTaxa: '   || case when coalesce(b.cancel_fee_cents, 0) > 0
                              then to_char(b.cancel_fee_cents / 100.0, 'FM999990.00') || ' EUR'
                              else 'nenhuma' end
      || v_serie
      || E'\n#' || left(b.id::text, 8);
end
$function$;

create or replace function public._trg_cleaning_notify_admin_cancel()
returns trigger
language plpgsql
security definer
set search_path to 'public'
as $function$
declare
  v_resumo text;
begin
  if coalesce(new.is_test_order, false) then return null; end if;

  begin
    v_resumo := public._alerta_txt_limpeza_cancelada(new);
  exception when others then
    v_resumo := null;
  end;
  v_resumo := coalesce(v_resumo, '❌ LIMPEZA CANCELADA PELO CLIENTE · #' || left(new.id::text, 8));

  -- best-effort: nunca impede o cancelamento
  begin
    perform public.notify_admin_urgent_push(
      'cleaning_booking_cancelled', v_resumo, 'cleaning_booking', new.id::text,
      jsonb_build_object(
        'booking_id', new.id, 'client_user_id', new.client_user_id,
        'cleaner_id', new.cleaner_id, 'scheduled_at', new.scheduled_at,
        'cancelled_by', new.cancelled_by, 'cancel_reason', new.cancel_reason,
        'cancel_fee_cents', new.cancel_fee_cents, 'no_show_client', new.no_show_client,
        'recurrence', new.recurrence, 'recurrence_group_id', new.recurrence_group_id),
      '/admin/limpeza/' || new.id::text);
  exception when others then
    raise notice 'cleaning cancel notify admin falhou: %', sqlerrm;
  end;

  return null;
end
$function$;

drop trigger if exists trg_cleaning_notify_admin_cancel on public.cleaning_bookings;
create trigger trg_cleaning_notify_admin_cancel
  after update of status on public.cleaning_bookings
  for each row
  when (new.status like 'cancelled%'
        and old.status is distinct from new.status
        and new.cancelled_by in ('client', 'cleaner'))
  execute function public._trg_cleaning_notify_admin_cancel();

revoke execute on function public._alerta_txt_limpeza_cancelada(cleaning_bookings) from public, anon, authenticated;
revoke execute on function public._trg_cleaning_notify_admin_cancel() from public, anon, authenticated;
