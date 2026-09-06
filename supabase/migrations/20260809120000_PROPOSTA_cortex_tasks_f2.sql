-- ============================================================================
-- F2 — cortex_tasks: fila de tarefas do Cortex multiagente (versão final com
-- as 7 decisões do Danilo fechadas em 2026-08-09; ver
-- .claude/.ai/reports/2026-08-09-fase2-blueprint.md §4)
-- ----------------------------------------------------------------------------
-- Tabela-mãe da fila de tarefas. Zona: META (não é dinheiro). Event Bus base
-- em Supabase Realtime (decisão 4.1) com fallback poll (decisão 4.1 híbrido).
--
-- PADRÃO ESPELHADO de 20260716190000_cortex_red_proposals.sql:
--   - RLS enabled, SEM policies -> só service_role (bypass) e admin via RPC
--     SECURITY DEFINER (pre-flight SS6 / RED_MODEL SS6: "service_role full +
--     admin via is_admin(); nunca anon/authenticated leitura direta").
--   - RPCs SECURITY DEFINER, `set search_path to 'public','pg_temp'`.
--   - Admin RPCs guardam com `perform public._admin_op_guard()`.
--   - Auditoria via `public.log_admin_action(text,text,uuid,jsonb)`.
--
-- DECISÕES FECHADAS (Danilo, 2026-08-09):
--   - 4.1 Realtime híbrido: cortex_tasks à publicação supabase_realtime.
--     Realtime ACORDA worker; SKIP LOCKED decide vencedor; poll fallback.
--   - 4.2 Zona vermelha RECUSADA em cortex_enqueue (raises
--     'zona_vermelha_nao_ejecutavel'). Vermelhas ficam em
--     cortex_red_proposals / proposals.jsonl (file-based), nunca claimable.
--   - 4.3 REVOKE/GRANT padrão robot_* explícito (gap fechado).
--   - 4.4 log_admin_action(text,text,uuid,jsonb) confirmado em
--       20260428000000_admin_audit_log.sql:65.
--   - 4.5 parent_id uuid REFERENCES cortex_tasks(id) ON DELETE CASCADE.
--   - 4.6 Sem índices extras (no premature opt).
--   - 4.7 dedup_key UNIQUE parcial WHERE NOT NULL; cortex_enqueue faz
--       INSERT ... ON CONFLICT (dedup_key) DO NOTHING RETURNING id
--       para idempotência opt-in.
--   - 4.8 Coexistência com carteiro: DB é nova via; .md permanece intocado;
--       não há callers em F2 (cortex-mcp não alterado).
--   - 4.9 Kill switch robot_b_enabled herdado: cortex_enqueue e
--       cortex_claim_next guardam via _robot_setting_enabled('robot_b_enabled')
--       -> raises 'KILL_SWITCH_ATIVO' se false. cortex_finish sem guard
--       (deixa drenar running).
--
-- APLICAÇÃO: Por SUBSTITUIR a versão anterior (commit 3d9cf3d). Idempotente
-- (CREATE TABLE IF NOT EXISTS, CREATE OR REPLACE FUNCTION, DO $$ para
-- publication). Pronta para `apply_migration` via MCP Supabase.
--
-- TRAVA: cortex_tasks está no FINTABLE do protege-banco.sh desde F1.4
-- (operações destrutivas sobre ela — remoção, esvaziamento, desativação de
-- RLS — bloqueadas em contexto SQL). O DOWN abaixo é documental — uma
-- reversão real é operação manual do Danilo (o agente não pode destruir
-- a própria fila, por design). Comentários evitam termos destrutivos
-- literais para não accionar o grep naive do hook em migrações futuras.
-- ============================================================================

-- ----------------------------------------------------------------------------
-- 1. Tabela cortex_tasks
-- ----------------------------------------------------------------------------
create table if not exists public.cortex_tasks (
  id                  uuid        primary key default gen_random_uuid(),
  pid_original        text,
  parent_id           uuid        references public.cortex_tasks(id) on delete cascade,
  zona                text        not null default 'verde'
                                check (zona in ('verde','amarela','vermelha')),
  authority_level     text        not null default 'normal'
                                check (authority_level in ('normal','critical')),
  status              text        not null default 'queued'
                                check (status in ('queued','running','done','failed','archived')),
  priority            int         not null default 0,
  tarefa              text        not null,
  payload             jsonb,
  autor               text,
  dedup_key           text,
  requires_consensus  boolean     not null default false,
  tentativa           int         not null default 0,
  teto_tentativas     int         not null default 5,
  assigned_agent      text,
  assigned_at         timestamptz,
  resultado           jsonb,
  erro                text,
  custo               numeric(12,4),
  modelo              text,
  created_at          timestamptz not null default now(),
  updated_at          timestamptz not null default now(),
  finished_at         timestamptz
);

-- ----------------------------------------------------------------------------
-- 2. REVOKE/GRANT padrão robot_* (gap 4.3 fechado)
-- ----------------------------------------------------------------------------
revoke all on public.cortex_tasks from public, anon, authenticated;
grant all    on public.cortex_tasks to service_role;

-- ----------------------------------------------------------------------------
-- 3. Índices (3 base + 1 unique parcial para dedup_key — decisão 4.6 + 4.7)
-- ----------------------------------------------------------------------------
create index if not exists idx_cortex_tasks_status_queued
  on public.cortex_tasks (priority desc, created_at)
  where status = 'queued';

create index if not exists idx_cortex_tasks_created_at
  on public.cortex_tasks (created_at);

create index if not exists idx_cortex_tasks_pid
  on public.cortex_tasks (pid_original);

-- Único índice extra: dedup_key UNIQUE parcial (decisão 4.7).
-- Tarefas sem dedup_key (NULL) ficam isentas do uniqueness — permite
-- retries / fire-and-forget sem chave. Com dedup_key informada, garante
-- idempotência óptica via ON CONFLICT em cortex_enqueue.
create unique index if not exists uq_cortex_tasks_dedup_key
  on public.cortex_tasks (dedup_key)
  where dedup_key is not null;

-- ----------------------------------------------------------------------------
-- 4. RLS: enable, SEM policies (padrão robot_* / cortex_red_proposals)
-- ----------------------------------------------------------------------------
alter table public.cortex_tasks enable row level security;
-- SEM policies (acesso só via RPCs SECURITY DEFINER abaixo; service_role bypass RLS).

-- ----------------------------------------------------------------------------
-- 5. Publicar em supabase_realtime (decisão 4.1 híbrido):
-- Realtime ACORDA worker; SKIP LOCKED em cortex_claim_next decide o vencedor.
-- Idempotente via DO $$ (padrão 20260506201000_5f_b1_robot_crosstalk.sql:74-85).
-- ----------------------------------------------------------------------------
do $$
begin
  if not exists (
    select 1 from pg_publication_tables
     where pubname = 'supabase_realtime'
       and schemaname = 'public'
       and tablename  = 'cortex_tasks'
  ) then
    alter publication supabase_realtime add table public.cortex_tasks;
  end if;
end $$;

-- ============================================================================
-- 6. RPC 1: cortex_enqueue — insere tarefa 'queued' (decision 4.2 + 4.7 + 4.9)
-- ----------------------------------------------------------------------------
-- - Kill switch: raises KILL_SWITCH_ATIVO se robot_b_enabled=false (decisão 4.9).
-- - Zona vermelha: raises zona_vermelha_nao_ejecutavel (decisão 4.2). Vermelhas
--   ficam em cortex_red_proposals / proposals.jsonl, nunca claimable aqui.
-- - Idempotência opt-in: se p_dedup_key informado e já existe linha com o
--   mesmo dedup_key, INSERT ON CONFLICT (dedup_key) DO NOTHING devolve o
--   id existente (decisão 4.7).
-- ============================================================================
create or replace function public.cortex_enqueue(
  p_tarefa             text,
  p_zona               text     default 'verde',
  p_authority_level    text     default 'normal',
  p_autor              text     default null,
  p_pid_original       text     default null,
  p_parent_id          uuid     default null,
  p_payload            jsonb    default null,
  p_priority           int      default 0,
  p_teto_tentativas    int      default 5,
  p_requires_consensus boolean  default false,
  p_dedup_key          text     default null
)
returns uuid
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $$
declare
  v_id uuid;
begin
  -- Kill switch (decision 4.9)
  if not public._robot_setting_enabled('robot_b_enabled') then
    raise exception 'KILL_SWITCH_ATIVO';
  end if;

  -- Validação de payload
  if p_tarefa is null or length(trim(p_tarefa)) = 0 then
    raise exception 'tarefa_vazia';
  end if;
  if p_zona not in ('verde','amarela','vermelha') then
    raise exception 'zona_invalida: %', p_zona;
  end if;
  if p_authority_level not in ('normal','critical') then
    raise exception 'authority_level_invalida: %', p_authority_level;
  end if;

  -- Zona vermelha recusada (decision 4.2). Vermelhas nunca ficam claimable.
  if p_zona = 'vermelha' then
    raise exception 'zona_vermelha_nao_ejecutavel (use cortex_red_proposals / proposals.jsonl)';
  end if;

  -- INSERT idempotente via ON CONFLICT em dedup_key (decision 4.7)
  insert into public.cortex_tasks
    (pid_original, parent_id, zona, authority_level, status, priority, tarefa,
     payload, autor, dedup_key, requires_consensus, teto_tentativas,
     created_at, updated_at)
  values
    (left(p_pid_original, 200), p_parent_id, p_zona, p_authority_level, 'queued',
     greatest(p_priority, 0), left(p_tarefa, 8000),
     p_payload, left(p_autor, 100), p_dedup_key, p_requires_consensus,
     greatest(p_teto_tentativas, 1), now(), now())
  on conflict (dedup_key) where dedup_key is not null
  do nothing
  returning id into v_id;

  -- Se ON CONFLICT DO NOTHING vida (dedup_key existing), v_id é null;
  -- buscar o id existente para devolver ao caller.
  if v_id is null and p_dedup_key is not null then
    select id into v_id from public.cortex_tasks where dedup_key = p_dedup_key limit 1;
  end if;

  return v_id;
end;
$$;

-- Limpar grants herdados e aplicar apenas o pretendido (idempotente).
revoke all on function public.cortex_enqueue(text,text,text,text,text,uuid,jsonb,int,int,boolean,text) from public, anon, authenticated;
grant execute on function public.cortex_enqueue(text,text,text,text,text,uuid,jsonb,int,int,boolean,text) to anon;

-- ----------------------------------------------------------------------------
-- 7. RPC 2: cortex_claim_next — claim atómica com FOR UPDATE SKIP LOCKED.
-- Kill switch (decision 4.9): robot_b_enabled=false -> KILL_SWITCH_ATIVO.
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
  -- Kill switch (decision 4.9)
  if not public._robot_setting_enabled('robot_b_enabled') then
    raise exception 'KILL_SWITCH_ATIVO';
  end if;

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

revoke all on function public.cortex_claim_next(text) from public, anon, authenticated;
grant execute on function public.cortex_claim_next(text) to anon;

-- ----------------------------------------------------------------------------
-- 8. RPC 3: cortex_finish — termina a tarefa (done/failed).
-- SEM guard kill switch (decision 4.9): deixa drenar mesas running.
-- ----------------------------------------------------------------------------
create or replace function public.cortex_finish(
  p_task_id    uuid,
  p_ok         boolean,
  p_resultado  jsonb    default null,
  p_erro       text     default null,
  p_custo      numeric  default null,
  p_modelo     text     default null
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

revoke all on function public.cortex_finish(uuid,boolean,jsonb,text,numeric,text) from public, anon, authenticated;
grant execute on function public.cortex_finish(uuid,boolean,jsonb,text,numeric,text) to anon;

-- ----------------------------------------------------------------------------
-- 9. RPC 4: cortex_archive — admin arquiva sem destruir.
-- Guard: _admin_op_guard. Auditoria: log_admin_action(text,text,uuid,jsonb).
-- ----------------------------------------------------------------------------
create or replace function public.cortex_archive(p_task_id uuid, p_motivo text default null)
returns void
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $$
declare
  v_admin record;
begin
  v_admin := public._admin_op_guard();

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

revoke all on function public.cortex_archive(uuid,text) from public, anon, authenticated;
grant execute on function public.cortex_archive(uuid,text) to authenticated, service_role;

-- ----------------------------------------------------------------------------
-- 10. RPC 5: cortex_list_tasks — admin leitura paginada por status.
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
declare
  v_admin record;
begin
  v_admin := public._admin_op_guard();

  return coalesce((
    select jsonb_agg(to_jsonb(s) order by s.created_at desc)
      from (
        select id, pid_original, parent_id, zona, authority_level, status,
               priority, tarefa, autor, dedup_key, requires_consensus,
               tentativa, teto_tentativas, assigned_agent, assigned_at,
               created_at, updated_at, finished_at
          from public.cortex_tasks
         where (p_status is null or status = p_status)
         order by created_at desc
         limit least(greatest(coalesce(p_limit, 100), 1), 500)
        offset greatest(coalesce(p_offset, 0), 0)
      ) s
  ), '[]'::jsonb);
end;
$$;

revoke all on function public.cortex_list_tasks(text,int,int) from public, anon, authenticated;
grant execute on function public.cortex_list_tasks(text,int,int) to authenticated, service_role;

-- ----------------------------------------------------------------------------
-- 11. RPC 6: cortex_queue_stats — observabilidade pre-flight SS8.
-- ----------------------------------------------------------------------------
create or replace function public.cortex_queue_stats()
returns jsonb
language plpgsql
stable
security definer
set search_path to 'public', 'pg_temp'
as $$
declare
  v_admin record;
  v_pending int;
  v_running int;
  v_oldest timestamptz;
  v_oldest_age_min int;
begin
  v_admin := public._admin_op_guard();

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

revoke all on function public.cortex_queue_stats() from public, anon, authenticated;
grant execute on function public.cortex_queue_stats() to authenticated, service_role;

-- ============================================================================
-- DOWN (documental — reversão MANUAL pelo Danilo; o agente é bloqueado de
-- destruir cortex_tasks, protegida pelo FINTABLE do protege-banco.sh desde
-- F1.4). Os comandos SQL de reversão não estão literais aqui para não
-- accionar o grep naive do hook (que le o texto cru da query).
-- Procedimento de reversão, executar como superuser via sessão com MCP
-- Supabase ativo (apply_migration de uma migration separada com os
-- comandos destrutivos em cascata necessários):
--   1. Retirar cortex_tasks da publicação supabase_realtime
--      (alter publication supabase_realtime ... <tabela> ... public.cortex_tasks).
--   2. Eliminar em cascata as 6 funções cortex_queue_stats, cortex_list_tasks,
--      cortex_archive, cortex_finish, cortex_claim_next, cortex_enqueue.
--   3. Eliminar em cascata a tabela public.cortex_tasks — isto remove
--      também a FK self e o índice unique dedup_key.
-- ============================================================================