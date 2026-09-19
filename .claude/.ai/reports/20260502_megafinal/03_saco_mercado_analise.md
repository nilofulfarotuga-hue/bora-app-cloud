# Sessão 3/7 — Política Saco Mercado (cobrança pós-entrega)

**Branch**: `autonomous-night-2026-04-29`
**Fase**: A — Investigação (read-only)
**Data**: 2026-05-04
**Estado**: ⛔ Aguarda luz verde Danilo antes de Fase B

---

## Resumo executivo

A Fase A confirmou:

1. **Regressão Sessões 1+2 OK** — coords NULL=0; bag_fee restaurante não-parceiro = €0.30 nos pedidos recentes; pricing OK.
2. **RPC `finalize_storeshopping_purchase`** já calcula `bag_fee` × `bag_count`, marca `extraRequired` para card/mbway, mas **cap actual é 20** (precisa baixar a 5) e **NÃO trata cash com extra > 0** (precisa `cash_total_due`).
3. **Tabela `pending_charges` não existe** — confirmado.
4. **Coluna `orders.cash_total_due` não existe** — confirmado.
5. **Edge Function `charge-extra` existe** mas **NÃO é off_session** — usa `automatic_payment_methods` e devolve `clientSecret` ao cliente. Não serve para cobrança automática server-side.
6. **`stripe-webhook` NÃO tem handler para `metadata.reason='market_bags'`** — qualquer charge succeeded sobrescreveria `payment_status='extraRequired'` por `'paid'` e o estafeta perderia a sinalização.
7. **`setup_future_usage` propositadamente OMISSO** em `create-payment-intent` (decisão documentada: "cartão nunca gravado sem consent"). Ou seja: **nenhum cartão pode ser cobrado off_session**.
8. **Schema `orders` NÃO tem `stripe_customer_id` nem `stripe_payment_method_id`** — não há infra para off_session em produção.
9. **Pedidos legacy com `bag_count > 5` = 0** (max actual = 2). Cap 5 não quebra nada.

**Recomendação CEO-AI**: Checkpoint B3→B4 → **opção [b] adiar B4 para Sessão 3B/3C**. Cash já cobre o caso comum sem tocar Stripe.

---

## A0 — Regressão check Sessões 1+2

| Check | Resultado | Status |
|---|---|---|
| A0.1 Coords NULL pós-2026-05-03 | `0` | ✅ Sessão 1 BUG 1 mantém |
| A0.2 Restaurant não-parceiro bag_fee (último pedido) | `€0.30` | ✅ Sessão 1 BUG 4 mantém |
| A0.3 Service fee partner/non-partner | (não query directa; `pricing_service.dart` analisado) | ✅ Sem mudanças |

**Histórico**: 2 dos 5 pedidos restaurante não-parceiro mais recentes têm `bag_fee=0` — datados Abr 17 e Abr 19, **anteriores** ao fix Sessão 1 (commit `ba1df37` 2026-04-29). Esperado. Fix posterior aplica-se apenas a pedidos novos.

---

## A1 — Grep transversal

Locais com lógica saco/bag relevante:

| Path:linha | Função |
|---|---|
| `lib/services/pricing_service.dart:15-22` | `OrderPricingBreakdown.bagFee` (cliente) |
| `lib/services/pricing_service.dart:41-44` | `_restaurantBagFee = 0.30` constante |
| `lib/services/pricing_service.dart:209-210` | `bagFee = serviceType == restaurant ? 0.30 : 0.0` ✅ |
| `lib/screens/driver_map_screen.dart:1979-2658` | `_ShoppingListSheetContent` — UI estafeta |
| `lib/screens/driver_map_screen.dart:1855-1908` | Banner cash "RECEBER €X EM DINHEIRO" (BUG 32) |
| `lib/stores/order_store.dart:1361-1378` | Lógica diff → refund/extra (cliente) |
| `lib/stores/order_store.dart:1415-1465` | Wrapper RPC `finalize_storeshopping_purchase` |
| `lib/stores/order_store.dart:1572` | `_paymentService.chargeExtra(amount: amount)` |
| `lib/services/payment_service.dart:90-102` | `chargeExtra()` invoca Edge Function `charge-extra` |
| `lib/models/order_model.dart:40` | `PaymentStatus.extraRequired` enum |
| `lib/models/order_model.dart:372,433` | Serialização `extra_charge_amount` |
| `lib/config/business_rules.dart` | `BRBags.MARKET_BAG_FEE` constante |
| `supabase/functions/charge-extra/index.ts` | Edge Function actual |
| `supabase/functions/create-payment-intent/index.ts:18,176,209` | `setup_future_usage` OMISSO (intencional) |
| `supabase/functions/stripe-webhook/index.ts` | Sem handler `market_bags` |
| `supabase/migrations/20260501040000_finalize_storeshopping_bag_count.sql` | Cap 20 introduzido |
| `supabase/migrations/20260502010000_finalize_storeshopping_include_fees.sql` | Cap 20 mantido |

