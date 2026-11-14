-- Missão editar-perfil-2026-11-11 (autorizada pelo Danilo a 11/11/2026, 16:54 e 17:00).
--
-- Porquê: uma cliente perguntou no suporte como mudar o perfil; o robô mandou-a
-- para "Perfil → Editar perfil", que não existia. O nome dela foi mudado à mão
-- por MCP — e só em public.users. A app lê o nome do metadata do login
-- (bora_name/bora_phone), por isso essa mudança nunca chegou ao telemóvel dela.
--
-- O que isto faz:
--   1. user_profile_changes — auditoria de cada mudança (quem, o quê, antes, depois).
--   2. _apply_user_profile_change — o núcleo único: valida, grava em public.users
--      E no metadata do login, regista a auditoria. Não é chamável de fora.
--   3. client_update_my_profile — o "Editar perfil" da app (só a própria conta).
--   4. admin_update_client_contact — o painel passa pelo mesmo núcleo.
--   5. admin_get_profile_changes — o histórico na ficha do cliente.
--   6. admin_approve_action (ACCOUNT_UPDATE) — aprovar o pedido do robô faz a
--      mudança pelo mesmo núcleo e avisa o cliente na app.
--
-- Guardas: auth.uid() / is_admin(), nunca current_user (erro de 10/11/2026).

-- ── 1. Auditoria ────────────────────────────────────────────────────────────
create table if not exists public.user_profile_changes (
  id                bigint generated always as identity primary key,
  user_id           uuid not null,
  changed_by        uuid,
  source            text not null check (source in ('cliente', 'admin', 'robo_aprovado')),
  pending_action_id uuid,
  antes             jsonb not null,
  depois            jsonb not null,
  created_at        timestamptz not null default now()
);

create index if not exists user_profile_changes_user_idx
  on public.user_profile_changes (user_id, created_at desc);

alter table public.user_profile_changes enable row level security;
-- Sem políticas de propósito: lê-se e escreve-se só pelas funções abaixo.
revoke all on public.user_profile_changes from public, anon, authenticated;

comment on table public.user_profile_changes is
  'Editar perfil (11/11/2026): cada mudança de nome/telemóvel de um utilizador — quem mudou, de onde (cliente/admin/robo_aprovado), antes e depois.';

-- ── 2. Núcleo único ─────────────────────────────────────────────────────────
create or replace function public._apply_user_profile_change(
  p_user_id           uuid,
  p_name              text,
  p_phone             text,
  p_changed_by        uuid,
  p_source            text,
  p_pending_action_id uuid default null
)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_old_name  text;
  v_old_phone text;
  v_name      text;
  v_phone     text;
  v_campos    text[] := '{}';
  v_antes     jsonb := '{}'::jsonb;
  v_depois    jsonb := '{}'::jsonb;
  v_meta      jsonb := '{}'::jsonb;
  v_id        bigint;
