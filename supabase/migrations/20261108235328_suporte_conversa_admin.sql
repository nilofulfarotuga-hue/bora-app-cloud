-- =============================================================================
-- SUPORTE: o aviso abre a conversa e o admin responde como pessoa
-- (adendo 1 da missão m4-amigo-bora-v1-2026-11-08, pedido do Danilo 08/11/2026 20:05)
--
-- Caso real: às 20:03 um cliente escreveu "falar com assistente" no suporte da app; o aviso
-- apontava para /admin/support-escalations, que só mostra sessões escaladas — e esta não era.
-- O Danilo tocou no aviso e não viu o que o cliente escreveu.
--
--   1. Os avisos do suporte (mensagem do cliente e pedido de ajuda vindo do chat) apontam para
--      a conversa: /admin/support/sessions/<session_id>. O push do telemóvel leva o mesmo link
--      (notify_admin_urgent_push manda o deep_link como "route"). Avisos antigos corrigidos,
--      com cópia antes.
--   2. Mensagens com papel 'admin' (a equipa Bora, escrita por uma pessoa) e sessões em modo
--      'admin' (o robô fica calado até o admin a devolver).
--   3. RPCs do painel (só admin): lista de TODAS as conversas com marca de não lida, a conversa
--      com o cliente (nome, telefone, email, últimos pedidos), responder e devolver ao robô.
--
-- Nunca aparece o nome de quem responde: ao cliente é sempre "Equipa Bora".
-- Idempotente.
-- =============================================================================

-- ─── 1. Papéis e modos novos ──────────────────────────────────────────────────
alter table public.support_chatbot_messages
  drop constraint if exists support_chatbot_messages_role_check;
alter table public.support_chatbot_messages
  add constraint support_chatbot_messages_role_check
  check (role = any (array['user', 'assistant', 'tool', 'system', 'admin']));

alter table public.support_chatbot_sessions
  drop constraint if exists support_chatbot_sessions_mode_check;
alter table public.support_chatbot_sessions
  add constraint support_chatbot_sessions_mode_check
  check (mode = any (array['ai', 'human_persona', 'admin']));

alter table public.support_chatbot_sessions add column if not exists admin_lida_em timestamptz;
alter table public.support_chatbot_sessions add column if not exists admin_assumiu_em timestamptz;
alter table public.support_chatbot_sessions add column if not exists admin_assumiu_por uuid;
alter table public.support_chatbot_sessions add column if not exists ultima_msg_em timestamptz;

-- Última mensagem (para ordenar a lista e marcar não lidas sem varrer as mensagens todas).
create or replace function public._support_sessao_ultima_msg()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if new.role in ('user', 'assistant', 'admin') then
    update public.support_chatbot_sessions
       set ultima_msg_em = greatest(coalesce(ultima_msg_em, new.created_at), new.created_at)
     where id = new.session_id;
  end if;
  return new;
end;
$$;

do $$
begin
  if not exists (select 1 from pg_trigger where tgname = 'trg_support_sessao_ultima_msg') then
    create trigger trg_support_sessao_ultima_msg
      after insert on public.support_chatbot_messages
      for each row execute function public._support_sessao_ultima_msg();
  end if;
end $$;

update public.support_chatbot_sessions s
   set ultima_msg_em = (select max(m.created_at) from public.support_chatbot_messages m
                         where m.session_id = s.id and m.role in ('user', 'assistant', 'admin'))
 where s.ultima_msg_em is null;

create index if not exists support_chatbot_sessions_ultima_idx
  on public.support_chatbot_sessions (ultima_msg_em desc nulls last);

-- ─── 2. Avisos apontam para a conversa ────────────────────────────────────────
create or replace function public.notify_support_user_message_admin()
returns trigger
language plpgsql
security definer
set search_path = public
as $function$
declare
  v_user uuid; v_nome text; v_tel text; v_resumo text;
begin
  if new.role is distinct from 'user' then return new; end if;

  select s.user_id into v_user from public.support_chatbot_sessions s where s.id = new.session_id;
  if v_user is null then return new; end if;
  if public.is_demo_user(v_user) then return new; end if;

  begin
    select u.name, u.phone into v_nome, v_tel from public.users u where u.id = v_user;
  exception when others then v_nome := null; v_tel := null;
  end;

  v_resumo := '💬 CLIENTE ESCREVEU AO SUPORTE · '
    || coalesce(nullif(v_nome, ''), 'cliente')
    || coalesce(' (' || nullif(v_tel, '') || ')', '')
    || ' · ' || left(coalesce(new.content, ''), 160);

  begin
    perform public.notify_admin_urgent_push(
      'support_user_message', v_resumo, 'support_session', new.session_id::text,
      jsonb_build_object('session_id', new.session_id, 'user_id', v_user,
        'client_name', v_nome, 'client_phone', v_tel, 'message', new.content),
      '/admin/support/sessions/' || new.session_id::text);
  exception when others then
    raise notice 'notify_support_user_message_admin erro: %', sqlerrm;
  end;
  return new;