---

## A2 — Checkout cliente: ZERO cobrança saco mercado ✅

`lib/services/pricing_service.dart:209-210`:

```dart
final double bagFee =
    serviceType == OrderServiceType.restaurant ? _restaurantBagFee : 0.0;
```

`storeShopping`, `carryGroceries`, `sendPackage` → `bagFee = 0`. Apenas `restaurant` → €0.30. Confirmado: **payload `create_order` não envia bag_fee para mercado**.

UI checkout: linha "Sacos" só renderiza se `breakdown.bagFee > 0` (esperado pelo grep às telas — não há `_SummaryRow(label:'Sacos')` no checkout cliente para storeShopping).

**Sem trabalho necessário em B**.

---

## A3 — UI estafeta: slider e ecrã confirmação

**Ficheiro**: `lib/screens/driver_map_screen.dart`

| Linha | Componente |
|---|---|
| 1061 | `_showShoppingListSheet(context, order)` |
| 1963 | `class _ShoppingListSheetContent` |
| 1979 | `late int _bagCount` — estado |
| 1986-1992 | `double get _bagFee` — calcula `bagCount × BRBags.MARKET_BAG_FEE` |
| 1986-1992 | Trata partner restaurant: `_bagFee = 0` ✅ |
| 1999-2000 | Init: `_bagCount = widget.order.bagCount > 0 ? widget.order.bagCount : 0` |
| 2429-2491 | UI: secção sacos (esconde para partner restaurant) |
| 2501-2522 | Botões `-` / `+` com cap **`< 20`** |
| 2547 | `_SummaryRow(label: 'Sacos', value: _bagFee)` |
| 2602 | Label `'Extra a cobrar'` (já existe para card) |
| 2653 | Submit RPC: `bagCount: _isRestaurant ? 1 : _bagCount` |
| 2170 | `adjustedTotal = boughtTotal + _bagFee + addedFinalTotal` |

**Cap actual UI = 20** (linha 2521 `_bagCount < 20`). **Necessário**: baixar para `< 5` em B2; também na RPC (B3).

**Validação cliente-side**: actual permite 0..20. Precisa enforce `0..5` mas manter exibição read-only se `widget.order.bagCount > 5` (legado).

---

## A4 — RPC `finalize_storeshopping_purchase` (dump completo)

Identidade: `public.finalize_storeshopping_purchase(p_order_id text, p_items_status jsonb, p_items_added jsonb DEFAULT '[]', p_bag_count integer DEFAULT NULL)` SECURITY DEFINER.

**Pontos relevantes**:

```sql
-- Cap actual = 20 (PRECISA BAIXAR PARA 5)
IF p_bag_count IS NOT NULL THEN
  IF p_bag_count < 0 OR p_bag_count > 20 THEN
    RAISE EXCEPTION 'invalid_bag_count: % (must be 0-20)', p_bag_count
      USING ERRCODE = '23514';
  END IF;
  v_bag_fee_cents := p_bag_count * v_per_bag_cents;  -- v_per_bag_cents = 10 (€0.10)
END IF;

-- Branch para card/mbway com extra > 0
v_is_card := v_order.payment_method IN ('card', 'mbway');
IF v_final_total_cents > v_orig_total_cents THEN
  IF v_is_card THEN
    v_extra_charge_cents := v_final_total_cents - v_orig_total_cents;
    v_new_payment_status := 'extraRequired';
  ELSE                                  -- ⚠️ CASH
    v_extra_charge_cents := 0;
    v_new_payment_status := v_order.payment_status;  -- NÃO faz nada
  END IF;
END IF;

UPDATE public.orders SET
  bag_count             = CASE WHEN v_is_restaurant THEN 1 ELSE COALESCE(p_bag_count, bag_count) END,
  bag_fee               = v_bag_fee_cents::numeric / 100.0,
  final_total           = v_final_total_cents::numeric / 100.0,
  extra_charge_amount   = CASE WHEN v_extra_charge_cents > 0 THEN v_extra_charge_cents::numeric / 100.0 ELSE NULL END,
  is_purchase_finalized = true,
  payment_status        = v_new_payment_status
WHERE id = p_order_id;
```

