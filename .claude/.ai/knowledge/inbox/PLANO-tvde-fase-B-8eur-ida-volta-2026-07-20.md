# PLANO — FASE B: €8 ida-e-volta (Flutter) · 2026-07-20

> **ESTADO: PLANO. Nada aplicado.** Só Flutter/UI. Backend (RPC/EF/SQL/cron) é do Claude.ai.
> Branch: `autonomous-night-2026-04-29`. Fase A fechada em `6f70037`.

---

## 1. O que o Flutter faz HOJE (investigado, não suposto)

### Cliente — `_solicitarRoundtrip()` (`tvde_request_ride_screen.dart:475-575`)

Ordem atual:

1. Folha `ReservationPaymentMethodSheet` → **só Cartão / MB Way** (sem dinheiro).
2. `createRoundtripPayment()` (cartão) ou `createRoundtripPaymentMbway(phone)` → EF `tvde-plan-payment`.
3. Cartão: `PaymentService().processPayment(clientSecret)` confirma já.
4. **Cria a ida** com `store.requestRide(...)` — **sem passar `paymentMethod`**, portanto vai o
   default `'cash'` (`tvde_store.dart:172`) → a ida nasce `'solicitada'` e **o dispatch começa já**.
5. Liga ao vale: cartão → `activateRoundtrip(ida.id, pi)`; MB Way → `TvdeRideMbwayWaitingDialog.forRoundtrip`
   (poll) que chama o `activate_roundtrip` quando o PI fica `succeeded`.

### Os 3 buracos reais que isto deixa

| # | Buraco | Consequência |
|---|---|---|
| **B1** | Não há opção **Dinheiro** no €8 | O €8-cash simplesmente não existe na app |
| **B2** | **MB Way:** a ida nasce e **despacha** durante o poll (até 120 s) | Motorista a caminho antes de o €8 pagar. Se o MB Way falhar, o `activate` não corre, a ida fica **solta como corrida cash normal** e o cliente paga os €5 ao motorista → é exactamente o "€13" que o Danilo proibiu |
| **B3** | **Cartão:** janela curta entre `processPayment` (cliente) e `activate_roundtrip` (servidor) | A ida já nasceu `'solicitada'`. Menor que B2, mas o mesmo padrão |

> Nota: o `activate_roundtrip` a correr é que põe `roundtrip_credit_id` na ida
> (migration `20260704090200_tvde_roundtrip.sql:90`) e é isso que faz o `tvde_finish_ride`
> tratá-la como **prepaga** (`v_prepaid := v_ride.roundtrip_credit_id IS NOT NULL`, linha 187).
> Sem essa ligação → a ida cobra a tarifa. **A ligação é a única coisa que separa €8 de €13.**

### Motorista

- `tvde_offer_screen.dart:128-189` e `tvde_ride_active_screen.dart:811` já mostram **"O teu ganho · €X"**
  a partir de `ride.driverEarnCents`. **Já existe o número certo** — falta só o aviso do €8.
- Os ecrãs do motorista **não distinguem dinheiro de online** em lado nenhum hoje.

### Modelo — `TvdeRide` (`lib/models/tvde_ride.dart`)

Mapeia 24 colunas mas **não mapeia** `roundtrip_credit_id` nem `is_return_leg`
(ambas existem na tabela desde `20260704090200`). **Sem elas o motorista não consegue saber que
está numa perna do €8** — é o bloqueio nº 1 da tarefa 3.

---

## 2. Ficheiros a mexer (7 · todos Flutter)

