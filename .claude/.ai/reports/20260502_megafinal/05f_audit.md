# Sessão 5F — Fase A · AUDIT (read-only)

**Data:** 2026-05-06
**Branch:** `autonomous-night-2026-04-29`
**Estado:** ⛔ STOP — aguarda luz verde Danilo para Fase B
**Pré-requisito:** 5E completo em prod (commits 5B → 5D → 5E)

---

## A0. Regressão check + numeração

| Métrica | Real | Esperado | Status |
|---|---|---|---|
| `support_skills` active total | **20** | 20-21 | ✅ |
| breakdown by mode | escalate=**2**, read_only=**11**, write_shadow=**7** | — | ℹ️ |
| `support_settings.rag_enabled` | true | true | ✅ |
| `support_knowledge_chunks` count | **534** | 534 | ✅ |
| `robot_crosstalk` table exists | **0** | 0 (a criar B1) | ✅ |
| skill `ASK_ROBOT_B` exists | **0** | 0 (a criar B2) | ✅ |
| function `_anonymize_pii` exists | **0** | 0 (a criar B1) | ✅ |
| `business_rules.md` última § | **§38** (5E) | §38 | ✅ → próxima §39 |

---

## A1. `match_knowledge` RPC (5C-α)

| Atributo | Valor |
|---|---|
| Args | `(query_embedding vector, match_count integer DEFAULT 5, min_similarity double precision DEFAULT 0.5)` |
| Returns | TABLE(id uuid, source_file text, source_type text, section_title text, chunk_text text, similarity double precision) |
| SECURITY DEFINER | true |
| GRANTs | postgres + authenticated + service_role |

✅ Reutilizável em `scripts/crosstalk/query_knowledge.ts` via SERVICE_ROLE_KEY.

---

## A2. `.claude/skills/` template

6 skills locais existem (todas `.claude/skills/<name>/SKILL.md`):

```
auto-rules-sync/SKILL.md
category-mapper-v2/SKILL.md
ceo-ai/SKILL.md
market-data-cleaner/SKILL.md
market-data-sync/SKILL.md
taxonomy-mapper/SKILL.md
```

Template usa frontmatter YAML + secções Markdown. `ask-knowledge-base/SKILL.md` em B4 seguirá mesmo padrão (descrição + triggers + uso).

---

## A3. `scripts/rag/.env` validation

✅ `.env` real existe + 3 keys obrigatórias presentes (mascaradas):

```
SUPABASE_URL=<masked>
SUPABASE_SERVICE_ROLE_KEY=<masked>
GEMINI_API_KEY=<masked>
```

`.env.example` lista as mesmas 3 keys. **Sem TODO Danilo** — scripts crosstalk podem assumir keys disponíveis.

---

## A4. ⚠️ DECISÃO ARQUITECTURAL — onde colocar tool

### Opção C (reuse `agent_create_ticket`) — INVIÁVEL ❌

`agent_create_ticket` NÃO existe no chatbot v6. Grep `create_ticket` retornou 0 matches. Eliminar.

### Opção A (editar support-chatbot v7) — RECOMENDADA ✅

**Estrutura real do chatbot v6** (SHA `eee616cc6555…`, 800+ linhas):

| Elemento | Localização | Notas |
|---|---|---|
| `TOOL_WHITELIST` Set | linhas 15-25 | 8 tools 5B/5B-β1 |
| `PROPOSE_ACTION_TOOL_NAMES` Set | linhas 27-32 | 4 shadow propose_* |
| `WRITE_SHADOW_ACTION_TYPES` Set | ~ | 5B action types |
| `buildFunctionDeclarations()` | linha 115 | Retorna array tool defs |
| `callRpc(userJwt, toolName, toolArgs)` | linha ~290 | Dispatcher genérico user JWT |
| Branching loop function calls | linha ~645 | `PROPOSE_ACTION_TOOL_NAMES` → adminClient; outras → `callRpc` |

### ⚠️ Padrão real ≠ plano original

**Plano dizia:**
- `case 'agent_ask_robot_b':` switch handler
- `GRANT EXECUTE TO service_role` only

**Real do chatbot v6:**
- NÃO tem switch case explícito — dispatch é **genérico** via `userClient.rpc(toolName, toolArgs)` (linha 302)
- 5 tools `agent_get_*` usam padrão **callRpc + user JWT**
- 4 tools `agent_propose_action*` usam padrão **adminClient + service_role** (porque inserem em `support_pending_actions` admin-only)
- Cross-check GRANTs DB: **TODAS** as 6 RPCs `agent_*` existentes têm GRANT TO `authenticated:EXECUTE + service_role:EXECUTE` (não só service_role)

### Recomendação revista B3

**Padrão A — `agent_ask_robot_b` segue convenção `agent_get_*` (callRpc + user JWT):**

- B1 GRANT EXECUTE TO **authenticated** (não só service_role)
- B1 SECURITY DEFINER + check interno `IF auth.uid() IS NULL THEN RAISE EXCEPTION 'NOT_AUTHENTICATED'`
- B3 mudanças no chatbot: **APENAS 2** (não 3 como plano):
  1. Adicionar `'agent_ask_robot_b'` ao `TOOL_WHITELIST` Set
  2. Adicionar tool def em `buildFunctionDeclarations()`
- **Sem switch case adicional** — dispatch genérico já existente fá-lo