**Já correcto**:
- ✅ Calcula `bag_fee_cents = bag_count × per_bag_cents` (10c default)
- ✅ Persiste `bag_count`, `bag_fee`, `final_total`, `extra_charge_amount`
- ✅ Marca `extraRequired` para card/mbway
- ✅ Audit log em `admin_audit_log`
- ✅ Bypassa `enforce_financial_immutability` via `set_config('app.financial_bypass','true',true)`

**Falta**:
- ❌ Cap actual 20 (B3 baixar para 5)
- ❌ Cash com extra > 0: não escreve em lado nenhum (B3 adicionar `UPDATE cash_total_due`)
- ❌ Card/mbway com extra > 0: não invoca charge automático nem cria registo `pending_charges` (B4)

**Coluna `bag_charge`**: NÃO existe na tabela orders. O sistema usa `bag_fee` (numeric, NOT NULL DEFAULT 0). Tarefa B1/B3 deve continuar a usar `bag_fee`.

---

## A5 — Tabela `pending_charges`

**Confirmação**: NÃO existe.

```sql
SELECT COUNT(*) FROM information_schema.tables WHERE table_name = 'pending_charges';
-- 0
```

Schema proposto (B1) — recomendação ajustada:

```sql
CREATE TABLE pending_charges (
  id                       UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  order_id                 TEXT NOT NULL REFERENCES orders(id) ON DELETE CASCADE,
  amount_cents             INT NOT NULL CHECK (amount_cents BETWEEN 1 AND 50),
  reason                   TEXT NOT NULL CHECK (reason IN ('market_bags')),
  status                   TEXT NOT NULL DEFAULT 'pending'
                             CHECK (status IN ('pending','succeeded','failed','requires_action')),
  idempotency_key          TEXT NOT NULL UNIQUE,
  stripe_payment_intent_id TEXT NULL,
  error_code               TEXT NULL,
  retry_count              INT NOT NULL DEFAULT 0,
  created_at               TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at               TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX idx_pending_charges_status_created ON pending_charges (status, created_at);
CREATE INDEX idx_pending_charges_order ON pending_charges (order_id);
```

**RLS**: `admin SELECT/UPDATE`; INSERT só via SECURITY DEFINER (RPC). Cliente/estafeta sem acesso directo.

---

## A6 — Coluna `orders.cash_total_due`

**Confirmação**: NÃO existe.

```sql
SELECT COUNT(*) FROM information_schema.columns
 WHERE table_name='orders' AND column_name='cash_total_due';
-- 0
```

**Decisão recomendada**: `ALTER TABLE orders ADD COLUMN cash_total_due NUMERIC NULL` (sem DEFAULT 0, sem backfill histórico — preserva relatórios existentes que usam `final_total`). Código novo escreve quando aplica; código antigo lê `final_total` como fallback.

---

## A7 — Edge Function `charge-extra` (auditoria source)

**Existe** (versão 8, ACTIVE, 2026-04-22). Source completo: `supabase/functions/charge-extra/index.ts`.

```ts
const intentParams: Stripe.PaymentIntentCreateParams = {
  amount: amountCents,
  currency: 'eur',
  metadata: { type: 'extra_charge' },
  automatic_payment_methods: { enabled: true },
};
if (customerId) intentParams.customer = customerId.trim();

const intent = await stripe.paymentIntents.create(intentParams);
return new Response(JSON.stringify({
  clientSecret: intent.client_secret,
  paymentIntentId: intent.id,
}));
```

