---
id: PLANO-tvde-bugs-testes-reais-2026-07-20
tema: tvde
estado: atual
tipo: plano
data: 2026-07-20
autor: CEO-AI (MODO PROTECÇÃO TOTAL — plano, nada aplicado)
---

# TVDE — ronda de bugs dos testes reais (€8 · paradas · volta · mapa)

**Estado: PLANO. Zero ficheiros alterados.** Só leitura + investigação (3 agentes de
exploração + MCP Supabase read-only). Nada de backend tocado.

---

## 0. Dois avisos antes de tudo

### 0.1 🔴 A cópia local da EF `tvde-payment` está PODRE (risco de apagar produção)

| | `charge` | `refund` | `confirm_ride_payment` | `charge_stop` | `confirm_stop_payment` |
|---|---|---|---|---|---|
| **Deployed (v4, ao vivo)** | ✅ | ✅ | ✅ | ✅ | ✅ |
| **`supabase/functions/tvde-payment/index.ts` (repo)** | ✅ | ✅ | ❌ | ❌ | ❌ |

Verificado por MCP (`get_edge_function` → `version: 4`). **Se alguém correr um deploy
desta função a partir do repo, apaga da produção as 3 ações novas** — incluindo o
`confirm_ride_payment` de que a Fase A já depende. Recomendo trazer o fonte deployed
para o repo (é só sincronizar documento, sem mudar comportamento), mas como é ficheiro
de EF de pagamento **não toquei** — fica sinalizado.

### 0.2 O bug 6 não é Flutter — é backend

`tvde_request_return_ride` (migration `20260704090200_tvde_roundtrip.sql:122-130`) faz o
INSERT da corrida da volta **sem `driver_earn_cents` nem `bora_cut_cents`**. A `tvde_request_ride`
insere-os; esta não. Logo a volta nasce com `driver_earn_cents = NULL` → o Flutter faz
`?? 0` → **€0,00**. Só no *finish* é que o valor aparece (aí sim lê
`tvde_roundtrip_return_driver_cents` = 350).

O Flutter consegue **mostrar** o valor certo lendo o setting (é o que proponho, bug 6),
mas a **causa-raiz é a RPC** e fica para o Claude.ai — ver §9.

---

## 1. Factos confirmados ao vivo (MCP, read-only)

`platform_settings`:

| chave | valor |
|---|---|
| `tvde_roundtrip_price_cents` | **800** (€8) |
| `tvde_roundtrip_return_driver_cents` | **350** (€3,50) |
| `tvde_stop_fee_cents` | **200** (€2) |
| `tvde_stop_driver_cents` | **100** (€1) |
| `tvde_max_stops` | **2** |

`tvde_ride_charge_cents` **não é setting** — é RPC (`tvde_ride_charge_cents(uuid)`).

`tvde_add_stop(uuid, float8, float8, text DEFAULT NULL, numeric DEFAULT 0, text DEFAULT NULL)`
— **6.º argumento `p_payment_intent_id` tem DEFAULT** ⇒ a chamada de 5 argumentos que o
Flutter faz hoje **continua válida**. O fluxo de dinheiro **não está partido**. ✅

`tvde_request_return_ride(p_credit_id, p_origin_lat, p_origin_lng, p_origin_label,
p_dest_lat, p_dest_lng, p_dest_label, p_est_distance_km)` — **já aceita origem E destino**.
⇒ o bug 5 (2 campos) é **100% UI**, sem backend. ✅

`tvde_ride_stops` já tem `payment_intent_id` ⇒ parada paga online é rastreável (§8).

---

## 2. A peça central: o memo partilhado de preço

Hoje **não existe** função única de preço. Cada ecrã formata o seu:

| Quem | Onde | O que mostra |
|---|---|---|
| Motorista | `tvde_pay_badge.dart:66` | `finalFareCents ?? estFareCents` — **sem paradas** |
| Cliente | `tvde_ride_tracking_screen.dart:911` | `ride.displayFareCents` — **sem paradas, sem pacote** |
| Cliente | `tvde_rides_history_screen.dart:93`, `tvde_rate_screen.dart:51` | idem |

E existe `TvdeRide.liveTotalCents` (`tvde_ride.dart:193`) que **já soma as paradas** —
**código morto, 0 call sites**. Alguém antecipou o problema e nunca o ligou.

