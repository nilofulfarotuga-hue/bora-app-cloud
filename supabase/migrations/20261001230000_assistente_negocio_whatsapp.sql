-- Assistente de Negocio no WhatsApp ("funcionario digital") — multi-cliente.
-- Missao 2026-10-01. Primeiro cliente: Barbearia Mister Navalha, em modo teste.
-- Nao toca em dinheiro: as marcacoes do assistente sao pagas na barbearia
-- (deposit_status='waived', sem cobranca na app), como as marcacoes ao balcao.

-- 1) Clientes do assistente (um por negocio)
create table if not exists public.assistant_tenants (
  id uuid primary key default gen_random_uuid(),
  slug text unique not null,
  nome text not null,
  provider_id text references public.service_providers(id),
  sessao text not null default 'vps-baileys:351937501673',
  mode text not null default 'desligado' check (mode in ('teste','ligado','desligado')),
  allowlist text[] not null default '{}',
  blocklist text[] not null default '{}',
  owner_number text,
  dono_destino text,
  knowledge jsonb not null default '{}'::jsonb,
  motor text not null default 'gemini-pago:gemini-3-flash-preview',
  motores_reserva text[] not null default array['gemini:gemini-3-flash-preview','groq:openai/gpt-oss-120b','gemini:gemini-3.1-flash-lite'],
  orcamento_mensal_eur numeric(10,2) not null default 5,
  aviso_orcamento_mes text,
  tom text,
  link_avaliacao text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

-- 2) Memoria por contacto
create table if not exists public.assistant_contacts (
  tenant_id uuid not null references public.assistant_tenants(id) on delete cascade,
  numero text not null,
  nome text,
  ultimo_servico text,
  ultima_visita timestamptz,
  a_espera_de jsonb,
  historico jsonb not null default '[]'::jsonb,
  silenciado_ate timestamptz,
  silenciado_motivo text,
  pessoal boolean not null default false,
  reativacao_enviada_em timestamptz,
  ultima_msg_em timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  primary key (tenant_id, numero)
);

-- 3) Conversas (entrada e saida) + fila de saida (direcao='saida', entrega_estado='pendente')
create table if not exists public.assistant_messages (
  id bigserial primary key,
  tenant_id uuid not null references public.assistant_tenants(id) on delete cascade,
  numero text not null,
  direcao text not null check (direcao in ('entrada','saida')),
  texto text,
  motivo text,
  decisao text,
  modelo text,
  ferramentas jsonb,
  tokens_in integer,
  tokens_out integer,
  custo_eur numeric(10,6) not null default 0,
  latencia_ms integer,
  simulado boolean not null default false,
  msg_id_wa text,
  quoted_id text,
  entrega_estado text,
  entrega_erro text,
  enviada_em timestamptz,
  created_at timestamptz not null default now()
);
create index if not exists assistant_messages_fila on public.assistant_messages (created_at)
  where direcao = 'saida' and entrega_estado = 'pendente';
create index if not exists assistant_messages_conversa on public.assistant_messages (tenant_id, numero, created_at desc);
create index if not exists assistant_messages_mes on public.assistant_messages (tenant_id, created_at);

-- 4) Tarefas com prazo (perguntas ao dono, lembretes, avaliacoes, reativacao, lista de espera, resumo)
create table if not exists public.assistant_tasks (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.assistant_tenants(id) on delete cascade,
  numero text,
  tipo text not null check (tipo in ('pergunta_dono','passar_dono','lembrete','avaliacao','reativacao','lista_espera','resumo_semanal')),
  codigo text,
  pergunta text,
  resposta text,
  payload jsonb not null default '{}'::jsonb,
  prazo timestamptz,
  estado text not null default 'aberta' check (estado in ('aberta','cumprida','expirada','cancelada')),
  tentativas integer not null default 0,
  msg_id_wa text,
  simulado boolean not null default false,
  created_at timestamptz not null default now(),
  cumprida_em timestamptz
);
create index if not exists assistant_tasks_abertas on public.assistant_tasks (tenant_id, tipo, prazo) where estado = 'aberta';

-- 5) Marcacoes: de onde vieram, se sao de teste, e o que o assistente ja mandou
alter table public.appointments
  add column if not exists origem text,
  add column if not exists is_test boolean not null default false,
  add column if not exists assistant_tenant_id uuid references public.assistant_tenants(id),
  add column if not exists assistant_reminder_sent_at timestamptz,
  add column if not exists assistant_review_sent_at timestamptz;

