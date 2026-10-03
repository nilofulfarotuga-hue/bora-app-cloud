# Sessão 7-TS-AUDIT — Implementação

## A0 — Audit Findings

### Tabela completa: TS vs platform_settings prod

| Constante TS | Valor TS antes | platform_settings | Estado | Acção |
|---|---|---|---|---|
| `SLA_BASE_MINUTES` | 10 | — | TS-only | manter |
| `SLA_CHECK_AT_MINUTES` | 7 | — | TS-only | manter |
| `SLA_MAX_EXTENSION_MINUTES` | 5 | — | TS-only | manter |
| `NEAR_ENOUGH_DISTANCE_METERS` | 500 | — | TS-only | manter |
| `NEAR_ENOUGH_ETA_MINUTES` | 2 | — | TS-only | manter |
| `LOCAL_QUEUE_RADIUS_METERS` | 200 | — | TS-only | manter |
| `LOCAL_QUEUE_DWELL_SECONDS` | 5 | — | TS-only | manter |
| `BATCHING_RADIUS_KM` | 15 | — | TS-only | manter |
| `BATCHING_WAIT_WINDOW_MINUTES` | 3 | — | TS-only | manter |
| `BATCHING_TIME_TOLERANCE` | 1.20 | — | TS-only | manter |
| `TOKEN_MAX_DISCOUNT_RATIO` | 0.50 | — | TS-only | manter |
| `TOKEN_VALUE_EUR` | 0.005 | — | TS-only | manter |
| `TOKEN_EXPIRY_DAYS` | 60 | — | TS-only | manter |
| `DRIVER_HELP_COST_EUR` | 4.00 | — | TS-only | manter |
| `DRIVER_ADDITIONAL_ORDER_BONUS_EUR` | 3.00 | — | TS-only | manter |
| `DRIVER_ADDITIONAL_ORDER_TOKENS` | 50 | — | TS-only | manter |
| `WRONG_ADDRESS_FEE_EUR` | 2.00 | — | TS-only | manter |
| **`CANCEL_FEE_BEFORE_DISPATCH_EUR`** | **1.00** | **150 (€1.50)** | 🛑 **DESALINHADO** | **fix → 1.50** |
| `CANCEL_FEE_AFTER_ACCEPT_EUR` | 2.50 | — | TS-only | manter |
| `CANCEL_FEE_AFTER_PURCHASE_RATIO` | 1.00 | — | TS-only | manter |
| `PARTNER_COMMISSION_RATIO` | 0.10 | — | TS-only | manter |
| `PLATFORM_SERVICE_FEE_RATIO` | 0.05 | — | TS-only | manter |
| `PRODUCT_MARGIN_RATIO` | 0.05 | — | TS-only | manter |
| `NON_PARTNER_MARKUP_RATIO` | 0.15 | 0.15 | ✅ OK | manter |
| **`CASH_MAX_ORDER_VALUE_EUR`** | **30.00** | **4000c (€40)** | 🛑 **DESALINHADO** | **fix → 40.00** |

### Settings prod ausentes em TS

| Setting prod | Valor | Decisão |
|---|---|---|
| `bag_fee_supermarket_per_bag_cents` | 10 | ❌ não adicionar (Q5 NÃO) — TS não precisa |
| `max_extra_charge_pct` | 0.30 | ❌ não adicionar |
| `wallet_negative_enabled` | true | ❌ não adicionar |

---

## Q3 — Consumers de `CANCEL_FEE_BEFORE_DISPATCH_EUR`

| Edge Function | Linha | Tipo de uso |
|---|---|---|
| `client-cancel-order/index.ts` | 31 (import), 70 | **ACTIVO** — `case 'before_dispatch': return CANCEL_FEE_BEFORE_DISPATCH_EUR;` |
| `execute-cancellation/index.ts` | 23 (import), 52 | **ACTIVO** — função `feeEur(t, total)` retorna directo |
| `cancel-order-with-choice/index.ts` | 24 (import), 61 | **ACTIVO** — `case 'before_dispatch': return CANCEL_FEE_BEFORE_DISPATCH_EUR;` |
| `stripe-webhook/index.ts` | 4 (import), 11 | **DORMENTE** — `void CANCEL_FEE_BEFORE_DISPATCH_EUR;` (suppress unused-import) |

⚠️ **Confirmação extra:** comment em `stripe-webhook/index.ts:197`
já dizia `"1.50 EUR retained (CANCEL_FEE_BEFORE_DISPATCH_EUR)"` —
intenção sempre foi €1.50, só a constante TS estava desalinhada.

**Impacto runtime:** clientes que cancelam antes do dispatch passam
de €1.00 para €1.50 retidos. Alinhado com `platform_settings` prod
e com o comment já presente no webhook.

---

## A0.5 — Hardcoded €30 noutro código

| Local | Conteúdo | Acção |
|---|---|---|
| `lib/config/business_rules.dart:111` | `CASH_MAX_ORDER_VALUE_EUR = 40.00` (Dart) | ✅ já correcto |
| `lib/stores/order_store.dart:686-688` | usa `BRBusiness.CASH_MAX_ORDER_VALUE_EUR` (Dart) | ✅ indirecto correcto |
| `supabase/migrations/20260430110000_platform_settings.sql:53` | `('max_cash_amount_cents', '4000', ...)` | ✅ prod correcto |
| `business_rules.md §1057, §1078` | "Orçamento L4 €30" | ✅ ignorar — não é cash limit |
| `BUGS_FOUND.md:27,36` + obsidian | refs históricas ao bug | ✅ manter (registo) |

---

## Decisões registadas

- **Q1** ✅ Aplicado: `CASH_MAX_ORDER_VALUE_EUR = 40.00`.
- **Q2** ✅ Aplicado: `CANCEL_FEE_BEFORE_DISPATCH_EUR = 1.50`.
- **Q3** ✅ Verificado antes de Q2: consumers usam read-only para
  retornar fee — uso simples, sem cuidado extra necessário.
- **Q4** ✅ Aplicado: doc drift fixed em 4 ficheiros (9 ocorrências).
- **Q5** ❌ NÃO aplicado: constantes em falta no TS (`bag_fee`,
  `max_extra_charge`, `wallet_negative`) ficam fora — fora scope.

---

## Validação

```
flutter analyze: 55 issues (baseline preservada)
TS: Deno-based, sem build local. Compilação valida em deploy.
```

---

## Próximas pontas soltas (não tratadas — futuras sessões)

- Sessão `7-DOCS-SYNC` (sugerida): varrer todas as docs / .obsidian-vault
  por valores numéricos hardcoded e cross-refs com `platform_settings`.
- Considerar mover constantes TS-only relevantes (cancel fees, driver
  bonuses) para `platform_settings` — única source of truth.