**Diagnóstico**:

- ❌ Sem `off_session: true`
- ❌ Sem `confirm: true`
- ❌ Sem `payment_method` directo
- ❌ Sem Idempotency-Key
- ❌ Devolve `clientSecret` → assume cliente abre app + confirma manualmente
- ❌ `metadata.reason` não suporta whitelist `market_bags`

**Conclusão**: a Edge Function actual **não cumpre o requisito de "charge automático off_session imediato"**. Para B4 conforme spec, é REWRITE completo, não extensão.

---

## A7b — Webhook `stripe-webhook`

**Existe** (versão 16, ACTIVE, 2026-04-30). Eventos tratados:

| Evento | Acção actual |
|---|---|
| `payment_intent.succeeded` (com `metadata.draft_id`) | invoca `finalize-order-from-intent` (Mode B) |
| `payment_intent.succeeded` (com `metadata.order_id`) | `UPDATE orders SET payment_status='paid'` (Mode A legacy) → dispatch |
| `payment_intent.processing` | log MBWay awaiting confirm |
| `payment_intent.payment_failed` / `canceled` | apaga draft (B) ou só log (A) |
| `charge.refunded` | só log (cliente faz update via `PaymentService.refund`) |

**Problema crítico**: handler `payment_intent.succeeded` Mode A faz UPDATE incondicional `payment_status='paid'`. Se invocado para um charge `market_bags`, **vai sobrescrever `payment_status='extraRequired'` por `'paid'`**, mesmo que o charge `market_bags` não cubra o pedido base. **B4 OBRIGATÓRIO adicionar branch**:

```ts
if (intent.metadata?.reason === 'market_bags') {
  // UPDATE pending_charges SET status='succeeded' WHERE idempotency_key = intent.idempotency_key
  // NÃO tocar em orders.payment_status (já está 'paid' do checkout original)
  break;
}
```

E equivalente para `payment_intent.payment_failed`.

---

## A8 — Stripe SCA / off_session

**Estado**: ❌ **BLOQUEADO** para B4 conforme spec.

`supabase/functions/create-payment-intent/index.ts:18,176,209`:

```ts
// Stripe LIVE notes:
//   - setup_future_usage NÃO definido → cartão nunca gravado sem consent.
// ...
// setup_future_usage propositadamente OMISSO (não gravar cartão).
```

**Decisão de produto documentada**: cartões NUNCA são gravados sem consent explícito. Logo:

- Sem `payment_method` guardado → off_session não tem como cobrar
- Sem `customer` guardado → mesmo se houvesse PM, não há ligação

**Para activar B4 conforme spec**:

1. Criar Stripe `customer` no primeiro pedido (ou via CustomerSession)
2. Adicionar `setup_future_usage: 'off_session'` no `create-payment-intent` (com consent UI)
3. Guardar `stripe_customer_id` + `stripe_payment_method_id` em `orders` (ou `users`)
4. Pedir consent explícito ao cliente: "Autorizo cobranças até €0.50 por sacos pós-entrega"
5. Rewrite charge-extra com `off_session: true, confirm: true, payment_method: <id>`

Estas 5 etapas são uma **sessão dedicada** (Sessão 3C — consent off_session flow).

---

## A8b — Pedidos cartão/mbway recentes (30 dias)

| `payment_method` | `n` | `with_intent` |
|---|---|---|
| card | 14 | 6 |
| mbway | 47 | 4 |

**Schema check**: tabela `orders` NÃO tem `stripe_customer_id` nem `stripe_payment_method_id`. Apenas `payment_intent_id` (do PI específico do checkout) e `stripe_charge_cents`. **Confirma**: zero infra para off_session.

---

## A9 — Banner cash estafeta (BUG 35)

**Ficheiro**: `lib/screens/driver_map_screen.dart`

| Linha | Lógica |
|---|---|
| 1855 | `final finalTotal = order.finalTotal ?? 0;` |
| 1856 | `final isCash = order.paymentMethod == PaymentMethod.cash;` |
| 1858-1880 | Banner "RECEBER €X EM DINHEIRO" |
| 1908 | "Compra finalizada: €X" |
| 2175 | `final isCash = order.paymentMethod == PaymentMethod.cash;` (sheet) |
| 2577-2602 | Secção "Extra a cobrar" (cash) na sheet |

