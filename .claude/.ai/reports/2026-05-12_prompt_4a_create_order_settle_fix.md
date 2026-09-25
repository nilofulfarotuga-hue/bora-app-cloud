# PROMPT 4a — `create_order` settle prematuro FIX

**Data:** 2026-05-12
**Branch:** `autonomous-night-2026-04-29`
**Modelo:** Opus 4.7
**Status:** ✅ EXECUTADO COMPLETO — **push NÃO efectuado** (aguarda Danilo)

---

## RESULTADO

### 3 migrations aplicadas via MCP

| # | Nome | Status |
|---|------|--------|
| 1 | `20260512200001_orders_add_debt_collected_cents` | ✅ |
| 2 | `20260512200002_create_order_conditional_settle` | ✅ |
| 3 | `20260512200003_apply_client_debt_settlement_on_payment_paid_trigger` | ✅ |

### Source local sincronizado
- `supabase/migrations/20260512200001..03_*.sql` ✅

### Edge Functions
- **Nenhuma tocada** nesta sessão.

---

## PRÉ-REQUISITOS — 8/8 ✅

| # | Check | Resultado |
|---|---|---|
| 1 | RPCs wallet (3/3) | ✅ wallet_debit_cancel_fee, wallet_debit_for_order, wallet_settle_debt |
| 2 | Trigger `apply_client_debt_settlement_on_cash_delivery` | ✅ 1 row |
| 3 | Settlements históricas | ✅ 0 |
| 4 | Wallets negativas | ✅ 0 |
| 5 | `orders.debt_collected_cents` NÃO existe pre-fix | ✅ 0 cols |
| 6 | `wallet_transactions.idempotency_key` existe | ✅ 1 col |
| 7 | `create_order` tem `v_payment_already_confirmed BOOLEAN` | ✅ true |
| 8 | Branch limpa | ✅ `autonomous-night-2026-04-29` em `a801c22` |

---

## 4 VALIDAÇÕES READ-ONLY

**V1 — `stripe-webhook` v23 actualiza `payment_status='paid'`:** ✅ SIM
```ts
const { error } = await supabase.from('orders')
  .update({ payment_status: 'paid' })
  .eq('id', order_id).eq('payment_status', 'pending');
```
UPDATE explícito com `payment_status` no SET → trigger NOVO `AFTER UPDATE OF payment_status` dispara correctamente em MBWay/Cartão LEGACY.

**V2 — Driver UI grep (TODO para PROMPT 4b):**
```
grep -rn "final_total\|payment_buffer_total\|total_to_collect\|cobrar"
  lib/screens/driver_*.dart lib/widgets/driver_*.dart
```
**Resultado vazio.** Driver screens não referenciam directamente esses campos. **TODO PROMPT 4b**: investigar onde a info do valor a cobrar é mostrada ao estafeta. Candidatos prováveis:
- Via [lib/models/order_model.dart](lib/models/order_model.dart) (getter/serialização)
- Widget intermediário em [lib/widgets/](lib/widgets/) (não-driver_*)
- Ou tela [lib/screens/driver_home_screen.dart](lib/screens/driver_home_screen.dart) usa variável local com nome diferente

PROMPT 4b deve mapear via grep mais abrangente (`grep -rn "final_total\|customerTotal\|totalCents\|priceFor" lib/`).

**V3 — Triggers existentes confirmados via SQL:**
- `orders_auto_confirm_cod`: `BEFORE UPDATE OF status WHEN delivered+(cash|mbway)` → modifica `NEW.payment_status` in-place; mas como `payment_status` NÃO está no SET clause do UPDATE original, evento "AFTER UPDATE OF payment_status" NÃO dispara. ✅ Sem conflito.
- `apply_client_debt_settlement_on_cash_delivery`: `AFTER UPDATE OF status WHEN delivered+cash` → continua válido após FIX 2.
- Trigger NOVO `apply_client_debt_settlement_on_payment_paid`: `AFTER UPDATE OF payment_status WHEN paid+(mbway,card)` — dispara apenas via UPDATE explícito de `payment_status` (webhook). CASH delivered via auto_confirm_cod NÃO dispara aqui (event mismatch + filtro payment_method).

**Zero conflito entre os 3 triggers** ✅.

**V4 — Estado PROMPT 3 mecanismo 2:**
- `create-payment-intent` v27 ✅ (não mergeado)
- `create-mbway-payment-intent` v19 ✅ (não mergeado)

