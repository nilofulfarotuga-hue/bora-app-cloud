# Sessão 5F-α — Fase A · AUDIT (read-only)

**Data:** 2026-05-06
**Branch:** `autonomous-night-2026-04-29`
**Estado:** ⛔ STOP — aguarda luz verde Danilo (PROTECÇÃO TOTAL)
**Pré-requisito:** 5F completo em prod (commit `14c0462`)

---

## A0. Regressão check + numeração + SHA

| Métrica | Real | Esperado | Status |
|---|---|---|---|
| `support_skills` active total | **21** (escalate=3, read_only=11, write_shadow=7) | 21 | ✅ |
| Skill `ASK_ROBOT_B` | mode=`escalate`, version=**1**, active=true | — | ✅ → próxima v2 |
| `robot_crosstalk` table | exists | 1 | ✅ |
| `robot_crosstalk` rows | **0** | qualquer | ✅ (backfill irrelevante — sem rows) |
| `support_settings.rag_enabled` | true | true | ✅ |
| `support_knowledge_chunks` | **534** | 534 | ✅ |
| `business_rules.md` última § | **§39** (5F) | §39 | ✅ → próxima §40 |
| `support-chatbot` version | **7** ACTIVE | 7 | ✅ |
| `support-chatbot` ezbr_sha256 | `7aee17d95b04a236672b05a1381a715926f6450e590914173318c18fe48f93e6` | — | 📌 **rollback target B2** |

---

## A1. Schema validation

### `support_skills` cols (relevantes)

| Coluna | Tipo | Nota |
|---|---|---|
| `skill_name` | text | PK lookup |
| `playbook_md` | text | UPDATE alvo |
| `version` | integer | `version+1` em B1 |
| `active` | boolean | filtro |
| `updated_at` | timestamptz | ✅ **EXISTE** — B1 pode incluir `updated_at = now()` |

→ **B1 inclui `updated_at = now()`** no UPDATE skill.

### `robot_crosstalk` schema actual (13 cols)

```
id (uuid PK), created_at, direction, status, question,
question_context, asked_by, answer, answered_at, answered_by,
skill_triggered, rag_chunks_used, session_id
```

→ **`urgency` NÃO existe** — ALTER ADD COLUMN em B1 é seguro.

### RPCs actuais

| RPC | Args (5F) | Returns |
|---|---|---|
| `agent_ask_robot_b` | `p_question text, p_session_id uuid DEFAULT NULL, p_skill_triggered text DEFAULT NULL, p_context jsonb DEFAULT '{}'` | uuid |
| `admin_list_crosstalk` | `p_status text DEFAULT 'pending', p_direction text DEFAULT 'all', p_limit integer DEFAULT 50` | TABLE 14 cols |
| `robot_b_respond` | `p_crosstalk_id uuid, p_answer text, p_rag_chunks jsonb DEFAULT '[]'` | void |

### ⚠️ GRANTs actuais — DIVERGEM DO PLANO 5F-α

| RPC | GRANT real (5F deploy) | Plano 5F-α | Discrepância |
|---|---|---|---|
| `agent_ask_robot_b` | **authenticated + service_role** | "service_role apenas" | ❌ DIVERGE |
| `admin_list_crosstalk` | authenticated + service_role | authenticated | ⚠️ menor (service_role ok) |
| `robot_b_respond` | service_role only | (preservar) | ✅ |

Detalhe completo:
```
admin_list_crosstalk → EXECUTE TO authenticated + service_role
agent_ask_robot_b   → EXECUTE TO authenticated + service_role
robot_b_respond     → EXECUTE TO service_role
```

→ Ver A4.1 para análise.

---

## A2. Tool `agent_ask_robot_b` no chatbot v7

### a) Tool definition actual (linhas ~221-252 do source)

```js
{
  name: 'agent_ask_robot_b',
  description: 'Regista problema tecnico da app...',
  parameters: {
    type: 'object',
    properties: {
      p_question: { type: 'string', description: 'Descricao completa...' },
      p_skill_triggered: { type: 'string', enum: ['ASK_ROBOT_B'], description: 'Sempre "ASK_ROBOT_B".' },
      p_context: { type: 'object', description: 'Contexto opcional...' },
    },
    required: ['p_question', 'p_skill_triggered'],
  },
}
```

→ Naming convention: **`p_` prefix** (espelha args do RPC). Adicionar **`p_urgency`** (não `urgency`).

### b) Handler dispatcher: **GENÉRICO** (NÃO case explícito) ✅

Source mostra branching:
```js
if (PROPOSE_ACTION_TOOL_NAMES.has(fnName)) {
  // adminClient.rpc('agent_propose_action', { ... }) — caminho dedicado
} else {
  rpcRes = await callRpc(userJwt, fnName, fnArgs);  // ← dispatcher genérico
}
```

`agent_ask_robot_b` **NÃO** está em `PROPOSE_ACTION_TOOL_NAMES` → cai no else → `callRpc` genérico.