**Os bugs 2 e 3 são o mesmo bug**: não há fonte única. Proposta:

### Novo ficheiro `lib/models/tvde_fare_view.dart` (puro, sem Flutter)

```dart
class TvdeFareView {
  final int clientTotalCents;    // o que o CLIENTE paga nesta corrida
  final int driverCollectCents;  // o que o MOTORISTA recolhe em mão (0 se online)
  final String clientLabel;      // "€8,00 (ida + volta)" / "€0,00 — incluída no pacote"
  final bool approx;             // ainda é estimativa (antes do finish)
  final bool coveredByPlan, isPaidOnline;

  static TvdeFareView of(TvdeRide ride, {required int packageCents});
}
```

**Regras (a parte subtil — é aqui que nasce o "€13"):**

| Caso | base do cliente | paradas |
|---|---|---|
| Ida do pacote (`isRoundtripLeg && !isReturnLeg`) | `packageCents` → "€8,00 (ida + volta)" | `finalFareCents ?? extraStopsFeeCents` |
| Volta do pacote (`isReturnLeg`) | `0` → "€0,00 — incluída no pacote" | `finalFareCents ?? extraStopsFeeCents` |
| Coberta pelo plano (`usedSubscriptionRide`) | `0` | idem |
| Normal | `finalFareCents ?? estFareCents` | só se `finalFareCents == null`: `+ extraStopsFeeCents` |

> ⚠️ **Porque as pernas do pacote são diferentes:** a `tvde_finish_ride` faz
> `IF v_prepaid THEN v_fare := v_stops_fee` — depois do finish, o `final_fare_cents` de
> uma perna do pacote **é só as paradas**, não a tarifa. Por isso ali soma-se
> `packageCents + final`, enquanto numa corrida normal o `final` **já inclui** as paradas
> e somá-las outra vez seria dupla contagem. É exatamente esta assimetria que o memo
> existe para não deixar cada ecrã adivinhar.

`driverCollectCents = isPaidOnline ? 0 : clientTotalCents`.

`packageCents` vem do memo que **já existe e já tem cache** —
`TvdeRoundtripPrice.load()` (`tvde_roundtrip_driver_notice.dart:15-39`, lê
`tvde_roundtrip_price_cents`, fallback 800). **Zero hardcode novo.**

**Ligações:**
- `tvde_pay_badge.dart` → `driverCollectCents` (badge passa a "COBRAR EM DINHEIRO: €10,00")
- `tvde_ride_tracking_screen.dart:911` → `clientTotalCents` + `clientLabel`
- `tvde_rides_history_screen.dart:93`, `tvde_rate_screen.dart:51` → `clientTotalCents`
- `tvde_ride_tracking_screen.dart:496` (taxa de cancelamento usa `estFareCents` — errado no
  pacote) → `clientTotalCents`

**Bug 3 fica resolvido de graça:** o realtime já reconstrói o `TvdeRide` dos dois lados
(`TvdeStore._subscribeRide` `tvde_store.dart:318-337` filtrado por id; `TvdeDriverStore._subscribe`
`tvde_driver_store.dart:189-208` em todas as `tvde_rides`) e ambos os ecrãs fazem `watch`.
Quando `extra_stops_fee_cents` muda, o objeto já é substituído e os ecrãs já repintam —
**só não mudava nada porque o número exibido ignorava as paradas.** Nada de subscrições novas.

---

## 3. Bug 1 — botão cortado na folha do €8

`_TvdePaymentSheet` (`tvde_request_ride_screen.dart:1258-1356`), aberta em **dois** sítios:
`:303-315` (pedido normal) e `:483-499` (€8), ambos `showModalBottomSheet(isScrollControlled: true)`
**sem `useSafeArea`**. O padding é `EdgeInsets.only(bottom: Spacing.lg + inset)` com
`inset = MediaQuery.viewInsets.bottom` (`:1260,:1267`) — **só teclado**. Não há
`viewPadding.bottom` nem `SafeArea` ⇒ o `BoraAccentButton` (`:1326`) fica sob a barra de
gestos.

**Fix:** `useSafeArea: true` nas duas chamadas (é o que o `_AddStopSheet` já faz — consistência),
mantendo o `viewInsets` para o teclado. Verificar no device que não fica padding a dobrar.

