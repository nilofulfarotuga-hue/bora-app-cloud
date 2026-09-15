# Sessão 7E-B — AUDIT (FASE A)

**Data:** 2026-05-07
**Branch:** `autonomous-night-2026-04-29`
**Pré-requisito:** 7E-A completo (commit `f3cef24`)
**Modo:** Read-only via MCP Supabase + Read tool. Zero mutações.
**Próxima §:** §46 (última = §45 em business_rules.md L2880)

---

## A0. Regressão (✅ tudo intacto)

| Item | Esperado | Real |
|---|---|---|
| `support_skills` active | 21 | **21** (escalate=3, read_only=11, write_shadow=7) |
| Fixtures 7E-A `auth.users` | ≥ 9 | **9** (6 .test + 3 driver.bora.app) |
| `business_rules.md` última | §45 (7E-A) | **§45** confirmado L2880 |
| Headers `## §N` | 159 hits | OK (sequencial até §45) |

---

## A1. `pricing_calculate` — DIVERGÊNCIAS CRÍTICAS vs proposta

### Schema real

```
ARGS:   p_service_type text, p_subtotal numeric, p_distance_km numeric,
        p_is_partner_store boolean DEFAULT false,
        p_apartment_delivery boolean DEFAULT false,
        p_is_stacked_partner boolean DEFAULT false

RETURN: TABLE (
  delivery_fee numeric,
  service_fee numeric,
  platform_commission numeric,
  driver_earnings numeric,
  customer_total numeric,
  partner_markup_hidden numeric,
  bag_fee numeric
)
```

### ⚠️ 5 divergências vs prompt original

1. **Retorna TABLE, não jsonb** — usar `result.data[0]` em Python (Supabase RPC retorna list).
2. **Valores em EUR (numeric, 2 decimais), NÃO em cents.** Helper `calculate_pricing` deve passar subtotal em EUR (ex.: `10.00` para 10€) e asserções comparar em EUR. Conversão `cents → eur = cents / 100`.
3. **`partner_service_fee_client` e `partner_commission_visible` NÃO existem no return.** São derivados em `create_order`:
   - `partner_commission_visible = platform_commission` quando `is_partner_store=true`
   - `partner_service_fee_client = service_fee` quando `is_partner_store=true`
4. **`bag_fee` é fixo (€0.30 restaurant, €0 outros) — NÃO multiplica por `bag_count`.** O bag_count entra apenas como input em `create_order` mas pricing_calculate ignora-o.
5. **`apartment_delivery=true` adiciona surcharge total (+€1.50) a delivery_fee, +€1.00 driver_earnings, +€0.50 platform_commission** (settings: apartment_surcharge_total/driver_share/platform_share).

### Fórmulas confirmadas (settings reais)

| Setting | Valor |
|---|---|
| `delivery_base_fee_cents` | **250** (€2.50) |
| `delivery_per_km_cents` | **50** (€0.50/km adicional) |
| `delivery_base_distance_km` | **4 km** |
| `bag_fee_restaurant_cents` | **30** (€0.30 fixo) |
| `partner_visible_commission_pct` | **0.10** (10%) |
| `partner_hidden_markup_pct` | **0.05** (5%) |
| `client_service_fee_pct` | **0.05** (5%) |
| `non_partner_markup_pct` | **0.15** (15%) |
| `driver_base_fee_cents` | **380** (€3.80) |
| `driver_per_km_cents` | **20** (€0.20/km) |

---

## A2. `create_order(p_input jsonb)` — schema input

### Args + return

```
ARGS:   p_input jsonb
RETURN: jsonb (order_id, price, subtotal, delivery_fee, service_fee,
        platform_commission, driver_earnings, bag_fee, apartment_surcharge,
        payment_buffer_total, customer_total, partner_markup_hidden,
        wallet_applied_cents, menu_credit_applied_cents,
        wallet_balance_pre_cents, wallet_settlement_cents, charge_total,
        fully_paid_by_wallet, payment_status)
```

### Keys input aceitas