-- 6) RLS: so admin (o servico do assistente usa a service role)
alter table public.assistant_tenants enable row level security;
alter table public.assistant_contacts enable row level security;
alter table public.assistant_messages enable row level security;
alter table public.assistant_tasks enable row level security;

create policy assistant_tenants_admin on public.assistant_tenants for all to authenticated using (public.is_admin()) with check (public.is_admin());
create policy assistant_contacts_admin on public.assistant_contacts for all to authenticated using (public.is_admin()) with check (public.is_admin());
create policy assistant_messages_admin on public.assistant_messages for all to authenticated using (public.is_admin()) with check (public.is_admin());
create policy assistant_tasks_admin on public.assistant_tasks for all to authenticated using (public.is_admin()) with check (public.is_admin());

-- 7) Vagas: a MESMA logica da app (get_available_slots) para cada profissional ativo
create or replace function public.assistente_vagas(p_tenant uuid, p_servico_id text, p_dia date)
returns table(slot_start timestamptz, staff_id text)
language plpgsql stable security definer set search_path to 'public'
as $$
declare v_prov text; v_staff record;
begin
  select provider_id into v_prov from assistant_tenants where id = p_tenant;
  if v_prov is null then raise exception 'tenant_sem_negocio'; end if;
  if not exists (select 1 from provider_services where id = p_servico_id and provider_id = v_prov and is_active) then
    raise exception 'servico_invalido';
  end if;
  for v_staff in select id from staff_members where provider_id = v_prov and is_active order by sort_order, created_at loop
    return query select s.slot_start, v_staff.id from public.get_available_slots(v_staff.id, p_servico_id, p_dia) s;
  end loop;
end $$;

-- 8) Marcar: confirma a vaga com a mesma funcao da app, tranca o profissional, cria a marcacao
create or replace function public.assistente_marcar(p_tenant uuid, p_servico_id text, p_inicio timestamptz,
  p_nome text, p_telefone text, p_teste boolean default false)
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
      begin
        perform public._appt_notify_partner(v_t.provider_id, 'appointment_new', 'Marcação nova pelo WhatsApp',
          v_svc.name || ' · ' || coalesce(nullif(trim(p_nome),''),'cliente') || ' · ' || v_quando, v_id::text);
      exception when others then null; end;
      return jsonb_build_object('ok', true, 'appointment_id', v_id, 'staff_id', v_staff, 'servico', v_svc.name,
        'inicio', p_inicio, 'duracao_min', v_svc.duration_minutes, 'preco_cents', v_svc.price_cents);
    end if;
  end loop;
  return jsonb_build_object('ok', false, 'erro', 'vaga_indisponivel');
end $$;

-- 9) Marcacoes futuras de um telefone (so as feitas pelo assistente deste negocio)
create or replace function public.assistente_minhas_marcacoes(p_tenant uuid, p_telefone text)
returns table(appointment_id uuid, servico text, inicio timestamptz, estado text)
language sql stable security definer set search_path to 'public'
as $$
  select a.id, ps.name, a.scheduled_at, a.status
    from appointments a join provider_services ps on ps.id = a.service_id
   where a.assistant_tenant_id = p_tenant
     and regexp_replace(coalesce(a.client_phone,''), '\D', '', 'g') = regexp_replace(coalesce(p_telefone,''), '\D', '', 'g')
     and a.status = 'confirmed' and a.scheduled_at > now()
   order by a.scheduled_at
$$;

-- 10) Desmarcar: so a do proprio telefone, so marcacoes do assistente (sem dinheiro envolvido)
create or replace function public.assistente_desmarcar(p_tenant uuid, p_appointment_id uuid, p_telefone text)
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
  begin
    perform public._appt_notify_partner(v_a.provider_id, 'appointment_cancelled', 'Marcação desmarcada (WhatsApp)',
      v_a.servico || ' · ' || coalesce(v_a.client_name,'cliente') || ' · ' || to_char(v_a.scheduled_at at time zone 'Europe/Lisbon','DD/MM HH24:MI'),
      p_appointment_id::text);
  exception when others then null; end;
  return jsonb_build_object('ok', true, 'appointment_id', p_appointment_id, 'servico', v_a.servico, 'inicio', v_a.scheduled_at,
    'service_id', v_a.service_id);
end $$;