---

## 4. Bug 4 — parada paga (CARTÃO **e** MB Way)

**Hoje as paradas estão escondidas em corridas online.** `tvde_ride_tracking_screen.dart:985-994`:

```dart
if (stops.isEmpty && (!canManage || ride.isPaidOnline)) return const SizedBox.shrink();
...
final canAdd = canManage && stops.length < maxStops && !ride.isPaidOnline;
```

Comentário no código: *"Corrida paga no app = preço FECHADO (MVP)"*. É essa a decisão que
agora muda.

**Plano:**
1. Tirar `ride.isPaidOnline` do gate e do `canAdd`.
2. `_addStop` (`:135-168`) passa a bifurcar depois de o `_AddStopSheet` devolver o `_PickedStop`:
   - **dinheiro** → caminho de hoje, intacto (`tvde_add_stop` direto, 5 args).
   - **online** → folha de confirmação **"Parada extra — €2,00"** (valor de
     `_stopFeeCents`, já lido de `tvde_stop_fee_cents`), com o método **da corrida**:
     - `card` → `charge_stop` → `PaymentService().processPayment(clientSecret)`
       (`payment_service.dart:78`, o mesmo do resto da app) → **uma** chamada a
       `confirm_stop_payment`.
     - `mbway` → **campo de telefone obrigatório**, reutilizando o widget e a validação de
       9 dígitos já feitos na Fase A (`tvde_payment_selector.dart:15-34`), pré-preenchido de
       `AuthStore.currentClient?.phone` → `charge_stop` com `phone` → **sem sheet do Stripe**
       → dialog **"Confirma o pagamento no MB Way"** com **poll de `confirm_stop_payment`
       a cada 3 s até 120 s**, via nova fábrica `TvdeRideMbwayWaitingDialog.forStop(...)`
       (o dialog já existe: `ride_mbway_waiting_dialog.dart`, poll 3 s/120 s, não-dispensável).
3. **A parada só entra na lista quando `succeeded:true`** → só aí `_loadStops()` + snackbar.
4. Estados de erro (mapeados para PT-PT, nunca "erro genérico"):

| resposta | mensagem |
|---|---|
| `succeeded:false, refunded:true` | "Pagamento devolvido — não foi possível adicionar a parada." + motivo |
| `max_stops_reached` | "Já atingiste o máximo de paradas (2)." |
| `invalid_ride_state_for_stop` | "A corrida já não permite adicionar paradas." |
| `stop_cash_flow` | defensivo: cai no caminho direto de dinheiro |
| `card_payments_not_enabled` | kill switch 🔴 desligado → "Pagamentos no cartão estão desativados." **e não adiciona** |
| timeout do poll (120 s) | "Não recebemos a confirmação do MB Way. A parada não foi adicionada." |

> Nota sobre o kill switch: o **Gate #1** da EF (`tvde_card_payments_enabled`) corre **antes
> de qualquer ação**, logo também bloqueia `charge_stop`/`confirm_stop_payment`. Tem de
> degradar com honestidade, não ficar a girar.

5. `TvdeStore` ganha 2 métodos finos: `chargeStop({...})` e `confirmStopPayment(paymentIntentId)`
   — `functions.invoke('tvde-payment', body: {...})`, mesmo padrão das 3 chamadas que já lá estão
   (`tvde_store.dart:224/376/767`).

**`segment_km`:** hoje vai sempre 0 (o call site `:150-155` nem o passa). Como
`tvde_stop_driver_cents` é **fixo** (€1) e `tvde_stop_fee_cents` é **fixo** (€2), o 0 não
altera dinheiro nenhum. **Mantenho 0** — calcular rota só para preencher um campo que não é
usado seria complicar. Fica anotado, não feito.

---

## 5. Bug 5 — folha "Chamar a volta"

`_ReturnSheet` (`tvde_request_ride_screen.dart:1473-1538`), aberta em `_callReturn()` `:680-722`:
- `showModalBottomSheet` **sem `useSafeArea`**, `Column(mainAxisSize.min)` **sem altura fixa
  e sem `SingleChildScrollView`** → é exatamente o padrão que o `_AddStopSheet` já teve de
  corrigir (o overlay do autocomplete tem 260 px e fica cortado — ver o comentário em `:1225-1234`).