`callRpc` (linhas ~290-302):
```js
const userClient = createClient(SUPABASE_URL, SUPABASE_ANON_KEY, {
  global: { headers: { Authorization: `Bearer ${userJwt}` } },
});
const { data, error } = await userClient.rpc(toolName, toolArgs);
```

→ `toolArgs` passa **directo** ao RPC. Adicionar `p_urgency` no tool def → Gemini popula → callRpc passa → RPC recebe automaticamente.

→ **NÃO precisa case explícito**. B2 é apenas **1 mudança** (não 2): só `buildFunctionDeclarations()`.

### c) Cliente Supabase no caminho `agent_ask_robot_b`

Nome: **`userClient`** (criado dentro de `callRpc`)
**Auth:** USER JWT (Bearer token do cliente final).
**NÃO usa** `adminClient` (service_role).

→ ⚠️ Implicação directa (ver A4.1): GRANT `service_role only` quebraria a tool.

---

## A3. AdminCrosstalkScreen actual (5F)

### Chamada RPC (`admin_crosstalk_screen.dart:67-74` + `:91-95`)

```dart
final data = await _supabase.rpc('admin_list_crosstalk', params: {
  'p_status': _statusFilter,
  'p_direction': _directionFilter,
  'p_limit': 100,
});
```

→ **NAMED params** ✅ → adicionar `'p_urgency': _urgencyFilter` é **plenamente compatível**. Sem migração obrigatória.

### Estrutura UI relevante

- `_statusFilter` / `_directionFilter`: state `String` + `PopupMenuButton` no `AppBar.actions`. Padrão para replicar para `_urgencyFilter`.
- `_pendingBadge`: int + Container colorido no AppBar title. Padrão para replicar para `_criticalCount` (banner topo).
- Card render: `_buildCard(Map ct)` em `:380-510`. Linha 397-422 tem Row com `dirBadge` + `status`. Inserir `urgency` badge nessa Row.
- Realtime subscription: já filtrada `status=eq.pending` (`:104-118`). Mantém-se em B3 — recarrega `_load()` + `_refreshBadge()` + (novo) recálculo `_criticalCount`.
- Banner topo: `_buildBanner()` em `:312-343` é **fixo** ("Modo observador 5F"). Podemos:
  - **Opção 1**: substituir banner fixo por banner dinâmico crítico se `_criticalCount > 0`, fallback ao banner observador.
  - **Opção 2**: mostrar banner crítico **acima** do banner observador.
  → Recomendo **Opção 2** (não esconder o aviso "modo observador" 5F).

---

## A4. Análise impacto

### A4.1 ⚠️ DECISÃO ARQUITECTURAL — GRANT `agent_ask_robot_b`

**Plano original 5F-α:**
> "MANTER GRANT service_role apenas (5F design)
>  NÃO adicionar auth.uid() check (service_role nunca tem auth.uid() — quebraria chamadas chatbot)"

**Realidade prod 5F:**
- `agent_ask_robot_b` GRANT = `authenticated + service_role`
- Chatbot v7 chama via `userClient` (USER JWT, role=authenticated) — **NÃO service_role**
- Comentário no código (linha ~217): "5B-α + 5B-β1: tools agent_propose_action* sao service_role only → adminClient. As outras tools (agent_get_*) usam user JWT + RLS via callRpc."
- `agent_ask_robot_b` está nas "outras tools" → user JWT path

**Se aplicarmos o plano original (REVOKE FROM authenticated; GRANT service_role only):**
- Chatbot v7 chamará via userClient → `permission denied` → tool falha → robô A não regista crosstalk → 5F partido em prod.

**Recomendação (Opção A — manter design 5F):**
- **Manter** GRANT `authenticated + service_role`.
- Anti-spam: já existe `rate_limit_per_user_day` em `support_settings` (chatbot enforça quota por user/dia). Bloqueio adicional em RPC seria duplicação.
- O "anti-spam" do plano é redundante se o cliente final só pode chamar via chatbot (via JWT user normal mas com quota global).

**Opção B — fazer REVOKE e migrar chatbot para `adminClient`:**
- Adicionar `agent_ask_robot_b` ao set `ADMIN_TOOLS` (ou novo) e usar `adminClient.rpc(...)`.
- Funciona, mas **mais cirurgia** no chatbot v7→v8 (3 mudanças em vez de 1).
- Sem ganho de segurança real (quota já existe).

**Opção C — apenas adicionar auth check sem mexer GRANT:**
- `agent_ask_robot_b` SECURITY DEFINER + `IF auth.uid() IS NULL AND current_setting('role') NOT LIKE '%service_role%' THEN RAISE`. Compatível com ambas roles.
- **Não pedido pelo plano**, mas deixa porta para chamadas directas via SDK authenticated (não-chatbot) sendo barradas a `service_role only` no futuro.

→ **Recomendo Opção A** (mais simples, zero risco).

### A4.2 Migrations / RPCs