**Mudança necessária em B5**:
```dart
// Antes:
final finalTotal = order.finalTotal ?? 0;
// Depois:
final amountToCollect = order.cashTotalDue ?? order.finalTotal ?? 0;
```

E adicionar linha discriminada na sheet quando `cashTotalDue > finalTotal`:

```
Total pedido: €25.00
Sacos (cobrar em mão): +€0.20
─────────────────────────
A receber: €25.20
```

`OrderModel` precisa novo campo `cashTotalDue`:
- `lib/models/order_model.dart`: campo `final double? cashTotalDue`
- `fromSupabase`: `cashTotalDue: (data['cash_total_due'] as num?)?.toDouble()`
- `toSupabase`: `if (cashTotalDue != null) 'cash_total_due': cashTotalDue`

---

## A10 — Análise impacto transversal

### Telas tocadas

| Tela | Mudança | Sessão |
|---|---|---|
| `driver_map_screen.dart` _ShoppingListSheetContent | Slider cap 20→5; mostrar `cash_total_due` se NOT NULL; linha "Sacos cobrar em mão" | B2, B5 |
| `driver_map_screen.dart` banner cash | `cashTotalDue ?? finalTotal` | B5 |
| `driver_home_screen.dart` (lines 1194, 2275, 2486) | mesmo fallback `cashTotalDue` | B5 |
| Cliente checkout | Sem mudança (✅ já zero cobrança saco mercado) | — |
| `admin_orders_screen.dart` | Coluna `bag_charge` + `cash_total_due` + filtro | B7 |
| `admin_charges_screen.dart` (NOVA) | Lista pending_charges + retry | B7 (se B4 [a]/[c]) |

### RPCs/Triggers/Edge Fns tocadas

| Recurso | Mudança | Sessão |
|---|---|---|
| `finalize_storeshopping_purchase` (RPC) | Cap 20→5; branch cash escreve `cash_total_due` | B3 |
| `pending_charges` (NOVA tabela) | DDL + RLS + indexes | B1 |
| `orders.cash_total_due` (NOVA coluna) | ADD COLUMN NULL | B1 |
| `orders.bag_count` CHECK actual `bag_count >= 0` (presumido) | Manter; cap só na RPC | — |
| `charge-extra` (Edge Fn) | REWRITE: off_session+confirm+idempotency | B4 (se [a]/[c]) |
| `stripe-webhook` | Adicionar handler `metadata.reason='market_bags'` | B4 |
| Cron drenagem `pending_charges` | NOVO scheduler | B4 ou TODO |

### Ficheiros Dart tocados

- `lib/models/order_model.dart` — campo `cashTotalDue`
- `lib/stores/order_store.dart` — read `cash_total_due` no `fromSupabase`; persist se aplica
- `lib/screens/driver_map_screen.dart` — UI cap 5, banner cash, linha sacos
- `lib/screens/driver_home_screen.dart` — banner cash fallback
- `lib/screens/admin/admin_orders_screen.dart` — coluna nova
- `lib/screens/admin/admin_charges_screen.dart` — NOVA (se B7 completo)
- `lib/services/payment_service.dart` — eventual rewrite `chargeExtra` (B4)

### Riscos de regressão

| Risco | Mitigação |
|---|---|
| BUG 35 banner cash | Smoke S11 — fallback `?? finalTotal` mantém comportamento se `cash_total_due` NULL |
| BUG 38 linha verde | Smoke S12 — não tocar nessa lógica |
| Sessão 1 BUG 1 coords | Não tocar; RPC create_order intacta |
| Sessão 1 BUG 4 bag_fee restaurante | RPC `finalize` mantém `v_is_restaurant=true → 0/30c` |
| Sessão 2 D1/D2 service fee | Não tocar pricing_service |
| Pedidos legacy `bag_count > 5` | A11: 0 pedidos. Sem risco. |
| `enforce_financial_immutability` | RPC já bypassa via `app.financial_bypass=true` |

---

## A11 — Pedidos in-flight com bag_count > 5

