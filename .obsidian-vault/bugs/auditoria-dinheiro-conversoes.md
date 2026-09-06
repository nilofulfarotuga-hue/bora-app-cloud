# Auditoria Dinheiro & Conversões — Completa
> Data: 2026-04-24
> Objectivo: zero erros de cêntimo, zero perdas, conformidade Stripe / MBWay
> Repo auditado: `C:\Users\danil\Desktop\projetosflutter\bora_app\`
> Confronto contra: `~/.claude/skills/ceo-ai/SKILL.md` §5 Business Rules + `lib/config/business_rules.dart` (canónico)

---

## 1. Mapa de unidades (EUR float vs cêntimos int)

| Camada | Função / ficheiro | Unidade in | Unidade out | Conversão |
|---|---|---|---|---|
| Flutter | `PricingService.calculateBreakdown` (`lib/services/pricing_service.dart:86`) | EUR `double` | EUR `double` (campos do `OrderPricingBreakdown`) | `_roundCurrency(v) = double.parse(v.toStringAsFixed(2))` ⇒ **round half-to-even (Dart `toStringAsFixed`)** |
| Flutter | `PricingService.applyMarkup` (`pricing_service.dart:81`) | EUR `double` | EUR `double` | `_roundCurrency` |
| Flutter | `PricingService.calculateBufferedTotal` (`pricing_service.dart:74`) | EUR `double` | EUR `double` (× 1.15) | `_roundCurrency` |
| Flutter | `PaymentService.createPaymentIntent` (`lib/services/payment_service.dart`) | EUR `double` | envia EUR `double` para Edge Function | (nenhuma) — server converte |
| Flutter | `PaymentService.refund` | EUR `double` | envia EUR `double` p/ EF | (nenhuma) |
| Flutter | `PaymentMethodScreen` token discount (`lib/screens/payment_method_screen.dart:74-85`) | EUR `double` | EUR `double` | `floor()` na contagem de tokens, sem `_roundCurrency` no `tokenDiscount` |
| Edge | `create-payment-intent/index.ts` | recebe EUR `number` | envia **cêntimos int** p/ Stripe | `Math.round(order.payment_buffer_total * 100)` |
| Edge | `create-mbway-payment-intent/index.ts:63` | lê `payment_buffer_total` (EUR num) | **cêntimos int** | `Math.round(order.payment_buffer_total * 100)` |
| Edge | `refund/index.ts` | EUR `number` (input do cliente) | **cêntimos int** | `Math.round(amount * 100)` |
| Edge | `charge-extra/index.ts` | EUR `number` | **cêntimos int** | `Math.round(amount * 100)` |
| Edge | `client-cancel-order/index.ts` | EUR `number` (DB) | **cêntimos int** Stripe | `Math.round(refundEur * 100)` (após `Number((totalEur - feeEur).toFixed(2))`) |
| Edge | `stripe-webhook/index.ts:48-103` | recebe `intent.amount` (cêntimos) | **não converte de volta** | — só faz update `payment_status` |
| Backend Node mirror | `backend/server.js` `toCents()` | EUR `number` | **cêntimos int** | `Math.round(euros * 100)` |
| SQL | `fn_award_tokens_on_delivery` (`supabase/migrations/20260404000000_bora_tokens.sql:136-174`) | `NEW.price` (NUMERIC EUR) | tokens (INT) | `GREATEST(1, ROUND(NEW.price * 0.03)::INTEGER)` |

---

## 2. Bugs Críticos de Dinheiro

### 🔴 [BUG-MN-001] Webhook não reconcilia o valor cobrado vs `payment_buffer_total`
**Ficheiro:** `supabase/functions/stripe-webhook/index.ts:48-66`

O `payment_intent.succeeded` faz apenas `update payment_status='paid'`. **Nunca compara `intent.amount_received` (cêntimos) contra `orders.payment_buffer_total * 100`**. Consequência: se um cliente conseguir manipular a chamada cliente→EF e a deviation cair dentro de ±5%, podemos cobrar 0,95×total e marcar como pago sem alarme. Mais: refunds parciais via `charge.refunded` ficam apenas em `console.log` (linha 158-164) e delegam toda a actualização de `refund_amount`/`payment_status` ao Flutter — quebra de fonte da verdade. Se o cliente nunca abrir o app de novo o estado nunca é actualizado em DB.

**Fix:** validar `intent.amount_received` contra `payment_buffer_total*100` no webhook (tolerância 0). Tratar `charge.refunded` no servidor: `update orders set refund_amount = charge.amount_refunded/100, payment_status = (amount_refunded == charge.amount ? 'refunded' : 'partial_refund')`.

### 🔴 [BUG-MN-002] Tolerância ±5% no `create-payment-intent` permite até 5% de underpayment
**Ficheiro:** `supabase/functions/create-payment-intent/index.ts` (`AMOUNT_TOLERANCE = 0.05`)

A tolerância existe para non-partner buffer (1.15×) mas o cálculo do buffer já está determinístico (`PricingService.calculateBufferedTotal`). Não há razão para o cliente enviar valor diferente do `payment_buffer_total` que ele acabou de criar. Resultado: numa ordem de €40 podemos aceitar pagamento de €38 (= 5% perdido = €2). **Em 1000 pedidos/dia isto vale ~€60/dia em buracos**.

**Fix:** ignorar completamente o `amount` enviado pelo cliente — usar `serverAmount = order.payment_buffer_total` e cobrar isso sempre. O parâmetro `amount` no body deve ser apenas para detecção de mismatch (log + erro), nunca para cobrar.

### 🔴 [BUG-MN-003] `_useTokens` aplicado **fora** do `payment_buffer_total` da ordem
**Ficheiro:** `lib/screens/payment_method_screen.dart:74-85` cruzado com `lib/stores/order_store.dart` (criação da ordem)

O cálculo `finalPrice = totalToPay - tokenDiscount` é local no ecrã, **mas** o `paymentBufferTotal` da ordem que vai para a DB é recalculado a partir do `pricingBreakdown` (sem desconto de tokens). Em `checkout_screen.dart` (excerto indexado) usa-se `createdOrder.paymentBufferTotal` para o Stripe — **isto não inclui o `tokenDiscount`**. Logo: cliente pensa que paga €X−tokens, mas o intent é criado por €X completo. Pior: `consume_tokens` RPC só é referenciado em `driver_earnings_screen.dart:_convertTokens` para conversão driver→saldo, **não vi nenhum ponto no fluxo do cliente que invoque `consume_tokens(role='client')` no checkout** → tokens nunca são debitados no resgate.

**Fix:** (a) no client-side, antes de `createOrder`, chamar `consume_tokens(p_role='client', p_amount=tokensToUse)` e abater do `payment_buffer_total` antes de persistir. (b) revalidar no server (EF) que `payment_buffer_total` reflecte `total - tokenDiscount`.

### 🔴 [BUG-MN-004] Refund EF: `amount` enviado pelo cliente sem cap contra `payment_buffer_total`
**Ficheiro:** `supabase/functions/refund/index.ts`

Embora exija `service_role` (mitigado), a EF não verifica que `amount ≤ paymentIntent.amount`. Um operador admin pode acidentalmente reembolsar mais do que foi cobrado (Stripe rejeita, mas só após chamada — não há guard local).

**Fix:** `await stripe.paymentIntents.retrieve(paymentIntentId)` e validar `amountCents <= pi.amount - already_refunded`. Idempotência: aceitar `idempotency_key` no header e passar a `stripe.refunds.create({ ... }, { idempotencyKey })`.

### 🔴 [BUG-MN-005] `_roundCurrency` usa `toStringAsFixed(2)` (banker's rounding) — incoerente com `Math.round` server
**Ficheiro:** `lib/services/pricing_service.dart:205-207`

Dart `toStringAsFixed(2)` faz **round-half-to-even** (banker's). JS `Math.round` faz **round-half-up**. Em casos como `1.225` Dart→`1.22`, JS→`1.23` (1 cêntimo de discrepância). Quando o EF compara `client.amount` vs `serverAmount` (`payment_buffer_total` que a Flutter calculou e gravou), ambos os lados consomem a mesma string, **mas** quando Stripe converte para cents (`Math.round(*100)`) e quando refund é calculado por `Number((totalEur - feeEur).toFixed(2))` (`client-cancel-order/index.ts`) usamos uma terceira convenção (`toFixed` em V8 = round-half-away-from-zero). Três regras de arredondamento diferentes na mesma transacção.

**Fix:** centralizar uma única convenção: cêntimos int desde a origem (item.price em cents). Toda a aritmética em int. Conversão para EUR só na UI. Ou no mínimo: unificar arredondamento em `Math.round(value*100)/100` no Flutter e `Math.round` no JS.

### 🔴 [BUG-MN-006] `tokenDiscount` é float, sem `_roundCurrency`
**Ficheiro:** `lib/screens/payment_method_screen.dart:82-83`

`tokenDiscount = tokensToUse * 0.005` → para 73 tokens = `0.365` (exacto), mas para 67 tokens = `0.335` que `(totalToPay - 0.335)` em IEEE-754 pode dar `9.665000000000001`. Stripe recebe `Math.round(x*100)` → resultado correcto neste caso, mas se o `paymentBufferTotal` for gravado em DB com float, fica registo `9.665000000000001` (depende do `numeric` precision da column).

**Fix:** `final tokenDiscount = double.parse((tokensToUse * BRTokens.TOKEN_VALUE_EUR).toStringAsFixed(2))`. Idem para `finalPrice`.

### 🔴 [BUG-MN-007] Cash limit (€40) só enforced client-side
**Ficheiro:** `lib/config/business_rules.dart:107-111` (comenta "client validation is UX only", "DB trigger `enforce_cash_payment_limit` enforces server-side")

A grep nas migrations não encontra a função `enforce_cash_payment_limit` definida (só referência ao nome no comentário). Se o trigger não existir, um cliente que manipule o app pode criar ordem cash com €200. Confirmar com `mcp__supabase__list_migrations` ou `execute_sql` que a função existe efectivamente.

**Fix:** confirmar trigger SQL ou criar `CHECK (payment_method != 'cash' OR total <= 40.00)` na coluna.

### 🔴 [BUG-MN-008] Trigger de tokens calcula 3% sobre `NEW.price` — definição ambígua
**Ficheiro:** `supabase/migrations/20260404000000_bora_tokens.sql:163`
```sql
v_client_tokens := GREATEST(1, ROUND(NEW.price * 0.03)::INTEGER);
```

`orders.price` no `OrderModel.toJson` (`lib/models/order_model.dart`) é mapeado como `'price': total` — **`total` inclui delivery fee + service fee + bag**. Regra do projecto diz "Cliente: 3% do **valor**". Se "valor" = subtotal de produtos (não inclui taxas), o trigger está a sobre-recompensar (3% × total > 3% × subtotal). Para um pedido €30 subtotal + €5 delivery + €2 service + €0.30 bag = €37.30, o cliente recebe `ROUND(37.30 × 0.03) = 1` token (porque arredonda para 1; mas em €100 subtotal seria `ROUND(107×0.03)=3` em vez de `ROUND(100×0.03)=3` — diferença pequena, mas cresce em ordens grandes).

Adicionalmente, SKILL.md dizia "Cliente: 50 tokens por entrega (taxa 3%)" — **fixed 50 vs 3%-of-price** são duas regras distintas. Código usa 3%-of-price com mínimo 1 (não 50 fixos). Documentação inconsistente — escolher uma fonte.

**Fix:** decidir e documentar. Recomendo: usar `subtotal` (não `price`) e remover ambiguidade na SKILL.md.

---

## 3. Bugs Médios

### 🟡 [BUG-MN-009] Markup non-partner aplicado **dentro** dos `cart_item.price` antes do breakdown
**Ficheiro:** `lib/services/pricing_service.dart:128-132`
> "The 15% markup is already embedded in item prices via CartStore.addItem() and is baked into normalizedSubtotal."

Significa que `subtotal` que chega ao `calculateBreakdown` **já tem markup**. Isto é correcto, mas: se duas chamadas concorrentes (re-builds de UI) chamarem `addItem` com isPartner mudado entretanto, o item é gravado duas vezes com markup ou sem. Sem teste de idempotência.

**Fix:** marcar `cart_item.basePrice` (sem markup) + `cart_item.markedUp` boolean — recompute on the fly em vez de mutar.

### 🟡 [BUG-MN-010] Não existe **camadas 10+5+5%** para parceiros — partilha incorrecta
**Pedido na auditoria:** "Markup: parceiro 10+5+5% (camadas?)"
**Realidade no código:** `applyMarkup` faz **0%** em parceiros (return basePrice). Comissão `_partnerCommissionRate = 0.20` sobre subtotal (linha 124, 158). **Não há 10+5+5%**.

**Fix:** confirmar com a regra de negócio canónica. Se 10+5+5 existir, falta totalmente; se foi consolidada em 20%, actualizar SKILL.md (a auditoria menciona-a) e remover a referência.

### 🟡 [BUG-MN-011] `_partnerDeliveryFee = 2.5` hardcoded — regra "€2.50 até 4km, +€0.50/km" implementada apenas para `isPartnerRestaurant/Retail` e `isNonPartnerOrder`
**Ficheiro:** `lib/services/pricing_service.dart:118-122`, `134-139`

Para `isPackageService` (carryGroceries/sendPackage) usa `_packageBaseFee=6.0` + `_packageExtraPerKm=0.5` (não 2.50). Isto é correcto para package mas conflita com a auditoria pedida ("€2.50 até 4km, +€0.50/km") se essa regra for universal. Confirmar.

### 🟡 [BUG-MN-012] `client-cancel-order` calcula refund em EUR e só depois converte
**Ficheiro:** `supabase/functions/client-cancel-order/index.ts`
```ts
const feeEur = Number(computeFeeEur(tier, totalEur).toFixed(2));
const refundEur = Math.max(0, Number((totalEur - feeEur).toFixed(2)));
...
amount: Math.round(refundEur * 100)
```

`toFixed(2)` em JS é round-half-away-from-zero, e a subtracção em EUR é onde o erro do float entra antes da conversão para cents. Para `totalEur=10.105`, `feeEur=2.50` → `refundEur = 7.605 → 7.61` (em vez de `7.60` correcto se total = 1011 cents). **1 cêntimo a mais reembolsado**.

**Fix:** calcular tudo em cents: `totalCents = Math.round(totalEur*100); feeCents = computeFeeCents(tier, totalCents); refundCents = Math.max(0, totalCents - feeCents); stripe.refunds.create({ amount: refundCents })`.

### 🟡 [BUG-MN-013] Tolerância +15% no buffer não é validada no servidor
`calculateBufferedTotal = est × 1.15` (Flutter). EF aceita esse valor sem checar se 1.15× faz sentido (poderia vir 2× e passar). Mitigado pelo `±5%` deviation, mas o invariante `payment_buffer_total ≤ 1.20 × estimatedTotal` deveria ser server-side.

### 🟡 [BUG-MN-014] Ausência de idempotency keys nas EFs Stripe
Nenhuma EF (`create-payment-intent`, `refund`, `charge-extra`, `client-cancel-order`, `create-mbway-payment-intent`) passa `idempotencyKey` no `stripe.X.create({...}, {idempotencyKey})`. Se o cliente fizer retry (rede flaky), criamos **dois PaymentIntents** ou **dois refunds**. Stripe `auto_payment_methods` mitiga PI duplicado (cobra-se um), mas refunds duplicados são possíveis.

**Fix:** `idempotencyKey: order_id` para PI; `idempotencyKey: \`${order_id}:${refund_reason}\`` para refund.