- **1 campo só** (`'Destino da volta'`, `:1520-1532`). O texto diz *"A recolha é a tua
  localização atual"* (`:1517`) mas **a origem não é relida** — reutiliza o `_pickup` da **ida**
  (`:707-709`), que pode ser um pin arrastado ou uma morada escrita à mão horas antes.
- **Falha silenciosa:** guard `:683` `if (credit == null || _pickup == null) return;` — se o GPS
  falhou, o botão "Chamar a volta" **não faz absolutamente nada, sem dizer porquê**.

**Fix:** refazer a folha —
- `useSafeArea: true` + `isScrollControlled: true` + altura fixa **≥ 60 % do ecrã**
  (`media.size.height * 0.6`) + `SingleChildScrollView` + o mesmo espaçador do `_AddStopSheet`
  para o overlay do autocomplete;
- **2 campos**: **"De onde sais"** (pré-preenchido, **editável**) e **"Destino da volta"**;
- origem pré-preenchida com a **localização atual relida na hora** —
  `LocationService.getCurrentLocation()` + `reverseGeocode()` (`location_service.dart:29,69`),
  com fallback para `_pickupLabel`;
- **botão explícito** "Chamar a volta" (hoje a folha fecha-se sozinha assim que escolhes a
  morada — não há confirmação);
- devolve `_ReturnTrip(origem, destino)`; distância pelo `DirectionsService` com fallback
  haversine (código já existe `:696-702`);
- **mata a falha silenciosa**: sem GPS o utilizador escreve a origem à mão.

Backend: **nenhuma alteração** — a `tvde_request_return_ride` já recebe origem e destino.

---

## 6. Bug 6 — oferta da volta mostra €0,00

Leitura pura, sem cálculo: `tvde_offer_screen.dart:130` `(ride.driverEarnCents ?? 0)/100` →
`:183`; igual em `tvde_ride_active_screen.dart:813` → `:855`, `:570` (snackbar do finish) e
`:1305` (banner back-to-back). E o aviso propaga o mesmo zero:
`tvde_roundtrip_driver_notice.dart:57-71` diz literalmente **"Recebes €0.00 desta corrida"**.

Causa-raiz em §0.2 (backend). **Fix de exibição no Flutter:**
- Novo `TvdeReturnDriverEarn` — gémeo do `TvdeRoundtripPrice`, cache estática de
  `getSettingInt('tvde_roundtrip_return_driver_cents', 350)`. **Lê o setting, não hardcoda.**
- Nos 4 sítios acima: se `ride.isReturnLeg && (ride.driverEarnCents ?? 0) == 0` → usa o setting.
  Se o backend for corrigido e passar a trazer o valor, o valor real ganha automaticamente —
  o fallback deixa de disparar sozinho.
- Aviso passa a: **"Recebes €3,50 desta corrida. A volta já está paga — não cobres nada ao cliente."**
  (a 2.ª frase mantém-se, como pedido).

---

## 7. Bug 7 — mapa do motorista trava (diagnóstico a sério)

Não é o GPS. `getPositionStream(accuracy: medium, distanceFilter: 50)`
(`tvde_driver_home_screen.dart:417-421`) é sensato. O problema é **fan-out de rebuilds**.
Causas por ordem de impacto:

**① Animação de interpolação a repintar a app inteira ~12×/s — a causa dominante.**
`DriverStore._animateDriverTowards` (`driver_store.dart:804-823`, constantes `:20-22`):
`Timer.periodic(80 ms)` × 12 passos, **`notifyListeners()` a cada passo**. E o ciclo
**auto-alimenta-se**: o motorista faz `upsert` na tabela `drivers` (`:588-593`), o realtime
`drivers_channel` (`:680-693`) devolve-lhe **o seu próprio UPDATE**,
`_handleRealtimeDriverRecord` (`:779`) dispara a animação — para uma posição que ele já tem
em bruto do GPS. Mais um `notifyListeners()` direto em `:586`.
**Fix:** no `_handleRealtimeDriverRecord`, **ignorar o eco de si próprio** (record cujo id ==
`currentDriverId`) — a animação suave existe para o mapa **do cliente** ver os *outros*.
Sozinho, isto corta ~12 rebuilds/s da árvore toda.