| Key | Tipo | Obrig./Default |
|---|---|---|
| `user_id` | UUID | obrigatório (ou `auth.uid()`) |
| `service_type` | text | obrigatório (`restaurant`/`storeShopping`/`carryGroceries`/`sendPackage`) |
| `payment_method` | text | default `'cash'` (∈ `cash`,`mbway`,`card` apenas) |
| `subtotal` | numeric (EUR) | default 0 |
| `distance_km` | numeric | default 1 |
| `is_partner_store` | boolean | default false |
| `apartment_delivery` | boolean | default false |
| `vendor_name` | text | opcional |
| `bag_count` | int | default 0 |
| `product_lines` | jsonb array | opcional (lookup price em `products`) |
| `wallet_applied_cents` | int | default 0 |
| `payment_intent_id` | text | opcional |
| `payment_already_confirmed` | bool | default false |
| `pickup_lat/lng` | double | obrigatório p/ restaurant/storeShopping/carryGroceries |
| `dropoff_lat/lng` | double | **obrigatório sempre** |

### ⚠️ Achados críticos

- **`payment_method` NÃO aceita `'wallet'`.** Wallet é aplicada via `wallet_applied_cents` em paralelo a `cash`/`mbway`/`card`.
- **NÃO valida cash max €30.** O business_rules.ts tem `CASH_MAX_ORDER_VALUE_EUR=30.00` (não €40 como prompt assumiu) mas o RPC `create_order` não enforça. T04 esperado FAIL no create_order — documentar BUG.
- **NÃO aceita `is_test_order` no input.** Helper `create_test_order` deve fazer `UPDATE orders SET is_test_order=true` pós-create.
- **Order ID é gerado via `gen_random_uuid()::TEXT`** (não int sequencial).
- **Para non-partner: `subtotal_server = subtotal × 1.15`** (markup 15% aplicado server-side se `product_lines` presentes); buffer adicional `+15%` para `payment_buffer_total`.

---

## A3. Wallet RPCs — schemas reais

### Args + return

| RPC | Args | Return |
|---|---|---|
| `wallet_get_balance` | `p_user_id uuid DEFAULT NULL` | jsonb (`free_cents`, `tokens_balance`, `token_value_cents_x100`, `last_transactions`) |
| `wallet_debit_for_order` | `p_user_id uuid, p_order_id text, p_amount_cents int` | jsonb (`success`, `debited_cents`, `new_balance_cents`) |
| `wallet_credit_refund_split` | `p_order_id text, p_user_id uuid, p_total_cents int, p_reason text` | jsonb (`debt_cleared_cents`, `free_cents`, `tokens_count`, `tokens_value_cents`, `split_pct`, `balance_before_cents`) |
| `wallet_credit_generic` | `p_user_id uuid, p_amount_cents int, p_kind text, p_reason text, p_related_order_id text DEFAULT NULL` | jsonb (`success`, `credited_cents`) — kind ∈ `cashback`/`referral`/`admin_grant` |
| `wallet_apply_post_delivery_adjustment` | `p_order_id text, p_user_id uuid, p_amount_cents int, p_reason text, p_kind text DEFAULT 'debit'` | jsonb com idempotency_key |

### ⚠️ DIVERGÊNCIA CRÍTICA: split 80/20 NÃO É free/promo

**`client_wallets` tem APENAS `free_balance_cents`** — não existe `promotional_balance_cents`.

`wallet_credit_refund_split` faz **80% free + 20% tokens**:
- `v_split_pct` = setting `wallet_split_free_pct` (default 0.80)
- `v_free_amount = ROUND(remaining × split_pct)` → credita em `free_balance_cents`
- `v_tokens_amount = remaining - free_amount` → converte para `tokens_count = tokens_amount × 20` (porque 1 token = €0.005)
- Devolve: `{free_cents, tokens_count, tokens_value_cents, split_pct}`

### Hard floor + soft floor

- `wallet_hard_floor_cents = -2000` (€-20.00) — bloqueia debit se cruzar.
- `wallet_max_negative_balance_cents = -1000` (€-10.00) — bloqueia novos `create_order` (soft cap).
- `wallet_negative_enabled = true` — kill-switch.

