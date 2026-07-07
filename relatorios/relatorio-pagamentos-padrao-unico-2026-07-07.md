# Pagamentos — PADRÃO ÚNICO (delivery) em todo o app — 2026-07-07

Branch: `autonomous-night-2026-04-29`. Modelo único: **cobrança imediata de preço fechado + refund
estilo `client-cancel-order`** (sem authorize/capture). **Kill switch TVDE `tvde_card_payments_enabled`
= OFF** (não liguei). Zonas protegidas intactas.

## O que fiz

### TVDE — Edge Function `tvde-payment` simplificada + **DEPLOYADA**
Reescrita para **2 ações** (padrão delivery), sem authorize/capture, sem margem:
- **`charge`** — cartão: PaymentIntent imediato (`automatic_payment_methods`) → `clientSecret` p/ o
  cliente confirmar (PaymentSheet); MB Way: `confirm:true` com telefone E.164. Em ambos: preço
  **sempre server-side** (`tvde_calculate_fare`), cria a corrida (JWT, auth.uid) e liga o
  `payment_intent_id`. Falha ao criar → cancela o PI.
- **`refund`** — cancelamento: `refund = max(0, min(pago − taxa, pago))` + idempotência
  `refund-${pi}-${cents}` (mesmo padrão do `client-cancel-order`).
- **Deployada via MCP** (`verify_jwt=true`, version 1 ACTIVE). **Sanidade OK:** com o switch OFF →
  **HTTP 403 `card_payments_not_enabled`** (recusa limpa, testado por curl).

### Flutter cliente
- Secção **"Pagamento"** (`TvdePaymentSelector`): Dinheiro sempre; Cartão+MB Way só com o switch on.
- `requestRidePaid` chama `tvde-payment` (action `charge`) e confirma o cartão via `PaymentService`.
- **Cancelamento paga no app → refund** (`cancelRide` invoca `tvde-payment` action `refund` com a
  taxa do `tvde_cancel_ride`; best-effort).
- **Paradas extra ESCONDIDAS** em corrida paga no app (preço fechado, MVP) — `tvde_ride_tracking`.