**② Dois GoogleMap vivos ao mesmo tempo.**
`tvde_driver_home_screen.dart:235-237` usa `Navigator.push(TvdeRideActiveScreen)` → a home
**fica montada** com o seu `GoogleMap` (`:619`), continua a `watch` 3 stores
(`:557,:560,:575`) e continua a chamar `_followCamera → animateCamera` **num mapa invisível**.
**Fix cirúrgico:** guardar o trabalho pesado da home com
`ModalRoute.of(context)?.isCurrent != true` → não segue câmara nem refaz markers quando
está por baixo. (Trocar o `push` pelo padrão `_RootNavigator` seria mais correto
arquiteturalmente mas é bem mais invasivo — **não** proponho agora.)

**③ `addPostFrameCallback` registado a CADA build + Directions sem trava de concorrência.**
`tvde_ride_active_screen.dart:664-668` (e home `:561-565`) agenda `_maybeFetchRoute` +
`_updateBearing` + `_maybeReloadStops` **em todos os frames** (~12×/s com ①).
`_maybeFetchRoute:273` só tem `if (key == _routeKey && _routePolys.isNotEmpty) return;` —
**sem guard de in-flight**: se o Directions demorar ou falhar, dispara **N pedidos HTTP
concorrentes por segundo**. Isto é *também* um bug de custo/quota da Google, não só de UI.
**Fix:** flag `_afterFrameScheduled` + `_routeFetchInFlight`.

**④ O GoogleMap não está isolado e o cache de markers é fino de mais.**
`tvde_ride_active_screen.dart:711-729` está inline num `build()` que faz
`context.watch<TvdeDriverStore>()` (`:643`); `markers: _markers(ride, driverPos)` (`:713`)
tem cache por chave com posição a **5 casas decimais (~1 m)** (`:484-488`) → a chave muda a
**cada passo da interpolação** → `Set<Marker>` novo + diff pelo platform channel ~12×/s.
**Fix:** extrair o mapa para widget próprio alimentado por `context.select` dos valores que
lhe interessam (+ `RepaintBoundary`), e arredondar a chave para 4 casas (~11 m) ou usar
limiar de distância.

**⑤ Tickers de 1 s com `setState(() {})` vazio** a repintar o ecrã inteiro (mapa incluído):
`tvde_ride_active_screen.dart:389,:458`, `tvde_offer_screen.dart:50,:1253`; mais
`Timer.periodic(10 s)` `tvde_driver_home_screen.dart:154` (chama `loadCurrent()` →
`notifyListeners`) e `:325` (30 s).
**Fix:** contadores em `ValueListenableBuilder`/widget folha — repinta o texto, não o mapa.

**⑥** `_updateBearing:247` (`setState` + `animateCamera` 400 ms) já tem trava de 15 m/1 s
(`:174-180`) mas é realimentado pelo ciclo — passa a ser chamado do **stream de posição**,
não de cada frame.

**Como se prova que ficou fluido** (sem depender de build local — o Gradle rebenta por RAM
nesta máquina, ver `tvde-pagamentos-pente-fino-2026-07-20.md` §7):
1. contador de rebuilds com `debugPrint` no `build` do ecrã ativo — antes/depois;
2. widget test: alterar **só** a localização no `DriverStore` **não** deve reconstruir o
   widget do mapa;
3. confirmação final no device pelo Danilo (`flutter run --profile`).

---

## 8. Painel admin — SINALIZADO, não implementado

1. **Paradas pagas online** (novo): `tvde_ride_stops.payment_intent_id` já existe e já é
   preenchido pela EF v4, mas **nenhum ecrã admin mostra paradas** — nem quais foram pagas
   online, nem quais foram reembolsadas. Falta coluna/detalhe num ecrã de corridas TVDE.
2. **Método do vale** (pendente da ronda anterior): `admin_tvde_roundtrips_screen.dart` lista
   os vales mas não mostra se o €8 foi dinheiro, cartão ou MB Way.
3. **Fila de acerto** (pendente): `admin_tvde_driver_debts_screen.dart` é read-only; não existe
   RPC `admin_tvde_settle_driver_debt` para liquidar.
4. **Alerta €13** (pendente): nada deteta uma corrida onde o pacote **e** a tarifa foram
   cobrados ao mesmo cliente.
