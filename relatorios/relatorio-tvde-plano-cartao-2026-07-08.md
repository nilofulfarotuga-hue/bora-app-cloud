# TVDE — cartão/MB Way TAMBÉM no plano (sem sobre-cobrar) — 2026-07-08

Branch `autonomous-night-2026-04-29`. Objetivo: corrida **coberta >6km** e **extra** poderem pagar
por **cartão/MB Way**, cobrando o **valor do plano** (não a tarifa cheia). Kill switch continua ON.

## O que mudei

### Edge Function `tvde-payment` (deployada, version 2, `verify_jwt=true`)
O `charge` deixou de recalcular a tarifa. Agora:
1. **Cria a corrida primeiro** (`tvde_request_ride`) — a RPC grava `est_fare_cents` **já com a regra
   do plano** (coberta→só excesso, extra→€4,50+excesso, normal→cheia).
2. **Cobra o valor de `tvde_ride_charge_cents(ride_id)`** (fonte única = `COALESCE(final_fare_cents,
   est_fare_cents, 0)`) — **não a tarifa cheia**.
3. **€0** (coberta ≤6km) → **não cria PaymentIntent** (devolve a corrida, `payment_status=not_charged`).
4. PaymentIntent **desse** valor (cartão → clientSecret p/ PaymentSheet; MB Way → confirm server-side,
   idempotência `tvde_charge_<ride_id>`). Se a cobrança falhar → **cancela a corrida órfã**.

### Flutter (`tvde_request_ride_screen.dart`)
A folha de pagamento passa a oferecer os **3 métodos** em **qualquer corrida com valor > 0**
(`allowOnline = _cardEnabled && _payableCents > 0`), não só na normal. Grátis (coberta ≤6km) continua
sem folha. O valor que a UI mostra é o mesmo que a EF cobra (ambos = valor do plano).

## Prova de que a EF cobra o valor do PLANO (não a cheia)
Cálculo determinístico com as `platform_settings` reais (base €5 / 6 km / €0,50 km / extra €4,50),
para uma corrida de **10 km**:

| Caso | est_fare_cents (o que `tvde_request_ride` grava) | EF cobra (`tvde_ride_charge_cents`) | Tarifa cheia (antiga) |
|---|---|---|---|
| **Coberta >6km** | **200 = €2,00** (só excesso 4 km × €0,50) | **€2,00** ✅ | ~~€7,00~~ |
| **Extra (membro)** | **650 = €6,50** (€4,50 + €2,00) | **€6,50** ✅ | ~~€7,00~~ |
| **Normal** | 700 = €7,00 | €7,00 ✅ | €7,00 |
| **Coberta ≤6km** | 0 | não cobra (`not_charged`) | — |

Cadeia (por código, verificada): `tvde_request_ride` calcula `v_client_fare` pela cobertura →
grava em `est_fare_cents` → `tvde_ride_charge_cents` devolve-o → a EF cria o PaymentIntent com **esse**
valor. **UI mostra €2,00 → EF cobra €2,00. UI "Grátis" → nenhuma cobrança.**

## ⚠️ A decidir (backend — fora do meu âmbito, RPCs bloqueadas)
No `tvde_finish_ride`, o ramo `v_online` (card/mbway) usa `est_fare_cents` e **NÃO consome a
subscrição** (`tvde_consume_subscription_ride` só corre no ramo dinheiro). Consequência: uma corrida
**coberta paga online não desconta o slot diário** — um membro poderia pagar o excesso online e obter
a base grátis repetidamente sem gastar as corridas incluídas do dia. Não sobre-cobra ninguém (o valor
está certo), mas é uma **fuga de limite** a fechar. Fix = consumir o slot também nas cobertas online
(mexe no `tvde_finish_ride` → decisão tua). Reportado, não aplicado.

## ✅ Checklist de teste (Redmi por cabo, switch ON)
- [ ] **Coberta ≤6km** → "Incluída no plano ✓", sem folha, corrida criada, **nada no Stripe**.
- [ ] **Coberta >6km** → folha mostra **€2,00** + 3 métodos. Pagar com **Cartão** → PaymentSheet →
      Stripe `succeeded` de **€2,00** (não €7). MB Way idem.
- [ ] **Extra (3.ª do dia)** → folha mostra **€6,50** + 3 métodos → Stripe `succeeded` de **€6,50**.
- [ ] **Normal** → €7,00 + 3 métodos → Stripe `succeeded` €7,00.
- [ ] **Dinheiro** em qualquer caso → sem Stripe; motorista cobra o valor certo no fim.
- [ ] **Cancelar** corrida paga → refund no Stripe (valor pago menos taxa).
- [ ] Cartão cancelado no PaymentSheet → a corrida órfã é cancelada (não fica "solicitada").

## Ficheiros
`supabase/functions/tvde-payment/index.ts` (charge = ride-first + `tvde_ride_charge_cents`, deployada),
`lib/screens/client/tvde/tvde_request_ride_screen.dart` (`allowOnline` = valor > 0). `flutter analyze`
0 erros (infos pré-existentes). Não mexi nas RPCs TVDE nem em zonas protegidas; switch não desligado.