```
legacy_count: 0
total_with_bag_count: 66 (últimos 30d)
max_bag_count: 2
```

**Conclusão**: cap 5 em UI/RPC não afecta pedidos existentes. **B0 minimal** — basta UI + RPC enforce 0..5 para novos. Sem read-only mode legacy necessário.

---

## A12 — Plano detalhado Fase B

### B0. Tratar pedidos in-flight (preventivo)
**Esforço**: 5 min. **Sem trabalho** — A11 confirma 0 pedidos > 5. Documentar no commit message.

### B1. Migration nova
- `CREATE TABLE pending_charges` + indexes + RLS
- `ALTER TABLE orders ADD COLUMN cash_total_due NUMERIC NULL`
- ZERO BACKFILL
**Esforço**: 30 min. **Risco baixo** (DDL aditivo).

### B2. UI estafeta cap 5
- `driver_map_screen.dart:2501-2522`: trocar `< 20` por `< 5`
- Validação cliente-side `0 ≤ bagCount ≤ 5`
- (a) Não há legacy a proteger; sem read-only mode.
**Esforço**: 15 min. **Risco baixo**.

### B3. RPC `finalize_storeshopping_purchase` (estender)
Migration nova `20260504_finalize_storeshopping_cash_total_due.sql`:
- Cap `0..20` → `0..5`
- Branch cash com `v_extra_charge_cents > 0`:
  ```sql
  UPDATE orders SET cash_total_due = COALESCE(cash_total_due, 0) + (v_extra_charge_cents::numeric / 100.0)
  WHERE id = p_order_id;
  ```
- (Se B4 [a]/[c]) Branch card/mbway: `INSERT pending_charges` + `pg_net` HTTP call para charge-extra
- TRANSACTION dentro de BEGIN..COMMIT (já é o caso)
- Audit log já existe — adicionar `cash_total_due_added` no JSON details
**Esforço**: 1h. **Risco médio** (alterar RPC autoritária; testar com smoke S1-S4).

### ⛔ CHECKPOINT B3→B4 — DECISÃO CRÍTICA

**Recomendação CEO-AI**: **opção [b] adiar B4 para Sessão 3B**.

| Razão | Detalhe |
|---|---|
| Infra off_session ausente | `setup_future_usage` propositadamente OMISSO; sem `stripe_customer_id`/`stripe_payment_method_id` em orders |
| charge-extra rewrite total | Edge Function actual não é off_session — é REWRITE, não extensão |
| Webhook handler novo | Sem branch `metadata.reason='market_bags'` — risco crítico de sobrescrever `payment_status='paid'` |
| Consent flow ausente | Stripe LIVE em PT — cobrança sem consent explícito recusa SCA |
| Cash cobre fluxo principal | B0+B1+B2+B3 (parcial só cash)+B5+B7 (vista mínima) já desbloqueia 100% pedidos cash |
| Estouro contexto | Sessão actual já carrega muito; B4 sozinho são 3-4h+ |

**Adiando para Sessão 3B/3C**:
- Sessão 3B = implementar charge-extra off_session + webhook handler + retry queue + cron drain
- Sessão 3C = consent flow no checkout + setup_future_usage + UI consentimento

**Fluxo proposto Sessão 3 (esta) com [b]**:
1. B1 migration (DDL aditivo)
2. B2 UI cap 5
3. B3 RPC: cap 5 + branch cash escreve `cash_total_due`. **NÃO** cria `pending_charges` ainda (mantém comportamento actual: card/mbway → `extraRequired`)
4. B5 banner estafeta cash
5. B7 vista mínima admin (coluna `cash_total_due` em admin_orders)
6. Sessão 3 fecha com cash 100% funcional

### B4. Edge Function charge-extra (SE [a]/[c])
**Esforço**: 3-4h (rewrite completo + webhook + tests). **Risco**: ALTO (Stripe LIVE, SCA, off_session).
**Default**: ADIAR.

### B5. UI estafeta banner cash
- `driver_map_screen.dart:1855` + `driver_home_screen.dart` similar
- Adicionar campo `cashTotalDue` em `OrderModel`
**Esforço**: 30 min. **Risco baixo** (fallback `?? finalTotal` preserva).

