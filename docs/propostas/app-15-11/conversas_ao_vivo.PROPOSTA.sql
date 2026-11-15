-- PROPOSTA (missão app-15-11, 15/11/2026): "Conversas ao vivo" dos robôs — caixa 8 / pedido do
-- Danilo de 12/11/2026 06:22 (texto em claude_ai_memoria prompt-conversas-ao-vivo-2026-11-12).
-- Nome sugerido: 20261115140000_conversas_ao_vivo. Aplica a Claude.ai. Nada de preços, comissões,
-- Stripe nem dinheiro. O WhatsApp da Bora (whatsapp_*) fica como está (robô desligado, de propósito).
--
-- Diagnóstico (e2e_log 9206): o robô do suporte já tem resposta da equipa (admin_suporte_*, 08/11) e
-- cala-se com mode='admin'; o Amigo Bora (client-assistant) não tem caminho humano; os robôs das lojas no
-- WhatsApp (VPS) já respeitam assistant_contacts.silenciado_ate e enviam o que estiver em
-- assistant_messages com direcao='saida' e entrega_estado='pendente'.
--
-- O QUE FAZ:
--   1. Avisos ao telemóvel do admin agrupados por CONVERSA (push_ref), compatível com o que existe.
--   2. Suporte: "Assumir" sem ter de escrever; "Devolver" limpa quem assumiu.
--   3. Amigo: colunas para a equipa assumir (12 h) e marcar como lida; papel 'admin' nas mensagens.
--   4. Lojas no WhatsApp: marcar como lida.
--   5. Lista única admin_conversas_ao_vivo + conversa admin_conversa_mensagens (marca como lida).
--   6. admin_conversa_assumir / _devolver / _responder (as 3 origens), com auditoria.
--   7. Aviso por cada mensagem de cliente no Amigo e nas lojas (como o suporte já tem).
--   8. Tempo real nas 2 tabelas de mensagens que faltam.
--   9. Erro achado: support_tickets não deixava o admin ler os pedidos de suporte dos clientes.
-- A parte da Edge client-assistant (o robô calar-se quando a equipa assume) vai no mesmo commit.
--
-- PARA DECIDIR (não está aqui): o Telegram recebe também cada mensagem de cliente (como já acontece
-- hoje com o suporte). Se for demais, limitar no notify-admin-urgent. E se a resposta da equipa pelo
-- WhatsApp de uma loja deve sair assinada "Equipa Bora" (aqui sai tal como escrita).

-- 1. Avisos agrupados por conversa ---------------------------------------------------------------
create or replace function public.notify_admin_urgent_push(p_event_type text, p_summary text, p_entity_type text, p_entity_id text, p_payload jsonb, p_deep_link text)
 returns uuid
 language plpgsql
 security definer
 set search_path to 'public'
as $function$
declare
  v_id    uuid;
  v_url   text;
  v_key   text;
  v_title text := '🔴 Ação pendente — Bora Admin';
  v_body  text := p_summary;
  v_nl    int;