begin
  if p_source is null or p_source not in ('cliente', 'admin', 'robo_aprovado') then
    raise exception 'ORIGEM_INVALIDA: %', p_source;
  end if;

  if p_user_id is null then
    return jsonb_build_object('ok', false, 'codigo', 'SEM_CONTA',
      'erro', 'Conta não encontrada.');
  end if;

  -- FOR UPDATE: dois toques seguidos no Guardar não se atropelam.
  select u.name, u.phone into v_old_name, v_old_phone
    from public.users u
   where u.id = p_user_id
   for update;
  if not found then
    return jsonb_build_object('ok', false, 'codigo', 'SEM_CONTA',
      'erro', 'Conta não encontrada.');
  end if;

  -- Nome: sem espaços nas pontas nem repetidos. Vazio/null = não mexe.
  v_name := nullif(regexp_replace(btrim(coalesce(p_name, '')), '[[:space:]]+', ' ', 'g'), '');
  if v_name is not null then
    if char_length(v_name) < 2 or char_length(v_name) > 60 then
      return jsonb_build_object('ok', false, 'codigo', 'NOME_INVALIDO',
        'erro', 'O nome tem de ter entre 2 e 60 caracteres.');
    end if;
    if char_length(regexp_replace(v_name, '[^[:alpha:]]', '', 'g')) < 2 then
      return jsonb_build_object('ok', false, 'codigo', 'NOME_INVALIDO',
        'erro', 'Escreve o teu nome com letras.');
    end if;
  end if;

  -- Telemóvel: 9 dígitos a começar por 9 — a forma que já se grava em
  -- users.phone. Aceita +351 / 00351 / 351 e tira-o. Vazio/null = não mexe.
  v_phone := regexp_replace(coalesce(p_phone, ''), '[[:space:]().-]', '', 'g');
  if v_phone = '' then
    v_phone := null;
  end if;
  if v_phone is not null then
    v_phone := regexp_replace(v_phone, '^\+', '');
    if v_phone like '00351%' then
      v_phone := substr(v_phone, 6);
    elsif char_length(v_phone) > 9 and v_phone like '351%' then
      v_phone := substr(v_phone, 4);
    end if;
    if v_phone !~ '^9[0-9]{8}$' then
      return jsonb_build_object('ok', false, 'codigo', 'TELEMOVEL_INVALIDO',
        'erro', 'Telemóvel inválido. Usa 9 dígitos a começar por 9 (ex.: 912345678).');
    end if;
  end if;

  if v_name is not null and v_name is distinct from v_old_name then
    v_campos := v_campos || 'name'::text;
    v_antes  := v_antes  || jsonb_build_object('name', v_old_name);
    v_depois := v_depois || jsonb_build_object('name', v_name);
    v_meta   := v_meta   || jsonb_build_object('bora_name', v_name);
  else
    v_name := v_old_name;
  end if;

  if v_phone is not null and v_phone is distinct from v_old_phone then
    v_campos := v_campos || 'phone'::text;
    v_antes  := v_antes  || jsonb_build_object('phone', v_old_phone);
    v_depois := v_depois || jsonb_build_object('phone', v_phone);
    v_meta   := v_meta   || jsonb_build_object('bora_phone', v_phone);
  else
    v_phone := v_old_phone;
  end if;

  if cardinality(v_campos) = 0 then
    return jsonb_build_object('ok', true, 'alterado', false,
      'name', v_old_name, 'phone', v_old_phone, 'campos', '[]'::jsonb);
  end if;

  -- Travão contra abuso só para o próprio cliente (o admin não tem limite).
  if p_source = 'cliente' and (
       select count(*) from public.user_profile_changes c
        where c.user_id = p_user_id and c.source = 'cliente'
          and c.created_at > now() - interval '1 day') >= 10 then
    return jsonb_build_object('ok', false, 'codigo', 'LIMITE_DIARIO',
      'erro', 'Já mudaste os teus dados muitas vezes hoje. Tenta amanhã ou fala com o Suporte.');
  end if;

  update public.users
     set name  = v_name,
         phone = v_phone
   where id = p_user_id;

  -- A app lê o nome do metadata do login ao abrir; sem isto a mudança feita
  -- pelo painel ou pelo robô ficava invisível no telemóvel do cliente.
  update auth.users
     set raw_user_meta_data = coalesce(raw_user_meta_data, '{}'::jsonb) || v_meta
   where id = p_user_id;

  insert into public.user_profile_changes
    (user_id, changed_by, source, pending_action_id, antes, depois)
  values
    (p_user_id, p_changed_by, p_source, p_pending_action_id, v_antes, v_depois)
  returning id into v_id;

  return jsonb_build_object('ok', true, 'alterado', true,
    'name', v_name, 'phone', v_phone,
    'campos', to_jsonb(v_campos), 'change_id', v_id);
end;
$$;

revoke all on function public._apply_user_profile_change(uuid, text, text, uuid, text, uuid)
  from public, anon, authenticated;

-- Aviso ao cliente (sino da app + push), quando a mudança não foi feita por ele.
create or replace function public._notify_profile_changed(
  p_user_id uuid,
  p_campos  jsonb,
  p_origem  text
)
returns void
language plpgsql
security definer
set search_path = public, net, vault
as $$
declare
  v_title text := 'Os teus dados foram atualizados';
  v_body  text;
  v_quais text;
  v_url   text;
  v_key   text;
begin
  v_quais := case
    when p_campos ? 'name' and p_campos ? 'phone' then 'o teu nome e o teu telemóvel'
    when p_campos ? 'name' then 'o teu nome'
    else 'o teu telemóvel'
  end;
  v_body := case p_origem
    when 'robo_aprovado' then 'Mudámos ' || v_quais || ', como pediste no Suporte.'
    else 'A equipa Bora atualizou ' || v_quais || '.'
  end || ' Se não foste tu a pedir, fala connosco no Suporte.';

  perform public._push_in_app_notification(p_user_id, 'admin', v_title, v_body, null);

  begin
    select decrypted_secret into v_url from vault.decrypted_secrets where name = 'project_url';
    select decrypted_secret into v_key from vault.decrypted_secrets where name = 'service_role_key';
    if v_url is not null and v_key is not null then
      perform net.http_post(
        url     := v_url || '/functions/v1/notify-admin-message',
        headers := jsonb_build_object('Authorization', 'Bearer ' || v_key,
                                      'Content-Type', 'application/json'),
        body    := jsonb_build_object(
          'targetUserId', p_user_id::text,
          'title', v_title,
          'body', v_body,
          'kind', 'admin_message_client',
          'relatedId', '')
      );
    end if;
  exception when others then
    -- O push é extra: o aviso no sino já ficou gravado.
    raise notice '[_notify_profile_changed] push não enviado: %', sqlerrm;
  end;