end
$function$;

create or replace function public.notify_support_ticket_admin()
returns trigger
language plpgsql
security definer
set search_path = public
as $function$
declare
  v_nome text; v_tel text; v_resumo text;
begin
  if public.is_demo_user(new.user_id) then return new; end if;

  begin
    select u.name, u.phone into v_nome, v_tel from public.users u where u.id = new.user_id;
  exception when others then v_nome := null; v_tel := null;
  end;

  v_resumo := '🆘 PEDIDO DE AJUDA NOVO · '
    || coalesce(nullif(v_nome, ''), 'cliente')
    || coalesce(' (' || nullif(v_tel, '') || ')', '')
    || ' · ' || left(coalesce(nullif(new.subject, ''), nullif(new.question, ''), nullif(new.body, ''), 'sem texto'), 160);

  begin
    perform public.notify_admin_urgent_push(
      'support_ticket_new', v_resumo, 'support_ticket', new.id::text,
      jsonb_build_object('ticket_id', new.id, 'user_id', new.user_id, 'client_name', v_nome,
        'client_phone', v_tel, 'question', new.question, 'subject', new.subject, 'channel', new.channel,
        'session_id', new.session_id),
      -- Pedido vindo do chat: abre a conversa. Os outros continuam na lista de pedidos.
      case when new.session_id is not null then '/admin/support/sessions/' || new.session_id::text
           else '/admin/support' end);
  exception when others then
    raise notice 'notify_support_ticket_admin erro: %', sqlerrm;
  end;
  return new;
end
$function$;

-- Avisos antigos: cópia e link novo.
create table if not exists public.bkp_admin_notifications_suporte_20261108 as
  select * from public.admin_notifications
   where event_type in ('support_user_message', 'support_ticket_new');
alter table public.bkp_admin_notifications_suporte_20261108 enable row level security;

update public.admin_notifications
   set deep_link = '/admin/support/sessions/' || entity_id
 where event_type = 'support_user_message'
   and entity_type = 'support_session'
   and entity_id ~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
   and deep_link is distinct from '/admin/support/sessions/' || entity_id;

update public.admin_notifications n
   set deep_link = '/admin/support/sessions/' || t.session_id::text
  from public.support_tickets t
 where n.event_type = 'support_ticket_new'
   and n.entity_type = 'support_ticket'
   and n.entity_id = t.id::text
   and t.session_id is not null
   and n.deep_link is distinct from '/admin/support/sessions/' || t.session_id::text;

-- ─── 3. RPCs do painel ────────────────────────────────────────────────────────

-- Lista de TODAS as conversas, as mais recentes primeiro, com marca de não lida.
create or replace function public.admin_suporte_sessoes(p_limite integer default 100, p_so_nao_lidas boolean default false)
returns table (
  session_id uuid, user_id uuid, nome text, telefone text, papel text,
  iniciada_em timestamptz, ultima_msg_em timestamptz, ultima_msg text, ultima_msg_papel text,
  mensagens bigint, escalada boolean, modo text, nao_lida boolean, ticket_id uuid
)
language plpgsql
stable
security definer
set search_path = public
as $$
begin
  if not coalesce(public.is_admin(), false) then
    raise exception 'admin_required';
  end if;
  return query
  select s.id, s.user_id, u.name, u.phone, s.user_role,
         s.started_at, coalesce(s.ultima_msg_em, s.started_at), lm.content, lm.role,
         (select count(*) from public.support_chatbot_messages m
           where m.session_id = s.id and m.role in ('user', 'assistant', 'admin')),
         coalesce(s.escalated, false), s.mode,
         exists (select 1 from public.support_chatbot_messages m
                  where m.session_id = s.id and m.role = 'user'
                    and m.created_at > coalesce(s.admin_lida_em, '-infinity'::timestamptz)) as nao_lida,
         s.ticket_id
    from public.support_chatbot_sessions s
    left join public.users u on u.id = s.user_id
    left join lateral (
      select m.content, m.role from public.support_chatbot_messages m
       where m.session_id = s.id and m.role in ('user', 'assistant', 'admin')
       order by m.created_at desc limit 1) lm on true
   where (not coalesce(p_so_nao_lidas, false))
      or exists (select 1 from public.support_chatbot_messages m
                  where m.session_id = s.id and m.role = 'user'
                    and m.created_at > coalesce(s.admin_lida_em, '-infinity'::timestamptz))
   order by coalesce(s.ultima_msg_em, s.started_at) desc nulls last
   limit greatest(1, least(coalesce(p_limite, 100), 500));
end;
$$;

