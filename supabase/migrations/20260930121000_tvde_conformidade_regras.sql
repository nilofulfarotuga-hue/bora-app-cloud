-- tvde-conformidade-lei-59-2026 · FASE 2 (regras no servidor) — 2026-09-30
-- Tudo atrás de interruptores (tvde_conf_ativa = mestre E o interruptor).
-- Com o mestre desligado nenhuma destas funções muda o que a app faz: só
-- CALCULAM e GUARDAM (estado de conformidade, horas, teto dos 25%).

-- ── Último sinal do motorista (heartbeat ou GPS) ────────────────────────────
create or replace function public._tvde_ultimo_sinal(p_driver uuid)
returns timestamptz language plpgsql stable security definer set search_path to 'public' as $$
declare v_id uuid; v_hb timestamptz; v_loc timestamptz;
begin
  select d.id, d.last_heartbeat_at into v_id, v_hb from public.drivers d where d.user_id = p_driver limit 1;
  select max(l.last_updated) into v_loc from public.driver_locations l
   where l.driver_id in (p_driver, v_id);
  return greatest(coalesce(v_hb, '-infinity'::timestamptz), coalesce(v_loc, '-infinity'::timestamptz));
end $$;
revoke all on function public._tvde_ultimo_sinal(uuid) from public, anon, authenticated;