### `client_wallets` schema

```
user_id uuid PRIMARY KEY
free_balance_cents int NOT NULL DEFAULT 0
created_at, updated_at timestamptz
```

(SEM `promotional_balance_cents`. SEM tabela separada de promo. Tokens estão em `client_token_balances` — não auditado nesta sessão.)

---

## A4. `driver_cancel_order` — quem pode chamar + status aceites

### Schema

```sql
ARGS: p_order_id text
RETURN: jsonb
SECURITY DEFINER
```

### Validações internas

- Driver ID via `auth.uid()` → lookup em `drivers WHERE user_id = auth.uid()` (cast ::text).
- Order ownership: `assigned_driver_id = v_driver_id`.
- Status aceites: **`driverAccepted` OU `pickedUp`** (ambos!).
- Comportamento: reverte para `status='callingDriver'`, limpa `assigned_driver_id`, `current_driver_offer_id`, adiciona ao `tried_driver_ids`, e dispara dispatch-engine via `net.http_post` (URL hardcoded).

### ⚠️ DIVERGÊNCIA T37

Prompt assumia: "driver tenta cancelar em pickedUp → expected fail". **Realidade: driver_cancel_order ACEITA `pickedUp`.** T37 deve ser:
- (a) ajustado para asserção contrária (driver consegue cancelar em pickedUp → re-dispatch),
- ou (b) marcado como BUG-7E-B-XXX (esperado bloquear pickedUp por regra negócio §8.3).

Recomendação: documentar em BUGS_FOUND.md e ajustar T37 para validar comportamento ACTUAL (sucesso) — separar fix da regra de negócio para sessão futura.

---

## A5. Edge Fns cancel — input/output (resumos)

### `client-cancel-order` (verify_jwt=true)
- **Body:** `{order_id: string, reason?: string}`
- **Auth:** JWT cliente; valida `order.user_id == user.id`.
- **Reason enum:** `changed_mind`/`wrong_address`/`wrong_items`/`too_long`/`driver_unresponsive`/`partner_unresponsive`/`payment_failed`/`payment_abandoned`/`other` (ou `other:<texto>`); cap 200 chars.
- **Tier fees:** before_dispatch (`created`/`preparing`/`callingDriver`)=€1.00; after_accept (`driverAccepted`)=€2.50; after_pickup (`pickedUp`/`onTheWay`)=100% × total.
- **Refund:** Apenas Stripe (cartão + payment_intent_id); skipa se PI sem charge succeeded.
- **Return:** `{ok, tier, fee_eur, refund_eur, refund_id, charge_missing}`.

### `cancel-order-with-choice` (verify_jwt=true)
- **Body:** `{order_id, reason, refund_method: 'stripe'|'wallet'}` (reason ≥3 chars)
- **Auth:** JWT cliente.
- **Refund:** escolha cliente — `wallet` chama `wallet_credit_refund_split` (split 80/20 free+tokens).
- **Return:** `{ok, tier, fee_eur, refund_eur, refund_method, refund_id?, wallet?}`.

### `admin-cancel-order` (verify_jwt=true)
- **Body:** `{order_id (UUID), reason_code, reason (≥3 chars)}`
- **Auth:** JWT user com `app_metadata.role='admin'`.
- **Reason codes enum:** `client_request`/`partner_unable`/`driver_unavailable`/`payment_failed`/`fraud_suspected`/`address_invalid`/`food_quality_issue`/`system_error`/`other`.
- **Pipeline:** chama RPC `admin_cancel_order(p_order_id, p_reason_code, p_reason)` → Stripe refund (idempotency `admin-cancel-${orderId}`) → notify-client/driver/partner → audit log.
- **Return:** `{success, idempotent, order_id, previous_status, refund: {result, stripe_id, amount, error}, notifications}`.

### `execute-cancellation` (verify_jwt=true)
- **Body:** `{request_id}` (UUID em `cancellation_requests`).
- **Auth:** admin role (jwt metadata).
- **Pipeline:** lê `cancellation_requests` → executa Stripe ou wallet refund → update orders → audit + notify-client.
- **NÃO usado no fluxo client direct** (post-approval orchestrator). Fora de escopo 7E-B.

