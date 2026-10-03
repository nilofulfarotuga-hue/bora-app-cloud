# PLANO — TVDE 2ª ronda de afinação (teste real: €8 + paradas + volta)

> **Estado: PLANO. Nada aplicado.** Data: 2026-07-20 · Branch `autonomous-night-2026-04-29` · HEAD `280e581`
> Âmbito: **só Flutter/UI**. Zero backend (RPC/EF/SQL) — o backend está confirmado certo.
> Baseline de testes: **39 testes TVDE** (12 `tvde_fare_view` + 9 `tvde_payment_selector` + 10 `tvde_ride_awaiting_payment` + 8 `tvde_roundtrip_cash`) + 4 `collect_badge`.

---

## Resumo executivo

| # | Bug | Causa-raiz (provada) | Ficheiro principal | Risco |
|---|-----|----------------------|--------------------|-------|
| 1 | Botão €8 cortado | `useSafeArea:true` do Flutter aplica `SafeArea(bottom:false)` — protege o topo, **exclui o fundo** de propósito. O conteúdo só compensa `viewInsets.bottom` (teclado), nunca `viewPadding.bottom` (barra de navegação) | `tvde_request_ride_screen.dart:1285-1384` | 🟢 baixo |
| 2 | "COBRAR" do motorista = €8 | **A fórmula em HEAD já dá €10** e tem teste a provar. O defeito é de **frescura do objeto `TvdeRide` do lado do motorista** (`extra_stops_fee_cents` a 0) | `tvde_pay_badge.dart` + `tvde_driver_store.dart` + `tvde_ride_active_screen.dart` | 🟡 médio |
| 3 | Falta aviso ao finalizar | Não existe — no finish só há `pushReplacement` para o ecrã de avaliação | `tvde_ride_active_screen.dart:551-600` | 🟢 baixo |
| 4 | Volta sem endereço | Sheet da volta ancorada ao fundo e a subtrair o teclado **duas vezes** (altura −inset **e** padding +inset) → campos/sugestões ficam por baixo do teclado. E tocar fora = barrier tap = `pop(null)` → volta ao ecrã normal €5 | `tvde_request_ride_screen.dart:706-760, 1513-1670` | 🟡 médio |

---

## BUG 1 — Botão "Confirmar · pagar em dinheiro" por baixo da barra do sistema

### O que se passa (provado, não suposto)
`showModalBottomSheet` em `lib/screens/client/tvde/tvde_request_ride_screen.dart:485-503` (pacote €8) e `:303-317` (corrida normal) usa `useSafeArea: true`.
No Flutter, `useSafeArea: true` envolve o conteúdo em **`SafeArea(bottom: false, …)`** — desliga o fundo de propósito (para a sheet poder encostar ao ecrã). Por isso a 1ª ronda não podia resolver.

O conteúdo (`_TvdePaymentSheet.build`, `:1285-1384`) faz:
```dart
final inset = MediaQuery.of(context).viewInsets.bottom;   // :1286 — SÓ teclado
padding: EdgeInsets.only(..., bottom: Spacing.lg + inset) // :1291-1295
```
`viewInsets.bottom` é **0** com o teclado fechado. `viewPadding.bottom` (barra de 3 botões ≈ 48 dp; gestos ≈ 16-24 dp) **nunca é considerado** — grep em todo o `lib/`: **zero** ocorrências de `viewPadding.bottom`. O botão `BoraAccentButton` (`:1354-1380`) é o último filho da Column → fica por baixo da barra.

### Padrão já correto no repo (copiar, não inventar)
`lib/screens/client/reservation/reservation_payment_method_sheet.dart:98-106`:
```dart
final viewInsets = MediaQuery.of(context).viewInsets;
return Padding(
  padding: EdgeInsets.only(bottom: viewInsets.bottom),
  child: SafeArea(
    top: false,                       // bottom fica ATIVO
    child: SingleChildScrollView(...),
```

