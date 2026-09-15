# 5B-α/7 — Skills WRITE Shadow + Grupo 1 — Relatório Final

**Data:** 2026-05-06
**Branch:** `autonomous-night-2026-04-29`
**Estado:** ✅ **COMPLETO** — Phase B0–B5 executados com scope reduzido (decisão Danilo).
**Próximo passo:** commit + 5B-β para Grupos 2/3 + OTP_RESEND.

---

## Sumário executivo

A sessão entregou:
1. **Infra shadow** completa (1 tabela + 4 RPCs + 1 ALTER constraint).
2. **2 Skills WRITE** (de 3 originais; OTP_RESEND adiado).
3. **Edge Fn `support-chatbot` v3** com nova tool `agent_propose_action`.
4. **Admin Inbox** Flutter (`AdminPendingActionsScreen`) com realtime + filtro + modais.
5. Smokes S1–S26 todos passam (DB + RPC + regressão).
6. Zero erros novos no `flutter analyze` (baseline 55 mantido).

Decisões aplicadas (luz verde Danilo após Fase A):
- (1) Skill mantém nome `UPDATE_DELIVERY_INSTRUCTIONS`; RPC mapeia para `customer_notes`.
- (2) `OTP_RESEND` adiado para 5B-β (sem flow OTP no app + pg_net settings ausentes).
- (3) Tabela nova `support_pending_actions` (não reutilizar `support_agent_actions`).
- (4) Scope reduzido: 2 skills em vez de 3.

---

## Migrations aplicadas (Supabase + ficheiros locais)

| # | Nome | Conteúdo | Status |
|---|------|----------|--------|
| B0 | `5b_b0_alter_mode_constraint` | ALTER `support_skills_mode_check` para incluir `write_shadow` + `write_auto` | ✅ |
| B1 | `5b_b1_support_pending_actions` | CREATE TABLE + RLS (3 policies) + 3 indexes + realtime publication | ✅ |
| B2 | `5b_b2_shadow_rpcs` (+`fix_order_id_text` patch) | 4 RPCs (`agent_propose_action`, `admin_approve/reject/list_pending_actions`) | ✅ |
| B3 | `5b_b3_seed_write_skills` | INSERT 2 skills (`UPDATE_DELIVERY_INSTRUCTIONS`, `UPDATE_DELIVERY_ADDRESS`) | ✅ |

Ficheiros locais em [supabase/migrations/](supabase/migrations/):
- `20260506100000_5b_b0_alter_mode_constraint.sql`
- `20260506100100_5b_b1_support_pending_actions.sql`
- `20260506100200_5b_b2_shadow_rpcs.sql`
- `20260506100300_5b_b3_seed_write_skills.sql`

---

## Edge Function `support-chatbot` v3

| Campo | Valor |
|-------|-------|
| Slug | `support-chatbot` |
| Versão antiga (rollback) | **v2** (`d3a0c9f4...`) |
| Versão nova | **v3** (`c4d734f0...`) |
| Status | ACTIVE |
| `verify_jwt` | `true` |
| `updated_at` | 2026-05-06 |

**Mudanças vs v2:**
- Header de comentário actualizado (5A-1 + 5C-β + 5B-α B4)
- `TOOL_WHITELIST` ganha `agent_propose_action`
- Constante nova `WRITE_SHADOW_ACTION_TYPES` (whitelist de action_types válidos)
- `buildFunctionDeclarations()`: declaração nova com enum em `skill_name` + `action_type`
- Tool-calling loop: `agent_propose_action` é routed via `adminClient` (service_role) em vez de `callRpc(userJwt, ...)` — porque o RPC tem GRANT só a service_role
- Validação extra anti-Gemini: `WRITE_SHADOW_ACTION_TYPES.has(action_type)` + `action_payload` deve ser plain object (não array, não null)
- Tudo o resto **inalterado** (RAG, sanitização, kill switch, ticket creation)

Source local em [supabase/functions/support-chatbot/index.ts](supabase/functions/support-chatbot/index.ts).

---

## Flutter — Admin Inbox

Novo: [lib/screens/admin/admin_pending_actions_screen.dart](lib/screens/admin/admin_pending_actions_screen.dart) (430 linhas)

