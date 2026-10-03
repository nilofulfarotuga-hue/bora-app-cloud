# 05d_audit — Auto-Suggest Cron Skills Novas (Fase A)

**Sessão:** 5D/7
**Data:** 2026-05-06
**Branch:** `autonomous-night-2026-04-29`
**Modo:** PROTECÇÃO TOTAL — STOP após A5
**MCP project_id:** `ojykpzwqrtusfeakzrna`

---

## A0 — Estado actual + gates infra

### Skills (20 active após 5B)

| Mode | Count |
|---|---|
| `escalate` | 2 |
| `read_only` | 11 |
| `write_shadow` | 7 |

### Infra

| Item | Estado |
|---|---|
| `support_settings.rag_enabled` | `true` |
| `support_knowledge_chunks` | **534** |
| Extensions `pg_cron` + `pg_net` | ✅ 2/2 |
| RPC `match_knowledge` | ✅ existe |
| RPC `is_admin()` | ✅ existe |
| Tabela `skill_suggestions` | ❌ NÃO existe (criar em B1) |
| Cron `analyze-conversations-weekly` | ❌ NÃO existe (criar em B4) |
| 16 cron jobs preexistentes | intactos |

### ⚠️ Gate crítico: pg_net settings NULL

```sql
current_setting('app.supabase_url', true)        -> NULL
current_setting('app.service_role_key', true)    -> MISSING
```

**Implicação:** o cron `analyze-conversations-weekly` será registado mas
**falhará silenciosamente** até `ALTER DATABASE SET app.supabase_url=...`
e `app.service_role_key=...` em prod (TODO histórico já documentado em
§36.10 Limitações conhecidas).

**Mitigação:** botão "🔄 Analisar Agora" em B5 funciona via JWT do admin
(não usa pg_net), permitindo análises manuais imediatas mesmo com cron
inactivo.

### business_rules.md numeração

Última secção numerada: §36.15 (5B-β2b). **Próxima disponível: §37**.

---

## A1 — Schema mensagens/sessões/settings

### `support_chatbot_messages` (read-only para 5D)

| Coluna | Tipo |
|---|---|
| `id` | uuid |
| `session_id` | uuid |
| `role` | text (`user`/`assistant`/`tool`) |
| `content` | text |
| `tool_name` | text |
| `tool_input` | jsonb |
| `tool_output` | jsonb |
| `tokens_used` | int |
| `created_at` | timestamptz |

### `support_chatbot_sessions` (read-only)

Inclui `escalated boolean`, `escalation_reason text`, `ended_at timestamptz`,
`active_skill text` ✓ (5D usa para priorizar mensagens escaladas).

### `support_settings`

⚠️ NÃO contém `last_skill_analysis_at` nem `skill_analysis_min_messages`
→ ALTER em B1.

### Tráfego actual

```sql
SELECT count(*) FROM support_chatbot_messages
WHERE role='user' AND created_at > now() - INTERVAL '7 days';
-- 0
```

Pré-launch — sugestões reais começam pós-tráfego. Smoke S12 vai testar
caminho `below_threshold`.

---

## A2 — Gemini quotas

- `GEMINI_API_KEY` em secrets (chatbot v6 usa-a com sucesso).
- gemini-1.5-flash limite gratuito: 15 RPM / 1M TPM / 1500 RPD.
- 5D consumo: 1 chamada/semana via cron + chamadas manuais (rate-limited
  1/h em B3) → folga muito grande.
- Risco de spam manual mitigado por rate limit no Edge Fn.

---

## A3 — Dedup semântico vs textual

### Estado

- `support_skills.playbook_md` **NÃO** está em `support_knowledge_chunks`
  (chunks 5C-α só indexam Obsidian/business_rules/knowledge).
- Dedup semântico real exigiria primeiro embedar e indexar todos os
  playbooks como `source_type='skill'` e depois usar `match_knowledge`.

### Decisão (5D textual)

- `pattern_hash = SHA256(pattern_summary.toLowerCase().trim())`
- `UNIQUE(pattern_hash, status)` na `skill_suggestions`
- INSERT `ON CONFLICT DO NOTHING` previne duplicatas no estado `pending`
- Antes de chamar Gemini: pre-load `skill_name` (active) + `pattern_summary`
  (pending) → injectar no prompt como "NÃO repetir" → previne duplicatas
  semânticas iniciais
