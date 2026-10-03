---
id: 2026-08-09-fase2-blueprint
title: Blueprint F2 â€” public.cortex_tasks (prÃ©-implementaÃ§Ã£o)
zona: verde
tipo: blueprint/relatÃ³rio
estado: rascunho_para_aprovaÃ§Ã£o
atualizado: 2026-08-09
refs:
  - PROPOSTA existente: supabase/migrations/20260809120000_PROPOSTA_cortex_tasks_f2.sql
  - .claude/.ai/security/RED_MODEL.md Â§6
  - .claude/.ai/security/pre-flight-multiagent.md Â§6/Â§7/Â§8
  - .claude/.ai/knowledge/permanente/procedural/convencoes.md (Windows/MCP/PostgREST)
---

# Blueprint F2 â€” `public.cortex_tasks` (prÃ©-implementaÃ§Ã£o, read-only)

> **Este documento Ã© sÃ³ blueprint. NÃƒO cria tabela, NÃƒO roda migration, NÃƒO
> altera `server.mjs`, `carteiro.sh` ou `campainha.sh`.** O objetivo Ã© fixar o
> contrato tÃ©cnico antes da implementaÃ§Ã£o, identificar ambiguidades e reportar
> conflitos contra o cÃ³digo real existente. A implementaÃ§Ã£o sÃ³ arranca apÃ³s
> aprovaÃ§Ã£o explÃ­cita do Danilo e abertura de branch `autonomous-night/fase2-*`.

## 0. Fonte principal e estado da arte

Existe em disco uma **primeira versÃ£o da migration** jÃ¡ com prefixo `PROPOSTA_`
(criada por processo autÃ³nomo na sessÃ£o anterior):
`supabase/migrations/20260809120000_PROPOSTA_cortex_tasks_f2.sql` â€” 314 linhas,
**nÃ£o aplicada** (sem MCP Supabase ativo naquele momento). Este blueprint
**baseia-se nela**, valida as escolhas contra o cÃ³digo real existente (relatÃ³rio
dos dois subagentes `explore` acima) e incorpora as **7 decisÃµes fechadas pelo
Danilo em 2026-08-09** (ver Â§9 â€” todas RESOLVIDAS).

> **Status do blueprint**: APROVADO PARA IMPLEMENTAÃ‡ÃƒO. As 7 decisÃµes em aberto
> foram fechadas pelo Danilo. Este documento Ã© o contrato tÃ©cnico formal da F2.
> PrÃ³ximo passo: abrir branch `autonomous-night/fase2-cortex-tasks`, criar
> backup, fazer nova migration com os ajustes decididos, aplicar via MCP
> Supabase, testar.

## 1. Schema completo da tabela `public.cortex_tasks`

Baseado em `supabase/migrations/20260809120000_PROPOSTA_cortex_tasks_f2.sql:36-58`
e validado contra decisÃµes jÃ¡ registadas (`pre-flight-multiagent.md Â§6/Â§7/Â§8`,
`RED_MODEL.md Â§6`, `server.mjs` order frontmatter, `autonomy_backlog_items`)
sem reabrir arquitetura.

### 1.1 Colunas (definitivas no blueprint)

| Coluna | Tipo | NULL | Default | CHECK / Notas |
|---|---|---|---|---|
| `id` | `uuid` | NOT NULL | `gen_random_uuid()` | **PK** |
| `pid_original` | `text` | NULL | â€” | link ao pid do cortex-mcp `prop-<hex>` (ver Â§1.5) |
| `zona` | `text` | NOT NULL | `'verde'` | `CHECK zona IN ('verde','amarela','vermelha')` â€” alinha com `autonomy_backlog_items.zona` (`20260701170000_autonomy_goals_fase5.sql:47`) e `cortex_red_proposals.zona` |
| `authority_level` | `text` | NOT NULL | `'normal'` | `CHECK authority_level IN ('normal','critical')` â€” `pre-flight-multiagent.md Â§6` (critical â†’ Opus 5; normal indisponÃ­vel â†’ GLM 5.1 fallback) |
| `status` | `text` | NOT NULL | `'queued'` | `CHECK status IN ('queued','running','done','failed','archived')` â€” ver Â§1.6 (conflito sobre idioma) |
| `priority` | `int` | NOT NULL | `0` | sem CHECK; Ð¸Ð½Ñ‚ÐµÑ€naÃ§Ã£o para `greatest(p_priority, 0)` em `cortex_enqueue` (na PROPOSTA linha 110) |
| `tarefa` | `text` | NOT NULL | â€” | descriÃ§Ã£o; truncada a 8000 chars em `cortex_enqueue` |
| `payload` | `jsonb` | NULL | â€” | dados estruturados do executor |
| `autor` | `text` | NULL | â€” | quem/o que criou; truncado a 100 chars em `enqueue` |
| `requires_consensus` | `boolean` | NOT NULL | `false` | `pre-flight-multiagent.md Â§7` â€” placeholder harmÃ³nico; sÃ³ vira tabela (`cortex_task_consensus_meta`) em F5 |
| `tentativa` | `int` | NOT NULL | `0` | incrementada atÃ³micamente em `cortex_claim_next` (ver Â§3.2) |
| `teto_tentativas` | `int` | NOT NULL | `5` | espelha `teto_tentativas` da ordem em `.md`; teto fixo em `cortex_nova_ordem` hoje Ã© 5 (`server.mjs:103-124`) |
| `assigned_agent` | `text` | NULL | â€” | worker que fez o claim (em F2 = Ãºnico; F6 = worktree registry) |
| `assigned_at` | `timestamptz` | NULL | â€” | preenchido em `cortex_claim_next` |
| `resultado` | `jsonb` | NULL | â€” | preenchido em `cortex_finish` |
| `erro` | `text` | NULL | â€” | preenchido em `cortex_finish` (truncado a 8000) |
| `custo` | `numeric(12,4)` | NULL | â€” | custo da chamada LLM em USD; `pre-flight-multiagent.md Â§8` |
| `modelo` | `text` | NULL | â€” | nome do modelo que correu (router em F3) |
| `created_at` | `timestamptz` | NOT NULL | `now()` | espelha `criada` do YAML da ordem |
| `updated_at` | `timestamptz` | NOT NULL | `now()` | updated em cada mutaÃ§Ã£o |
| `finished_at` | `timestamptz` | NULL | â€” | preenchido em `cortex_finish` |

### 1.2 PK / FK / RelaÃ§Ãµes

- **PK**: `id uuid` (`gen_random_uuid()`).
- **FK explÃ­cita**: nenhuma (mantÃ©m a tabela isolada â€” nÃ£o amarada a
  `robot_suggestions` nem `autonomy_backlog_items`; ver Â§1.4 para justificaÃ§Ã£o).
