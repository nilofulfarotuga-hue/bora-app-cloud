-- Missão hermes-diretor-2026-11-20 — B3: o vigia por eventos (sentinela), sem IA.
-- Corre de minuto a minuto no pg_cron, só lê linhas recentes e escreve em sentinela_eventos (e no despacho, se for urgente).
-- Não toca em nenhuma zona protegida: lê estados de pedidos, corridas, marcações e conversas; nunca escreve em nenhuma delas.
-- Depende de 20261122190000_hermes_diretor_tabelas.sql (sentinela_eventos).
-- Aplicar pela Claude.ai (a trava do modo automático não deixa o Claude Code mudar estrutura em produção).

-- ───────────────────────── 1. Definições (platform_settings) ─────────────────────────
insert into public.platform_settings (key, value, description, category, is_secret) values
  ('sentinela_ligada',                  'true'::jsonb, 'Vigia por eventos ligado. Desligado, a varredura não cria eventos nem tarefas para o Hermes.', 'sentinela', false),
  ('sentinela_min_loja_por_aceitar',    '8'::jsonb,    'Minutos que um pedido pode ficar sem a loja aceitar antes de o vigia avisar.', 'sentinela', false),
  ('sentinela_min_pronto_sem_estafeta', '5'::jsonb,    'Minutos que um pedido pode ficar a chamar estafeta sem ninguém aceitar antes de o vigia avisar.', 'sentinela', false),
  ('sentinela_min_a_caminho',           '45'::jsonb,   'Minutos que um pedido pode ficar recolhido ou a caminho antes de o vigia avisar.', 'sentinela', false),
  ('sentinela_min_tvde_sem_motorista',  '5'::jsonb,    'Minutos que uma corrida TVDE pode ficar sem motorista antes de o vigia avisar.', 'sentinela', false),
  ('sentinela_min_limpeza_espera',      '30'::jsonb,   'Minutos que uma limpeza pode ficar sem profissional antes de o vigia avisar.', 'sentinela', false),
  ('sentinela_min_lavagem_espera',      '30'::jsonb,   'Minutos que uma lavagem pode ficar sem lavador antes de o vigia avisar.', 'sentinela', false),
  ('sentinela_min_marcacao_espera',     '120'::jsonb,  'Minutos que uma marcação pode ficar à espera de o parceiro confirmar se foi feita antes de o vigia avisar.', 'sentinela', false),
  ('sentinela_min_reserva_espera',      '30'::jsonb,   'Minutos que uma reserva de mesa pode ficar sem resposta do restaurante antes de o vigia avisar.', 'sentinela', false),
  ('sentinela_min_encomenda_telefone',  '30'::jsonb,   'Minutos que uma encomenda por telefone pode ficar parada (nem libertada nem cancelada) antes de o vigia avisar.', 'sentinela', false),
  ('sentinela_min_conversa_sem_resposta','10'::jsonb,  'Minutos que uma pergunta de cliente pode ficar sem resposta (suporte, Amigo Bora, WhatsApp) antes de o vigia avisar.', 'sentinela', false),
  ('sentinela_erros_repetidos_n',       '3'::jsonb,    'Quantas vezes o mesmo erro tem de aparecer em 30 minutos para o vigia avisar. Tarefa agendada que falha avisa logo à primeira.', 'sentinela', false),
  ('sentinela_carrinho_hora',           '21'::jsonb,   'Hora de Lisboa a partir da qual o vigia regista a contagem diária de carrinhos abandonados (só conta, não contacta ninguém).', 'sentinela', false)
on conflict (key) do nothing;

-- ───────────────────────── 2. Estado da varredura (o batimento confere aqui) ─────────────────────────
create table if not exists public.sentinela_estado (
  id                   smallint primary key default 1 check (id = 1),
  ultima_varredura     timestamptz,
  duracao_ms           integer,
  eventos_novos        integer not null default 0,
  detetores_com_erro   integer not null default 0,
  ultimo_erro          text,
  ultimo_erro_em       timestamptz,
  ligada               boolean
);
alter table public.sentinela_estado enable row level security;
drop policy if exists sentinela_estado_admin on public.sentinela_estado;
create policy sentinela_estado_admin on public.sentinela_estado for all to authenticated using (public.is_admin()) with check (public.is_admin());
revoke all on public.sentinela_estado from anon;
insert into public.sentinela_estado (id) values (1) on conflict (id) do nothing;

