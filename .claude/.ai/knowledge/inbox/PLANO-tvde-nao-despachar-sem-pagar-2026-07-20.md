---
id: plano-tvde-nao-despachar-sem-pagar-2026-07-20
tema: tvde
estado: atual
tipo: plano
data: 2026-07-20
autor: CEO-AI (sessão interativa, MODO PROTECÇÃO TOTAL)
---

# PLANO — TVDE: a corrida não pode despachar antes de pagar

**Nada foi aplicado.** Só investigação (leitura de código + `SELECT` ao vivo).
Só Flutter será tocado; backend é do Claude.ai via MCP.

---

## 0. O padrão do delivery (referência lida)

`payment_method_screen.dart:770-929` + `create-payment-intent` + `finalize-order-from-intent`:

```
1. cartStore.startCardPaymentDraft()  → payment_drafts (TTL 30min) + Stripe PI · SEM order
2. paymentService.processPayment(clientSecret)   → o cliente paga
3. stripe-webhook → finalize-order-from-intent   → CRIA a order (e só aí despacha)
4. orderStore.waitForOrderFromDraft(draftId)     → poll de payment_drafts.used_at
   Recusou → não há order para limpar; o draft expira pelo pg_cron cleanup_payment_drafts
```

**O TVDE não vai copiar `payment_drafts`** — e ainda bem. O contrato que o Claude.ai
garantiu é mais simples e chega ao mesmo fim: a corrida **nasce** mas fica **estacionada**
em `aguarda_pagamento`, e o cron de dispatch ignora esse estado. Mesma propriedade de
segurança (nada despacha sem pagar), menos peças. O plano alinha-se a esse contrato.

---

## 1. O que o Flutter tem hoje (e o que parte)

| Sítio | Hoje | Com `aguarda_pagamento` |
|---|---|---|
| `TvdeRide.statusLabel` | `default: return status` | ⚠️ o cliente vê a **string crua `aguarda_pagamento`** |
| `TvdeRide.isSearching` | `status == 'solicitada'` | ✅ fica false — não diz "à procura" |
| `TvdeRide.isLive` | `isSearching \|\| isAssigned \|\| isInProgress` | ⚠️ corrida parada **não é "live"** → o resume não a reabre |
| `TvdeRide.isTerminal` | finished/cancelled/noDriver | ⚠️ também não é terminal → **limbo** |
| Tracking `:832` | `if (ride.isSearching)` mostra a procura | ✅ não mostra — mas **não mostra nada em vez disso** |
| Admin `_statusStyle` | `_ => (s ?? '—', …)` | ⚠️ o admin vê a **string crua** |
| `TvdeStore.cancelRide` | **refund sempre** que `isPaidOnline` | ⚠️ num cancelamento `payment_failed` **não há nada a reembolsar** |
| `TvdeStore` | não tem `confirmRidePayment` | ⚠️ falta |
| `TvdeRide.fromMap` | não lê `payment_status` | ⚠️ falta (a Fase 1 lê por query à parte) |

**Dívida da sessão anterior (minha):** no €8 por MB Way eu crio a corrida de ida **antes**
da confirmação, de propósito, para a poder ligar ao vale. Com o contrato novo isso é
exatamente o bug descrito — **nasce uma corrida cash que despacha**. A Fase B desfaz isto.

---

## 2. FASE A — cartão/MB Way na corrida normal

### A1 · Modelo `lib/models/tvde_ride.dart`
- `statusLabel`: `case 'aguarda_pagamento': return 'A aguardar pagamento…';`
- `bool get isAwaitingPayment => status == 'aguarda_pagamento';`
- `isLive`: **acrescentar** `isAwaitingPayment` — senão o cliente que volta à app durante
  o MB Way perde o ecrã e fica sem saber o que aconteceu ao dinheiro.
- ler `payment_status` no `fromMap` (novo campo `paymentStatus`).

### A2 · Store `lib/stores/tvde_store.dart`
- `Future<bool> confirmRidePayment(String rideId)` → invoca
  `tvde-payment {action:'confirm_ride_payment', ride_id}`; devolve `succeeded`.
  Substitui o poll a `fetchRidePaymentStatus` da Fase 1 (que fica só como leitura auxiliar).
