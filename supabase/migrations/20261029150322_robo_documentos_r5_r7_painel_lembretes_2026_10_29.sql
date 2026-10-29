-- Robo "fiscal de documentos" (missao final-app-2026-10-29, adendo 3, R5 + R7): lembretes, painel e app.
-- R5: lembretes dias 1, 3 e 7 (10:00 de Lisboa) so a quem entrou ou enviou DEPOIS de robo_documentos_corte,
--     e so com o robo a agir. Candidatos ja parados nao recebem nada automatico; ao "lembrar este" do painel
--     so vai quem o Danilo escolher.
-- R7: funcoes para o painel (so admin) e para a app do candidato (so o proprio, so com o robo a agir).
-- O robo NUNCA aprova nada.

-- ── R5: lembretes ────────────────────────────────────────────────────────────────
create or replace function public.robo_documentos_lembretes_correr(p_ignorar_hora boolean default false)
returns jsonb language plpgsql security definer set search_path to 'public' as $f$
declare
  cfg jsonb := public._robo_documentos_cfg();
  v_corte timestamptz := (cfg ->> 'corte')::timestamptz;
  v_dias jsonb := cfg -> 'lembretes_dias';
  v_uid uuid;
  v_ref timestamptz;
  v_enviados integer;
  v_alvo integer;
  v_passados integer;
  v_faltas text[];
  v_corpo text;
  n_enviados integer := 0;
  n_vistos integer := 0;
begin
  if not public._robo_documentos_age() or v_corte is null then
    return jsonb_build_object('ok', true, 'enviados', 0, 'porque', 'desligado_ou_sem_corte');
  end if;
  if not coalesce(p_ignorar_hora, false)
     and extract(hour from (now() at time zone 'Europe/Lisbon')) <> 10 then
    return jsonb_build_object('ok', true, 'enviados', 0, 'porque', 'fora_de_horas');
  end if;
  if jsonb_typeof(v_dias) <> 'array' or jsonb_array_length(v_dias) = 0 then
    return jsonb_build_object('ok', true, 'enviados', 0, 'porque', 'sem_dias');
  end if;

  for v_uid in
    select distinct x.u from (
      select user_id as u from public.drivers where approval_status = 'pending' and deleted_at is null
      union select user_id from public.cleaners where approval_status = 'pending'
      union select user_id from public.washers where approval_status = 'pending'
      union select user_id from public.service_providers where approval_status = 'pending'
    ) x
    where x.u is not null and not public.is_demo_user(x.u)
  loop
    n_vistos := n_vistos + 1;
    -- Candidatos que ja estavam parados antes da ativacao nao recebem nada automatico.
    v_ref := greatest(
      coalesce(public._provider_atividade_ultima_candidatura(v_uid), '-infinity'::timestamptz),
      coalesce((select a.enviado_em from public.provider_atividade a where a.user_id = v_uid), '-infinity'::timestamptz));
    if v_ref < v_corte then continue; end if;

    v_faltas := public._robo_documentos_faltas(v_uid);
    if coalesce(array_length(v_faltas, 1), 0) = 0 then continue; end if;

    select count(*) into v_enviados from public.documentos_lembretes_enviados where user_id = v_uid and quem = 'cron';
    if v_enviados >= jsonb_array_length(v_dias) then continue; end if;
    v_alvo := (v_dias ->> v_enviados)::integer;
    v_passados := floor(extract(epoch from (now() - v_ref)) / 86400)::integer;
    if v_passados < v_alvo then continue; end if;
    if exists (select 1 from public.documentos_lembretes_enviados
                where user_id = v_uid and enviado_em > now() - interval '20 hours') then continue; end if;

    v_corpo := public._robo_documentos_texto_pedido(v_faltas);
    perform public._provider_atividade_avisar(v_uid, 'Faltam documentos na tua candidatura', v_corpo);
    perform public._robo_documentos_email(v_uid, 'Bora: faltam documentos para aprovarmos a tua conta',
      'Olá! ' || v_corpo || ' Se precisares de ajuda, responde a este email.');
    insert into public.documentos_lembretes_enviados (user_id, dia, quem, faltas) values (v_uid, v_alvo, 'cron', v_faltas);
    n_enviados := n_enviados + 1;
  end loop;

  insert into public.e2e_log (fluxo, passo, estado, detalhe, device)
  values ('robo-documentos', 'lembretes', 'ok', 'candidatos=' || n_vistos || ' enviados=' || n_enviados, 'servidor');
  return jsonb_build_object('ok', true, 'candidatos', n_vistos, 'enviados', n_enviados);