- **`parent_id` (relaÃ§Ã£o parent/child)**: **NAO existe** nesta PROPOSTA. A
  relaÃ§Ã£o hierÃ¡rquica entre uma ordem-mÃ£e e passos (chaining de missÃ£o) Ã© hoje
  gerida em `carteiro.sh` pelos campos `missao` + `passo` no YAML da ordem
  (`.claude/.ai/hermes/orquestrador-carteiro/deploy/carteiro.sh:341-355`,
  `missao_fire_next` `:358-378`). A PROPOSTA atual nÃ£o introduz `parent_id`.
  Ver Â§4.5 (decisÃ£o ambÃ­gua: preciso de parent/child em cortex_tasks?).

### 1.3 Ãndices

Da PROPOSTA (`:60-65`):

```sql
create index if not exists idx_cortex_tasks_status_queued
  on public.cortex_tasks (priority desc, created_at)
  where status = 'queued';

create index if not exists idx_cortex_tasks_created_at
  on public.cortex_tasks (created_at);

create index if not exists idx_cortex_tasks_pid
  on public.cortex_tasks (pid_original);
```

**Apenas 3 Ã­ndices** â€” minimalista. Valido:

- `idx_cortex_tasks_status_queued` **partial** suporta o `SELECT â€¦ FOR UPDATE
  SKIP LOCKED` do `cortex_claim_next` (filtro `status='queued'`, sort
  `priority desc, created_at`). **OK.**
- `idx_cortex_tasks_created_at` suporta `cortex_list_tasks` ordenado por
  `created_at desc` â€” OK (embora possa ser substituÃ­do por um partial para
  status running/done numa fase futura).
- `idx_cortex_tasks_pid` suporta lookup por `pid_original` no cortex-mcp
  (verifica se pedido jÃ¡ foi enqueueado) â€” OK.

**PossÃ­veis Ã­ndices adicionais em consideraÃ§Ã£o** (nÃ£o na PROPOSTA; **decisÃ£o
ambÃ­gua â€” ver Â§4.6**):
- `idx_cortex_tasks_status_running` partial `WHERE status='running'` (suporta
  alertas de worker que morreu a meio; necessÃ¡rio em F6+).
- `idx_cortex_tasks_assigned_agent` parcial `WHERE assigned_agent IS NOT NULL`
  (isentificaÃ§Ã£o de worktrees Ã³rfÃ£s em F6).

### 1.4 DecisÃ£o registada: separaÃ§Ã£o de `autonomy_backlog_items` vs `cortex_tasks`

Confirmado contra `supabase/migrations/20260701170000_autonomy_goals_fase5.sql:4-9`
e reportado pelos subagentes:

- **`autonomy_backlog_items`** Ã© a fila hÃ­brida do **maestro** (single-worker),
  FK a `autonomy_goals` (envelope de tetos por goal) e FK opcional a
  `robot_suggestions` (ponte para a fila Robot B). Tem valor-avaliaÃ§Ã£o do Juiz
  (`nota`, `olhos`, `histÃ³rico`, `benchmark`, `max_tentativas`,
  `nota_minima_aceite`). NÃ£o tem `payload jsonb`, `assigned_agent`, `pid_original`,
  `custo`, `modelo`.
- **`cortex_tasks`** (PROPOSTA F2) Ã© a fila-mÃ£e do **Cortex multiagente**, sem
  amarra a `autonomy_goals` (incompatÃ­vel com tetos por goal). Tem colunas
  multiagente (`assigned_agent`, `requires_consensus`, `custo`, `modelo`).
- **Coexistem** â€” decisÃ£o jÃ¡ tomada pelo Danilo; F2 NÃƒO re-purpose
  `autonomy_backlog_items`.

### 1.5 `pid_original` â€” vÃ­nculo ao cortex-mcp file-based

- `pid_original text` aceita os pids `prop-<hex8>` que o `cortex_propor` (
  `server.mjs:93`) gera e persiste em `BRAIN/inbox/_reports/proposals.jsonl`
  (`server.mjs:19`, fonte de verdade file-based).
- `cortex_enqueue` NÃƒO valida o pid nem lÃª o jsonl â€” sÃ³ o guarda como
  link. A leitura correspondent do ficheiro continua a cargo do cortex-mcp
  (duplicar essa leitura na DB quebraria o padrÃ£o `cortex_red_proposals`
  file-based-first documentado em `cortex-mcp-fila-propostas.md`).
- `cortex_red_proposals` (DB) Ã© **espelho read-only** de propostas vermelhas;
  **nÃ£o substitui** o ficheiro (`20260716190000_cortex_red_proposals.sql:1-3`).
  Ver Â§4.2 para conflito em proposals vermelhas que tambÃ©m sÃ£o tasks.

### 1.6 Estados vÃ¡lidos (state machine)

```
       enqueue                 claim_next             finish(ok)
   â”Œâ”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”         â”Œâ”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”         â”Œâ”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”
   â”‚  queued    â”‚â”€â”€â”€â”€â”€â”€â–¶ â”‚  running   â”‚â”€â”€â”€â”€â”€â”€â–¶ â”‚   done     â”‚
   â””â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”˜         â””â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”˜         â””â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”˜
        â”‚                       â”‚
        â”‚                       â”‚ finish(!ok)
        â”‚                       â–¼
        â”‚                  â”Œâ”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”
        â”‚                  â”‚   failed   â”‚
        â”‚                  â””â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”˜
        â”‚                       â”‚
        â”‚                       â”‚ admin archive
        â”‚                       â–¼
        â””â”€â”€â”€ admin archive â”€â–¶ â”Œâ”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”
                              â”‚  archived   â”‚
                              â””â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”˜
```

TransiÃ§Ãµes:
- `queued â†’ running`: sÃ³ dentro de `cortex_claim_next` (atÃ³mica, com
  `tentativa = tentativa + 1`).
- `running â†’ done|failed`: sÃ³ dentro de `cortex_finish` (qualora `status='running'`,
  caso contrÃ¡rio `task_nao_encontrada_ou_nao_running`).
- `* â†’ archived`: sÃ³ dentro de `cortex_archive` (admin, `_admin_op_guard`).

**Sem reabertura automÃ¡tica** de `failed` para `queued` nesta fase (decisÃ£o
registada â€” retry Ã© via nova `cortex_enqueue` ou, em F5+, via consenso). Em
particular, `cortex_finish` nÃ£o pode decrementar `tentativa` nem voltar a
`queued`.

### 1.7 Constraints

- `CHECK (zona IN ('verde','amarela','vermelha'))` (alinha com
  `autonomy_backlog_items.zona` e `cortex_red_proposals.zona`).
- `CHECK (authority_level IN ('normal','critical'))`.
- `CHECK (status IN ('queued','running','done','failed','archived'))`.
- Nenhuma UNIQUE constraint (pid_original pode repetir-se em retentativas;
  pid Ãºnico Ã© privilÃ©gio do cortex-mcp file-based).

## 2. RLS â€” Row Level Security

Baseado na PROPOSTA (`:67-68`) e validado contra o padrÃ£o
`robot_*`/`autonomy_*`/`cortex_red_proposals` (subagente Â§2):

```sql
alter table public.cortex_tasks enable row level security;
-- SEM policies (acesso so via RPCs SECURITY DEFINER; service_role bypassa RLS).
```