-- ───────────────────────── 3. Utilitários ─────────────────────────
create or replace function public._sentinela_num(p_chave text, p_padrao numeric)
returns numeric language sql stable security definer set search_path = public, pg_temp as $$
  select coalesce((select nullif(value #>> '{}', '')::numeric from public.platform_settings where key = p_chave), p_padrao)
$$;

-- Tira ids longos e emails de um texto de erro, para o evento nunca levar dados pessoais.
create or replace function public._sentinela_limpa(p_texto text)
returns text language sql immutable set search_path = public, pg_temp as $$
  select left(regexp_replace(coalesce(p_texto, ''), '\S+@\S+|[0-9a-fA-F-]{8,}', '#', 'g'), 80)
$$;

-- ───────────────────────── 4. Registar um evento (com dedup e despacho se urgente) ─────────────────────────
create or replace function public.sentinela_registar(
  p_tipo text, p_gravidade text, p_chave text, p_titulo text, p_dados jsonb, p_janela_min integer default 30
) returns bigint
language plpgsql security definer set search_path = public, pg_temp as $$
declare
  v_id bigint;
  v_desp bigint;
begin
  if exists (select 1 from public.sentinela_eventos
              where chave_dedup = p_chave and criado_em > now() - make_interval(mins => greatest(p_janela_min, 1))) then
    return null;
  end if;

  insert into public.sentinela_eventos (tipo, gravidade, chave_dedup, titulo, dados)
  values (p_tipo, p_gravidade, p_chave, p_titulo, coalesce(p_dados, '{}'::jsonb))
  returning id into v_id;

  if p_gravidade = 'urgente' then
    begin
      -- origem 'evento': a origem 'sentinela' não existe na regra da tabela despacho (origens permitidas: danilo-telegram, claude-ai, relogio, evento, agente).
      insert into public.despacho (origem, para, tipo, prioridade, titulo, tarefa)
      values ('evento', 'emerson', 'tarefa', 90, p_titulo,
              'Evento urgente do vigia (evento ' || v_id || '). Vê os dados, trata do que podes e avisa o Danilo se for preciso. Dados: ' || coalesce(p_dados, '{}'::jsonb)::text)
      returning id into v_desp;
      update public.sentinela_eventos set despacho_id = v_desp where id = v_id;
    exception when others then
      null;  -- um despacho que falha nunca pode apagar o evento
    end;
  end if;
  return v_id;
end $$;

-- ───────────────────────── 5. Detetores (cada um devolve quantos eventos novos criou) ─────────────────────────

-- Pedidos parados. Só pedidos recentes (12 h) e reais; pedido agendado para o futuro é ignorado.
create or replace function public._sentinela_det_pedidos()
returns integer language plpgsql security definer set search_path = public, pg_temp as $$
declare
  r record; n integer := 0;
  v_loja numeric := public._sentinela_num('sentinela_min_loja_por_aceitar', 8);
  v_pronto numeric := public._sentinela_num('sentinela_min_pronto_sem_estafeta', 5);
  v_cam numeric := public._sentinela_num('sentinela_min_a_caminho', 45);
begin
  -- (a) a loja não aceita
  for r in
    select o.id, o.order_type, o.restaurant_id,
           floor(extract(epoch from now() - greatest(o.created_at, coalesce(o.scheduled_for, o.created_at))) / 60)::int as min
      from public.orders o
     where o.status = 'created' and o.accepted_at is null
       and o.order_type in ('partnerRestaurant', 'takeaway')
       and coalesce(o.is_test_order, false) = false
       and (o.scheduled_for is null or o.scheduled_for <= now())
       and o.created_at > now() - interval '12 hours'
       and greatest(o.created_at, coalesce(o.scheduled_for, o.created_at)) < now() - make_interval(mins => v_loja::int)
  loop
    if public.sentinela_registar('pedido_parado', 'urgente', 'pedido:' || r.id || ':loja',
         'Pedido parado: a loja ainda não aceitou (' || r.min || ' min)',
         jsonb_build_object('order_id', r.id, 'regra', 'loja_por_aceitar', 'minutos', r.min, 'order_type', r.order_type, 'restaurant_id', r.restaurant_id), 240) is not null
    then n := n + 1; end if;
  end loop;

  -- (b) pronto e sem estafeta
  for r in
    select o.id, o.order_type, o.restaurant_id,
           floor(extract(epoch from now() - coalesce(o.dispatch_calling_since, o.status_updated_at)) / 60)::int as min
      from public.orders o
     where o.status = 'callingDriver' and o.assigned_driver_id is null
       and coalesce(o.is_test_order, false) = false
       and (o.scheduled_for is null or o.scheduled_for <= now())
       and o.created_at > now() - interval '12 hours'
       and coalesce(o.dispatch_calling_since, o.status_updated_at) < now() - make_interval(mins => v_pronto::int)
  loop
    if public.sentinela_registar('pedido_parado', 'urgente', 'pedido:' || r.id || ':sem_estafeta',
         'Pedido parado: pronto e sem estafeta (' || r.min || ' min)',
         jsonb_build_object('order_id', r.id, 'regra', 'pronto_sem_estafeta', 'minutos', r.min, 'order_type', r.order_type, 'restaurant_id', r.restaurant_id), 240) is not null
    then n := n + 1; end if;
  end loop;

  -- (c) a caminho há demasiado tempo
  for r in
    select o.id, o.order_type, o.restaurant_id,
           floor(extract(epoch from now() - o.status_updated_at) / 60)::int as min
      from public.orders o
     where o.status in ('pickedUp', 'onTheWay')
       and coalesce(o.is_test_order, false) = false
       and o.created_at > now() - interval '12 hours'
       and o.status_updated_at < now() - make_interval(mins => v_cam::int)
  loop
    if public.sentinela_registar('pedido_parado', 'urgente', 'pedido:' || r.id || ':a_caminho',
         'Pedido parado: a caminho há ' || r.min || ' min',
         jsonb_build_object('order_id', r.id, 'regra', 'a_caminho', 'minutos', r.min, 'order_type', r.order_type, 'restaurant_id', r.restaurant_id), 240) is not null
    then n := n + 1; end if;
  end loop;
  return n;
end $$;

-- Corridas TVDE, limpezas, lavagens, marcações, reservas e encomendas por telefone à espera de alguém.
create or replace function public._sentinela_det_servicos()
returns integer language plpgsql security definer set search_path = public, pg_temp as $$
declare r record; n integer := 0;
begin
  -- TVDE
  for r in
    select t.id, t.status, floor(extract(epoch from now() - coalesce(t.no_driver_since, t.created_at)) / 60)::int as min
      from public.tvde_rides t
     where t.status in ('solicitada', 'sem_motorista')
       and t.created_at > now() - interval '12 hours'
       and coalesce(t.no_driver_since, t.created_at) < now() - make_interval(mins => public._sentinela_num('sentinela_min_tvde_sem_motorista', 5)::int)
  loop
    if public.sentinela_registar('pedido_parado', 'urgente', 'tvde:' || r.id || ':sem_motorista',
         'Corrida TVDE sem motorista há ' || r.min || ' min',
         jsonb_build_object('ride_id', r.id, 'regra', 'tvde_sem_motorista', 'estado', r.status, 'minutos', r.min), 240) is not null
    then n := n + 1; end if;
  end loop;

  -- Limpeza sem profissional
  for r in
    select b.id, floor(extract(epoch from now() - b.created_at) / 60)::int as min
      from public.cleaning_bookings b
     where b.status = 'scheduled' and b.cleaner_id is null
       and coalesce(b.is_test_order, false) = false
       and b.created_at > now() - interval '12 hours'
       and b.created_at < now() - make_interval(mins => public._sentinela_num('sentinela_min_limpeza_espera', 30)::int)
  loop
    if public.sentinela_registar('pedido_parado', 'urgente', 'limpeza:' || r.id || ':sem_profissional',
         'Limpeza sem profissional há ' || r.min || ' min',
         jsonb_build_object('booking_id', r.id, 'regra', 'limpeza_sem_profissional', 'minutos', r.min), 240) is not null
    then n := n + 1; end if;
  end loop;

  -- Lavagem sem lavador
  for r in
    select b.id, floor(extract(epoch from now() - b.created_at) / 60)::int as min
      from public.carwash_bookings b
     where b.status = 'scheduled' and b.washer_id is null
       and coalesce(b.is_test_order, false) = false
       and b.created_at > now() - interval '12 hours'
       and b.created_at < now() - make_interval(mins => public._sentinela_num('sentinela_min_lavagem_espera', 30)::int)
  loop
    if public.sentinela_registar('pedido_parado', 'urgente', 'lavagem:' || r.id || ':sem_lavador',
         'Lavagem sem lavador há ' || r.min || ' min',
         jsonb_build_object('booking_id', r.id, 'regra', 'lavagem_sem_lavador', 'minutos', r.min), 240) is not null
    then n := n + 1; end if;
  end loop;

  -- Marcação à espera de o parceiro confirmar se foi feita
  for r in
    select a.id, floor(extract(epoch from now() - a.awaiting_since) / 60)::int as min
      from public.appointments a
     where a.status = 'awaiting_confirmation' and coalesce(a.is_test, false) = false
       and a.awaiting_since > now() - interval '3 days'
       and a.awaiting_since < now() - make_interval(mins => public._sentinela_num('sentinela_min_marcacao_espera', 120)::int)
  loop
    if public.sentinela_registar('pedido_parado', 'normal', 'marcacao:' || r.id || ':por_confirmar',
         'Marcação à espera de confirmação do parceiro há ' || r.min || ' min',
         jsonb_build_object('appointment_id', r.id, 'regra', 'marcacao_por_confirmar', 'minutos', r.min), 1440) is not null
    then n := n + 1; end if;
  end loop;

  -- Reserva de mesa sem resposta do restaurante
  for r in
    select v.id, floor(extract(epoch from now() - v.created_at) / 60)::int as min
      from public.reservations v
     where v.status = 'pending' and v.reserved_for > now()
       and v.created_at > now() - interval '2 days'
       and v.created_at < now() - make_interval(mins => public._sentinela_num('sentinela_min_reserva_espera', 30)::int)
  loop
    if public.sentinela_registar('pedido_parado', 'urgente', 'reserva:' || r.id || ':sem_resposta',
         'Reserva de mesa sem resposta do restaurante há ' || r.min || ' min',
         jsonb_build_object('reservation_id', r.id, 'regra', 'reserva_sem_resposta', 'minutos', r.min), 240) is not null
    then n := n + 1; end if;
  end loop;

  -- Encomenda por telefone parada (nem libertada nem cancelada)
  for r in
    select e.order_id, floor(extract(epoch from now() - e.criado_em) / 60)::int as min
      from public.encomendas_telefone e
     where e.libertado_em is null and e.cancelado_em is null
       and e.criado_em > now() - interval '1 day'
       and e.criado_em < now() - make_interval(mins => public._sentinela_num('sentinela_min_encomenda_telefone', 30)::int)
  loop
    if public.sentinela_registar('pedido_parado', 'urgente', 'encomenda_tel:' || r.order_id || ':parada',
         'Encomenda por telefone parada há ' || r.min || ' min',
         jsonb_build_object('order_id', r.order_id, 'regra', 'encomenda_telefone_parada', 'minutos', r.min), 240) is not null
    then n := n + 1; end if;
  end loop;
  return n;
end $$;

-- Pagamento estranho: só transforma achados novos dos vigias que já existem. Não recalcula nada.
create or replace function public._sentinela_det_pagamentos()
returns integer language plpgsql security definer set search_path = public, pg_temp as $$
declare r record; n integer := 0;
begin
  for r in select d.draft_id from public.payment_drafts_alertados d where d.alertado_em > now() - interval '10 minutes'
  loop
    if public.sentinela_registar('pagamento_estranho', 'urgente', 'pagamento:rascunho:' || r.draft_id,
         'Pagamento estranho: rascunho de pagamento alertado',
         jsonb_build_object('draft_id', r.draft_id, 'origem', 'payment_drafts_alertados'), 240) is not null
    then n := n + 1; end if;
  end loop;

  for r in
    select f.id, f.kind, f.severity, f.entity_type, f.entity_id
      from public.payment_reconciliation_findings f
     where f.resolved_at is null and f.run_at > now() - interval '10 minutes'
  loop
    if public.sentinela_registar('pagamento_estranho', 'urgente', 'pagamento:achado:' || r.id,
         'Pagamento estranho: achado da reconciliação (' || coalesce(r.kind, 'sem tipo') || ')',
         jsonb_build_object('finding_id', r.id, 'kind', r.kind, 'severity', r.severity, 'entity_type', r.entity_type, 'entity_id', r.entity_id,
                            'origem', 'payment_reconciliation_findings'), 240) is not null
    then n := n + 1; end if;
  end loop;
  return n;
end $$;

-- Erros que se repetem: a mesma assinatura N ou mais vezes em 30 min (tarefa agendada falhada: basta 1).
create or replace function public._sentinela_det_erros()
returns integer language plpgsql security definer set search_path = public, pg_temp as $$
declare
  r record; n integer := 0;
  v_n integer := greatest(public._sentinela_num('sentinela_erros_repetidos_n', 3)::int, 1);
  v_max bigint;
  v_seg integer;
begin
  for r in
    select e.component as fonte, public._sentinela_limpa(e.error_message) as amostra, count(*) as c
      from public.order_lifecycle_errors e where e.occurred_at > now() - interval '30 minutes'
     group by 1, 2 having count(*) >= v_n
  loop
    if public.sentinela_registar('erro_repetido', 'normal', 'erro:ciclo:' || md5(coalesce(r.fonte, '') || r.amostra),
         'Erro repetido no ciclo do pedido (' || coalesce(r.fonte, '?') || ', ' || r.c || ' vezes em 30 min)',
         jsonb_build_object('origem', 'order_lifecycle_errors', 'componente', r.fonte, 'amostra', r.amostra, 'vezes', r.c)) is not null
    then n := n + 1; end if;
  end loop;

  for r in
    select e.screen as fonte, public._sentinela_limpa(e.error_message) as amostra, count(*) as c
      from public.debug_crash_logs e where e.created_at > now() - interval '30 minutes'
     group by 1, 2 having count(*) >= v_n
  loop
    if public.sentinela_registar('erro_repetido', 'normal', 'erro:crash:' || md5(coalesce(r.fonte, '') || r.amostra),
         'Falha repetida nas apps (' || coalesce(r.fonte, '?') || ', ' || r.c || ' vezes em 30 min)',
         jsonb_build_object('origem', 'debug_crash_logs', 'ecra', r.fonte, 'amostra', r.amostra, 'vezes', r.c)) is not null
    then n := n + 1; end if;
  end loop;

  for r in
    select e.robo as fonte, public._sentinela_limpa(e.erro) as amostra, count(*) as c
      from public.ia_gastos e where e.ok = false and e.quando > now() - interval '30 minutes'
     group by 1, 2 having count(*) >= v_n
  loop
    if public.sentinela_registar('erro_repetido', 'normal', 'erro:ia:' || md5(coalesce(r.fonte, '') || r.amostra),
         'Pedidos à IA a falhar (' || coalesce(r.fonte, '?') || ', ' || r.c || ' vezes em 30 min)',
         jsonb_build_object('origem', 'ia_gastos', 'robo', r.fonte, 'amostra', r.amostra, 'vezes', r.c)) is not null
    then n := n + 1; end if;
  end loop;

  for r in
    select public._sentinela_limpa(e.error) as amostra, count(*) as c
      from public.robot_runs e where e.status = 'error' and e.started_at > now() - interval '30 minutes'
     group by 1 having count(*) >= v_n
  loop
    if public.sentinela_registar('erro_repetido', 'normal', 'erro:robot:' || md5(r.amostra),
         'Robô do painel a falhar (' || r.c || ' vezes em 30 min)',
         jsonb_build_object('origem', 'robot_runs', 'amostra', r.amostra, 'vezes', r.c)) is not null
    then n := n + 1; end if;
  end loop;

  for r in
    select public._sentinela_limpa(e.motivo) as amostra, count(*) as c
      from public.vigia_servidor_registos e where e.alertou and e.criado_em > now() - interval '30 minutes'
     group by 1 having count(*) >= v_n
  loop
    if public.sentinela_registar('erro_repetido', 'normal', 'erro:servidor:' || md5(r.amostra),
         'O vigia do servidor alertou ' || r.c || ' vezes em 30 min',
         jsonb_build_object('origem', 'vigia_servidor_registos', 'amostra', r.amostra, 'vezes', r.c)) is not null
    then n := n + 1; end if;
  end loop;

  -- Tarefas agendadas (pg_cron): 1 falha basta; 3 seguidas = urgente. Só olha às últimas execuções (a tabela é grande).
  select max(runid) into v_max from cron.job_run_details;
  for r in
    select j.jobid, j.jobname, count(*) as c,
           (select count(*) filter (where x.status = 'failed')
              from (select d2.status from cron.job_run_details d2
                     where d2.jobid = j.jobid and d2.runid > coalesce(v_max, 0) - 6000
                     order by d2.runid desc limit 3) x) as ultimas_falhadas
      from cron.job_run_details d join cron.job j on j.jobid = d.jobid
     where d.status = 'failed' and d.runid > coalesce(v_max, 0) - 6000 and d.start_time > now() - interval '30 minutes'
     group by j.jobid, j.jobname
  loop
    if public.sentinela_registar('erro_repetido', case when r.ultimas_falhadas >= 3 then 'urgente' else 'normal' end,
         'erro:cron:' || r.jobid,
         'Tarefa agendada a falhar: ' || coalesce(r.jobname, r.jobid::text) || ' (' || r.c || ' falhas em 30 min)',
         jsonb_build_object('origem', 'cron.job_run_details', 'jobid', r.jobid, 'job', r.jobname, 'falhas_30min', r.c, 'ultimas_3_falhadas', r.ultimas_falhadas)) is not null
    then n := n + 1; end if;
  end loop;
  return n;
end $$;

-- Registo único de um robô em apuros. Nunca leva texto da conversa, telefone, email nem nome: só o tipo e uma referência.
create or replace function public._sentinela_robo_evento(p_robo text, p_ref text, p_motivo text, p_min integer)
returns boolean language plpgsql security definer set search_path = public, pg_temp as $$
declare v_grav text; v_tit text;
begin
  v_grav := case when p_motivo in ('pede_humano', 'passagem_pendente') then 'urgente' else 'normal' end;
  v_tit := case p_motivo
    when 'pede_humano' then 'Cliente pede uma pessoa ou reclama (' || p_robo || ')'
    when 'passagem_pendente' then 'Passagem a humano pendente há ' || p_min || ' min (' || p_robo || ')'
    when 'sem_resposta' then 'Pergunta sem resposta há ' || p_min || ' min (' || p_robo || ')'
    else 'Conversa com nota baixa (' || p_robo || ')' end;
  return public.sentinela_registar('robo_em_apuros', v_grav, 'robo:' || p_robo || ':' || p_ref || ':' || p_motivo, v_tit,
           jsonb_build_object('robo', p_robo, 'ref', p_ref, 'motivo', p_motivo, 'minutos', p_min), case when p_motivo = 'nota_baixa' then 1440 else 240 end) is not null;
end $$;

create or replace function public._sentinela_det_robos()
returns integer language plpgsql security definer set search_path = public, pg_temp as $$
declare
  r record; n integer := 0;
  v_min integer := public._sentinela_num('sentinela_min_conversa_sem_resposta', 10)::int;
  v_re constant text := '(humano|atendente|reclama|queixa|n[aã]o resolve|falar com (uma |um )?(pessoa|algu[eé]m)|quero (uma )?pessoa)';
begin
  -- Suporte (chatbot do suporte)
  for r in
    select s.id, s.escalated_pending, s.ultima_msg_em,
           u.created_at as u_em, coalesce(u.content ~* v_re, false) as pede,
           l.role as l_role, l.created_at as l_em
      from public.support_chatbot_sessions s
      left join lateral (select m.content, m.created_at from public.support_chatbot_messages m
                          where m.session_id = s.id and m.role = 'user' order by m.created_at desc limit 1) u on true
      left join lateral (select m.role, m.created_at from public.support_chatbot_messages m
                          where m.session_id = s.id order by m.created_at desc limit 1) l on true
     where s.ultima_msg_em > now() - interval '6 hours' and s.admin_assumiu_em is null
  loop
    if r.pede and r.u_em > now() - interval '2 hours' then
      if public._sentinela_robo_evento('suporte', r.id::text, 'pede_humano', 0) then n := n + 1; end if;
    end if;
    if coalesce(r.escalated_pending, false) and r.ultima_msg_em < now() - make_interval(mins => v_min) then
      if public._sentinela_robo_evento('suporte', r.id::text, 'passagem_pendente', floor(extract(epoch from now() - r.ultima_msg_em) / 60)::int) then n := n + 1; end if;
    elsif r.l_role = 'user' and r.l_em < now() - make_interval(mins => v_min) then
      if public._sentinela_robo_evento('suporte', r.id::text, 'sem_resposta', floor(extract(epoch from now() - r.l_em) / 60)::int) then n := n + 1; end if;
    end if;
  end loop;

  -- Nota baixa nos tickets de suporte
  for r in
    select t.id from public.support_tickets t
     where t.satisfaction <= 2 and coalesce(t.updated_at, t.created_at) > now() - interval '1 hour'
  loop
    if public._sentinela_robo_evento('suporte', 'ticket-' || r.id::text, 'nota_baixa', 0) then n := n + 1; end if;
  end loop;

  -- Amigo Bora
  for r in
    select c.id, c.status, c.last_message_at,
           u.created_at as u_em, coalesce(u.content ~* v_re, false) as pede,
           l.role as l_role, l.created_at as l_em
      from public.assistant_conversations c
      left join lateral (select m.content, m.created_at from public.assistant_chat_messages m
                          where m.conversation_id = c.id and m.role = 'user' order by m.created_at desc limit 1) u on true
      left join lateral (select m.role, m.created_at from public.assistant_chat_messages m
                          where m.conversation_id = c.id order by m.created_at desc limit 1) l on true
     where c.last_message_at > now() - interval '6 hours' and c.equipa_assumiu_por is null
  loop
    if r.pede and r.u_em > now() - interval '2 hours' then
      if public._sentinela_robo_evento('amigo', r.id::text, 'pede_humano', 0) then n := n + 1; end if;
    end if;
    if r.status = 'handoff' and r.last_message_at < now() - make_interval(mins => v_min) then
      if public._sentinela_robo_evento('amigo', r.id::text, 'passagem_pendente', floor(extract(epoch from now() - r.last_message_at) / 60)::int) then n := n + 1; end if;
    elsif r.status = 'open' and r.l_role = 'user' and r.l_em < now() - make_interval(mins => v_min) then
      if public._sentinela_robo_evento('amigo', r.id::text, 'sem_resposta', floor(extract(epoch from now() - r.l_em) / 60)::int) then n := n + 1; end if;
    end if;
  end loop;

  -- WhatsApp da loja (a referência é um resumo do número, nunca o número)
  for r in
    select 'wa-' || left(md5(c.numero), 10) as ref,
           coalesce(e.texto, e.transcricao, '') ~* v_re as pede, e.created_at as e_em,
           l.direcao as l_dir, l.created_at as l_em
      from public.whatsapp_contacts c
      left join lateral (select m.texto, m.transcricao, m.created_at from public.whatsapp_messages m
                          where m.numero = c.numero and m.direcao = 'entrada' order by m.created_at desc limit 1) e on true
      left join lateral (select m.direcao, m.created_at from public.whatsapp_messages m
                          where m.numero = c.numero order by m.created_at desc limit 1) l on true
     where c.ultima_msg_em > now() - interval '6 hours'
       and not coalesce(c.bot_pausado, false) and not coalesce(c.assumido_por_danilo, false)
  loop
    if r.pede and r.e_em > now() - interval '2 hours' then
      if public._sentinela_robo_evento('whatsapp', r.ref, 'pede_humano', 0) then n := n + 1; end if;
    end if;
    if r.l_dir = 'entrada' and r.l_em < now() - make_interval(mins => v_min) then
      if public._sentinela_robo_evento('whatsapp', r.ref, 'sem_resposta', floor(extract(epoch from now() - r.l_em) / 60)::int) then n := n + 1; end if;
    end if;
  end loop;
  return n;
end $$;

-- Carrinhos abandonados: só conta. Um evento 'info' por dia (data de Lisboa). Não contacta clientes.
create or replace function public._sentinela_det_carrinhos()
returns integer language plpgsql security definer set search_path = public, pg_temp as $$
declare
  v_hoje date := (now() at time zone 'Europe/Lisbon')::date;
  v_hora integer := extract(hour from (now() at time zone 'Europe/Lisbon'))::int;
  v_ab integer; v_conv integer;
begin
  if v_hora < public._sentinela_num('sentinela_carrinho_hora', 21)::int then return 0; end if;
  select count(*) filter (where c.convertido_em is null and coalesce(c.n_itens, 0) > 0),
         count(*) filter (where c.convertido_em is not null)
    into v_ab, v_conv
    from public.carrinhos_abandonados c
   where (c.atualizado_em at time zone 'Europe/Lisbon')::date = v_hoje
     and c.atualizado_em > now() - interval '30 hours';
  if public.sentinela_registar('carrinho_abandonado', 'info', 'carrinho:' || v_hoje::text,
       'Carrinhos de hoje: ' || v_ab || ' abandonados, ' || v_conv || ' concluídos',
       jsonb_build_object('dia', v_hoje, 'abandonados', v_ab, 'convertidos', v_conv), 1200) is not null
  then return 1; end if;
  return 0;
end $$;

-- ───────────────────────── 6. A varredura ─────────────────────────
create or replace function public.sentinela_varrer()
returns jsonb
language plpgsql security definer set search_path = public, pg_temp set statement_timeout = '25s' as $$
declare
  v_ini timestamptz := clock_timestamp();
  v_ligada boolean;
  v_nome text; v_n integer; v_total integer := 0; v_erros integer := 0; v_msg text := null;
  v_res jsonb := '{}'::jsonb;
begin
  if not pg_try_advisory_xact_lock(hashtext('sentinela_varrer')) then
    return jsonb_build_object('ocupada', true);
  end if;

  select coalesce((value #>> '{}')::boolean, true) into v_ligada from public.platform_settings where key = 'sentinela_ligada';
  v_ligada := coalesce(v_ligada, true);
  if not v_ligada then
    update public.sentinela_estado set ultima_varredura = now(), duracao_ms = 0, eventos_novos = 0, detetores_com_erro = 0, ligada = false where id = 1;
    return jsonb_build_object('ligada', false);
  end if;

  foreach v_nome in array array['pedidos', 'servicos', 'pagamentos', 'erros', 'robos', 'carrinhos'] loop
    begin
      execute format('select public.%I()', '_sentinela_det_' || v_nome) into v_n;
      v_res := v_res || jsonb_build_object(v_nome, coalesce(v_n, 0));
      v_total := v_total + coalesce(v_n, 0);
    exception when others or query_canceled then
      v_erros := v_erros + 1;
      v_msg := coalesce(v_msg || ' | ', '') || v_nome || ': ' || left(sqlerrm, 200);
      v_res := v_res || jsonb_build_object(v_nome, 'erro');
    end;
  end loop;

  update public.sentinela_estado
     set ultima_varredura = now(),
         duracao_ms = (extract(epoch from clock_timestamp() - v_ini) * 1000)::int,
         eventos_novos = v_total,
         detetores_com_erro = v_erros,
         ultimo_erro = coalesce(v_msg, ultimo_erro),
         ultimo_erro_em = case when v_msg is not null then now() else ultimo_erro_em end,
         ligada = true
   where id = 1;
  return jsonb_build_object('ligada', true, 'eventos_novos', v_total, 'detetores_com_erro', v_erros, 'por_detetor', v_res);
end $$;

-- ───────────────────────── 7. Permissões: só o serviço corre isto ─────────────────────────
do $$
declare f text;
begin
  foreach f in array array[
    'public._sentinela_num(text, numeric)',
    'public._sentinela_limpa(text)',
    'public.sentinela_registar(text, text, text, text, jsonb, integer)',
    'public._sentinela_det_pedidos()',
    'public._sentinela_det_servicos()',
    'public._sentinela_det_pagamentos()',
    'public._sentinela_det_erros()',
    'public._sentinela_robo_evento(text, text, text, integer)',
    'public._sentinela_det_robos()',
    'public._sentinela_det_carrinhos()',
    'public.sentinela_varrer()'
  ] loop
    execute 'revoke execute on function ' || f || ' from public, anon, authenticated';
    execute 'grant execute on function ' || f || ' to service_role';
  end loop;
end $$;

-- ───────────────────────── 8. Agendar de minuto a minuto ─────────────────────────
do $$
begin
  begin
    perform cron.unschedule('sentinela-varrer');
  exception when others then
    null;  -- ainda não existia
  end;
  perform cron.schedule('sentinela-varrer', '* * * * *', $cmd$select public.sentinela_varrer();$cmd$);
end $$;