### Badge único do executor — `CollectBadge` (aplica-se às 3 verticais)
Novo `lib/widgets/payments/collect_badge.dart` com 3 estados (**valor obrigatório** no cash por
assert): `collectCash` (laranja, "COBRAR EM DINHEIRO: €X"), `paidOnline` (verde, "JÁ PAGO NA APP —
não cobrar"), `coveredByPlan` (verde). Aplicado em:
- **TVDE** (motorista) — `TvdePayBadge` passou a ser um adapter fino sobre o `CollectBadge`.
- **Limpeza** (profissional) — `cleaner_home` mostra agora o badge (cash → cobrar €X; card/mbway →
  "JÁ PAGO NA APP", que antes era só texto).
- **Delivery** (estafeta) — substituídas as ~4 cópias inline divergentes (cor/valor/ícone) em
  `driver_home_screen` (+ `driver_map_screen`), **incluindo o bug real: card/MB Way não mostrava
  NADA → agora mostra "JÁ PAGO NA APP — não cobrar"** (evita cobrar dinheiro num pedido já pago).

## Auditoria — padrão único por vertical

| Vertical | 3 métodos na UI? | Cobrança = PI imediato (delivery)? | Refund = client-cancel-order? | Executor vê badge? | Campos DB |
|---|---|---|---|---|---|
| Delivery restaurante | ✅ 3 | ✅ `create-payment-intent` | ✅ `client-cancel-order` | ✅ **CollectBadge** (era parcial) | orders.payment_method/intent/status/… |
| Mercados | ✅ 3 | ✅ igual delivery | ✅ | ✅ **CollectBadge** | orders |
| Favores | ✅ 3 | ✅ igual delivery | ✅ | ✅ **CollectBadge** | orders |
| Reservas de mesa | card+mbway (cash excluído, pré-pago €3) | ⚠️ PI **próprio** (`create-reservation-…`) | ❌ cancel próprio (>2h) | N/A (pré-pago) | reservations |
| Serviços/barbearia | card+mbway (pré-pago €3) | ⚠️ PI **próprio** (`create-appointment-…`) | ❌ cancel próprio | N/A (pré-pago) | appointments |
| **Limpeza** | ✅ 3 (card/mbway gated) | ⚠️ PI **próprio** `cleaning-checkout` (LIVE) | ⚠️ próprio `reverse` (mesmo espírito) | ✅ **CollectBadge** (novo) | cleaning_bookings |
| TVDE corrida | cash sempre; card/mbway c/ switch | ✅ `tvde-payment` (novo, padrão delivery) | ✅ `tvde-payment` refund | ✅ **CollectBadge** | tvde_rides |
| TVDE ida-e-volta | pacote €8 (card/mbway) | ⚠️ `tvde-plan-payment` próprio | ❌ cancel próprio | ✅ coveredByPlan | tvde_rides |

**Leitura:** delivery/mercados/favores/TVDE-corrida = padrão único completo (cobrança + refund +
badge). Reservas/serviços/limpeza/ida-volta têm **Edge Functions de pagamento próprias mas
equivalentes** (PI imediato + refund-menos-taxa) — **não unifiquei o backend** (funcionam, LIVE, e
mexer é Lista Vermelha). O que era rápido (o **badge do executor**) foi unificado já nas 3 verticais
operacionais.

### Limpeza (deep-dive)
Oferece os 3 métodos (`cleaning_wizard` L622-639, card/mbway atrás de `stripeEnabled`); cobra online
via `cleaning-checkout` (PI imediato, LIVE desde 2026-07-05); cancela com refund via
`cleaning-checkout/reverse` (total − `cancel_fee_cents`). Ou seja: **já segue o espírito do padrão
único** com Edge Function própria. Único gap era o **badge visual** do profissional para "pago na
app" (era só texto) → **corrigido** com o `CollectBadge`.

## ✅ Checklist de go-live (quando quiseres ligar — passos teus)
1. (feito) `tvde-payment` deployada, `verify_jwt=true`, recusa com switch off.
2. Confirma o segredo `STRIPE_SECRET_KEY` no projeto (a function usa o mesmo do delivery).
3. Liga `tvde_card_payments_enabled=true` (via MCP).
4. **1 corrida CARTÃO**: pedir → confirmar no PaymentSheet → ver o PI em Stripe (charged) + a ride
   com `payment_intent_id`/`payment_status` + o motorista vê "JÁ PAGO — não cobrar" + o saldo do
   motorista fica **negativo** (Bora deve o ganho).
5. **1 corrida MB WAY**: pedir → aprovar o push MB WAY → mesmos checks.
6. **Cancelamento**: cancelar uma corrida paga → ver o refund em Stripe (menos a taxa) e
   `payment_status=refunded/partial_refund`.
7. Se algo falhar → `tvde_card_payments_enabled=false` (volta tudo a dinheiro).

## Admin
`admin_tvde_rides_list` devolve `payment_method` (confirmado). O saldo do motorista já lê o sinal
(negativo = "Bora deve"). **A confirmar via MCP:** se a lista admin devolve também `payment_status`
(útil para ver pago/refund) — se não, ajustar a RPC (tu, via MCP).

## Limitações / falta ligar (quando testares)
- **Captura no fim / status final:** o cartão é cobrado no PEDIDO (preço fechado do estimado), não
  no fim — por design deste modelo (preço fechado). Se a distância real divergir muito, é o
  estimado que fica cobrado (paradas escondidas em corrida paga).
- **MB Way sucesso:** depende do push aprovado; o `stripe-webhook` (não tocado) trata
  `payment_intent.succeeded` — confirmar que roteia o metadata `kind:tvde_ride` (senão o
  `payment_status` da ride fica em "processing"; não bloqueia a corrida).

## Ficheiros
**Novos:** `lib/widgets/payments/collect_badge.dart`, `test/collect_badge_test.dart`.
**Alterados:** `supabase/functions/tvde-payment/index.ts` (simplificado + deployado),
`lib/widgets/tvde/tvde_pay_badge.dart`, `lib/screens/cleaner/cleaner_home_screen.dart`,
`lib/screens/client/tvde/tvde_ride_tracking_screen.dart`, `lib/stores/tvde_store.dart`,
`lib/screens/driver_home_screen.dart` + `lib/screens/driver_map_screen.dart` (CollectBadge).
`flutter analyze` limpo nos ficheiros tocados; testes badge+seletor 7/7 verdes.