### 2.1 PolÃ­tica de acesso â€” quem pode quÃª

| Camada | Acesso Ã  tabela `cortex_tasks` | Via |
|---|---|---|
| `service_role` | **full** (SELECT/INSERT/UPDATE/DELETE bypass RLS) | direto (bypass RLS Supabase) â€” usado por Edge Function / cron / runtime server-mcp |
| `authenticated` (admin) | leitura/escrita admin (listar, arquivar, stats) | RPCs `SECURITY DEFINER` com `_admin_op_guard()` (`cortex_archive`, `cortex_list_tasks`, `cortex_queue_stats`) |
| `authenticated` (nÃ£o-admin) | **nenhum** | RPCs admin com `_admin_op_guard` falham (`app_metadata.role != 'admin'`); RLS sem policies fecha SELECT direto |
| `anon` | sÃ³ executa RPCs operacionais (`cortex_enqueue`, `cortex_claim_next`, `cortex_finish`) | grant `anon` explÃ­cito para workflows externos (VPS, carteiro via curl) â€” mesmo padrÃ£o de `cortex_proposal_sync_upsert` (`20260716190000_cortex_red_proposals.sql:62`) |
| `anon` (SELECT direto) | **bloqueado** | RLS sem policies |

### 2.2 PadrÃ£o SECURITY DEFINER (todas as 6 RPCs)

Cada RPC declara explicitamente:

```sql
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
```

`search_path` explÃ­cito previne ataques de shadowing (mesma patrÃ£o jÃ¡ em
`robot_*`/`autonomy_*`/`cortex_red_proposals`). Ver subagente Â§2.

### 2.3 Grants da tabela â€” replicar padrÃ£o robot_*

Na implementaÃ§Ã£o, **tem que** haver `REVOKE â€¦ FROM PUBLIC, anon, authenticated`
seguido de `GRANT` a `service_role`. Esta parte **nÃ£o estÃ¡ explÃ­cita na
PROPOSTA atual** â€” precisa adicionar:

```sql
revoke all on public.cortex_tasks from public, anon, authenticated;
grant all    on public.cortex_tasks to service_role;
```

(pad pÃ¡gina `20260610150604_robot_b_v4_motor_perfeicao_continua.sql:73-76`, comentÃ¡rio "armadilha M3.5").

**Faltava na PROPOSTA** â€” ver Â§4.3.

### 2.4 ConfirmaÃ§Ã£o: nenhuma polÃ­tica permite alteraÃ§Ã£o indevida

- Nenhuma `policy` (USING/WITH CHECK) na tabela.
- Toda mutaÃ§Ã£o passa por RPC `SECURITY DEFINER` com gate explÃ­cito:
  - operacional: grant `anon` mas funÃ§Ã£o sÃ³ aceita:
    - `cortex_enqueue`: raises `tarefa_vazia`, `zona_invalida`, `authority_level_invalida`.
    - `cortex_claim_next`: sÃ³ faz claim de `status='queued'` (nÃ£o, por ex.,
      alterar aleatoriamente outras colunas).
    - `cortex_finish`: sÃ³ update `WHERE id = p_task_id AND status='running'`
      (nÃ£o found â†’ raise).
  - admin: `_admin_op_guard()` que exige `app_metadata.role='admin'`
    (`20260428000005_admin_gate_app_metadata.sql:21-55`, immutable by client).
- service_role bypassa RLS mas nÃ£o hÃ¡ Edge Function exposta a anon que
  permita UPDATE direto (todas passam pelos RPCs) â€” desde que a F2 nÃ£o
  crie uma Edge Function que mute `cortex_tasks` sem RPC. O blueprint
  **nÃ£o cria Edge Functions** â€” confirmado.

## 3. RPCs â€” contratos formais

### 3.1 `cortex_enqueue` (enqueue de tarefa)

**Assinatura** (`PROPOSTA :76-117`):

```sql
cortex_enqueue(
  p_tarefa             text,
  p_zona               text    default 'verde',
  p_authority_level    text    default 'normal',
  p_autor              text    default null,
  p_pid_original       text    default null,
  p_payload            jsonb   default null,
  p_priority           int     default 0,
  p_teto_tentativas    int     default 5,
  p_requires_consensus boolean default false
) returns uuid
```

- **Grant**: `anon` (`:119`) â€” o cortex-mcp / carteiro (curl VPS) pode chamar.
- **PermissÃ£o**: uma fila de inserÃ§Ã£o; nenhum update/delete capability exposto.
- **Comportamento transacional**: `INSERT` simples numa transaÃ§Ã£o. Sem locks
  sobre outras linhas. Idempotente apenas por idempotÃªncia natural do
  `gen_random_uuid()` (cada chamada cria nova row â€” nÃ£o hÃ¡ dedup; pedido
  repetido cria task duplicada).
- **Filosofia**: vermelha **NÃƒO nasce aqui por execuÃ§Ã£o direta** â€” o cortex-mcp
  jÃ¡ barra `RED_ORDER` na porta (`server.mjs:22`) mandando para
  `cortex_propor`/`proposals.jsonl`. No entanto a RPC nÃ£o invalida `p_zona =
  'vermelha'` (pode ser chamada em leans de casos onde o caller (admin) queira
  bypassar o gate file-based; ver Â§4.2).
- **Truncagens defensivas**: `left(p_pid_original, 200)`, `left(p_tarefa, 8000)`,
  `left(p_autor, 100)`.
- **ValidaÃ§Ãµes de domÃ­nio**: `p_tarefa` non-empty; `p_zona` em CHECK; `p_authority_level` em CHECK.

**IdempotÃªncia**: ausente â€” caller precisa ser responsÃ¡vel por nÃ£o duplicar
enqueue. Ver Â§4.7 (decisÃ£o ambÃ­gua â€” adicionar `dedup_key` como
`robot_suggestions`?).

### 3.2 `cortex_claim_next` (claim atÃ³mico com `FOR UPDATE SKIP LOCKED`)

**Assinatura** (`PROPOSTA :127-160`):

```sql
cortex_claim_next(p_agent text) returns setof public.cortex_tasks
```

- **Grant**: `anon` (`:162`) â€” qualquer worker com a service_role_key ou
  anon pode pedir work; limitado apenas por ser chamado em contexto de
  runtime.
- **Comportamento**:
  ```sql
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
  ```
- **Tratamento de concorrÃªncia**: `FOR UPDATE OF public.cortex_tasks
  SKIP LOCKED` khÃ³a a row; outros workers concorrentes saltam e pegam outra.
  Validado padrÃ£o jÃ¡ existente em `maestro_next_backlog_item`
  (`20260701170000_autonomy_goals_fase5.sql:165-171`) e `cleaning_bookings`
  (`20260713100000_cleaning_no_cleaner_cancel.sql:34-40`).
- **Atomicidade**: cada iteraÃ§Ã£o `BEGIN/COMMIT` implÃ­cita envolve sÃ³
  `SELECT FOR UPDATE + UPDATE RETURNING` na mesma row â€” deadlock-impossÃ­vel
  com workers concorrentes (SKIP LOCKED garante).
