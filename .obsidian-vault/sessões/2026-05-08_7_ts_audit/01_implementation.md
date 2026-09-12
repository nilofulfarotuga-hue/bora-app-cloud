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
| `stripe-webhook/index.ts` | 4 (import), 11 | **DORMENTE** — `void CANCEL_FEE_BEFORE_DISPATCH_EUR;` (suppress) |

⚠️ Comment em `stripe-webhook:197` já dizia `"1.50 EUR retained"` —
intenção sempre foi €1.50, só a constante TS estava desalinhada.

**Impacto runtime:** clientes que cancelam antes do dispatch passam
de €1.00 para €1.50 retidos (alinhado com prod).

---

## Decisões registadas

- **Q1** ✅ `CASH_MAX_ORDER_VALUE_EUR = 40.00`.
- **Q2** ✅ `CANCEL_FEE_BEFORE_DISPATCH_EUR = 1.50`.
- **Q3** ✅ Verificado consumers — uso simples, sem cuidado extra.
- **Q4** ✅ Doc drift fixed em 4 ficheiros (9 ocorrências).
- **Q5** ❌ Constantes em falta no TS — fora scope.

---

## Próximas pontas soltas

- Sessão `7-DOCS-SYNC` (sugerida): varrer todas as docs por valores
  numéricos hardcoded e cross-refs com `platform_settings`.
- Considerar mover constantes TS-only (cancel fees, driver bonuses)
  para `platform_settings` — única source of truth.