-- 11) Remarcar: a nova hora tem de ser uma vaga real (mesma funcao da app)
create or replace function public.assistente_remarcar(p_tenant uuid, p_appointment_id uuid, p_telefone text, p_novo_inicio timestamptz)
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
      begin
        perform public._appt_notify_partner(v_a.provider_id, 'appointment_rescheduled', 'Marcação remarcada (WhatsApp)',
          v_a.servico || ' · ' || coalesce(v_a.client_name,'cliente') || ' · passou para ' || to_char(p_novo_inicio at time zone 'Europe/Lisbon','DD/MM HH24:MI'),
          v_a.id::text);
      exception when others then null; end;
      return jsonb_build_object('ok', true, 'appointment_id', v_a.id, 'servico', v_a.servico,
        'de', v_antigo, 'para', p_novo_inicio, 'service_id', v_a.service_id);
    end if;
  end loop;
  return jsonb_build_object('ok', false, 'erro', 'vaga_indisponivel');
end $$;

-- 12) Painel: limpar as marcacoes de teste (cancela; nunca apaga) + resumo por cliente
create or replace function public.admin_assistente_limpar_testes(p_tenant uuid default null)
returns jsonb
language plpgsql security definer set search_path to 'public'
as $$
declare v_n int; v_t int;
begin
  if not (public.is_admin() or coalesce(auth.role(),'') = 'service_role') then raise exception 'so_admin'; end if;
  update appointments set status = 'cancelled', cancelled_at = now(), cancelled_by = 'admin',
         cancel_reason = 'Marcação de teste do assistente — limpa'
   where is_test and status not in ('cancelled')
     and (p_tenant is null or assistant_tenant_id = p_tenant);
  get diagnostics v_n = row_count;
  update assistant_tasks set estado = 'cancelada' where simulado and estado = 'aberta'
     and (p_tenant is null or tenant_id = p_tenant);
  get diagnostics v_t = row_count;
  return jsonb_build_object('ok', true, 'marcacoes_canceladas', v_n, 'tarefas_canceladas', v_t);
end $$;

create or replace function public.admin_assistente_resumo()
returns table(tenant_id uuid, nome text, mode text, custo_mes_eur numeric, orcamento_eur numeric,
  mensagens_mes bigint, conversas_mes bigint, marcacoes_mes bigint, marcacoes_teste_ativas bigint, tarefas_abertas bigint)
language plpgsql stable security definer set search_path to 'public'
as $$
begin
  if not (public.is_admin() or coalesce(auth.role(),'') = 'service_role') then raise exception 'so_admin'; end if;
  return query
  select t.id, t.nome, t.mode,
    coalesce((select sum(m.custo_eur) from assistant_messages m where m.tenant_id = t.id and m.created_at >= date_trunc('month', now())), 0)::numeric,
    t.orcamento_mensal_eur,
    (select count(*) from assistant_messages m where m.tenant_id = t.id and m.created_at >= date_trunc('month', now())),
    (select count(distinct m.numero) from assistant_messages m where m.tenant_id = t.id and m.created_at >= date_trunc('month', now())),
    (select count(*) from appointments a where a.assistant_tenant_id = t.id and a.created_at >= date_trunc('month', now())),
    (select count(*) from appointments a where a.assistant_tenant_id = t.id and a.is_test and a.status <> 'cancelled'),
    (select count(*) from assistant_tasks k where k.tenant_id = t.id and k.estado = 'aberta')
  from assistant_tenants t order by t.created_at;
end $$;

-- 13) O aviso ao admin passa a dizer "pelo WhatsApp" quando a marcacao veio do assistente
create or replace function public.notify_new_appointment_admin()
 returns trigger
 language plpgsql
 security definer
 set search_path to 'public'
as $function$
declare
  v_loja    text;
  v_servico text;
  v_cliente text;
  v_preco   numeric;
  v_quando  text;
  v_tipo    text;
  v_resumo  text;
