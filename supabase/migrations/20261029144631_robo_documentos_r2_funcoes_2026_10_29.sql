-- Robo "fiscal de documentos" (missao final-app-2026-10-29, adendo 3, R2/R4): funcoes de apoio e de decisao.
-- Tudo isto so le tabelas de candidatos e nunca aprova nada. Fechado a anon e a authenticated:
-- so o servidor (service_role) chama. As funcoes do painel e da app vem noutra migracao.

create or replace function public._robo_documentos_cfg()
returns jsonb language sql stable security definer set search_path to 'public' as $f$
  select jsonb_build_object(
    'ativo', coalesce((select (value #>> '{}')::boolean from public.platform_settings where key = 'robo_documentos_ativo'), false),
    'modo', coalesce((select value #>> '{}' from public.platform_settings where key = 'robo_documentos_modo'), 'sombra'),
    'confianca_min', coalesce((select (value #>> '{}')::numeric from public.platform_settings where key = 'robo_documentos_confianca_min'), 0.85),
    'limite_dia', coalesce((select (value #>> '{}')::integer from public.platform_settings where key = 'robo_documentos_limite_dia'), 200),
    'lembretes_dias', coalesce((select value from public.platform_settings where key = 'robo_documentos_lembretes_dias'), '[1,3,7]'::jsonb),
    'corte', (select nullif(value #>> '{}', '')::timestamptz from public.platform_settings where key = 'robo_documentos_corte')
  );
$f$;

create or replace function public._robo_documentos_age()
returns boolean language sql stable security definer set search_path to 'public' as $f$
  select coalesce((x.c ->> 'ativo')::boolean, false) and (x.c ->> 'modo') = 'ativo'
  from (select public._robo_documentos_cfg() as c) x;
$f$;

create or replace function public._robo_documentos_admin_uid()
returns uuid language sql stable security definer set search_path to 'public' as $f$
  select id from auth.users where coalesce(raw_app_meta_data ->> 'role', '') = 'admin' order by created_at limit 1;
$f$;

create or replace function public._robo_documentos_juntar(p text[])
returns text language sql immutable as $f$
  select case coalesce(array_length(p, 1), 0)
    when 0 then ''
    when 1 then p[1]
    else array_to_string(p[1:array_length(p, 1) - 1], ', ') || ' e ' || p[array_length(p, 1)]
  end;
$f$;

create or replace function public._robo_documentos_nome_conta(p_uid uuid)
returns text language sql stable security definer set search_path to 'public' as $f$
  select coalesce(
    (select nullif(btrim(coalesce(nullif(d.legal_name, ''), d.name, '')), '') from public.drivers d where d.user_id = p_uid and d.deleted_at is null limit 1),
    (select nullif(btrim(coalesce(nullif(c.legal_name, ''), c.name, '')), '') from public.cleaners c where c.user_id = p_uid limit 1),
    (select nullif(btrim(coalesce(nullif(w.legal_name, ''), w.name, '')), '') from public.washers w where w.user_id = p_uid limit 1),
    (select nullif(btrim(coalesce(nullif(s.legal_name, ''), s.name, '')), '') from public.service_providers s where s.user_id = p_uid limit 1),
    (select nullif(btrim(u.name), '') from public.users u where u.id = p_uid)
  );
$f$;

create or replace function public._robo_documentos_nif_conta(p_uid uuid)
returns text language sql stable security definer set search_path to 'public' as $f$
  select coalesce(
    (select nullif(regexp_replace(coalesce(a.nif, ''), '\D', '', 'g'), '') from public.provider_atividade a where a.user_id = p_uid),
    (select nullif(regexp_replace(coalesce(d.nif, ''), '\D', '', 'g'), '') from public.drivers d where d.user_id = p_uid and d.deleted_at is null limit 1),
    (select nullif(regexp_replace(coalesce(c.nif, ''), '\D', '', 'g'), '') from public.cleaners c where c.user_id = p_uid limit 1),
    (select nullif(regexp_replace(coalesce(w.nif, ''), '\D', '', 'g'), '') from public.washers w where w.user_id = p_uid limit 1),
    (select nullif(regexp_replace(coalesce(s.nif, ''), '\D', '', 'g'), '') from public.service_providers s where s.user_id = p_uid limit 1)
  );
$f$;

-- Um URL assinado, "balde/caminho" ou caminho solto -> {bucket, path}. null se nao der.
create or replace function public._robo_documentos_caminho(p_valor text, p_balde text)
returns jsonb language plpgsql immutable as $f$
declare
  m text[];
  v text := nullif(btrim(coalesce(p_valor, '')), '');
begin
  if v is null then return null; end if;
  m := regexp_match(v, '/object/(?:sign|public|authenticated)/([^/?]+)/([^?]+)');
  if m is not null then return jsonb_build_object('bucket', m[1], 'path', m[2]); end if;
  if v ~* '^https?://' then return null; end if;
  if left(v, length(p_balde) + 1) = p_balde || '/' then
    return jsonb_build_object('bucket', p_balde, 'path', substr(v, length(p_balde) + 2));
  end if;
  return jsonb_build_object('bucket', p_balde, 'path', v);
end
$f$;

create or replace function public._robo_documentos_item(p_papel text, p_campo text, p_tipo text, p_valor text, p_balde text)
returns jsonb language sql immutable as $f$
  select case when x.c is null then null
              else jsonb_build_object('papel', p_papel, 'campo', p_campo, 'tipo_esperado', p_tipo) || x.c end
  from (select public._robo_documentos_caminho(p_valor, p_balde) as c) x;
$f$;

create or replace function public._robo_documentos_somar(p_v jsonb, p_x jsonb)
returns jsonb language sql immutable as $f$
  select case when p_x is null then p_v else p_v || jsonb_build_array(p_x) end;
$f$;

-- Os documentos que a pessoa tem agora, com o balde e o caminho. Nome e NIF da conta so servem
-- para o servidor comparar (nunca se guardam na tabela dos vereditos).
create or replace function public._robo_documentos_alvos(p_user_id uuid)
returns jsonb language plpgsql stable security definer set search_path to 'public' as $f$
declare
  v jsonb := '[]'::jsonb;
  r record;
  a record;
  pend boolean;
begin
  pend := exists (select 1 from public.drivers where user_id = p_user_id and deleted_at is null and approval_status = 'pending')
       or exists (select 1 from public.cleaners where user_id = p_user_id and approval_status = 'pending')
       or exists (select 1 from public.washers where user_id = p_user_id and approval_status = 'pending')
       or exists (select 1 from public.service_providers where user_id = p_user_id and approval_status = 'pending');

  select documento_path into a from public.provider_atividade where user_id = p_user_id and documento_path is not null;
  if found then
    v := public._robo_documentos_somar(v, public._robo_documentos_item(
      coalesce((public._provider_atividade_papeis(p_user_id))[1], 'prestador'),
      'provider_atividade.documento_path', 'comprovativo_atividade_AT', a.documento_path, 'provider-atividade'));
  end if;

  for r in select vehicle_type, registration_selfie_url, document_photo_url, vehicle_photo_url, vehicle_doc_url
             from public.drivers
            where user_id = p_user_id and deleted_at is null and coalesce(approval_status, '') <> 'rejected'
  loop
    declare p text := case when r.vehicle_type = 'carro_passageiros' then 'motorista_tvde' else 'estafeta' end;
    begin
      v := public._robo_documentos_somar(v, public._robo_documentos_item(p, 'drivers.registration_selfie_url', 'selfie', r.registration_selfie_url, 'driver-documents'));
      v := public._robo_documentos_somar(v, public._robo_documentos_item(p, 'drivers.document_photo_url', 'documento_identificacao', r.document_photo_url, 'driver-documents'));
      v := public._robo_documentos_somar(v, public._robo_documentos_item(p, 'drivers.vehicle_photo_url', 'foto_veiculo', r.vehicle_photo_url, 'driver-documents'));
      v := public._robo_documentos_somar(v, public._robo_documentos_item(p, 'drivers.vehicle_doc_url', 'documento_veiculo', r.vehicle_doc_url, 'driver-documents'));
    end;
  end loop;

  for r in select docs from public.cleaners where user_id = p_user_id and approval_status <> 'rejected' loop
    v := public._robo_documentos_somar(v, public._robo_documentos_item('limpeza', 'cleaners.docs.id_doc', 'documento_identificacao',
           case when jsonb_typeof(r.docs -> 'id_doc') = 'string' then r.docs ->> 'id_doc' end, 'cleaner-documents'));
  end loop;

  for r in select docs from public.washers where user_id = p_user_id and approval_status <> 'rejected' loop
    v := public._robo_documentos_somar(v, public._robo_documentos_item('lavagem', 'washers.docs.id_doc', 'documento_identificacao',
           case when jsonb_typeof(r.docs -> 'id_doc') = 'string' then r.docs ->> 'id_doc' end, 'washer-documents'));
    v := public._robo_documentos_somar(v, public._robo_documentos_item('lavagem', 'washers.docs.driving_license', 'carta_conducao',
           case when jsonb_typeof(r.docs -> 'driving_license') = 'string' then r.docs ->> 'driving_license' end, 'washer-documents'));
  end loop;

  return jsonb_build_object('pendente', pend, 'nome_conta', public._robo_documentos_nome_conta(p_user_id),
                            'nif_conta', public._robo_documentos_nif_conta(p_user_id), 'alvos', v);
end
$f$;

-- O que falta a esta candidatura (so documentos), com as mesmas palavras e a mesma regra das apps
-- (driver_documentos.dart e prestador_documentos.dart). Motorista TVDE fica de fora (tem a sua conformidade).
create or replace function public._robo_documentos_faltas(p_user_id uuid)
returns text[] language plpgsql stable security definer set search_path to 'public' as $f$
declare
  f text[] := '{}';
  r record;
  a record;
  cfg record;
  quer_atividade boolean := false;
  obrig boolean;
begin
  for r in select vehicle_type, photo_url, registration_selfie_url, document_photo_url, document_number, vehicle_photo_url, license_plate
             from public.drivers
            where user_id = p_user_id and deleted_at is null and approval_status = 'pending'
              and coalesce(vehicle_type, '') <> 'carro_passageiros'
  loop
    quer_atividade := true;
    if nullif(btrim(coalesce(r.photo_url, '')), '') is null and nullif(btrim(coalesce(r.registration_selfie_url, '')), '') is null then
      f := f || 'foto pessoal (selfie)'; end if;
    if nullif(btrim(coalesce(r.document_photo_url, '')), '') is null then f := f || 'foto do documento'; end if;
    if nullif(btrim(coalesce(r.document_number, '')), '') is null then f := f || 'número do documento'; end if;
    if coalesce(r.vehicle_type, '') <> 'bicycle' then
      if nullif(btrim(coalesce(r.vehicle_photo_url, '')), '') is null then f := f || 'foto do veículo'; end if;
      if nullif(btrim(coalesce(r.license_plate, '')), '') is null then f := f || 'matrícula'; end if;
    end if;
  end loop;

  for r in select photo_url, docs from public.cleaners where user_id = p_user_id and approval_status = 'pending' loop
    quer_atividade := true;
    if nullif(btrim(coalesce(r.photo_url, '')), '') is null then f := f || 'foto de perfil'; end if;
    if nullif(btrim(case when jsonb_typeof(r.docs -> 'id_doc') = 'string' then r.docs ->> 'id_doc' else '' end), '') is null then
      f := f || 'documento de identificação'; end if;
  end loop;

  for r in select photo_url, docs from public.washers where user_id = p_user_id and approval_status = 'pending' loop
    quer_atividade := true;
    if nullif(btrim(coalesce(r.photo_url, '')), '') is null then f := f || 'foto de perfil'; end if;
    if nullif(btrim(case when jsonb_typeof(r.docs -> 'id_doc') = 'string' then r.docs ->> 'id_doc' else '' end), '') is null then
      f := f || 'documento de identificação'; end if;
    if nullif(btrim(case when jsonb_typeof(r.docs -> 'driving_license') = 'string' then r.docs ->> 'driving_license' else '' end), '') is null then
      f := f || 'carta de condução'; end if;
  end loop;

  if exists (select 1 from public.service_providers where user_id = p_user_id and approval_status = 'pending') then
    quer_atividade := true;
  end if;

  if quer_atividade then
    select * into cfg from public._provider_atividade_config();
    select * into a from public.provider_atividade where user_id = p_user_id;
    obrig := coalesce(a.obrigatoria,
      coalesce(cfg.ligado, false) and cfg.corte is not null
        and coalesce(public._provider_atividade_ultima_candidatura(p_user_id) >= cfg.corte, false));
    if obrig and (a.documento_path is null or a.atividade_status = 'recusada') then
      f := f || 'comprovativo de atividade';
    end if;
  end if;
  return f;
end
$f$;

-- Tem tudo e tudo certo? (candidatura pendente, nada em falta, cada documento com veredito ok ou
-- comprovativo ja aprovado). So serve para dizer ao Danilo "falta so aprovares".
create or replace function public._robo_documentos_pronto(p_uid uuid)
returns boolean language plpgsql stable security definer set search_path to 'public' as $f$
declare
  al jsonb := public._robo_documentos_alvos(p_uid);
  x jsonb;
  v text;
  st text;
  n integer := 0;
begin
  if not coalesce((al ->> 'pendente')::boolean, false) then return false; end if;
  if coalesce(array_length(public._robo_documentos_faltas(p_uid), 1), 0) > 0 then return false; end if;
  for x in select * from jsonb_array_elements(al -> 'alvos') loop
    if x ->> 'campo' = 'provider_atividade.documento_path' then
      select atividade_status into st from public.provider_atividade where user_id = p_uid;
      if st = 'aprovada' then n := n + 1; continue; end if;
    end if;
    select dv.decisao into v from public.documentos_verificacoes dv
     where dv.user_id = p_uid and dv.campo = x ->> 'campo' and dv.path = x ->> 'path' and dv.revertido_em is null
     order by dv.id desc limit 1;
    if v is distinct from 'ok' then return false; end if;
    n := n + 1;
  end loop;
  return n > 0;
end
$f$;

-- Chama a Edge Function verificar-documento (pg_net, assincrono; sem espera).
create or replace function public._robo_documentos_chamar(p_corpo jsonb)
returns bigint language plpgsql security definer set search_path to 'public' as $f$
declare
  v_key text;
  v_url text;
  v_header jsonb;
  v_req bigint;
begin
  select decrypted_secret into v_key from vault.decrypted_secrets where name = 'sb_secret_backend';
  if v_key is not null then
    v_header := jsonb_build_object('apikey', v_key, 'Content-Type', 'application/json');
  else
    select decrypted_secret into v_key from vault.decrypted_secrets where name = 'service_role_key';
    if v_key is not null then
      v_header := jsonb_build_object('apikey', v_key, 'Authorization', 'Bearer ' || v_key, 'Content-Type', 'application/json');
    end if;
  end if;
  select decrypted_secret into v_url from vault.decrypted_secrets where name = 'project_url';
  if v_header is null then
    insert into public.e2e_log (fluxo, passo, estado, detalhe, device)
    values ('robo-documentos', 'chamar', 'falhou', 'sem chave no cofre', 'servidor');
    return null;
  end if;
  select net.http_post(
    url := coalesce(v_url, 'https://ojykpzwqrtusfeakzrna.supabase.co') || '/functions/v1/verificar-documento',
    headers := v_header, body := p_corpo, timeout_milliseconds := 60000) into v_req;
  return v_req;
exception when others then
  insert into public.e2e_log (fluxo, passo, estado, detalhe, device)
  values ('robo-documentos', 'chamar', 'falhou', sqlerrm, 'servidor');
  return null;
end
$f$;

-- Email da conta de suporte (agentes-email-enviar). Nunca a contas de demonstracao.
create or replace function public._robo_documentos_email(p_uid uuid, p_assunto text, p_texto text)
returns bigint language plpgsql security definer set search_path to 'public' as $f$
declare
  v_key text;
  v_url text;
  v_header jsonb;
  v_to text;
  v_req bigint;
begin
  if public.is_demo_user(p_uid) then return null; end if;
  select u.email into v_to from auth.users u where u.id = p_uid;
  if v_to is null or v_to !~ '^[^\s@]+@[^\s@]+\.[A-Za-z]{2,}$' then return null; end if;
  select decrypted_secret into v_key from vault.decrypted_secrets where name = 'sb_secret_backend';
  if v_key is not null then
    v_header := jsonb_build_object('apikey', v_key, 'Content-Type', 'application/json');
  else
    select decrypted_secret into v_key from vault.decrypted_secrets where name = 'service_role_key';
    if v_key is not null then
      v_header := jsonb_build_object('apikey', v_key, 'Authorization', 'Bearer ' || v_key, 'Content-Type', 'application/json');
    end if;
  end if;
  select decrypted_secret into v_url from vault.decrypted_secrets where name = 'project_url';
  if v_header is null then return null; end if;
  select net.http_post(
    url := coalesce(v_url, 'https://ojykpzwqrtusfeakzrna.supabase.co') || '/functions/v1/agentes-email-enviar',
    headers := v_header,
    body := jsonb_build_object('agente', 'suporte', 'para', v_to, 'assunto', p_assunto, 'texto', p_texto,
                               'idempotencia', 'robo-doc-' || md5(p_uid::text || p_assunto || p_texto || current_date::text))) into v_req;
  return v_req;
exception when others then
  insert into public.e2e_log (fluxo, passo, estado, detalhe, device)
  values ('robo-documentos', 'email', 'falhou', sqlerrm, 'servidor');
  return null;
end
$f$;

-- Texto do pedido (PT-PT, "tu"): o que falta e como enviar. Nunca fala de pouca procura.
create or replace function public._robo_documentos_texto_pedido(p_faltas text[])
returns text language sql immutable as $f$
  select 'Para entrares na fila de aprovação, envia o que falta: ' || public._robo_documentos_juntar(p_faltas)
         || '. Abre a app Bora e envia em "Falta enviar" — aparece logo à entrada.';
$f$;

-- Aplica o veredito (so no modo ativo e com o interruptor ligado). NUNCA aprova nada.
--  - comprovativo errado: recusa pelo mesmo caminho do painel (admin_provider_atividade_decidir, via robo-documentos)
--  - outro documento errado: aviso pelo caminho do _provider_atividade_avisar (app + push)
--  - tudo certo: so avisa o Danilo que falta aprovar
-- Em ambos os casos de erro tambem sai um email do suporte com o que falta.
create or replace function public.robo_documentos_aplicar(p_id bigint)
returns jsonb language plpgsql security definer set search_path to 'public' as $f$
declare
  v public.documentos_verificacoes;
  cfg jsonb := public._robo_documentos_cfg();
  al jsonb;
  at_row public.provider_atividade;
  admin_id uuid;
  faltas text[];
  corpo text;
  nome text;
  texto_lembrete text;
begin
  select * into v from public.documentos_verificacoes where id = p_id;
  if not found then return jsonb_build_object('ok', false, 'erro', 'nao_existe'); end if;
  if v.modo <> 'ativo' or not public._robo_documentos_age() then
    return jsonb_build_object('ok', true, 'acao', 'nenhuma', 'porque', 'sombra');
  end if;
  if v.revertido_em is not null or v.acao <> 'nenhuma' then
    return jsonb_build_object('ok', true, 'acao', 'nenhuma', 'porque', 'ja_tratado');
  end if;
  if public.is_demo_user(v.user_id) then
    return jsonb_build_object('ok', true, 'acao', 'nenhuma', 'porque', 'demo');
  end if;
  al := public._robo_documentos_alvos(v.user_id);
  if not coalesce((al ->> 'pendente')::boolean, false) then
    return jsonb_build_object('ok', true, 'acao', 'nenhuma', 'porque', 'nao_pendente');
  end if;

  if v.decisao = 'errado' and coalesce(v.confianca, 0) >= coalesce((cfg ->> 'confianca_min')::numeric, 0.85) then
    if v.campo = 'provider_atividade.documento_path' then
      select * into at_row from public.provider_atividade where user_id = v.user_id;
      if at_row.documento_path is distinct from v.path or at_row.atividade_status <> 'em_analise' then
        return jsonb_build_object('ok', true, 'acao', 'nenhuma', 'porque', 'estado_mudou');
      end if;
      admin_id := public._robo_documentos_admin_uid();
      if admin_id is null then return jsonb_build_object('ok', false, 'erro', 'sem_admin'); end if;
      perform set_config('request.jwt.claim.sub', admin_id::text, true);
      perform set_config('bora.agente', 'robo-documentos', true);
      perform public.admin_provider_atividade_decidir(v.user_id, 'recusar', v.motivo_pt, true);
      perform set_config('bora.agente', '', true);
      perform set_config('request.jwt.claim.sub', '', true);
      update public.documentos_verificacoes set acao = 'recusado' where id = p_id;
      faltas := public._robo_documentos_faltas(v.user_id);
      corpo := 'Olá! ' || v.motivo_pt || ' ' || public._robo_documentos_texto_pedido(faltas);
    else
      faltas := public._robo_documentos_faltas(v.user_id);
      corpo := v.motivo_pt || case when coalesce(array_length(faltas, 1), 0) > 0
                then ' Falta também: ' || public._robo_documentos_juntar(faltas) || '.' else '' end
               || ' Abre a app Bora e envia de novo em "Falta enviar".';
      perform public._provider_atividade_avisar(v.user_id, 'Documento a corrigir na tua candidatura', corpo);
      update public.documentos_verificacoes set acao = 'pedido' where id = p_id;
      corpo := 'Olá! ' || corpo;
    end if;
    perform public._robo_documentos_email(v.user_id, 'Bora: falta enviares o documento certo para aprovarmos a tua conta', corpo);
    return jsonb_build_object('ok', true, 'acao', case when v.campo = 'provider_atividade.documento_path' then 'recusado' else 'pedido' end);
  end if;

  if v.decisao = 'ok' and public._robo_documentos_pronto(v.user_id) then
    nome := coalesce(al ->> 'nome_conta', 'Uma candidatura');
    texto_lembrete := nome || ' tem tudo certo, falta só aprovares.';
    if not exists (select 1 from public.lembretes_danilo
                    where origem = 'robo-documentos' and link = v.user_id::text and created_at > now() - interval '3 days') then
      perform public.notify_admin_urgent_push('robo_documentos_pronto',
        nome || E' tem tudo certo\nFalta só aprovares. O robô não aprova nada.',
        'provider_atividade', v.user_id::text, jsonb_build_object('user_id', v.user_id), '/admin/documentos-robo');
      insert into public.lembretes_danilo (texto, link, quando, origem, urgente)
      values (texto_lembrete, v.user_id::text, now(), 'robo-documentos', false);
      return jsonb_build_object('ok', true, 'acao', 'nenhuma', 'pronto_para_aprovar', true);
    end if;
  end if;
  return jsonb_build_object('ok', true, 'acao', 'nenhuma');
end
$f$;

-- Fecha tudo ao publico e abre so ao servidor.
revoke all on function public._robo_documentos_cfg() from public, anon, authenticated;
revoke all on function public._robo_documentos_age() from public, anon, authenticated;
revoke all on function public._robo_documentos_admin_uid() from public, anon, authenticated;
revoke all on function public._robo_documentos_juntar(text[]) from public, anon, authenticated;
revoke all on function public._robo_documentos_nome_conta(uuid) from public, anon, authenticated;
revoke all on function public._robo_documentos_nif_conta(uuid) from public, anon, authenticated;
revoke all on function public._robo_documentos_caminho(text, text) from public, anon, authenticated;
revoke all on function public._robo_documentos_item(text, text, text, text, text) from public, anon, authenticated;
revoke all on function public._robo_documentos_somar(jsonb, jsonb) from public, anon, authenticated;
revoke all on function public._robo_documentos_alvos(uuid) from public, anon, authenticated;
revoke all on function public._robo_documentos_faltas(uuid) from public, anon, authenticated;
revoke all on function public._robo_documentos_pronto(uuid) from public, anon, authenticated;
revoke all on function public._robo_documentos_chamar(jsonb) from public, anon, authenticated;
revoke all on function public._robo_documentos_email(uuid, text, text) from public, anon, authenticated;
revoke all on function public._robo_documentos_texto_pedido(text[]) from public, anon, authenticated;
revoke all on function public.robo_documentos_aplicar(bigint) from public, anon, authenticated;
grant execute on function public._robo_documentos_alvos(uuid) to service_role;
grant execute on function public._robo_documentos_cfg() to service_role;
grant execute on function public.robo_documentos_aplicar(bigint) to service_role;