| # | Ficheiro | O quê | Risco |
|---|---|---|---|
| 1 | `lib/models/tvde_ride.dart` | +2 campos: `roundtripCreditId`, `isReturnLeg` + `fromMap` + helper `isRoundtripLeg` | 🟢 |
| 2 | `lib/stores/tvde_store.dart` | +`createRoundtripCreditCash(outboundRideId)` → `rpc('tvde_create_roundtrip_credit_cash')` | 🟢 |
| 3 | `lib/screens/client/tvde/tvde_request_ride_screen.dart` | Folha do €8 passa a ter Dinheiro; `_solicitarRoundtrip` ganha 2 caminhos | 🟡 |
| 4 | `lib/screens/driver/tvde/tvde_offer_screen.dart` | Banner do €8 na oferta | 🟢 |
| 5 | `lib/screens/driver/tvde/tvde_ride_active_screen.dart` | Mesmo banner na corrida ativa | 🟢 |
| 6 | `lib/widgets/tvde/tvde_roundtrip_driver_notice.dart` **(novo)** | Widget único do aviso (não duplicar texto em 2 ecrãs) | 🟢 |
| 7 | `test/tvde_roundtrip_cash_test.dart` **(novo)** | Testes de modelo + do texto do aviso | 🟢 |

**Nada em `supabase/`.**

---

## 3. Lógica proposta

### T1 + T2 — Cliente: Dinheiro no €8 e a ida sempre ligada ao vale

**Folha:** trocar `ReservationPaymentMethodSheet` pelo `_TvdePaymentSheet` que já existe neste
mesmo ficheiro (linha 1012) — ele já usa o `TvdePaymentSelector`, que já tem
**Dinheiro (default) + Cartão + MB Way** com keys testadas (`tvde_pay_cash/card/mbway`) e já trata
o número MB Way. Precisa de **um parâmetro novo `allowTokens: false`**: no €8 os tokens ficam de
fora (o preço é server-side; misturar tokens aqui é mexer em dinheiro sem contrato).

```
_solicitarRoundtrip():
  método ← folha(_TvdePaymentSheet, amount: _roundtripPriceCents, allowTokens: false)

  ── CASH ─────────────────────────────────────────────
  1. ida = requestRide(..., paymentMethod: 'cash')
  2. vale = store.createRoundtripCreditCash(ida.id)     // RPC nova
  3. vale == null → ver "recuo" abaixo
  4. _openTracking()

  ── CARD / MBWAY (mantém o que já funciona, + trava) ─
  1..3. igual a hoje (PI → confirma → cria ida → activate_roundtrip)
  4. se ida.isAwaitingPayment → _aguardarPagamentoOnline(...)   ← reusa a Fase A
```

**A trava do B2/B3 (importante — precisa de gancho no backend):** o Flutter **já sabe** esperar,
via `_aguardarPagamentoOnline` (linha 418), mas só se a ida **nascer** em `aguarda_pagamento`.
Hoje ela nasce `'solicitada'` porque o €8-online cria a ida com `paymentMethod` default `'cash'`.

→ **A ANOTAR PARA O CLAUDE.AI (backend, não faço):** um de dois ganchos —
  - **(a)** `tvde_request_ride` aceitar a ida do €8-online parked (ex.: `p_payment_method => 'card'`
    já a faz nascer `aguarda_pagamento`?) **e** o `activate_roundtrip` libertá-la para `'solicitada'`
    no fim; ou
  - **(b)** o `activate_roundtrip` ser o único a libertar, e a ida do €8 nascer sempre parked.

  **Sem esse gancho, o Flutter fica tolerante aos dois mundos** (igual à Fase A): se a ida nascer
  `aguarda_pagamento` espera; se nascer `solicitada` segue como hoje. **Não invento o gancho.**

**Recuo do cash (passo 3):** se a RPC do vale falhar com a ida já criada, temos uma ida cash solta
que cobraria €5 — o cenário proibido. Proposta: **cancelar a ida** (`cancelRide(reason:
'roundtrip_credit_failed', skipRefund: true)` — nada foi cobrado, é dinheiro) + PT-PT
*"Não foi possível garantir a volta. A corrida não foi pedida — tenta outra vez."*
Retry 3× antes de desistir. ⚠️ **`roundtrip_credit_failed` é um `cancel_reason` novo — confirmar
com o Claude.ai se o backend o aceita** (senão uso `payment_failed`, que já existe).

### T3 — Motorista: "os €8 não são teus"

Widget novo, mostrado **só quando `ride.isRoundtripLeg`** (i.e. `roundtripCreditId != null`),
na oferta e na corrida ativa, por baixo do "O teu ganho":