**Robô B → A** (`robot_b_respond`): GRANT TO `service_role` only — chamado por scripts crosstalk via SERVICE_ROLE_KEY (não user-facing).

**Admin** (`admin_list_crosstalk`): GRANT TO `authenticated` + `is_admin()` check internal — observador na UI.

### Opção B (split sessão) — não preferida

Adia tool para 5F-β; deixa skill `ASK_ROBOT_B` seedada mas sem tool ⇒ Gemini chamaria tool não whitelistada ⇒ erro UX. **Eliminar Opção B.**

### Decisão proposta

**Opção A (modificada conforme padrão real do chatbot)** — todos os 4 itens (DB + skill + chatbot edit + scripts).

---

## A5. Análise impacto

### Migrations DB (2)

**B1** `20260506_5f_b1_robot_crosstalk`:
- `_anonymize_pii(text) RETURNS text` IMMUTABLE (helper reusable)
- `robot_crosstalk` tabela (PK uuid, RLS, 3 indexes parciais, realtime publication)
  - `session_id` FK → `support_chatbot_sessions(id)` **ON DELETE SET NULL** (proponho — não estava no plano)
- 3 RPCs SECURITY DEFINER:
  - `agent_ask_robot_b(question, session_id?, skill_triggered?, context?)` — GRANT authenticated; check `auth.uid() IS NOT NULL`; usa `_anonymize_pii`
  - `robot_b_respond(crosstalk_id, answer, rag_chunks?)` — GRANT service_role only
  - `admin_list_crosstalk(status?, direction?, limit?)` — GRANT authenticated; `is_admin()` check
- RLS policies: `admin_all` (is_admin), `service_role_all`

**B2** `20260506_5f_b2_seed_ask_robot_b_skill` (condicional Opção A):
- INSERT skill `ASK_ROBOT_B` (mode='escalate', allowed_tools=['agent_ask_robot_b'])

### Edge Fn (1, condicional Opção A)

`support-chatbot` v6 → **v7**:
- TOOL_WHITELIST: +1 entry
- buildFunctionDeclarations: +1 tool def
- Anotar SHA v6 `eee616cc6555…` antes do deploy (rollback redeploy v6)
- **NÃO precisa** alterar branching loop (linhas ~645) — `agent_ask_robot_b` segue caminho callRpc genérico

### Claude Code (4 ficheiros)

- `.claude/skills/ask-knowledge-base/SKILL.md`
- `scripts/crosstalk/query_knowledge.ts` (RAG via match_knowledge + Gemini embedding)
- `scripts/crosstalk/check_pending.ts` (lista a_to_b pending)
- `scripts/crosstalk/respond.ts` (chama robot_b_respond)

Todos com gate `SUPABASE_SERVICE_ROLE_KEY` (presente em A3).

### Flutter (1 ficheiro)

`lib/screens/admin/admin_crosstalk_screen.dart` (read-only observer, sem reply em 5F).

### Riscos

| Risco | Mitigação | Severidade |
|---|---|---|
| Edição prod chatbot v7 | SHA v6 anotado; rollback redeploy via `deploy_edge_function`; mudança cirúrgica (2 lines) | Baixo |
| `_anonymize_pii` PG vs Edge Fn JS drift | PG regex equivalente JS (5D); helper `IMMUTABLE` reusable | Baixo |
| `session_id` FK ON DELETE | Proponho `SET NULL` (não estava no plano) — preserva histórico crosstalk se sessão deletada | Baixo |
| Skill `HUMAN_REQUEST` (escalate) overlap | Documentar no playbook ASK_ROBOT_B: técnico **app behavior** vs HUMAN_REQUEST geral | Baixo |
| Cloudflare WAF blocks SQL keywords em smokes | Smokes usam strings limpas (sem palavras reservadas) | Baixo |
| `whatsapp_number`/`support_email` 5E CRITICAL não regridem | 5F é ortogonal | Zero |

### Plano rollback emergência

```sql
-- B1
DROP TABLE IF EXISTS public.robot_crosstalk CASCADE;
DROP FUNCTION IF EXISTS public.agent_ask_robot_b;
DROP FUNCTION IF EXISTS public.robot_b_respond;
DROP FUNCTION IF EXISTS public.admin_list_crosstalk;
DROP FUNCTION IF EXISTS public._anonymize_pii;

-- B2
DELETE FROM support_skills WHERE skill_name='ASK_ROBOT_B';

-- B3
-- Redeploy chatbot v6 (SHA eee616cc…) via deploy_edge_function
```

---

## A6. Skill identification

Nenhuma skill nova durante Fase A (apenas leitura).

---

## ⛔ DECISÕES PARA DANILO ANTES DE FASE B

1. **Opção A (modificada) vs B vs C** — Recomendo **Opção A modificada**:
   - Padrão `callRpc + user JWT` (não service_role)
   - GRANT TO authenticated (espelha 5B 6 agent_* RPCs)
   - Apenas 2 mudanças no chatbot (não 3) — sem switch case
   - Confirma?

2. **`session_id` FK ON DELETE SET NULL** — proposta minha, não no plano. Aceita?

3. **Aprovação granular** — peço luz verde **B1 isolado** primeiro (migration tabela + helper + 3 RPCs). Depois B2/B3/B4/B5.

---

**Aguardo:**

- ✅ "go B1" para migration `robot_crosstalk` + RPCs
- ⛔ ou correcções nas 3 decisões acima