begin

  -- 27/10/2026 modo demonstracao: o pedido de teste da loja em demonstracao nao alerta ninguem.
  IF p_entity_type = 'order' AND public._e_pedido_demo_loja(p_entity_id) THEN RETURN NULL; END IF;
  -- 1) Persiste a linha (badge + inbox dependem disto), severidade HIGH.
  v_id := public.notify_admin_event(
    p_event_type, 'high', p_summary,
    p_entity_type, p_entity_id, coalesce(p_payload, '{}'::jsonb), p_deep_link
  );

  -- 2) Push persistente + Telegram, best-effort (nunca quebra a transação de origem).
  begin
    v_nl := position(E'\n' in coalesce(p_summary, ''));
    if v_nl > 1 then
      v_title := btrim(left(p_summary, v_nl - 1));
      v_body  := btrim(substr(p_summary, v_nl + 1), E' \n');
      if coalesce(v_title, '') = '' or coalesce(v_body, '') = '' then
        v_title := '🔴 Ação pendente — Bora Admin';
        v_body  := p_summary;
      end if;
    end if;

    select decrypted_secret into v_url from vault.decrypted_secrets where name = 'project_url';
    select decrypted_secret into v_key from vault.decrypted_secrets where name = 'service_role_key';
    if v_url is not null and v_key is not null then
      perform net.http_post(
        url     := v_url || '/functions/v1/notify-admin-urgent',
        headers := jsonb_build_object(
          'Authorization', 'Bearer ' || v_key,
          'Content-Type', 'application/json'),
        body    := jsonb_build_object(
          'kind',  'generic',
          'title', v_title,
          'body',  v_body,
          'route', coalesce(p_deep_link, '/admin'),
          -- 15/11 (conversas ao vivo): com push_ref no payload, a notificação agrupa-se por
          -- conversa em vez de todas substituírem a mesma. Sem ele, igual a antes.
          'ref',   coalesce(nullif(p_payload->>'push_ref', ''), p_event_type))
      );
    end if;
  exception when others then
    raise notice 'notify_admin_urgent_push push error: %', sqlerrm;
  end;

  return v_id;
end
$function$;

create or replace function public.notify_support_user_message_admin()
 returns trigger
 language plpgsql
 security definer
 set search_path to 'public'
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
        'client_name', v_nome, 'client_phone', v_tel, 'message', new.content,
        'push_ref', 'conversa:suporte_app:' || new.session_id::text),
      '/admin/conversas/suporte_app/' || new.session_id::text);
  exception when others then
    raise notice 'notify_support_user_message_admin erro: %', sqlerrm;
  end;
  return new;
end
$function$;

-- 2. Suporte: assumir sem escrever; devolver limpa quem assumiu ------------------------------------
create or replace function public.admin_suporte_devolver(p_session_id uuid)
 returns jsonb
 language plpgsql
 security definer
 set search_path to 'public'
as $function$
declare
  v_n int;
begin
  if not coalesce(public.is_admin(), false) then
    raise exception 'admin_required';
  end if;
  update public.support_chatbot_sessions
     set mode = 'ai', admin_assumiu_em = null, admin_assumiu_por = null
   where id = p_session_id and mode = 'admin';
  get diagnostics v_n = row_count;
  perform public.log_admin_action('suporte_devolver_robo', 'support_session', p_session_id::text, '{}'::jsonb);
  return jsonb_build_object('ok', true, 'mudou', v_n > 0);
end;
$function$;

create or replace function public.admin_suporte_assumir(p_session_id uuid)
 returns jsonb
 language plpgsql
 security definer
 set search_path to 'public'
as $function$
declare
  v_n int;
begin
  if not coalesce(public.is_admin(), false) then
    raise exception 'admin_required';
  end if;
  update public.support_chatbot_sessions
     set mode = 'admin',
         admin_assumiu_em = coalesce(admin_assumiu_em, now()),
         admin_assumiu_por = auth.uid(),
         admin_lida_em = now()
   where id = p_session_id;
  get diagnostics v_n = row_count;
  perform public.log_admin_action('suporte_assumir', 'support_session', p_session_id::text, '{}'::jsonb);
  return jsonb_build_object('ok', v_n > 0);
end;
$function$;
revoke all on function public.admin_suporte_assumir(uuid) from public, anon;
grant execute on function public.admin_suporte_assumir(uuid) to authenticated;

-- 3. Amigo: a equipa pode assumir (12 h) e responder --------------------------------------------
alter table public.assistant_conversations
  add column if not exists equipa_assumiu_por uuid,
  add column if not exists equipa_ate timestamptz,
  add column if not exists admin_lida_em timestamptz;
alter table public.assistant_chat_messages drop constraint if exists assistant_chat_messages_role_check;
alter table public.assistant_chat_messages add constraint assistant_chat_messages_role_check
  check (role = any (array['user', 'assistant', 'tool', 'system', 'admin']));

