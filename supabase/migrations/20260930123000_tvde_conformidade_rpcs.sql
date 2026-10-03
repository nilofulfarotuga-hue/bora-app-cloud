-- tvde-conformidade-lei-59-2026 · FASES 3–6 (funções que a app chama) — 2026-09-30
-- Só leitura e registos novos. Nenhuma destas funções muda preço, comissão ou
-- ganho: o "preço discriminado" LÊ as mesmas chaves que a corrida usa.

-- ════════════════════════════ CLIENTE ═══════════════════════════════════════

-- Configuração que a app precisa (uma chamada só).
create or replace function public.tvde_conformidade_config()
returns jsonb language sql stable security definer set search_path to 'public' as $$
  select jsonb_build_object(
    'mestre', coalesce((public.get_setting('tvde_compliance_enforce') #>> '{}')::boolean, false),
    'so_pagamento_eletronico', public.tvde_conf_ativa('tvde_electronic_payment_only'),
    'avaliar_passageiro_desativado', public.tvde_conf_ativa('tvde_driver_rates_client_disabled'),
    'limite_horas_ativo', public.tvde_conf_ativa('tvde_work_limit_enforce'),
    'bloqueio_ativo', public.tvde_conf_ativa('tvde_compliance_block'),
    'opcoes_cliente', coalesce((public.get_setting('tvde_client_options_enabled') #>> '{}')::boolean, false),
    'iva_discriminar', coalesce((public.get_setting('tvde_iva_discriminar') #>> '{}')::boolean, false),
    'limite_horas', coalesce((public.get_setting('tvde_work_limit_hours') #>> '{}')::numeric, 10),
    'livro_reclamacoes_url', coalesce(public.get_setting('livro_reclamacoes_url') #>> '{}', 'https://www.livroreclamacoes.pt/Inicio/'),
    'email_contacto', public.get_setting('plataforma_email_contacto') #>> '{}')
$$;
revoke all on function public.tvde_conformidade_config() from public;
grant execute on function public.tvde_conformidade_config() to anon, authenticated;

-- Página "Sobre o operador da plataforma" (art. 17.º n.º 8).
create or replace function public.tvde_operador_plataforma()
returns jsonb language sql stable security definer set search_path to 'public' as $$
  select jsonb_build_object(
    'marca', coalesce(nullif(public.get_setting('plataforma_marca') #>> '{}', ''), 'Bora'),
    'denominacao', nullif(public.get_setting('plataforma_denominacao') #>> '{}', ''),
    'nif', nullif(public.get_setting('plataforma_nif') #>> '{}', ''),
    'sede', nullif(public.get_setting('plataforma_sede') #>> '{}', ''),
    'licenca_imt', nullif(public.get_setting('plataforma_licenca_imt') #>> '{}', ''),
    'email', nullif(public.get_setting('plataforma_email_contacto') #>> '{}', ''),
    'em_constituicao', coalesce(public.get_setting('plataforma_nif') #>> '{}', '') = ''
                    or coalesce(public.get_setting('plataforma_denominacao') #>> '{}', '') = '')
$$;
revoke all on function public.tvde_operador_plataforma() from public;
grant execute on function public.tvde_operador_plataforma() to anon, authenticated;

-- Preço discriminado ANTES de pedir (art. 15.º). Lê as mesmas chaves que
-- tvde_calculate_fare / tvde_finish_ride. A parte do motorista é estimativa.
create or replace function public.tvde_fare_breakdown(p_distance_km numeric)
returns jsonb language plpgsql stable security definer set search_path to 'public' as $$
declare
  v_km numeric := greatest(coalesce(p_distance_km, 0), 0);
  v_base int := (public.get_setting('tvde_base_fare_cents') #>> '{}')::int;
  v_base_km int := (public.get_setting('tvde_base_distance_km') #>> '{}')::int;
  v_km_preco int := (public.get_setting('tvde_extra_per_km_cents') #>> '{}')::int;
  v_d_base int := (public.get_setting('tvde_driver_base_cents') #>> '{}')::int;
  v_d_km int := (public.get_setting('tvde_driver_per_km_cents') #>> '{}')::int;
  v_extra int := greatest(0, ceil(v_km - v_base_km))::int;
  v_fixo int := public.tvde_client_fixed_fare_cents(auth.uid(), v_km);
  v_total int; v_mot int; v_interm int;
  v_iva_disc boolean := coalesce((public.get_setting('tvde_iva_discriminar') #>> '{}')::boolean, false);
  v_iva_pct numeric := coalesce((public.get_setting('tvde_iva_transporte_pct') #>> '{}')::numeric, 6);
begin
  v_total := public.tvde_calculate_fare(v_km);
  if v_fixo is not null then
    v_mot := coalesce(public.tvde_client_fixed_driver_earn_cents(auth.uid(), v_km), v_d_base + v_extra * v_d_km);
  else
    v_mot := v_d_base + v_extra * v_d_km;
  end if;
  v_interm := greatest(v_total - v_mot, 0);
  return jsonb_build_object(
    'distancia_km', round(v_km, 1),
    'tarifa_base_cents', case when v_fixo is null then v_base end,
    'km_incluidos', case when v_fixo is null then v_base_km end,
    'km_extra', case when v_fixo is null then v_extra end,
    'preco_km_extra_cents', case when v_fixo is null then v_km_preco end,
    'preco_por_minuto_cents', 0,
    'fator_dinamico', 1.0,
    'tarifa_combinada', v_fixo is not null,
    'intermediacao_cents', v_interm,
    'intermediacao_pct', case when v_total > 0 then round(100.0 * v_interm / v_total, 1) end,
    'iva_pct', case when v_iva_disc then v_iva_pct end,
    'iva_cents', case when v_iva_disc then round(v_total - v_total / (1 + v_iva_pct / 100.0)) end,
    'total_cents', v_total,
    'preco_fixo', false,
    'nota', 'Estimativa. O preço final calcula-se com a mesma tabela sobre a distância real percorrida. O preço não depende do tempo nem de procura (sem tarifa dinâmica).');
end $$;
revoke all on function public.tvde_fare_breakdown(numeric) from public, anon;
grant execute on function public.tvde_fare_breakdown(numeric) to authenticated;

-- Preferências (fala português / mobilidade reduzida).
create or replace function public.tvde_prefs_obter()
returns jsonb language sql stable security definer set search_path to 'public' as $$
  select coalesce((select to_jsonb(p) from public.tvde_client_prefs p where p.client_id = auth.uid()),
                  jsonb_build_object('client_id', auth.uid(), 'fala_portugues', false, 'mobilidade_reduzida', false,
                                     'cao_guia', false, 'cadeira_rodas', false, 'carrinho_bebe', false))
$$;
revoke all on function public.tvde_prefs_obter() from public, anon;
grant execute on function public.tvde_prefs_obter() to authenticated;

create or replace function public.tvde_prefs_guardar(p jsonb)
returns jsonb language plpgsql security definer set search_path to 'public' as $$
begin
  if auth.uid() is null then raise exception 'sem_sessao'; end if;
  insert into public.tvde_client_prefs as c (client_id, fala_portugues, mobilidade_reduzida, cao_guia, cadeira_rodas, carrinho_bebe, updated_at)
  values (auth.uid(), coalesce((p->>'fala_portugues')::boolean, false), coalesce((p->>'mobilidade_reduzida')::boolean, false),
          coalesce((p->>'cao_guia')::boolean, false), coalesce((p->>'cadeira_rodas')::boolean, false),
          coalesce((p->>'carrinho_bebe')::boolean, false), now())
  on conflict (client_id) do update set
    fala_portugues = coalesce((p->>'fala_portugues')::boolean, c.fala_portugues),
    mobilidade_reduzida = coalesce((p->>'mobilidade_reduzida')::boolean, c.mobilidade_reduzida),
    cao_guia = coalesce((p->>'cao_guia')::boolean, c.cao_guia),
    cadeira_rodas = coalesce((p->>'cadeira_rodas')::boolean, c.cadeira_rodas),
    carrinho_bebe = coalesce((p->>'carrinho_bebe')::boolean, c.carrinho_bebe),
    updated_at = now();
  return public.tvde_prefs_obter();
end $$;
revoke all on function public.tvde_prefs_guardar(jsonb) from public, anon;
grant execute on function public.tvde_prefs_guardar(jsonb) to authenticated;

-- Carros adaptados disponíveis agora (art. 6).
create or replace function public.tvde_mobilidade_disponivel()
returns jsonb language sql stable security definer set search_path to 'public' as $$
  select jsonb_build_object(
    'adaptados_online', (select count(distinct dv.driver_user_id)
       from public.tvde_driver_vehicle dv
       join public.tvde_vehicles v on v.id = dv.vehicle_id and v.adaptado_mobilidade_reduzida and v.estado = 'aprovado'
       join public.drivers d on d.user_id = dv.driver_user_id
      where dv.ativo and d.is_online and d.approval_status = 'approved'
        and d.last_heartbeat_at > now() - interval '10 minutes'),
    'espera_min', coalesce((public.get_setting('tvde_mobilidade_espera_min') #>> '{}')::int, 15))
$$;
revoke all on function public.tvde_mobilidade_disponivel() from public, anon;
grant execute on function public.tvde_mobilidade_disponivel() to authenticated;

-- Queixas (art. 19.º n.º 3).
create or replace function public.tvde_queixa_criar(p_ride uuid, p_categoria text, p_descricao text, p_contacto text default null)
returns jsonb language plpgsql security definer set search_path to 'public' as $$
declare v_uid uuid := auth.uid(); r public.tvde_rides; q public.tvde_complaints; v_papel text := 'cliente';
begin
  if v_uid is null then raise exception 'sem_sessao'; end if;
  if p_descricao is null or length(trim(p_descricao)) < 5 then
    raise exception 'descricao_curta' using hint = 'Descreve o que aconteceu (mínimo 5 caracteres).';
  end if;
  if p_ride is not null then
    select * into r from public.tvde_rides where id = p_ride;
    if not found or (r.client_id is distinct from v_uid and r.driver_id is distinct from v_uid) then
      raise exception 'viagem_invalida';
    end if;
    if r.driver_id = v_uid then v_papel := 'motorista'; end if;
  end if;
  insert into public.tvde_complaints (ride_id, autor_user_id, autor_papel, driver_user_id, categoria, descricao, contacto)
  values (p_ride, v_uid, v_papel, case when v_papel = 'cliente' then r.driver_id end,
          coalesce(nullif(p_categoria, ''), 'outro'), trim(p_descricao), nullif(trim(coalesce(p_contacto, '')), ''))
  returning * into q;
  insert into public.tvde_compliance_events (tipo, ride_id, driver_user_id, ator_user_id, ator, motivo, meta)
  values ('queixa_recebida', p_ride, q.driver_user_id, v_uid, v_papel, q.categoria, jsonb_build_object('numero', q.numero));
  begin
    perform public.notify_admin_event('tvde_queixa', 'warning',
      'Nova queixa TVDE n.º ' || q.numero || ' (' || q.categoria || ')', 'tvde_complaint', q.id::text,
      jsonb_build_object('numero', q.numero), '/admin/tvde-conformidade');
  exception when others then null;
  end;
  return jsonb_build_object('ok', true, 'numero', q.numero, 'id', q.id, 'estado', q.estado);
end $$;
revoke all on function public.tvde_queixa_criar(uuid, text, text, text) from public, anon;
grant execute on function public.tvde_queixa_criar(uuid, text, text, text) to authenticated;

create or replace function public.tvde_minhas_queixas()
returns jsonb language sql stable security definer set search_path to 'public' as $$
  select coalesce(jsonb_agg(jsonb_build_object('numero', q.numero, 'categoria', q.categoria, 'estado', q.estado,
           'descricao', q.descricao, 'resposta', q.resposta, 'created_at', q.created_at, 'ride_id', q.ride_id)
           order by q.created_at desc), '[]'::jsonb)
    from public.tvde_complaints q where q.autor_user_id = auth.uid()
$$;
revoke all on function public.tvde_minhas_queixas() from public, anon;
grant execute on function public.tvde_minhas_queixas() to authenticated;

-- SOS (arts. 17.º-A n.º 2 e) e 19.º n.º 1 j)): regista e avisa o admin.
-- A chamada ao 112 e a partilha de localização fazem-se no telemóvel.
create or replace function public.tvde_sos_registar(p_ride uuid, p_lat double precision, p_lng double precision,
                                                    p_ligou_112 boolean default false, p_partilhou boolean default false)
returns jsonb language plpgsql security definer set search_path to 'public' as $$
declare v_uid uuid := auth.uid(); r public.tvde_rides; v_papel text; v_id bigint;
begin
  if v_uid is null then raise exception 'sem_sessao'; end if;
  select * into r from public.tvde_rides where id = p_ride;
  if not found then raise exception 'viagem_invalida'; end if;
  v_papel := case when r.client_id = v_uid then 'cliente' when r.driver_id = v_uid then 'motorista' end;
  if v_papel is null then raise exception 'viagem_invalida'; end if;
  insert into public.tvde_sos_events (ride_id, user_id, papel, lat, lng, ligou_112, partilhou)
  values (p_ride, v_uid, v_papel, p_lat, p_lng, coalesce(p_ligou_112, false), coalesce(p_partilhou, false))
  returning id into v_id;
  insert into public.tvde_compliance_events (tipo, ride_id, driver_user_id, ator_user_id, ator, motivo, meta)
  values ('sos', p_ride, r.driver_id, v_uid, v_papel, 'Botão de emergência',
          jsonb_build_object('lat', p_lat, 'lng', p_lng, 'ligou_112', p_ligou_112));
  begin
    perform public.notify_admin_event('tvde_sos', 'critical',
      'SOS TVDE (' || v_papel || ') na viagem ' || upper(left(replace(p_ride::text, '-', ''), 8))
        || coalesce(' · https://maps.google.com/?q=' || p_lat || ',' || p_lng, ''),
      'tvde_ride', p_ride::text, jsonb_build_object('lat', p_lat, 'lng', p_lng, 'papel', v_papel), '/admin/tvde-conformidade');
  exception when others then null;
  end;
  return jsonb_build_object('ok', true, 'id', v_id);
end $$;
revoke all on function public.tvde_sos_registar(uuid, double precision, double precision, boolean, boolean) from public, anon;
grant execute on function public.tvde_sos_registar(uuid, double precision, double precision, boolean, boolean) to authenticated;

-- ════════════════════════════ MOTORISTA ═════════════════════════════════════

create or replace function public.tvde_operadores_aprovados()
returns jsonb language sql stable security definer set search_path to 'public' as $$
  select coalesce(jsonb_agg(jsonb_build_object('id', o.id, 'denominacao', o.denominacao, 'nipc', o.nipc,
           'licenca_imt_numero', o.licenca_imt_numero) order by o.denominacao), '[]'::jsonb)
    from public.tvde_operators o where o.estado = 'aprovado'
$$;
revoke all on function public.tvde_operadores_aprovados() from public, anon;
grant execute on function public.tvde_operadores_aprovados() to authenticated;

create or replace function public.tvde_minha_conformidade()
returns jsonb language plpgsql security definer set search_path to 'public' as $$
declare v_uid uuid := auth.uid(); d public.drivers; v_calc jsonb; o public.tvde_operators; v jsonb;
begin
  if v_uid is null then raise exception 'sem_sessao'; end if;
  select * into d from public.drivers where user_id = v_uid and deleted_at is null limit 1;
  if not found then raise exception 'nao_e_motorista'; end if;
  v_calc := public.tvde_driver_conformidade_refresh(v_uid, 'motorista');
  select * into o from public.tvde_operators where id = d.tvde_operator_id;
  select to_jsonb(x) - 'seguro_apolice' into v from (
    select vv.* from public.tvde_driver_vehicle dv join public.tvde_vehicles vv on vv.id = dv.vehicle_id
     where dv.driver_user_id = v_uid and dv.ativo order by dv.desde desc limit 1) x;
  return v_calc || jsonb_build_object(
    'bloqueio_efetivo', public.tvde_conf_ativa('tvde_compliance_block'),
    'limite_efetivo', public.tvde_conf_ativa('tvde_work_limit_enforce'),
    'horas_bora_24h', public.tvde_driver_horas_24h(v_uid),
    'horas_total_24h', public.tvde_driver_horas_total(v_uid),
    'limite_horas', coalesce((public.get_setting('tvde_work_limit_hours') #>> '{}')::numeric, 10),
    'horas_outras_plataformas', case when d.tvde_horas_outras_declaradas_em > now() - interval '24 hours'
                                     then d.tvde_horas_outras_plataformas else 0 end,
    'operador', case when o.id is null then null else jsonb_build_object('id', o.id, 'denominacao', o.denominacao,
                    'estado', o.estado, 'licenca_imt_validade', o.licenca_imt_validade) end,
    'veiculo', v,
    'carta_b_emitida_em', d.carta_b_emitida_em,
    'fala_portugues', d.fala_portugues,
    'curso_atualizacao_em', d.tvde_curso_atualizacao_em,
    'tem_contrato', d.tvde_contrato_operador_path is not null,
    'tem_foto_cmtvde', d.tvde_cert_foto_path is not null);
end $$;
revoke all on function public.tvde_minha_conformidade() from public, anon;
grant execute on function public.tvde_minha_conformidade() to authenticated;

-- Guarda os dados do motorista (só os campos de conformidade).
create or replace function public.tvde_motorista_guardar_conformidade(p jsonb)
returns jsonb language plpgsql security definer set search_path to 'public' as $$
declare v_uid uuid := auth.uid();
begin
  if v_uid is null then raise exception 'sem_sessao'; end if;
  if not exists (select 1 from public.drivers where user_id = v_uid and deleted_at is null) then
    raise exception 'nao_e_motorista';
  end if;
  if p ? 'operador_id' and nullif(p->>'operador_id', '') is not null and not exists (
       select 1 from public.tvde_operators where id = (p->>'operador_id')::uuid and estado = 'aprovado') then
    raise exception 'operador_invalido' using hint = 'Escolhe um operador da lista.';
  end if;
  if p ? 'horas_outras_plataformas' and ((p->>'horas_outras_plataformas')::numeric < 0
     or (p->>'horas_outras_plataformas')::numeric > 24) then
    raise exception 'horas_invalidas';
  end if;
  update public.drivers d set
    tvde_operator_id = case when p ? 'operador_id' then nullif(p->>'operador_id', '')::uuid else d.tvde_operator_id end,
    carta_b_emitida_em = case when p ? 'carta_b_emitida_em' then nullif(p->>'carta_b_emitida_em', '')::date else d.carta_b_emitida_em end,
    fala_portugues = case when p ? 'fala_portugues' then (p->>'fala_portugues')::boolean else d.fala_portugues end,
    tvde_curso_atualizacao_em = case when p ? 'curso_atualizacao_em' then nullif(p->>'curso_atualizacao_em', '')::date else d.tvde_curso_atualizacao_em end,
    tvde_cert_foto_path = case when p ? 'cert_foto_path' then nullif(p->>'cert_foto_path', '') else d.tvde_cert_foto_path end,
    tvde_contrato_operador_path = case when p ? 'contrato_path' then nullif(p->>'contrato_path', '') else d.tvde_contrato_operador_path end,
    tvde_horas_outras_plataformas = case when p ? 'horas_outras_plataformas' then (p->>'horas_outras_plataformas')::numeric else d.tvde_horas_outras_plataformas end,
    tvde_horas_outras_declaradas_em = case when p ? 'horas_outras_plataformas' then now() else d.tvde_horas_outras_declaradas_em end,
    updated_at = now()
  where d.user_id = v_uid;
  insert into public.tvde_compliance_events (tipo, driver_user_id, ator_user_id, ator, meta)
  values ('dados_motorista', v_uid, v_uid, 'motorista', p - 'cert_foto_path' - 'contrato_path');
  return public.tvde_minha_conformidade();
end $$;
revoke all on function public.tvde_motorista_guardar_conformidade(jsonb) from public, anon;
grant execute on function public.tvde_motorista_guardar_conformidade(jsonb) to authenticated;

-- O motorista submete o carro (fica pendente até o admin aprovar).
create or replace function public.tvde_motorista_submeter_veiculo(p jsonb)
returns jsonb language plpgsql security definer set search_path to 'public' as $$
declare v_uid uuid := auth.uid(); v_id uuid; v_mat text;
begin
  if v_uid is null then raise exception 'sem_sessao'; end if;
  v_mat := upper(regexp_replace(coalesce(p->>'matricula', ''), '[^A-Za-z0-9]', '', 'g'));
  if length(v_mat) < 6 then raise exception 'matricula_invalida'; end if;
  if (p->>'lugares') is not null and ((p->>'lugares')::int < 1 or (p->>'lugares')::int > 9) then
    raise exception 'lugares_invalidos' using hint = 'Um carro TVDE tem no máximo 9 lugares.';
  end if;
  select id into v_id from public.tvde_vehicles where upper(replace(matricula, '-', '')) = v_mat;
  if v_id is not null and not exists (select 1 from public.tvde_vehicles where id = v_id
       and (submetido_por = v_uid or exists (select 1 from public.tvde_driver_vehicle dv
             where dv.vehicle_id = v_id and dv.driver_user_id = v_uid))) then
    raise exception 'matricula_de_outro' using hint = 'Este carro já está registado. Fala com o teu operador.';
  end if;
  if v_id is null then
    insert into public.tvde_vehicles (matricula, submetido_por) values (v_mat, v_uid) returning id into v_id;
  end if;
  update public.tvde_vehicles v set
    operator_id = coalesce((select tvde_operator_id from public.drivers where user_id = v_uid limit 1), v.operator_id),
    marca = coalesce(nullif(trim(p->>'marca'), ''), v.marca),
    modelo = coalesce(nullif(trim(p->>'modelo'), ''), v.modelo),
    cor = coalesce(nullif(trim(p->>'cor'), ''), v.cor),
    ano_fabrico = coalesce(nullif(p->>'ano_fabrico', '')::int, v.ano_fabrico),
    primeira_matricula_em = coalesce(nullif(p->>'primeira_matricula_em', '')::date, v.primeira_matricula_em),
    lugares = coalesce(nullif(p->>'lugares', '')::int, v.lugares),
    eletrico = coalesce((p->>'eletrico')::boolean, v.eletrico),
    foto_path = coalesce(nullif(p->>'foto_path', ''), v.foto_path),
    registo_imt_numero = coalesce(nullif(trim(p->>'registo_imt_numero'), ''), v.registo_imt_numero),
    registo_imt_validade = coalesce(nullif(p->>'registo_imt_validade', '')::date, v.registo_imt_validade),
    seguro_seguradora = coalesce(nullif(trim(p->>'seguro_seguradora'), ''), v.seguro_seguradora),
    seguro_apolice = coalesce(nullif(trim(p->>'seguro_apolice'), ''), v.seguro_apolice),
    seguro_validade = coalesce(nullif(p->>'seguro_validade', '')::date, v.seguro_validade),
    seguro_acidentes_pessoais = coalesce((p->>'seguro_acidentes_pessoais')::boolean, v.seguro_acidentes_pessoais),
    seguro_path = coalesce(nullif(p->>'seguro_path', ''), v.seguro_path),
    inspecao_proxima = coalesce(nullif(p->>'inspecao_proxima', '')::date, v.inspecao_proxima),
    distico_id = coalesce(nullif(trim(p->>'distico_id'), ''), v.distico_id),
    adaptado_mobilidade_reduzida = coalesce((p->>'adaptado_mobilidade_reduzida')::boolean, v.adaptado_mobilidade_reduzida),
    -- qualquer alteração feita pelo motorista volta a precisar de aprovação
    estado = case when v.estado = 'aprovado' then 'pendente' else v.estado end,
    updated_at = now()
  where v.id = v_id;
  insert into public.tvde_driver_vehicle (driver_user_id, vehicle_id, criado_por)
  values (v_uid, v_id, v_uid) on conflict (driver_user_id, vehicle_id) do update set ativo = true, ate = null;
  insert into public.tvde_compliance_events (tipo, driver_user_id, vehicle_id, ator_user_id, ator, motivo)
  values ('veiculo_submetido', v_uid, v_id, v_uid, 'motorista', v_mat);
  return public.tvde_minha_conformidade();
end $$;
revoke all on function public.tvde_motorista_submeter_veiculo(jsonb) from public, anon;
grant execute on function public.tvde_motorista_submeter_veiculo(jsonb) to authenticated;

create or replace function public.tvde_motorista_registar_documento(p_doc_type text, p_file_path text, p_validade date default null)
returns jsonb language plpgsql security definer set search_path to 'public' as $$
declare v_uid uuid := auth.uid(); v_driver uuid; v_id uuid;
begin
  if v_uid is null then raise exception 'sem_sessao'; end if;
  select id into v_driver from public.drivers where user_id = v_uid and deleted_at is null limit 1;
  if v_driver is null then raise exception 'nao_e_motorista'; end if;
  if p_file_path is null or split_part(p_file_path, '/', 1) <> v_uid::text then
    raise exception 'ficheiro_invalido';
  end if;
  insert into public.tvde_driver_documents (driver_id, doc_type, file_path, status, validade)
  values (v_driver, p_doc_type, p_file_path, 'pending', p_validade) returning id into v_id;
  insert into public.tvde_compliance_events (tipo, driver_user_id, ator_user_id, ator, motivo)
  values ('documento_enviado', v_uid, v_uid, 'motorista', p_doc_type);
  return jsonb_build_object('ok', true, 'id', v_id);
end $$;
revoke all on function public.tvde_motorista_registar_documento(text, text, date) from public, anon;
grant execute on function public.tvde_motorista_registar_documento(text, text, date) to authenticated;

-- Pré-verificação antes de ficar online (o travão verdadeiro é o gatilho).
create or replace function public.tvde_driver_pode_ficar_online()
returns jsonb language plpgsql security definer set search_path to 'public' as $$
declare v_uid uuid := auth.uid(); v_mot jsonb := '[]'::jsonb; v_h numeric; v_lim numeric;
begin
  if v_uid is null then raise exception 'sem_sessao'; end if;
  v_h := public.tvde_driver_horas_total(v_uid);
  v_lim := coalesce((public.get_setting('tvde_work_limit_hours') #>> '{}')::numeric, 10);
  if public.tvde_conf_ativa('tvde_compliance_block') then
    v_mot := public._tvde_conformidade_calc(v_uid)->'motivos';
  end if;
  if public.tvde_conf_ativa('tvde_work_limit_enforce') and v_h >= v_lim then
    v_mot := v_mot || jsonb_build_object('codigo', 'limite_horas',
      'rotulo', 'Atingiste o limite legal de ' || v_lim || ' horas');
  end if;
  return jsonb_build_object('ok', jsonb_array_length(v_mot) = 0, 'motivos', v_mot,
                            'horas_total_24h', v_h, 'limite_horas', v_lim);
end $$;
revoke all on function public.tvde_driver_pode_ficar_online() from public, anon;
grant execute on function public.tvde_driver_pode_ficar_online() to authenticated;

-- ════════════════════════════ ADMIN (PT-BR) ═════════════════════════════════

create or replace function public._tvde_admin_ou_erro()
returns void language plpgsql stable security definer set search_path to 'public' as $$
begin
  if not public.is_admin() then raise exception 'forbidden'; end if;
end $$;
revoke all on function public._tvde_admin_ou_erro() from public, anon;
grant execute on function public._tvde_admin_ou_erro() to authenticated;

create or replace function public.admin_tvde_conf_resumo()
returns jsonb language plpgsql stable security definer set search_path to 'public' as $$
begin
  perform public._tvde_admin_ou_erro();
  return jsonb_build_object(
    'interruptores', (select coalesce(jsonb_agg(jsonb_build_object('key', s.key, 'value', s.value,
                        'description', s.description, 'category', s.category) order by s.category desc, s.key), '[]'::jsonb)
                        from public.platform_settings s
                       where s.category = 'tvde_conformidade'
                          or s.key in ('plataforma_nome','plataforma_nif','plataforma_licenca_imt','plataforma_denominacao',
                                       'plataforma_sede','plataforma_marca','plataforma_email_contacto','livro_reclamacoes_url')),
    'operadores', (select count(*) from public.tvde_operators),
    'operadores_aprovados', (select count(*) from public.tvde_operators where estado = 'aprovado'),
    'veiculos', (select count(*) from public.tvde_vehicles),
    'veiculos_pendentes', (select count(*) from public.tvde_vehicles where estado = 'pendente'),
    'motoristas', (select count(*) from public.drivers where vehicle_type = 'carro_passageiros' and deleted_at is null and approval_status = 'approved'),
    'motoristas_com_impedimentos', (select count(*) from public.tvde_driver_compliance where bloqueado),
    'queixas_abertas', (select count(*) from public.tvde_complaints where estado in ('recebida','em_analise')),
    'sos_7d', (select count(*) from public.tvde_sos_events where at > now() - interval '7 days'),
    'acima_teto', (select count(*) from public.tvde_intermediacao_verificacao where not cumpre),
    'requisitos', (select jsonb_object_agg(estado, n) from (select estado, count(*) n from public.tvde_legal_requirements group by 1) q));
end $$;
revoke all on function public.admin_tvde_conf_resumo() from public, anon;
grant execute on function public.admin_tvde_conf_resumo() to authenticated;

create or replace function public.admin_tvde_conf_set(p_key text, p_value jsonb)
returns jsonb language plpgsql security definer set search_path to 'public' as $$
declare v_old jsonb;
begin
  perform public._tvde_admin_ou_erro();
  if not exists (select 1 from public.platform_settings where key = p_key and (category = 'tvde_conformidade'
        or key in ('plataforma_nome','plataforma_nif','plataforma_licenca_imt','plataforma_denominacao',
                   'plataforma_sede','plataforma_marca','plataforma_email_contacto','livro_reclamacoes_url'))) then
    raise exception 'chave_nao_permitida' using hint = 'Só as chaves da conformidade TVDE mudam aqui.';
  end if;
  if p_key = 'plataforma_nif' and coalesce(p_value #>> '{}', '') <> '' and (p_value #>> '{}') !~ '^[0-9]{9}$' then
    raise exception 'nif_invalido';
  end if;
  select value into v_old from public.platform_settings where key = p_key;
  update public.platform_settings set value = p_value, updated_at = now(), updated_by = auth.uid() where key = p_key;
  insert into public.tvde_compliance_events (tipo, ator_user_id, ator, motivo, meta)
  values ('interruptor', auth.uid(), 'admin', p_key, jsonb_build_object('antes', v_old, 'depois', p_value));
  perform public.log_admin_action('tvde_conformidade_setting', 'platform_setting', p_key,
                                  jsonb_build_object('antes', v_old, 'depois', p_value));
  return jsonb_build_object('ok', true, 'key', p_key, 'value', p_value);
end $$;
revoke all on function public.admin_tvde_conf_set(text, jsonb) from public, anon;
grant execute on function public.admin_tvde_conf_set(text, jsonb) to authenticated;

-- Operadores
create or replace function public.admin_tvde_operadores()
returns jsonb language plpgsql stable security definer set search_path to 'public' as $$
begin
  perform public._tvde_admin_ou_erro();
  return coalesce((select jsonb_agg(to_jsonb(o) || jsonb_build_object(
      'motoristas', (select count(*) from public.drivers d where d.tvde_operator_id = o.id),
      'veiculos', (select count(*) from public.tvde_vehicles v where v.operator_id = o.id)) order by o.denominacao)
    from public.tvde_operators o), '[]'::jsonb);
end $$;
revoke all on function public.admin_tvde_operadores() from public, anon;
grant execute on function public.admin_tvde_operadores() to authenticated;

create or replace function public.admin_tvde_operador_guardar(p jsonb)
returns jsonb language plpgsql security definer set search_path to 'public' as $$
declare v_id uuid := nullif(p->>'id', '')::uuid; o public.tvde_operators;
begin
  perform public._tvde_admin_ou_erro();
  if v_id is null then
    insert into public.tvde_operators (denominacao, nipc) values (trim(p->>'denominacao'), regexp_replace(coalesce(p->>'nipc',''), '\s', '', 'g'))
    returning id into v_id;
  end if;
  update public.tvde_operators x set
    denominacao = coalesce(nullif(trim(p->>'denominacao'), ''), x.denominacao),
    nipc = coalesce(nullif(regexp_replace(coalesce(p->>'nipc',''), '\s', '', 'g'), ''), x.nipc),
    licenca_imt_numero = case when p ? 'licenca_imt_numero' then nullif(trim(p->>'licenca_imt_numero'), '') else x.licenca_imt_numero end,
    licenca_imt_validade = case when p ? 'licenca_imt_validade' then nullif(p->>'licenca_imt_validade', '')::date else x.licenca_imt_validade end,
    email = case when p ? 'email' then nullif(trim(p->>'email'), '') else x.email end,
    telefone = case when p ? 'telefone' then nullif(trim(p->>'telefone'), '') else x.telefone end,
    sede = case when p ? 'sede' then nullif(trim(p->>'sede'), '') else x.sede end,
    contrato_path = case when p ? 'contrato_path' then nullif(p->>'contrato_path', '') else x.contrato_path end,
    contrato_assinado_em = case when p ? 'contrato_assinado_em' then nullif(p->>'contrato_assinado_em', '')::date else x.contrato_assinado_em end,
    notas = case when p ? 'notas' then nullif(p->>'notas', '') else x.notas end,
    updated_at = now()
  where x.id = v_id returning * into o;
  insert into public.tvde_compliance_events (tipo, operator_id, ator_user_id, ator, meta)
  values ('operador_guardado', v_id, auth.uid(), 'admin', p);
  perform public.log_admin_action('tvde_operador_guardar', 'tvde_operator', v_id::text, p);
  return to_jsonb(o);
end $$;
revoke all on function public.admin_tvde_operador_guardar(jsonb) from public, anon;
grant execute on function public.admin_tvde_operador_guardar(jsonb) to authenticated;

create or replace function public.admin_tvde_operador_estado(p_id uuid, p_estado text, p_motivo text default null)
returns jsonb language plpgsql security definer set search_path to 'public' as $$
begin
  perform public._tvde_admin_ou_erro();
  if p_estado not in ('pendente','aprovado','suspenso','rejeitado') then raise exception 'estado_invalido'; end if;
  if p_estado in ('suspenso','rejeitado') and coalesce(length(trim(p_motivo)), 0) < 3 then raise exception 'motivo_obrigatorio'; end if;
  update public.tvde_operators set estado = p_estado, estado_motivo = p_motivo, decidido_por = auth.uid(),
         decidido_em = now(), updated_at = now() where id = p_id;
  if not found then raise exception 'operador_nao_encontrado'; end if;
  insert into public.tvde_compliance_events (tipo, operator_id, ator_user_id, ator, motivo, meta)
  values ('operador_' || p_estado, p_id, auth.uid(), 'admin', p_motivo, '{}'::jsonb);
  perform public.log_admin_action('tvde_operador_estado', 'tvde_operator', p_id::text,
                                  jsonb_build_object('estado', p_estado, 'motivo', p_motivo));
  perform public.tvde_driver_conformidade_refresh(d.user_id, 'admin') from public.drivers d where d.tvde_operator_id = p_id;
  return jsonb_build_object('ok', true);
end $$;
revoke all on function public.admin_tvde_operador_estado(uuid, text, text) from public, anon;
grant execute on function public.admin_tvde_operador_estado(uuid, text, text) to authenticated;

-- Veículos
create or replace function public.admin_tvde_veiculos()
returns jsonb language plpgsql stable security definer set search_path to 'public' as $$
begin
  perform public._tvde_admin_ou_erro();
  return coalesce((select jsonb_agg(to_jsonb(v) || jsonb_build_object(
      'operador', (select o.denominacao from public.tvde_operators o where o.id = v.operator_id),
      'motoristas', (select coalesce(jsonb_agg(jsonb_build_object('user_id', d.user_id, 'nome', d.name, 'ativo', dv.ativo)), '[]'::jsonb)
                       from public.tvde_driver_vehicle dv join public.drivers d on d.user_id = dv.driver_user_id
                      where dv.vehicle_id = v.id)) order by v.estado, v.matricula)
    from public.tvde_vehicles v), '[]'::jsonb);
end $$;
revoke all on function public.admin_tvde_veiculos() from public, anon;
grant execute on function public.admin_tvde_veiculos() to authenticated;

create or replace function public.admin_tvde_veiculo_guardar(p jsonb)
returns jsonb language plpgsql security definer set search_path to 'public' as $$
declare v_id uuid := nullif(p->>'id', '')::uuid; v public.tvde_vehicles;
begin
  perform public._tvde_admin_ou_erro();
  if v_id is null then
    insert into public.tvde_vehicles (matricula, submetido_por)
    values (upper(regexp_replace(coalesce(p->>'matricula', ''), '[^A-Za-z0-9]', '', 'g')), auth.uid()) returning id into v_id;
  end if;
  update public.tvde_vehicles x set
    operator_id = case when p ? 'operator_id' then nullif(p->>'operator_id', '')::uuid else x.operator_id end,
    marca = case when p ? 'marca' then nullif(trim(p->>'marca'), '') else x.marca end,
    modelo = case when p ? 'modelo' then nullif(trim(p->>'modelo'), '') else x.modelo end,
    cor = case when p ? 'cor' then nullif(trim(p->>'cor'), '') else x.cor end,
    ano_fabrico = case when p ? 'ano_fabrico' then nullif(p->>'ano_fabrico', '')::int else x.ano_fabrico end,
    primeira_matricula_em = case when p ? 'primeira_matricula_em' then nullif(p->>'primeira_matricula_em', '')::date else x.primeira_matricula_em end,
    lugares = case when p ? 'lugares' then nullif(p->>'lugares', '')::int else x.lugares end,
    eletrico = case when p ? 'eletrico' then (p->>'eletrico')::boolean else x.eletrico end,
    foto_path = case when p ? 'foto_path' then nullif(p->>'foto_path', '') else x.foto_path end,
    registo_imt_numero = case when p ? 'registo_imt_numero' then nullif(trim(p->>'registo_imt_numero'), '') else x.registo_imt_numero end,
    registo_imt_validade = case when p ? 'registo_imt_validade' then nullif(p->>'registo_imt_validade', '')::date else x.registo_imt_validade end,
    seguro_seguradora = case when p ? 'seguro_seguradora' then nullif(trim(p->>'seguro_seguradora'), '') else x.seguro_seguradora end,
    seguro_apolice = case when p ? 'seguro_apolice' then nullif(trim(p->>'seguro_apolice'), '') else x.seguro_apolice end,
    seguro_validade = case when p ? 'seguro_validade' then nullif(p->>'seguro_validade', '')::date else x.seguro_validade end,
    seguro_acidentes_pessoais = case when p ? 'seguro_acidentes_pessoais' then (p->>'seguro_acidentes_pessoais')::boolean else x.seguro_acidentes_pessoais end,
    inspecao_proxima = case when p ? 'inspecao_proxima' then nullif(p->>'inspecao_proxima', '')::date else x.inspecao_proxima end,
    distico_id = case when p ? 'distico_id' then nullif(trim(p->>'distico_id'), '') else x.distico_id end,
    adaptado_mobilidade_reduzida = case when p ? 'adaptado_mobilidade_reduzida' then (p->>'adaptado_mobilidade_reduzida')::boolean else x.adaptado_mobilidade_reduzida end,
    updated_at = now()
  where x.id = v_id returning * into v;
  insert into public.tvde_compliance_events (tipo, vehicle_id, ator_user_id, ator, meta)
  values ('veiculo_guardado', v_id, auth.uid(), 'admin', p - 'seguro_apolice');
  perform public.log_admin_action('tvde_veiculo_guardar', 'tvde_vehicle', v_id::text, p - 'seguro_apolice');
  perform public.tvde_driver_conformidade_refresh(dv.driver_user_id, 'admin') from public.tvde_driver_vehicle dv where dv.vehicle_id = v_id;
  return to_jsonb(v);
end $$;
revoke all on function public.admin_tvde_veiculo_guardar(jsonb) from public, anon;
grant execute on function public.admin_tvde_veiculo_guardar(jsonb) to authenticated;

create or replace function public.admin_tvde_veiculo_estado(p_id uuid, p_estado text, p_motivo text default null)
returns jsonb language plpgsql security definer set search_path to 'public' as $$
begin
  perform public._tvde_admin_ou_erro();
  if p_estado not in ('pendente','aprovado','suspenso','rejeitado') then raise exception 'estado_invalido'; end if;
  if p_estado in ('suspenso','rejeitado') and coalesce(length(trim(p_motivo)), 0) < 3 then raise exception 'motivo_obrigatorio'; end if;
  update public.tvde_vehicles set estado = p_estado, estado_motivo = p_motivo, decidido_por = auth.uid(),
         decidido_em = now(), updated_at = now() where id = p_id;
  if not found then raise exception 'veiculo_nao_encontrado'; end if;
  insert into public.tvde_compliance_events (tipo, vehicle_id, ator_user_id, ator, motivo)
  values ('veiculo_' || p_estado, p_id, auth.uid(), 'admin', p_motivo);
  perform public.log_admin_action('tvde_veiculo_estado', 'tvde_vehicle', p_id::text,
                                  jsonb_build_object('estado', p_estado, 'motivo', p_motivo));
  perform public.tvde_driver_conformidade_refresh(dv.driver_user_id, 'admin') from public.tvde_driver_vehicle dv where dv.vehicle_id = p_id;
  return jsonb_build_object('ok', true);
end $$;
revoke all on function public.admin_tvde_veiculo_estado(uuid, text, text) from public, anon;
grant execute on function public.admin_tvde_veiculo_estado(uuid, text, text) to authenticated;

create or replace function public.admin_tvde_associar_veiculo(p_driver uuid, p_vehicle uuid, p_ativo boolean)
returns jsonb language plpgsql security definer set search_path to 'public' as $$
begin
  perform public._tvde_admin_ou_erro();
  insert into public.tvde_driver_vehicle (driver_user_id, vehicle_id, ativo, criado_por, ate)
  values (p_driver, p_vehicle, p_ativo, auth.uid(), case when p_ativo then null else now() end)
  on conflict (driver_user_id, vehicle_id) do update set ativo = excluded.ativo,
     ate = case when excluded.ativo then null else now() end;
  insert into public.tvde_compliance_events (tipo, driver_user_id, vehicle_id, ator_user_id, ator)
  values (case when p_ativo then 'veiculo_associado' else 'veiculo_desassociado' end, p_driver, p_vehicle, auth.uid(), 'admin');
  perform public.tvde_driver_conformidade_refresh(p_driver, 'admin');
  return jsonb_build_object('ok', true);
end $$;
revoke all on function public.admin_tvde_associar_veiculo(uuid, uuid, boolean) from public, anon;
grant execute on function public.admin_tvde_associar_veiculo(uuid, uuid, boolean) to authenticated;

-- Motoristas
create or replace function public.admin_tvde_motoristas_conformidade()
returns jsonb language plpgsql security definer set search_path to 'public' as $$
begin
  perform public._tvde_admin_ou_erro();
  perform public.tvde_driver_conformidade_refresh(d.user_id, 'admin')
     from public.drivers d where d.vehicle_type = 'carro_passageiros' and d.deleted_at is null and d.user_id is not null;
  return coalesce((select jsonb_agg(jsonb_build_object(
      'user_id', d.user_id, 'nome', coalesce(nullif(trim(d.legal_name), ''), d.name), 'telefone', d.phone,
      'aprovacao', d.approval_status, 'online', d.is_online,
      'operador', (select o.denominacao from public.tvde_operators o where o.id = d.tvde_operator_id),
      'operador_id', d.tvde_operator_id,
      'veiculo', (select v.matricula from public.tvde_driver_vehicle dv join public.tvde_vehicles v on v.id = dv.vehicle_id
                   where dv.driver_user_id = d.user_id and dv.ativo order by dv.desde desc limit 1),
      'carta_b_emitida_em', d.carta_b_emitida_em, 'fala_portugues', d.fala_portugues,
      'curso_atualizacao_em', d.tvde_curso_atualizacao_em,
      'bloqueado', c.bloqueado, 'motivos', c.motivos, 'avisos', c.avisos,
      'bloqueio_manual', c.bloqueio_manual, 'bloqueio_manual_motivo', c.bloqueio_manual_motivo,
      'horas_bora_24h', public.tvde_driver_horas_24h(d.user_id),
      'horas_total_24h', public.tvde_driver_horas_total(d.user_id),
      'verificado_em', c.verificado_em) order by c.bloqueado desc, d.name)
    from public.drivers d left join public.tvde_driver_compliance c on c.driver_user_id = d.user_id
   where d.vehicle_type = 'carro_passageiros' and d.deleted_at is null and d.user_id is not null), '[]'::jsonb);
end $$;
revoke all on function public.admin_tvde_motoristas_conformidade() from public, anon;
grant execute on function public.admin_tvde_motoristas_conformidade() to authenticated;

create or replace function public.admin_tvde_motorista_bloqueio(p_driver uuid, p_bloquear boolean, p_motivo text)
returns jsonb language plpgsql security definer set search_path to 'public' as $$
begin
  perform public._tvde_admin_ou_erro();
  if coalesce(length(trim(p_motivo)), 0) < 3 then raise exception 'motivo_obrigatorio'; end if;
  insert into public.tvde_driver_compliance as c (driver_user_id, bloqueio_manual, bloqueio_manual_motivo, bloqueio_manual_por, bloqueio_manual_em)
  values (p_driver, p_bloquear, p_motivo, auth.uid(), now())
  on conflict (driver_user_id) do update set bloqueio_manual = p_bloquear, bloqueio_manual_motivo = p_motivo,
     bloqueio_manual_por = auth.uid(), bloqueio_manual_em = now();
  insert into public.tvde_compliance_events (tipo, driver_user_id, ator_user_id, ator, motivo)
  values (case when p_bloquear then 'bloqueio_manual' else 'desbloqueio_manual' end, p_driver, auth.uid(), 'admin', p_motivo);
  perform public.log_admin_action('tvde_motorista_bloqueio', 'driver', p_driver::text,
                                  jsonb_build_object('bloquear', p_bloquear, 'motivo', p_motivo));
  return public.tvde_driver_conformidade_refresh(p_driver, 'admin');
end $$;
revoke all on function public.admin_tvde_motorista_bloqueio(uuid, boolean, text) from public, anon;
grant execute on function public.admin_tvde_motorista_bloqueio(uuid, boolean, text) to authenticated;

create or replace function public.admin_tvde_motorista_dados(p_driver uuid, p jsonb)
returns jsonb language plpgsql security definer set search_path to 'public' as $$
begin
  perform public._tvde_admin_ou_erro();
  update public.drivers d set
    tvde_operator_id = case when p ? 'operador_id' then nullif(p->>'operador_id', '')::uuid else d.tvde_operator_id end,
    carta_b_emitida_em = case when p ? 'carta_b_emitida_em' then nullif(p->>'carta_b_emitida_em', '')::date else d.carta_b_emitida_em end,
    fala_portugues = case when p ? 'fala_portugues' then (p->>'fala_portugues')::boolean else d.fala_portugues end,
    tvde_curso_atualizacao_em = case when p ? 'curso_atualizacao_em' then nullif(p->>'curso_atualizacao_em', '')::date else d.tvde_curso_atualizacao_em end,
    tvde_contrato_operador_path = case when p ? 'contrato_path' then nullif(p->>'contrato_path', '') else d.tvde_contrato_operador_path end,
    updated_at = now()
  where d.user_id = p_driver;
  if not found then raise exception 'motorista_nao_encontrado'; end if;
  insert into public.tvde_compliance_events (tipo, driver_user_id, ator_user_id, ator, meta)
  values ('dados_motorista', p_driver, auth.uid(), 'admin', p);
  perform public.log_admin_action('tvde_motorista_dados', 'driver', p_driver::text, p);
  return public.tvde_driver_conformidade_refresh(p_driver, 'admin');
end $$;
revoke all on function public.admin_tvde_motorista_dados(uuid, jsonb) from public, anon;
grant execute on function public.admin_tvde_motorista_dados(uuid, jsonb) to authenticated;

create or replace function public.admin_tvde_horas(p_driver uuid default null, p_dias int default 7)
returns jsonb language plpgsql stable security definer set search_path to 'public' as $$
begin
  perform public._tvde_admin_ou_erro();
  return coalesce((select jsonb_agg(jsonb_build_object('driver_user_id', l.driver_user_id,
      'nome', (select d.name from public.drivers d where d.user_id = l.driver_user_id limit 1),
      'inicio', l.inicio, 'fim', l.fim, 'fecho', l.fecho,
      'horas', round(extract(epoch from (coalesce(l.fim, now()) - l.inicio)) / 3600.0, 2)) order by l.inicio desc)
    from public.tvde_driver_work_log l
   where (p_driver is null or l.driver_user_id = p_driver)
     and l.inicio > now() - make_interval(days => greatest(p_dias, 1))), '[]'::jsonb);
end $$;
revoke all on function public.admin_tvde_horas(uuid, int) from public, anon;
grant execute on function public.admin_tvde_horas(uuid, int) to authenticated;

-- Documentos a caducar (motoristas, veículos, operadores)
create or replace function public.admin_tvde_a_caducar(p_dias int default 30)
returns jsonb language plpgsql stable security definer set search_path to 'public' as $$
declare v_hoje date := (now() at time zone 'Europe/Lisbon')::date;
begin
  perform public._tvde_admin_ou_erro();
  return coalesce((select jsonb_agg(x order by x->>'validade') from (
    select jsonb_build_object('tipo', 'motorista', 'quem', coalesce(nullif(trim(d.legal_name), ''), d.name),
             'documento', t.doc, 'validade', t.val, 'dias', t.val - v_hoje) x
      from public.drivers d join public.motorista_ficha_legal f on f.user_id = d.user_id
      cross join lateral (values ('CMTVDE', f.tvde_cert_validade), ('Carta de condução', f.carta_validade)) t(doc, val)
     where d.vehicle_type = 'carro_passageiros' and d.deleted_at is null and t.val is not null and t.val - v_hoje <= p_dias
    union all
    select jsonb_build_object('tipo', 'veiculo', 'quem', v.matricula, 'documento', t.doc, 'validade', t.val, 'dias', t.val - v_hoje)
      from public.tvde_vehicles v
      cross join lateral (values ('Registo IMT', v.registo_imt_validade), ('Seguro', v.seguro_validade),
                                 ('Inspeção', v.inspecao_proxima)) t(doc, val)
     where t.val is not null and t.val - v_hoje <= p_dias
    union all
    select jsonb_build_object('tipo', 'operador', 'quem', o.denominacao, 'documento', 'Licença IMT',
             'validade', o.licenca_imt_validade, 'dias', o.licenca_imt_validade - v_hoje)
      from public.tvde_operators o where o.licenca_imt_validade is not null and o.licenca_imt_validade - v_hoje <= p_dias
  ) q), '[]'::jsonb);
end $$;
revoke all on function public.admin_tvde_a_caducar(int) from public, anon;
grant execute on function public.admin_tvde_a_caducar(int) to authenticated;

-- Queixas
create or replace function public.admin_tvde_queixas(p_estado text default null)
returns jsonb language plpgsql stable security definer set search_path to 'public' as $$
begin
  perform public._tvde_admin_ou_erro();
  return coalesce((select jsonb_agg(to_jsonb(q) || jsonb_build_object(
      'motorista', (select d.name from public.drivers d where d.user_id = q.driver_user_id limit 1),
      'autor', (select u.name from public.users u where u.id = q.autor_user_id),
      'viagem', upper(left(replace(q.ride_id::text, '-', ''), 8)),
      'prazo_retencao', (q.created_at + make_interval(years => coalesce((public.get_setting('tvde_retencao_anos') #>> '{}')::int, 2)))::date)
      order by q.created_at desc)
    from public.tvde_complaints q where p_estado is null or q.estado = p_estado), '[]'::jsonb);
end $$;
revoke all on function public.admin_tvde_queixas(text) from public, anon;
grant execute on function public.admin_tvde_queixas(text) to authenticated;

create or replace function public.admin_tvde_queixa_atualizar(p_id uuid, p_estado text, p_diligencia text default null,
                                                             p_resposta text default null, p_resolucao text default null)
returns jsonb language plpgsql security definer set search_path to 'public' as $$
declare q public.tvde_complaints;
begin
  perform public._tvde_admin_ou_erro();
  if p_estado not in ('recebida','em_analise','respondida','resolvida','arquivada') then raise exception 'estado_invalido'; end if;
  update public.tvde_complaints x set
    estado = p_estado,
    diligencias = case when nullif(trim(coalesce(p_diligencia, '')), '') is null then x.diligencias
                       else x.diligencias || jsonb_build_array(jsonb_build_object('em', now(), 'por', auth.uid(), 'texto', trim(p_diligencia))) end,
    resposta = coalesce(nullif(trim(coalesce(p_resposta, '')), ''), x.resposta),
    resolucao = coalesce(nullif(trim(coalesce(p_resolucao, '')), ''), x.resolucao),
    respondida_em = case when p_estado = 'respondida' and x.respondida_em is null then now() else x.respondida_em end,
    resolvida_em = case when p_estado = 'resolvida' and x.resolvida_em is null then now() else x.resolvida_em end,
    updated_at = now()
  where x.id = p_id returning * into q;
  if q.id is null then raise exception 'queixa_nao_encontrada'; end if;
  insert into public.tvde_compliance_events (tipo, ride_id, driver_user_id, ator_user_id, ator, motivo, meta)
  values ('queixa_' || p_estado, q.ride_id, q.driver_user_id, auth.uid(), 'admin', p_diligencia, jsonb_build_object('numero', q.numero));
  if q.autor_user_id is not null and nullif(trim(coalesce(p_resposta, '')), '') is not null then
    begin
      perform public._push_in_app_notification(q.autor_user_id, 'tvde_queixa', 'Resposta à tua queixa n.º ' || q.numero,
                                              left(trim(p_resposta), 180), q.id::text);
    exception when others then null;
    end;
  end if;
  return to_jsonb(q);
end $$;
revoke all on function public.admin_tvde_queixa_atualizar(uuid, text, text, text, text) from public, anon;
grant execute on function public.admin_tvde_queixa_atualizar(uuid, text, text, text, text) to authenticated;

create or replace function public.admin_tvde_eventos(p_tipo text default null, p_limite int default 200)
returns jsonb language plpgsql stable security definer set search_path to 'public' as $$
begin
  perform public._tvde_admin_ou_erro();
  return coalesce((select jsonb_agg(to_jsonb(e) || jsonb_build_object(
      'motorista', (select d.name from public.drivers d where d.user_id = e.driver_user_id limit 1)) order by e.at desc)
    from (select * from public.tvde_compliance_events where p_tipo is null or tipo = p_tipo
           order by at desc limit least(greatest(p_limite, 1), 1000)) e), '[]'::jsonb);
end $$;
revoke all on function public.admin_tvde_eventos(text, int) from public, anon;
grant execute on function public.admin_tvde_eventos(text, int) to authenticated;

-- Teto 25% e AMT
create or replace function public.admin_tvde_intermediacao(p_limite int default 200)
returns jsonb language plpgsql stable security definer set search_path to 'public' as $$
begin
  perform public._tvde_admin_ou_erro();
  return jsonb_build_object(
    'resumo', (select jsonb_build_object('verificadas', count(*), 'acima_teto', count(*) filter (where not cumpre),
                 'pct_medio', round(avg(pct), 2), 'pct_max', max(pct)) from public.tvde_intermediacao_verificacao),
    'linhas', coalesce((select jsonb_agg(to_jsonb(iv) || jsonb_build_object('viagem', upper(left(replace(iv.ride_id::text, '-', ''), 8)))
                 order by iv.cumpre, iv.verificado_em desc)
               from (select * from public.tvde_intermediacao_verificacao order by cumpre, verificado_em desc
                      limit least(greatest(p_limite, 1), 1000)) iv), '[]'::jsonb));
end $$;
revoke all on function public.admin_tvde_intermediacao(int) from public, anon;
grant execute on function public.admin_tvde_intermediacao(int) to authenticated;

create or replace function public.admin_tvde_amt()
returns jsonb language plpgsql stable security definer set search_path to 'public' as $$
begin
  perform public._tvde_admin_ou_erro();
  return coalesce((select jsonb_agg(to_jsonb(a) order by a.mes desc) from public.tvde_amt_reports a), '[]'::jsonb);
end $$;
revoke all on function public.admin_tvde_amt() from public, anon;
grant execute on function public.admin_tvde_amt() to authenticated;

create or replace function public.admin_tvde_amt_gerar(p_mes date)
returns jsonb language plpgsql security definer set search_path to 'public' as $$
begin
  perform public._tvde_admin_ou_erro();
  return public.tvde_amt_relatorio_gerar(p_mes);
end $$;
revoke all on function public.admin_tvde_amt_gerar(date) from public, anon;
grant execute on function public.admin_tvde_amt_gerar(date) to authenticated;

-- Checklist "Pronto para licenciamento"
create or replace function public.admin_tvde_requisitos()
returns jsonb language plpgsql stable security definer set search_path to 'public' as $$
begin
  perform public._tvde_admin_ou_erro();
  return coalesce((select jsonb_agg(to_jsonb(r) order by r.ordem) from public.tvde_legal_requirements r), '[]'::jsonb);
end $$;
revoke all on function public.admin_tvde_requisitos() from public, anon;
grant execute on function public.admin_tvde_requisitos() to authenticated;

create or replace function public.admin_tvde_requisito_estado(p_codigo text, p_estado text, p_o_que_falta text default null)
returns jsonb language plpgsql security definer set search_path to 'public' as $$
begin
  perform public._tvde_admin_ou_erro();
  if p_estado not in ('verde','amarelo','vermelho') then raise exception 'estado_invalido'; end if;
  update public.tvde_legal_requirements set estado = p_estado,
         o_que_falta = coalesce(p_o_que_falta, o_que_falta), atualizado_em = now() where codigo = p_codigo;
  if not found then raise exception 'requisito_nao_encontrado'; end if;
  insert into public.tvde_compliance_events (tipo, ator_user_id, ator, motivo, meta)
  values ('requisito', auth.uid(), 'admin', p_codigo, jsonb_build_object('estado', p_estado));
  return jsonb_build_object('ok', true);
end $$;
revoke all on function public.admin_tvde_requisito_estado(text, text, text) from public, anon;
grant execute on function public.admin_tvde_requisito_estado(text, text, text) to authenticated;

-- ════════════════════════ FISCALIZAÇÃO (art. 20.º-A) ═══════════════════════
-- Dados estritamente necessários: sem nome, telefone ou email do passageiro.
create or replace function public._tvde_fiscal_dados(p_escopo jsonb)
returns jsonb language plpgsql stable security definer set search_path to 'public' as $$
declare
  v_de timestamptz := coalesce((p_escopo->>'desde')::date, (now() - interval '30 days')::date)::timestamptz;
  v_ate timestamptz := (coalesce((p_escopo->>'ate')::date, (now() at time zone 'Europe/Lisbon')::date) + 1)::timestamptz;
  v_drv uuid := nullif(p_escopo->>'driver_user_id', '')::uuid;
  v_veh uuid := nullif(p_escopo->>'vehicle_id', '')::uuid;
  v_op uuid := nullif(p_escopo->>'operator_id', '')::uuid;
  v_mot uuid[];
begin
  select array_agg(distinct d.user_id) into v_mot
    from public.drivers d
   where d.vehicle_type = 'carro_passageiros' and d.user_id is not null
     and (v_drv is null or d.user_id = v_drv)
     and (v_op is null or d.tvde_operator_id = v_op)
     and (v_veh is null or exists (select 1 from public.tvde_driver_vehicle dv
                                    where dv.driver_user_id = d.user_id and dv.vehicle_id = v_veh));
  v_mot := coalesce(v_mot, '{}'::uuid[]);
  return jsonb_build_object(
    'escopo', p_escopo, 'periodo', jsonb_build_object('de', v_de, 'ate', v_ate),
    'gerado_em', now(),
    'plataforma', public.tvde_operador_plataforma(),
    'viagens', coalesce((select jsonb_agg(jsonb_build_object(
        'codigo', upper(left(replace(r.id::text, '-', ''), 8)), 'pedida_em', r.created_at,
        'inicio', (select min(e.at) from public.tvde_ride_events e where e.ride_id = r.id and e.status = 'em_andamento'),
        'fim', (select max(e.at) from public.tvde_ride_events e where e.ride_id = r.id and e.status = 'finalizada'),
        'estado', r.status, 'origem', r.origin_label, 'destino', r.dest_label,
        'distancia_km', coalesce(r.final_distance_km, r.est_distance_km),
        'valor_cents', coalesce(nullif(r.final_fare_cents, 0), r.est_fare_cents),
        'intermediacao_cents', r.bora_cut_cents, 'pagamento', r.payment_method,
        'motorista', (select coalesce(nullif(trim(d.legal_name), ''), d.name) from public.drivers d where d.user_id = r.driver_id limit 1),
        'matricula', (select d.license_plate from public.drivers d where d.user_id = r.driver_id limit 1)) order by r.created_at)
      from public.tvde_rides r where r.driver_id = any(v_mot) and r.created_at >= v_de and r.created_at < v_ate), '[]'::jsonb),
    'tempos_trabalho', coalesce((select jsonb_agg(jsonb_build_object(
        'motorista', (select coalesce(nullif(trim(d.legal_name), ''), d.name) from public.drivers d where d.user_id = l.driver_user_id limit 1),
        'inicio', l.inicio, 'fim', l.fim, 'fecho', l.fecho,
        'horas', round(extract(epoch from (coalesce(l.fim, now()) - l.inicio)) / 3600.0, 2)) order by l.inicio)
      from public.tvde_driver_work_log l where l.driver_user_id = any(v_mot) and l.inicio < v_ate and coalesce(l.fim, now()) >= v_de), '[]'::jsonb),
    'documentos', coalesce((select jsonb_agg(jsonb_build_object(
        'motorista', coalesce(nullif(trim(d.legal_name), ''), d.name),
        'cmtvde_numero', f.tvde_cert_numero, 'cmtvde_validade', f.tvde_cert_validade,
        'carta_validade', f.carta_validade, 'carta_b_desde', d.carta_b_emitida_em,
        'operador', (select jsonb_build_object('denominacao', o.denominacao, 'nipc', o.nipc, 'licenca', o.licenca_imt_numero,
                        'licenca_validade', o.licenca_imt_validade) from public.tvde_operators o where o.id = d.tvde_operator_id),
        'veiculos', (select coalesce(jsonb_agg(jsonb_build_object('matricula', v.matricula, 'marca', v.marca, 'modelo', v.modelo,
                        'registo_imt', v.registo_imt_numero, 'registo_validade', v.registo_imt_validade,
                        'seguro_validade', v.seguro_validade, 'inspecao', v.inspecao_proxima, 'distico', v.distico_id,
                        'estado', v.estado)), '[]'::jsonb)
                      from public.tvde_driver_vehicle dv join public.tvde_vehicles v on v.id = dv.vehicle_id
                     where dv.driver_user_id = d.user_id and (v_veh is null or v.id = v_veh))))
      from public.drivers d left join public.motorista_ficha_legal f on f.user_id = d.user_id
     where d.user_id = any(v_mot)), '[]'::jsonb),
    'queixas', coalesce((select jsonb_agg(jsonb_build_object('numero', q.numero, 'data', q.created_at, 'canal', q.canal,
        'categoria', q.categoria, 'descricao', q.descricao, 'estado', q.estado, 'diligencias', q.diligencias,
        'resolucao', q.resolucao, 'resolvida_em', q.resolvida_em,
        'motorista', (select d.name from public.drivers d where d.user_id = q.driver_user_id limit 1)) order by q.created_at)
      from public.tvde_complaints q where (q.driver_user_id = any(v_mot) or (v_drv is null and v_op is null and v_veh is null))
        and q.created_at >= v_de and q.created_at < v_ate), '[]'::jsonb),
    'bloqueios', coalesce((select jsonb_agg(jsonb_build_object('data', e.at, 'tipo', e.tipo, 'motivo', e.motivo, 'ator', e.ator,
        'motorista', (select d.name from public.drivers d where d.user_id = e.driver_user_id limit 1)) order by e.at)
      from public.tvde_compliance_events e
     where e.driver_user_id = any(v_mot) and e.at >= v_de and e.at < v_ate
       and e.tipo in ('bloqueio','desbloqueio','bloqueio_manual','desbloqueio_manual','online_recusado')), '[]'::jsonb));
end $$;
revoke all on function public._tvde_fiscal_dados(jsonb) from public, anon, authenticated;

create or replace function public.admin_tvde_fiscal_criar(p_entidade text, p_agente text, p_finalidade text,
                                                         p_escopo jsonb, p_horas int default 24)
returns jsonb language plpgsql security definer set search_path to 'public' as $$
declare a public.tvde_fiscal_access;
begin
  perform public._tvde_admin_ou_erro();
  if coalesce(length(trim(p_entidade)), 0) < 2 or coalesce(length(trim(p_finalidade)), 0) < 3 then
    raise exception 'entidade_e_finalidade_obrigatorias';
  end if;
  insert into public.tvde_fiscal_access (codigo, entidade, agente, finalidade, escopo, criado_por, expira_em)
  values (translate(encode(extensions.gen_random_bytes(12), 'base64'), '+/=', 'xyz'), trim(p_entidade),
          nullif(trim(coalesce(p_agente, '')), ''), trim(p_finalidade), coalesce(p_escopo, '{}'::jsonb), auth.uid(),
          now() + make_interval(hours => least(greatest(coalesce(p_horas, 24), 1), 168)))
  returning * into a;
  insert into public.tvde_compliance_events (tipo, ator_user_id, ator, motivo, meta)
  values ('fiscalizacao_acesso_criado', auth.uid(), 'admin', a.entidade,
          jsonb_build_object('acesso_id', a.id, 'finalidade', a.finalidade, 'escopo', a.escopo, 'expira_em', a.expira_em));
  perform public.log_admin_action('tvde_fiscalizacao_acesso', 'tvde_fiscal_access', a.id::text,
                                  jsonb_build_object('entidade', a.entidade, 'escopo', a.escopo));
  return jsonb_build_object('id', a.id, 'codigo', a.codigo, 'expira_em', a.expira_em,
    'url', coalesce(public.get_setting('tvde_fiscal_base_url') #>> '{}', 'https://app.boraguarda.com/fiscalizacao.html?c=') || a.codigo);
end $$;
revoke all on function public.admin_tvde_fiscal_criar(text, text, text, jsonb, int) from public, anon;
grant execute on function public.admin_tvde_fiscal_criar(text, text, text, jsonb, int) to authenticated;

create or replace function public.admin_tvde_fiscal_lista()
returns jsonb language plpgsql stable security definer set search_path to 'public' as $$
begin
  perform public._tvde_admin_ou_erro();
  return coalesce((select jsonb_agg(jsonb_build_object('id', a.id, 'entidade', a.entidade, 'agente', a.agente,
      'finalidade', a.finalidade, 'escopo', a.escopo, 'criado_em', a.criado_em, 'expira_em', a.expira_em,
      'revogado_em', a.revogado_em, 'consultas', a.consultas, 'ultima_consulta', a.ultima_consulta,
      'ativo', a.revogado_em is null and a.expira_em > now()) order by a.criado_em desc)
    from public.tvde_fiscal_access a), '[]'::jsonb);
end $$;
revoke all on function public.admin_tvde_fiscal_lista() from public, anon;
grant execute on function public.admin_tvde_fiscal_lista() to authenticated;

create or replace function public.admin_tvde_fiscal_revogar(p_id uuid)
returns jsonb language plpgsql security definer set search_path to 'public' as $$
begin
  perform public._tvde_admin_ou_erro();
  update public.tvde_fiscal_access set revogado_em = now() where id = p_id and revogado_em is null;
  insert into public.tvde_compliance_events (tipo, ator_user_id, ator, meta)
  values ('fiscalizacao_acesso_revogado', auth.uid(), 'admin', jsonb_build_object('acesso_id', p_id));
  return jsonb_build_object('ok', true);
end $$;
revoke all on function public.admin_tvde_fiscal_revogar(uuid) from public, anon;
grant execute on function public.admin_tvde_fiscal_revogar(uuid) to authenticated;

-- O admin exporta diretamente (também fica registado).
create or replace function public.admin_tvde_fiscal_exportar(p_escopo jsonb)
returns jsonb language plpgsql security definer set search_path to 'public' as $$
begin
  perform public._tvde_admin_ou_erro();
  insert into public.tvde_compliance_events (tipo, ator_user_id, ator, meta)
  values ('fiscalizacao_exportacao', auth.uid(), 'admin', jsonb_build_object('escopo', p_escopo));
  return public._tvde_fiscal_dados(p_escopo);
end $$;
revoke all on function public.admin_tvde_fiscal_exportar(jsonb) from public, anon;
grant execute on function public.admin_tvde_fiscal_exportar(jsonb) to authenticated;

-- Consulta pela entidade fiscalizadora, só com o código (sem conta Bora).
create or replace function public.tvde_fiscal_consulta(p_codigo text)
returns jsonb language plpgsql security definer set search_path to 'public' as $$
declare a public.tvde_fiscal_access;
begin
  if p_codigo is null or length(p_codigo) < 12 or length(p_codigo) > 40 then
    return jsonb_build_object('ok', false, 'motivo', 'codigo_invalido');
  end if;
  select * into a from public.tvde_fiscal_access where codigo = p_codigo;
  if not found then return jsonb_build_object('ok', false, 'motivo', 'codigo_invalido'); end if;
  if a.revogado_em is not null then return jsonb_build_object('ok', false, 'motivo', 'codigo_revogado'); end if;
  if a.expira_em <= now() then return jsonb_build_object('ok', false, 'motivo', 'codigo_expirado', 'expirou_em', a.expira_em); end if;
  update public.tvde_fiscal_access set consultas = consultas + 1, ultima_consulta = now() where id = a.id;
  insert into public.tvde_compliance_events (tipo, ator, motivo, meta)
  values ('fiscalizacao_consulta', 'entidade_fiscalizadora', a.entidade,
          jsonb_build_object('acesso_id', a.id, 'agente', a.agente, 'escopo', a.escopo));
  return jsonb_build_object('ok', true, 'entidade', a.entidade, 'finalidade', a.finalidade, 'expira_em', a.expira_em)
         || public._tvde_fiscal_dados(a.escopo);
end $$;
revoke all on function public.tvde_fiscal_consulta(text) from public;
grant execute on function public.tvde_fiscal_consulta(text) to anon, authenticated;

insert into public.platform_settings (key, value, description, category) values
  ('tvde_fiscal_base_url', to_jsonb('https://app.boraguarda.com/fiscalizacao.html?c='::text),
   'Endereço da página de consulta das entidades fiscalizadoras (o código vai no fim).', 'tvde_conformidade')
on conflict (key) do nothing;
