# Roadmap 7E-B / 7E-C / 7E-D — testes funcionais E2E

Sub-sessões adiadas após 7E-A (esqueleto + smokes). Cada sub-sessão corre em ~4-6h, escrita em PT-PT, com decisões de mock granular já validadas no audit.

---

## 7E-B — Tests críticos lançamento (4-6h, ~23 tests)

### Helpers a implementar

- [ ] `helpers/orders.py`
  - [ ] `create_test_order(client, **kwargs) -> dict`
  - [ ] `advance_status(client, order_id, target: str) -> dict`
  - [ ] `simulate_dispatch_accept(client, order_id, driver_id) -> None`
  - [ ] `simulate_stripe_payment_succeeded(client, order_id, amount: float) -> None`
- [ ] `helpers/wallet.py` **(novo)**
  - [ ] `check_balance(client, user_id) -> int  # cents`
  - [ ] `simulate_topup(client, user_id, amount_cents: int) -> None`
- [ ] `helpers/dispatch.py` **(novo)**
  - [ ] `simulate_offer_flow(client, order_id, driver_ids: list[str]) -> str  # accepted_id`

### Tests

- [ ] **Grupo 1 — Pricing (8 tests T01-T08)**
  - T01: subtotal €0 → fees mínimos correctos
  - T02: subtotal €10 partner → commission 15%
  - T03: subtotal €10 non-partner → commission 0%
  - T04: distance 0 km → delivery_fee mínimo
  - T05: distance 5 km → delivery_fee escalado
  - T06: apartment_delivery → +€0.50 service_fee
  - T07: carryGroceries → fórmula diferente
  - T08: oracle PricingService (Dart) ≡ DB output (NUMERIC)

- [ ] **Grupo 2 — Dispatch (5 tests T09-T13)**
  - T09: order created → status=callingDriver após delay
  - T10: 1 driver online → offer único
  - T11: driver rejeita → next driver
  - T12: timeout 10s → next driver
  - T13: ninguém aceita → status volta a `preparing`

- [ ] **Grupo 4 — Wallet (6 tests T19-T24)**
  - T19: top-up €10 → balance += 1000c
  - T20: order paga com wallet (saldo positivo)
  - T21: order parcial wallet + Stripe
  - T22: saldo negativo permitido (§28 wallet sessão 3B-NOVA)
  - T23: refund > balance → saldo negativo
  - T24: cleanup wallet apaga sem cascade quebrar ledger

- [ ] **Grupo 7 — Cancellation (4 tests T35-T38)**
  - T35: client_cancel antes de driverAccepted → refund full
  - T36: client_cancel depois de driverAccepted → fee
  - T37: admin_cancel → refund full + admin_reason
  - T38: cancel-order-with-choice → 3 paths (refund / wallet / promo)

---

## 7E-C — Tests secundários (4-6h, ~30 tests)

### Helpers a implementar

- [ ] `helpers/tokens.py` (add/consume/get_user_tokens)
- [ ] `helpers/ratings.py` (submit_rating + asserções AVG)
- [ ] `helpers/reservations.py` (create reservation + payout)
- [ ] `helpers/refunds.py` (refund admin / partial)
- [ ] `helpers/store.py` (storeShopping + finalize_storeshopping_purchase)

### Tests

- [ ] **Grupo 3 — Stacking (5 tests T14-T18)** — pode FAIL legitimamente se "Order stacking up to 3" não implementado em prod
- [ ] **Grupo 5 — Tokens (5 tests T25-T29)** — descobre §32.4 inconsistência docs/código
- [ ] **Grupo 6 — Store Shopping (5 tests T30-T34)**
- [ ] **Grupo 8 — Ratings (7 tests T39-T45 Sessão 6)**
  - submit_rating com `is_private=true` → não conta para AVG
  - subject_type='app' → sem trigger update
  - rater_user_id ≠ user_id → REJECT
  - tags array livre
- [ ] **Grupo 9 — Reservations (5 tests T46-T50)**
- [ ] **Grupo 10 — Refunds (3 tests T51-T53)** — incluindo `trg_enforce_refund_cap`

---

## 7E-D — Tests terciários + segurança (3-5h, ~14 tests)

### Helpers a implementar

- [ ] `helpers/robot.py` (mock Gemini default; populate `RESPONSE_FIXTURES`)

### Tests

- [ ] **Grupo 11 — Robot A (4 tests T54-T57)** — chatbot, crosstalk, write shadow
- [ ] **Grupo 12 — Skill Suggestions (2 tests T58-T59)**
- [ ] **Grupo 13 — RLS (5 tests T60-T64)** — segurança crítica:
  - T60: client não consegue ler orders de outro user
  - T61: driver só lê orders assigned
  - T62: append-only ledger (`ledger_no_update` / `ledger_no_delete`)
  - T63: admin pode ler tudo (via JWT bora_role=admin)
  - T64: anon não consegue ler nada
- [ ] **Grupo 14 — Status Lifecycle (3 tests T65-T67)**
  - T65: status flow rígido (created → preparing → ... → delivered)
  - T66: rejected é terminal
  - T67: trigger `orders_set_delivered_at` popula `delivered_at`

---

## GAPS documentados a investigar

- **§32.4 — fórmula tokens divergente entre docs e código** (descoberta esperada em 7E-C T25-T29). Docs dizem `+1 token / 0.5 EUR`, código usa `floor(amount / 1)`.
- **§3 — Order stacking up to 3** — não claro se implementado em prod; 7E-C Grupo 3 pode falhar legitimamente.
- **§15-§18 (UI Flutter)** — fora de scope E2E backend; abrir TODO 7E-Flutter (separado).
- **dispatch-engine pg_cron** — não testado directo; coberto por monitoring prod.
- **stripe-webhook signature** — não testado directo; coberto por validação manual.

---

## TODO 7E-Flutter (sub-sessão futura, prioridade baixa)

Suite de testes UI Flutter usando `flutter_test` + `integration_test`. Fora de scope desta linha 7E.
