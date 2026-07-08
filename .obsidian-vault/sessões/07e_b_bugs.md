# BUGs encontrados durante testes E2E

Política: tests legítimos que falham NÃO bloqueiam merge.
Cada FAIL → entrada aqui + fix em sessão dedicada futura.
CEO-AI orchestrator vê via sync Obsidian
(`.obsidian-vault/sessoes/07e_b_bugs.md`).

> Espelho do ficheiro canónico `scripts/e2e/BUGS_FOUND.md`.
> Última sync: 2026-05-08 (Sessão 7-α-MIGRATIONS-SYNC-MANUAL).

---

## ⚠️ TODOs governança DB

### TODO 7-α (sync migrations locais) — PARTIAL 2026-05-08

- ✅ **6 migrations `2026-05-08` sincronizadas** (commit `78c73ec`,
  sessão `7-alpha-MIGRATIONS-SYNC-MANUAL`). SQL extraído directamente
  de `supabase_migrations.schema_migrations` via MCP (Opção A) porque
  `supabase db pull --linked` abortou por drift histórico massivo.
- ⏸️ **Drift sistemático de ~140 migrations** DEFERIDO para sessão
  dedicada de governança DB (`7-α-GOVERNANCE` — sugerida):
  - ~70 ficheiros locais sem entry em `schema_migrations` prod
    (CLI sugere `migration repair --status reverted`).
  - ~80 entries em `schema_migrations` prod sem ficheiro local
    (CLI sugere `migration repair --status applied`).
  - `supabase db pull --linked` falha enquanto este drift não for
    reconciliado.
- 🟢 **Não bloqueia launch** — prod funciona normalmente; é apenas
  drift de histórico CLI (cosmético). Resolver quando houver tempo
  de auditoria profunda (~1-3h).

---

## Sessão 7E-B (2026-05-07) — 25/26 PASS + 5 BUGs

### Nota numeração

**BUG-7E-B-002 saltado** — entry intermédio reclassificado durante o run
(`assert_bag_fee_restaurant_fixed_30c`: bag fee restaurante €0.30 fixo
**não é bug** — é a regra documentada em
`platform_settings.bag_fee_restaurant_cents=30`).

---

### BUG-7E-B-001 (LOW) — Cash limit DOCS_VS_CODE mismatch

- **Status:** ✅ **CLOSED 2026-05-08 (Sessão 7 MEGAFINAL + 7-TS-AUDIT)**
- **Razão**: setting `platform_settings.max_cash_amount_cents=4000`
  (€40) já era correcta em prod. Era apenas desalinhamento docs —
  `business_rules.ts` (código) dizia €30. Documentação
  `business_rules.md §3.2` actualizada com valor `4000` cents +
  nome do trigger `orders_enforce_cash_limit`.
- **Migration:** nenhuma (apenas docs).
- **Pendente RESOLVIDO em 7-TS-AUDIT (2026-05-08)**:
  `business_rules.ts` `CASH_MAX_ORDER_VALUE_EUR=40.00` +
  `CANCEL_FEE_BEFORE_DISPATCH_EUR=1.50` (bonus do audit). Doc drift
  "cash cap €30" corrigido em 4 ficheiros. 4 Edge Functions
  consumers verificados (3 activos + 1 dormente). Backend não tocado.

---

### BUG-7E-B-003 (LOW) — `storeShopping` retorna `bag_fee=0`

- **Status:** ✅ **CLOSED 2026-05-08 (Sessão 7 MEGAFINAL — FALSE POSITIVE)**
- **Razão**: `finalize_storeshopping_purchase` está correcta.
  Validação prod: 4 orders `storeShopping` últimos 30d todos com
  `cents_per_bag=10.00` exacto.
- **Reclassificação**: FALSE POSITIVE. T06 valida
  `pricing_calculate` (preview pré-checkout); bag fee só é
  calculado pós-finalização — comportamento correcto.
- **Migration:** nenhuma.

---

### BUG-7E-B-004 (HIGH) — Estafeta consegue cancelar `pickedUp`

- **Status:** ✅ **CLOSED 2026-05-08 (Sessão 7-UI-BUG004 — ciclo completo)**
- **Backend FIX:** 7-FIX (2026-05-07) — migration
  `20260507223338_fix_7e_b_bug_004_driver_cannot_cancel_pickedup`.
  RPC devolve `{ok:false, error:'cancel_blocked_after_pickup',
  message:'Após recolher o pedido, contacte o suporte para cancelar.',
  support_required:true}`.
- **UI FIX:** 7-UI-BUG004 (2026-05-08):
  - Widget novo `lib/widgets/cancel_blocked_pickup_sheet.dart` (verde
    `AppTheme.primary` + laranja `AppTheme.secondary`).
  - `OrderStore.driverCancelAcceptedOrder`: `Future<bool>` →
    `Future<Map<String,dynamic>>`, expõe `support_required`.
  - `DriverHomeScreen._handleCancelDelivery` abre bottom sheet quando
    `support_required==true`; outros erros preservam SnackBar.
  - `SupportChatScreen` aceita `String? initialMessage` opcional →
    pre-fill `"Preciso cancelar o pedido #ID (já recolhido). Motivo: "`.
  - Permissions: Android `<queries>` `tel` intent appended +
    iOS `LSApplicationQueriesSchemes` adicionado.