begin
  if coalesce(NEW.status, '') = 'blocked' then
    return NEW;
  end if;

  select name into v_loja from public.service_providers where id = NEW.provider_id;
  v_loja := coalesce(v_loja, 'parceiro');

  select name into v_servico from public.provider_services where id = NEW.service_id;
  v_servico := coalesce(v_servico, 'servico');

  v_cliente := coalesce(nullif(trim(NEW.client_name), ''), 'cliente sem nome');
  v_preco   := coalesce(NEW.service_price_cents, 0) / 100.0;
  v_quando  := to_char(NEW.scheduled_at at time zone 'Europe/Lisbon', 'DD/MM HH24:MI');
  v_tipo    := case when coalesce(NEW.origem, '') = 'whatsapp' then 'pelo WhatsApp' || case when NEW.is_test then ' (TESTE)' else '' end
                    when coalesce(NEW.is_walk_in, false) then 'ao balcao' else 'pela app' end;

  v_resumo := 'MARCACAO NOVA · ' || v_loja
              || ' · ' || v_servico
              || ' · ' || v_cliente
              || case when coalesce(NEW.client_phone, '') <> ''
                      then ' (' || NEW.client_phone || ')' else '' end
              || ' · ' || to_char(v_preco, 'FM999999990.00') || ' EUR'
              || ' · ' || v_quando
              || ' · ' || v_tipo
              || ' · #' || left(NEW.id::text, 8);

  begin
    perform public.notify_admin_urgent_push(
      'new_appointment', v_resumo, 'appointment', NEW.id::text,
      jsonb_build_object(
        'appointment_id', NEW.id,
        'provider_id',    NEW.provider_id,
        'service',        v_servico,
        'client_name',    NEW.client_name,
        'client_phone',   NEW.client_phone,
        'price_eur',      v_preco,
        'scheduled_at',   NEW.scheduled_at,
        'is_walk_in',     NEW.is_walk_in
      ),
      '/admin/appointments'
    );
  exception when others then
    raise notice 'notify_new_appointment_admin erro: %', sqlerrm;
  end;

  return NEW;
end;
$function$;

-- 14) Permissoes: as funcoes do assistente so para a service role; as de painel para admin autenticado
revoke all on function public.assistente_vagas(uuid, text, date) from public, anon, authenticated;
revoke all on function public.assistente_marcar(uuid, text, timestamptz, text, text, boolean) from public, anon, authenticated;
revoke all on function public.assistente_minhas_marcacoes(uuid, text) from public, anon, authenticated;
revoke all on function public.assistente_desmarcar(uuid, uuid, text) from public, anon, authenticated;
revoke all on function public.assistente_remarcar(uuid, uuid, text, timestamptz) from public, anon, authenticated;
grant execute on function public.assistente_vagas(uuid, text, date) to service_role;
grant execute on function public.assistente_marcar(uuid, text, timestamptz, text, text, boolean) to service_role;
grant execute on function public.assistente_minhas_marcacoes(uuid, text) to service_role;
grant execute on function public.assistente_desmarcar(uuid, uuid, text) to service_role;
grant execute on function public.assistente_remarcar(uuid, uuid, text, timestamptz) to service_role;
revoke all on function public.admin_assistente_limpar_testes(uuid) from public, anon;
revoke all on function public.admin_assistente_resumo() from public, anon;
grant execute on function public.admin_assistente_limpar_testes(uuid) to authenticated, service_role;
grant execute on function public.admin_assistente_resumo() to authenticated, service_role;

-- 15) Primeiro cliente: Barbearia Mister Navalha, em modo teste
insert into public.assistant_tenants (slug, nome, provider_id, sessao, mode, allowlist, blocklist, owner_number, dono_destino, tom, knowledge)
values ('mister-navalha', 'Barbearia Mister Navalha', '553a0d77-30ff-4f51-b148-59cb1264cfa1', 'vps-baileys:351937501673', 'teste',
  array['351931992662','351937472634'], '{}', '351937472634', '351931992662',
  'Português de Portugal, curto e simpático, como um bom recepcionista de barbearia. Trata por "você" ou sem tratamento; nunca "senhor/senhora" a quem não conhece. Sem emojis em excesso (no máximo um).',
  jsonb_build_object(
    'ficha', jsonb_build_object(
      'nome', 'Barbearia Mister Navalha',
      'dono', 'Ernando Silva',
      'morada', 'R. António Sérgio 20, bloco F, 6300-665 Guarda',
      'telefone', '937 472 634',
      'instagram', '@barbearia_mister_navalha__',
      'site', 'https://misternavalha.boraguarda.com',
      'pagamento', 'Paga-se na barbearia, no fim do serviço.',
      'notas', jsonb_build_array(
        'O degradê está incluído no Corte (não é serviço à parte).',
        'Freestyle, desenhos, madeixas, coloração e descontos: só o Ernando decide — passar ao dono.',
        'Corte infantil tem o mesmo preço do Corte.'
      )
    ),
    'perguntas_aprendidas', '[]'::jsonb
  ))
on conflict (slug) do nothing;
