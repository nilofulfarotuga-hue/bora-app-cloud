# Sessão 7-FIX — Relatório

**Data:** 2026-05-07 (continuação 7E-B)
**Duração:** ~2 h
**Status:** ✅ Concluída — 3 BUGs HIGH fixed
**Branch:** `autonomous-night-2026-04-29`

---

## Sumário

3 BUGs HIGH descobertos em 7E-B foram corrigidos via MCP em produção
e sincronizados localmente. Smoke 7E-B re-correu **26/26 PASS** (era
25/26).

---

## Migrations (2)

- `20260507223228_fix_7e_b_bug_005_bug_007_tokens_uuid_to_text.sql`
- `20260507223338_fix_7e_b_bug_004_driver_cannot_cancel_pickedup.sql`

---

## BUGs fixed

| ID | Severidade | Fix |
|----|-----------|-----|
| **005** | HIGH | factor ×20 → ×2 (matemática 1 token = €0.005) |
| **007** | HIGH | UUID → TEXT em `bora_tokens.source_order_id` e `add_tokens.p_order_id`; `fn_award_tokens_on_delivery` sem cast `::UUID`; `wallet_credit_refund_split` sem try/except silencioso |
| **004** | HIGH | `driver_cancel_order` rejeita `pickedUp` + mensagem PT-PT redirige suporte (`support_required=true`) |

---

## Validação MCP isolada

- Refund €10 → 400 tokens criados em `bora_tokens` ✅
- `bora_tokens.source_order_id` agora TEXT (igual a `orders.id`) ✅
- Token expira em 60 dias ✅
- Driver em `pickedUp` recebe `cancel_blocked_after_pickup` ✅

---

## Tests invertidos

Tests que documentavam BUGs agora validam comportamento correcto:

- T22 `test_t22_refund_split_zero_balance` — `tokens_count=400`
  + valida directamente `bora_tokens` row (fonte de verdade).
- T24 `test_t24_tokens_conversion_factor_2` (renomeado) — factor `×2`.
- T37 `test_t37_driver_blocked_pickedup_redirects_support` (renomeado)
  — `ok=false` + `support_required=true` + mensagem PT-PT.

Helper `helpers/wallet.py`: `TOKENS_PER_CENT` 20 → 2.
Helper `helpers/cancellation.py`: `driver_attempt_cancel` parser
defensivo para excepções com payload-dict.

---

## BUGs ainda OPEN

- 001 LOW — cash limit docs/code (€30 vs €40).
- 003 LOW — `storeShopping` `bag_fee=0` (regra antiga €0.10/saco).
- 006 MEDIUM — Stripe webhook fee mismatch (€1.50 vs €1.00).

---

## Próximos

- 7E-C ⏳ stacking + reservations + refund choice flow.
- 7E-D ⏳ robot crosstalk + skill_suggestions + RLS.
- Decisão Danilo: granting compensatório aos clientes que cancelaram
  orders historicamente sem receber tokens em refund (BUG-007 antigo)?

---

## Smoke

```
====== 26 passed, 1 warning in 32.60s ======
```

```bash
cd bora_app/scripts/e2e/
bash run_all.sh smoke-7eb
# 26/26 PASS — todas as regressões cobertas
```