end;
$$;

revoke all on function public._notify_profile_changed(uuid, jsonb, text)
  from public, anon, authenticated;

-- ── 3. "Editar perfil" da app do cliente ────────────────────────────────────
create or replace function public.client_update_my_profile(
  p_name  text,
  p_phone text default null
)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_uid uuid := auth.uid();
begin
  if v_uid is null then
    return jsonb_build_object('ok', false, 'codigo', 'SEM_SESSAO',
      'erro', 'A tua sessão terminou. Entra outra vez na tua conta.');
  end if;
  if public.is_conta_convidado() then
    return jsonb_build_object('ok', false, 'codigo', 'CONVIDADO',
      'erro', 'Cria uma conta para poderes guardar os teus dados.');
  end if;
  -- Só a própria conta: o id vem do token, nunca de um parâmetro.
  return public._apply_user_profile_change(v_uid, p_name, p_phone, v_uid, 'cliente', null);
end;
$$;

revoke all on function public.client_update_my_profile(text, text) from public, anon;
grant execute on function public.client_update_my_profile(text, text) to authenticated;

-- ── 4. Painel: editar nome/telemóvel de um cliente ──────────────────────────
-- Mesma assinatura e mesmas chaves de resposta (ok, name, phone, erro). Tira
-- também o "exception when undefined_table" antigo, que desfazia o UPDATE e
-- ainda assim respondia ok:true.
create or replace function public.admin_update_client_contact(
  p_user_id uuid,
  p_name    text,
  p_phone   text
)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_res jsonb;
begin
  if not public.is_admin() then
    raise exception 'apenas administradores';
  end if;

  v_res := public._apply_user_profile_change(p_user_id, p_name, p_phone, auth.uid(), 'admin', null);

  if coalesce((v_res->>'ok')::boolean, false) and coalesce((v_res->>'alterado')::boolean, false) then
    insert into public.admin_audit_log (admin_id, action, target_type, target_id, details)
    values (auth.uid(), 'update_client_contact', 'user', p_user_id::text,
            jsonb_build_object('campos', v_res->'campos', 'change_id', v_res->'change_id'));
    perform public._notify_profile_changed(p_user_id, v_res->'campos', 'admin');
  end if;

  return v_res;
end;
$$;

revoke all on function public.admin_update_client_contact(uuid, text, text) from public, anon;
grant execute on function public.admin_update_client_contact(uuid, text, text) to authenticated;

-- ── 5. Painel: histórico das mudanças na ficha do cliente ───────────────────
-- Junta a auditoria nova com o que ficou antes dela: edições antigas do painel
-- (admin_audit_log) e pedidos do robô executados à mão (sem linha de auditoria).
create or replace function public.admin_get_profile_changes(
  p_user_id uuid,
  p_limit   integer default 50
)
returns table (
  quando            timestamptz,
  origem            text,
  quem              text,
  antes             jsonb,
  depois            jsonb,
  pending_action_id uuid
)
language plpgsql
security definer
set search_path = public, pg_temp
as $$
begin
  if not public.is_admin() then
    raise exception 'NOT_ADMIN';
  end if;

  return query
  select * from (
    select c.created_at, c.source, coalesce(au.email::text, c.changed_by::text),
           c.antes, c.depois, c.pending_action_id
      from public.user_profile_changes c
      left join auth.users au on au.id = c.changed_by
     where c.user_id = p_user_id
    union all
    select l.created_at, 'admin (antigo)'::text, coalesce(au.email::text, l.admin_id::text),
           null::jsonb, l.details, null::uuid
      from public.admin_audit_log l
      left join auth.users au on au.id = l.admin_id
     where l.action = 'update_client_contact'
       and l.target_id = p_user_id::text
       and not (l.details ? 'change_id')
    union all
    select coalesce(a.executed_at, a.reviewed_at, a.proposed_at), 'robo (feito à mão)'::text,
           coalesce(au.email::text, a.reviewed_by::text, '—'),
           null::jsonb, a.action_payload, a.id
      from public.support_pending_actions a
      left join auth.users au on au.id = a.reviewed_by
     where a.user_id = p_user_id
       and a.action_type = 'ACCOUNT_UPDATE'
       and a.status = 'executed'
       and not exists (select 1 from public.user_profile_changes c2
                        where c2.pending_action_id = a.id)
  ) h
  order by 1 desc
  limit least(greatest(coalesce(p_limit, 50), 1), 200);
end;
$$;

revoke all on function public.admin_get_profile_changes(uuid, integer) from public, anon;
grant execute on function public.admin_get_profile_changes(uuid, integer) to authenticated;
