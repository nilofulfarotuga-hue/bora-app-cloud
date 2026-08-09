-- ============================================================================
-- F2 — cortex_tasks: fila de tarefas do Cortex multiagente (PROPOSTA, nao aplicada)
-- ----------------------------------------------------------------------------
-- Tabela-mae da fila de tarefas. Nascem aqui as tarefas que o cortex-mcp
-- despacha e que um worker reclama/executa. Zona: META (nao e dinheiro).
--
-- PADRAO ESPELHADO de 20260716190000_cortex_red_proposals.sql:
--   - RLS enabled, SEM policies -> so service_role (bypass) e admin via RPC
--     SECURITY DEFINER (pre-flight SS6 / RED_MODEL SS6: "service_role full +
--     admin via is_admin(); nunca anon/authenticated leitura direta").
--   - RPCs SECURITY DEFINER, `set search_path to 'public','pg_temp'`.
--   - Admin RPCs guardam com `perform public._admin_op_guard()`.
--   - Auditoria via `public.log_admin_action(...)`.
--
-- COLUNAS derivadas de decisoes JA registadas (nao ha arquitetura nova):
--   - server.mjs order frontmatter (cortex_aprovar_proposta / t_nova_ordem):
--     pid_original, tarefa, autor, tentativa, teto_tentativas, zona.
--   - pre-flight-multiagent.md SS6: authority_level ('normal'|'critical').
--   - pre-flight-multiagent.md SS7: requires_consensus (F5 meta-vira-tabela
--     depois; coluna harmless ja fica, default false).
--   - runtime minimo (F2 = worker unico, sem paralelismo ate F6):
--     status, payload, assigned_agent, assigned_at, resultado, erro, custo,
--     modelo, finished_at.
--
-- APLICACAO: PROPOSTA. Sem MCP Supabase nesta sessao. Aguarda "vai" do Danilo;
-- depois aplicada por sessao com MCP (apply_migration). Idempotente
-- (create table/function if not exists) para re-corre segura.
--
-- TRAVA: cortex_tasks foi adicionada ao FINTABLE do protege-banco.sh em F1.4
-- (operacoes destrutivas sobre ela -- remover tabela, esvaziar, desativar RLS
-- -- bloqueadas em contexto SQL). O DOWN abaixo e
-- documental -- uma reversao real e operacao manual do Danilo (o agente
-- nao pode destruir a propria fila, por design).
-- ============================================================================

create table if not exists public.cortex_tasks (
  id                uuid        primary key default gen_random_uuid(),
  pid_original      text,                                    -- link ao pid do cortex-mcp (prop-...)
  zona              text        not null default 'verde'     check (zona in ('verde','amarela','vermelha')),
  authority_level   text        not null default 'normal'    check (authority_level in ('normal','critical')),
  status            text        not null default 'queued'    check (status in ('queued','running','done','failed','archived')),
  priority          int         not null default 0,
  tarefa            text        not null,                     -- descricao da tarefa (espelha 'tarefa' da ordem)
  payload           jsonb,                                    -- dados estruturados para o executor
  autor             text,                                     -- quem/o que criou a tarefa
  requires_consensus boolean    not null default false,       -- pre-flight SS7 (F5): precisara de consenso
  tentativa         int         not null default 0,            -- espelha 'tentativa' da ordem
  teto_tentativas   int         not null default 5,            -- espelha 'teto_tentativas' da ordem
  assigned_agent    text,                                     -- worker que reclamou (F6: worktree)
  assigned_at       timestamptz,
  resultado         jsonb,
  erro              text,
  custo             numeric(12,4),                           -- custo da chamada (pre-flight SS8 budget)
  modelo            text,                                     -- modelo que correu (F3 router)
  created_at        timestamptz not null default now(),        -- espelha 'criada'
  updated_at        timestamptz not null default now(),
  finished_at       timestamptz
);

create index if not exists idx_cortex_tasks_status_queued
  on public.cortex_tasks (priority desc, created_at)
  where status = 'queued';

create index if not exists idx_cortex_tasks_created_at on public.cortex_tasks (created_at);
create index if not exists idx_cortex_tasks_pid         on public.cortex_tasks (pid_original);

alter table public.cortex_tasks enable row level security;
-- SEM policies (acesso so via RPCs SECURITY DEFINER abaixo; service_role bypassa RLS).

-- ----------------------------------------------------------------------------
-- RPC 1: cortex_enqueue — insere tarefa 'queued'. Chamada pelo cortex-mcp /
-- carteiro (service role / anon key no VPS, mesmo modelo do
-- cortex_proposal_sync_upsert). Tarefa vermelha NUNCA nasce aqui por execucao
-- direta — o cortex-mcp ja barra RED_ORDER na porta; vermelhas viram proposta.
-- ----------------------------------------------------------------------------
create or replace function public.cortex_enqueue(
  p_tarefa            text,
  p_zona              text    default 'verde',
  p_authority_level   text    default 'normal',
  p_autor             text    default null,
  p_pid_original      text    default null,
  p_payload           jsonb   default null,
  p_priority          int     default 0,
  p_teto_tentativas   int     default 5,
  p_requires_consensus boolean default false
)
returns uuid
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $$
declare
  v_id uuid;
begin
  if p_tarefa is null or length(trim(p_tarefa)) = 0 then
    raise exception 'tarefa_vazia';
  end if;
  if p_zona not in ('verde','amarela','vermelha') then
    raise exception 'zona_invalida: %', p_zona;
  end if;
  if p_authority_level not in ('normal','critical') then
    raise exception 'authority_level_invalida: %', p_authority_level;
  end if;

  insert into public.cortex_tasks
    (pid_original, zona, authority_level, status, priority, tarefa, payload,
     autor, requires_consensus, teto_tentativas, created_at, updated_at)
  values
    (left(p_pid_original, 200), p_zona, p_authority_level, 'queued',
     greatest(p_priority, 0), left(p_tarefa, 8000), p_payload,
     left(p_autor, 100), p_requires_consensus,
     greatest(p_teto_tentativas, 1), now(), now())
  returning id into v_id;

  return v_id;
end;
$$;

grant execute on function public.cortex_enqueue(text,text,text,text,text,jsonb,int,int,boolean) to anon;

-- ----------------------------------------------------------------------------
-- RPC 2: cortex_claim_next — reclamacao atomica (FOR UPDATE SKIP LOCKED) da
-- proxima tarefa 'queued' (priority desc, created_at asc). F2 = worker unico;
-- o SKIP LOCKED prepara para paralelismo futuro (F6) sem mudar a semantica.
-- Marca 'running', assigned_agent, assigned_at, tentativa++.
-- ----------------------------------------------------------------------------
create or replace function public.cortex_claim_next(p_agent text)
returns setof public.cortex_tasks
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $$
declare
  v_row record;
begin
  if p_agent is null or length(trim(p_agent)) = 0 then
    raise exception 'agent_vazio';
  end if;

  for v_row in
    select * from public.cortex_tasks
     where status = 'queued'
     order by priority desc, created_at
     for update of public.cortex_tasks skip locked
     limit 1
  loop
    update public.cortex_tasks
       set status         = 'running',
           assigned_agent = left(p_agent, 100),
           assigned_at    = now(),
           tentativa      = tentativa + 1,
           updated_at     = now()
     where id = v_row.id
     returning * into v_row;
    return next v_row;
    return;
  end loop;
  -- fila vazia: devolve 0 linhas
end;
$$;

grant execute on function public.cortex_claim_next(text) to anon;

-- ----------------------------------------------------------------------------
-- RPC 3: cortex_finish — termina a tarefa (done/failed). Define resultado,
-- erro, custo, modelo, finished_at. Nao reabre tarefa (arquivar e separado).
-- ----------------------------------------------------------------------------
create or replace function public.cortex_finish(
  p_task_id    uuid,
  p_ok         boolean,
  p_resultado  jsonb  default null,
  p_erro       text   default null,
  p_custo      numeric default null,
  p_modelo     text   default null
)
returns void
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $$
begin
  if p_task_id is null then
    raise exception 'task_id_nulo';
  end if;

  update public.cortex_tasks
     set status      = case when p_ok then 'done' else 'failed' end,
         resultado   = p_resultado,
         erro        = left(p_erro, 8000),
         custo       = p_custo,
         modelo      = left(p_modelo, 100),
         finished_at = now(),
         updated_at  = now()
   where id = p_task_id and status = 'running';

  if not found then
    raise exception 'task_nao_encontrada_ou_nao_running: %', p_task_id;
  end if;
end;
$$;

grant execute on function public.cortex_finish(uuid,boolean,jsonb,text,numeric,text) to anon;

-- ----------------------------------------------------------------------------
-- RPC 4: cortex_archive (admin) — arquiva sem destruir. Guarda _admin_op_guard.
-- ----------------------------------------------------------------------------
create or replace function public.cortex_archive(p_task_id uuid, p_motivo text default null)
returns void
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $$
begin
  perform public._admin_op_guard();

  update public.cortex_tasks
     set status     = 'archived',
         updated_at = now()
   where id = p_task_id;

  if not found then
    raise exception 'task_nao_encontrada: %', p_task_id;
  end if;

  perform public.log_admin_action(
    'cortex_archive',
    'cortex_tasks',
    p_task_id,
    jsonb_build_object('motivo', left(trim(coalesce(p_motivo, '')), 500))
  );
end;
$$;

grant execute on function public.cortex_archive(uuid,text) to authenticated;

-- ----------------------------------------------------------------------------
-- RPC 5: cortex_list_tasks (admin) — leitura paginada por status.
-- ----------------------------------------------------------------------------
create or replace function public.cortex_list_tasks(
  p_status text default null,
  p_limit  int  default 100,
  p_offset int  default 0
)
returns jsonb
language plpgsql
stable
security definer
set search_path to 'public', 'pg_temp'
as $$
begin
  perform public._admin_op_guard();
  return coalesce((
    select jsonb_agg(to_jsonb(s) order by s.created_at desc)
      from (
        select id, pid_original, zona, authority_level, status, priority, tarefa,
               autor, requires_consensus, tentativa, teto_tentativas,
               assigned_agent, assigned_at, created_at, updated_at, finished_at
          from public.cortex_tasks
         where (p_status is null or status = p_status)
         order by created_at desc
         limit least(greatest(coalesce(p_limit, 100), 1), 500)
        offset greatest(coalesce(p_offset, 0), 0)
      ) s
  ), '[]'::jsonb);
end;
$$;

grant execute on function public.cortex_list_tasks(text,int,int) to authenticated;

-- ----------------------------------------------------------------------------
-- RPC 6: cortex_queue_stats (admin) — observabilidade (pre-flight SS8).
-- ----------------------------------------------------------------------------
create or replace function public.cortex_queue_stats()
returns jsonb
language plpgsql
stable
security definer
set search_path to 'public', 'pg_temp'
as $$
declare
  v_pending int;
  v_running int;
  v_oldest timestamptz;
  v_oldest_age_min int;
begin
  perform public._admin_op_guard();

  select count(*) into v_pending from public.cortex_tasks where status = 'queued';
  select count(*) into v_running from public.cortex_tasks where status = 'running';
  select min(created_at) into v_oldest from public.cortex_tasks where status = 'queued';
  v_oldest_age_min := coalesce(extract(epoch from (now() - v_oldest))::int / 60, 0);

  return jsonb_build_object(
    'pending_count', v_pending,
    'running_count', v_running,
    'oldest_queued_age_min', v_oldest_age_min
  );
end;
$$;

grant execute on function public.cortex_queue_stats() to authenticated;

-- ----------------------------------------------------------------------------
-- DOWN (documental — reversao MANUAL pelo Danilo; o agente nao pode remover
-- cortex_tasks, protegida pelo FINTABLE do protege-banco.sh desde F1.4).
-- Procedimento de reversao, por ordem inversa, executar como superuser:
--   1) eliminar as 6 funcoes cortex_queue_stats, cortex_list_tasks,
--      cortex_archive, cortex_finish, cortex_claim_next, cortex_enqueue
--      (CASCADE);
--   2) eliminar a tabela public.cortex_tasks (CASCADE).
-- Os comandos SQL nao estao aqui literais para nao accionar o protege-banco.sh
-- (que le o texto cru do query e bloqueia DDL destrutiva sobre FINTABLE, mesmo
-- dentro de comentarios). A reversao e intencionalmente manual.
-- ============================================================================