# 05b_b2a_audit — Skills WRITE Cancelamentos Avançados (Fase A)

**Data:** 2026-05-06
**Branch:** `autonomous-night-2026-04-29`
**Último commit:** `12ff6e0` (5B-β1)
**Modo:** PROTECÇÃO TOTAL — STOP após A10
**MCP project_id:** `ojykpzwqrtusfeakzrna`

---

## A0 — Regressão check + contagens reais

### Skills (`support_skills`) — total 14

| Mode | Count | Skills |
|---|---|---|
| `escalate` | 1 | HUMAN_REQUEST |
| `read_only` | 8 | APP_TROUBLESHOOTING, GENERAL_FAQ, ORDER_HISTORY, ORDER_STATUS, REFUND_STATUS, TOKENS_INFO, WALLET_BLOCKED_HELP, WALLET_INFO |
| `write_shadow` | 5 | ACCOUNT_UPDATE, CANCEL_PRE_PURCHASE, PASSWORD_RESET, UPDATE_DELIVERY_ADDRESS, UPDATE_DELIVERY_INSTRUCTIONS |

✅ Confirma: 5B-α (3 write_shadow: UPDATE_DELIVERY_INSTRUCTIONS, UPDATE_DELIVERY_ADDRESS, CANCEL_PRE_PURCHASE) + 5B-β1 (2 write_shadow: PASSWORD_RESET, ACCOUNT_UPDATE) = 5 ✓

### `support_pending_actions` status CHECK

```
CHECK ((status = ANY (ARRAY['pending'::text, 'executed'::text, 'failed'::text, 'rejected'::text])))
```

⚠️ NÃO inclui `dispatched` → **ALTER necessário em B1**.

### support-chatbot v4 ACTIVE

- `slug = support-chatbot`, `version = 4`, `verify_jwt = true`
- `sha256 = eef9b8d2fddc41187d726742decffe661d5e1a5f58dc37d24e2e494511832d10`
- Snapshot pré-deploy registado (rollback target: v4).

---

## A1 — Schema `reservations`

| Coluna | Tipo | Nulo |
|---|---|---|
| `id` | uuid | NO |
| `created_at` | timestamptz | NO |
| `restaurant_id` | text | NO |
| `client_user_id` | uuid | NO |
| `client_name` | text | NO |
| `client_phone` | text | NO |
| `people` | int | NO |
| `reserved_for` | timestamptz | NO |
| `notes` | text | YES |
| `status` | text | NO |
| `prepayment_cents` | int | NO |
| `prepayment_pi` | text | YES |
| `decided_at` | timestamptz | YES |
| `arrived_at` | timestamptz | YES |
| `cancelled_at` | timestamptz | YES |
| `cancel_reason` | text | YES |

⚠️ **CORRECÇÃO PROMPT** — campo é **`reserved_for`** (NÃO `scheduled_at`) e **`client_user_id`** (NÃO `user_id`). B2 RESERVATION_CANCEL precisa adaptar nomes.

---

## A2 — RPCs reservation existentes

São **6 RPCs**, NÃO 7 como o prompt indica:

| Nome | Args | SECURITY DEFINER |
|---|---|---|
| `admin_reservations_metrics` | `p_days int DEFAULT 30` | ✓ |
| `admin_reservations_today` | — | ✓ |
| `auto_close_no_show_reservations` | — | ✓ |
| `client_cancel_reservation` | `p_reservation_id uuid, p_reason text DEFAULT NULL` | ✓ |
| `client_confirm_reservation_payment` | `p_reservation_id uuid` | ✓ |
| `partner_decide_reservation` | `p_reservation_id uuid, p_accept boolean, p_reason text DEFAULT NULL` | ✓ |

⚠️ NÃO existe `cancel_reservation` plain. Existe `client_cancel_reservation`.

### `client_cancel_reservation` — análise (admin pode usar?)

**RESPOSTA: NÃO directamente.** A RPC tem owner check:

```sql
IF v_rsv.client_user_id != v_uid THEN RAISE EXCEPTION 'not_your_reservation'; END IF;
```

`v_uid := auth.uid()` retorna o admin → fail.

Lógica interna (já implementada e segura):
- Lê `reservation_cancel_window_hours` de `platform_settings` (fallback 2)
- Calcula `v_diff_h = EXTRACT(EPOCH FROM (reserved_for - NOW())) / 3600`
- `will_refund = (v_diff_h >= v_window_h)`
- Marca status `cancelled_refunded` ou `cancelled_no_refund`
- Push notification + log audit
- Retorna `prepayment_pi` para "caller (Edge Fn refund) refunds Stripe"