5. **Dívida do motorista em corrida online** (§8.1 do pente-fino): `tvde_finish_ride` acumula
   em `tvde_driver_balances` sem olhar ao método — com pagamento online o motorista passa a
   "dever" o que não deve. Nunca explodiu porque **nenhuma corrida online passou ainda**;
   explode na primeira. Agora que o bug 4 abre o caminho online das paradas, sobe de prioridade.

---

## 9. Para o Claude.ai (backend — não tocado por mim)

| # | O quê | Porquê |
|---|---|---|
| B1 | `tvde_request_return_ride` inserir `driver_earn_cents` (= `tvde_roundtrip_return_driver_cents`) e `bora_cut_cents` | causa-raiz do bug 6; enquanto não for feito, o Flutter mostra o setting como fallback |
| B2 | `tvde_finish_ride` não acumular dívida ao motorista quando `payment_method` é online | §8.5 — explode na primeira corrida online |
| B3 | Sincronizar `supabase/functions/tvde-payment/index.ts` do repo com o v4 deployed | §0.1 — hoje um deploy do repo apaga 3 ações de produção |

---

## 10. Ficheiros que o plano toca (só Flutter)

**Novos (2)**
- `lib/models/tvde_fare_view.dart` — o memo partilhado de preço
- `test/tvde_fare_view_test.dart` — testes do memo

**Alterados (9)**
- `lib/widgets/tvde/tvde_pay_badge.dart` — usa o memo (bugs 2,3)
- `lib/widgets/tvde/tvde_roundtrip_driver_notice.dart` — `TvdeReturnDriverEarn` + texto (bug 6)
- `lib/screens/client/tvde/tvde_ride_tracking_screen.dart` — total do cliente + paradas online (bugs 2,3,4)
- `lib/screens/client/tvde/tvde_request_ride_screen.dart` — SafeArea da folha + folha da volta (bugs 1,5)
- `lib/screens/client/tvde/ride_mbway_waiting_dialog.dart` — fábrica `.forStop()` (bug 4)
- `lib/stores/tvde_store.dart` — `chargeStop` + `confirmStopPayment` (bug 4)
- `lib/screens/driver/tvde/tvde_offer_screen.dart` — €3,50 na volta (bug 6)
- `lib/screens/driver/tvde/tvde_ride_active_screen.dart` — €3,50 + performance do mapa (bugs 6,7)
- `lib/stores/driver_store.dart` — corta o eco da própria posição (bug 7 ①)

**Também tocados por consistência de preço (bug 2):**
`tvde_rides_history_screen.dart:93`, `tvde_rate_screen.dart:51`

---

## 11. Testes

- **27 testes TVDE existentes têm de ficar verdes** (`tvde_payment_selector_test` 9 ·
  `tvde_ride_awaiting_payment_test` 10 · `tvde_roundtrip_cash_test` 8). Nenhum é apagado
  nem enfraquecido.
- **Novos** (guarda anti-regressão do "€13"):
  - memo: ida do pacote em dinheiro sem paradas → cliente €8,00 / motorista €8,00
  - memo: ida do pacote em dinheiro **com 1 parada** → **€10,00** dos dois lados
  - memo: volta → cliente €0,00 "incluída no pacote"; volta com parada em dinheiro → €2,00
  - memo: corrida normal pós-finish → **não** soma paradas duas vezes
  - memo: corrida online → motorista recolhe €0,00
  - widget: `TvdePayBadge` mostra "€10,00" na ida do pacote com 1 parada
- Gate do Juiz (`anti_trapaca.py --base HEAD`) + `flutter analyze` antes de aceitar.

---

## 12. 🔴 Aviso de dinheiro

Este plano **não altera preços, fórmulas, nem lógica de cobrança** — o que muda é **o que se
mostra** e **um caminho de UI novo que chama uma EF de cobrança que já está no ar**.

Mas há um ponto a saber antes de testar: com o bug 4 ligado, **adicionar uma parada numa
corrida de cartão/MB Way cobra €2 a sério** (`BORA_STRIPE_MODE` faz default a `live`).
O primeiro teste desse caminho gasta dinheiro real. O teste em **dinheiro** não cobra nada e
pode ser feito à vontade.

**Nada aplicado. À espera da tua revisão (e do Claude.ai) antes de escrever uma linha.**
