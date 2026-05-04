# Sessão 4/7 — Bugs Colaterais / Housekeeping — Relatório Fase A

**Data:** 2026-05-04
**Branch:** `autonomous-night-2026-04-29`
**Estado:** Fase A concluída. Aguarda luz verde Danilo para Fase B.
**Pré-validações MCP Claude.ai:** confirmadas em A0-A7 (incluindo correcções de leitura).

---

## Sumário executivo

| Bug | Estado A | Recomendação B |
|---|---|---|
| C1 — `confirm-mbway-payment` obsoleta | 0 callers reais (2 comentários a actualizar) | ✅ Apagar + actualizar comentários |
| C2 — `create-mbway-payment-intent-debug` debug em prod | 0 callers em todo repo | ✅ Apagar |
| C3 — `final_total` double precision | 24 callsites mapeados; estratégia dual-write `trg_zz_*` validada | ✅ Commit 1 nesta sessão |
| C4 — `extra_charge_amount` sem marker settlement | 0 rows positivos (gate B3 passa); ajuste de kind necessário | ✅ Aditiva trivial |
| C5 — `quote_order_pricing` coords | RPC só lê `distance_km` (não coords); 1 caller real (Edge Fn) | ✅ Caso A — documentar |
| C6 — Flutter productId=NOME | **86% orders amostra com productId=name; 67% pós Bug-B fix** | ⚠️ **Diferir Sessão 4C** |

---

## A0 — Regressão Sessões 1, 2, 3, 3B-NOVA

| Check | Resultado | Status |
|---|---|---|
| Coords NULL pós-0503 | 0 | ✅ |
| Coords NULL legacy (25/04→02/05) | 46 | ℹ️ histórico pré-fix, não regressão |
| `is_partner=true` aprovados | 5 pending (locais) | ✅ |
| `is_partner=false` aprovados (markets) | 10 (Continente/Lidl/etc) | ✅ Sessão 1 BUG 6 OK |
| Reservation RPCs | 7 (incluindo `partner_mark_arrival`) | ✅ Sessão 2 OK |
| `cash_total_due` col | existe | ✅ |
| `pending_charges` rows | 0 | ✅ inactiva |
| `client_wallets` CHECK | `>= -2000` (hard floor −€20) | ✅ |
| `platform_settings` wallet_* | 7 (incluindo extras `wallet_split_free_pct`, `wallet_max_use_pct_per_order`) | ✅ |
| Wallet RPCs | 2 (`apply` + `forgive`) | ✅ |
| Cron `wallet_overdue_alerts` | 1 | ✅ |
| `create_order` tem `WALLET_BLOCKED` | true | ✅ |
| `finalize` tem `wallet_apply` | true | ✅ |
| `extra_charge_amount > 0` | 0 rows | ✅ **GATE B3 PASSA** |
| `final_total` type | `double precision` | ⚠️ bug C3 |
| `customer_total` type | `numeric` | ✅ |
| `wallet_transactions.related_order_id` | `text NULL` | ✅ |
| `final_total_numeric` exists | 0 | ✅ B2 livre |
| `trg_zz_final_total_dual_write` exists | 0 | ✅ |

---

## A0b — 17 triggers em `orders` (alfabético)

```
1.  orders_auto_confirm_cod
2.  orders_cash_settlement
3.  orders_enforce_cash_limit                ← BEFORE OF final_total
4.  orders_enforce_payment_before_preparing  ← BEFORE UPDATE
5.  orders_financial_lock                    ← BEFORE UPDATE (CRÍTICO)
6.  orders_financial_split
7.  orders_post_to_ledger
8.  orders_set_delivered_at                  ← BEFORE UPDATE
9.  orders_storeshopping_pickup_guard        ← BEFORE UPDATE
10. trg_award_cashback
11. trg_award_tokens_on_delivery
12. trg_dispatch_on_calling_driver
13. trg_dispatch_on_rejection
14. trg_enforce_refund_cap
15. trg_notify_on_order_cancel
16. trg_referral_reward
17. trigger_credit_driver_on_delivery
```

**Análise B2:** os 5 BEFORE triggers que disparam em UPDATE de `final_total` começam com `orders_*` ('o'=111 < 't'=116) → todos executam ANTES de `trg_zz_*`. Estratégia trg_zz_* validada.

`trigger_credit_driver_on_delivery` (`trig` > `trg`) ALFABETICAMENTE vem depois de `trg_zz_*`, mas é AFTER UPDATE OF status — não dispara em UPDATE de `final_total` → zero conflito runtime.