end
$f$;
revoke all on function public.robo_documentos_lembretes_correr(boolean) from public, anon, authenticated;
grant execute on function public.robo_documentos_lembretes_correr(boolean) to service_role;

-- 09:00 e 10:00 UTC; a funcao so avanca quando em Lisboa sao as 10 (hora de verao incluida).
select cron.schedule('robo-documentos-lembretes', '0 9,10 * * *', 'select public.robo_documentos_lembretes_correr()');

-- ── R7: painel (so admin) ─────────────────────────────────────────────────────────
create or replace function public.admin_robo_documentos_config()
returns jsonb language plpgsql security definer set search_path to 'public' as $f$
begin
  if not public.is_admin() then raise exception 'admin_required' using errcode = '42501'; end if;
  return public._robo_documentos_cfg() || jsonb_build_object(
    'a_agir', public._robo_documentos_age(),
    'analises_24h', (select count(*) from public.documentos_verificacoes
                      where created_at > now() - interval '24 hours' and modelo is not null),
    'total', (select count(*) from public.documentos_verificacoes));
end
$f$;

create or replace function public.admin_robo_documentos_definir(p_chave text, p_valor jsonb)
returns jsonb language plpgsql security definer set search_path to 'public' as $f$
declare
  v_corte jsonb;
begin
  if not public.is_admin() then raise exception 'admin_required' using errcode = '42501'; end if;
  if p_chave = 'robo_documentos_ativo' then
    if jsonb_typeof(p_valor) <> 'boolean' then raise exception 'valor_invalido'; end if;
  elsif p_chave = 'robo_documentos_modo' then
    if p_valor not in ('"sombra"'::jsonb, '"ativo"'::jsonb) then raise exception 'valor_invalido'; end if;
  elsif p_chave = 'robo_documentos_confianca_min' then
    if jsonb_typeof(p_valor) <> 'number' or (p_valor #>> '{}')::numeric < 0.5 or (p_valor #>> '{}')::numeric > 1 then
      raise exception 'valor_invalido';
    end if;
  elsif p_chave = 'robo_documentos_limite_dia' then
    if jsonb_typeof(p_valor) <> 'number' or (p_valor #>> '{}')::numeric < 0 or (p_valor #>> '{}')::numeric > 2000 then
      raise exception 'valor_invalido';
    end if;
  else
    raise exception 'chave_invalida';
  end if;
  update public.platform_settings set value = p_valor, updated_at = now(), updated_by = auth.uid() where key = p_chave;
  -- A primeira vez que o robo passa a agir marca a hora da ativacao: so entra nos avisos automaticos quem
  -- se registar ou enviar depois dela.
  if p_chave = 'robo_documentos_ativo' and p_valor = 'true'::jsonb then
    select value into v_corte from public.platform_settings where key = 'robo_documentos_corte';
    if v_corte is null or v_corte = 'null'::jsonb then
      update public.platform_settings
         set value = to_jsonb(to_char(now() at time zone 'utc', 'YYYY-MM-DD"T"HH24:MI:SS"Z"')), updated_at = now(), updated_by = auth.uid()
       where key = 'robo_documentos_corte';
    end if;
  end if;
  perform public.log_admin_action('robo_documentos_definir'::text, 'platform_settings'::text, p_chave::text,
    jsonb_build_object('valor', p_valor));
  return public.admin_robo_documentos_config();
end
$f$;

create or replace function public.admin_documentos_verificacoes(p_user_id uuid default null, p_limite integer default 200)
returns jsonb language plpgsql security definer set search_path to 'public' as $f$
begin
  if not public.is_admin() then raise exception 'admin_required' using errcode = '42501'; end if;
  return coalesce((
    select jsonb_agg(to_jsonb(x) order by x.id desc) from (
      select dv.id, dv.user_id, public._robo_documentos_nome_conta(dv.user_id) as nome, dv.papel, dv.campo,
             dv.tipo_documento_esperado, dv.tipo_detectado, dv.legivel, dv.nome_bate, dv.nif_bate, dv.validade,
             dv.confianca, dv.motivo_pt, dv.decisao, dv.acao, dv.modo, dv.modelo, dv.path, dv.created_at,
             dv.revertido_em
        from public.documentos_verificacoes dv
       where p_user_id is null or dv.user_id = p_user_id
       order by dv.id desc
       limit least(greatest(coalesce(p_limite, 200), 1), 1000)
    ) x), '[]'::jsonb);
end
$f$;

create or replace function public.admin_documentos_prontos()
returns jsonb language plpgsql security definer set search_path to 'public' as $f$
begin
  if not public.is_admin() then raise exception 'admin_required' using errcode = '42501'; end if;
  return coalesce((
    select jsonb_agg(jsonb_build_object(
             'user_id', z.u, 'nome', public._robo_documentos_nome_conta(z.u),
             'papeis', public._provider_atividade_papeis(z.u),
             'desde', public._provider_atividade_ultima_candidatura(z.u)) order by z.u)
      from (
        select distinct x.u from (
          select user_id as u from public.drivers where approval_status = 'pending' and deleted_at is null
          union select user_id from public.cleaners where approval_status = 'pending'
          union select user_id from public.washers where approval_status = 'pending'
          union select user_id from public.service_providers where approval_status = 'pending'
        ) x where x.u is not null and not public.is_demo_user(x.u)
      ) z where public._robo_documentos_pronto(z.u)), '[]'::jsonb);
end
$f$;

-- Desfaz o que o robo fez: se recusou o comprovativo, volta a "em analise" (sem avisar ninguem);
-- fica registado quem desfez e quando.
create or replace function public.admin_documentos_desfazer(p_id bigint)
returns jsonb language plpgsql security definer set search_path to 'public' as $f$
declare
  v public.documentos_verificacoes;
  a public.provider_atividade;
begin
  if not public.is_admin() then raise exception 'admin_required' using errcode = '42501'; end if;
  select * into v from public.documentos_verificacoes where id = p_id for update;
  if not found then raise exception 'nao_existe'; end if;
  if v.revertido_em is not null then raise exception 'ja_desfeito'; end if;
  if v.acao = 'recusado' and v.campo = 'provider_atividade.documento_path' then
    select * into a from public.provider_atividade where user_id = v.user_id;
    if a.atividade_status = 'recusada' and a.documento_path is not distinct from v.path then
      perform public.admin_provider_atividade_decidir(v.user_id, 'em_analise', null, false);
    end if;
  end if;
  update public.documentos_verificacoes set revertido_por = auth.uid(), revertido_em = now() where id = p_id;
  perform public.log_admin_action('robo_documentos_desfazer'::text, 'documentos_verificacoes'::text, p_id::text,
    jsonb_build_object('user_id', v.user_id, 'acao', v.acao, 'campo', v.campo));
  return jsonb_build_object('ok', true, 'id', p_id, 'acao_desfeita', v.acao);
end
$f$;

-- "Lembrar este": so vai a quem o Danilo escolher (nunca em massa). Funciona mesmo com o robo em sombra.
create or replace function public.admin_robo_documentos_lembrar(p_user_id uuid)
returns jsonb language plpgsql security definer set search_path to 'public' as $f$
declare
  v_faltas text[];
  v_corpo text;
begin
  if not public.is_admin() then raise exception 'admin_required' using errcode = '42501'; end if;
  if public.is_demo_user(p_user_id) then return jsonb_build_object('ok', false, 'motivo', 'demo'); end if;
  v_faltas := public._robo_documentos_faltas(p_user_id);
  if coalesce(array_length(v_faltas, 1), 0) = 0 then
    return jsonb_build_object('ok', false, 'motivo', 'nada_a_pedir');
  end if;
  v_corpo := public._robo_documentos_texto_pedido(v_faltas);
  perform public._provider_atividade_avisar(p_user_id, 'Faltam documentos na tua candidatura', v_corpo);
  perform public._robo_documentos_email(p_user_id, 'Bora: faltam documentos para aprovarmos a tua conta',
    'Olá! ' || v_corpo || ' Se precisares de ajuda, responde a este email.');
  insert into public.documentos_lembretes_enviados (user_id, dia, quem, faltas) values (p_user_id, 0, 'painel', v_faltas);
  perform public.log_admin_action('robo_documentos_lembrar'::text, 'documentos_verificacoes'::text, p_user_id::text,
    jsonb_build_object('faltas', v_faltas));
  return jsonb_build_object('ok', true, 'faltas', v_faltas, 'mensagem', v_corpo);
end
$f$;

-- Botao "Analisar pendentes agora": manda ver tudo o que esta pendente, SEMPRE em sombra (so olha e regista).
create or replace function public.admin_robo_documentos_varrer(p_reverificar boolean default false)
returns jsonb language plpgsql security definer set search_path to 'public' as $f$
begin
  if not public.is_admin() then raise exception 'admin_required' using errcode = '42501'; end if;
  return public.robo_documentos_varrer(true, coalesce(p_reverificar, false));
end
$f$;

-- ── R8: a app do candidato (so o proprio; so mostra veredito com o robo a agir) ───────────────
create or replace function public.provider_documentos_estado()
returns jsonb language plpgsql security definer set search_path to 'public' as $f$
declare
  v_uid uuid := auth.uid();
  al jsonb;
  x jsonb;
  v record;
  itens jsonb := '[]'::jsonb;
begin
  if v_uid is null then raise exception 'sem_sessao' using errcode = '42501'; end if;
  if not public._robo_documentos_age() then
    return jsonb_build_object('ativo', false, 'itens', itens);
  end if;
  al := public._robo_documentos_alvos(v_uid);
  for x in select * from jsonb_array_elements(al -> 'alvos') loop
    select dv.decisao, dv.motivo_pt, dv.acao into v from public.documentos_verificacoes dv
     where dv.user_id = v_uid and dv.campo = x ->> 'campo' and dv.path = x ->> 'path' and dv.revertido_em is null
     order by dv.id desc limit 1;
    if found then
      itens := itens || jsonb_build_array(jsonb_build_object(
        'campo', x ->> 'campo',
        'decisao', case when v.decisao = 'errado' and v.acao = 'nenhuma' then 'duvida' else v.decisao end,
        'motivo_pt', case when v.decisao = 'errado' and v.acao <> 'nenhuma' then v.motivo_pt else null end));
    end if;
  end loop;
  return jsonb_build_object('ativo', true, 'itens', itens);
end
$f$;

-- Permissoes: nada para anon; o painel e a app entram com sessao (cada funcao confirma quem e).
revoke all on function public.admin_robo_documentos_config() from public, anon;
revoke all on function public.admin_robo_documentos_definir(text, jsonb) from public, anon;
revoke all on function public.admin_documentos_verificacoes(uuid, integer) from public, anon;
revoke all on function public.admin_documentos_prontos() from public, anon;
revoke all on function public.admin_documentos_desfazer(bigint) from public, anon;
revoke all on function public.admin_robo_documentos_lembrar(uuid) from public, anon;
revoke all on function public.admin_robo_documentos_varrer(boolean) from public, anon;
revoke all on function public.provider_documentos_estado() from public, anon;
grant execute on function public.admin_robo_documentos_config() to authenticated;
grant execute on function public.admin_robo_documentos_definir(text, jsonb) to authenticated;
grant execute on function public.admin_documentos_verificacoes(uuid, integer) to authenticated;
grant execute on function public.admin_documentos_prontos() to authenticated;
grant execute on function public.admin_documentos_desfazer(bigint) to authenticated;
grant execute on function public.admin_robo_documentos_lembrar(uuid) to authenticated;
grant execute on function public.admin_robo_documentos_varrer(boolean) to authenticated;
grant execute on function public.provider_documentos_estado() to authenticated;
