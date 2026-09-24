-- motorista-ficha-legal-2026-09-23 · Blocos 1, 3, 4 (servidor) e 5
-- Lei 45/2018 revista pela Lei 59/2026 (em vigor 01/09/2026): o motorista TVDE
-- tem de mostrar na fiscalização a identificação dele, do veículo, do operador,
-- da plataforma, seguro, inspeção, dístico e a viagem em curso.
--
-- O que JÁ existia e se reaproveita (regra dos gémeos — não se duplica):
--   drivers.name / legal_name / photo_url / nif / license_plate /
--   vehicle_make_model / vehicle_color.
-- O que faltava vive numa tabela nova, uma linha por PESSOA (user_id manda).
-- Nada aqui mexe em preços, comissões ou valores cobrados: o recibo só LÊ
-- os números que a corrida já gravou.

-- ── 1. Ficha legal ──────────────────────────────────────────────────────────
create table if not exists public.motorista_ficha_legal (
  user_id uuid primary key references auth.users(id) on delete cascade,
  tvde_cert_numero text,
  tvde_cert_validade date,
  carta_numero text,
  carta_validade date,
  veiculo_ano integer check (veiculo_ano is null or veiculo_ano between 1980 and 2100),
  distico_numero text,
  distico_validade date,
  inspecao_validade date,
  seguro_seguradora text,
  seguro_apolice text,
  seguro_validade date,
  seguro_cobre_passageiros boolean,
  operador_nome text,
  operador_nif text,
  operador_licenca text,
  atualizado_em timestamptz not null default now(),
  atualizado_por uuid
);
alter table public.motorista_ficha_legal enable row level security;
drop policy if exists mfl_select_proprio_ou_admin on public.motorista_ficha_legal;
create policy mfl_select_proprio_ou_admin on public.motorista_ficha_legal
  for select to authenticated using (user_id = auth.uid() or public.is_admin());
-- Escrita só pelas RPCs abaixo (validam e auditam).

insert into public.platform_settings (key, value, description, category) values
  ('plataforma_nome', to_jsonb('Bora'::text), 'Nome do operador de plataforma TVDE mostrado na fiscalização', 'legal'),
  ('plataforma_nif', to_jsonb(''::text), 'NIF da empresa operadora da plataforma (vazio = "em processo")', 'legal'),
  ('plataforma_licenca_imt', to_jsonb(''::text), 'N.º de licença IMT de operador de plataforma TVDE (vazio = "em processo")', 'legal'),
  ('motorista_bloqueio_doc_expirado', 'true'::jsonb, 'Motorista TVDE com documento expirado não pode ficar online', 'legal'),
  ('motorista_docs_aviso_dias', '30'::jsonb, 'Dias de antecedência do aviso de documento a expirar', 'legal'),
  ('fiscalizacao_verificar_base_url', to_jsonb('https://boraguarda.com/verificar/'::text), 'Endereço público da página de verificação (o token vai no fim)', 'legal'),
  ('fiscalizacao_token_horas', '24'::jsonb, 'Validade do token da página pública de verificação', 'legal'),
  ('tvde_recibo_email_auto', 'true'::jsonb, 'Enviar recibo por email ao passageiro no fim de cada viagem TVDE', 'legal')
on conflict (key) do nothing;