`enforce_financial_immutability` (via `orders_financial_lock`): bloqueia mutações em 9 colunas: `price, final_total, subtotal, delivery_fee, service_fee, platform_commission, driver_earnings, bag_fee, payment_buffer_total`. Escapes: `auth.role()='service_role'` OR `current_setting('app.financial_bypass')='true'`. **B2 backfill:** usar `SET LOCAL app.financial_bypass='true'` como defesa em profundidade (apesar de Supabase MCP correr como service_role).

---

## A1 — `confirm-mbway-payment` v11

- **Status:** ACTIVE, verify_jwt=true, version=11
- **Backup:** `.claude/.ai/backups/edge_fns/confirm-mbway-payment_v11.ts` ✅
- **Callers `lib/`:** 2 referências em comentários (`order_store.dart:831, 2260`); 0 invocações reais
- **Callers `supabase/functions/`:** apenas o próprio `config.toml`
- **Decisão:** apagar em B1 + actualizar 2 comentários para apontar `stripe-webhook`

## A2 — `create-mbway-payment-intent-debug` v1

- **Status:** ACTIVE, verify_jwt=true, version=1
- **Backup:** `.claude/.ai/backups/edge_fns/create-mbway-payment-intent-debug_v1.ts` ✅
- **Suspeito:** usa `payment_method_types: ['multibanco','card']` em vez de `mb_way`
- **Callers em todo o repo:** 0 (apenas em reports/.ai)
- **Decisão:** apagar em B1

---

## A3 — C3 dependency map (`final_total`)

### DB — 11 funções/RPCs + 1 trigger explícito
- RPCs/funcs: `apply_driver_cash_settlement`, `apply_order_financial_split`, `compute_driver_settlement(uuid,tstz,bool)`, `create_order(jsonb)`, `enforce_cash_payment_limit`, `enforce_financial_immutability`, `finalize_storeshopping_purchase(text,jsonb,jsonb,int)`, `fn_award_cashback_on_delivery`, `fn_referral_reward_on_first_delivery`, `list_driver_orders_in_week(uuid,tstz)`, `post_order_to_ledger`
- Triggers OF final_total: `orders_enforce_cash_limit`
- **Views: 0** ✅

### Flutter — 9 ficheiros
`lib/models/order_model.dart`, `lib/stores/order_store.dart`, `lib/screens/orders_screen.dart`, `lib/screens/driver_map_screen.dart`, `lib/screens/driver_home_screen.dart`, `lib/widgets/weekly_settlement_card.dart`, `lib/screens/admin/admin_order_detail_screen.dart`, `lib/screens/admin/admin_driver_detail_screen.dart`, `lib/screens/admin/_admin_cancel_order_dialog.dart`

### Edge Fns — 3 ficheiros
`client-cancel-order/index.ts`, `cancel-order-with-choice/index.ts`, `execute-cancellation/index.ts`

**Total: 24 callsites.** Todos continuam a ler `final_total` (double) durante dual-write — zero churn imediato.

---

## A4 — extra_charge / settlement state

| Check | Resultado | Status |
|---|---|---|
| `orders.extra_charge_amount > 0` | 0 rows | ✅ **GATE B3 PASSA** |
| `extra_charge_amount = 0` (set explicit) | 1 row | ℹ️ |
| `extra_charge_amount IS NULL` | 93 rows | ℹ️ |
| `extra_charge_amount` type | **`double precision`** | 🐛 **mesmo bug categórico C3** |
| `wallet_transactions.related_order_id` | `text NULL` | ✅ |
| `wallet_transactions.kind` valores actuais | `cashback, order_payment, refund_credit_free, refund_credit_tokens` | ⚠️ |
| `extra_charge_settled_at`/`_via` | NÃO existem | ✅ B3 livre |

**Acção B3:** `wallet_apply_post_delivery_adjustment` aceita `kind ∈ {'debit','adjustment'}`; `create_order` insere directamente com `kind='settlement'` (confirmado A7 via leitura linha-a-linha — a string `'debt_settlement'` que aparece no source é um campo REASON dentro de `jsonb_build_object`, NÃO o kind). WHERE clause final:
```sql
WHERE wt.kind IN ('debit', 'adjustment', 'settlement')
```

---

## A5 — `quote_order_pricing` coords

### Comparação chaves jsonb
| Chave | `create_order` | `quote_order_pricing` |
|---|---|---|
| `dropoff_lat/lng` | ✅ lê | ❌ não lê |
| `pickup_lat/lng` | ✅ lê | ❌ não lê |
| `distance_km` | ✅ usa para pricing | ✅ usa para pricing |
| `apartment, is_partner, service_type` | ✅ | ✅ |

**Correcção MCP Claude.ai:** `create_order` lê coords apenas para PERSISTIR (mapa); pricing usa `distance_km` payload. Logo ambas RPCs usam mesmo valor SE caller envia mesmo `distance_km`.

