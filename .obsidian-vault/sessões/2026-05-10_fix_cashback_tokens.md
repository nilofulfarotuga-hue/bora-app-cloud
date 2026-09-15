---
date: 2026-05-11
session: fix-cashback-and-tokens-read
branch: autonomous-night-2026-04-29
project: bora_app
type: bugfix
tags:
  - wallet
  - tokens
  - cashback
  - migration
  - bug-7e-b-007-closed
---

# Sessão 2026-05-10 → 2026-05-11 — Cashback 1% removido + Tokens read fix

## TL;DR

- **BUG 1** — Cashback 1% indevido a creditar em qualquer pedido entregue → **trigger + função + setting removidos**.
- **BUG 2** — Tokens "0" na UI apesar de 748 na DB → **`wallet_get_balance` corrigida** (tratava `INTEGER` como JSONB) + 4 call sites Flutter com cast tolerante.
- **BUG-7E-B-005** (×20) → likely-fixed (reconfirmado).
- **BUG-7E-B-007** (add_tokens silent fail) → **CLOSED** (era leitura, não escrita).
- **Sem backfill, sem estorno** (decisão Danilo).

## Migration aplicada

`supabase/migrations/20260510120000_fix_cashback_remove_and_tokens_read.sql`
→ `mcp apply_migration` → `{"success":true}`

## Re-validação (post-fix)

| Campo | Esperado | Obtido |
|---|---|---|
| `wallet_get_balance('c9fccf85')->>'tokens_balance'` | `"748"` | ✅ `"748"` |
| triggers `trg_award_cashback` | 0 | ✅ 0 |
| function `fn_award_cashback_on_delivery` | 0 | ✅ 0 |
| setting `cashback_pct` | 0 | ✅ 0 |

## Ficheiros tocados

- `supabase/migrations/20260510120000_fix_cashback_remove_and_tokens_read.sql` (novo)
- `lib/screens/profile_screen.dart` (cast token row)
- `lib/screens/payment_method_screen.dart` (cast cart tokens)
- `lib/screens/driver_earnings_screen.dart` (cast driver earnings)
- `lib/stores/driver_store.dart` (cast fetchTokenBalance)
- `.claude/.ai/business_rules.md` (§32.4 update + §32.6 + §32.7 + §32.8 renum)

## Áreas proibidas — não tocadas

`create_order`, `pricing_*`, `finalize_storeshopping_purchase`,
`wallet_apply_post_delivery_adjustment`, Stripe/MBWay/refund/cancel-order-*,
dispatch-engine, notify-driver, `enforce_financial_immutability`,
`wallet_credit_refund_split` (refund 80/20).

## Próximo passo

Danilo cria pedido novo → verifica:
1. Profile mostra tokens > 0.
2. Wallet/cart mostra tokens correctamente.
3. **Sem** nova entrada `kind='cashback'` em `wallet_transactions`.

## TODOs sessão futura

- §32.4 fórmula tokens — alinhar `ROUND(price×3)` vs doc "3%" (decisão de negócio).
- Admin tokens screen já existe (`admin_tokens_screen.dart`) — sem alterações.

## Relatório técnico completo

[`.claude/.ai/reports/2026-05-10_fix_cashback_tokens_FINAL.md`](../../.claude/.ai/reports/2026-05-10_fix_cashback_tokens_FINAL.md)
