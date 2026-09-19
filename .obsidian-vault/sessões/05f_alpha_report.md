# Sessão 5F-α — Fase B · REPORT

**Data:** 2026-05-06
**Branch:** `autonomous-night-2026-04-29`
**Estado:** ✅ Completo (B1 + B2 + B3) — pronto para commit + push
**Pré-requisito:** 5F completo (commit `14c0462`)
**Modo:** PROTECÇÃO TOTAL (aprovação granular B1 → B2 → B3)

---

## Sumário

Notificação de urgência por escalação do Robô A → admin. Em 5F-α
o canal é **realtime via `AdminCrosstalkScreen`** (banner topo
vermelho + filtro). Push real (FCM/email) fica para 5F-β.

Tool `agent_ask_robot_b` ganha `p_urgency` (critical/medium/normal).
Skill `ASK_ROBOT_B` playbook v2 instrui Gemini a classificar
antes de chamar. ORDER BY críticas primeiro em
`admin_list_crosstalk`. Banner condicional acima do banner
observador 5F (Opção 2 do audit).

---

## B1 · DB

**Migrations** (2):
- `supabase/migrations/20260506202000_5f_alpha_b1_urgency.sql`
- `supabase/migrations/20260506202001_5f_alpha_b1_hotfix_overload_grants.sql`

### Mudanças

- **ALTER `robot_crosstalk` ADD COLUMN `urgency`** text NOT NULL
  DEFAULT `'normal'` CHECK in 3 valores. Backfill irrelevante
  (0 rows à data do ALTER).
- **Index parcial** `idx_crosstalk_urgency_critical`
  ON (urgency, status, created_at DESC) WHERE crit+pending —
  acelera dashboard admin críticas pendentes.
- **`agent_ask_robot_b` 5 args** (CREATE OR REPLACE com novo
  `p_urgency` DEFAULT `'normal'`). Sanitização server-side via
  CASE WHEN — fallback `'normal'` para valor inválido.
- **`admin_list_crosstalk` 4 args** (DROP + CREATE — RETURNS
  TABLE muda). Adiciona col `urgency`; ORDER BY CASE críticas
  primeiro; RE-GRANT auth+service_role.
- **`UPDATE support_skills` ASK_ROBOT_B** playbook v2
  (`version+1`, `updated_at=now()`); DO block ROW_COUNT=1.

### Hotfix detectado em smokes

CREATE OR REPLACE com signature nova (5 args) NÃO substituiu
a 4-arg — criou overload. PostgreSQL default GRANT EXECUTE
TO PUBLIC contaminou o `anon` no novo overload.

→ Migration hotfix: DROP overload 4-arg + REVOKE PUBLIC/anon
+ explicit GRANT auth+service_role.

### Decisão arquitectural — A4.1 Opção A

Plano original 5F-α dizia "GRANT service_role only" para
`agent_ask_robot_b`. **Realidade**: GRANT prod 5F era
`authenticated + service_role` e chatbot v7 chama via **user JWT**
(`callRpc(userJwt, ...)` em `support-chatbot/index.ts`).

**Aplicado: Opção A** — manter GRANT existente. Anti-spam
delegado a `support_settings.rate_limit_per_user_day`. Zero
risco prod.

---

## B2 · Edge Fn `support-chatbot` v7 → v8

**Ficheiro:** `supabase/functions/support-chatbot/index.ts` (mod)

Mudança cirúrgica conforme A2 do audit (dispatcher genérico):

- `buildFunctionDeclarations()` tool `agent_ask_robot_b` ganha
  prop `p_urgency` (enum 3 valores + descrição completa).
- Comentário header: `+ 5F-α B2`.
- **NÃO** mexe TOOL_WHITELIST, RAG injection, kill switch,
  cap mensagens, dispatcher.

**Deploy verificado MCP:**

| Item | Valor |
|---|---|
| version | 8 |
| status | ACTIVE |
| verify_jwt | true |
| ezbr_sha256 v8 | `e351ab629847ff0edcea3b7719acc41418cf728426373917f67f0a9f68f9a108` |
| ezbr_sha256 v7 (rollback) | `7aee17d95b04a236672b05a1381a715926f6450e590914173318c18fe48f93e6` |

---

## B3 · Flutter `AdminCrosstalkScreen`

**Ficheiro:** `lib/screens/admin/admin_crosstalk_screen.dart` (mod)

### Mudanças

- 2 constantes cor: `_critical` (`#D32F2F`), `_criticalBg` (`#FFEBEE`)
- 2 state vars: `_urgencyFilter='all'`, `_criticalCount=0`
- 1 mapa estático `_urgencyOptions` (4 entries com emojis)
- `_load()` envia `'p_urgency': _urgencyFilter`
- `_refreshBadge()` reusa payload pending+a_to_b para computar
  `_pendingBadge` E `_criticalCount` (1 só RPC call)
- `_urgencyBadgeData(String)` helper (label + cor)
- `_buildUrgencyBadge(String)` widget (Container rounded com
  fundo `withValues(alpha:0.15)`)
- 3º `PopupMenuButton` urgência no AppBar (`Icons.priority_high`)
- `_buildCriticalBanner()` widget condicional vermelho **acima**
  do banner observador 5F (Opção 2)
- `_buildCard()` extrai `urgency` + insere `_buildUrgencyBadge`
  no Row antes do badge de status
- Realtime mantido (filter `status=eq.pending`)