### 🟡 [BUG-MN-015] Bag fee de mercado não está no breakdown final
`OrderPricingBreakdown.bagFee` defaults a 0. Para mercado, o `bagFee = bagCount × 0.10` é calculado **em `driver_map_screen.dart:1981-2000`** (driver UI) mas não fica baked no `customerTotal` do cliente — o cliente vê `subtotal+serviceFee+deliveryFee+bagFee` apenas se `bagFee` foi setado em `calculateBreakdown` (e este não recebe `bagCount`). Resultado: cliente paga sem bag fee de mercado e este aparece só no driver. **Receita perdida em todos os pedidos market**.

**Fix:** `calculateBreakdown` deve receber `bagCount` e `serviceType` e calcular `bagFee` para market também (`isMarket ? bagCount × 0.10 : (isRestaurant ? 0.30 : 0)`).

---

## 4. Bugs Baixos

### 🟢 [BUG-MN-016] `applyMarkup` round antes da soma → soma de itens arredondados ≠ arredondamento da soma
Cada item recebe `_roundCurrency(price × 1.15)` individualmente. Em 5 itens isto pode acumular ±2 cêntimos vs aplicar markup ao subtotal completo.
**Fix:** aplicar markup só na soma final (mas isto muda apresentação de preços). Aceitável trade-off — documentar.