-- 4. Lojas no WhatsApp: marcar como lida ---------------------------------------------------------
alter table public.assistant_contacts add column if not exists admin_lida_em timestamptz;

-- 5. Lista única e conversa ----------------------------------------------------------------------
create or replace function public.admin_conversas_ao_vivo(
  p_limite integer default 100, p_so_nao_lidas boolean default false, p_origem text default null)
 returns table(origem text, conversa_id text, cliente_user_id uuid, cliente_nome text, canal text,
               ultima_mensagem_em timestamptz, ultima_mensagem_resumo text, ultimo_autor text,
               estado text, nao_lidas integer)
 language plpgsql
 stable
 security definer
 set search_path to 'public', 'pg_temp'
as $function$
begin
  if not coalesce(public.is_admin(), false) then
    raise exception 'admin_required' using errcode = '42501';
  end if;
  return query
  select x.* from (
    -- Robô do suporte da app
    select 'suporte_app'::text, s.id::text, s.user_id,
           coalesce(nullif(u.name, ''), 'Cliente'), 'App · suporte'::text,
           coalesce(lm.created_at, s.ultima_msg_em, s.started_at),
           left(coalesce(lm.content, ''), 200),
           case lm.role when 'user' then 'cliente' when 'admin' then 'equipa' else 'robo' end,
           case when s.mode = 'admin' then 'equipa'
                when coalesce(s.escalated_pending, false) or coalesce(s.escalated, false) then 'pediu_pessoa'
                else 'robo' end,
           (select count(*)::int from public.support_chatbot_messages m
             where m.session_id = s.id and m.role = 'user'
               and m.created_at > coalesce(s.admin_lida_em, '-infinity'::timestamptz))
      from public.support_chatbot_sessions s
      left join public.users u on u.id = s.user_id
      left join lateral (select m.content, m.role, m.created_at from public.support_chatbot_messages m
                          where m.session_id = s.id and m.role in ('user', 'assistant', 'admin')
                          order by m.created_at desc limit 1) lm on true
     where (p_origem is null or p_origem = 'suporte_app')
       and not coalesce(public.is_demo_user(s.user_id), false)
    union all
    -- Amigo Bora
    select 'amigo'::text, c.id::text, c.user_id,
           coalesce(nullif(u.name, ''), 'Cliente'), 'App · Amigo Bora'::text,
           coalesce(lm.created_at, c.last_message_at, c.started_at),
           left(coalesce(lm.content, ''), 200),
           case lm.role when 'user' then 'cliente' when 'admin' then 'equipa' else 'robo' end,
           case when c.equipa_ate > now() then 'equipa'
                when c.status = 'handoff' then 'pediu_pessoa'
                else 'robo' end,
           (select count(*)::int from public.assistant_chat_messages m
             where m.conversation_id = c.id and m.role = 'user'
               and m.created_at > coalesce(c.admin_lida_em, '-infinity'::timestamptz))
      from public.assistant_conversations c
      left join public.users u on u.id = c.user_id
      left join lateral (select m.content, m.role, m.created_at from public.assistant_chat_messages m
                          where m.conversation_id = c.id and m.role in ('user', 'assistant', 'admin')
                          order by m.created_at desc limit 1) lm on true
     where (p_origem is null or p_origem = 'amigo')
       and not coalesce(public.is_demo_user(c.user_id), false)
       and coalesce(c.platform, '') <> 'pc-prova' and coalesce(c.platform, '') not like 'prova-mcp%'
    union all
    -- Robôs das lojas no WhatsApp
    select 'whatsapp_loja'::text, ct.tenant_id::text || ':' || ct.numero, null::uuid,
           coalesce(nullif(ct.nome, ''), 'Cliente') || ' · ' || t.nome, ('WhatsApp · ' || t.nome)::text,
           coalesce(lm.created_at, ct.ultima_msg_em),
           left(coalesce(lm.texto, ''), 200),
           case when lm.direcao = 'entrada' then 'cliente' when lm.motivo = 'equipa' then 'equipa' else 'robo' end,
           case when ct.silenciado_ate > now() then 'equipa'
                when t.mode = 'desligado' then 'desligado'
                else 'robo' end,
           (select count(*)::int from public.assistant_messages m
             where m.tenant_id = ct.tenant_id and m.numero = ct.numero and m.direcao = 'entrada'
               and not coalesce(m.simulado, false)
               and m.created_at > coalesce(ct.admin_lida_em, '-infinity'::timestamptz))
      from public.assistant_contacts ct
      join public.assistant_tenants t on t.id = ct.tenant_id
      left join lateral (select m.texto, m.direcao, m.motivo, m.created_at from public.assistant_messages m
                          where m.tenant_id = ct.tenant_id and m.numero = ct.numero
                            and not coalesce(m.simulado, false)
                          order by m.created_at desc limit 1) lm on true
     where (p_origem is null or p_origem = 'whatsapp_loja')
  ) as x(origem, conversa_id, cliente_user_id, cliente_nome, canal, ultima_mensagem_em,
         ultima_mensagem_resumo, ultimo_autor, estado, nao_lidas)
   where not coalesce(p_so_nao_lidas, false) or x.nao_lidas > 0 or x.estado = 'pediu_pessoa'
   order by x.ultima_mensagem_em desc nulls last
   limit least(greatest(coalesce(p_limite, 100), 1), 500);