**Impacto em `debt_collected_cents`** (Cartão NEW):
- Estado actual (mecanismo 2 não mergeado): `create_order` inline settle popula `debt_collected_cents = v_settlement_cents` (Cenário 9a)
- Se mecanismo 2 for mergeado no futuro: webhook settla primeiro → wallet=0 quando create_order corre → `debt_collected_cents = 0` (Cenário 9b — data hygiene; sem double-settle)

---

## 9 SMOKE TESTS — 9/9 PASSAM ✅

User teste: `118ee00c-8efc-4df4-a6a6-2e2d70902425` (e2e_client_c). Cleanup completo após cada cenário.

### Cenário 1 — Cartão NEW com dívida (Stripe já cobrou) ✅
**Setup**: wallet=-1000, `create_order(payment_method=card, payment_already_confirmed=true, ...)`
**Resultado validado**:
| Campo | Esperado | Actual |
|---|---|---|
| `client_wallets.free_balance_cents` | 0 | 0 ✅ |
| Settlements idem='settle_create_order_*' | 1 | 1 ✅ |
| `orders.debt_collected_cents` | 1000 | 1000 ✅ |
| `orders.payment_status` | 'paid' | 'paid' ✅ |
| `orders.final_total` | 15.30 (sem dívida) | 15.30 ✅ |
| `orders.payment_buffer_total` | 29.10 (com dívida ×1.15) | 29.10 ✅ |

### Cenário 2 — CASH com dívida (NÃO zera) ✅
**Setup**: wallet=-1000, `create_order(payment_method=cash, ...)`
**Resultado**: balance=-1000 (preservada), settlements=0, debt_col=1000, payment_status=pending, final_total=15.30, buffer=29.10 ✅

### Cenário 3 — Trigger CASH dispara em delivered ✅
**Setup**: continuação do Cenário 2, `UPDATE orders SET status='delivered'`
**Resultado**: balance=0 (trigger CASH antigo disparou), settle_cash_tx=1, settle_paid_tx=0 ✅ (NOVO trigger NÃO dispara, filtro payment_method exclui cash)

### Cenário 4 — MBWay com dívida (NÃO zera) ✅
**Setup**: wallet=-1000, `create_order(payment_method=mbway, ...)`
**Resultado**: balance=-1000, settlements=0, debt_col=1000, status=pending, final_total=15.30, buffer=29.10 ✅

### Cenário 5 — Trigger payment_paid em MBWay paid ✅
**Setup**: continuação do Cenário 4, `UPDATE orders SET payment_status='paid'`
**Resultado**: balance=0, settle_paid_tx=1 (NOVO trigger disparou via UPDATE OF payment_status) ✅

### Cenário 6 — Sem dívida (regression) ✅
**Setup**: wallet=0, `create_order(payment_method=cash, ...)`
**Resultado**: balance=0, charge_total=15.30 (sem extras), debt_collected_cents=0, buffer=17.60 (15.30×1.15 sem dívida) ✅

### Cenário 7 — Idempotência duplo-delivered ✅
**Setup**: Cenário 3 já entregue (idem='settle_cash_<id>' inserido). Rollback fictício status→preparing, voltar a delivered.
**Resultado**: balance=0 (permanece), settle_tx=1 (NÃO duplicou — wallet_settle_debt retornou idempotent:true via SELECT prévio do idem_key) ✅

### Cenário 8 — Cancel CASH antes da entrega ✅
**Setup**: wallet=-1000, criar CASH, `UPDATE orders SET status='cancelled'`
**Resultado**: balance=-1000 (cliente continua a dever), settlements=0, status=cancelled ✅

### Cenário 9a — Cartão NEW estado actual (mecanismo 2 não mergeado) ✅
**Setup**: wallet=-1000, `create_order(payment_method=card, payment_already_confirmed=true, ...)` (sem webhook prévio)
**Resultado**: comportamento idêntico ao Cenário 1 — `v_wallet_balance_pre=-1000`, inline settle dispara, `debt_collected_cents=1000` ✅