### 🟢 [BUG-MN-017] `payment_method_screen` recalcula totais com leitura de `pricing.deliveryFee - apartmentSurcharge` e clamp >=0
Lógica correcta mas frágil: se `apartmentSurcharge > deliveryFee`, baseDeliveryFee=0 ⇒ display lies. Improvável (1.5 < 2.5), mas defensivo.

### 🟢 [BUG-MN-018] Driver bonus shopping `_shoppingDriverBonus = 0.80` e `_driverBasePay = 3.80` somados = €4.60. Auditoria pede `€3.80 + €0.20/km + €0.80`. Confere ✅ — mas para `apartmentDriverBonus = 1.0` (do `_apartmentDriverShare`), isto eleva o total para €5.60 (+ km). Documentar.

### 🟢 [BUG-MN-019] `notify-driver`/`notify-partner` (não auditados) podem disparar antes do webhook → estado paid divergente.

### 🟢 [BUG-MN-020] Backend Node em `backend/server.js` é "dead code" (CLAUDE.md confirma "not currently called by the app"). Risco: alguém commit por engano alterações lá e a app continua a usar EF. Marcar como deprecated ou remover.

---

## 5. Verificação ponto-a-ponto das regras

| Regra | Status | Evidência |
|---|---|---|
| **Tokens: 100 = €0.50** | ✅ | `BRTokens.TOKEN_VALUE_EUR = 0.005` → 100 × 0.005 = 0.50 ✓ |
| **Tokens: máx 50% desconto** | ⚠️ | `TOKEN_MAX_DISCOUNT_RATIO = 0.50` aplicado client-side só. **Server não valida** (BUG-MN-003) |
| **Tokens: taxa 3% sobre subtotal** | ❌ | Trigger usa `NEW.price` (=total) em vez de subtotal (BUG-MN-008) |
| **Driver +40 normal** | ✅ | `v_driver_tokens INTEGER := 40` (`bora_tokens.sql:143`) |
| **Driver +50 partner** | ❌ | **NÃO IMPLEMENTADO**. Trigger dá sempre 40, sem distinção partner. Falta lógica `IF NEW.is_partner_store THEN v_driver_tokens := 50`. |
| **Driver fee base €3.80** | ✅ | `_driverBasePay = 3.80` |
| **Driver fee €0.20/km** | ✅ | `_driverPerKmRate = 0.2` |
| **Driver bonus shopping €0.80** | ✅ | `_shoppingDriverBonus = 0.80` |
| **Driver fee partner +€3** | ❌ | **NÃO IMPLEMENTADO**. Não há `+3.00` para partner em parte alguma do `calculateBreakdown`. Driver ganha igual partner/non-partner (excepto que non-partner ganha extra €0.80 shopping). Inverso do esperado. |
| **Entrega cliente €2.50 até 4km** | ✅ partner / ✅ non-partner | `_partnerDeliveryFee=2.5`, `_packageBaseDistanceKm=4.0`, `_packageExtraPerKm=0.5` |
| **Entrega cliente +€0.50/km após 4km** | ✅ | linha 119, 138 |
| **Markup non-partner 15%** | ✅ | `_nonPartnerMarkupRate = 0.15` |
| **Markup partner 10+5+5%** | ❌ | Não existe. `applyMarkup` returna basePrice unchanged para partner. Comissão é flat 20% (`_partnerCommissionRate=0.20`). |
| **Cash máx €40** | ⚠️ | `CASH_MAX_ORDER_VALUE_EUR = 40.00` client-side; server-side trigger referido mas **não confirmado em migrations** (BUG-MN-007) |
| **Saco restaurante €0.30 fixo** | ✅ | `BRBags.RESTAURANT_BAG_FEE = 0.30` |
| **Saco mercado €0.10/saco** | ⚠️ | `BRBags.MARKET_BAG_FEE = 0.10` ✓ valor, mas **não cobrado ao cliente** (BUG-MN-015) — só aparece em UI driver. |
| **Trigger trg_award_tokens_on_delivery** | ✅ existe | `bora_tokens.sql:179` |
| **Idempotência tokens** | ✅ | `UNIQUE INDEX idx_bora_tokens_order_role` + `add_tokens` `ON CONFLICT DO NOTHING` |
| **Refunds parciais via Stripe** | ⚠️ | Funciona mecanicamente, mas BUG-MN-004 (sem cap) e BUG-MN-012 (rounding) e BUG-MN-014 (sem idempotency). |
| **MBWay flow + webhook** | ✅ live, ⚠️ sem reconcile | EF `create-mbway-payment-intent` cria + confirm; webhook handle `payment_intent.succeeded`. Buffer reconcile ausente (BUG-MN-001) |
| **payment_buffer_total ±5% reconcile** | ⚠️ | Validado em `create-payment-intent` (input client). **Não validado** em `stripe-webhook` no `succeeded`. |