- `cancelRide(..., {bool skipRefund = false})` — em `payment_failed` **não** chamar refund.

### A3 · Ecrã `tvde_request_ride_screen.dart` — `_solicitar()`
```
charge (card|mbway) → corrida nasce 'aguarda_pagamento' (não despacha)
├─ CARTÃO
│   processPayment(clientSecret)
│   ├─ ok      → confirmRidePayment(ride.id)
│   │            ├─ succeeded → _openTracking()   ("à procura de motorista")
│   │            └─ false     → cancelRide(payment_failed) + "pagamento não concluído"
│   └─ recusa/cancela → cancelRide(payment_failed) + "pagamento não concluído"
└─ MB WAY
    dialog "confirma no MB Way" · poll confirmRidePayment a cada 3 s até 120 s
    ├─ succeeded → _openTracking()
    └─ timeout/falha → cancelRide(payment_failed) + erro
```
Reusa o `TvdeRideMbwayWaitingDialog` que já existe — só troca o `checkPaid` para
`confirmRidePayment`. **Nunca** abre o tracking em modo "à procura" antes do `succeeded`.

### A4 · Ecrã `tvde_ride_tracking_screen.dart`
Ramo novo `if (ride.isAwaitingPayment)`: cartão "A aguardar pagamento" + explicação
PT-PT + botão **Cancelar**. Garantir que o bloco `isSearching` (`:832`) e o mapa/ETA
**não** aparecem neste estado.

### A5 · Admin (PT-BR) `admin_tvde_rides_screen.dart`
- `_statusStyle`: `'aguarda_pagamento' => ('Aguardando pagamento', AppColors.warning)`.
- Contadores do topo: `aguarda_pagamento` **não** conta como corrida ativa saudável.

---

## 3. FASE B — €8 ida-e-volta

### B1 · Ordem correta (desfaz a dívida da Fase 1)
```
picker (Dinheiro | Cartão | MB Way)
├─ CARTÃO / MB WAY → pagar PRIMEIRO, confirmar, e só depois criar a ida
└─ DINHEIRO        → sem Stripe (ver B3 — contrato em falta)
recusa/timeout → NÃO cria ida nenhuma (hoje ficava uma cash €5 despachada)
```

### B2 · Seletor + motorista
- Acrescentar **Dinheiro** ao `ReservationPaymentMethodSheet` do €8 (hoje só cartão/MBWay).
  → widget próprio do TVDE em vez de alargar o das Reservas (não contaminar reservas).
- **App do motorista** (`tvde_offer_screen.dart` / `tvde_pay_badge.dart`), PT-PT:
  > **"Recebes €X desta corrida. Os €8 que o cliente paga NÃO são teus — a Bora acerta
  > no fim da semana."**
  Só quando a corrida é do pacote €8 em dinheiro.
- ⚠️ **Dependência:** `TvdeRide` **não expõe** `roundtrip_credit_id` nem `is_return_leg`
  (confirmado no `fromMap`). O Flutter tem de os ler — e a fonte que alimenta a oferta do
  motorista tem de os devolver.

### B3 · 🚧 BURACO NO CONTRATO — o €8 em dinheiro não tem backend
Os contratos 1–4 do pedido **não cobrem** o €8 em dinheiro, e o que existe hoje **não
serve**:
```sql
tvde_create_roundtrip_credit(p_client_id, p_outbound_ride_id, p_paid_cents, p_payment_intent_id)
```
exige `payment_intent_id`, e a EF `activate_roundtrip` só cria o vale **depois de
verificar um PaymentIntent `succeeded` na Stripe**. Em dinheiro **não há PaymentIntent**.

**Pergunta para o Claude.ai (bloqueia a Fase B):** que RPC/ação é que o Flutter chama para
criar o vale de €8 em dinheiro, e como é que o €8 entra no acerto semanal do motorista
(`tvde_driver_balances`)? Sem isso não dá para escrever o caminho do dinheiro.

*(Nota: o `v_prepaid` do `tvde_finish_ride` já garante que a ida ligada ao vale não cobra
€5 — o "€8 é o total" fica resolvido pelo link, desde que o vale exista.)*

---

## 4. Perguntas abertas para o Claude.ai (levar com o plano)