### Cenário 9b — Simulação mecanismo 2 mergeado ✅
**Setup**: wallet=-1000 → `wallet_settle_debt('settle_pi_test_9b')` (simular webhook) → balance=0 → depois `create_order(payment_method=card, payment_already_confirmed=true)`
**Resultado**:
- `v_wallet_balance_pre=0` → bloco settle skip (balance>=0)
- `settle_create_tx=0` (NÃO criou nova settlement) ✅
- `pre_settle_tx=1` (settlement do "webhook" preservada)
- `orders.debt_collected_cents=0` (data hygiene — sem double-settle nem surplus indevido)
- `orders.payment_status='paid'`

**Sem double-settle, sem surplus.** Documenta data hygiene esperada se mecanismo 2 for mergeado no futuro.

### Cenário 9c — Surplus check em wallet zerada ✅
**Setup**: wallet=-1000 → 1ª `wallet_settle_debt(idem='A')` → wallet=0 → 2ª `wallet_settle_debt(idem='B')` (com idem-key DIFERENTE)
**Resultado**: 2ª chamada → `was_debt_cents=0, surplus_cents=1000, new_balance_cents=1000`. Validação SQL separada: `actual_balance=1000` (positivo).

**Comportamento esperado da spec PROMPT 2 — NÃO é bug.** `wallet_settle_debt` aceita amount > debt; excedente vira saldo positivo (100% free_balance_cents). Documentado em §54.

⚠️ **Atenção para o futuro**: se PROMPT 3 (mecanismo 2) for re-tentado, garantir que webhook E `create_order` NÃO chamem ambos settle no mesmo PI (Cenário 9b confirma que actualmente NÃO há colisão porque `create_order` faz skip quando balance>=0).

**Discrepância MCP detectada** (não-bug): em query única `SELECT wallet_settle_debt(...), (SELECT free_balance_cents FROM ...) AS balance_after`, o sub-SELECT pode ser avaliado ANTES da função pelo optimizer → `balance_after=0` enquanto a RPC retornava `new_balance_cents=1000`. Validação separada confirmou `actual_balance=1000`. Ordem de avaliação SELECT não é garantida.

---

## ANOMALIAS DETECTADAS DURANTE EXECUÇÃO (resolvidas)

1. **Order órfã** (`8ca13b5b-...`): primeiro tentativa CTE do Cenário 8 (`WITH new_order AS (SELECT create_order(...)->>'order_id'...) UPDATE...`) não retornou linha do RETURNING. A `create_order` foi executada (efeito colateral) mas o CTE ficou no plano. Refeito com query separada. Order órfã apagada no cleanup final.

2. **Wallet transactions related_order_id=NULL** após DELETE orders: porque `wallet_transactions.related_order_id` não tem `ON DELETE CASCADE`. Cleanup adicional por `idempotency_key`.

3. **Cenário 9c discrepância balance**: ordem de avaliação SELECT inline. Não-bug; comportamento esperado do PostgreSQL.

---

## ÁREAS PROIBIDAS RESPEITADAS

- ✅ Edge Functions: `dispatch-engine`, `upload-avatar`, `upload-receipt`, `stripe-webhook v23`, `create-payment-intent v27`, `create-mbway-payment-intent v19`, `finalize-order-from-intent v7`, `refund`, `cancel-order-with-choice v11`, `client-cancel-order v19`, `pay-debt-standalone v1`, `create-reservation-payment-intent` — **não tocadas**
- ✅ RPCs: `wallet_settle_debt`, `wallet_debit_cancel_fee`, `wallet_debit_for_order`, `wallet_credit_refund_split`, `wallet_apply_post_delivery_adjustment`, `quote_order_pricing`, `pricing_calculate`, `enforce_*` — não tocadas
- ✅ Triggers existentes: 17 anteriores (incluindo `apply_client_debt_settlement_on_cash_delivery`, `orders_cash_settlement`, `orders_auto_confirm_cod`, `orders_enforce_*`, `orders_financial_lock`, etc.) — não tocados
- ✅ Fluxo parceiro (`is_partner_store=true`) — não tocado
- ✅ Pasta `lib/` (Flutter) — **0 mudanças** (vai no PROMPT 4b)
- ✅ `business_rules.md` — **não tocado** (actualização vai no PROMPT 4b)

**Excepção desta sessão (aprovada)**: modificação cirúrgica em `create_order` RPC + ALTER TABLE add column + CREATE TRIGGER.

---

## PENDÊNCIAS PARA PROMPT 4b

### Driver UI — total a cobrar em CASH