---

## A6. Order status + timestamp columns — DIVERGÊNCIAS GRANDES

### CHECK constraints em `orders`
- **Não há CHECK em `status`** — coluna TEXT livre.
- Constraints existentes: refund_method, extra_charge_settled_via, wallet/menu credit non-negative, refund_consistency.

### Status valores reais (90 dias)

| status | n |
|---|---|
| `cancelled` | 36 |
| `delivered` | 41 |
| `driverAccepted` | 3 |
| `rejected` | 10 |

(`created`/`preparing`/`callingDriver`/`pickedUp`/`onTheWay` não aparecem em DB — produção move rápido entre status.)

### ⚠️ DIVERGÊNCIA STATUS_AT_COLUMNS

**Realidade — apenas estes timestamps existem em `orders`:**
```
cancelled_at, created_at, delivered_at, driver_offer_expires_at,
extra_charge_settled_at, helper_requested_at, offer_expires_at,
rated_at, refunded_at, takeaway_ready_at, tip_added_at
```

**NÃO existem:** `preparing_at`, `calling_driver_at`, `driver_accepted_at`, `picked_up_at`, `on_the_way_at`.

**Implicações:**
- Helper `advance_status` proposto no prompt **não pode** escrever em `<status>_at` para 5 dos 7 status.
- Helper `simulate_offer_accept` referenciava `driver_accepted_at` — coluna inexistente.
- **Solução:** STATUS_AT_COLUMNS reduzido a apenas `delivered`/`cancelled`. Para outros status, UPDATE só em `status` (sem timestamp).

```python
STATUS_AT_COLUMNS = {
    'delivered': 'delivered_at',
    'cancelled': 'cancelled_at',
}
```

---

## A7. `token_config` snapshot

| key | value | descrição |
|---|---|---|
| `tokens_per_delivery` | 40 | tokens ganhos por entrega |
| `token_value_eur_x1000` | 5 | 1 token = €0.005 |
| `driver_weekly_convert_max_pct` | 50 | máx % saldo conversível/semana |
| `priority_5min_cost` | 50 | prioridade 5min = €0.25 |
| `priority_10min_cost` | 90 | prioridade 10min = €0.45 |

Contexto para 7E-C — não usado em 7E-B.

---

## A3-bis. `drivers` schema (para mock dispatch)

| Campo | Tipo | Notas |
|---|---|---|
| `id` | uuid | PK |
| `user_id` | uuid | link auth.users |
| `name` | text | usado em fixture lookup `E2E_TEST_%` |
| `lat` | double precision | GPS |
| `lng` | double precision | GPS |
| `is_online` | boolean | **NÃO `online` como prompt assumiu** |

Helper `find_nearest_driver` deve usar `is_online=true` (não `online`).

---

## A8. Matriz 23 tests (regra § + RPC + setup + asserção)

### Grupo 1 PRICING (8 tests T01-T08)

| T | Regra § | RPC/Edge Fn | Setup | Asserção | Risco BUG |
|---|---|---|---|---|---|
| T01 | §2.4 partner hybrid 10+5+5 | `pricing_calculate` | partner=true, subtotal=10€ | `service_fee≈0.50` E `platform_commission≈1.00` E `partner_markup_hidden≈0.50` | baixo |
| T02 | §2.2 non-partner 15% | `pricing_calculate` | partner=false, subtotal=10€ | `service_fee=2.50` (fixo) E `platform_commission≥2.50` | baixo |
| T03 | §2.1 delivery ≤4km | `pricing_calculate` | distance=3km partner=true | `delivery_fee=2.50` | baixo |
| T03b | §2.1 delivery >4km | `pricing_calculate` | distance=5km partner=true | `delivery_fee=3.00` (2.50+0.50) | baixo |
| T04 | §2.x cash max €30 | `create_order` | payment_method=cash, subtotal=35€ | esperado RAISE — **PROVAVELMENTE FAIL: RPC não valida** → BUG | **alto** |
| T05 | §2.x bag fee restaurant | `pricing_calculate` | service_type=restaurant | `bag_fee=0.30` (NÃO × bag_count) | médio (escopo) |
| T06 | §2.x bag fee market | `pricing_calculate` | service_type=storeShopping | `bag_fee=0.00` — **regra negócio diz €0.10/saco × N**, RPC retorna 0 → **FAIL → BUG** | **alto** |
| T07 | §3.1 driver non-partner | `pricing_calculate` | partner=false, distance=3km, restaurant | `driver_earnings>=4.40` (base 3.80 + 0.20×3 + share) | baixo |
| T08 | §3.1 driver partner | `pricing_calculate` | partner=true, distance=3km | `driver_earnings≈4.40` (3.80 + 0.20×3) | baixo |