⚠️ **GAP**: Stripe refund NÃO é feito pela RPC. Hoje quem chama é o cliente via UI; o refund Stripe é responsabilidade do caller (Edge Fn). Para skill admin precisamos:

**Opção A (recomendada):** RPC nova `admin_cancel_reservation_on_behalf_of(p_reservation_id, p_user_id, p_reason)` SECURITY DEFINER, sem owner check, idêntica semanticamente à `client_cancel_reservation` mas auditada como acção admin.
**Opção B:** Edge Fn nova `admin-cancel-reservation` (admin JWT → RPC nova → Stripe refund se will_refund → notify).

---

## A3 — Settings reserva

Tabela: `platform_settings` (key/value jsonb).

```
reservation_cancel_window_hours = 2
reservation_prepayment_cents = 300
reservation_partner_payout_cents = 200
reservation_bora_service_cents = 100
reservation_credit_expiry_days = 30
reservation_no_show_grace_minutes = 60
```

⚠️ **NÃO existem chaves para taxa cancel_during_purchase**. As taxas estão hardcoded no `stripe-webhook` (1.50€ / 50% / 100%) e na BR §8.3 (€1 / €2.50 / 100%) — **valores divergentes** (reportar GAP).

---

## A4 — `admin-cancel-order` Edge Fn

- `slug = admin-cancel-order`, `version = 2`, `verify_jwt = true`
- Auth: `app_metadata.role === 'admin'` (NÃO JWT bora_role)
- Body: `{ order_id, reason_code, reason }` (todos obrigatórios)
- `order_id` validado contra UUID regex puro
- `reason_code` ∈ `{client_request, partner_unable, driver_unavailable, payment_failed, fraud_suspected, address_invalid, food_quality_issue, system_error, other}`
- Internamente: `userClient.rpc('admin_cancel_order')` → Stripe refund se `payment_intent_id` + `total > 0` → notify-client/notify-driver/notify-partner → audit log
- Retorna: `{ success, idempotent, refund: {result, stripe_id, amount, error}, notifications }`

✅ Para CANCEL_DURING_PURCHASE → reason_code = `client_request`.

---

## A5 — Schema `orders` cancellation fields

| Coluna | Existe |
|---|---|
| `cancellation_reason` | ❌ NÃO |
| `cancelled_at` | ✅ |
| `cancelled_by` | ✅ (uuid) |
| `refund_amount` | ✅ (double precision) |
| `refund_status` | ✅ (text) |
| `cancellation_fee` | ❌ NÃO |
| `payment_buffer_total` | ✅ |
| `status` | ✅ |

Reason vai para `admin_audit_log.details.reason_code` via `admin-cancel-order`.

---

## A6 — `business_rules.md` numeração + taxa cancel_during

Total: 1808 linhas.

### Estrutura §35–§36

- §35 RAG (5C-β) — §35.1–§35.7
- **§36 AGENTE IA WRITE Shadow** (5B-α/β1) — §36.1–§36.10
- ⚠️ **§36.10 já está OCUPADO** (= "Limitações conhecidas"). O prompt diz "atualizar §36.10 no fim" mas isso destrói as Limitações.

**Plano numeração revisto:**
- Manter §36.10 = Limitações conhecidas (actualizar conteúdo)
- Adicionar §36.11 = Skills Grupo 3a (5B-β2a)
- Adicionar §36.12 = Pattern EXTERNAL_DISPATCH_REQUIRED

### Taxa cancel_during_purchase — BR §8.3 (linha 376)

| Momento | Taxa BR §8.3 |
|---|---|
| Antes do estafeta aceitar (`callingDriver`) | **€1,00** |
| Estafeta a caminho do restaurante (`driverAccepted`) | **€2,50** |
| Estafeta já tem comida/compras (`pickedUp`/`onTheWay`) | **100%** (sem reembolso) |

⚠️ **GAP** vs stripe-webhook hardcoded constants:
- `CANCEL_FEE_BEFORE_DISPATCH_EUR = 1.50` (≠ €1 em BR)
- `CANCEL_FEE_AFTER_ACCEPT_RATIO = 0.5` (≠ €2.50 fixo em BR)
- `CANCEL_FEE_AFTER_PURCHASE_RATIO = 1.0` (= 100% ✓)

Para playbook CANCEL_DURING_PURCHASE: NÃO mencionar valor exacto (admin decide). Só "taxa possível conforme BR §8.3".

### Janela de cancelamento reserva — INCONSISTÊNCIA