> **Ida (`isReturnLeg == false`) + `paymentMethod == 'cash'`:**
> «Recebes **€4,00** desta corrida. Os **€8,00** que o cliente paga **não são teus** — recolhes em
> mão por conta da Bora e ela acerta no fim da semana.»
>
> **Ida online (card/mbway):** «Recebes **€4,00** desta corrida. O cliente **já pagou os €8,00**
> online — **não cobres nada** ao cliente.»
>
> **Volta (`isReturnLeg == true`):** «Recebes **€3,50** desta corrida. A volta **já está paga** —
> **não cobres nada** ao cliente.»

Os valores **não são hardcoded**: €X = `ride.driverEarnCents`; €8 = `tvde_roundtrip_price_cents`
(já lido por `getSettingInt`). Só o texto é fixo.

### T4 — Recusa

- **Online:** já coberto pelo `_aguardarPagamentoOnline` da Fase A → cancela a ida
  (`payment_failed`, `skipRefund: true`). No MB Way passa a **cancelar a ida** em vez de a deixar
  seguir como corrida normal — **é uma mudança de comportamento face a hoje** (hoje a mensagem diz
  «segue como corrida normal, sem a volta garantida»). É o que o Danilo pediu; **fica assinalado**.
- **Cash:** não há recusa (sem Stripe). Só o recuo do vale acima.

---

## 4. Painel admin (PT-BR) — o que falta (não entra nesta fase)

`admin_tvde_roundtrips_screen.dart` já lista os vales (cliente, ida, volta, comprado em, válido até,
estado). **Falta:**

1. **Método de pagamento do vale** — coluna/chip `Dinheiro` vs `Cartão`/`MB Way`. Hoje não há como
   ver quem pagou em mão. *(Precisa de campo no vale — do Claude.ai.)*
2. **Fila de acerto semanal** — por motorista: **débito €4,00** (recolheu €8, ganhou €4 → deve €4 à
   Bora) e **crédito €3,50** (fez a volta grátis → a Bora deve-lhe). Total líquido por motorista.
3. **Alerta de vale órfão** — ida em dinheiro **sem** `roundtrip_credit_id`: é exactamente o bug do
   €13 a acontecer em produção. Vale a pena um contador no dashboard.

---

## 5. Testes / verificação

- `flutter analyze` — 0 erros (baseline 217 issues, 0 erros).
- `flutter test` — os 19 da Fase A continuam verdes + os novos.
- **Teste manual só em DINHEIRO.** ⚠️ **Não se testa cobrança real de cartão/MB Way nesta máquina**
  (Stripe LIVE — cobrança verdadeira). O caminho online valida-se por leitura de código + o que o
  Claude.ai confirmar do lado do servidor.
- Anti-trapaça (`.claude/juiz/anti_trapaca.py --base HEAD`) + Gate do Juiz antes de aceitar.

---

## 6. Perguntas ao Claude.ai (a resolver ANTES de aplicar)

1. **Gancho da ida-online:** quem liberta a ida do €8 quando o `activate_roundtrip` conclui?
   (opção (a) ou (b) do §3). O Flutter fica tolerante enquanto não existir.
2. `tvde_create_roundtrip_credit_cash(p_outbound_ride_id)` — **assinatura e retorno exactos**
   (devolve a linha do vale? `{id, expires_at, ...}`? erro como exceção ou `{error}`?).
3. A RPC **já** exige que a ida seja `payment_method='cash'`, ou o Flutter deve garantir?
4. `cancel_reason = 'roundtrip_credit_failed'` é aceite, ou uso `payment_failed`?
5. O vale guarda o **método de pagamento** (para o admin ver "Dinheiro")?

---

## 7. Zonas 🔴 tocadas

O €8 **é dinheiro**. Este plano **não altera valores, fórmulas nem cobra nada** — só liga a UI a
contratos que o Claude.ai já construiu. Ainda assim: **`pagamentos-wallet` em PROPOSE-ONLY** e a
aplicação espera o **"vai"** do Danilo.

⚠️ **ISTO MEXE EM PAGAMENTO/DINHEIRO. O plano está pronto — confirma que eu aplico.**