- **IdempotÃªncia**: N/A (cada chamada retorna 0 ou 1 tarefa nova; chamada
  duplicada pelo mesmo worker dentro da mesma janela Ã© idempotente sÃ³ se
  fila estÃ¡ vazia).
- **F2 vs F6**: F2 tem sÃ³ 1 worker, mas o `SKIP LOCKED` jÃ¡ prepara paralelismo
  sem mudar semÃ¢ntica (mesma observaÃ§Ã£o no comentÃ¡rio `PROPOSTA:124`).

### 3.3 `cortex_finish` (publicaÃ§Ã£o do resultado)

**Assinatura** (`PROPOSTA :168-200`):

```sql
cortex_finish(
  p_task_id    uuid,
  p_ok         boolean,
  p_resultado  jsonb  default null,
  p_erro       text   default null,
  p_custo      numeric default null,
  p_modelo     text   default null
) returns void
```

- **Grant**: `anon` (`:202`) â€” workers externos (VPS, runtime) reportam.
- **Comportamento**:
  ```sql
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
  ```
- **IdempotÃªncia**:ä¸¥æ ¼ nÃ£o-idempotente â€” segunda chamada ao mesmo
  `p_task_id` com status jÃ¡ `done/failed` throwa
  `task_nao_encontrada_ou_nao_running`. Caller precisa ser responsÃ¡vel por
  nÃ£o reportar resultado duas vezes; se houver risco, usar `RETURNING status`
  para confirmar antes.
- **Sem transiÃ§Ã£o para `queued`** â€” ver Â§1.6 regra "sem reabertura".

### 3.4 `cortex_archive` (admin â€” arquivar sem destruir)

**Assinatura** (`PROPOSTA :207-232`):

```sql
cortex_archive(p_task_id uuid, p_motivo text default null) returns void
```

- **Grant**: `authenticated` (`:234`) â€” sÃ³ admin via `_admin_op_guard()`.
- **Comportamento**: SET `status='archived'`, `updated_at=now()`. NÃ£o hÃ¡
  validaÃ§Ã£o de transiÃ§Ã£o â€” pode arquivar qualquer `status` (incluindo `queued`
  sem jamais ter corrido). **Justificativa**: o admin pode parar a fila.
- **Auditoria**: chama `public.log_admin_action('cortex_archive',
  'cortex_tasks', p_task_id, jsonb_build_object('motivo', ...))`. Confirma
  `log_admin_action` existe? Ver subagente Â§2.5 â€” `robot_audit_log` existe
  (`20260610150604_robot_b_v4_motor_perfeicao_continua.sql:49`), mas
  `public.log_admin_action(...)` â€” precisa validar. **Pendente** (ver Â§4.4).

### 3.5 `cortex_list_tasks` (admin â€” leitura paginada)

**Assinatura** (`PROPOSTA :239-266`):

```sql
cortex_list_tasks(
  p_status text default null,
  p_limit  int  default 100,
  p_offset int  default 0
) returns jsonb
```

- **Grant**: `authenticated` (`:268`) â€” admin via `_admin_op_guard()`.
- **Stable** (read-only); paginado (`limit` capped a 500).
- **Excludes**: `payload, resultado, erro, custo, modelo` â€” nÃ£o devolve payload
  completo (evita leakage por JSON grande); sÃ³ metadados. OK.

### 3.6 `cortex_queue_stats` (admin â€” observabilidade pre-flight Â§8)

**Assinatura** (`PROPOSTA :273-299`):

```sql
cortex_queue_stats() returns jsonb
```

- **Grant**: `authenticated` (`:301`) â€” admin via `_admin_op_guard()`.
- Devolve: pending_count, running_count, oldest_queued_age_min
  (igual a `approved_queue_watermark()` do Robot B).

### 3.7 RPCs NÃƒO incluÃ­das no blueprint F2 â€” adiadas

- **`cortex_publish_result`** (pub/sub do resultado para outros workers):
  NÃƒO existe â€” ver Â§4.1 (conflito Realtime).
- **`cortex_register_feedback`** (avaliaÃ§Ã£o do Juiz): adiada para F5 (consensus);
  hoje existe em `autonomy_backlog_items.juiz_detalhe`.
- **`cortex_vote_consensus`**: adiada para F5 (`cortex_task_consensus_meta`).
- **`cortex_requeue`** (reentrar `failed â†’ queued` com teto): NÃƒO existe â€”
  sem reabertura na F2.
- **`cortex_link_suggestion`** (ponte a `robot_suggestions`): existe jÃ¡ em
  `maestro_link_suggestion` (`20260701170000_autonomy_goals_fase5.sql:184`),
  contexto backlog; cortex_tasks nÃ£o tem este conceito (ver Â§4.8).
## 4. Conflitos / decisÃµes ambÃ­guas â€” RESOLVIDOS pelo Danilo (2026-08-09)

> Todas as 7 decisÃµes fechadas. Nenhuma fica por escolher. As escolhas do
> Danilo estÃ£o marcadas como **[DANIL: ...]**, com a justificaÃ§Ã£o divergente
> da PROPOSTA original onde aplicÃ¡vel. O blueprint da migration final segue
> estas decisÃµes.

### 4.1 CONFLITO A â€” Realtime / Event Bus para `cortex_tasks` â€” RESOLVIDO

**DecisÃ£o do Danilo**: **(c) hÃ­brido.** `cortex_tasks` serÃ¡ Event Bus baseado
em Supabase Realtime, mas **Realtime NÃƒO Ã© garantia de entrega nem de
exclusÃ£o de claim**. Fluxo:

```
Realtime â†’ acorda/notifica worker â†’ RPC cortex_claim_next() â†’ PostgreSQL SKIP LOCKED decide o vencedor
```

Se Realtime cair, worker deve continuar capaz de descobrir tarefas atravÃ©s de
mecanismo de recuperaÃ§Ã£o/poll. Sem NATS na F2.

**Impacto no blueprint**: a migration final **deve adicionar `cortex_tasks`
Ã  publicaÃ§Ã£o `supabase_realtime`** (idempotente via `DO $$ ... $$`, mesmo
padrÃ£o de `20260506201000_5f_b1_robot_crosstalk.sql:74-85`). Worker runtime
mÃ­nimo assina canal `cortex_tasks` (insert) + mantÃ©m loop de poll como
fallback (claim_next a cada N segundos).

### 4.2 CONFLITO B â€” Zona vermelha em `cortex_enqueue` â€” RESOLVIDO

**DecisÃ£o do Danilo**: **(a) recusar execuÃ§Ã£o.** Tarefa que corresponder a
`RED_ORDER` nÃ£o pode ser executada pelo Cortex worker. `cortex_enqueue`
rejeita tarefa vermelha para execuÃ§Ã£o autÃ³noma, ou a encaminha
explicitamente para `cortex_red_proposals` / aprovaÃ§Ã£o humana. Fluxo
proibido: `zona='vermelha' â†’ queued â†’ worker â†’ execuÃ§Ã£o`.