-- ── Estado de cada documento (semáforo) ─────────────────────────────────────
create or replace function public._motorista_docs_estado(p_user uuid)
returns jsonb language plpgsql stable security definer set search_path to 'public' as $$
declare
  f public.motorista_ficha_legal;
  v_hoje date := (now() at time zone 'Europe/Lisbon')::date;
  v_aviso int := coalesce((public.get_setting('motorista_docs_aviso_dias') #>> '{}')::int, 30);
  v_out jsonb := '[]'::jsonb;
  r record;
begin
  select * into f from public.motorista_ficha_legal where user_id = p_user;
  for r in
    select * from (values
      ('certificado_tvde', 'Certificado TVDE (IMT)', f.tvde_cert_validade, 1),
      ('carta', 'Carta de condução', f.carta_validade, 2),
      ('seguro', 'Seguro do veículo', f.seguro_validade, 3),
      ('inspecao', 'Inspeção periódica', f.inspecao_validade, 4),
      ('distico', 'Dístico TVDE (IMT)', f.distico_validade, 5)
    ) as t(doc, rotulo, validade, ordem) order by ordem
  loop
    v_out := v_out || jsonb_build_object(
      'doc', r.doc, 'rotulo', r.rotulo, 'validade', r.validade,
      'dias', case when r.validade is null then null else r.validade - v_hoje end,
      'estado', case
        when r.validade is null then 'em_falta'
        when r.validade < v_hoje then 'expirado'
        when r.validade - v_hoje <= v_aviso then 'a_expirar'
        else 'valido' end);
  end loop;
  return v_out;
end $$;
revoke all on function public._motorista_docs_estado(uuid) from public;

-- ── Guardar a ficha (o próprio motorista) ───────────────────────────────────
create or replace function public._mfl_aplicar(p_user uuid, p jsonb, p_autor uuid)
returns void language plpgsql security definer set search_path to 'public' as $$
begin
  insert into public.motorista_ficha_legal as m (user_id, atualizado_por) values (p_user, p_autor)
  on conflict (user_id) do nothing;
  update public.motorista_ficha_legal m set
    tvde_cert_numero = case when p ? 'tvde_cert_numero' then nullif(trim(p->>'tvde_cert_numero'), '') else m.tvde_cert_numero end,
    tvde_cert_validade = case when p ? 'tvde_cert_validade' then nullif(p->>'tvde_cert_validade', '')::date else m.tvde_cert_validade end,
    carta_numero = case when p ? 'carta_numero' then nullif(trim(p->>'carta_numero'), '') else m.carta_numero end,
    carta_validade = case when p ? 'carta_validade' then nullif(p->>'carta_validade', '')::date else m.carta_validade end,
    veiculo_ano = case when p ? 'veiculo_ano' then nullif(p->>'veiculo_ano', '')::int else m.veiculo_ano end,
    distico_numero = case when p ? 'distico_numero' then nullif(trim(p->>'distico_numero'), '') else m.distico_numero end,
    distico_validade = case when p ? 'distico_validade' then nullif(p->>'distico_validade', '')::date else m.distico_validade end,
    inspecao_validade = case when p ? 'inspecao_validade' then nullif(p->>'inspecao_validade', '')::date else m.inspecao_validade end,
    seguro_seguradora = case when p ? 'seguro_seguradora' then nullif(trim(p->>'seguro_seguradora'), '') else m.seguro_seguradora end,
    seguro_apolice = case when p ? 'seguro_apolice' then nullif(trim(p->>'seguro_apolice'), '') else m.seguro_apolice end,
    seguro_validade = case when p ? 'seguro_validade' then nullif(p->>'seguro_validade', '')::date else m.seguro_validade end,
    seguro_cobre_passageiros = case when p ? 'seguro_cobre_passageiros' then (p->>'seguro_cobre_passageiros')::boolean else m.seguro_cobre_passageiros end,
    operador_nome = case when p ? 'operador_nome' then nullif(trim(p->>'operador_nome'), '') else m.operador_nome end,
    operador_nif = case when p ? 'operador_nif' then nullif(regexp_replace(p->>'operador_nif', '\s', '', 'g'), '') else m.operador_nif end,
    operador_licenca = case when p ? 'operador_licenca' then nullif(trim(p->>'operador_licenca'), '') else m.operador_licenca end,
    atualizado_em = now(), atualizado_por = p_autor
  where m.user_id = p_user;
  -- Os campos que já viviam em drivers continuam a viver lá (sem gémeos).
  update public.drivers d set
    license_plate = case when p ? 'matricula' then upper(nullif(trim(p->>'matricula'), '')) else d.license_plate end,
    vehicle_make_model = case when p ? 'marca_modelo' then nullif(trim(p->>'marca_modelo'), '') else d.vehicle_make_model end,
    vehicle_color = case when p ? 'cor' then nullif(trim(p->>'cor'), '') else d.vehicle_color end,
    updated_at = now()
  where d.user_id = p_user and (p ? 'matricula' or p ? 'marca_modelo' or p ? 'cor');
end $$;
revoke all on function public._mfl_aplicar(uuid, jsonb, uuid) from public;

create or replace function public.motorista_guardar_ficha_legal(p jsonb)
returns jsonb language plpgsql security definer set search_path to 'public' as $$
declare v_uid uuid := auth.uid();
begin
  if v_uid is null then raise exception 'sem_sessao'; end if;
  if not exists (select 1 from public.drivers where user_id = v_uid and deleted_at is null) then
    raise exception 'nao_e_motorista';
  end if;
  if p ? 'operador_nif' and nullif(p->>'operador_nif', '') is not null
     and regexp_replace(p->>'operador_nif', '\s', '', 'g') !~ '^[0-9]{9}$' then
    raise exception 'nif_operador_invalido' using hint = 'O NIF do operador tem 9 algarismos.';
  end if;
  perform public._mfl_aplicar(v_uid, p, v_uid);
  return jsonb_build_object('ok', true, 'documentos', public._motorista_docs_estado(v_uid));
end $$;
revoke all on function public.motorista_guardar_ficha_legal(jsonb) from public;
grant execute on function public.motorista_guardar_ficha_legal(jsonb) to authenticated;

create or replace function public.motorista_minha_ficha_legal()
returns jsonb language sql stable security definer set search_path to 'public' as $$
  select coalesce(to_jsonb(f), jsonb_build_object('user_id', auth.uid()))
         || jsonb_build_object('matricula', d.license_plate, 'marca_modelo', d.vehicle_make_model,
                               'cor', d.vehicle_color,
                               'documentos', public._motorista_docs_estado(auth.uid()))
  from public.drivers d
  left join public.motorista_ficha_legal f on f.user_id = d.user_id
  where d.user_id = auth.uid() and d.deleted_at is null
  limit 1
$$;
revoke all on function public.motorista_minha_ficha_legal() from public;
grant execute on function public.motorista_minha_ficha_legal() to authenticated;

-- ── Admin: editar a ficha de qualquer motorista ─────────────────────────────
create or replace function public.admin_guardar_ficha_legal(p_user uuid, p jsonb)
returns jsonb language plpgsql security definer set search_path to 'public' as $$
begin
  if not public.is_admin() then raise exception 'forbidden'; end if;
  perform public._mfl_aplicar(p_user, p, auth.uid());
  perform public.log_admin_action('motorista_ficha_legal_editar', 'driver', p_user::text, p);
  return jsonb_build_object('ok', true, 'documentos', public._motorista_docs_estado(p_user));
end $$;
revoke all on function public.admin_guardar_ficha_legal(uuid, jsonb) from public;
grant execute on function public.admin_guardar_ficha_legal(uuid, jsonb) to authenticated;

-- ── 2/3. Ficha de fiscalização + token de verificação ───────────────────────
create table if not exists public.fiscalizacao_tokens (
  token text primary key,
  user_id uuid not null references auth.users(id) on delete cascade,
  criado_em timestamptz not null default now(),
  expira_em timestamptz not null,
  consultas integer not null default 0,
  ultima_consulta timestamptz
);
create index if not exists fiscalizacao_tokens_user_idx on public.fiscalizacao_tokens(user_id, expira_em desc);
alter table public.fiscalizacao_tokens enable row level security;
drop policy if exists fisc_tokens_admin on public.fiscalizacao_tokens;
create policy fisc_tokens_admin on public.fiscalizacao_tokens for select to authenticated using (public.is_admin());

create or replace function public._fiscalizacao_viagem(p_user uuid, p_publica boolean)
returns jsonb language plpgsql stable security definer set search_path to 'public' as $$
declare r public.tvde_rides; v_inicio timestamptz; v_nome text; v_em_curso boolean := true;
begin
  select * into r from public.tvde_rides
   where driver_id = p_user
     and status in ('motorista_atribuido','motorista_a_caminho','motorista_chegou','em_andamento')
     and not coalesce(is_queued, false)
   order by (status = 'em_andamento') desc, updated_at desc limit 1;
  if not found then
    v_em_curso := false;
    select * into r from public.tvde_rides where driver_id = p_user and status = 'finalizada'
     order by updated_at desc limit 1;
    if not found then return null; end if;
  end if;
  select min(e.at) into v_inicio from public.tvde_ride_events e where e.ride_id = r.id and e.status = 'em_andamento';
  if p_publica then
    return jsonb_build_object('em_curso', v_em_curso, 'estado', r.status,
      'inicio', coalesce(v_inicio, r.created_at));
  end if;
  select nullif(trim(u.name), '') into v_nome from public.users u where u.id = r.client_id;
  return jsonb_build_object(
    'id', r.id, 'em_curso', v_em_curso, 'estado', r.status,
    'inicio', coalesce(v_inicio, r.created_at),
    'origem', r.origin_label, 'destino', r.dest_label,
    'preco_cents', coalesce(nullif(r.final_fare_cents, 0), nullif(r.agreed_fare_cents, 0), r.est_fare_cents),
    'preco_final', r.final_fare_cents is not null and r.status = 'finalizada',
    'pagamento', r.payment_method,
    'passageiro_inicial', case when v_nome is null then null else upper(left(v_nome, 1)) || '.' end);
end $$;
revoke all on function public._fiscalizacao_viagem(uuid, boolean) from public;

create or replace function public._fiscalizacao_dados(p_user uuid, p_publica boolean)
returns jsonb language plpgsql stable security definer set search_path to 'public' as $$
declare d public.drivers; f public.motorista_ficha_legal;
  v_pnif text := coalesce(public.get_setting('plataforma_nif') #>> '{}', '');
  v_plic text := coalesce(public.get_setting('plataforma_licenca_imt') #>> '{}', '');
begin
  select * into d from public.drivers where user_id = p_user and deleted_at is null limit 1;
  if not found then return null; end if;
  select * into f from public.motorista_ficha_legal where user_id = p_user;
  return jsonb_build_object(
    'motorista', jsonb_build_object(
      'nome', coalesce(nullif(trim(d.legal_name), ''), d.name),
      'foto', d.photo_url,
      'nif', case when p_publica then null else d.nif end,
      'tvde_cert_numero', f.tvde_cert_numero, 'tvde_cert_validade', f.tvde_cert_validade,
      'carta_numero', case when p_publica then
          case when f.carta_numero is null then null else '••••' || right(f.carta_numero, 3) end
        else f.carta_numero end,
      'carta_validade', f.carta_validade),
    'veiculo', jsonb_build_object(
      'matricula', d.license_plate, 'marca_modelo', d.vehicle_make_model, 'cor', d.vehicle_color,
      'ano', f.veiculo_ano, 'distico_numero', f.distico_numero, 'distico_validade', f.distico_validade,
      'inspecao_validade', f.inspecao_validade,
      'seguro_seguradora', f.seguro_seguradora,
      'seguro_apolice', case when p_publica then null else f.seguro_apolice end,
      'seguro_validade', f.seguro_validade, 'seguro_cobre_passageiros', f.seguro_cobre_passageiros),
    'operador', case when f.operador_nome is null then null else jsonb_build_object(
      'nome', f.operador_nome, 'nif', case when p_publica then null else f.operador_nif end,
      'licenca', f.operador_licenca) end,
    'plataforma', jsonb_build_object(
      'nome', coalesce(public.get_setting('plataforma_nome') #>> '{}', 'Bora'),
      'nif', case when p_publica or v_pnif = '' then null else v_pnif end,
      'licenca', nullif(v_plic, ''),
      'em_processo', v_plic = '' or v_pnif = ''),
    'documentos', public._motorista_docs_estado(p_user),
    'viagem', public._fiscalizacao_viagem(p_user, p_publica));
end $$;
revoke all on function public._fiscalizacao_dados(uuid, boolean) from public;

create or replace function public.motorista_ficha_fiscalizacao()
returns jsonb language plpgsql security definer set search_path to 'public' as $$
declare v_uid uuid := auth.uid(); v_dados jsonb; t public.fiscalizacao_tokens;
  v_horas int := coalesce((public.get_setting('fiscalizacao_token_horas') #>> '{}')::int, 24);
  v_base text := coalesce(public.get_setting('fiscalizacao_verificar_base_url') #>> '{}', 'https://boraguarda.com/verificar/');
begin
  if v_uid is null then raise exception 'sem_sessao'; end if;
  v_dados := public._fiscalizacao_dados(v_uid, false);
  if v_dados is null then raise exception 'nao_e_motorista'; end if;
  -- Reaproveita o token enquanto tiver pelo menos 1 h de vida (o QR não muda a cada abertura).
  select * into t from public.fiscalizacao_tokens
   where user_id = v_uid and expira_em > now() + interval '1 hour'
   order by expira_em desc limit 1;
  if not found then
    insert into public.fiscalizacao_tokens (token, user_id, expira_em)
    values (translate(encode(extensions.gen_random_bytes(8), 'base64'), '+/=', 'xyz'), v_uid,
            now() + make_interval(hours => v_horas))
    returning * into t;
  end if;
  return v_dados || jsonb_build_object('gerado_em', now(), 'verificacao', jsonb_build_object(
    'token', t.token, 'url', v_base || t.token, 'criado_em', t.criado_em, 'expira_em', t.expira_em));
end $$;
revoke all on function public.motorista_ficha_fiscalizacao() from public;
grant execute on function public.motorista_ficha_fiscalizacao() to authenticated;

-- Página pública: só leitura, sem NIF, sem morada, sem apólice, sem passageiro.
create or replace function public.verificar_ficha_publica(p_token text)
returns jsonb language plpgsql security definer set search_path to 'public' as $$
declare t public.fiscalizacao_tokens;
begin
  if p_token is null or length(p_token) < 8 or length(p_token) > 40 then
    return jsonb_build_object('ok', false, 'motivo', 'token_invalido');
  end if;
  select * into t from public.fiscalizacao_tokens where token = p_token;
  if not found then return jsonb_build_object('ok', false, 'motivo', 'token_invalido'); end if;
  if t.expira_em <= now() then
    return jsonb_build_object('ok', false, 'motivo', 'token_expirado', 'expirou_em', t.expira_em);
  end if;
  update public.fiscalizacao_tokens set consultas = consultas + 1, ultima_consulta = now() where token = p_token;
  return jsonb_build_object('ok', true, 'gerado_em', t.criado_em, 'expira_em', t.expira_em,
    'consultado_em', now()) || coalesce(public._fiscalizacao_dados(t.user_id, true), '{}'::jsonb);
end $$;
revoke all on function public.verificar_ficha_publica(text) from public;
grant execute on function public.verificar_ficha_publica(text) to anon, authenticated;

-- ── 5. Bloqueio de ficar online com documento expirado (TVDE) ───────────────
create or replace function public.fn_motorista_doc_expirado_online()
returns trigger language plpgsql security definer set search_path to 'public' as $$
declare v_exp text;
begin
  if coalesce(new.is_online, false) and not coalesce(old.is_online, false)
     and new.vehicle_type = 'carro_passageiros'
     and coalesce((public.get_setting('motorista_bloqueio_doc_expirado') #>> '{}')::boolean, true) then
    select string_agg(e->>'rotulo', ', ') into v_exp
      from jsonb_array_elements(public._motorista_docs_estado(new.user_id)) e
     where e->>'estado' = 'expirado';
    if v_exp is not null then
      raise exception 'DOCUMENTO_EXPIRADO: %', v_exp
        using hint = 'Atualiza a validade na Ficha legal (Fiscalização) para voltares a ficar online.';
    end if;
  end if;
  return new;
end $$;
drop trigger if exists trg_motorista_doc_expirado_online on public.drivers;
create trigger trg_motorista_doc_expirado_online before update of is_online on public.drivers
  for each row execute function public.fn_motorista_doc_expirado_online();

-- ── 5. Aviso automático (motorista + admin) ─────────────────────────────────
create table if not exists public.motorista_docs_alertas (
  id bigserial primary key,
  user_id uuid not null,
  doc text not null,
  validade date not null,
  estado text not null check (estado in ('a_expirar','expirado')),
  enviado_em timestamptz not null default now(),
  unique (user_id, doc, validade, estado)
);
alter table public.motorista_docs_alertas enable row level security;
drop policy if exists mda_admin on public.motorista_docs_alertas;
create policy mda_admin on public.motorista_docs_alertas for select to authenticated
  using (public.is_admin() or user_id = auth.uid());

create or replace function public.motorista_docs_alerta_diario()
returns jsonb language plpgsql security definer set search_path to 'public', 'net', 'vault' as $$
declare r record; v_url text; v_key text; n int := 0; v_resumo text := ''; v_titulo text; v_corpo text;
begin
  select decrypted_secret into v_url from vault.decrypted_secrets where name = 'project_url';
  select decrypted_secret into v_key from vault.decrypted_secrets where name = 'service_role_key';
  for r in
    select d.user_id, coalesce(nullif(trim(d.name), ''), 'Motorista') nome, e->>'doc' doc, e->>'rotulo' rotulo,
           (e->>'validade')::date validade, e->>'estado' estado, (e->>'dias')::int dias
      from public.drivers d
      cross join lateral jsonb_array_elements(public._motorista_docs_estado(d.user_id)) e
     where d.vehicle_type = 'carro_passageiros' and d.deleted_at is null
       and d.approval_status = 'approved' and not coalesce(d.is_banned, false)
       and e->>'estado' in ('a_expirar','expirado')
  loop
    insert into public.motorista_docs_alertas (user_id, doc, validade, estado)
    values (r.user_id, r.doc, r.validade, r.estado) on conflict do nothing;
    if not found then continue; end if;
    n := n + 1;
    v_titulo := case when r.estado = 'expirado' then r.rotulo || ' expirado'
                     else r.rotulo || ' expira em ' || r.dias || ' dias' end;
    v_corpo := case when r.estado = 'expirado'
      then 'Não podes ficar online até atualizares a validade na tua Ficha legal.'
      else 'Válido até ' || to_char(r.validade, 'DD/MM/YYYY') || '. Renova a tempo e atualiza a Ficha legal na app.' end;
    perform public._push_in_app_notification(r.user_id, 'motorista_documento', v_titulo, v_corpo, r.doc);
    if v_url is not null and v_key is not null then
      begin
        perform net.http_post(url := v_url || '/functions/v1/notify-admin-message',
          headers := jsonb_build_object('Authorization', 'Bearer ' || v_key, 'Content-Type', 'application/json'),
          body := jsonb_build_object('targetUserId', r.user_id::text, 'title', v_titulo, 'body', v_corpo,
                                     'kind', 'admin_message_driver', 'relatedId', ''));
      exception when others then
        insert into public.e2e_log (fluxo, passo, estado, detalhe, device)
        values ('motorista-docs-alerta', 'push', 'falhou', r.user_id || ' ' || sqlerrm, 'pg_cron');
      end;
    end if;
    v_resumo := v_resumo || r.nome || ': ' || v_titulo || E'\n';
  end loop;
  if n > 0 then
    perform public.notify_admin_event('motorista_documentos', 'warning',
      n || ' aviso(s) de documento de motorista' || E'\n' || v_resumo,
      'driver', null, jsonb_build_object('avisos', n), '/admin/motoristas-documentos');
  end if;
  return jsonb_build_object('ok', true, 'avisos', n);
end $$;
revoke all on function public.motorista_docs_alerta_diario() from public;

do $$ begin
  perform cron.unschedule('motorista-docs-alerta-diario') where exists
    (select 1 from cron.job where jobname = 'motorista-docs-alerta-diario');
  perform cron.schedule('motorista-docs-alerta-diario', '0 8 * * *',
    'select public.motorista_docs_alerta_diario()');
end $$;

-- ── 5. Painel admin: semáforo por motorista ─────────────────────────────────
create or replace function public.admin_motoristas_documentos()
returns jsonb language plpgsql stable security definer set search_path to 'public' as $$
begin
  if not public.is_admin() then raise exception 'forbidden'; end if;
  return coalesce((select jsonb_agg(x order by x->>'pior' desc, x->>'nome') from (
    select jsonb_build_object(
      'user_id', d.user_id, 'nome', coalesce(nullif(trim(d.legal_name), ''), d.name),
      'telefone', d.phone, 'email', d.email, 'aprovacao', d.approval_status, 'online', d.is_online,
      'matricula', d.license_plate, 'marca_modelo', d.vehicle_make_model, 'cor', d.vehicle_color,
      'ficha', to_jsonb(f), 'documentos', docs,
      'pior', case
        when docs @> '[{"estado":"expirado"}]' then '3_expirado'
        when docs @> '[{"estado":"a_expirar"}]' then '2_a_expirar'
        when docs @> '[{"estado":"em_falta"}]' then '1_em_falta'
        else '0_valido' end) x
      from public.drivers d
      left join public.motorista_ficha_legal f on f.user_id = d.user_id
      cross join lateral (select public._motorista_docs_estado(d.user_id) docs) s
     where d.vehicle_type = 'carro_passageiros' and d.deleted_at is null) q), '[]'::jsonb);
end $$;
revoke all on function public.admin_motoristas_documentos() from public;
grant execute on function public.admin_motoristas_documentos() to authenticated;

-- ── 4. Recibo da viagem ao passageiro ───────────────────────────────────────
create table if not exists public.tvde_recibos_email (
  ride_id uuid primary key references public.tvde_rides(id) on delete cascade,
  email text,
  enviado_em timestamptz not null default now(),
  ok boolean not null,
  detalhe text
);
alter table public.tvde_recibos_email enable row level security;
drop policy if exists tre_admin on public.tvde_recibos_email;
create policy tre_admin on public.tvde_recibos_email for select to authenticated using (public.is_admin());

-- Só LÊ o que a corrida gravou. Linhas discriminadas apenas quando batem
-- certo ao cêntimo (motorista + Bora = valor da viagem); senão devolve o
-- total com a razão — nunca inventa uma divisão.
create or replace function public._tvde_recibo(p_ride uuid)
returns jsonb language plpgsql stable security definer set search_path to 'public' as $$
declare r public.tvde_rides; v_total int; v_desc int; v_inicio timestamptz; v_fim timestamptz;
  v_mot text; v_bate boolean;
begin
  select * into r from public.tvde_rides where id = p_ride;
  if not found or r.status <> 'finalizada' then return null; end if;
  v_total := coalesce(nullif(r.final_fare_cents, 0), r.est_fare_cents, 0);
  v_desc := coalesce(r.tokens_applied_value_cents, 0) + coalesce(r.promo_credit_applied_cents, 0);
  v_bate := v_total > 0 and r.bora_cut_cents is not null and r.driver_earn_cents is not null
            and r.bora_cut_cents + r.driver_earn_cents = v_total;
  select min(at) filter (where status = 'em_andamento'), max(at) filter (where status = 'finalizada')
    into v_inicio, v_fim from public.tvde_ride_events where ride_id = r.id;
  select coalesce(nullif(trim(d.legal_name), ''), d.name) || coalesce(' · ' || d.license_plate, '')
    into v_mot from public.drivers d where d.user_id = r.driver_id limit 1;
  return jsonb_build_object(
    'ride_id', r.id, 'numero', upper(left(replace(r.id::text, '-', ''), 8)),
    'data', coalesce(v_fim, r.updated_at), 'inicio', coalesce(v_inicio, r.created_at),
    'origem', r.origin_label, 'destino', r.dest_label,
    'distancia_km', coalesce(r.final_distance_km, r.est_distance_km),
    'motorista', v_mot,
    'plataforma', coalesce(public.get_setting('plataforma_nome') #>> '{}', 'Bora'),
    'plataforma_nif', nullif(public.get_setting('plataforma_nif') #>> '{}', ''),
    'pagamento', r.payment_method,
    'valor_viagem_cents', v_total,
    'discriminado', v_bate,
    'transporte_cents', case when v_bate then r.driver_earn_cents end,
    'taxa_intermediacao_cents', case when v_bate then r.bora_cut_cents end,
    'paragens_cents', nullif(r.extra_stops_fee_cents, 0),
    'descontos_cents', nullif(v_desc, 0),
    'total_pago_cents', greatest(v_total - v_desc, 0),
    'razao', case
      when v_total = 0 then 'Viagem incluída num pacote ou assinatura já pago.'
      when not v_bate then 'Viagem com ajuste de pacote ida-e-volta: a divisão entre motorista e Bora está no teu extrato de pacote.'
      end,
    'aviso_legal', 'Recibo de viagem. Não substitui fatura: a fatura é emitida por software certificado.');
end $$;
revoke all on function public._tvde_recibo(uuid) from public;

create or replace function public.tvde_recibo_viagem(p_ride uuid)
returns jsonb language plpgsql stable security definer set search_path to 'public' as $$
begin
  if not exists (select 1 from public.tvde_rides where id = p_ride
                   and (client_id = auth.uid() or driver_id = auth.uid() or public.is_admin())) then
    raise exception 'forbidden';
  end if;
  return public._tvde_recibo(p_ride);
end $$;
revoke all on function public.tvde_recibo_viagem(uuid) from public;
grant execute on function public.tvde_recibo_viagem(uuid) to authenticated;

create or replace function public.fn_tvde_recibo_email_ao_finalizar()
returns trigger language plpgsql security definer set search_path to 'public', 'net', 'vault' as $$
declare v_url text; v_key text;
begin
  if new.status = 'finalizada' and old.status is distinct from 'finalizada'
     and coalesce((public.get_setting('tvde_recibo_email_auto') #>> '{}')::boolean, true) then
    begin
      select decrypted_secret into v_url from vault.decrypted_secrets where name = 'project_url';
      select decrypted_secret into v_key from vault.decrypted_secrets where name = 'service_role_key';
      if v_url is not null and v_key is not null then
        perform net.http_post(url := v_url || '/functions/v1/tvde-recibo-viagem',
          headers := jsonb_build_object('Authorization', 'Bearer ' || v_key, 'Content-Type', 'application/json'),
          body := jsonb_build_object('rideId', new.id::text));
      end if;
    exception when others then
      insert into public.e2e_log (fluxo, passo, estado, detalhe, device)
      values ('tvde-recibo-email', 'trigger', 'falhou', new.id || ' ' || sqlerrm, 'db');
    end;
  end if;
  return new;
end $$;
drop trigger if exists trg_tvde_recibo_email on public.tvde_rides;
create trigger trg_tvde_recibo_email after update of status on public.tvde_rides
  for each row execute function public.fn_tvde_recibo_email_ao_finalizar();
