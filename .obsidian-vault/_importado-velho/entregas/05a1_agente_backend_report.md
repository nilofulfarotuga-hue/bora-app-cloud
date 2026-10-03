# Sessão 5A-1/7 — Agente IA Suporte: Backend Foundation

## Fase B — EXECUÇÃO BACKEND (Relatório)

**Data:** 2026-05-04
**Branch:** `autonomous-night-2026-04-29`
**Modelo:** claude-opus-4-7[1m]
**Modo:** PROTECÇÃO TOTAL — fase A audit + fase B backend, ambas aprovadas explicitamente

---

## ✅ Migrations aplicadas (8)

| # | Migration | Arquivo | Estado |
|---|-----------|---------|--------|
| B1 | `support_settings` (singleton id=1) | `20260504070000_5a1_support_settings.sql` | ✅ |
| B2 | `support_skills` | `20260504070100_5a1_support_skills.sql` | ✅ |
| B3 | `support_chatbot_sessions` | `20260504070200_5a1_support_chatbot_sessions.sql` | ✅ |
| B4 | `support_chatbot_messages` | `20260504070300_5a1_support_chatbot_messages.sql` | ✅ |
| B5 | `support_chatbot_quota` + `increment_chatbot_quota()` | `20260504070400_5a1_support_chatbot_quota.sql` | ✅ |
| B6 | `support_agent_actions` | `20260504070500_5a1_support_agent_actions.sql` | ✅ |
| B7 | ALTER `support_tickets` (+9 cols, CHECK, comments, backfill) | `20260504070600_5a1_alter_support_tickets.sql` | ✅ |
| B8 | 5 RPCs whitelisted | `20260504070700_5a1_agent_rpcs.sql` | ✅ |

**Total RLS policies criadas:** 12 (2 por tabela: select_own + modify_admin).

---

## ✅ Edge Functions deployed

| # | Slug | Version | verify_jwt | Status |
|---|------|---------|------------|--------|
| B9 | `support-chatbot` | v1 | true | ACTIVE |
| B10 | `support-submit-ticket` | v1 | true | ACTIVE |

---

## ✅ Ajustes aplicados (5 — descobertos via MCP audit)

1. **B8.3** wallet RPC usa `free_balance_cents` (não `balance_cents`).
2. **B8.4** tokens RPC: `expires_at` é NOT NULL → predicado simplificado para `expires_at > now()`.
3. **B8.4** tokens RPC: `is_used` é nullable → `COALESCE(is_used, false) = false`.
4. **B8.3** `RETURNS TABLE` removeu `promo_balance_cents` (col não existe; promo wallet 80/20 é 5B+).
5. **RLS policies:** `is_admin()` sem args (não `is_admin(auth.uid())`).

---

## 📊 Smokes resultado

### DB-side (validados via MCP) ✅

| Smoke | Resultado |
|-------|-----------|
| S1 — 6 tabelas novas existem | ✅ 6/6 |
| S2 — ALTER support_tickets +9 cols + CHECK channel | ✅ 9/9 + check |
| S3 — `support_settings` singleton id=1 | ✅ 1 row |
| S4 — Backfill `channel='chatbot'` | ✅ no-op (0 rows totais) |
| S5/S6 — RLS 12 policies + qual ownership | ✅ correcto |
| S7 — 6 RPCs SECURITY DEFINER, sem `p_user_id` | ✅ 6/6 |
| S7b — chamada sem auth → `NOT_AUTHENTICATED` | ✅ enforced |
| S11 — `increment_chatbot_quota` UPSERT atómico | ✅ ON CONFLICT presente |
| S12 — Edge Fn `support-chatbot` sem JWT → 401 | ✅ gateway rejeita |
| S13 — Edge Fn `support-submit-ticket` sem JWT → 401 | ✅ gateway rejeita |

### Regressão Sessões 1-4 ✅

| Smoke | Resultado |
|-------|-----------|
| S16 — coords NULL pós 2026-05-03 | ✅ 0 rows |
| S17 — `finalize_storeshopping_purchase` cap 5 sacos | ✅ source ok |
| S20 — `orders.extra_charge_settled_via` (Sessão 4 B3) | ✅ col existe |
| S21 — trigger `trg_zz_final_total_dual_write` (Sessão 4 B2) | ✅ enabled |
| S22 — namespace `messages` (operacional) isolado | ✅ |

### Diferidos para smoke produção (requer JWT real / UI)

| Smoke | Razão |
|-------|-------|
| S8/S9/S10 — RPCs com auth.uid() real | requer JWT user → smoke produção 5A-2 |
| S14 — `support-submit-ticket` rejeita `channel='chatbot'` | requer JWT real |
| S15 — prompt injection blocked | requer JWT real |
| S18/S19 — wallet free flows (cash + cartão) | requer `create_order` end-to-end |
| S23/S24 — BUG 35/38 UI Flutter | UI não tocada nesta sessão; presumivelmente intacta |

---

## 📋 Análise transversal