### Grupo 4 WALLET (6 tests T19-T24)

⚠️ **Re-escopo necessário**: schema NÃO tem `promotional_balance_cents`. Tests T20-T23 precisam reformular para `tokens` ou removidos para 7E-C.

| T | Regra § | RPC | Setup | Asserção |
|---|---|---|---|---|
| T19 | §28 wallet debit | `wallet_debit_for_order` | cliente_a free=10000c, debit 5000c | `new_balance_cents=5000` |
| T20 | §28 hard floor | `wallet_debit_for_order` | balance=−1500c, tentar debit 1000c | `RAISE wallet_hard_floor_exceeded` (-2500 < -2000 floor) |
| T21 | §28 negative create_order block | `create_order` | balance=−1500c, novo pedido | RAISE `WALLET_BLOCKED` (< -1000 soft cap) |
| T22 | §28 settlement on order | `create_order` | balance=−500c | order created + balance=0 + tx kind=`settlement` |
| T23 | §32.4 tokens 60d expiry | (skip — escopo 7E-C) | — | **mover para 7E-C** |
| T24 | §28.6 refund split 80/20 | `wallet_credit_refund_split` | refund 1000c | `free_cents=800` E `tokens_count=4000` (200c × 20) |

(T20/T22 substituem o conceito "promo" por hard_floor/settlement reais.)

### Grupo 7 CANCELLATION (4 tests T35-T38)

| T | Regra § | Edge Fn/RPC | Setup | Asserção |
|---|---|---|---|---|
| T35 | §8.3 pre-dispatch | `client-cancel-order` | order status=`created` cliente_a card paid | `tier=before_dispatch` E `fee_eur=1.00` E refund processado |
| T36 | §8.3 after-accept | `client-cancel-order` | order status=`driverAccepted` | `tier=after_accept` E `fee_eur=2.50` |
| T37 | §8.3 driver cancel pickedUp | `driver_cancel_order` | order status=`pickedUp` driver_a | **comportamento ACTUAL: ok=true** — documentar BUG (esperado bloquear) |
| T38 | §8.x admin cancel | `admin-cancel-order` Edge Fn | admin auth + reason_code=`other` | `success=true` E `refund.result≠failed` |

### Grupo 2 DISPATCH (5 tests T09-T13)

⚠️ **drivers.online → is_online**, **`driver_accepted_at` não existe**.

| T | Regra § | Mecanismo | Setup | Asserção |
|---|---|---|---|---|
| T09 | §6 nearest | helper `find_nearest_driver` | 3 drivers GPS diferente, is_online=true | retorna driver_a (mais perto) |
| T10 | §6 reject reassigns | UPDATE direct + helper | driver_a reject → `current_driver_offer_id=NULL`, `tried_driver_ids+=driver_a` | next find_nearest exclui driver_a |
| T11 | §6 all reject | helper loop | todos rejeitam | status=`callingDriver` permanece, `tried_driver_ids` contém todos |
| T12 | §6 offline excluded | helper `find_nearest_driver` | driver_c is_online=false | retorna apenas online |
| T13 | §6 single offer | UPDATE direct | UPDATE current_driver_offer_id | SELECT confirma valor |

---

## A9. Impacto + rollback

### Mudanças repo (apenas adições)