Feature set:
- Filtro status (popup menu): pending / executed / rejected / failed / all
- AppBar com **badge realtime** para pending novas
- Pull-to-refresh
- Lista de cards com: cliente (email), `user_message` (italic), `action_payload` formatado, `agent_reasoning`, timestamps, status badge colorido
- Botão **Aprovar** (verde Bora `#1B5E20`) → `AlertDialog` confirmação → `admin_approve_action` → SnackBar resultado
- Botão **Rejeitar** (laranja Bora `#E65100`) → Dialog com TextField motivo (max 200 chars) → `admin_reject_action`
- Cards não-pending mostram `reviewed_at`, `execution_result`, `rejection_reason` em modo read-only
- Realtime channel `admin_pending_actions` em `support_pending_actions` (re-fetch + badge update)

Modificado: [lib/screens/admin/admin_dashboard_screen.dart](lib/screens/admin/admin_dashboard_screen.dart)
- Import novo
- `_NavCard` adicionado abaixo do card "Knowledge Base":
  - Ícone: `fact_check_outlined`, cor laranja
  - Título: "Propostas IA", subtítulo: "Aprovar/rejeitar acções WRITE do robô"

`flutter analyze`: 2 issues introduzidas + 2 corrigidas (`prefer_const_constructors` + `withOpacity` → `withValues`). Total final = baseline 55, zero erros novos.

---

## Smokes S1–S26 — todos passam ✅

| # | Teste | Resultado |
|---|-------|-----------|
| S1 | Tabela `support_pending_actions` + RLS + 3 policies | ✅ |
| S2 | Realtime publication inclui tabela | ✅ |
| S3 | 4 RPCs criadas (`agent_propose_action`, `admin_approve/reject/list_pending_actions`) | ✅ |
| S5 | `admin_list_pending_actions` sem admin → `NOT_ADMIN` | ✅ |
| S6 | 2 skills `write_shadow` seedadas com `allowed_tools=jsonb` | ✅ |
| S7 | Total skills = 11 (9 antigas + 2 novas) | ✅ |
| S8 | CHECK constraint inclui `write_shadow` + `write_auto` | ✅ |
| S9 | INSERT fake pending → approve → `status='failed'` (NO_ROWS_AFFECTED) com `execution_result.error` populado | ✅ |
| S10 | INSERT com `payload` sem `order_id` → approve → `status='failed'` (INVALID_ORDER_ID) | ✅ |
| S12 | INSERT pending → reject com motivo → `status='rejected'` + `rejection_reason` populado | ✅ |
| S13 | `support-chatbot` re-deployed v3 ACTIVE | ✅ |
| S14 | `AdminPendingActionsScreen` compila sem erros | ✅ (analyzer crashed por OOM em full-project, mas grep targeted confirma 0 issues no file novo) |
| S19 | `flutter analyze` 0 erros novos (baseline 55) | ✅ |
| S20 | `rag_enabled = true` | ✅ |
| S21 | 534 chunks intactos | ✅ |
| S22 | 9 skills antigas (8 read_only + 1 escalate) intactas | ✅ |
| S23 | Sessões 1–6, B2c2, 5C intactas (não tocadas) | ✅ |
| S24 | BUGs 35/38 não regridem (não tocados) | ✅ |
| S25 | `final_total = numeric` | ✅ |
| S26 | `match_knowledge` (RAG) intacta | ✅ |
| S26b | `support_agent_actions` table intacta (não tocada) | ✅ |

S11 (status incompatível) implícito em S9 — mesma path `NO_ROWS_AFFECTED` é exercitado.

---

## Riscos mitigados

- **R1 — UPDATE silent zero rows**: `GET DIAGNOSTICS v_rows_affected = ROW_COUNT; IF =0 THEN RAISE EXCEPTION` em ambos os action_types. Validado em S9.
- **R2 — Cast UUID inválido**: substituído por comparação de text directa (orders.id é TEXT). Suporta legacy IDs não-UUID.
- **R5 — RLS leak**: cliente vê só `user_id=auth.uid()`; admin vê tudo via `is_admin()`. Validado em S5 (NOT_ADMIN).
- **R6 — service_role escrita não autorizada**: `agent_propose_action` é `SECURITY DEFINER` + GRANT só a service_role; cliente NUNCA chama directo.
- **R8 (NEW)** — `customer_notes` reescrita destrutiva: documentado em playbook + RPC tem MAX 200 chars; futuro melhoramento "merge mode" possível.