Se necessÃ¡rio registrar ocorrÃªncia para auditoria, pode existir como estado
nÃ£o executÃ¡vel, mas **nunca como work claimable**.

**Impacto no blueprint**:
- `cortex_enqueue` faz raise `zona_vermelha_nao_ejecutavel` se
  `p_zona='vermelha'`. A autoridade para propostas vermelhas continua em
  `cortex_red_proposals` (DB espelho) + `proposals.jsonl` (file-based).
- NÃ£o hÃ¡ caminho "via admin" para enqueue vermelha via `cortex_enqueue`.
  Vermelhas **nunca** ficam claimable em `cortex_tasks`.

### 4.3 GAP â€” Faltam REVOKE/GRANT na tabela (gap tÃ©cnico)

**Resolvido por completude** (nÃ£o foi uma decisÃ£o ambÃ­gua, era gap):
implementaÃ§Ã£o final incluirÃ¡ explicitamente:

```sql
revoke all on public.cortex_tasks from public, anon, authenticated;
grant all    on public.cortex_tasks to service_role;
```

Antes de `enable row level security` (padrÃ£o
`20260610150604_robot_b_v4_motor_perfeicao_continua.sql:73-76`).

### 4.4 GAP â€” `log_admin_action` â€” validar empiricamente

Ainda pendente empÃ­rico. Validar que `public.log_admin_action` existe na
fase de implementaÃ§Ã£o. Se nÃ£o existir, adicionar helper simples ou usar
`admin_audit_log` diretamente.

### 4.5 DECISÃƒO â€” `parent_id` â€” RESOLVIDO

**DecisÃ£o do Danilo**: **adicionar FK.**

```sql
parent_id uuid references public.cortex_tasks(id) on delete cascade
```

MotivaÃ§Ã£o (Danilo): "O Cortex vai precisar de uma relaÃ§Ã£o formal pai â†’ filho
para: orchestrator â†’ executor, executor â†’ critic, task â†’ consensus, fan-out
paralelo, retries/subtasks futuros. NÃ£o depender apenas de `missao`/`passo` em
Markdown."

**Impacto no blueprint**:
- Adicionar coluna `parent_id uuid` Ã  tabela (nullable, default null).
- FK `ON DELETE CASCADE` â€” deletar pai apaga filhos. JustificaÃ§Ã£o (Danilo):
  cascading Ã© a semÃ¢ntica pretendida para sub-tasks Ã³rfÃ£s.
- Sem `ON UPDATE CASCADE` (PK Ã© `uuid`, imutÃ¡vel).
- NÃ£o cria Ã­ndice explÃ­cito em `parent_id` (ver Â§4.6 â€” sem otimizaÃ§Ã£o prematura).

### 4.6 DECISÃƒO â€” Ãndices adicionais â€” RESOLVIDO

**DecisÃ£o do Danilo**: **nÃ£o adicionar agora.** "NÃ£o fazer otimizaÃ§Ã£o prematura.
SÃ³ criar Ã­ndices adicionais quando houver evidÃªncia de necessidade no
teste/performance ou nas fases posteriores."

**Impacto no blueprint**: manter os 3 Ã­ndices da PROPOSTA original (`queued`
partial, `created_at`, `pid_original`). NÃ£o adicionar `status_running` nem
`assigned_agent` parciais agora. Uma coluna `parent_id` FK nÃ£o ganha Ã­ndice
extra por enquanto.

### 4.7 DECISÃƒO â€” `dedup_key` â€” RESOLVIDO

**DecisÃ£o do Danilo**: **adicionar agora.** SemÃ¢ntica definida abaixo.

- `dedup_key text` â€” nullable, default null. Tarefas sem chave explÃ­cita
  ficam `null` (mÃºltiplas permitidas, nÃ£o hÃ¡ enforcement).
- Quando informada (nÃ£o null), `UNIQUE INDEX WHERE dedup_key IS NOT NULL`
  garante singularidade. Tarefas sem dedup_key ficam de fora do uniqueness
  (parcial), permitindo retries / fire-and-forget sem chave.
- Exemplos de `dedup_key`:
  - `prop-<hex8>` â€” pid original do cortex-mcp para ordens jÃ¡ propostas.
  - `missao-<mid>:passo-<pid>` â€” chaining de missÃ£o.
  - `retry:<parent_task_id>:<attempt>` â€” retry explÃ­cito de uma task.
- `cortex_enqueue` faz `INSERT ... ON CONFLICT (dedup_key) WHERE dedup_key
  IS NOT NULL DO NOTHING RETURNING id` â€” callers repetidos retornam o
  `id` jÃ¡ existente sem duplicar. Efeito: idempotÃªncia opt-in via `p_dedup_key`.

### 4.8 CONFLITO C â€” CoexistÃªncia cortex_tasks â†” carteiro â€” RESOLVIDO

**DecisÃ£o do Danilo**: **coexistÃªncia com DB como fonte de verdade para novas
tarefas, mantendo o file-based como compatibilidade/mirror durante a transiÃ§Ã£o.**

> "NÃ£o faÃ§a uma migraÃ§Ã£o brusca. Durante F2: nova ordem â†’ cortex_tasks. E o
> sistema legado `.md` continua existindo como compatibilidade/mirror durante
> a transiÃ§Ã£o. O ponto fundamental Ã©: nÃ£o permitir dupla execuÃ§Ã£o. `task_id` /
> `dedup_key` deve ser a identidade da tarefa. NÃ£o deprecar nem remover
> `carteiro.sh`, `campainha.sh` ou o fluxo `.md` nesta fase. A migraÃ§Ã£o
> completa do carteiro para DB fica para uma fase posterior, depois de o bus
> estar comprovadamente estÃ¡vel."

**Impacto no blueprint**:
- F2 NÃƒO altera `carteiro.sh` nem `campainha.sh`.
- F2 NÃƒO altera `cortex-mcp/server.mjs` nesta fase (o cortex-mcp continua a
  escrever `.md` como atÃ© hoje â€” file-based runtime do carteiro permanece
  100% funcional).
- A migration cria `cortex_tasks` e as 6 RPCs â€” prontas para serem chamadas
  por runtime futuro, mas nenhum runtime as chama ainda nesta fase.
- O `dedup_key` resolve o problema de "execuÃ§Ã£o dupla" caso um runtime futuro
  duplique: se caller passa `dedup_key`, DB idempotente garante 1 linha.
- NÃ£o hÃ¡ conflito de arquitetura: em F2, `cortex_tasks` Ã© uma nova fila
  paralela vazia (sem callers); o carteiro continua file-based. A transiÃ§Ã£o
  real para "DB primÃ¡ria" serÃ¡ fase posterior apÃ³s F2 estÃ¡vel.

### 4.9 CONFLITO D â€” kill switch `robot_b_enabled` â€” RESOLVIDO

**DecisÃ£o do Danilo**: **(a) guard em enqueue + claim.**