- **Dedup semântico via embeddings adiado para 5D-β** (TODO).

---

## A4 — Análise transversal: impacto + riscos

### Riscos

**🟡 MÉDIO 1 — pg_net settings NULL.** Cron registado mas inactivo.
Mitigação: análise manual via botão. TODO permanece (já existia desde
5B-β1).

**🟢 BAIXO 2 — Quota Gemini.** 1/semana cron + 1/h manual → folga
ampla. Sem risco.

**🟢 BAIXO 3 — PII em mensagens.** Anonimização regex no Edge Fn antes
do Gemini (email/phone/uuid/numbers). Limitação documentada (regex
simples; library GDPR adiada).

**🟢 BAIXO 4 — Aditivo.** Não toca `support-chatbot`, skills existentes,
ou outros sistemas. Risco regressão muito baixo.

**🟡 MÉDIO 5 — Aprovação cria skill activa imediatamente.** Admin tem
de rever playbook antes. Mitigação: editor multiline 10-rows obrigatório
no dialog de aprovação.

**🟢 BAIXO 6 — `pattern_hash` colisão.** SHA256 colisão astronómica;
UNIQUE(pattern_hash, status) garante constraint mesmo em colisão.

### Impacto

- **Migrations:** 1 tabela (`skill_suggestions`) + RLS + 2 indexes +
  realtime publication + 2 cols em `support_settings` + 3 RPCs + 1 cron
- **Edge Fn:** 1 nova `analyze-conversations`
- **Flutter:** 1 screen nova `AdminSkillSuggestionsScreen` + rota +
  link no menu admin
- **Documentação:** §37 (5 sub-secções) + sync Obsidian

---

## A5 — Skill identification + plano Fase B

### Skills/artefactos identificados

Nenhum helper além do plano original. Todos os artefactos B1-B5 já
contemplados.

### Plano Fase B (após luz verde)

| Bloco | Acção |
|---|---|
| **B1** | Migration `20260506_5d_b1_skill_suggestions` — tabela + RLS + indexes + realtime + 2 cols em `support_settings` |
| **B2** | Migration `20260506_5d_b2_skill_suggestion_rpcs` — 3 RPCs (admin_approve / admin_reject / admin_list) |
| **B3** | Edge Fn nova `analyze-conversations` v1 — admin check, rate limit 1/h, dry_run, anonimização PII regex, Gemini 1.5 Flash, parse robusto, INSERT ON CONFLICT |
| **B4** | Migration `20260506_5d_b4_cron_analyze_conversations` — `cron.schedule` semanal segundas 04:00 UTC (inactivo até pg_net config) |
| **B5** | Flutter `AdminSkillSuggestionsScreen` — banner cron status, botão "Analisar Agora" rate-limited, lista cards, aprovação editor markdown, rejeição motivo, realtime badge, link menu admin |
| Smokes | S1–S27 (DB + Edge Fn + Flutter + regressão) |
| Docs | business_rules §37.1-37.6 |

### Decisões pendentes (luz verde Danilo)

| # | Item | Proposta |
|---|---|---|
| D1 | pg_net settings NULL | Aceitar — cron inactivo até config; análise manual via botão funciona; TODO permanece em §37.6 |
| D2 | Dedup textual (SHA256 pattern_hash) | Aceitar para 5D; semântico embeddings adiado para 5D-β |
| D3 | Anonimização PII regex | Aceitar para 5D; library GDPR (Microsoft Presidio etc.) adiada para 5D-β |
| D4 | Threshold mínimo mensagens | `skill_analysis_min_messages = 5` (default; admin pode editar) |
| D5 | Numeração BR | §37.1-37.6 (5D dedicada) |
| D6 | Editor playbook | TextField multiline 10 rows, monospace; markdown avançado adiado |

---

## ⛔ STOP — aguardar luz verde Danilo

Decisões pendentes: **D1–D6**. Risco principal: D1 (pg_net settings).
Sem confirmação, não prossigo Fase B.