### Fix proposto
1. Em `_TvdePaymentSheet.build` (`:1285-1295`): trocar o cálculo manual por
   `Padding(bottom: viewInsets.bottom)` **exterior** + `SafeArea(top: false)` (bottom ativo) a envolver o `SingleChildScrollView`. Já é `SingleChildScrollView` → **scrollável fica garantido**.
2. Nos dois `showModalBottomSheet` (`:485-503` e `:303-317`): manter `isScrollControlled: true`; **remover `useSafeArea: true`** (passa a ser o `SafeArea` interno a mandar, sem duplicar) e acrescentar
   `constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.9)` para a folha nunca tapar o ecrã todo.
3. Aplicar o **mesmo** padrão a `_StopPayConfirmSheet` (`tvde_ride_tracking_screen.dart`, mesmo defeito) — é a folha do pagamento da parada, o Danilo vai lá bater a seguir.

### Como se prova
- Teste de widget novo (`test/tvde_payment_selector_test.dart`): montar a sheet com `MediaQueryData(viewPadding: EdgeInsets.only(bottom: 48))` e assertar que o `bottom` do botão ≤ `screenHeight - 48`. Falha no código atual, passa depois.
- Manual: barra de 3 botões **e** navegação por gestos.

---

## BUG 2 — O "COBRAR EM DINHEIRO" do motorista mostra €8 em vez de €10

### ⚠️ Descoberta importante: a fórmula **já está certa** em HEAD

`lib/widgets/tvde/tvde_pay_badge.dart:47` já usa a **fonte única** `TvdeFareView`, a mesma do cliente:
```dart
final fare = TvdeFareView.of(ride, packageCents: _packageCents);   // → CollectBadge
```
E `lib/models/tvde_fare_view.dart:53-74` (perna do pacote) faz `base(800) + stops(200) = 1000`.
Há **teste a provar** — `test/tvde_fare_view_test.dart:58-62`:
```dart
test('com 1 parada ⇒ €10 dos DOIS lados (pacote €8 + €2)', () {
  expect(f.clientTotalCents, 1000);
  expect(f.driverCollectCents, 1000);   // ← o valor do motorista
});
```
Este código entrou no commit `0479e19` — a mesma ronda que o Danilo testou. **Logo, se o badge mostrou €8, não foi por causa da conta: foi porque o `TvdeRide` que o motorista tinha em mão trazia `extra_stops_fee_cents = 0`.** (800 + 0 = 800.)

### Por que é que o objeto do motorista fica velho
- O motorista lê a corrida por realtime — `tvde_driver_store.dart:189-208` (`_subscribe`) → `_onRideChange` (`:210`). O canal **não tem** `onError`/reconnect handler que chame `loadCurrent()`.
- Quando o cliente adiciona+paga a parada (a app do motorista pode estar em background, com o canal caído), a app volta e fica com a linha antiga. O `loadCurrent()` (`:143`) só corre no toggle Online / resume / deep-link da notificação.
- O ecrã ativo tem um sinal independente que **também** revela a desatualização: `_maybeReloadStops` (`tvde_ride_active_screen.dart:429-439`) recarrega a lista de paradas do servidor (`fetchRideStops`). Se essa lista tem N paradas e a linha em memória diz `extraStopsCount == 0`, a linha está velha — e ninguém age sobre isso.

### Fix proposto (2 camadas, sem duplicar fonte da verdade)
**(a) Auto-cura no ecrã do motorista** — `tvde_ride_active_screen.dart`, junto de `_loadStops` (`:441-447`):
depois de carregar a lista, se `_stops.length != ride.extraStopsCount`, a linha está dessincronizada → chamar `context.read<TvdeDriverStore>().loadCurrent()` (refetch da linha completa, uma vez, com guarda anti-loop por `_stopsKey`). O badge repinta com o valor certo. **A fonte da verdade continua a ser a linha do servidor** — não se soma nada localmente.

**(b) Rede de segurança no store** — `tvde_driver_store.dart:189-208`:
no `..subscribe()` passar o callback de estado (`(status, err) { if (status == RealtimeSubscribeStatus.subscribed) loadCurrent(); }`), para que **cada (re)ligação do canal** puxe a linha fresca. Cobre o caso "app esteve em background".