| Camada | Impacto |
|--------|---------|
| Cliente (UI) | nenhum (5A-2 add FAB) |
| Estafeta (UI) | nenhum |
| Parceiro (UI) | nenhum |
| Admin | apenas RLS policies preparadas; UI suporte em 5A-2 |
| DB | 8 migrations aditivas, zero conflito com tabelas existentes |
| Dispatch / Pricing / Stripe / Wallet RPCs | NÃO TOCADO |
| Triggers existentes (17 em orders) | NÃO TOCADO |
| ChatStore operacional (messages) | NÃO TOCADO (namespace separado) |

---

## 🛡️ Painel admin

- 12 RLS policies aplicadas — admin via `is_admin()` tem leitura/escrita global em tabelas suporte.
- RPC `admin_resolve_ticket(p_ticket_id, p_notes)` planeada para 5A-2 (com audit em `admin_notes`).
- UI lista admin de tickets é 5A-2.
- CRUD completo `support_skills` editor é 5B.

---

## 🐛 Bugs colaterais (REPORTADOS — não fixados)

- **BUG 39** — UUID/TEXT mismatch entre `messages.order_id`, `bora_tokens.source_order_id` e `orders.id`. Sessão 7 dedicada (`decisions/2026-04-29-restaurants-id-uuid-refactor.md`). Documentado em business_rules.md §32.1.
- **BUG 34/35/37** — relacionados §32.

---

## 🧠 Skills identificadas

**Nenhuma nova skill emergiu** durante Fase A/B. Registo formal em `.claude/skills/identified_during_5a1_NONE.md`. As 9 skills read-only aprovadas ficam para seed em 5A-2 B17.

---

## 📦 Sync Obsidian

- Audit Fase A → `Bora\entregas\05a1_agente_backend_audit.md` (SHA256 idem) ✅
- Relatório Fase B → `Bora\entregas\05a1_agente_backend_report.md` (este ficheiro)
- business_rules.md §31 + §32 → fonte única em `.claude/.ai/business_rules.md`

---

## ⏭ TODOs adiados

### 5A-2 (próxima sessão Flutter UI + skills seed)
- `BoraSupportFab`, `BoraSupportSheet`, `SupportChatScreen`, `SupportEmailFormScreen`
- Wrapper FAB nas 16+ screens enumeradas no prompt
- Seed 9 skills com playbooks markdown (consultar §31.7)
- Admin support_tickets list mínima + RPC `admin_resolve_ticket(p_ticket_id, p_notes)`
- Smokes diferidos S8/S9/S10/S14/S15/S18/S19 com JWT real

### 5B
- Skills WRITE: `UPDATE_DELIVERY_INSTRUCTIONS`, `UPDATE_DELIVERY_ADDRESS`, `ACCOUNT_UPDATE`, `PASSWORD_RESET`, `OTP_RESEND`, `FEEDBACK_SUGGESTION`
- Skills CANCEL shadow: `CANCEL_PRE_PURCHASE`, `CANCEL_DURING_PURCHASE`, `RESERVATION_CANCEL`, `PARTNER_REJECTED_ORDER`
- Skills MARKET: `MARKET_ITEM_UNAVAILABLE`, `MARKET_ITEM_ADDED`, `MARKET_PRICE_DIFFERENCE`
- Shadow approval workflow admin (4 semanas → auto)
- Resend/SMTP outbound email
- Push cliente quando admin responde ticket
- Admin FAQs CRUD (deprecar `support_screen.dart` hardcoded)
- Admin support_settings editor + métricas + custo Gemini estimado
- Tabela `support_channel_taps` (analytics WhatsApp/email taps)

### 5C
- Instalar pgvector
- RAG embeddings: business_rules + schemas + sessões
- Skills avançadas: `MISSING_ITEM`, `WRONG_ITEM`, `DAMAGED_ITEM`, `CASH_CHANGE_ISSUE`, `TOKENS_NOT_CREDITED`, `PAYMENT_ISSUE_DIAGNOSE`
- Learning loop (examples crescentes + thumbs feedback)

---

## ⚠️ Avisos prod

- `GEMINI_API_KEY` confirmada por Danilo em A7 (Supabase Edge Functions secrets).
- `support_agent_enabled=true` desde início — kill switch pronto. Para desligar:
  ```sql
  UPDATE support_settings SET support_agent_enabled=false WHERE id=1;
  ```
- 5A-1 é **backend only** — sem UI no app. Nenhum user vê impacto até 5A-2.
- Custo Gemini Flash: ~free tier 1500 req/dia. Monitorizar em 5B com métricas admin.

---

## ✅ Status final Fase B

🟢 **B1-B10 + smokes DB-side todos passam. Sessão fechada.**

🟡 **Diferido produção:** S8/S9/S10/S14/S15/S18/S19/S23/S24 — testar em 5A-2 com JWT/UI real.

⏭ **Próxima sessão:** 5A-2 (Flutter UI + skills seed + admin tickets list).