```
scripts/e2e/conftest.py                         NEW
scripts/e2e/helpers/pricing.py                  NEW
scripts/e2e/helpers/wallet.py                   NEW
scripts/e2e/helpers/dispatch.py                 NEW
scripts/e2e/helpers/cancellation.py             NEW
scripts/e2e/helpers/orders.py                   IMPL (era stub)
scripts/e2e/tests/group_01_pricing/             NEW (8 files)
scripts/e2e/tests/group_02_dispatch/            NEW (5 files)
scripts/e2e/tests/group_04_wallet/              NEW (6 files)
scripts/e2e/tests/group_07_cancellation/        NEW (4 files)
scripts/e2e/BUGS_FOUND.md                       NEW
.claude/.ai/business_rules.md                   EDIT (§46)
.obsidian-vault/sessoes/07e_b_*.md              NEW (sync)
```

**Sem mudanças:** schema produção, Edge Fns, código produção (Flutter), seeds 7E-A.

### Riscos identificados

1. **T04, T06 vão FAIL legitimamente** — bag fee de mercado e cash €30 cap não enforçados em `pricing_calculate`/`create_order`. Documentar BUG, NÃO bloqueia merge (política 7E-B).
2. **T20-T23 reformulados** — não há `promotional_balance_cents`. Tests adaptados a hard_floor/settlement/tokens.
3. **T37 expectation invertida** — driver_cancel_order aceita `pickedUp`. Documentar BUG, ajustar test ao comportamento ACTUAL.
4. **STATUS_AT_COLUMNS reduzido a 2** — `delivered_at`, `cancelled_at` apenas. Outras transições UPDATE só status.
5. **Trigger `fn_dispatch_on_calling_driver` pode disparar** em UPDATE manual de status — aceitável, side effects ignorados nos tests.
6. **drivers.is_online (não online)** — corrigir helper.
7. **payment_method 'wallet' não existe** — usar `cash`/`card` + `wallet_applied_cents`.

### Rollback

```bash
git checkout scripts/e2e/helpers/orders.py
rm -rf scripts/e2e/tests/group_{01_pricing,02_dispatch,04_wallet,07_cancellation}
rm scripts/e2e/{conftest.py,BUGS_FOUND.md}
rm scripts/e2e/helpers/{pricing,wallet,dispatch,cancellation}.py
git checkout .claude/.ai/business_rules.md
python scripts/e2e/cleanup.py --confirm
```

---

## A10. Skills + sync

- **Skill aplicável:** `simplify` (revisão pós-implementação) + skill nativa pytest (sem skill custom).
- **Sync Obsidian:** este ficheiro replicado em `.obsidian-vault/sessoes/07e_b_audit.md` na fase de commit (B12).
- **CEO-AI:** workflow de FAIL via `BUGS_FOUND.md` documentado para próximas sessões.

---

## ⛔ STOP — luz verde Danilo necessária para FASE B

**Decisões pendentes pelo Danilo (efeito vinculativo nas implementações B1-B12):**

1. **T04 (cash €30 cap)**: documentar como BUG e teste FAIL, OU mover para 7E-D (seria fix produção)?
2. **T05/T06 (bag fee mercado / multiplicação)**: documentar como BUG e adaptar asserções, OU remover do escopo?
3. **T20-T23 (promo balance ausente)**: aceitar reformulação proposta (hard_floor/settlement/tokens) OU mover para 7E-C tokens?
4. **T37 (driver cancela pickedUp)**: ajustar teste para asserção contrária (sucesso) OU manter expectativa original e documentar como BUG?
5. **STATUS_AT_COLUMNS reduzido a 2**: aceitar (UPDATE só status para transições intermédias) OU adicionar timestamp columns ao schema (mudança produção, fora de escopo 7E-B)?

Recomendação CEO-AI: **opção menos intrusiva em todos** — documentar BUGS, adaptar tests à realidade actual, não tocar código produção. Permite 7E-B avançar com 23 tests sendo `≈18 PASS + 5 BUGS_FOUND` esperado.

**Aguardo aprovação granular B1→B12 ou correcções ao plano.**