> "O kill switch Ã© obrigatÃ³rio. Se `robot_b_enabled = false`, entÃ£o: novas
> tarefas nÃ£o podem iniciar execuÃ§Ã£o autÃ³noma; `cortex_claim_next()` nÃ£o pode
> entregar trabalho a worker; nenhum worker pode contornar o guard; o sistema
> pode permanecer em modo read-only/observaÃ§Ã£o. Reutilize o mecanismo
> canÃ³nico `_robot_op_guard` existente. NÃ£o crie outro kill switch."

**Impacto no blueprint**:
- `cortex_enqueue`: no inÃ­cio do bloco, chama
  `IF NOT public._robot_setting_enabled('robot_b_enabled') THEN RAISE
  'KILL_SWITCH_ATIVO'`. Sem enqueue novo quando kill switch desligado.
- `cortex_claim_next`: idem, raise `KILL_SWITCH_ATIVO` antes do
  `FOR UPDATE SKIP LOCKED`.
- `cortex_finish`: **NÃƒO tem guard** â€” worker que jÃ¡ tem task `running` deve
  poder finalizar mesmo em kill switch (consistentemente com nÃ£o bloquear
  calling de finish numa parada controlada â€” nÃ£o ficam tasks penduradas em
  `running` eterno).
- `cortex_archive`, `cortex_list_tasks`, `cortex_queue_stats`: continuam com
  `_admin_op_guard` apenas (admin sempre pode ver e arquivar em kill switch
  â€” observabilidade Ã© essencial durante debug).
- Reutiliza `public._robot_setting_enabled(p_key)` jÃ¡ definido em
  `20260610150604_robot_b_v4_motor_perfeicao_continua.sql:92-98`.

## 5. SeguranÃ§a â€” verificaÃ§Ã£o cruzada

### 5.1 `protege-banco.sh` jÃ¡ protege `cortex_tasks`

Confirmado: `.claude/hooks/protege-banco.sh:51` lista `cortex_tasks` no
FINTABLE (entre `pending_charges` e `cortex_task_messages`). Efeito:
- `DROP TABLE cortex_tasks` em contexto SQL (MCP Supabase ou psql) â†’ exit 2
  bloqueado. Validado em F1.6 testes (29/29 PASS).
- `TRUNCATE cortex_tasks` â†’ bloqueado.
- `ALTER TABLE cortex_tasks DISABLE ROW LEVEL SECURITY` â†’ bloqueado.
- Harmless atÃ© existir â€” a regex sÃ³ ativa se garantir contexto SQL.

### 5.2 Compatibilidade com `RED_MODEL.md` Â§6

RED_MODEL Â§6 determina: `cortex_tasks` (F2) â†’ proteÃ§Ã£o
"DROP/TRUNCATE/DISABLE RLS". CompatÃ­vel com `protege-banco.sh` Â§5.1
(verificado). RLS destas tabelas Cortex (RED_MODEL Â§6): "service_role full
+ admin via `is_admin()`. Nunca `anon`/`authenticated` leitura direta â€” sÃ³
via RPC `SECURITY DEFINER` (padrÃ£o jÃ¡ seguido por `robot_*`/`autonomy_*`
/`cortex_red_proposals`)." O blueprint segue este padrÃ£o (ver Â§2).

### 5.3 `robot_b_enabled` â€” kill switch

RESOLVIDO em Â§4.9 â€” guard em `cortex_enqueue` e `cortex_claim_next`.

### 5.4 Nenhuma tabela `$` (dinheiro) serÃ¡ tocada pela F2

A migration `20260809120000_PROPOSTA_cortex_tasks_f2.sql` **sÃ³** cria
`public.cortex_tasks` e 6 RPCs. NÃ£o altera:
- Nenhuma tabela listada em `FINTABLE` prÃ©-F1.4 (orders, wallets, ledger,
  ledger_entries, bora_tokens, wallet_transactions, tvde_driver_balances,
  driver_balances, order_financials, order_financial_transactions,
  driver_weekly_settlements, partner_weekly_settlements, appointment_payouts,
  partner_reservation_payouts, pending_charges).
- Nenhuma funÃ§Ã£o SQL listada em `MONEYFN` (`protege-banco.sh:50`).
- Nenhuma edge function slug em `PROTSLUG` (`protege-banco.sh:52`).
- Nenhuma das tabelas Cortex listadas em Â§6 do RED_MODEL **alÃ©m** de
  `cortex_tasks` (F2 nÃ£o cria `llm_call_log` F3, `cortex_task_messages` F4,
  `cortex_task_consensus_meta` F5, `worktree_registry` F6, `agent_events` F7).

Verificado por grep da PROPOSTA: apenas `cortex_tasks` aparece em `create
table`. As 6 RPCs nÃ£o tÃªm qualquer menÃ§Ã£o a tabela financeira.

### 5.5 F2 nÃ£o altera a Trava

- Nenhum hook `.claude/hooks/**` Ã© modificado.
- Nenhum `settings.json` / `settings.local.json` (project ou user home) Ã©
  modificado.
- Nenhum `.claude/.ai/cortex-mcp/server.mjs` modificado.
- Nenhum `carteiro.sh` / `campainha.sh` modificado.
- A migration sÃ³ estende a DB (cria tabela + RPCs) â€” nÃ£o toca nas camadas
  de guardiÃ£o. A F2 Ã© respeitada pela F1 (que protegeu `cortex_tasks` no
  `FINTABLE`); F2 consome essa proteÃ§Ã£o.

## 6. Blueprint de testes E2E (`scripts/e2e/tests/group_15_cortex/`)
> **A criar na implementaÃ§Ã£o F2, nÃ£o nesta fase de blueprint.**
> DiretÃ³rio: `scripts/e2e/tests/group_15_cortex/` (anÃ¡logo a `group_11_robot/`,
> `group_12_suggestions/`, ...).

PadrÃ£o a seguir: `scripts/e2e/conftest.py` (fixtures admin_client service_role
e clientes authenticated; ver subagente Â§A.3). Helpers em `scripts/e2e/helpers/`
(nÃ£o importa cortex helper ainda â€” criar).

### Testes obrigatÃ³rios pedidos pelo Danilo (com decisÃµes resolvidas):