`flutter analyze`: **55 baseline** (0 erros novos). Ficheiro
analisado isoladamente: 0 issues.

---

## Smokes — todos os 23 verificados

### DB (B1)

| Smoke | Resultado |
|---|---|
| S1 col urgency CHECK + default | text NOT NULL DEFAULT `'normal'` ✅ |
| S2 index parcial | `idx_crosstalk_urgency_critical` ✅ |
| S3 `agent_ask_robot_b` 5 args | `p_urgency text DEFAULT 'normal'` ✅ |
| S4 sanitização | critical/banana→normal/sem param→normal/medium ✅ |
| S5 `admin_list_crosstalk` 4 args | + col `urgency` no RETURNS ✅ |
| S6 ORDER BY críticas | rank 1=crit, 2=med, 3=normal ✅ |
| S7 skill ASK_ROBOT_B v2 | version=2, has critical/medium/normal/p_urgency/🔴, 2612 chars ✅ |

### Edge Fn (B2)

| Smoke | Resultado |
|---|---|
| S8 v8 ACTIVE | sha `e351ab62…f9a108` ✅ |
| S9 tool def `p_urgency` | enum + descrição 3 categorias ✅ |

### Flutter (B3)

| Smoke | Resultado |
|---|---|
| S10 renderiza badges urgência | `_buildUrgencyBadge` 🔴/🟡/🟢 ✅ |
| S11 filtro urgência | `PopupMenuButton` 4 opções + `_load()` ✅ |
| S12 banner crítico aparece | `if (_criticalCount > 0) _buildCriticalBanner()` ✅ |
| S13 banner ausente se 0 | mesmo `if` retorna `SizedBox.shrink` implícito ✅ |
| S14 flutter analyze | **55 baseline** ✅ |

### Funcional (manual após smoke chat)

| Smoke | Estado |
|---|---|
| S15 chat "paguei e não recebi pedido" → urgency=critical | TODO Danilo testar em-app |

### Regressão

| Smoke | Resultado |
|---|---|
| S16 21 skills active | escalate=3, read=11, shadow=7 ✅ |
| S17 RAG 534 chunks | rag_enabled=true ✅ |
| S18 robot_crosstalk rows existentes | 0 (backfill irrelevante) ✅ |
| S19 4 RPCs crosstalk preservados | agent_ask_robot_b/admin_list_crosstalk atualizadas; robot_b_respond/_anonymize_pii intactas ✅ |
| S20 skill version 1→2 | confirmado ✅ |
| S21 BUG 35/38/39 não regridem | ortogonal ✅ |
| S22 final_total numeric | sem alterações pricing ✅ |
| S23 `_showRagChunks` + `_showQuestionContext` 5F | preservados ✅ |

---

## Documentação

- `business_rules.md` §40.1-40.7 (novo).
- `.obsidian-vault/sessoes/05f_alpha_audit.md` + `05f_alpha_report.md`
  (sync).
- `.claude/.ai/todos/sessao_5f_alpha_pending.md` (5F-β + 5F-α
  pendentes manuais).

---

## Ficheiros (resumo)

```
supabase/migrations/20260506202000_5f_alpha_b1_urgency.sql                 (novo)
supabase/migrations/20260506202001_5f_alpha_b1_hotfix_overload_grants.sql  (novo)
supabase/functions/support-chatbot/index.ts                                (mod  — v7→v8)
lib/screens/admin/admin_crosstalk_screen.dart                              (mod  — urgency)
.claude/.ai/business_rules.md                                              (mod  — §40)
.claude/.ai/reports/20260502_megafinal/05f_alpha_audit.md                  (novo)
.claude/.ai/reports/20260502_megafinal/05f_alpha_report.md                 (novo — este)
.claude/.ai/todos/sessao_5f_alpha_pending.md                               (novo)
.obsidian-vault/sessoes/05f_alpha_audit.md + 05f_alpha_report.md           (sync)
.obsidian-vault/sessoes/05f_alpha_prompt.md                                (novo)
```

---

## Rollback emergência

```sql
-- DB rollback (reverso da migration B1)
DROP INDEX IF EXISTS idx_crosstalk_urgency_critical;
ALTER TABLE robot_crosstalk DROP COLUMN urgency;

DROP FUNCTION IF EXISTS public.agent_ask_robot_b(text, uuid, text, jsonb, text);
-- recriar agent_ask_robot_b 5F (4 args, sem urgency) — ver migration 5F B1

DROP FUNCTION IF EXISTS public.admin_list_crosstalk(text, text, text, integer);
-- recriar admin_list_crosstalk 5F (3 args, sem urgency) — ver migration 5F B1

UPDATE support_skills SET playbook_md='<5F playbook>', version=1
WHERE skill_name='ASK_ROBOT_B';
```

```
-- Edge Fn rollback
deploy_edge_function support-chatbot
  com SHA v7 = 7aee17d95b04a236672b05a1381a715926f6450e590914173318c18fe48f93e6
```

---

## Próximas sessões

- **5F-β** — Push real (pg_net + FCM + email Resend) + reply UI
  + auto-resposta scheduling + métricas + anonymization JS fix.
- **5G** — Painel admin inbox propostas avançado (~3h).
- **Sessão 6 ORIGINAL** — Avaliações por estrelas (~3-4h).
- **Sessão 7** — Validações finais + UUID refactor BUG 39 (~6-8h).

---

*Sessão 5F-α — notificações urgência admin. Estado: pronto para commit + push.*