end
$function$;
revoke all on function public.admin_conversas_ao_vivo(integer, boolean, text) from public, anon;
grant execute on function public.admin_conversas_ao_vivo(integer, boolean, text) to authenticated;

-- A conversa inteira, balão a balão; marca como lida.
create or replace function public.admin_conversa_mensagens(
  p_origem text, p_conversa_id text, p_limite integer default 300)
 returns table(id text, autor text, texto text, ferramenta text, criado_em timestamptz)
 language plpgsql
 security definer
 set search_path to 'public', 'pg_temp'
as $function$
declare
  v_tenant uuid;
  v_numero text;
  v_lim int := least(greatest(coalesce(p_limite, 300), 1), 1000);
begin
  if not coalesce(public.is_admin(), false) then
    raise exception 'admin_required' using errcode = '42501';
  end if;
  if p_origem = 'suporte_app' then
    update public.support_chatbot_sessions set admin_lida_em = now() where support_chatbot_sessions.id = p_conversa_id::uuid;
    return query
      select m.id::text,
             case m.role when 'user' then 'cliente' when 'admin' then 'equipa' when 'tool' then 'ferramenta' else 'robo' end,
             coalesce(m.content, ''), m.tool_name, m.created_at
        from public.support_chatbot_messages m
       where m.session_id = p_conversa_id::uuid and m.role <> 'system'
       order by m.created_at desc limit v_lim;
  elsif p_origem = 'amigo' then
    update public.assistant_conversations set admin_lida_em = now() where assistant_conversations.id = p_conversa_id::uuid;
    return query
      select m.id::text,
             case m.role when 'user' then 'cliente' when 'admin' then 'equipa' when 'tool' then 'ferramenta' else 'robo' end,
             coalesce(m.content, ''), m.tool_name, m.created_at
        from public.assistant_chat_messages m
       where m.conversation_id = p_conversa_id::uuid and m.role <> 'system'
       order by m.created_at desc limit v_lim;
  elsif p_origem = 'whatsapp_loja' then
    v_tenant := split_part(p_conversa_id, ':', 1)::uuid;
    v_numero := substr(p_conversa_id, length(split_part(p_conversa_id, ':', 1)) + 2);
    update public.assistant_contacts set admin_lida_em = now()
     where assistant_contacts.tenant_id = v_tenant and assistant_contacts.numero = v_numero;
    return query
      select m.id::text,
             case when m.direcao = 'entrada' then 'cliente' when m.motivo = 'equipa' then 'equipa' else 'robo' end,
             coalesce(m.texto, ''), null::text, m.created_at
        from public.assistant_messages m
       where m.tenant_id = v_tenant and m.numero = v_numero and not coalesce(m.simulado, false)
       order by m.created_at desc limit v_lim;
  else
    raise exception 'origem_invalida';
  end if;