| Teste | Garante | DecisÃ£o alvo |
|---|---|---|
| `test_t72_enqueue_creates_queued.py` | `cortex_enqueue` com payload mÃ­nimo devolve uuid; row em `cortex_tasks` com `status='queued'`, `zona='verde'`, `authority_level='normal'`, `tentativa=0`, `teto_tentativas=5`. Usa `admin_client` (service_role) para verificar. | base |
| `test_t73_dequeue_moves_to_running.py` | `cortex_claim_next('worker-a')` devolve 1 row; `cortex_finish(ok)` no id correto. Fila vazia devolve 0 linhas (nÃ£o raises). | base |
| `test_t74_concurrent_workers_one_claim.py` | 2 workers concorrentes (`threading` ou `asyncio`); sÃ³ 1 pega a row; outro devolve vazio. SKIP LOCKED valida. | base |
| `test_t75_skip_locked.py` | Cria 5 tasks; worker A pega 1 em transaÃ§Ã£o longa (begin sem commit); worker B salta a locked e pega prÃ³xima; worker A rollback. Validar estado final. | base |
| `test_t76_publish_result.py` | `cortex_finish` com `p_ok=true` popula `resultado`, `custo`, `modelo`, `finished_at`, status `done`. IdempotÃªncia: segunda chamada raises `task_nao_encontrada_ou_nao_running`. | base |
| `test_t77_retry_increments_tentativa.py` | `failed â†’ nova enqueue` cria nova row com `tentativa=0` (nÃ£o hÃ¡ requeue na F2). Ou diagramar que retry exige `cortex_enqueue` explÃ­cito. | base |
| `test_t78_parent_child_pid_link.py` | Enqueue parent + child com `parent_id`; validar FK e cascade delete. | Â§4.5 |
| `test_t79_dedup_key_idempotency.py` | 2x enqueue com mesmo `dedup_key='prop-deadbeef'` â†’ devolve mesmo `id`. `ON CONFLICT DO NOTHING` validado. Sem dedup_key â†’ mÃºltiplas rows permitidas. | Â§4.7 |
| `test_t80_realtime_insert_notifies.py` | Subscrever canal `cortex_tasks` (Realtime insert); fazer INSERT; validar notificaÃ§Ã£o recebida dentro de timeout. | Â§4.1 (c) hÃ­brido |
| `test_t81_poll_recovery_when_realtime_down.py` | Simular Realtime indisponÃ­vel (desconectar listener); worker faz poll loop `cortex_claim_next` de qualquer forma; valida que fila drena (fallback). | Â§4.1 (c) hÃ­brido |
| `test_t82_kill_switch_halts_enqueue_claim.py` | Set `platform_settings.robot_b_enabled=false` (via `admin_autonomy_set_switch`); chamar `cortex_enqueue` e `cortex_claim_next` â†’ ambos raises `KILL_SWITCH_ATIVO`. `cortex_finish` em task jÃ¡ running â†’ ainda funciona (nÃ£o bloqueada). | Â§4.9 |
| `test_t83_red_zone_rejected_by_enqueue.py` | `cortex_enqueue(zona='vermelha', tarefa='MUDAR tarifa TVDE para 1.0')` â†’ raises `zona_vermelha_nao_ejecutavel`. Vermelhas nunca entram na fila cortex_tasks. | Â§4.2 |
| `test_t84_rls_blocks_direct_select.py` | `anon` client nÃ£o consegue `select * from cortex_tasks` (RLS sem policies devolve 0/permission denied). `anon` consegue chamar `cortex_enqueue` (grant explicit). `authenticated` nÃ£o-admin tambÃ©m bloqueado em SELECT. | Â§2 |
| `test_t85_admin_archive_via_op_guard.py` | `cortex_archive` chamado por `authenticated` admin â†’ ok. chamado por `authenticated` nÃ£o-admin â†’ raises `not_admin`. chamado por `anon` â†’ raises permission denied (sem grant). | Â§2 |
| `test_t86_list_tasks_and_queue_stats.py` | `cortex_list_tasks(status='queued', limit=5)` devolve jsonb array paginado. `cortex_queue_stats` devolve `pending_count`, `running_count`, `oldest_queued_age_min`. | base |
| `test_t87_md_db_no_duplicate_execution.py` | Simula fluxo de coexistÃªncia: caller escreve `.md` com `missao-id` E chama `cortex_enqueue` com `dedup_key='missao-id'`. 2a chamada `cortex_enqueue` mesmo `dedup_key` â†’ devolve mesmo `id` (idempotÃªncia). Garante 1 execuÃ§Ã£o. | Â§4.8 |
| `test_t88_rollback_down_migration.py` | Aplica migration F2; executa DOWN; verifica que tabela e 6 RPCs desaparecem; re-aplica (idempotente). Realizar sÃ³ em DB de teste. | base |

### Testes NÃƒO cobertos por blueprint F2 (leave para fases futuras):
- Consenso / criticizing (F5 â€” `cortex_task_consensus_meta`).
- LLM routing por `authority_level` (F3 â€” `llm_call_log`).
- Worktree paralelo (F6 â€” `worktree_registry`).
- Cost budget acumulado (F7 â€” `agent_events`).

## 7. Pontos empÃ­ricos a validar na fase de implementaÃ§Ã£o

Antes do `apply_migration` real, validar:

1. **`public.log_admin_action`** existe em prod? Ver Â§4.4. Se nÃ£o, adicionar
   helper ou usar INSERT direto em `admin_audit_log`.
2. **`public._admin_op_guard()`** e `public._robot_setting_enabled()`** jÃ¡
   estÃ£o disponÃ­veis (compilados) â€” provavelmente sim, referenciados em
   mÃºltiplas migrations.
3. **`public.is_admin()`** disponÃ­vel (`20260503040000_partners_rls_approved_only.sql:5-28`
   confirma).
4. **CRLF em migrations SQL**: proibido em scripts `.sh` (`.gitattributes`),
   migrations sÃ£o text plain SQL â€” sem restriÃ§Ã£o explÃ­cita, mas todos os
   scripts devem ser LF.
5. **PostgREST teto** (`convencoes.md:52-58`): aplicar a migration exige
   MCP Supabase, NÃƒO pode ser via `curl` PostgREST (nÃ£o cobre DDL). SessÃ£o
   de implementaÃ§Ã£o tem que ter `mcp__claude_ai_Supabase__apply_migration`
   ativo.
6. **`.venv/Scripts/python.exe`** para scripts Python auxiliares (nÃ£o
   `python` global quebrado).

## 8. Resumo do blueprint final â€” snapshot Ãºnico (com decisÃµes)

- **Tabela**: `public.cortex_tasks` com **24 colunas** (22 originais +
  `parent_id` + `dedup_key`), 3 CHECK, 3 Ã­ndices (queued partial +
  created_at + pid_original) + 1 unique partial `dedup_key` (parcial WHERE
  NOT NULL), PK `uuid`, 1 FK self (`parent_id` ON DELETE CASCADE). RLS
  enabled sem policies. REVOKE/GRANT padrÃ£o robot_*.
- **6 RPCs SECURITY DEFINER** (search_path public/pg_temp):
  - `cortex_enqueue` (anon) â€” INSERT queued; **guarda kill switch**;
    **rechaza zona='vermelha'**; **idempotente via `dedup_key`**.
  - `cortex_claim_next` (anon) â€” FOR UPDATE SKIP LOCKED, queued â†’ running;
    **guarda kill switch**.
  - `cortex_finish` (anon) â€” running â†’ done/failed. Sem guard (drenar running).
  - `cortex_archive` (auth+admin) â€” archive via `_admin_op_guard`.
  - `cortex_list_tasks` (auth+admin) â€” paginated list.
  - `cortex_queue_stats` (auth+admin) â€” observability.
- **Realtime**: YES â€” `cortex_tasks` adicionada a `supabase_realtime`
  (publicaÃ§Ã£o idempotente). Worker hÃ­brido:Realtime + fallback poll.
