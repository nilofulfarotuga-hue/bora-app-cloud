-- JA APLICADA EM PRODUCAO a 14/11/2026 (versao 20261114181007). Copiada para o repo a 15/11
-- (missao manha-15-11, bloco D) a partir de supabase_migrations.schema_migrations.
-- Achado 8801 da missao sistema-conteudo-14-11: qualquer utilizador com sessao conseguia escrever
-- no admin_audit_log chamando log_admin_action diretamente pela API.
-- Guarda: chamada DIRETA (topo da pilha) vinda da API por quem nao e admin e ignorada.
-- Chamadas de dentro de outras funcoes (cancelar reserva, chegada do parceiro, reembolso, robots)
-- continuam a registar como antes; service_role e chamadas internas (sem pedido da API) tambem.

create or replace function public._audit_chamada_direta_nao_admin()
returns boolean
language plpgsql
stable
security definer
set search_path to 'public', 'pg_temp'
as $$
declare
  v_ctx text;
begin
  if coalesce(auth.role(), '') not in ('authenticated', 'anon') then
    return false;
  end if;
  if public.is_admin() then
    return false;
  end if;
  get diagnostics v_ctx = pg_context;
  -- linha 1 = esta funcao; linha 2 = log_admin_action; mais linhas = chamada de dentro de outra funcao
  return coalesce(array_length(string_to_array(v_ctx, E'\n'), 1), 0) <= 2;
end;
$$;

revoke all on function public._audit_chamada_direta_nao_admin() from public, anon, authenticated;

create or replace function public.log_admin_action(p_action_type text, p_entity_type text, p_entity_id text, p_details jsonb default null::jsonb)
returns void
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $function$
declare v_uuid uuid;
begin
  if public._audit_chamada_direta_nao_admin() then
    return;
  end if;
  if p_entity_id ~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$' then
    v_uuid := p_entity_id::uuid;
  end if;
  insert into public.admin_audit_log (admin_id, admin_email, action, entity_type, entity_id, entity_id_text, details)
  values (auth.uid(),
          coalesce(auth.jwt() ->> 'email', auth.jwt() -> 'user_metadata' ->> 'email'),
          coalesce(nullif(trim(p_action_type), ''), 'acao_admin'),
          p_entity_type, v_uuid, p_entity_id, coalesce(p_details, '{}'::jsonb));
exception when others then
  raise warning 'log_admin_action(text): auditoria falhou: %', sqlerrm;
end;
$function$;

create or replace function public.log_admin_action(p_action text, p_entity_type text default null::text, p_entity_id uuid default null::uuid, p_details jsonb default '{}'::jsonb)
returns uuid
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $function$
declare
  v_admin_id    uuid;
  v_admin_email text;
  v_log_id      uuid;
begin
  if public._audit_chamada_direta_nao_admin() then
    return null;
  end if;

  v_admin_id := auth.uid();
  v_admin_email := coalesce(auth.jwt() ->> 'email', (auth.jwt() -> 'user_metadata' ->> 'email'));

  if v_admin_id is null then
    raise exception 'log_admin_action: not authenticated';
  end if;
  if p_action is null or length(trim(p_action)) = 0 then
    raise exception 'log_admin_action: action cannot be null or empty';
  end if;

  insert into public.admin_audit_log (admin_id, admin_email, action, entity_type, entity_id, details)
  values (v_admin_id, v_admin_email, p_action, p_entity_type, p_entity_id, coalesce(p_details, '{}'::jsonb))
  returning id into v_log_id;

  return v_log_id;
end;
$function$;
