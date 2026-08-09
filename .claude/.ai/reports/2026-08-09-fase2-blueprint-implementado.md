---
scope: relatorio
tema: fase2-blueprint-implementado
escopo: projeto
estado: parado_aguardando_apply_mcp
atualizado: 2026-08-09
zona: verde
confianca: alto
refs:
  - .claude/.ai/reports/2026-08-09-fase2-blueprint.md
  - supabase/migrations/20260809120000_PROPOSTA_cortex_tasks_f2.sql
---

# Sessão 2026-08-09 — F2 Blueprint + Implementação parcial (parou por falta de MCP Supabase)

> Continuação direta da F1 (commit `d2effc9`). Branch `autonomous-night/fase2-cortex-tasks`
> criada (etiqueta `PROPOSTA` no prefixo do migration até apply efetiva).

## 1. Blueprint atualizado com as 7 decisões FECHADAS pelo Danilo

Documento: `.claude/.ai/reports/2026-08-09-fase2-blueprint.md` (818 linhas).

| § | Decisão |
|---|---|
| 4.1 Realtime | **(c) híbrido** — Realtime notifica; SKIP LOCKED decide; poll fallback. Sem NATS. |
| 4.2 Zona vermelha | **(a) recusar execução** — `cortex_enqueue` raises se `zona='vermelha'`. |
| 4.3 Gap REVOKE/GRANT | **Completude** — adicionados explicitamente. |
| 4.4 `log_admin_action` | **Validado** — `20260428000000_admin_audit_log.sql:65` confirmado. |
| 4.5 `parent_id` | **Adicionar FK com `ON DELETE CASCADE`.** |
| 4.6 Índices adicionais | **Não adicionar agora** (no premature opt). |
| 4.7 `dedup_key` | **Adicionar agora** — UNIQUE parcial, opt-in, idempotência. |
| 4.8 Coexistência carteiro | **Coexistência** — DB nova via; `.md` mantido; sem duplas (dedup_key). |
| 4.9 Kill switch | **(a) guard em `enqueue` + `claim`** — herda `robot_b_enabled` via `_robot_setting_enabled`. |

## 2. Implementação nesta sessão (commits staged)

**24 arquivos staged** no commit F2 evolução (a aparecer após commit final).

### 2.1 Migration final (`20260809120000_PROPOSTA_cortex_tasks_f2.sql`)

Atualizada da v1 (commit `3d9cf3d`) com TODAS as 7 decisões:

- **Schema**: 24 colunas (22 originais + `parent_id` uuid FK self ON DELETE CASCADE + `dedup_key text`).
- **CHECKs**: `zona IN ('verde','amarela','vermelha')`, `authority_level IN ('normal','critical')`,
  `status IN ('queued','running','done','failed','archived')`.
- **Índices (4)**: `idx_cortex_tasks_status_queued` (partial WHERE status='queued'),
  `idx_cortex_tasks_created_at`, `idx_cortex_tasks_pid`, `uq_cortex_tasks_dedup_key`
  (UNIQUE partial WHERE dedup_key IS NOT NULL).
- **RLS**: enabled sem policies. **REVOKE/GRANT padrão robot_*** (gap 4.3 fechado).
- **Realtime**: `DO $$ ... alter publication supabase_realtime add table public.cortex_tasks ... $$;`
  (idempotente, padrão `20260506201000_5f_b1_robot_crosstalk.sql:74-85`).
- **6 RPCs SECURITY DEFINER** (all `set search_path to 'public','pg_temp'`):
  1. `cortex_enqueue(text,text,text,text,text,uuid,jsonb,int,int,boolean,text) → uuid`
     - guard `_robot_setting_enabled('robot_b_enabled')` → raises `KILL_SWITCH_ATIVO` se false (D 4.9).
     - raises `zona_vermelha_nao_ejecutavel` se `p_zona='vermelha'` (D 4.2).
     - `ON CONFLICT (dedup_key) WHERE dedup_key IS NOT NULL DO NOTHING` → idempotência (D 4.7).
     - grant `anon` (compatibilidade com VPS/carteiro curl).
  2. `cortex_claim_next(text) → setof cortex_tasks`
     - guard `robot_b_enabled` idem (D 4.9).
     - `FOR UPDATE OF public.cortex_tasks SKIP LOCKED LIMIT 1` + UPDATE `status='running',
       tentativa++, assigned_agent/assigned_at`.
  3. `cortex_finish(uuid,boolean,jsonb,text,numeric,text) → void`
     - só `WHERE id = p_task_id AND status='running'`; `not found` raises.
     - SEM guard kill switch (deixa drenar `running`).
  4. `cortex_archive(uuid,text) → void` — admin via `_admin_op_guard` + `log_admin_action`.
  5. `cortex_list_tasks(text,int,int) → jsonb` — admin via `_admin_op_guard`.
  6. `cortex_queue_stats() → jsonb` — admin via `_admin_op_guard`.