---

## 6. Conversões EUR ↔ cêntimos — risco de perda

| Função | Input | Conversão | Output | Risco |
|---|---|---|---|---|
| `_roundCurrency` (Dart) | EUR `double` | `toStringAsFixed(2)` (banker's) | EUR `double` | Round half-to-even — diverge de JS Math.round |
| `Math.round(amount*100)` (refund EF, charge-extra, MBWay, CPI) | EUR `number` | round-half-up | int cents | OK isolado; problema é a inconsistência com Flutter |
| `Number((x).toFixed(2))` (client-cancel) | EUR `number` | round-half-away-from-zero | EUR `number` | Cumulativo após subtração — perde cêntimo (BUG-MN-012) |
| `tokensToUse * 0.005` | int×double | float multiply | EUR `double` | IEEE-754 errors para certos valores |
| `ROUND(NEW.price * 0.03)::INTEGER` (SQL) | NUMERIC | banker's (Postgres `ROUND`) | INT | OK; mas `price` ≠ subtotal (BUG-MN-008) |
| Stripe `intent.amount` (cents int) → comparar com `payment_buffer_total*100` | int vs float×100 | `Math.round` | int | Não feito (BUG-MN-001) |

---

## 7. Reconciliação Stripe — `payment_buffer_total`

A tolerância de ±5% (`AMOUNT_TOLERANCE = 0.05`) é validada **apenas na criação do PI** (`create-payment-intent/index.ts`). Nunca é re-verificada após `payment_intent.succeeded`. Isto significa:

- Se o cliente envia `amount = 0.95 × buffer`, deviation = 5%, **passa o gate** e o PI é criado com `amountCents = Math.round(buffer × 100)` — porque o EF usa `serverAmount` para criar o PI (linha após validation, dump indexado: `const amountCents = Math.round((order.payment_buffer_total as number) * 100)`). **Ou seja, o `amount` do cliente é só comparison, não usado** ⇒ OK.
- **Mas** o cliente envia `amount` recalculado (com tokens descontados, talvez). Se o cliente espera pagar `total - tokenDiscount` mas o servidor cobra `payment_buffer_total` (sem tokens), há **discrepância UX silenciosa** (BUG-MN-003).

A tolerância faz sentido só se usássemos o amount do cliente para cobrar, **o que não fazemos**. Recomendo: remover tolerância, validar igualdade exacta como sanity-check apenas; se diferir, recusar.

---

## 8. Refund vs Charge — simetria

- **Charge**: `amountCents = Math.round(payment_buffer_total * 100)` — server-trusted.
- **Refund**: `amountCents = Math.round(amount * 100)` — **client-trusted**, sem cap nem retrieve do PI. Asymétrico ⇒ vulnerável (BUG-MN-004).

Idempotência: zero. Retry de rede pode duplicar (BUG-MN-014).

---

## 9. Melhorias Sugeridas

### 🔴 [MEL-MN-001] Migrar tudo para cêntimos int (single source of truth)
Adoptar pattern de Stripe: `cart_item.priceCents`, `order.totalCents`, `order.paymentBufferTotalCents`. Conversão para EUR só na UI. Elimina BUG-MN-005, MN-006, MN-012 de uma vez. **Impacto: alto, esforço: alto (~1 sprint), risco: médio (migration de DB).**

### 🔴 [MEL-MN-002] Mover **toda** a lógica de pricing para o servidor (RPC)
Hoje, Flutter calcula breakdown e Edge re-valida com tolerância. Em vez disso: criar RPC `compute_order_total(order_id)` que devolve breakdown autoritativo. Flutter só consome para display. Elimina BUG-MN-002, MN-003, MN-013.

### 🟡 [MEL-MN-003] Adicionar idempotency keys em todas as EFs Stripe
Trivial: `{ idempotencyKey: \`${order_id}:create\` }` etc. Resolve BUG-MN-014.

### 🟡 [MEL-MN-004] Adicionar tabela `payment_events` (audit log) com cada webhook recebido
`(id, event_id, event_type, order_id, amount_cents, raw_payload, created_at)` UNIQUE(event_id). Reconciliação manual e auditoria fiscal (BR §20.2 — 10 anos).

### 🟡 [MEL-MN-005] Testes property-based de PricingService
Usar `dart:test` + property tests: para qualquer (subtotal, distance, isPartner, apartment), `customerTotal == subtotal + delivery + service + bag` (invariante) e `driverEarnings + platformCommission ≤ customerTotal - subtotal`. Cobertura actual desconhecida.

### 🟢 [MEL-MN-006] Documentar matriz de arredondamento num único `pricing_invariants.md`
Cada layer + convenção. Hoje os comentários estão espalhados.

### 🟢 [MEL-MN-007] Webhook deve atualizar `refund_amount` no DB (não delegar ao Flutter)
Resolve metade do BUG-MN-001.

### 🟢 [MEL-MN-008] Remover `backend/server.js` ou marcar como deprecated
Reduz superfície de ataque + risco de drift.

---

## 10. Pontuação

| Critério | Score | Notas |
|---|---|---|
| Conversão EUR↔cêntimos | 4/10 | 3 convenções de arredondamento diferentes; banker's vs half-up |
| Reconciliação Stripe | 3/10 | Sem reconcile no webhook; ±5% tolerance arriscada |
| Refunds | 4/10 | Funcionam mas sem cap, sem idempotency, sem rounding-safe math |
| Tokens | 5/10 | Trigger correcto na maior parte; `consume_tokens` cliente em falta no checkout |
| Pricing rules | 6/10 | Maioria implementada; **partner +€3 driver fee e markup 10+5+5% NÃO existem**; bag mercado não cobrado |
| Cash limit | 5/10 | Client OK; server-trigger não confirmado |
| MBWay | 7/10 | Live e funcional; falta reconcile e idempotency |
| Idempotência geral | 2/10 | Só no trigger SQL de tokens |
| Auditoria fiscal | 3/10 | Sem tabela de payment_events; `client-cancel-order` preserva mas o resto é volátil |
| Testabilidade | 4/10 | Sem property tests; lógica espalhada |

### TOTAL: **43 / 100**
> Vs Stripe Connect / Uber accounting standards (estes 90+/100). Bora App está num nível "MVP funcional" mas **não pronto para escala fiscal**.

---

## 11. Recomendação — Top 5 a atacar primeiro

1. **[BUG-MN-005 + MEL-MN-001]** Adoptar cêntimos int (`*_cents`) em todo o stack. Resolve metade dos bugs deste relatório.
2. **[BUG-MN-001 + BUG-MN-007]** Reconciliação no webhook: validar `intent.amount_received == payment_buffer_total*100` e tratar `charge.refunded` server-side (incluindo update de `refund_amount`/`payment_status`). Confirmar trigger SQL `enforce_cash_payment_limit` ou criar.
3. **[BUG-MN-003]** Tokens: implementar `consume_tokens` no fluxo do checkout do cliente; abater do `payment_buffer_total` antes de gravar a ordem.
4. **[BUG-MN-015 + BUG-MN-008]** Bag mercado: incluir `bagFee = bagCount × 0.10` no `calculateBreakdown` e cobrar ao cliente. Trigger de tokens: usar `subtotal` (não `total`) para os 3%; adicionar `+50` para driver partner.
5. **[BUG-MN-014 + BUG-MN-004]** Adicionar `idempotencyKey` em todas as `stripe.*.create` calls. No `refund` EF, `retrieve(pi)` e validar `amountCents <= pi.amount_capturable - already_refunded`.

---

## Apêndice A — Ficheiros auditados

- `lib/services/pricing_service.dart` (208 linhas, todo)
- `lib/services/payment_service.dart` (todo)
- `lib/screens/payment_method_screen.dart` (linhas 1-200, lógica tokens)
- `lib/config/business_rules.dart` (113 linhas, todo)
- `lib/models/order_model.dart` (toJson)
- `lib/stores/cart_store.dart`, `lib/stores/order_store.dart`
- `supabase/functions/create-payment-intent/index.ts` (todo)
- `supabase/functions/create-mbway-payment-intent/index.ts` (102 linhas, todo)
- `supabase/functions/refund/index.ts` (todo)
- `supabase/functions/charge-extra/index.ts` (todo)
- `supabase/functions/stripe-webhook/index.ts` (todo)
- `supabase/functions/client-cancel-order/index.ts` (todo)
- `supabase/migrations/20260404000000_bora_tokens.sql` (todo)
- `supabase/migrations/20260404000001_bora_tokens_type_fix.sql` (todo)
- `backend/server.js` (parcial — confirmado dead code)
- `lib/screens/driver_map_screen.dart` (linhas 1981-2000, bag fee)
- `lib/screens/driver_earnings_screen.dart` (consume_tokens driver)

## Apêndice B — Ficheiros NÃO auditados (recomendados em próxima passagem)

- `supabase/functions/dispatch-engine/index.ts` (impacto em driver fees)
- `supabase/functions/confirm-mbway-payment/index.ts` (existe mas não foi lido)
- `supabase/migrations/*.sql` outras (e.g. `enforce_cash_payment_limit`, `order_financials`, `driver_balances`, `ledger_entries`)
- `lib/screens/partner_earnings_screen.dart` (não localizado em path esperado)
- `lib/screens/driver_earnings_screen.dart` completo
- RPC `consume_tokens` SQL (apenas referenciado, body não inspeccionado)