### Callers
- Flutter `lib/`: **0**
- Edge Fn `create-payment-intent/index.ts:149`: 1 caller real (`userClient.rpc('quote_order_pricing', ...)`)
- Migration de definição + decisions/reports

### Decisão B4 — Caso A (paridade simples)
- Não alterar signature
- Documentar em `business_rules.md`: caller é responsável por distance_km consistente
- Smoke obrigatório: quote(distance_km=X) vs create_order(distance_km=X) → ± €0.01

### 🐛 Colateral A5 (sessão futura — anti-fraud)
`distance_km` sem validação server-side em ambas RPCs → cliente malicioso pode enviar `distance_km=0.1`. Sessão dedicada a anti-fraud.

---

## A6 — Flutter productId trace (CRÍTICO)

### Arquitectura confirmada
1. Flutter envia payload via RPC `create_order` com key `'product_id'` (snake)
2. RPC lê `'product_id'` (snake) e persiste em `orders.items` com `'productId'` (camel)
3. Sem inserts directos a `orders.items`

### Estatísticas (amostra 30 orders mais recentes)
| Métrica | Valor |
|---|---|
| Orders com `productId` (camel) persistido | 29/30 |
| Orders onde `productId == name` | **26/30 (86%)** |
| Orders cujo productId existe em `products` | **3/30 (10%)** |
| Orders pós Bug-B fix (2026-04-30) | 12 |
| Orders pós-fix com bug ainda activo | **8/12 (67%)** |

### Causa raiz
`cart_item.dart:22` → `productId = productId ?? name`
Fallback silencioso quando caller não passa productId real.

### Callers OK (passam product.id)
- `restaurant_menu_screen.dart:459`
- `store_products_screen.dart:871, 1065`
- `product_detail_screen.dart:50`
- `business_mapper.dart:25` (Bug-B fix 2026-04-30)

### Callers passthrough (clonam productId)
- `cart_store.dart:303, 477`
- `order_store.dart:429, 625`
- `reorder_service.dart:62`
- `driver_map_screen.dart:1067`
- `restaurant_menu_screen.dart:187`

### Callers usando keys derivadas (intencional)
- `_variantKey(v)` em variantes (`product_detail_screen.dart:28`, `store_products_screen.dart:1148`)
- `'extra_${ts}'` em items extra (`driver_map_screen.dart:2137`)

### Total: 107 ocorrências de `CartItem(...)` em `lib/`

### Impacto transversal
- **Cliente:** vê produto OK (price/name correctos)
- **Estafeta driver_map:** shopping list mostra nome; lookup imagem/SKU pode falhar
- **Parceiro dashboard:** vê nome literal, não consegue reconciliar inventário
- **Admin:** lookup produto FALHA em 86% dos orders → admin_order_detail sem imagem/categoria
- **Telemetria:** GROUP BY productId é lixo (cada nome único = produto distinto)

### 🐛 Colaterais A6
1. 11/30 orders recentes com `payment_status='failed'` — correlação com productId=name?
2. 1 order `E2E2daa86` com productId completamente NULL — caso edge

---

## A7 — Análise impacto consolidada

### Plano Fase B (decisões finais)

#### B1 — Apagar 2 Edge Fns + actualizar comentários
- Backups feitos ✅
- Callers reais: 0
- Comentários a actualizar: `order_store.dart:830-835` e `:2256-2262`
- Painel admin: `admin_edge_functions_screen` reflecte lista limpa
- Risco: 0 / Rollback: redeploy a partir do backup
- **Esforço:** 15 min

#### B2 — final_total dual-write (commit 1)
- ALTER TABLE ADD COLUMN `final_total_numeric NUMERIC NULL`
- Backfill: `UPDATE orders SET final_total_numeric = final_total::numeric` com `SET LOCAL app.financial_bypass='true'`
- CREATE FUNCTION `fn_sync_final_total_numeric()` BEFORE INSERT/UPDATE OF final_total
- CREATE TRIGGER `trg_zz_final_total_dual_write` (sufixo zz garante última posição alfabética)
- Dry-run obrigatório primeiro: BEGIN; ALTER+UPDATE; SELECT mismatches=0; ROLLBACK
- 24 callsites continuam a ler `final_total` (double) — zero churn
- Painel admin `admin_orders/admin_order_detail`: COALESCE durante transição
- Risco: baixo / Rollback: DROP TRIGGER + DROP FUNCTION + DROP COLUMN
- Commit 2 (DROP+RENAME) sessão futura após +24h smoke prod
- **Esforço:** 60 min