- **DOWN documental** (sem comandos literais para não accionar `protege-banco.sh`).

### 2.2 Teste de simulação da Trava (`f2_trava_sim_test.sh`)

Atualizado de v1 `.cjs` → v2 `.sh`. Valida que `protege-banco.sh`:

- **PERMITE** `apply_migration` com query da migration F2 final (CREATE TABLE/INDEX/FUNCTION/DO).
- **PERMITE** `execute_sql` com query da migration F2 final.
- **BLOQUEIA** `DROP TABLE cortex_tasks` (controlo negativo — exit 2).
- **BLOQUEIA** `ALTER TABLE cortex_tasks DISABLE ROW LEVEL SECURITY` (exit 2).

Resultado: **5/5 PASS**.

### 2.3 Testes E2E (17 testes em `scripts/e2e/tests/group_15_cortex/`)

Implementados `T72`–`T88` conforme blueprint §6:

| Teste | Cobre | Status real |
|---|---|---|
| t72 | enqueue normal | **SKIP** (precisa tabela) |
| t73 | dequeue → running | **SKIP** |
| t74 | 2 workers concorrentes → 1 claim | **SKIP** |
| t75 | SKIP LOCKED | **SKIP** |
| t76 | publish result + idempotência | **SKIP** |
| t77 | retry via nova enqueue | **SKIP** |
| t78 | parent/child cascade delete | **SKIP** |
| t79 | dedup_key idempotência | **SKIP** |
| t80 | Realtime insert notifica | **SKIP** |
| t81 | poll recovery (Realtime DOWN) | **SKIP** |
| t82 | kill switch OFF corta enqueue+claim | **SKIP** |
| t83 | RED_ORDER nunca executa | **SKIP** |
| t84 | RLS bloqueia anon direct SELECT | **SKIP** |
| t85 | admin archive via _admin_op_guard | **SKIP** |
| t86 | cortex_list_tasks + cortex_queue_stats | **SKIP** |
| t87 | .md↔DB coexistência sem dupla | **SKIP** |
| t88 | rollback/down migration (manual) | **SKIP** (documental manual) |

Todos têm `skip_if_no_cortex_tasks(admin_client)` no início que valida a
existência da tabela via service_role e skipa automaticamente se migration
ainda não aplicada. Resultado do `pytest`:

```
======================= 17 skipped, 1 warning in 5.31s ========================
```

Helper em `scripts/e2e/helpers/cortex_tasks.py` com wrappers
`enqueue`/`claim_next`/`finish`/`set_robot_b_enabled`/`cleanup_all_tasks`/etc.

### 2.4 Runtime mínimo (`cortex-worker.js`)

`scripts/e2e/cortex-mcp/runtime/cortex-worker.js` (180 linhas):
- Assina canal Realtime `cortex-tasks-realtime` para `INSERT` events.
- Poll fallback a cada 10s (default).
- `FEATURE_FLAG: USE_BUS=false` (default) — em modo observador, faz claim+finish
  com `resultado={reason:'observer_noop'}` sem "executar".
- `USE_BUS=true` — executa placeholder no-op (`resultado={runtime_placeholder:true}`).
- Stats + graceful shutdown (SIGINT/SIGTERM/timeout 60s).
- **Não altera** `server.mjs`, `carteiro.sh`, ou qualquer runtime existente.

### 2.5 Backups criados

`.claude/_backups/fase2/2026-08-09-fase2-evolucao/` com:
- `20260809120000_PROPOSTA_cortex_tasks_f2.sql.v1.bak` (migration v1 do commit `3d9cf3d`)
- `cortex_tasks_f2_test.py.v1.bak` (teste v1 do commit `3d9cf3d`)
- `f2_trava_sim_test.cjs.v1.bak` (sim v1 em `.cjs`)

## 3. Validações executadas nesta sessão