**Não mexer** em `TvdeFareView` nem em `TvdePayBadge` — estão certos e testados. Mexer aqui seria arriscar o €10 do cliente, que já funciona.

### Como se prova
- Teste de store/unit: dado um `TvdeRide` com `extraStopsCount:0` e uma lista de 1 parada devolvida pelo servidor → assertar que `loadCurrent()` foi chamado exactamente 1×.
- Manual: cliente adiciona parada com a app do motorista em background → trazer à frente → badge tem de dizer €10,00.

---

## BUG 3 — Aviso GRANDE ao finalizar ("💶 COBRAR EM DINHEIRO: €10,00")

### Estado actual
`tvde_ride_active_screen.dart:855-858` → botão "Finalizar viagem" → `_finish(ride)` (`:551`) → `store.finishRide(...)` (`:576-577`, devolve o `TvdeRide` já com `final_fare_cents`) → no `build` (`:693-694`) `pushReplacement` para `TvdeDriverRateScreen`.
**Não há nenhum dialog nem banner de cobrança** — nem no TVDE, nem no delivery. O padrão visual mais próximo é o banner laranja da limpeza (`cleaner_home_screen.dart:700-729`, "RECEBER €X EM DINHEIRO").

### Fix proposto
Widget novo **`lib/widgets/tvde/tvde_collect_reminder_dialog.dart`** (ou, melhor para reutilizar nas 3 verticais, `lib/widgets/payments/collect_reminder_dialog.dart`):
- `showDialog(barrierDismissible: false)` com um cartão grande: ícone `Icons.payments`, texto **"💶 COBRAR EM DINHEIRO"**, valor a `fontSize ~34, w800`, e um único botão "Recebi em mão" que fecha.
- Se `fare.isPaidOnline` → variante verde **"Já pago no app — não cobrar nada"**.
- Se `fare.driverCollectCents == 0` e coberto pelo plano → **"Coberta pelo plano — não cobrar"**.

Ligação: em `_finish` (`:551`), **depois** de `finishRide` devolver a corrida e **antes** do `_goToRate` (`:647-653`) — `await` do dialog, para o motorista não conseguir saltar por cima.
Valor: `TvdeFareView.of(finishedRide, packageCents: _packageCents).driverCollectCents` — **exactamente a mesma fonte do ponto 2**, nunca `final_fare_cents` (que numa perna do pacote é só os €2).
`_packageCents` obtém-se com `TvdeRoundtripPrice.load(store)` (`tvde_roundtrip_driver_notice.dart:27-38`, cache de sessão — leitura barata).

### Como se prova
Teste de widget: 3 casos (dinheiro €10 / pago online / coberto pelo plano) → texto e valor certos.

---

## BUG 4 — "Chamar a minha volta": não dá para pôr o endereço + cai em corrida €5

São **dois** defeitos independentes na mesma folha.

### 4a — O autocomplete não é acessível (não é o autocomplete que está partido)
`_ReturnSheet` (`tvde_request_ride_screen.dart:1513-1670`) usa o **mesmo** `AddressAutocompleteField` do pedido normal (`:1614-1630` origem, `:1632-1650` destino), com controller + `onSelected` + `onChanged` todos ligados. O widget está bem.

O que está mal é o layout (`:1580-1588`):
```dart
final inset = media.viewInsets.bottom;
height: media.size.height * 0.72 - inset,          // :1582  desconta o teclado
padding: EdgeInsets.only(..., bottom: Spacing.lg + inset), // :1588  desconta OUTRA vez
```
Não há `Padding(bottom: inset)` **exterior**, por isso com `isScrollControlled: true` (`:708`) a folha fica encostada ao fundo e o teclado tapa-a; e a faixa útil encolhe para ≈ `0.72h − 2·inset` (≈ 0 com um teclado normal). Resultado exacto do teste: o teclado sobe, mas não se vê o texto nem se consegue tocar nas sugestões.