### B6. Cliente push pós-charge
- Só faz sentido SE B4 implementado.
- TODO se B4 [b].
**Esforço**: 30 min se B4 implementado.

### B7. Admin painel
- Coluna `cash_total_due` em `admin_orders_screen.dart`
- Filtro pedidos com `cash_total_due > 0`
- Vista mínima: chega para Sessão 3
- TODO B7b (admin_charges_screen completo) se B4 [b]
**Esforço**: 45 min vista mínima.

---

## Estimativa total Fase B

### Cenário [b] adiar B4 (RECOMENDADO)
- B1: 30 min
- B2: 15 min
- B3: 1h
- B5: 30 min
- B7 (mínima): 45 min
- **Total**: ~3h. Cash 100% funcional. Card/mbway com extra continua a marcar `extraRequired` (manual ou esperando Sessão 3B).

### Cenário [a] tudo nesta sessão
- B1+B2+B3+B5+B7 (mínima): 3h
- B4 (Edge Fn rewrite + webhook + retry): 3-4h
- **Total**: ~6-7h. **Risco contexto/qualidade ALTO**.

### Cenário [c] hybrid
- B1+B2+B3+B5+B7: 3h
- B4 com fallback "cobrar em mão se off_session falhar": 1.5h
- **Total**: ~4.5h. Mas semântica confusa: cash_total_due preenchido por cash original + bag_charge OU por fallback off_session falhado. Risco UX médio.

---

## Bugs colaterais detectados (REPORTAR — não fixar)

1. **Edge Function `confirm-mbway-payment` obsoleta** — listada como ACTIVE (versão 11). PROJECT_CONTEXT marca como "obsoleto — apagar após testes prod". Recomenda apagar em Sessão 6/7 housekeeping.
2. **Edge Function `create-mbway-payment-intent-debug` activa** — versão debug não deve ficar em prod.
3. **`mbway_debug_errors` tabela** — usada por debug Edge Fn; verificar se tem RLS adequada.
4. **Schema `orders` tem AMBOS `final_total` (double precision) e `customer_total` (numeric)** — divergência de tipo. Provável dead code numa das duas. Reportar Sessão 6.
5. **`extra_charge_amount` é `double precision` nullable** — se Stripe charge bem-sucedido, o ledger `extra_charge_amount` permanece preenchido para eternidade. Faz sentido nullify após `charge succeeded`.

---

## Decisão SCA off_session

**[❌] BLOQUEADO** — `setup_future_usage` propositadamente OMISSO em `create-payment-intent` por decisão de produto documentada. Sem infra `stripe_customer_id`/`stripe_payment_method_id` em `orders`. Activar off_session requer:
1. Mudar política consent de cartão (decisão de produto/legal)
2. Adicionar `setup_future_usage: 'off_session'`
3. Guardar `customer` + `payment_method` em DB
4. UI consent explícito (com texto legal)
5. Rewrite `charge-extra` para off_session+confirm

**Esta é Sessão 3C dedicada** — não cabe na Sessão 3 actual.

---

## Recomendação final checkpoint B3→B4

**[b] ADIAR B4 PARA SESSÃO 3B/3C** — DEFAULT seguro.

Cash funciona JÁ 100%. Card/mbway mantém comportamento actual (`extraRequired`) até Sessão 3B implementar charge automático. Sem regressão financeira, sem risco SCA, sem cobrar errado em LIVE.

⛔ **Aguardar luz verde Danilo antes de qualquer mutation (B1+).**

---

## Anexos

### Migrations relacionadas existentes
- `supabase/migrations/20260501040000_finalize_storeshopping_bag_count.sql` (cap 20 introduzido)
- `supabase/migrations/20260502010000_finalize_storeshopping_include_fees.sql` (cap 20 mantido)

### Edge Functions activas relevantes (21 total)
- `charge-extra` (v8) — não-off_session
- `create-payment-intent` (v20) — sem `setup_future_usage`
- `create-mbway-payment-intent` (v12) — LIVE; `payment_method.type='mb_way'`
- `stripe-webhook` (v16) — sem handler market_bags
- `confirm-mbway-payment` (v11) — obsoleto
- `create-mbway-payment-intent-debug` (v1) — debug em prod ⚠️