#### B3 — extra_charge settlement marker
- ALTER TABLE ADD COLUMN `extra_charge_settled_at TIMESTAMPTZ NULL`, `extra_charge_settled_via TEXT NULL CHECK (... IN ('wallet','cash','none'))`
- Backfill com WHERE `kind IN ('debit','adjustment','settlement')` (kind literal usado em `create_order`, confirmado A7)
- Esperado 0 rows marked (validado A4)
- Estender `finalize_storeshopping_purchase`: UPDATE settled_at=now(), settled_via='wallet'
- Cash path: estafeta confirma cash → settled_via='cash'
- Painel admin `admin_order_detail`: colunas "Liquidado em" + "Via" + filtro
- Risco: 0 / Rollback: DROP COLUMN
- **Esforço:** 30 min

#### B4 — quote_order_pricing coords (Caso A)
- Não alterar signature
- Documentar em `business_rules.md`
- Smoke obrigatório: quote vs create_order ± €0.01 com mesmas coords e distance_km
- Painel admin: simulação de pricing usa nova doc
- Risco: 0 / Rollback: N/A (apenas docs)
- **Esforço:** 20 min
- 🐛 Anti-fraud `distance_km` validation diferido para sessão dedicada

#### B5 — Flutter productId
- ⚠️ **ESCOPO INFLATIONADO** — 107 call sites; 67% orders pós-fix-anterior ainda têm bug
- Mudanças mínimas (esta sessão, opção mitigação):
  - `cart_item.dart:22` — REMOVER fallback `?? name`
  - `cart_item.dart` construtor — ADD `assert(productId.isNotEmpty && !productId.contains(' ') && productId.length < 100)`
  - 2-4 linhas
- Mudanças completas (Sessão 4C dedicada):
  - Mapear todos os 107 call sites
  - Identificar caminhos que dependem do fallback
  - Fix transversal (cliente, estafeta, parceiro, admin)
  - Smoke + regressão completa
  - Considerar limpeza de orders históricas (UPDATE products lookup nome→SKU)
- **Recomendação: Opção B (Sessão 4C dedicada)** — esta sessão fica saturada com B1-B4
- **PERGUNTA AO DANILO:** confirmar Opção A (apertar B5 nesta) ou Opção B (4C dedicada)?

### Riscos de regressão (todos verificados)
| Sessão / BUG | Estado |
|---|---|
| Sessão 1 (coords, partner backfill, unit_price fallback) | ✅ intacta |
| Sessão 2 (7 reservation RPCs) | ✅ intacta |
| Sessão 3 (cash, sacos cap 5, cash_total_due) | ✅ intacta |
| Sessão 3B-NOVA (wallet hard floor, gate, finalize, cron) | ✅ intacta |
| BUG 35 banner cash, BUG 38 linha verde | ✅ não tocados em B1-B4 |
| BUG 34 orders.id TEXT (Sessão 7) | ✅ não tocado |

### 🐛 Colaterais consolidados (reportar — não fixar)
1. **A4** — `orders.extra_charge_amount` é `double precision` (mesmo padrão C3) — sessão futura housekeeping financeiro
2. **A5** — `distance_km` server-side sem validação anti-fraud em quote+create_order — sessão dedicada
3. **A6** — 11/30 orders recentes com `payment_status='failed'` — correlação com productId=name a investigar
4. **A6** — 1 order `E2E2daa86` com productId NULL — caso edge a investigar
5. **A6** — Bug-B fix 2026-04-30 NÃO eliminou productId=name (67% pós-fix ainda têm bug)

### Estimativa total Fase B (sem B5 completo)
- B1: 15 min
- B2: 60 min
- B3: 30 min
- B4: 20 min
- B5 mitigação (assert+remover fallback): 20 min
- Smokes S1-S20: 60 min
- Commit + business_rules.md update: 30 min
- **Total: ~3h45m** (dentro do estimado 3-4h)

---

## A8 — Pendências para Fase B

⛔ **STOP — aguardar luz verde Danilo.**

### Decisões pendentes (Danilo)
1. **B5 — Opção A ou B?** Apertar B5 completo nesta sessão (alto risco overflow) OU diferir para Sessão 4C dedicada (mitigação imediata SÓ assert)?
2. **Kind literal confirmado: `'settlement'`** (briefing original correcto; a leitura inicial confundiu com campo REASON `'previous_debt_settlement'` num `jsonb_build_object`)
3. **B4 Caso A confirmado?** (não alterar signature, apenas documentar)

### Documentos que actualizar em fim de Fase B
- `business_rules.md` — tipos NUMERIC, Edge Fns activas, productId real, trigger naming `trg_zz_*`, distance_km caller responsibility
- `.claude/.ai/todos/sessao_4_pending.md` — C3 commit 2 ordem obrigatória; colaterais; B5 4C; anti-fraud
- `.claude/.ai/reports/20260502_megafinal/04_bugs_colaterais_report.md` — Fase B execução