- §12.3 (linha 524): "**Até 4 horas antes:** reembolso total / Menos de 4 horas: perde €3"
- §18.3 (linha 1122): "`reservation_cancel_window_hours = 2` / ≥2h refund / <2h Bora 100%"
- DB `platform_settings = 2` (fonte da verdade)

➡️ Skills usarão **2h** (DB). Reportar a Danilo: §12.3 desactualizada.

---

## A7 — `admin_approve_action` v3 (5B-β1)

WHEN clauses actuais:
1. `UPDATE_DELIVERY_INSTRUCTIONS` — UPDATE orders.customer_notes (status NOT IN delivered/cancelled/pickedUp/onTheWay)
2. `UPDATE_DELIVERY_ADDRESS` — UPDATE orders.dropoff_address + reset coords (status IN created/preparing)
3. `ACCOUNT_UPDATE` — UPDATE users.name/phone (defesa anti-FORBIDDEN_FIELD)
4. `PASSWORD_RESET` — `net.http_post` para `support-password-reset` Edge Fn
5. `CANCEL_PRE_PURCHASE` — **`RAISE EXCEPTION 'EXTERNAL_DISPATCH_REQUIRED'`** ← capturado pelo handler global → status='**failed**' (inconsistente com pattern proposto `dispatched`)

⚠️ **REFACTOR NECESSÁRIO** em B2:
- Adicionar variável local `v_dispatch_target text` ao DECLARE
- Mudar handler `CANCEL_PRE_PURCHASE` actual: trocar `RAISE EXCEPTION` por `v_target_status := 'dispatched'; v_dispatch_target := 'admin-cancel-order'; v_result := jsonb_build_object(...)`
- Mudar UPDATE final para incluir `dispatch_target = v_dispatch_target, dispatched_at = CASE WHEN v_target_status='dispatched' THEN now() ELSE dispatched_at END`
- ⚠️ **Risco regressão**: AdminPendingActionsScreen actual provavelmente trata `failed` com mensagem de erro `'EXTERNAL_DISPATCH_REQUIRED'` no execution_result — verificar Flutter durante B5.

`admin_finalize_action(p_action_id, p_status, p_result, p_reason)` ✓ existe (5B-β1). Pode ser reutilizado no lugar de criar `admin_mark_action_dispatched`. **DECISÃO RECOMENDADA**: usar `admin_finalize_action` em vez de criar nova RPC; poupa 1 migration.

`is_admin()` ✓ existe.

---

## A8 — support-chatbot v4 audit

```typescript
WRITE_SHADOW_ACTION_TYPES = {
  'UPDATE_DELIVERY_INSTRUCTIONS',
  'UPDATE_DELIVERY_ADDRESS',
  'CANCEL_PRE_PURCHASE',
  'PASSWORD_RESET',
  'ACCOUNT_UPDATE',
}
```

Tools (9 totais; limite 4 propose mantido):
- 5 read: `agent_get_user_orders_summary, agent_get_order_status, agent_get_user_wallet_summary, agent_get_user_tokens_summary, agent_get_refund_status`
- 4 propose: `agent_propose_action` (genérico, enum [UPDATE_DELIVERY_INSTRUCTIONS, UPDATE_DELIVERY_ADDRESS]), `agent_propose_action_cancel` (enum [CANCEL_PRE_PURCHASE]), `agent_propose_action_password`, `agent_propose_action_account`

**Para B4 (v5):** estender `agent_propose_action` (genérico) com `CANCEL_DURING_PURCHASE` + `RESERVATION_CANCEL` no enum action_type/skill_name. Adicionar ambos ao `WRITE_SHADOW_ACTION_TYPES`. **NÃO** criar tools novas (mantém limite 4).

Alternativa considerada: estender `agent_propose_action_cancel` com CANCEL_DURING_PURCHASE (mesma família). Rejeitado: prompt diz seguir genérico para ambos.

---

## A9 — Análise transversal: impacto + riscos

### 🔴 RISCOS CRÍTICOS (decisão Danilo necessária)

**R1 — RPC `cancel_reservation` não existe como prompt assume.**
- Realidade: `client_cancel_reservation` rejeita admin com `not_your_reservation`.
- Solução: criar **RPC nova** `admin_cancel_reservation_on_behalf_of(p_reservation_id, p_user_id, p_reason)` SECURITY DEFINER, sem owner check, mesma semântica.
- Custo: +1 migration.