**Problema**: estafeta vê `final_total=15.30` (sem dívida) mas tem de cobrar `final_total + debt_collected_cents/100 = 25.30` em pedidos CASH com dívida.

**Mapeamento necessário** (não feito nesta sessão, V2 grep retornou vazio em `lib/screens/driver_*.dart`):
1. Investigar [lib/models/order_model.dart](lib/models/order_model.dart) — adicionar campo `debtCollectedCents` + getter `totalToCollect = finalTotal + debtCollectedCents/100`
2. Investigar widget intermediário entre [lib/screens/driver_home_screen.dart](lib/screens/driver_home_screen.dart) e display do total
3. Adicionar UI text: "Cobrar do cliente: €X.XX (inclui €Y.YY de dívida anterior)"

### `business_rules.md` §54 — actualizar
- Mecanismo 1 (CASH): explicitar que `create_order` NÃO zera wallet antes da entrega (trigger CASH faz settle em delivered)
- Mecanismo 2 (Cartão NEW): explicitar `payment_already_confirmed=true` → inline settle correcto
- Mecanismo 2 (MBWay/Cartão LEGACY): adicionar info do trigger NOVO `apply_client_debt_settlement_on_payment_paid`
- Adicionar tabela matriz idem-keys (4 caminhos sem colisão)

### Race condition pedidos CASH paralelos (atenção, não fix)
Cliente devia €10, abre 2 pedidos CASH simultaneamente:
- Ambos têm `debt_collected_cents=1000` (estafetas cobram +€10 cada)
- Entrega A: trigger settle wallet=0 (idem='settle_cash_<A>')
- Entrega B: trigger dispara → `wallet_settle_debt` SELECT prévio detecta wallet=0 (não negativa) → retorna NO-OP via early return na função `fn_apply_client_debt_settlement_on_cash_delivery` (`IF v_balance >= 0 THEN RETURN NEW`)
- Mas estafeta B recolheu €10 extra que vai para... ele.

**Mitigation recomendada (PROMPT 4b ou futuro)**: bloquear novos pedidos CASH se já existe pending com `debt_collected_cents>0`. Ou tornar a dívida "locked" a 1 pedido específico.

---

## 5 COMMITS GRANULARES (a fazer)

1. `feat(orders): add debt_collected_cents column for driver UI display`
2. `fix(rpc): create_order - condicionar settle a payment_already_confirmed (zero impacto historico)`
3. `feat(trigger): apply_client_debt_settlement_on_payment_paid for mbway/card`
4. `chore(sync): 3 migrations from MCP applies`
5. `chore(reports): 2026-05-12_prompt_4a_create_order_settle_fix.md`

---

## OUTROS BUGS / INCONSISTÊNCIAS DETECTADOS FORA DO ESCOPO

1. **`wallet_max_negative_balance_cents=-1000` (€10) vs regra €40 em cancel**: inconsistência conhecida (§53/§54). Cliente que cancele 1× pedido CASH after_pickup de €40 fica wallet=-€40 → bloqueado de criar novo pedido até regularizar via mecanismo 3 (standalone). Decisão Danilo: aceitar como é.

2. **`stripe-webhook` v23 não reverte settlement em payment_failed/canceled**: era issue em MBWay/Cartão LEGACY no estado pré-fix. Agora **resolvido implicitamente** pelo FIX 2 (`create_order` NÃO faz settle prematuro → não há nada para reverter).

3. **Dependência implícita Cartão NEW**: Flutter envia `include_debt:true` → `quote_order_pricing` server-side → buffer com dívida → Stripe cobra. Comment recomendado em [lib/stores/cart_store.dart:201](lib/stores/cart_store.dart#L201) referenciando que o flag é essencial. **TODO PROMPT 4b.**

4. **Wallet transactions sem CASCADE em DELETE orders**: quando se apaga uma order, `wallet_transactions.related_order_id` fica NULL (não-cascade). Não é bug, mas pode causar dificuldade em queries `LEFT JOIN orders` para auditoria. Considerar ON DELETE SET NULL explícito (já é o comportamento default, apenas explicitar). Não-blocker.

5. **Order órfã durante teste**: bug de procedimento (CTE com `create_order` no SELECT não comportou-se como esperado em RETURNING). Mitigação: separar criação e UPDATE em queries distintas. Sem impacto em produção.

---

*Relatório gerado pelo Claude Code Opus 4.7 — 2026-05-12*