-- ── Horas de serviço na janela móvel de 24 h (art. 13) ──────────────────────
-- Só o que o Bora sabe (períodos online). As horas noutras plataformas vêm da
-- declaração do motorista e somam-se em tvde_driver_horas_total.
create or replace function public.tvde_driver_horas_24h(p_driver uuid)
returns numeric language plpgsql stable security definer set search_path to 'public' as $$
declare
  v_now timestamptz := now();
  v_de timestamptz := now() - interval '24 hours';
  v_hb int := coalesce((public.get_setting('tvde_heartbeat_window_seconds') #>> '{}')::int, 600);
  v_sinal timestamptz := public._tvde_ultimo_sinal(p_driver);
  v_fim_aberto timestamptz;
  v_seg numeric;
begin
  -- Período aberto: conta até agora se há sinal recente; senão só até ao último sinal.
  v_fim_aberto := case when v_sinal > v_now - make_interval(secs => v_hb) then v_now
                       else greatest(v_sinal, '-infinity'::timestamptz) end;
  select coalesce(sum(greatest(0, extract(epoch from (
           least(coalesce(l.fim, v_fim_aberto), v_now) - greatest(l.inicio, v_de))))), 0)
    into v_seg
    from public.tvde_driver_work_log l
   where l.driver_user_id = p_driver
     and coalesce(l.fim, v_now) > v_de;
  return round(v_seg / 3600.0, 2);
end $$;
revoke all on function public.tvde_driver_horas_24h(uuid) from public, anon;
grant execute on function public.tvde_driver_horas_24h(uuid) to authenticated;

create or replace function public.tvde_driver_horas_total(p_driver uuid)
returns numeric language sql stable security definer set search_path to 'public' as $$
  select public.tvde_driver_horas_24h(p_driver)
       + coalesce((select case when d.tvde_horas_outras_declaradas_em > now() - interval '24 hours'
                               then d.tvde_horas_outras_plataformas else 0 end
                     from public.drivers d where d.user_id = p_driver limit 1), 0)
$$;
revoke all on function public.tvde_driver_horas_total(uuid) from public, anon;
grant execute on function public.tvde_driver_horas_total(uuid) to authenticated;

-- ── Cálculo de conformidade de um motorista (art. 10, 12, 14) ──────────────
-- Devolve {motivos:[...bloqueiam...], avisos:[...não bloqueiam...]}.
create or replace function public._tvde_conformidade_calc(p_driver uuid)
returns jsonb language plpgsql stable security definer set search_path to 'public' as $$
declare
  d public.drivers; f public.motorista_ficha_legal; o public.tvde_operators; v public.tvde_vehicles;
  c public.tvde_driver_compliance;
  v_hoje date := (now() at time zone 'Europe/Lisbon')::date;
  v_aviso int := coalesce((select max(x::int) from jsonb_array_elements_text(public.get_setting('tvde_docs_alert_days')) x), 30);
  v_carta_anos int := coalesce((public.get_setting('tvde_carta_min_anos') #>> '{}')::int, 3);
  v_idade int; v_lug int := coalesce((public.get_setting('tvde_vehicle_max_seats') #>> '{}')::int, 9);
  v_base date;
  m jsonb := '[]'::jsonb; a jsonb := '[]'::jsonb;
  r record;
begin
  select * into d from public.drivers where user_id = p_driver and deleted_at is null limit 1;
  if not found then return jsonb_build_object('motivos', '[]'::jsonb, 'avisos', '[]'::jsonb); end if;
  select * into f from public.motorista_ficha_legal where user_id = p_driver;
  select * into o from public.tvde_operators where id = d.tvde_operator_id;
  select vv.* into v from public.tvde_driver_vehicle dv join public.tvde_vehicles vv on vv.id = dv.vehicle_id
   where dv.driver_user_id = p_driver and dv.ativo order by dv.desde desc limit 1;
  select * into c from public.tvde_driver_compliance where driver_user_id = p_driver;

  -- Motorista
  if f.tvde_cert_numero is null then
    m := m || jsonb_build_object('codigo','cmtvde_em_falta','rotulo','Certificado de motorista TVDE (CMTVDE) em falta');
  end if;
  -- Validades: caducado bloqueia; a caducar avisa.
  for r in select * from (values
      ('cmtvde', 'Certificado de motorista TVDE (CMTVDE)', f.tvde_cert_validade, true),
      ('carta', 'Carta de condução', f.carta_validade, true),
      ('licenca_operador', 'Licença IMT do operador', o.licenca_imt_validade, d.tvde_operator_id is not null),
      ('registo_veiculo', 'Registo do veículo no IMT', v.registo_imt_validade, v.id is not null),
      ('seguro', 'Seguro do veículo', v.seguro_validade, v.id is not null),
      ('inspecao', 'Inspeção do veículo', v.inspecao_proxima, v.id is not null and v.inspecao_proxima is not null)
    ) t(cod, rot, val, aplica)
  loop
    continue when not r.aplica;
    if r.val is null then
      m := m || jsonb_build_object('codigo', r.cod || '_sem_validade', 'rotulo', r.rot || ': validade em falta');
    elsif r.val < v_hoje then
      m := m || jsonb_build_object('codigo', r.cod || '_caducado', 'rotulo', r.rot || ' caducado', 'validade', r.val);
    elsif r.val - v_hoje <= v_aviso then
      a := a || jsonb_build_object('codigo', r.cod || '_a_caducar', 'rotulo', r.rot || ' caduca em ' || (r.val - v_hoje) || ' dias',
                                   'validade', r.val, 'dias', r.val - v_hoje);
    end if;
  end loop;
  if d.carta_b_emitida_em is null then
    m := m || jsonb_build_object('codigo','carta_b_data_em_falta','rotulo','Data de emissão da carta B em falta');
  elsif d.carta_b_emitida_em > (v_hoje - make_interval(years => v_carta_anos))::date then
    m := m || jsonb_build_object('codigo','carta_b_menos_anos','rotulo','Carta B com menos de ' || v_carta_anos || ' anos');
  end if;
  -- Operador (art. 10: o motorista trabalha por um operador licenciado)
  if d.tvde_operator_id is null then
    m := m || jsonb_build_object('codigo','operador_em_falta','rotulo','Sem operador TVDE associado');
  elsif o.estado is distinct from 'aprovado' then
    m := m || jsonb_build_object('codigo','operador_nao_aprovado','rotulo','Operador TVDE não aprovado (' || coalesce(o.estado,'?') || ')');
  end if;
  if d.tvde_contrato_operador_path is null and not exists (
       select 1 from public.tvde_driver_documents td where td.driver_id = d.id
          and td.doc_type = 'contrato_operador' and td.status = 'approved') then
    m := m || jsonb_build_object('codigo','contrato_operador_em_falta','rotulo','Contrato escrito com o operador em falta');
  end if;
  -- Veículo (art. 12)
  if v.id is null then
    m := m || jsonb_build_object('codigo','veiculo_em_falta','rotulo','Sem veículo TVDE associado');
  else
    if v.estado <> 'aprovado' then
      m := m || jsonb_build_object('codigo','veiculo_nao_aprovado','rotulo','Veículo ' || v.matricula || ' não aprovado (' || v.estado || ')');
    end if;
    v_idade := case when v.eletrico then coalesce((public.get_setting('tvde_vehicle_max_age_ev_years') #>> '{}')::int, 12)
                    else coalesce((public.get_setting('tvde_vehicle_max_age_years') #>> '{}')::int, 10) end;
    v_base := coalesce(v.primeira_matricula_em, case when v.ano_fabrico is not null then make_date(v.ano_fabrico, 1, 1) end);
    if v_base is null then
      m := m || jsonb_build_object('codigo','veiculo_idade_desconhecida','rotulo','Data da 1.ª matrícula do veículo em falta');
    elsif v_base < (v_hoje - make_interval(years => v_idade))::date then
      m := m || jsonb_build_object('codigo','veiculo_idade_excedida','rotulo','Veículo com mais de ' || v_idade || ' anos');
    elsif (v_base + make_interval(years => v_idade))::date - v_hoje <= v_aviso then
      a := a || jsonb_build_object('codigo','veiculo_idade_a_caducar','rotulo','Veículo atinge a idade máxima em '
             || ((v_base + make_interval(years => v_idade))::date - v_hoje) || ' dias');
    end if;
    if v.lugares is not null and v.lugares > v_lug then
      m := m || jsonb_build_object('codigo','veiculo_lotacao','rotulo','Veículo com mais de ' || v_lug || ' lugares');
    end if;
    if v.seguro_acidentes_pessoais is distinct from true then
      a := a || jsonb_build_object('codigo','seguro_acidentes_pessoais','rotulo','Confirmar seguro de acidentes pessoais');
    end if;
    if v.inspecao_proxima is null then
      a := a || jsonb_build_object('codigo','inspecao_sem_data','rotulo','Data da próxima inspeção em falta');
    end if;
  end if;
  -- Bloqueio manual do admin
  if coalesce(c.bloqueio_manual, false) then
    m := m || jsonb_build_object('codigo','bloqueio_manual','rotulo','Bloqueado pelo admin: ' || coalesce(c.bloqueio_manual_motivo, 'sem motivo'));
  end if;
  -- Avisos que não bloqueiam
  if d.fala_portugues is null then
    a := a || jsonb_build_object('codigo','lingua_por_declarar','rotulo','Declarar se fala português');
  end if;
  if d.tvde_curso_atualizacao_em is null then
    a := a || jsonb_build_object('codigo','curso_atualizacao_por_declarar','rotulo','Data do curso de atualização por declarar');
  end if;
  return jsonb_build_object('motivos', m, 'avisos', a);
end $$;
revoke all on function public._tvde_conformidade_calc(uuid) from public, anon, authenticated;

-- Guarda o estado e regista no histórico quando muda.
create or replace function public.tvde_driver_conformidade_refresh(p_driver uuid, p_ator text default 'sistema')
returns jsonb language plpgsql security definer set search_path to 'public' as $$
declare v_calc jsonb; v_bloq boolean; v_ant boolean;
begin
  v_calc := public._tvde_conformidade_calc(p_driver);
  v_bloq := jsonb_array_length(v_calc->'motivos') > 0;
  select bloqueado into v_ant from public.tvde_driver_compliance where driver_user_id = p_driver;
  insert into public.tvde_driver_compliance as c (driver_user_id, bloqueado, motivos, avisos, verificado_em)
  values (p_driver, v_bloq, v_calc->'motivos', v_calc->'avisos', now())
  on conflict (driver_user_id) do update
     set bloqueado = excluded.bloqueado, motivos = excluded.motivos,
         avisos = excluded.avisos, verificado_em = now();
  if v_ant is distinct from v_bloq then
    insert into public.tvde_compliance_events (tipo, driver_user_id, ator, motivo, meta)
    values (case when v_bloq then 'bloqueio' else 'desbloqueio' end, p_driver, p_ator,
            (select string_agg(e->>'rotulo', '; ') from jsonb_array_elements(v_calc->'motivos') e),
            jsonb_build_object('motivos', v_calc->'motivos',
                               'efetivo', public.tvde_conf_ativa('tvde_compliance_block')));
  end if;
  return v_calc || jsonb_build_object('bloqueado', v_bloq);
end $$;
revoke all on function public.tvde_driver_conformidade_refresh(uuid, text) from public, anon, authenticated;

-- ── Portão do despacho: pode este motorista receber esta oferta? ───────────
-- Com o mestre desligado devolve SEMPRE true (sai na 1.ª linha).
-- Falha aberta: um erro aqui nunca pára o despacho (fica no e2e_log).
create or replace function public.tvde_driver_offer_allowed(p_driver uuid, p_ride uuid)
returns boolean language plpgsql security definer set search_path to 'public' as $$
declare r public.tvde_rides; d public.drivers; v_lim numeric;
begin
  if not coalesce((public.get_setting('tvde_compliance_enforce') #>> '{}')::boolean, false) then
    return true;
  end if;
  if public.tvde_conf_ativa('tvde_compliance_block')
     and jsonb_array_length(public._tvde_conformidade_calc(p_driver)->'motivos') > 0 then
    return false;
  end if;
  if public.tvde_conf_ativa('tvde_work_limit_enforce') then
    v_lim := coalesce((public.get_setting('tvde_work_limit_hours') #>> '{}')::numeric, 10);
    if public.tvde_driver_horas_total(p_driver) >= v_lim then return false; end if;
  end if;
  if p_ride is not null and public.tvde_conf_ativa('tvde_pref_matching_enforce') then
    select * into r from public.tvde_rides where id = p_ride;
    select * into d from public.drivers where user_id = p_driver limit 1;
    if r.pref_fala_portugues and d.fala_portugues is not true then return false; end if;
    if r.pede_mobilidade_reduzida and not exists (
         select 1 from public.tvde_driver_vehicle dv join public.tvde_vehicles v on v.id = dv.vehicle_id
          where dv.driver_user_id = p_driver and dv.ativo and v.adaptado_mobilidade_reduzida) then
      return false;
    end if;
  end if;
  return true;
exception when others then
  begin
    insert into public.e2e_log (fluxo, passo, estado, detalhe, device)
    values ('tvde-conformidade', 'offer_allowed', 'falhou', p_driver || ' ' || sqlerrm, 'db');
  exception when others then null;
  end;
  return true;
end $$;
revoke all on function public.tvde_driver_offer_allowed(uuid, uuid) from public, anon, authenticated;

-- ── Tempos de serviço: abrir/fechar período ao ficar online/offline ─────────
create or replace function public.fn_tvde_work_log_online()
returns trigger language plpgsql security definer set search_path to 'public' as $$
begin
  if new.vehicle_type is distinct from 'carro_passageiros' or new.user_id is null then return new; end if;
  begin
    if coalesce(new.is_online, false) and not coalesce(old.is_online, false) then
      insert into public.tvde_driver_work_log (driver_user_id, inicio)
      values (new.user_id, now())
      on conflict (driver_user_id) where fim is null do nothing;
    elsif coalesce(old.is_online, false) and not coalesce(new.is_online, false) then
      update public.tvde_driver_work_log set fim = now(), fecho = 'offline'
       where driver_user_id = new.user_id and fim is null;
    end if;
  exception when others then
    insert into public.e2e_log (fluxo, passo, estado, detalhe, device)
    values ('tvde-conformidade', 'work_log', 'falhou', new.user_id || ' ' || sqlerrm, 'db');
  end;
  return new;
end $$;
create trigger trg_tvde_work_log_online after update of is_online on public.drivers
  for each row execute function public.fn_tvde_work_log_online();

-- Fecha períodos abertos de quem ficou sem sinal (app morta, sem rede).
create or replace function public.tvde_work_log_sweep()
returns integer language plpgsql security definer set search_path to 'public' as $$
declare v_hb int := coalesce((public.get_setting('tvde_heartbeat_window_seconds') #>> '{}')::int, 600);
        n int;
begin
  with fechar as (
    select l.id, public._tvde_ultimo_sinal(l.driver_user_id) s
      from public.tvde_driver_work_log l where l.fim is null)
  update public.tvde_driver_work_log l
     set fim = greatest(l.inicio, f.s), fecho = 'sem_sinal'
    from fechar f
   where l.id = f.id and f.s < now() - make_interval(secs => v_hb);
  get diagnostics n = row_count;
  return n;
end $$;
revoke all on function public.tvde_work_log_sweep() from public, anon, authenticated;

-- ── Não ficar online bloqueado / acima do limite de horas ───────────────────
create or replace function public.fn_tvde_conformidade_online()
returns trigger language plpgsql security definer set search_path to 'public' as $$
declare v_mot text; v_lim numeric; v_h numeric;
begin
  if coalesce(new.is_online, false) and not coalesce(old.is_online, false)
     and new.vehicle_type = 'carro_passageiros' and new.user_id is not null
     and coalesce((public.get_setting('tvde_compliance_enforce') #>> '{}')::boolean, false) then
    if public.tvde_conf_ativa('tvde_compliance_block') then
      select string_agg(e->>'rotulo', '; ') into v_mot
        from jsonb_array_elements(public._tvde_conformidade_calc(new.user_id)->'motivos') e;
      if v_mot is not null then
        insert into public.tvde_compliance_events (tipo, driver_user_id, ator, motivo)
        values ('online_recusado', new.user_id, 'sistema', v_mot);
        raise exception 'TVDE_BLOQUEADO: %', v_mot
          using hint = 'Resolve os documentos em falta na área Conformidade para voltares a ficar online.';
      end if;
    end if;
    if public.tvde_conf_ativa('tvde_work_limit_enforce') then
      v_lim := coalesce((public.get_setting('tvde_work_limit_hours') #>> '{}')::numeric, 10);
      v_h := public.tvde_driver_horas_total(new.user_id);
      if v_h >= v_lim then
        raise exception 'LIMITE_HORAS: Atingiste o limite legal de % horas', v_lim
          using hint = 'Nas últimas 24 horas já fizeste ' || v_h || ' h de serviço.';
      end if;
    end if;
  end if;
  return new;
end $$;
create trigger trg_tvde_conformidade_online before update of is_online on public.drivers
  for each row execute function public.fn_tvde_conformidade_online();

-- ── Só pagamento eletrónico (art. 15.º n.º 7) ───────────────────────────────
-- Deixa passar o que já está pago (volta de pacote, assinatura, pacote).
create or replace function public.fn_tvde_pagamento_eletronico()
returns trigger language plpgsql security definer set search_path to 'public' as $$
begin
  if new.payment_method = 'cash'
     and (tg_op = 'INSERT' or old.payment_method is distinct from 'cash')
     and new.roundtrip_credit_id is null
     and not coalesce(new.used_subscription_ride, false)
     and not coalesce(new.is_return_leg, false)
     and public.tvde_conf_ativa('tvde_electronic_payment_only') then
    raise exception 'PAGAMENTO_ELETRONICO_OBRIGATORIO'
      using hint = 'No TVDE só se aceita pagamento por cartão ou MB Way (Lei 45/2018, art. 15.º n.º 7).';
  end if;
  return new;
end $$;
create trigger trg_tvde_pagamento_eletronico before insert or update of payment_method on public.tvde_rides
  for each row execute function public.fn_tvde_pagamento_eletronico();

-- ── Preferências do cliente copiadas para a corrida ─────────────────────────
create or replace function public.fn_tvde_rides_prefs()
returns trigger language plpgsql security definer set search_path to 'public' as $$
declare p public.tvde_client_prefs;
begin
  select * into p from public.tvde_client_prefs where client_id = new.client_id;
  if found then
    new.pref_fala_portugues := p.fala_portugues;
    new.pede_mobilidade_reduzida := p.mobilidade_reduzida;
    new.necessidades := jsonb_build_object('cao_guia', p.cao_guia, 'cadeira_rodas', p.cadeira_rodas,
                                           'carrinho_bebe', p.carrinho_bebe);
  end if;
  return new;
exception when others then
  return new;
end $$;
create trigger trg_tvde_rides_prefs before insert on public.tvde_rides
  for each row execute function public.fn_tvde_rides_prefs();

-- ── Teto da taxa de intermediação (art. 15.º n.º 3) — só VERIFICA ───────────
-- Base: parte do Bora (bora_cut_cents) sobre o valor da viagem, os dois com o
-- mesmo tratamento de IVA (hoje sem IVA: não há empresa). Não altera o preço.
create or replace function public.tvde_verificar_intermediacao(p_ride uuid)
returns jsonb language plpgsql security definer set search_path to 'public' as $$
declare r public.tvde_rides; v_total int; v_teto numeric; v_pct numeric; v_ok boolean;
begin
  select * into r from public.tvde_rides where id = p_ride;
  if not found or r.status <> 'finalizada' then return null; end if;
  v_teto := coalesce((public.get_setting('tvde_intermediacao_teto_pct') #>> '{}')::numeric, 25);
  v_total := coalesce(r.driver_earn_cents, 0) + coalesce(r.bora_cut_cents, 0);
  if v_total <= 0 or r.bora_cut_cents is null then
    v_pct := null; v_ok := true;
  else
    v_pct := round(100.0 * r.bora_cut_cents / v_total, 2);
    v_ok := v_pct <= v_teto;
  end if;
  insert into public.tvde_intermediacao_verificacao as iv
    (ride_id, valor_viagem_cents, intermediacao_cents, pct, teto_pct, cumpre, base, verificado_em)
  values (p_ride, greatest(v_total, 0), coalesce(r.bora_cut_cents, 0), v_pct, v_teto, v_ok,
          'bora_cut / (motorista + bora_cut); sem IVA (empresa por constituir)', now())
  on conflict (ride_id) do update set valor_viagem_cents = excluded.valor_viagem_cents,
     intermediacao_cents = excluded.intermediacao_cents, pct = excluded.pct, teto_pct = excluded.teto_pct,
     cumpre = excluded.cumpre, base = excluded.base, verificado_em = now();
  if not v_ok then
    insert into public.tvde_compliance_events (tipo, ride_id, driver_user_id, ator, motivo, meta)
    values ('intermediacao_acima_teto', p_ride, r.driver_id, 'sistema',
            'Taxa de intermediação ' || v_pct || '% acima do teto de ' || v_teto || '%',
            jsonb_build_object('pct', v_pct, 'bora_cut_cents', r.bora_cut_cents, 'total_cents', v_total));
  end if;
  return jsonb_build_object('pct', v_pct, 'cumpre', v_ok, 'teto', v_teto);
end $$;
revoke all on function public.tvde_verificar_intermediacao(uuid) from public, anon, authenticated;

create or replace function public.fn_tvde_intermediacao_no_fim()
returns trigger language plpgsql security definer set search_path to 'public' as $$
begin
  if new.status = 'finalizada' then
    begin
      perform public.tvde_verificar_intermediacao(new.id);
    exception when others then
      insert into public.e2e_log (fluxo, passo, estado, detalhe, device)
      values ('tvde-conformidade', 'intermediacao', 'falhou', new.id || ' ' || sqlerrm, 'db');
    end;
  end if;
  return new;
end $$;
create trigger trg_tvde_intermediacao after update of status, bora_cut_cents on public.tvde_rides
  for each row when (new.status = 'finalizada')
  execute function public.fn_tvde_intermediacao_no_fim();

-- ── Avaliação do passageiro proibida (art. 19.º n.º 5) ──────────────────────
-- Igual à anterior + 1 bloco: com o interruptor ligado a avaliação do
-- motorista é ignorada (não grava, não marca rated_by_driver).
create or replace function public.tvde_rate(p_ride_id uuid, p_stars smallint, p_comment text default null::text)
returns jsonb language plpgsql security definer set search_path to 'public' as $function$
DECLARE v_uid UUID := auth.uid(); v_ride public.tvde_rides; v_subject_type TEXT; v_subject_id TEXT;
BEGIN
  IF p_stars < 1 OR p_stars > 5 THEN RAISE EXCEPTION 'invalid_stars'; END IF;
  SELECT * INTO v_ride FROM public.tvde_rides WHERE id = p_ride_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'ride_not_found'; END IF;
  IF v_ride.status <> 'finalizada' THEN RAISE EXCEPTION 'ride_not_finished'; END IF;
  IF v_uid = v_ride.client_id THEN
    IF v_ride.rated_by_client THEN RAISE EXCEPTION 'already_rated'; END IF;
    v_subject_type := 'driver'; v_subject_id := v_ride.driver_id::text;
    INSERT INTO public.ratings (driver_id, rating, stars, comment, subject_type, subject_id, rater_user_id)
      VALUES (v_ride.driver_id, p_stars, p_stars, p_comment, 'driver', v_subject_id, v_uid);
    UPDATE public.tvde_rides SET rated_by_client = true WHERE id = p_ride_id;
  ELSIF v_uid = v_ride.driver_id THEN
    -- 2026-09-30 conformidade (art. 19.º n.º 5): avaliação de passageiros proibida.
    IF public.tvde_conf_ativa('tvde_driver_rates_client_disabled') THEN
      RETURN jsonb_build_object('ride_id', p_ride_id, 'ignorada', true,
                                'motivo', 'avaliacao_passageiro_desativada');
    END IF;
    IF v_ride.rated_by_driver THEN RAISE EXCEPTION 'already_rated'; END IF;
    v_subject_type := 'tvde_passenger'; v_subject_id := v_ride.client_id::text;
    INSERT INTO public.ratings (rating, stars, comment, subject_type, subject_id, rater_user_id)
      VALUES (p_stars, p_stars, p_comment, 'tvde_passenger', v_subject_id, v_uid);
    UPDATE public.tvde_rides SET rated_by_driver = true WHERE id = p_ride_id;
  ELSE
    RAISE EXCEPTION 'not_ride_party';
  END IF;
  RETURN jsonb_build_object('ride_id', p_ride_id, 'subject_type', v_subject_type, 'stars', p_stars);
END; $function$;

-- ── Cron diário: estado de todos os motoristas + avisos 30/7 dias ───────────
create or replace function public.tvde_conformidade_diaria()
returns jsonb language plpgsql security definer set search_path to 'public' as $$
declare r record; e jsonb; n_mot int := 0; n_bloq int := 0; n_avisos int := 0;
  v_dias int[] := array(select x::int from jsonb_array_elements_text(public.get_setting('tvde_docs_alert_days')) x);
  v_mestre boolean := coalesce((public.get_setting('tvde_compliance_enforce') #>> '{}')::boolean, false);
  v_calc jsonb; v_chave text; v_limiar int; v_resumo text := '';
begin
  perform public.tvde_work_log_sweep();
  for r in select d.user_id from public.drivers d
            where d.vehicle_type = 'carro_passageiros' and d.deleted_at is null
              and d.user_id is not null and d.approval_status = 'approved'
  loop
    n_mot := n_mot + 1;
    v_calc := public.tvde_driver_conformidade_refresh(r.user_id);
    if (v_calc->>'bloqueado')::boolean then n_bloq := n_bloq + 1; end if;
    -- Avisos de validade só com o mestre ligado (antes disso seriam ruído:
    -- ainda não há operadores nem veículos registados).
    continue when not v_mestre;
    for e in select * from jsonb_array_elements(v_calc->'avisos') loop
      continue when e->>'dias' is null;
      select min(x) into v_limiar from unnest(v_dias) x where x >= (e->>'dias')::int;
      continue when v_limiar is null;
      v_chave := (e->>'codigo') || '|' || (e->>'validade') || '|' || v_limiar;
      continue when exists (select 1 from public.tvde_compliance_events
                             where tipo = 'aviso_validade' and driver_user_id = r.user_id
                               and meta->>'chave' = v_chave);
      insert into public.tvde_compliance_events (tipo, driver_user_id, ator, motivo, meta)
      values ('aviso_validade', r.user_id, 'sistema', e->>'rotulo', jsonb_build_object('chave', v_chave));
      perform public._push_in_app_notification(r.user_id, 'tvde_conformidade', e->>'rotulo',
        'Renova a tempo e atualiza os dados na área Conformidade da app.', e->>'codigo');
      n_avisos := n_avisos + 1;
      v_resumo := v_resumo || r.user_id || ': ' || (e->>'rotulo') || E'\n';
    end loop;
  end loop;
  if v_mestre and n_avisos > 0 then
    perform public.notify_admin_event('tvde_conformidade', 'warning',
      n_avisos || ' aviso(s) de validade TVDE' || E'\n' || v_resumo,
      'driver', null, jsonb_build_object('avisos', n_avisos), '/admin/tvde-conformidade');
  end if;
  insert into public.tvde_compliance_events (tipo, ator, motivo, meta)
  values ('verificacao_diaria', 'sistema', n_bloq || ' de ' || n_mot || ' motoristas com impedimentos',
          jsonb_build_object('motoristas', n_mot, 'com_impedimentos', n_bloq, 'avisos', n_avisos,
                             'bloqueio_efetivo', public.tvde_conf_ativa('tvde_compliance_block')));
  return jsonb_build_object('motoristas', n_mot, 'com_impedimentos', n_bloq, 'avisos', n_avisos);
end $$;
revoke all on function public.tvde_conformidade_diaria() from public, anon, authenticated;

-- ── Relatório mensal AMT ────────────────────────────────────────────────────
create or replace function public.tvde_amt_relatorio_gerar(p_mes date default null)
returns jsonb language plpgsql security definer set search_path to 'public' as $$
declare v_mes date := date_trunc('month', coalesce(p_mes, (now() at time zone 'Europe/Lisbon')::date - interval '1 month'))::date;
  v_pct numeric := coalesce((public.get_setting('tvde_amt_contribuicao_pct') #>> '{}')::numeric, 5);
  v_row public.tvde_amt_reports;
begin
  -- a verificação dos 25% tem de existir para todas as corridas do mês
  perform public.tvde_verificar_intermediacao(r.id) from public.tvde_rides r
    where r.status = 'finalizada'
      and (r.updated_at at time zone 'Europe/Lisbon')::date >= v_mes
      and (r.updated_at at time zone 'Europe/Lisbon')::date < (v_mes + interval '1 month')::date
      and not exists (select 1 from public.tvde_intermediacao_verificacao iv where iv.ride_id = r.id);
  insert into public.tvde_amt_reports as a (mes, viagens, faturado_cents, intermediacao_cents,
     contribuicao_pct, contribuicao_cents, viagens_acima_teto, detalhe, gerado_em)
  select v_mes, count(*), coalesce(sum(iv.valor_viagem_cents), 0), coalesce(sum(iv.intermediacao_cents), 0),
         v_pct, round(coalesce(sum(greatest(iv.intermediacao_cents, 0)), 0) * v_pct / 100.0),
         count(*) filter (where not iv.cumpre),
         jsonb_build_object(
           'por_pagamento', (select jsonb_object_agg(pm, n) from (
               select coalesce(r2.payment_method, '?') pm, count(*) n from public.tvde_rides r2
                where r2.status = 'finalizada'
                  and (r2.updated_at at time zone 'Europe/Lisbon')::date >= v_mes
                  and (r2.updated_at at time zone 'Europe/Lisbon')::date < (v_mes + interval '1 month')::date
                group by 1) q),
           'nota', 'Valores sem IVA (empresa por constituir). Contribuição = % da taxa de intermediação cobrada.'),
         now()
    from public.tvde_rides r join public.tvde_intermediacao_verificacao iv on iv.ride_id = r.id
   where r.status = 'finalizada'
     and (r.updated_at at time zone 'Europe/Lisbon')::date >= v_mes
     and (r.updated_at at time zone 'Europe/Lisbon')::date < (v_mes + interval '1 month')::date
  on conflict (mes) do update set viagens = excluded.viagens, faturado_cents = excluded.faturado_cents,
     intermediacao_cents = excluded.intermediacao_cents, contribuicao_pct = excluded.contribuicao_pct,
     contribuicao_cents = excluded.contribuicao_cents, viagens_acima_teto = excluded.viagens_acima_teto,
     detalhe = excluded.detalhe, gerado_em = now()
  returning * into v_row;
  return to_jsonb(v_row);
end $$;
revoke all on function public.tvde_amt_relatorio_gerar(date) from public, anon, authenticated;

create or replace function public.tvde_amt_relatorio_mensal_cron()
returns void language plpgsql security definer set search_path to 'public' as $$
begin
  if coalesce((public.get_setting('tvde_amt_report_enabled') #>> '{}')::boolean, true) then
    perform public.tvde_amt_relatorio_gerar(null);
  end if;
end $$;
revoke all on function public.tvde_amt_relatorio_mensal_cron() from public, anon, authenticated;

do $$ begin
  perform cron.unschedule(jobname) from cron.job
   where jobname in ('tvde-conformidade-diaria', 'tvde-work-log-sweep', 'tvde-amt-mensal');
  perform cron.schedule('tvde-conformidade-diaria', '15 7 * * *', 'select public.tvde_conformidade_diaria()');
  perform cron.schedule('tvde-work-log-sweep', '*/5 * * * *', 'select public.tvde_work_log_sweep()');
  perform cron.schedule('tvde-amt-mensal', '0 6 1 * *', 'select public.tvde_amt_relatorio_mensal_cron()');
end $$;