**R2 — Stripe refund da reserva não está integrado end-to-end.**
- `client_cancel_reservation` retorna `prepayment_pi` mas NÃO chama Stripe.
- Solução: Edge Fn nova **`admin-cancel-reservation`** (admin JWT → RPC nova → Stripe refund se will_refund → notify). Espelha admin-cancel-order.
- Custo: +1 Edge Fn + Stripe SDK + cors + audit.

**R3 — Refactor `admin_approve_action` mais profundo que o prompt indica.**
- Handler `CANCEL_PRE_PURCHASE` actual usa `RAISE EXCEPTION` (cai em `failed`). Pattern novo precisa `dispatched`.
- Risco regressão: AdminPendingActionsScreen pode estar a interpretar `execution_result.error='EXTERNAL_DISPATCH_REQUIRED'` (status=failed) — vai partir.
- Mitigação: refactor cuidadoso + smoke test S6 com fluxo CANCEL_PRE_PURCHASE existente.

### ⚠️ RISCOS MÉDIOS

**R4 — Inconsistência §12.3 (4h) vs §18.3/DB (2h).** Skills usam 2h. Reportar.
**R5 — Numeração §36.10 já ocupada** ("Limitações conhecidas"). Plano: §36.11 + §36.12.
**R6 — Schema `reservations` usa `reserved_for` + `client_user_id`** (NÃO `scheduled_at`/`user_id`). Adaptar B2.
**R7 — `orders.id` é TEXT mas admin-cancel-order exige UUID.** Cast `(payload->>'order_id')::uuid` falha em IDs legados não-UUID.
**R8 — Taxa cancel_during_purchase divergente** (BR §8.3 vs stripe-webhook). Playbook NÃO menciona valor exacto.
**R9 — `admin_finalize_action` já existe** — usar em vez de criar `admin_mark_action_dispatched` (poupa 1 migration).
**R10 — RPCs reservation são 6** (NÃO 7 como prompt diz).

### ⚠️ RISCOS BAIXOS

**R11 — pg_net não configurado em prod** (`app.supabase_url`/`service_role_key` NULL). Não bloqueia 5B-β2a porque novo pattern usa Flutter dispatch (não pg_net).

---

## A10 — Skills identificadas + decisões pendentes

### Novos artefactos NÃO previstos no prompt original

1. **RPC `admin_cancel_reservation_on_behalf_of`** (R1) — necessária para Flutter dispatch funcionar.
2. **Edge Fn `admin-cancel-reservation`** (R2) — necessária para Stripe refund da reserva.

### Decisões arquitecturais propostas (luz verde Danilo)

| # | Item | Proposta | Alternativa |
|---|---|---|---|
| D1 | RPC dispatch tracker | Reutilizar `admin_finalize_action` | Criar `admin_mark_action_dispatched` (prompt) |
| D2 | Cancelar reserva como admin | Nova RPC + nova Edge Fn (R1+R2) | Adaptar `admin_approve_action` para chamar RPC + Stripe directo via `net.http_post` |
| D3 | Tools chatbot | Estender `agent_propose_action` genérico (prompt) | Estender `agent_propose_action_cancel` com CANCEL_DURING_PURCHASE |
| D4 | Numeração BR | §36.11 + §36.12 (manter §36.10 = Limitações) | Renumerar Limitações → §36.13 |
| D5 | Janela reserva | Skills usam 2h (DB) + reportar §12.3 | — |
| D6 | Taxa cancel_during | Playbook não menciona valor; "admin decide" | Hardcode BR §8.3 (€1/€2.50/100%) |

### Plano Fase B revisto (após luz verde)

- **B0 (NOVO):** RPC `admin_cancel_reservation_on_behalf_of` + Edge Fn `admin-cancel-reservation` (cobre R1+R2).
- **B1:** ALTER status CHECK + colunas `dispatch_target`/`dispatched_at`.
- **B2:** EXTEND `admin_approve_action` (refactor CANCEL_PRE_PURCHASE pattern + 2 novos WHEN). Reutilizar `admin_finalize_action`.
- **B3:** Seed 2 skills (CANCEL_DURING_PURCHASE + RESERVATION_CANCEL).
- **B4:** support-chatbot v5 (extend WRITE_SHADOW_ACTION_TYPES + enums).
- **B5:** AdminPendingActionsScreen — detectar `dispatched`, dispatch para `admin-cancel-order` ou `admin-cancel-reservation`, finalizar com `admin_finalize_action`.

---

## ⛔ STOP — aguardar luz verde Danilo

Decisões pendentes: **D1–D6**.

Sem luz verde sobre R1+R2 (RPC + Edge Fn novas para reserva), **NÃO posso prosseguir** porque o prompt original não cobre estes itens.
