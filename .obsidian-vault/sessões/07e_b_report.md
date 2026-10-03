# Sessão 7E-B — Relatório

**Data:** 2026-05-07
**Estimativa:** 6-8 h
**Status:** ✅ Concluída — 25/26 PASS (96.2%)
**Branch:** `autonomous-night-2026-04-29`

---

## Sumário

23 tests planeados → **26 implementados** (parametrize T03×3 + T04×2).
**25 PASS + 1 FAIL legítimo** (T22 — BUG-007).

---

## Resultados por grupo

| Grupo | Tests | PASS | FAIL |
|-------|-------|------|------|
| 1 Pricing | 11 | 11 | 0 |
| 2 Dispatch | 5 | 5 | 0 |
| 4 Wallet | 6 | 5 | 1 |
| 7 Cancellation | 4 | 4 | 0 |
| **TOTAL** | **26** | **25** | **1** |

Tempo smoke final: **31.93 s**.

---

## Helpers (5 ficheiros)

- `pricing.py` — apartment dual surcharge.
- `wallet.py` — settlement-first + tokens 1:20 ACTUAL.
- `dispatch.py` — haversine + activate/reposition + link auth.
- `cancellation.py` — 3 paths (client/admin/driver) + utilitários.
- `orders.py` — `create_test_order` + `advance_status` reduzido.

Mais: `helpers/auth.py` ganhou `login_as_user` + alias
`get_admin_client`. `run_all.sh` ganhou action `smoke-7eb`.

---

## BUGs encontrados (5 numerados + nota BUG-002)

| ID | Severidade | Resumo |
|----|-----------|--------|
| 001 | LOW | Cash limit €30 vs €40 (docs vs trigger DB) |
| 003 | LOW | `storeShopping` `bag_fee=0` (regra antiga €0.10/saco) |
| 004 | HIGH | Driver cancela `pickedUp` (regra nova Danilo bloqueia) |
| 005 | HIGH | Tokens factor ×20 (deveria ×2 — bonus 10×) |
| 006 | MEDIUM | Stripe webhook comentário fee €1.50 vs §8.3 €1.00 |
| 007 | HIGH | `add_tokens` silent fail em `wallet_credit_refund_split` |

(BUG-002 saltado — reclassificado: bag fee restaurante €0.30 fixo
é regra correcta.)

---

## Decisões arquitecturais aplicadas

- Unit consistency: **EUR** (não cents) com `EPSILON=0.005` —
  `pricing_calculate` devolve numeric em EUR.
- `STATUS_AT_COLUMNS` reduzido a `{delivered, cancelled}` (apenas
  estes têm timestamp dedicado em prod).
- T38 usa RPC directo `admin_cancel_order` (Edge Fn rejeita
  service_role JWT).
- `cancel_fee` é coluna `orders` (não kind `wallet_transactions`).
- Drivers `E2E_TEST_*` link auth via email (idempotente).
- Auto-settlement em `create_order` força inverter setup T23.

---

## Próximos passos

- **7E-C**: stacking + tokens completos + ratings + store + reservations
  + refund flow choice (~30 tests, 4-6h).
- **7E-D**: robot crosstalk + skill suggestions + RLS + lifecycle
  (~14 tests, 3-5h).
- **Sessão 7**: validações finais + UUID refactor (~6-8h).
- **Fix BUGs HIGH** (004, 005, 007) em sessão dedicada.

---

## Como correr smoke

```bash
cd bora_app/scripts/e2e/
bash run_all.sh smoke-7eb
# 25/26 PASS, T22 FAIL (BUG-7E-B-007 add_tokens silent fail)
```