end
$function$;
revoke all on function public.admin_conversa_mensagens(text, text, integer) from public, anon;
grant execute on function public.admin_conversa_mensagens(text, text, integer) to authenticated;

-- 6. Assumir, devolver e responder (as 3 origens) --------------------------------------------------
create or replace function public.admin_conversa_assumir(p_origem text, p_conversa_id text)
 returns jsonb
 language plpgsql
 security definer
 set search_path to 'public', 'pg_temp'
as $function$
declare
  v_n int := 0;
begin
  if not coalesce(public.is_admin(), false) then
    raise exception 'admin_required' using errcode = '42501';
  end if;
  if p_origem = 'suporte_app' then
    return public.admin_suporte_assumir(p_conversa_id::uuid);
  elsif p_origem = 'amigo' then
    update public.assistant_conversations
       set equipa_ate = now() + interval '12 hours', equipa_assumiu_por = auth.uid(), admin_lida_em = now()
     where id = p_conversa_id::uuid;
    get diagnostics v_n = row_count;
  elsif p_origem = 'whatsapp_loja' then
    update public.assistant_contacts
       set silenciado_ate = now() + interval '12 hours', silenciado_motivo = 'equipa', admin_lida_em = now()
     where tenant_id = split_part(p_conversa_id, ':', 1)::uuid
       and numero = substr(p_conversa_id, length(split_part(p_conversa_id, ':', 1)) + 2);
    get diagnostics v_n = row_count;
  else
    raise exception 'origem_invalida';
  end if;
  perform public.log_admin_action('conversa_assumir', p_origem, p_conversa_id, '{}'::jsonb);
  return jsonb_build_object('ok', v_n > 0);
end
$function$;

create or replace function public.admin_conversa_devolver(p_origem text, p_conversa_id text)
 returns jsonb
 language plpgsql
 security definer
 set search_path to 'public', 'pg_temp'
as $function$
declare
  v_n int := 0;
begin
  if not coalesce(public.is_admin(), false) then
    raise exception 'admin_required' using errcode = '42501';
  end if;
  if p_origem = 'suporte_app' then
    return public.admin_suporte_devolver(p_conversa_id::uuid);
  elsif p_origem = 'amigo' then
    update public.assistant_conversations
       set equipa_ate = null, equipa_assumiu_por = null,
           status = case when status = 'handoff' then 'open' else status end
     where id = p_conversa_id::uuid;
    get diagnostics v_n = row_count;
  elsif p_origem = 'whatsapp_loja' then
    update public.assistant_contacts
       set silenciado_ate = null, silenciado_motivo = null
     where tenant_id = split_part(p_conversa_id, ':', 1)::uuid
       and numero = substr(p_conversa_id, length(split_part(p_conversa_id, ':', 1)) + 2)
       and silenciado_motivo = 'equipa';
    get diagnostics v_n = row_count;
  else
    raise exception 'origem_invalida';
  end if;
  perform public.log_admin_action('conversa_devolver', p_origem, p_conversa_id, '{}'::jsonb);
  return jsonb_build_object('ok', true, 'mudou', v_n > 0);
end
$function$;

create or replace function public.admin_conversa_responder(p_origem text, p_conversa_id text, p_texto text)
 returns jsonb
 language plpgsql
 security definer
 set search_path to 'public', 'pg_temp'
