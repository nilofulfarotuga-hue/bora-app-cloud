# Proposta — TVDE "paragem adicional" (3 bugs) · PROPOSE-ONLY

- **Agente:** `estafeta-motorista` 🟡 · **Ordem:** ac75 `[MODELO: OPUS] [PROPOSE-ONLY]`
- **Data:** 2026-07-13 · **Branch:** `autonomous-night-2026-04-29`
- **Feature:** TVDE-CAMPO-02 F1 (paradas adicionais), LIVE desde 2026-07-04.
- **Zona:** 🔴 **adjacente** (bug #2 mexe em `tvde_finish_ride`, perto de tokens/split).
  Nada foi aplicado, nada foi editado, nada foi commitado. **Espera "vai" do Danilo.**

> ⚠️ **ISTO É ADJACENTE A DINHEIRO (bug #2).** Está tudo diagnosticado e o patch
> preparado, mas **NÃO apliquei**. Para o bug #2 o diagnóstico conclui que **não é
> preciso mexer** (já resolvido em prod) — confirma antes de eu tocar em qualquer coisa.

## Achado transversal (importante)
Os TRÊS problemas **já têm correção commitada nesta branch** e a base de dados já está
no estado pós-fix. O relatório de "ainda quebrado" cheira a **APK/deploy stale** (padrão
recorrente — ver memória `project_autocomplete_guarda_stale_apk` e
`project_tvde_tokens_half_deployed`), com uma **fragilidade residual real** no bug #1 e
uma **lacuna de UX real** no bug #3 que vale a pena endurecer. Commits relevantes:
- `f3f4dc9` — "finish_ride 4-arg (resolve PGRST203) + folha autocomplete visível"
- `83db927` — "parada extra — lista de sugestões cortada/não-clicável no bottom sheet"
- `7bc5a9c` — "fix(tvde/A2): oferta de ENTREGA em foreground toca em qualquer ecrã"

---

## BUG #1 — Autocomplete cortado/não-clicável na folha de parada

**Ficheiro:** `lib/screens/client/tvde/tvde_ride_tracking_screen.dart`
(`_addStop` linha ~135; `_AddStopSheetState.build` linhas ~1170/1178/1229)

### Causa raiz
A folha é `showModalBottomSheet(isScrollControlled: true)` → `_AddStopSheet` =
`Padding(bottom: viewInsets) > SizedBox(height: 0.7*altura) > SingleChildScrollView`.
O `AddressAutocompleteField` desenha as sugestões num **overlay de root** que abre
**para baixo** (`maxHeight: 260`) e, ao focar, faz `Scrollable.ensureVisible(alignment:0)`
para pôr o campo no topo do scrollview.

O `0.7` **fixo** é a fragilidade: com o teclado aberto, o `Padding(bottom: teclado)`
empurra a caixa de `0.7*h` para cima; em ecrãs pequenos/teclados altos
`0.7*h + teclado > h`, logo o **topo do viewport fica fora do ecrã**. O `ensureVisible`
alinha o campo ao topo desse viewport (off-screen) e os 260px da lista descem para
**trás do teclado** → sugestões **cortadas e não-clicáveis**. O `SizedBox(height: 280)`
mágico agrava (acoplado ao 260 do overlay).

### Correção proposta (dimensionar a folha ao espaço ACIMA do teclado)
```dart
// _addStop(): belt-and-suspenders
   final picked = await showModalBottomSheet<_PickedStop>(
     context: context,
     isScrollControlled: true,
+    useSafeArea: true,
     backgroundColor: AppColors.surface,
     ...
   );
```
```dart
// _AddStopSheetState.build()
-    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
-    ...
-    final maxSheet = MediaQuery.of(context).size.height * 0.7;
+    final media = MediaQuery.of(context);
+    final bottomInset = media.viewInsets.bottom;
+    // Preenche exatamente o espaço acima do teclado: o campo sobe ao topo e os
+    // 260px de sugestões ficam SEMPRE visíveis/clicáveis em qualquer ecrã.
+    // (o 0.7 fixo cortava a lista em telas pequenas / teclados altos.)
+    final maxSheet = media.size.height - bottomInset - media.padding.top;
```
Alternativa mais robusta (maior mudança, entregar ao `flutter-ui`): converter a folha
numa **página full-screen** `Scaffold > body: SingleChildScrollView`, idêntica ao padrão
JÁ PROVADO em `tvde_request_ride_screen.dart` (linha ~486-534). É o que o comentário da
folha aspira ("reusa o mesmo AddressAutocompleteField do ecrã de pedido") mas não adotou.

### Risco background/realtime
Nulo — UI pura, não toca GPS/FCM/heartbeat/realtime.

### Teste sugerido
Corrida em curso, cliente "Adicionar parada" num **ecrã pequeno (≤5") com teclado aberto**:
digitar "rua", confirmar que ≥3 sugestões aparecem **acima** do teclado e que a **última
da lista é tocável**. Repetir em ecrã grande. (E2E: `maestro`/scrcpy no fluxo cliente.)

---

## BUG #2 — Corrida não finaliza (rides com parada) · 🔴 ADJACENTE

**Ficheiros:** `lib/stores/tvde_driver_store.dart` (`finishRide`, linha ~327) +
`tvde_finish_ride` de **4 args** em prod.

### Diagnóstico (verificado ao vivo via MCP, read-only)
Estado REAL da base de dados `ojykpzwqrtusfeakzrna` (SELECT em `pg_proc`):
| assinatura | linguagem | papel |
|---|---|---|
| `tvde_finish_ride(uuid,numeric)` | sql | wrapper → delega na 4-arg |
| `tvde_finish_ride(uuid,numeric,text)` | sql | wrapper → delega na 4-arg |
| `tvde_finish_ride(uuid,numeric,text,integer)` | **plpgsql** | **REAL** (stops + roundtrip + tokens) |

O `finishRide` do app passa **os 4 params nomeados** (`p_ride_id`,
`p_final_distance_km`, `p_distance_source`, `p_tokens_to_apply:0`) → resolve
**inequivocamente** para a 4-arg → **PGRST203 (overload ambíguo) é impossível hoje**.
Confirmei também que **todas as 10 colunas** que a 4-arg lê existem em prod
(`extra_stops_count/fee_cents/driver_cents`, `roundtrip_credit_id`, `is_return_leg`,
`final_distance_source`, `tokens_applied_count`, `tokens_applied_value_cents`,
`subscription_id`, `used_subscription_ride`). E a 4-arg lê `extra_stops_fee_cents` /
`extra_stops_driver_cents` — **soma a parada** ao fare do cliente e ao ganho do motorista.

### Causa raiz
**Já resolvido em código+DB** (commit `f3f4dc9` + migrations `20260704090300` e
`20260710000000`, ambas aplicadas). O sintoma reportado corresponde a **APK stale**
(build anterior ao `f3f4dc9`, que chamava finish com uma assinatura que apanhava o
PGRST203 quando os overloads coexistiam antes de normalizados em wrappers) e/ou ao
report ter sido feito ANTES da migration `20260710000000`. A parte "erro no lado do
cliente" é sintoma secundário: se o finish falha no motorista, a corrida fica
`em_andamento` e o cliente fica **preso no tracking** (percebido como erro), não é um
erro próprio do cliente.

### Correção proposta
**Nenhuma alteração de código/DB.** (Money-adjacent — não toco.) Ação:
1. Confirmar que o APK instalado é **≥ commit `f3f4dc9`** (rebuild+reinstall se preciso — `devops-ci`).
2. Migration `20260710000000_tvde_tokens_threading_rpcs.sql` — **confirmada aplicada** (a 4-arg plpgsql existe).
3. **Opcional e NÃO recomendado** (só se o Danilo quiser cinto-e-suspensórios): dropar os
   wrappers 2-arg/3-arg para eliminar qualquer ambiguidade teórica. São delegadores
   inofensivos; dropar é mudança de DB adjacente a dinheiro → **só com "vai"**.

### Risco / Teste
Risco de aplicar = zero (nada se aplica). Teste após confirmar build: corrida com **2
paradas** → motorista "Finalizar" → estado `finalizada`, `final_fare_cents` inclui
`2×tvde_stop_fee_cents`, `driver_earn_cents` inclui `2×tvde_stop_driver_cents`; cliente
navega ao rate screen. Validar split com `driver-earnings-validator` (só leitura).

---

## BUG #3 — Notificação A2 silenciosa em foreground no mapa TVDE

**Ficheiro:** `lib/services/notification_service.dart`
(`onMessage.listen` foreground, linhas ~1009-1012; helper modelo `_showTvdeOfferNotification` ~1705)

### Causa raiz
"A2" = **oferta de ENTREGA (`new_order_offer`) em foreground** — é o próprio código que
rotula assim (comentário linha ~1002 "[A2 2026-07-04]"). Hoje, em foreground:
```dart
if (type == 'new_order_offer') {
  _sound.playOnce();   // <- só um beep curto, SEM heads-up visual
  return;
}
```
Contraste: `new_tvde_ride_offer` chama `_showTvdeOfferNotification(msg)` — heads-up
completo (canal urgente `bora_orders_urgent_v3`, som contínuo, `fullScreenIntent`,
tocável). Logo, um motorista "everything" **parado no mapa TVDE** que recebe uma oferta
de ENTREGA ouve (na melhor das hipóteses) um beep curto e **não vê card** para aceitar —
o card de delivery só existe no ecrã de delivery. Percebido como "silencioso". Parte do
report é ainda **APK stale** (commit `7bc5a9c` pode não estar no build do testador).

### Correção proposta (espelhar o caminho TVDE — visual + som, acionável em qualquer ecrã)
```dart
// onMessage foreground
   if (type == 'new_order_offer') {
-    _sound.playOnce();
+    // Antes: só um beep — no mapa TVDE (ou fora do ecrã de delivery) o motorista
+    // ouvia mas NÃO via card para aceitar. Agora heads-up local (visual + som do
+    // canal urgente), igual à oferta TVDE, acionável em qualquer ecrã.
+    unawaited(_showDeliveryOfferNotification(msg));
     return;
   }
```
```dart
// NOVO helper, modelado 1:1 em _showTvdeOfferNotification (mesmo canal urgente).
// payload {type:'new_order_offer', orderId:...} → tap abre o fluxo de aceitação.
Future<void> _showDeliveryOfferNotification(RemoteMessage message) async {
  final data = message.data;
  final orderId = data['orderId']?.toString() ?? '';
  final title = data['title']?.toString() ?? '📦 Novo pedido!';
  final body = data['body']?.toString() ??
      '${data['vendorName'] ?? 'Loja'} · ${data['driverEarnings'] ?? '—'} €';
  try {
    final plugin = FlutterLocalNotificationsPlugin();
    // ... createNotificationChannel('bora_orders_urgent_v3', ...) igual à TVDE ...
    // ... AndroidNotificationDetails Importance.max/Priority.max, fullScreenIntent,
    //     sound RawResourceAndroidNotificationSound('bora_alert') ...
    await plugin.show(orderId.hashCode, title, body,
      NotificationDetails(android: androidDetails),
      payload: jsonEncode({'type': 'new_order_offer', 'orderId': orderId}));
  } catch (_) { _sound.playOnce(); }
}
```
**Co-dono:** entregar o wiring exato ao agente `notificacoes` (canal/ícone/payload de tap
e garantir que o `_onLocalNotifTap` encaminha `new_order_offer` → gate de aceitação).
Tradeoff aceite (igual ao que o comentário já assume p/ o som): no ecrã de delivery pode
haver leve sobreposição com o card — objetivo é **nunca silêncio**.

### Risco background/realtime
Médio-baixo mas **sensível** (é FCM/heads-up, zona 🟡). Não altera dispatch nem o
caminho de background (que já mostra heads-up). Só acrescenta o heads-up em **foreground**.
Verificar que não duplica com o `OfferPresentationGate`/overlay quando ambos disparam.

### Teste sugerido
Motorista em "everything", app aberta **no mapa TVDE**, injetar `new_order_offer` (push
de teste) → confirmar **heads-up visível + som** e que o **tap abre a aceitação**. Repetir
com app em background (não deve regredir). E com ecrã bloqueado (fullScreenIntent).

---

## Resumo de aplicação (quando o Danilo disser "vai")
| Bug | Ação | Zona | Aplicar? |
|---|---|---|---|
| #1 autocomplete | 2 edits UI em `tvde_ride_tracking_screen.dart` | 🟢 | sim, após "vai" |
| #2 finish | **nada** (já resolvido em prod) + confirmar build ≥ `f3f4dc9` | 🔴 adj | não mexer |
| #3 A2 foreground | 1 edit + 1 helper em `notification_service.dart` (c/ `notificacoes`) | 🟡 | sim, após "vai" |

**Gate do Juiz** obrigatório antes de qualquer commit (anti-trapaça + 3 camadas).
**Admin Panel:** paradas já têm leitura no admin (`admin_tvde_ride_stops` / ecrã
`admin_tvde_rides_screen.dart`) — sem nova paridade necessária para estes fixes.