1. **`ride_in_progress`** — `aguarda_pagamento` conta como "corrida em curso" no guard do
   `tvde_request_ride`? Se contar, um pagamento recusado tranca o cliente até o cron
   passar. Deve **não** contar (ou o cancelamento imediato do Flutter resolve na hora).
2. **`admin_tvde_rides_list(p_scope:'live')`** inclui `aguarda_pagamento`? O Danilo quer
   ver estas corridas.
3. **Cancelamentos automáticos do cron** — que `cancel_reason` gravam? Preciso do valor
   exato para o mostrar em PT-PT/PT-BR em vez da string crua.
4. **Fase B** — `confirm_ride_payment` é por `ride_id`; o €8 tem PaymentIntent próprio
   (via `tvde-plan-payment`). Uso o `activate_roundtrip` como confirmador, ou haverá ação
   nova?
5. **B3** — o contrato do €8 em dinheiro (acima).

---

## 5. Painel admin (regra de paridade)

| Precisa | Estado |
|---|---|
| Ver corridas em `aguarda_pagamento` | ❌ chip novo (A5) + confirmar o scope 'live' (Q2) |
| Ver cancelamentos automáticos por não-pagamento | ⚠️ o ecrã de cancelamentos existe; falta o motivo legível (Q3) |
| Acerto do motorista (débitos/créditos) | ✅ `AdminTvdeDriverDebtsScreen` já existe (sessão anterior) — **mas** só lê; *liquidar* continua sem RPC |
| Ida-e-volta | ✅ `AdminTvdeRoundtripsScreen` já existe |

---

## 6. Ficheiros a mexer

**Fase A:** `lib/models/tvde_ride.dart` · `lib/stores/tvde_store.dart` ·
`lib/screens/client/tvde/tvde_request_ride_screen.dart` ·
`lib/screens/client/tvde/ride_mbway_waiting_dialog.dart` ·
`lib/screens/client/tvde/tvde_ride_tracking_screen.dart` ·
`lib/screens/admin/admin_tvde_rides_screen.dart`

**Fase B (bloqueada por B3):** os de cima + widget de método do €8 ·
`lib/screens/driver/tvde/tvde_offer_screen.dart` · `lib/widgets/tvde/tvde_pay_badge.dart`

**Não tocar:** Edge Functions, RPCs, SQL, migrations, crons, `pricing_service`,
`dispatch_engine`, `finalizePurchase`, `bora_tokens`, `stripe-webhook`, delivery.
**`PaymentService.processPayment` mantém a assinatura** — completa em sucesso, lança em
cancelamento. Os pagamentos web de 2026-07-20 dependem disso em 9 call-sites.

---

## 7. Ordem de ligação (coordenar com o Claude.ai)

O contrato 1 diz que o Claude.ai **só liga** o `aguarda_pagamento` depois do Flutter estar
pronto. A ordem segura é:

1. Flutter da Fase A **merged e no APK** (tolera os dois mundos: se a corrida nascer
   `solicitada`, o `confirmRidePayment` devolve `succeeded` e nada muda).
2. Claude.ai liga o `aguarda_pagamento` + a ação `confirm_ride_payment` + o cron.
3. Teste real do Danilo no telemóvel.

**O código da Fase A vai ser escrito para aguentar os dois estados** — sem isso, ligar o
backend antes do APK chegar aos telemóveis parte o TVDE para quem tiver a versão antiga.

---

## 8. Testes — limitação a assumir já

- **Só consigo testar com dinheiro.** A conta Stripe está em **LIVE**: cartões de teste
  não servem e não vou cobrar ninguém num teste automático.
- Faço: `flutter analyze` (0 erros), widget tests dos estados novos
  (`aguarda_pagamento` no label/tracking/admin), e o anti-trapaça do Juiz.
- **O teste real de cobrança (cartão + MB Way + recusa) fica contigo, no telemóvel.**
  Recorda também que o build do APK nesta máquina rebentou por RAM na sessão anterior
  (crash da JVM do Gradle) — o APK terá de vir do CI.

---

## ⚠️ ISTO MEXE EM PAGAMENTO/DINHEIRO. Plano pronto — leva-o ao Claude.ai.

**Parado à espera de revisão**, como pediste. Quando aprovares, começo pela **Fase A**
(a Fase B fica bloqueada até haver resposta ao **B3**).