| Item | Resultado |
|---|---|
| Juiz `anti_trapaca.py --base d2effc9` | **CLEAN** (0 batota) |
| 0 ficheiros `$` tocados no diff | **PASS** (verificado por grep manual) |
| `f2_trava_sim_test.sh` (5 casos) | **5/5 PASS** |
| Colecção dos 17 testes E2E | **17 collected (EXIT 0)** |
| Execução dos 17 testes | **17 skipped** (cortex_tasks não existe em prod) |
| Sintaxe SQL estática (8 pares `$$`, 1 create table, 4 index, 6 functions...) | **OK** |
| Helpers SQL em prod: `_admin_op_guard`, `_robot_setting_enabled`, `log_admin_action` | **confirmados por grep** |

## 4. BLOQUEADOR — passo 4 (apply_migration via MCP Supabase)

**Não executado**: este runtime opencode **não tem MCP Supabase disponível**.
- `~/.claude/mcp.json` não existe.
- `.claude/mcp.json` não existe.
- `psql` / `docker` não disponíveis no PATH.

`apply_migration` precisa de `mcp__claude_ai_Supabase__apply_migration` (capability
MCP que não está registada neste runtime) ou SQL direto via `psql` no Supabase.

**Como desbloquear**: o Danilo precisa de uma das seguintes opções:
1. **(Preferido)** Abrir sessão em runtime com MCP Supabase ativo (Claude Code Crush)
   e executar `mcp__claude_ai_Supabase__apply_migration` com o conteúdo da
   migration F2 final.
2. **(Em alternativa)** Aplicar via `supabase db push` ou `supabase migration up`
   na CLI local — mas isto pode impactar a DB de produção; precisa autorização
   explícita antes.

Após apply, **re-correr os 17 testes** (`pytest scripts/e2e/tests/group_15_cortex/`)
que deixarão de skip e validarão todos os 17 critérios.

## 5. Trava intacta — confir o que foi NEW

- `.claude/hooks/*` NÃO tocados.
- `.claude/settings.json` (project + home) NÃO tocados.
- `.claude/.ai/cortex-mcp/server.mjs` NÃO tocado.
- `carteiro.sh` / `campainha.sh` NÃO tocados.
- Migration NÃO toca FINTABLE (`cortex_tasks` está no FINTABLE desde F1; só cria
  a tabela, os índices, RLS, RPCs e adiciona à publicação Realtime).
- `MONEYFN` e `PROTSLUG` intocados.

## 6. NÃO avançou para F3 (respeitando regra de parada)

- Nenhuma tabela `llm_call_log` criada (F3).
- Nenhuma ACL `authority_level` enforceada via DB trigger (F3).
- Nenhum router implementado (F3).
- Nenhum consenso mecanismo (F5 — `cortex_task_consensus_meta`).
- Worktree registry (F6) e agent_events (F7) não começados.
- Política de modelos confirmada intocada:
  - `critical → Opus 5 obrigatório → indisponível = pausa humana`
  - `normal → GLM 5.1 fallback + log`
  (Decisão permanece em F3.)

## 7. Próximo pass (handoff)

1. **Danilo**: aplicar migration F2 via MCP Supabase em runtime apropriado
   (conteúdo em `supabase/migrations/20260809120000_PROPOSTA_cortex_tasks_f2.sql`).
2. Após apply, **re-correr** `scripts/e2e/.venv/Scripts/pytest tests/group_15_cortex/ -v`
   para validar os 17 testes (deixam de skip).
3. Se algum teste falhar, **PARE** (regra do Danilo); não tente fix num runtime
   sem MCP Supabase — abra sessão com MCP e investigue.
4. Só depois de 17/17 verdes, fazer commit final do apply na branch
   `autonomous-night/fase2-cortex-tasks` (rename `PROPOSTA_` do ficheiro).

## 8. Resumo do commit staged nesta sessão

24 arquivos prontos para commit em `autonomous-night/fase2-cortex-tasks`:

- 1 migration F2 final atualizada (`+308/-154` delta vs v1)
- 1 blueprint F2 (818 linhas)
- 1 sim teste da Trava substituído (`.cjs` → `.sh`)
- 17 testes E2E em `group_15_cortex/`
- 1 helper `cortex_tasks.py`
- 1 runtime mínimo `cortex-worker.js`

**Status**: parado conforme regra "parar e apresentar relatório" — apply_migration
pendente de sessão com MCP Supabase.