- `20260506_5f_alpha_b1_urgency.sql`:
  - ALTER ADD COLUMN urgency text DEFAULT 'normal' CHECK IN (3 valores) NOT NULL
  - CREATE INDEX parcial críticas pendentes
  - CREATE OR REPLACE `agent_ask_robot_b` (5 args, sanitização inline; manter GRANT actual conforme A4.1 Opção A)
  - DROP + CREATE `admin_list_crosstalk` (4 args, novo col urgency em RETURNS TABLE, ORDER BY CASE)
  - UPDATE `support_skills` ASK_ROBOT_B playbook + version+1 + updated_at=now()
  - DO block validate ROW_COUNT=1 (skill update)

### A4.3 Edge Fn — apenas 1 mudança cirúrgica

`buildFunctionDeclarations()` tool `agent_ask_robot_b`: adicionar prop `p_urgency` (enum 3 valores). Dispatcher genérico não precisa alteração.

→ Re-deploy support-chatbot v7 → **v8** ACTIVE. Anotar SHA pré-deploy: **`7aee17d9…48f93e6`** (rollback).

### A4.4 Flutter

- Adicionar state `_urgencyFilter` + `_criticalCount`.
- Adicionar 4º `'p_urgency'` na chamada `_load()` + `_refreshBadge()`.
- Novo `PopupMenuButton<String>` urgência no AppBar.
- Novo `_buildUrgencyBadge(String)` widget.
- Novo banner crítico condicional (acima do banner observador 5F).
- Inserir badge urgência em `_buildCard`.

### A4.5 Riscos / Plano rollback

| Risco | Mitigação | Severidade |
|---|---|---|
| GRANT change quebra chatbot | A4.1 Opção A — não mexer GRANT | Eliminado |
| DROP+CREATE `admin_list_crosstalk` | Plano 2 DROPs (3-arg + 4-arg overloads); idempotent | Baixo |
| Flutter named params já existentes | A3 confirma compatível | Zero |
| SHA chatbot mudou após smokes | A0 captura SHA real `7aee17d9…48f93e6` | Baixo |
| Skill UPDATE atinge >1 row | DO block ROW_COUNT=1 hard-fail | Eliminado |
| BUG 35/38/39 regressão | 5F-α ortogonal | Zero |

**Rollback emergência:**
```sql
-- DB
ALTER TABLE robot_crosstalk DROP COLUMN urgency;
DROP INDEX IF EXISTS idx_crosstalk_urgency_critical;
-- recriar agent_ask_robot_b 5F (4 args)
-- recriar admin_list_crosstalk 5F (3 args, sem urgency em RETURNS)
UPDATE support_skills SET playbook_md='<5F playbook>', version=1
WHERE skill_name='ASK_ROBOT_B';

-- Edge Fn: redeploy v7 SHA 7aee17d9…48f93e6 via deploy_edge_function
```

---

## A5. Skill identification

Sem nova skill identificada durante Fase A (apenas leitura/audit).

---

## ⛔ DECISÕES PARA DANILO ANTES DE FASE B

### 1. GRANT `agent_ask_robot_b` — ⚠️ DECISÃO CRÍTICA

Plano original 5F-α dizia "service_role only". **Realidade prod = authenticated + service_role**, e chatbot v7 chama via user JWT.

| Opção | Acção | Custo | Risco |
|---|---|---|---|
| **A (recomendada)** | Manter GRANT actual | 0 mudanças extra | Zero |
| B | REVOKE auth + migrar chatbot p/ adminClient | +3 edits chatbot | Baixo |
| C | Adicionar guard interno SECURITY DEFINER + manter GRANT | +5 linhas RPC | Baixo |

**Recomendação:** Opção A.

### 2. Banner crítico topo — empilhar ou substituir?

| Opção | Comportamento |
|---|---|
| **2 (recomendada)** | Banner crítico **acima** do banner "Modo observador 5F" se `criticalCount>0` |
| 1 | Banner crítico **substitui** banner observador |

**Recomendação:** 2.

### 3. Aprovação granular (PROTECÇÃO TOTAL)

Peço luz verde **B1 isolado primeiro** (migration + 2 RPCs + skill update). Depois B2 (chatbot v8) e depois B3 (Flutter) — cada um com validação.

---

## A6. Resumo

| Item | Resposta |
|---|---|
| Skills total real | 21 (escalate=3, read=11, write_shadow=7) |
| SHA chatbot v7 | `7aee17d95b04a236672b05a1381a715926f6450e590914173318c18fe48f93e6` |
| `updated_at` em `support_skills` | ✅ EXISTE |
| Handler chatbot | **dispatcher genérico** via `callRpc(userJwt, ...)` |
| Flutter call `admin_list_crosstalk` | **NAMED params** ✅ |
| Skill ASK_ROBOT_B version actual | 1 → próxima 2 |
| GRANT `agent_ask_robot_b` real | authenticated + service_role (DIVERGE do plano) |

---

**Aguardo:**
- ✅ "go A4.1 Opção A + B1" para migration única (ou split por mudança)
- ⛔ ou correcção nas 3 decisões acima