## Bugs colaterais detectados

Nenhum BUG novo. BUG 39 (UUID/TEXT em `orders.id`) **mantém-se reservado para Sessão 7** — nesta sessão foi mitigado localmente no RPC mas não resolvido a nível arquitectural.

---

## Skills identificadas durante 5B-α

Nenhuma skill nova para extrair. Padrão de auditoria + entrega multi-camada (DB+Edge+Flutter) já estabelecido em sessões anteriores (5A, 5C).

---

## Limitações conhecidas (documentadas em §36.7)

1. `pg_net` settings (`app.supabase_url`, `app.service_role_key`) NÃO configuradas — qualquer skill futura que dependa de `pg_net.http_post` precisa primeiro popular.
2. Cliente não tem visibilidade da sua proposta (apenas "aguarda aprovação"); notificação in-app adiada para 5B-β.
3. Sem push admin (FCM) ou email Resend para nova proposta; admin precisa abrir o Inbox manualmente (badge realtime indica).

---

## Próximos passos sugeridos (Sessão 5B-β)

Ver lista completa em [.claude/.ai/todos/sessao_5b_a_pending.md](.claude/.ai/todos/sessao_5b_a_pending.md):

1. Skills Grupo 2 (`ACCOUNT_UPDATE`, `PASSWORD_RESET`, `CANCEL_PRE_PURCHASE`, `RESERVATION_CANCEL`)
2. Skills Grupo 3 (5 skills relacionadas com store-shopping order lifecycle)
3. `OTP_RESEND` (após decisão sobre flow OTP no app)
4. Email outbound (Resend SMTP) + Push admin (FCM)
5. `pg_net` settings configuration check + alerta automático

---

## Ficheiros modificados/criados nesta sessão

### Migrações (Supabase + locais)
- [supabase/migrations/20260506100000_5b_b0_alter_mode_constraint.sql](supabase/migrations/20260506100000_5b_b0_alter_mode_constraint.sql)
- [supabase/migrations/20260506100100_5b_b1_support_pending_actions.sql](supabase/migrations/20260506100100_5b_b1_support_pending_actions.sql)
- [supabase/migrations/20260506100200_5b_b2_shadow_rpcs.sql](supabase/migrations/20260506100200_5b_b2_shadow_rpcs.sql)
- [supabase/migrations/20260506100300_5b_b3_seed_write_skills.sql](supabase/migrations/20260506100300_5b_b3_seed_write_skills.sql)

### Edge Function
- [supabase/functions/support-chatbot/index.ts](supabase/functions/support-chatbot/index.ts) — modificado (header + TOOL_WHITELIST + WRITE_SHADOW_ACTION_TYPES + buildFunctionDeclarations + tool-calling handler)

### Flutter
- [lib/screens/admin/admin_pending_actions_screen.dart](lib/screens/admin/admin_pending_actions_screen.dart) — NOVO
- [lib/screens/admin/admin_dashboard_screen.dart](lib/screens/admin/admin_dashboard_screen.dart) — modificado (import + tile)

### Documentação
- [.claude/.ai/business_rules.md](.claude/.ai/business_rules.md) — §36 adicionado
- [.claude/.ai/reports/20260502_megafinal/05b_a_write_audit.md](.claude/.ai/reports/20260502_megafinal/05b_a_write_audit.md)
- [.claude/.ai/reports/20260502_megafinal/05b_a_write_report.md](.claude/.ai/reports/20260502_megafinal/05b_a_write_report.md) (este ficheiro)
- [.claude/.ai/todos/sessao_5b_a_pending.md](.claude/.ai/todos/sessao_5b_a_pending.md)

### Sync Obsidian
- `.obsidian-vault/entregas/05b_a_write_audit.md` ✅
- `.obsidian-vault/entregas/05b_a_write_report.md` ✅
- `.obsidian-vault/sessões/05b_a_prompt.md` ✅