-- Uma conversa: cliente, mensagens (as de ferramenta só com o nome) e últimos pedidos.
-- Abrir marca como lida.
create or replace function public.admin_suporte_conversa(p_session_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_s public.support_chatbot_sessions%rowtype;
  v jsonb;
begin
  if not coalesce(public.is_admin(), false) then
    raise exception 'admin_required';
  end if;
  select * into v_s from public.support_chatbot_sessions where id = p_session_id;
  if v_s.id is null then
    return jsonb_build_object('ok', false, 'erro', 'conversa não encontrada');
  end if;
  update public.support_chatbot_sessions set admin_lida_em = now() where id = p_session_id;

  select jsonb_build_object(
    'ok', true,
    'sessao', jsonb_build_object(
      'id', v_s.id, 'iniciada_em', v_s.started_at, 'terminada_em', v_s.ended_at,
      'escalada', coalesce(v_s.escalated, false), 'motivo', v_s.escalation_reason,
      'modo', v_s.mode, 'papel', v_s.user_role, 'pedido_id', v_s.order_id,
      'ticket_id', v_s.ticket_id, 'admin_assumiu_em', v_s.admin_assumiu_em),
    'cliente', (select jsonb_build_object(
        'id', u.id, 'nome', u.name, 'telefone', u.phone,
        'email', coalesce((select au.email from auth.users au where au.id = v_s.user_id), null))
       from public.users u where u.id = v_s.user_id),
    'mensagens', coalesce((
        select jsonb_agg(jsonb_build_object(
                 'id', m.id, 'papel', m.role,
                 'texto', case when m.role = 'tool' then null else m.content end,
                 'ferramenta', m.tool_name, 'quando', m.created_at) order by m.created_at)
          from public.support_chatbot_messages m
         where m.session_id = p_session_id and m.role <> 'system'), '[]'::jsonb),
    'pedidos', coalesce((
        select jsonb_agg(x order by x.quando desc) from (
          select o.id, o.created_at as quando, o.status, o.service_type as tipo,
                 coalesce(nullif(o.vendor_name, ''), o.restaurant_id) as loja, o.customer_total as total
            from public.orders o
           where o.user_id = v_s.user_id
           order by o.created_at desc
           limit 10) x), '[]'::jsonb)
  ) into v;
  return v;
end;
$$;

-- O admin responde como "Equipa Bora": a mensagem chega ao chat do cliente ao vivo e o robô
-- fica calado nesta sessão até o admin a devolver.
create or replace function public.admin_suporte_responder(p_session_id uuid, p_texto text)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_user uuid;
  v_texto text := btrim(coalesce(p_texto, ''));
  v_id uuid;
begin
  if not coalesce(public.is_admin(), false) then
    raise exception 'admin_required';
  end if;
  if length(v_texto) = 0 then
    raise exception 'texto_vazio';
  end if;
  if length(v_texto) > 2000 then
    v_texto := left(v_texto, 2000);
  end if;
  select user_id into v_user from public.support_chatbot_sessions where id = p_session_id;
  if v_user is null then
    return jsonb_build_object('ok', false, 'erro', 'conversa não encontrada');
  end if;

  insert into public.support_chatbot_messages (session_id, role, content)
  values (p_session_id, 'admin', v_texto)
  returning id into v_id;

  update public.support_chatbot_sessions
     set mode = 'admin',
         admin_assumiu_em = coalesce(admin_assumiu_em, now()),
         admin_assumiu_por = auth.uid(),
         admin_lida_em = now(),
         ended_at = null
   where id = p_session_id;

  -- Sininho da app do cliente (best-effort; o chat aberto já recebe pelo Realtime).
  begin
    perform public._push_in_app_notification(v_user, 'suporte_resposta', 'A equipa Bora respondeu',
                                             left(v_texto, 140), p_session_id::text);
  exception when others then
    raise warning 'admin_suporte_responder: aviso ao cliente falhou: %', sqlerrm;
  end;

  perform public.log_admin_action('suporte_responder', 'support_session', p_session_id::text,
                                  jsonb_build_object('mensagem_id', v_id, 'caracteres', length(v_texto)));
  return jsonb_build_object('ok', true, 'mensagem_id', v_id);
end;
$$;

-- Devolve a conversa ao robô.
create or replace function public.admin_suporte_devolver(p_session_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_n int;
begin
  if not coalesce(public.is_admin(), false) then
    raise exception 'admin_required';
  end if;
  update public.support_chatbot_sessions set mode = 'ai' where id = p_session_id and mode = 'admin';
  get diagnostics v_n = row_count;
  perform public.log_admin_action('suporte_devolver_robo', 'support_session', p_session_id::text, '{}'::jsonb);
  return jsonb_build_object('ok', true, 'mudou', v_n > 0);
end;
$$;

revoke all on function public.admin_suporte_sessoes(integer, boolean) from public, anon;
revoke all on function public.admin_suporte_conversa(uuid) from public, anon;
revoke all on function public.admin_suporte_responder(uuid, text) from public, anon;
revoke all on function public.admin_suporte_devolver(uuid) from public, anon;
grant execute on function public.admin_suporte_sessoes(integer, boolean) to authenticated;
grant execute on function public.admin_suporte_conversa(uuid) to authenticated;
grant execute on function public.admin_suporte_responder(uuid, text) to authenticated;
grant execute on function public.admin_suporte_devolver(uuid) to authenticated;
revoke all on function public._support_sessao_ultima_msg() from public, anon, authenticated;