**Fix:** copiar o padrão da folha que funciona no mesmo domínio — `tvde_ride_tracking_screen.dart:1510-1516`:
```dart
final maxSheet = media.size.height - bottomInset - media.padding.top;
return Padding(padding: EdgeInsets.only(bottom: bottomInset),   // ← exterior
  child: SizedBox(height: maxSheet,
    child: SingleChildScrollView(padding: const EdgeInsets.all(Spacing.lg), ...
```
Ou seja: **um** desconto do teclado (no `Padding` exterior), altura sem o segundo desconto, e `SafeArea(top:false)` para o botão de confirmar da volta não repetir o Bug 1.

### 4b — Tocar fora fecha a folha e perde a volta
`showModalBottomSheet` (`:706-718`) não define `isDismissible`. Tocar fora = barrier tap = `Navigator.pop(null)`; `:719` faz `if (picked == null || !mounted) return;` — sai **em silêncio**. Não existe nenhuma flag de fluxo (`_isReturnFlow`): o contexto da volta vive **só** no `Future` desse `showModalBottomSheet`. O ecrã por baixo fica com `_roundtrip = false` (`:73`) e o botão volta a ser "Solicitar corrida" → `_onRequestPressed` (`:896-905`) = corrida normal €5. O `_activeCredit` (`:75`) não se perde, mas nada reabre a folha.

**Fix (3 medidas, todas de UI):**
1. `isDismissible: false` + `enableDrag: false` na folha da volta (`:706-718`) — fechar só pelo "X"/"Cancelar" explícito. Tocar fora passa a **só fechar o teclado** (o `Padding` do 4a já reserva o espaço).
2. `GestureDetector(onTap: () => FocusScope.of(context).unfocus())` **dentro** da folha, para que tocar no corpo feche o teclado sem fechar nada.
3. Persistir o fluxo no ecrã: guardar `_pendingReturnCredit` (o `credit['id']` de `:732`) em estado do ecrã, e no `build`, se houver vale activo e o fluxo da volta estava aberto, o botão principal continuar a ser **"Chamar a minha volta"** e não "Solicitar corrida". Se o utilizador cancelar de propósito, snackbar: *"A tua volta continua disponível — podes chamá-la quando quiseres."* Nunca cair em silêncio num pedido €5.

A chamada final continua `store.requestReturnRide(creditId:…, origin…, dest…)` (`tvde_store.dart:890-911`) — **inalterada**.

### Como se prova
- Teste de widget: montar `_ReturnSheet` com `viewInsets.bottom = 300` e assertar que o campo "Destino da volta" fica visível (`tester.getRect(...).bottom <= screenHeight - 300`).
- Teste de widget: barrier tap com `isDismissible:false` não fecha a folha.
- Manual: chamar a volta ponta-a-ponta (origem + destino + confirmar) e verificar que a corrida nasce como perna do pacote (`is_return_leg`), não como corrida €5.

---

## Ordem de execução sugerida (quando o Danilo aprovar)

1. **Bug 1** (isolado, baixo risco) → correr os 39 testes.
2. **Bug 4a** (mesmo tipo de correcção de sheet — aproveita o padrão do 1) → 39 testes.
3. **Bug 4b** (estado do fluxo da volta) → 39 testes.
4. **Bug 2** (frescura do lado do motorista) → 39 testes.
5. **Bug 3** (dialog novo, depende do valor certo do 2) → 39 testes.
6. `flutter analyze` (baseline: 217 issues, 0 erros — "limpo" = 0 erros e 0 novos nos ficheiros tocados) + `flutter test` completo.
7. Gate do Juiz (`python .claude/juiz/anti_trapaca.py --base HEAD`) antes de qualquer commit.

## Zonas a NÃO tocar
- `TvdeFareView` e `TvdePayBadge` (fórmula certa + testada — o €10 do cliente depende dela).
- Qualquer RPC / Edge Function / SQL (`tvde_finish_ride`, `tvde_add_stop`, `tvde_request_return_ride`, `tvde-payment`).
- `pricing_service` e tudo o que seja Lista Vermelha. **Nenhuma das 4 correcções altera valores cobrados** — só onde e quando são mostrados.