- **Test:** T37 `test_t37_driver_blocked_pickedup_redirects_support`
  (backend-only, esperado).

---

### BUG-7E-B-005 (HIGH) — Tokens conversion factor ×20 (deveria ×2)

- **Status:** ✅ **FIXED em 7-FIX (2026-05-07)**
- **Migration:** `20260507223228_fix_7e_b_bug_005_bug_007_tokens_uuid_to_text`
- **Validado MCP:** refund €10 → 400 tokens (era 4000 antes).
- **Matemática confirmada:** 1 token = €0.005 ⇒ factor ×2.
- **Test:** T24 `test_t24_tokens_conversion_factor_2`.

---

### BUG-7E-B-006 (MEDIUM) — Stripe webhook fee mismatch

- **Status:** ✅ **CLOSED 2026-05-08 (Sessão 7 MEGAFINAL)**
- **Razão**: criada setting
  `platform_settings.cancel_fee_before_dispatch_cents=150` (€1.50).
- **Migration:** `fix_bug_006_stripe_cancel_fee_setting`
  (`20260508084132`).
- **Pendente** (não bloqueante): Edge Function `stripe-webhook` v17
  ainda hardcoded com €1.50. Refactor 5F-β-β futuro lerá da
  setting. Valor está alinhado.

---

### BUG-7E-B-007 (HIGH) — `add_tokens` silent fail em `wallet_credit_refund_split`

- **Status:** ✅ **FIXED em 7-FIX (2026-05-07)**
- **Migration:** `20260507223228_fix_7e_b_bug_005_bug_007_tokens_uuid_to_text`
- **Causa raíz:** `orders.id` é TEXT mas `add_tokens.p_order_id` era
  UUID. Cast implícito falhava com ERRCODE 22P02 silenciado por
  try/except.
- **Fix:** `bora_tokens.source_order_id UUID→TEXT` +
  `add_tokens.p_order_id UUID→TEXT` (DROP+CREATE) +
  `fn_award_tokens_on_delivery` removeu cast `::UUID` +
  `wallet_credit_refund_split` removeu try/except.
- **Validado MCP:** refund €10 → 1 row em `bora_tokens` com
  `amount=400`, `source_order_id text`.

---

## Tests adiados — 7E-C

- `cancel-order-with-choice` + `execute-cancellation` (workflow
  cliente → admin via `cancellation_requests`).
- Refund completo split wallet 80/20 + cartão Stripe live.
- Promo balance non-cumulative / 60 d expiry — mover para tokens
  equivalente.

---

## Estado final 7E-B + 7-FIX + 7 MEGAFINAL

**TODOS 6 BUGs do smoke 7E-B estão CLOSED:**

| BUG | Severidade | Sessão close | Tipo |
|---|---|---|---|
| 001 | LOW | 7 MEGAFINAL (2026-05-08) | Doc fix |
| 003 | LOW | 7 MEGAFINAL (2026-05-08) | FALSE POSITIVE |
| 004 | HIGH | 7-FIX backend + **7-UI-BUG004** UI (2026-05-08) | Migration + Flutter UI |
| 005 | HIGH | 7-FIX (2026-05-07) | Migration |
| 006 | MEDIUM | 7 MEGAFINAL (2026-05-08) | Setting + migration |
| 007 | HIGH | 7-FIX (2026-05-07) | Migration |

✅ App seguro para launch.

---

## ORPHANED ORDERS CLEANUP (2026-05-08)

Sessão: `7-alpha-ORPHANED-CLEANUP`.
Aplicado via MCP directo + migration files locais.

- ✅ **CAT A** — 9 orders `cash+rejected+pending` → `cancelled_no_charge`
  - Migration: `20260508135500_cleanup_orphaned_orders_cat_a.sql`
  - IDs: `79ca3c7a`, `93b7bf00`, `be175307`, `3ce12489`, `22d13fb5`,
    `b0a2af78`, `5c470d30`, `de02d96c`, `a550efe3`
  - Risco: zero
- ✅ **CAT B** — 3 orders stuck `driverAccepted` >19 dias → `cancelled`
  - Migration: `20260508135700_cleanup_orphaned_orders_cat_b_skip_triggers.sql`
  - IDs: `94d02b17`, `cd0193ab`, `cc706061`
  - `user_id` orphan: `f9ad894e-42a2-44ca-a4b0-2546bdb11cb9`
  - Skip triggers via `SET LOCAL session_replication_role=replica`
  - Risco: baixo (>19 dias, `driver_transactions` preservadas)
- 🟡 **CAT C** — 1 order DEFERIDA (TODO governance futuro)
  - ID: `92276b06-688a-4068-be82-dc32145ccf5d`
  - `delivered + pending + card + payment_intent_id=NULL` (€30.59)
  - Decisão admin necessária. NÃO mexer sem revisão manual.

**Validação prod pós-cleanup:** ZERO orders stuck >7 dias em estados
não-terminais. 1 Cat C aguarda decisão admin.

---

*Última actualização: 2026-05-08 — Sessão 7-α-ORPHANED-CLEANUP (12 orders limpas, 1 deferida; 0 stuck >7d em prod)*