as $function$
declare
  v_texto text := left(btrim(coalesce(p_texto, '')), 2000);
  v_user uuid;
  v_tenant uuid;
  v_numero text;
  v_id text;
begin
  if not coalesce(public.is_admin(), false) then
    raise exception 'admin_required' using errcode = '42501';
  end if;
  if length(v_texto) = 0 then
    raise exception 'texto_vazio';
  end if;
  if p_origem = 'suporte_app' then
    return public.admin_suporte_responder(p_conversa_id::uuid, v_texto);
  elsif p_origem = 'amigo' then
    select user_id into v_user from public.assistant_conversations where id = p_conversa_id::uuid;
    if v_user is null then
      return jsonb_build_object('ok', false, 'erro', 'conversa não encontrada');
    end if;
    insert into public.assistant_chat_messages (conversation_id, user_id, role, content)
    values (p_conversa_id::uuid, v_user, 'admin', v_texto)
    returning assistant_chat_messages.id::text into v_id;
    update public.assistant_conversations
       set equipa_ate = now() + interval '12 hours', equipa_assumiu_por = auth.uid(),
           admin_lida_em = now(), last_message_at = now()
     where id = p_conversa_id::uuid;
    begin
      perform public._push_in_app_notification(v_user, 'amigo_resposta', 'A equipa Bora respondeu',
                                               left(v_texto, 140), p_conversa_id);
    exception when others then
      raise warning 'admin_conversa_responder: aviso ao cliente falhou: %', sqlerrm;
    end;
  elsif p_origem = 'whatsapp_loja' then
    v_tenant := split_part(p_conversa_id, ':', 1)::uuid;
    v_numero := substr(p_conversa_id, length(split_part(p_conversa_id, ':', 1)) + 2);
    insert into public.assistant_messages (tenant_id, numero, direcao, texto, motivo, entrega_estado, simulado)
    values (v_tenant, v_numero, 'saida', v_texto, 'equipa', 'pendente', false)
    returning assistant_messages.id::text into v_id;
    update public.assistant_contacts
       set silenciado_ate = now() + interval '12 hours', silenciado_motivo = 'equipa', admin_lida_em = now()
     where tenant_id = v_tenant and numero = v_numero;
  else
    raise exception 'origem_invalida';
  end if;
  perform public.log_admin_action('conversa_responder', p_origem, p_conversa_id,
                                  jsonb_build_object('mensagem_id', v_id, 'caracteres', length(v_texto)));
  return jsonb_build_object('ok', true, 'mensagem_id', v_id);
end
$function$;

revoke all on function public.admin_conversa_assumir(text, text) from public, anon;
revoke all on function public.admin_conversa_devolver(text, text) from public, anon;
revoke all on function public.admin_conversa_responder(text, text, text) from public, anon;
grant execute on function public.admin_conversa_assumir(text, text) to authenticated;
grant execute on function public.admin_conversa_devolver(text, text) to authenticated;
grant execute on function public.admin_conversa_responder(text, text, text) to authenticated;

-- 7. Aviso por cada mensagem de cliente no Amigo e nas lojas ---------------------------------------
create or replace function public._amigo_mensagem_aviso()
 returns trigger
 language plpgsql
 security definer
 set search_path to 'public'
as $function$
declare
  v_nome text; v_plataforma text;
begin
  if new.role is distinct from 'user' then return new; end if;
  if coalesce(public.is_demo_user(new.user_id), false) then return new; end if;
  select c.platform into v_plataforma from public.assistant_conversations c where c.id = new.conversation_id;
  if coalesce(v_plataforma, '') = 'pc-prova' or coalesce(v_plataforma, '') like 'prova-mcp%' then return new; end if;
  begin
    select u.name into v_nome from public.users u where u.id = new.user_id;
  exception when others then v_nome := null;
  end;
  begin
    perform public.notify_admin_urgent_push(
      'amigo_user_message',
      '💬 AMIGO BORA · ' || coalesce(nullif(v_nome, ''), 'cliente') || E'\n' || left(coalesce(new.content, ''), 160),
      'assistant_conversation', new.conversation_id::text,
      jsonb_build_object('conversation_id', new.conversation_id, 'user_id', new.user_id,
                         'push_ref', 'conversa:amigo:' || new.conversation_id::text),
      '/admin/conversas/amigo/' || new.conversation_id::text);
  exception when others then
    raise notice '_amigo_mensagem_aviso erro: %', sqlerrm;
  end;
  return new;
