-- Assistente de Negocio — verificacao adversarial 01/10 + adendo 2 (audios). Nada e removido:
-- (a) funcoes _v2 com p_notificar (simulacao nao avisa o parceiro) e aviso "TESTE ·" nos testes reais;
--     as versoes antigas ficam no ar, sem uso;
-- (b) a limpeza de testes nao reescreve marcacoes ja concluidas pelo parceiro;
-- (c) assistant_messages.media_path: nota de voz (ogg/opus) a enviar pela porta.
alter table public.assistant_messages add column if not exists media_path text;

create or replace function public.assistente_marcar_v2(p_tenant uuid, p_servico_id text, p_inicio timestamptz,
  p_nome text, p_telefone text, p_teste boolean default false, p_notificar boolean default true)
returns jsonb
language plpgsql security definer set search_path to 'public'
as $$
declare v_t record; v_svc record; v_staff text; v_id uuid; v_quando text;
begin
  select * into v_t from assistant_tenants where id = p_tenant;
  if v_t is null or v_t.provider_id is null then raise exception 'tenant_sem_negocio'; end if;
  select id, name, duration_minutes, price_cents into v_svc from provider_services
    where id = p_servico_id and provider_id = v_t.provider_id and is_active;
  if v_svc is null then raise exception 'servico_invalido'; end if;
  if coalesce(trim(p_telefone),'') = '' then raise exception 'telefone_em_falta'; end if;
  for v_staff in select id from staff_members where provider_id = v_t.provider_id and is_active order by sort_order, created_at loop
    perform pg_advisory_xact_lock(hashtext('appt-staff:' || v_staff));
    if exists (select 1 from public.get_available_slots(v_staff, p_servico_id, (p_inicio at time zone 'Europe/Lisbon')::date) s
               where s.slot_start = p_inicio) then
      insert into appointments(provider_id, staff_id, service_id, client_user_id, client_name, client_phone,
        scheduled_at, duration_minutes, service_price_cents, deposit_cents, deposit_status, status,
        is_walk_in, client_notes, origem, is_test, assistant_tenant_id, confirmed_at)
      values (v_t.provider_id, v_staff, p_servico_id, null, coalesce(nullif(trim(p_nome),''),'Cliente WhatsApp'), p_telefone,
        p_inicio, v_svc.duration_minutes, v_svc.price_cents, 0, 'waived', 'confirmed',
        true, 'Marcado pelo WhatsApp (assistente). Paga na barbearia.' || case when p_teste then ' [TESTE]' else '' end,
        'whatsapp', coalesce(p_teste,false), p_tenant, now())
      returning id into v_id;
      v_quando := to_char(p_inicio at time zone 'Europe/Lisbon', 'DD/MM HH24:MI');
      if coalesce(p_notificar, true) then
        begin
          perform public._appt_notify_partner(v_t.provider_id, 'appointment_new',
            case when p_teste then 'TESTE · ' else '' end || 'Marcação nova pelo WhatsApp',
            v_svc.name || ' · ' || coalesce(nullif(trim(p_nome),''),'cliente') || ' · ' || v_quando, v_id::text);
        exception when others then null; end;
      end if;
      return jsonb_build_object('ok', true, 'appointment_id', v_id, 'staff_id', v_staff, 'servico', v_svc.name,
        'inicio', p_inicio, 'duracao_min', v_svc.duration_minutes, 'preco_cents', v_svc.price_cents);
    end if;
  end loop;
  return jsonb_build_object('ok', false, 'erro', 'vaga_indisponivel');
end $$;

create or replace function public.assistente_desmarcar_v2(p_tenant uuid, p_appointment_id uuid, p_telefone text,
  p_notificar boolean default true)
returns jsonb
language plpgsql security definer set search_path to 'public'
as $$
declare v_a record;
begin
  select a.*, ps.name as servico into v_a from appointments a join provider_services ps on ps.id = a.service_id
   where a.id = p_appointment_id and a.assistant_tenant_id = p_tenant;
  if v_a is null then return jsonb_build_object('ok', false, 'erro', 'marcacao_nao_encontrada'); end if;
  if regexp_replace(coalesce(v_a.client_phone,''), '\D', '', 'g') <> regexp_replace(coalesce(p_telefone,''), '\D', '', 'g') then
    return jsonb_build_object('ok', false, 'erro', 'nao_e_sua');
  end if;
  if v_a.status <> 'confirmed' then return jsonb_build_object('ok', false, 'erro', 'ja_nao_esta_ativa'); end if;
  update appointments set status = 'cancelled', cancelled_at = now(), cancelled_by = 'client',
         cancel_reason = 'Desmarcado pelo cliente no WhatsApp'
   where id = p_appointment_id and status = 'confirmed';
  if coalesce(p_notificar, true) then
    begin
      perform public._appt_notify_partner(v_a.provider_id, 'appointment_cancelled',
        case when v_a.is_test then 'TESTE · ' else '' end || 'Marcação desmarcada (WhatsApp)',
        v_a.servico || ' · ' || coalesce(v_a.client_name,'cliente') || ' · ' || to_char(v_a.scheduled_at at time zone 'Europe/Lisbon','DD/MM HH24:MI'),
        p_appointment_id::text);
    exception when others then null; end;
  end if;
  return jsonb_build_object('ok', true, 'appointment_id', p_appointment_id, 'servico', v_a.servico, 'inicio', v_a.scheduled_at,
    'service_id', v_a.service_id);