- **Kill switch `robot_b_enabled`**: herdado via
  `_robot_setting_enabled('robot_b_enabled')` em enqueue e claim.
- **Zona vermelha**: recusada em_enqueue. Vermelhas ficam em
  `cortex_red_proposals`/`proposals.jsonl` (file-based).
- **`parent_id`**: FK self com `ON DELETE CASCADE`.
- **`dedup_key`**: UNIQUE parcial; idempotÃªncia opt-in.
- **CoexistÃªncia carteiro**: file-based stays; DB Ã© nova fila paralela
  (sem callers em F2); `dedup_key` resolve duplas.
- **Herdado da F1**: `cortex_tasks` jÃ¡ no `FINTABLE` do `protege-banco.sh`
  desde F1.4 (DROP/TRUNCATE/DISABLE RLS bloqueados).

## 9. DecisÃµes FINAIS pelo Danilo (todas fechadas em 2026-08-09)

| Â§ | DecisÃ£o |
|---|---|
| 4.1 Realtime | **(c) hÃ­brido** â€” Realtime notifica, SKIP LOCKED decide. Poll fallback. Sem NATS. |
| 4.2 Zona vermelha | **(a) recusar execuÃ§Ã£o** â€” `cortex_enqueue` raises se `zona='vermelha'`. |
| 4.3 Gap REVOKE/GRANT | **Completude tÃ©cnica â€” adicionar explicitamente**. |
| 4.4 `log_admin_action` | **Validar empiricamente na implementaÃ§Ã£o.** |
| 4.5 `parent_id` | **Adicionar FK com `ON DELETE CASCADE`.** |
| 4.6 Ãndices adicionais | **NÃ£o adicionar agora** (no premature opt). |
| 4.7 `dedup_key` | **Adicionar agora** â€” UNIQUE parcial, opt-in, idempotÃªncia. |
| 4.8 CoexistÃªncia carteiro | **CoexistÃªncia com DB nova verdade**; `.md` mantido; sem duplas (dedup_key). |
| 4.9 Kill switch | **(a) guard em enqueue + claim** â€” herda `robot_b_enabled`. |

## 10. ConclusÃ£o

A PROPOSTA existente em disco (`20260809120000_PROPOSTA_cortex_tasks_f2.sql`)
estÃ¡ tecnicamente sÃ³lida como base. As 7 decisÃµes do Danilo fecham todos os
conflitos. PrÃ³ximo passo da implementaÃ§Ã£o:

1. Abrir `autonomous-night/fase2-cortex-tasks` a partir de `autonomous-night/fase1-hardening` (que tem commit F1 `d2effc9`).
2. Criar backup `.claude/_backups/fase2/<ts>/` (mesmo padrÃ£o da Fase 1).
3. Escrever migration final `supabase/migrations/<ts>_cortex_tasks_f2.sql` com:
   - 24 colunas (22 originais + `parent_id` + `dedup_key`).
   - REVOKE/GRANT padrÃ£o robot_*.
   - 4 Ã­ndices (3 originais + unique parcial `dedup_key` WHERE NOT NULL).
   - `alter publication supabase_realtime add table public.cortex_tasks` (idempotente).
   - 6 RPCs com as decisÃµes de guard / vermelha / dedup / parent.
   - Bloco DOWN (rollback manual do Danilo â€” documental, nÃ£o literal para nÃ£o
     accionar `protege-banco.sh`).
4. Aplicar via `mcp__claude_ai_Supabase__apply_migration` (destrutivo sobre
   `cortex_tasks` Ã© bloqueado pelo hook, mas migration CREATE TABLE nÃ£o Ã©).
5. Implementar runtime mÃ­nimo (Node/Edge/standalone script) sÃ³ para testes
   Realtime + poll fallback. Feature flags default OFF (`USE_BUS=false`).
6. Criar `scripts/e2e/tests/group_15_cortex/` com os 17 testes tabelados em Â§6.
7. Rodar via `scripts/e2e/.venv/Scripts/pytest.exe tests/group_15_cortex/`.
8. Validar que 0 ficheiros `$` foram tocados (`pre-flight-multiagent.md Â§4`).
9. **Parar e apresentar relatÃ³rio. NÃ£o abrir F3 automaticamente.**

---

## 11. Anexo â€” citaÃ§Ãµes diretas (file:line) usadas como prova

Cada afirmativa deste blueprint tem um `file:line` no repositÃ³rio. As
principais:

- Subagente `explore` Â§A: `robot_suggestions` Ã© fila Ãºnica do Robot B
  (criada em `20260610150604_robot_b_v4_motor_perfeicao_continua.sql:28`,
  RLS sem policies `:68-76`, kill switch `:80-88`).
- Subagente `explore` Â§B: `autonomy_backlog_items` Ã© a fila do maestro
  (`20260701170000_autonomy_goals_fase5.sql:40`, FK dupla; justificaÃ§Ã£o
  para nÃ£o-repurpose em `:4-9`).
- Subagente `explore` Â§C: `robot_crosstalk` Ã© o canal pergunta/resposta
  (`20260506201000_5f_b1_robot_crosstalk.sql:32`, Ãºnico em `supabase_realtime`
  `:74-85`) â€” prova que padrÃ£o de publicaÃ§Ã£o jÃ¡ existe.
- Subagente `explore` Â§D: `carteiro.sh` e `campainha.sh` usam inotify no
  VPS, NÃƒO Realtime â€” f2 nÃ£o substitui isto.
- Subagente `explore` Â§F: 10 tools MCP em `cortex-mcp/server.mjs:224-235`;
  `cortex_nova_ordem` escreve `.md` direto (nÃ£o chama DB) â€” f2 nÃ£o altera
  isto.
- Subagente `explore` Â§G: `cortex_red_proposals` Ã© espelho DB sÃ³ de leitura
  de `proposals.jsonl` (`20260716190000_cortex_red_proposals.sql:1-3`).
- Subagente `explore` Â§H: `robot_b_enabled` lido em 8 camadas; helper
  `_robot_setting_enabled` em `20260610150604_robot_b_v4_motor_perfeicao_continua.sql:92-98`.
- Subagente `explore` Â§I: PostgREST nÃ£o cobre DDL; `convencoes.md:52-58`.
- Subagente 2 Â§4: `FOR UPDATE SKIP LOCKED` jÃ¡ usado em produÃ§Ã£o em
  `autonomy_backlog_items` (maestro) e `cleaning_bookings`.
- Subagente 2 Â§5: pg_cron jÃ¡ tem consumidor robot-b-hourly (jobid 35) e
  cleaning crons; blueprint F2 nÃ£o introduz novo cron.
- Subagente 2 Â§7: As 5 outras tabelas Cortex (F3-F7) NÃƒO existem em
  migrations; apenas `cortex_tasks` tem PROPOSTA.

---

**Status**: APROVADO pelo Danilo em 2026-08-09. Pronto para implementaÃ§Ã£o
conforme passos em Â§10.