end
$function$;

create or replace function public._whatsapp_loja_mensagem_aviso()
 returns trigger
 language plpgsql
 security definer
 set search_path to 'public'
as $function$
declare
  v_nome text; v_id text;
begin
  if new.direcao is distinct from 'entrada' or coalesce(new.simulado, false) then return new; end if;
  v_id := new.tenant_id::text || ':' || new.numero;
  begin
    select coalesce(nullif(c.nome, ''), 'cliente') || ' · ' || t.nome into v_nome
      from public.assistant_tenants t
      left join public.assistant_contacts c on c.tenant_id = t.id and c.numero = new.numero
     where t.id = new.tenant_id;
  exception when others then v_nome := null;
  end;
  begin
    perform public.notify_admin_urgent_push(
      'whatsapp_loja_user_message',
      '💬 ROBÔ DA LOJA (WhatsApp) · ' || coalesce(v_nome, 'cliente') || E'\n' || left(coalesce(new.texto, ''), 160),
      'assistant_contact', v_id,
      jsonb_build_object('tenant_id', new.tenant_id, 'push_ref', 'conversa:whatsapp_loja:' || v_id),
      '/admin/conversas/whatsapp_loja/' || v_id);
  exception when others then
    raise notice '_whatsapp_loja_mensagem_aviso erro: %', sqlerrm;
  end;
  return new;
end
$function$;

revoke all on function public._amigo_mensagem_aviso() from public, anon, authenticated;
revoke all on function public._whatsapp_loja_mensagem_aviso() from public, anon, authenticated;

drop trigger if exists trg_amigo_mensagem_aviso on public.assistant_chat_messages;
create trigger trg_amigo_mensagem_aviso after insert on public.assistant_chat_messages
  for each row execute function public._amigo_mensagem_aviso();
drop trigger if exists trg_whatsapp_loja_mensagem_aviso on public.assistant_messages;
create trigger trg_whatsapp_loja_mensagem_aviso after insert on public.assistant_messages
  for each row execute function public._whatsapp_loja_mensagem_aviso();

-- 8. Tempo real nas mensagens do Amigo e das lojas -----------------------------------------------
do $$
begin
  if exists (select 1 from pg_publication where pubname = 'supabase_realtime') then
    if not exists (select 1 from pg_publication_tables where pubname = 'supabase_realtime'
                    and schemaname = 'public' and tablename = 'assistant_chat_messages') then
      alter publication supabase_realtime add table public.assistant_chat_messages;
    end if;
    if not exists (select 1 from pg_publication_tables where pubname = 'supabase_realtime'
                    and schemaname = 'public' and tablename = 'assistant_messages') then
      alter publication supabase_realtime add table public.assistant_messages;
    end if;
  end if;
end $$;

-- 9. Erro achado: o admin não lia os pedidos de suporte dos clientes -------------------------------
drop policy if exists support_tickets_admin_ler on public.support_tickets;
create policy support_tickets_admin_ler on public.support_tickets
  for select to authenticated using (coalesce(public.is_admin(), false));

-- PROVA (depois de aplicar), com a conta de admin no painel:
--   select origem, estado, nao_lidas from public.admin_conversas_ao_vivo(20);      -- 3 origens
--   select count(*) from public.admin_conversa_mensagens('suporte_app', '<id>');  -- balões
-- Sem sessão (postgres): select public.admin_conversas_ao_vivo(1);  → 42501 admin_required.