end $$;

create or replace function public.assistente_remarcar_v2(p_tenant uuid, p_appointment_id uuid, p_telefone text,
  p_novo_inicio timestamptz, p_notificar boolean default true)
returns jsonb
language plpgsql security definer set search_path to 'public'
as $$
declare v_a record; v_staff text; v_antigo timestamptz;
begin
  select a.*, ps.name as servico into v_a from appointments a join provider_services ps on ps.id = a.service_id
   where a.id = p_appointment_id and a.assistant_tenant_id = p_tenant;
  if v_a is null then return jsonb_build_object('ok', false, 'erro', 'marcacao_nao_encontrada'); end if;
  if regexp_replace(coalesce(v_a.client_phone,''), '\D', '', 'g') <> regexp_replace(coalesce(p_telefone,''), '\D', '', 'g') then
    return jsonb_build_object('ok', false, 'erro', 'nao_e_sua');
  end if;
  if v_a.status <> 'confirmed' then return jsonb_build_object('ok', false, 'erro', 'ja_nao_esta_ativa'); end if;
  v_antigo := v_a.scheduled_at;
  for v_staff in select id from staff_members where provider_id = v_a.provider_id and is_active
                 order by (id = v_a.staff_id) desc, sort_order, created_at loop
    perform pg_advisory_xact_lock(hashtext('appt-staff:' || v_staff));
    if exists (select 1 from public.get_available_slots(v_staff, v_a.service_id, (p_novo_inicio at time zone 'Europe/Lisbon')::date) s
               where s.slot_start = p_novo_inicio) then
      insert into appointment_reschedules(appointment_id, old_scheduled_at, new_scheduled_at, old_staff_id, new_staff_id, changed_by)
      values (v_a.id, v_antigo, p_novo_inicio, v_a.staff_id, v_staff, 'client');
      update appointments set scheduled_at = p_novo_inicio, staff_id = v_staff,
             original_scheduled_at = coalesce(original_scheduled_at, v_antigo),
             reschedule_count = reschedule_count + 1, last_rescheduled_at = now(),
             reminder_24h_sent_at = null, reminder_2h_sent_at = null, assistant_reminder_sent_at = null
       where id = v_a.id;
      if coalesce(p_notificar, true) then
        begin
          perform public._appt_notify_partner(v_a.provider_id, 'appointment_rescheduled',
            case when v_a.is_test then 'TESTE · ' else '' end || 'Marcação remarcada (WhatsApp)',
            v_a.servico || ' · ' || coalesce(v_a.client_name,'cliente') || ' · passou para ' || to_char(p_novo_inicio at time zone 'Europe/Lisbon','DD/MM HH24:MI'),
            v_a.id::text);
        exception when others then null; end;
      end if;
      return jsonb_build_object('ok', true, 'appointment_id', v_a.id, 'servico', v_a.servico,
        'de', v_antigo, 'para', p_novo_inicio, 'service_id', v_a.service_id);
    end if;
  end loop;
  return jsonb_build_object('ok', false, 'erro', 'vaga_indisponivel');
end $$;

create or replace function public.admin_assistente_limpar_testes(p_tenant uuid default null)
returns jsonb
language plpgsql security definer set search_path to 'public'
as $$
declare v_n int; v_t int;
begin
  if not (public.is_admin() or coalesce(auth.role(),'') = 'service_role') then raise exception 'so_admin'; end if;
  update appointments set status = 'cancelled', cancelled_at = now(), cancelled_by = 'admin',
         cancel_reason = 'Marcação de teste do assistente — limpa'
   where is_test and status in ('confirmed', 'pending_payment', 'awaiting_confirmation')
     and (p_tenant is null or assistant_tenant_id = p_tenant);
  get diagnostics v_n = row_count;
  update assistant_tasks set estado = 'cancelada' where simulado and estado = 'aberta'
     and (p_tenant is null or tenant_id = p_tenant);
  get diagnostics v_t = row_count;
  return jsonb_build_object('ok', true, 'marcacoes_canceladas', v_n, 'tarefas_canceladas', v_t);
end $$;

revoke all on function public.assistente_marcar_v2(uuid, text, timestamptz, text, text, boolean, boolean) from public, anon, authenticated;
revoke all on function public.assistente_desmarcar_v2(uuid, uuid, text, boolean) from public, anon, authenticated;
revoke all on function public.assistente_remarcar_v2(uuid, uuid, text, timestamptz, boolean) from public, anon, authenticated;
grant execute on function public.assistente_marcar_v2(uuid, text, timestamptz, text, text, boolean, boolean) to service_role;
grant execute on function public.assistente_desmarcar_v2(uuid, uuid, text, boolean) to service_role;
grant execute on function public.assistente_remarcar_v2(uuid, uuid, text, timestamptz, boolean) to service_role;
