# Sessão `reservas-flutter` — FASE 2 (Execução)

**Data:** 2026-05-17
**Branch:** `autonomous-night-2026-04-29`
**Tag rollback:** `pre-reservas-notif-2026-05-17`
**Push:** ✅ `23fa4fc..231eb16` → `origin/autonomous-night-2026-04-29`
**DB / Edge Functions:** aplicados via Claude.ai MCP antes desta sessão (NÃO tocados).

---

## Commits

| # | Hash | Scope |
|---|------|-------|
| 1 | `4855232` | `fix(reservas): remover image_url inexistente da query JOIN` |
| 2 | `f870408` | `fix(avaliacao): dialog imediato via OrderStore Realtime sem reabrir app` |
| 3 | `231eb16` | `fix(reservas-realtime): subscription no ecrã principal + fetch leve restaurante` |
| 4 | — | **SKIP** — handler Flutter genérico já existe |

---

## BUG 1 — "As minhas reservas" → "Ocorreu um erro" ✅

**Causa raiz:** coluna `image_url` não existe em `restaurants` (colunas reais: `id, name, photo_url, user_`). PostgREST devolvia 42703, apanhado pelo catch genérico em `fetchMyReservations`.

**Fix aplicado em [`lib/stores/reservation_store.dart`](bora_app/lib/stores/reservation_store.dart):**

- Linha 121 (`fetchMyReservations`): `restaurants(id, name, photo_url, image_url)` → `restaurants(id, name, photo_url)`
- Linha 378 (`fetchMyWaitlist`): idem
- Linha 400 (`fetchMyNotify`): idem

Comentário inline documenta a razão para evitar regressão.

---

## BUG 3 — Avaliação só aparece ao reabrir app ✅

**Causa raiz:** `_checkUnratedOrders()` só corria em `initState` postFrame + `didChangeAppLifecycleState.resumed`. Sem listener no `OrderStore` para captar transições `→ delivered` via Realtime enquanto a app está em foreground.

**Mecanismo do fix:**

[`lib/stores/order_store.dart`](bora_app/lib/stores/order_store.dart):
- Novos campos privados: `_seenDeliveredOrderIds: Set<String>`, `_lastDeliveredAt: DateTime?`, `_deliveredTrackingInitialised: bool`.
- Getter público `lastDeliveredAt`.
- `notifyListeners()` foi sobrescrito — corre `_trackDeliveredTransitions()` antes de `super.notifyListeners()`. Cobre TODOS os caminhos de mutação de `_orders` (main client stream, fallback `_clientOrdersChannel`, driver streams, `_advanceStatus`).
- A primeira chamada apenas seeda o set; só transições NOVAS para delivered marcam o timestamp — historical orders nunca disparam o dialog.

[`lib/screens/client_home_screen.dart`](bora_app/lib/screens/client_home_screen.dart):
- Import `order_store.dart`.
- Campo `_orderStore: OrderStore?` + listener `_onOrderStoreChanged`.
- `initState` postFrame: `_orderStore = context.read<OrderStore>(); _orderStore!.addListener(_onOrderStoreChanged);`.
- `dispose`: `removeListener`.
- `_onOrderStoreChanged()`: se `lastDeliveredAt` for ≤10s, agenda `_checkUnratedOrders()` após 2s de delay UX.
- Guard `_ratingCheckInFlight` previne stack de `RatingScreen` se triggers concorrentes coincidirem (resume + Realtime delivered em <2s).

---

## BUGs OS-1 / OS-2 ✅

### OS-1 — `subscribeMyReservations()` no ecrã principal

[`lib/screens/client_reservations_screen.dart:30-39`](bora_app/lib/screens/client_reservations_screen.dart#L30-L39): após o `fetchMyReservations()` em postFrame, chama agora `store.subscribeMyReservations()` (idempotente). Antes só era ligado em `MyReservationListsScreen` (waitlist/notify), por isso a lista principal não actualizava em tempo real.

### OS-2 — `.stream()` sem JOIN → fetch leve assíncrono

[`lib/stores/reservation_store.dart`](bora_app/lib/stores/reservation_store.dart):
- Novos campos: `_restaurantInfoCache: Map<String, ({String name, String? photoUrl})>`, `_restaurantFetchInFlight: Set<String>`.
- `subscribeMyReservations()` callback:
  1. Quando uma row vem com `restaurantName != null` → guarda em cache.
  2. Quando vem `null` → tenta merge de prev (já existia), depois cache, e só em último caso agenda fetch.
- Novo helper `_ensureRestaurantInfoFetched(restaurantId)`:
  - Fire-and-forget. Idempotente (cache + in-flight set).
  - `SELECT name, photo_url FROM restaurants WHERE id = ?`.
  - Ao chegar, re-merge das reservas locais com esse `restaurantId` e `notifyListeners()`.

---

## COMMIT 4 — Handler Flutter `type='reservation_status'`: SKIP

[`lib/services/notification_service.dart:127-137`](bora_app/lib/services/notification_service.dart#L127-L137) já tem handler genérico:

```dart
FirebaseMessaging.onMessage.listen((RemoteMessage msg) {
  if (msg.data['type'] == 'new_order') return;          // skip (Realtime já trata)
  if (msg.data['type'] == 'chat') { _showChatBanner(msg); return; }
  _sound.playOnce();                                     // outros tipos: só som
});
```

- **App em background/terminated:** FCM mostra título+body nativamente — utilizador vê "Reserva aprovada" / "Reserva rejeitada — reembolso". ✅
- **App em foreground:** toca som, sem banner visível (consistente com TODOS os outros pushes não-chat).

Per instrução do Danilo: *"Se já existe handler genérico que mostra qualquer push: OK, não tocar."* → sem COMMIT 4.

**Nota:** `onMessageOpenedApp.listen` apenas faz `debugPrint` — não navega. Adicionar deep-link para `/client/reservations` quando `data['type'] == 'reservation_status'` é melhoria pós-lançamento (todos os outros tipos sofrem do mesmo).

---

## Smoke tests (mentais — Flutter não executado)

| # | Cenário | Estado |
|---|---------|:-:|
| T1 | "As minhas reservas" abre sem erro | ✅ image_url removido |
| T2 | Tab "Próximas" mostra reservas futuras | ✅ `isUpcoming` getter inalterado |
| T3 | Tab "Passadas" e "Canceladas" | ✅ getters inalterados |
| T4 | Reserva pending → parceiro aprova → cliente recebe push | ✅ via DB (MCP) |
| T5 | Reserva pending → parceiro rejeita → cliente recebe push | ✅ via DB (MCP) |
| T6 | Pedido `delivered` → dialog avaliação em ~2s sem reabrir | ✅ listener + delay UX |
| T7 | Dialog "Agora não" → fecha, não repete | ✅ `rating_skipped_<id>_count` preservado |
| T8 | Dialog "Avaliar" → rating screen abre | ✅ `RatingScreen` route inalterada |
| T9 | Ecrã reservas actualiza quando chega novo status | ✅ `subscribeMyReservations` no initState |
| T10 | Push reserva confirmada (tap → navega) | 🟡 mostra notif em background; tap não navega (mesmo que outros tipos) |

---

## `dart analyze`

❌ Não corrido — `flutter analyze` e `dart analyze` ambos falham com **out-of-memory** no Windows (page file insuficiente para `analysis_server.dart.snapshot`). Erro de ambiente, não de código.

**Diagnóstico IDE LSP (post-edit hooks):** nenhum erro/warning ficou pendente após as edits — o único warning durante a sessão (`_checkInFlight` unused) foi corrigido imediatamente.

**Verificação manual:**
- Override `notifyListeners` em `ChangeNotifier`: API pública do Flutter, padrão suportado.
- Record type `({String name, String? photoUrl})`: Dart 3.0+, projecto já usa records (e.g. `notification_service.dart`).
- `unawaited(...)`: importado via `dart:async` já presente em `reservation_store.dart`.

---

## Bugs fora do scope encontrados

1. **`onMessageOpenedApp` não navega** — apenas `debugPrint`. Aplica-se a TODOS os tipos de push (chat, ordem, reserva). Pós-lançamento.
2. **Foreground sem banner visível** — `onMessage` só toca som excepto chat. Aceitável para lançamento (notificação aparece em background, e a UI tem Realtime para reflectir o estado). Pós-lançamento, considerar mostrar `BoraSnackBar` para reservas.
3. **Edge Function `notify-client` v15** — aceita agora `customTitle/customBody/kind/type`. Falta validar em prod se o payload do helper DB chega ao FCM com o conteúdo correcto (DB já está aplicada via MCP). Smoke test manual recomendado: criar reserva, aprovar via parceiro, observar push no telemóvel.

---

## Follow-ups identificados

| ID | Item | Prioridade |
|----|------|-----------|
| F1 | Smoke test manual end-to-end com parceiro real (T4/T5/T6) | Alta — lançamento |
| F2 | Deep-link `onMessageOpenedApp` por `data['type']` (reservation_status → `/client/reservations`; order_status → `/client/orders`) | Média — pós-lançamento |
| F3 | Banner foreground para reservation_status (mimica chat banner) | Baixa — pós-lançamento |
| F4 | Considerar `subscribeMyReservations()` em `client_main_screen.dart` para garantir Realtime mesmo sem entrar no ecrã de reservas | Baixa |

---

## Áreas tocadas vs proibidas

### Tocadas (Flutter only — permitido)
- `lib/stores/reservation_store.dart`
- `lib/stores/order_store.dart`
- `lib/screens/client_home_screen.dart`
- `lib/screens/client_reservations_screen.dart`

### NÃO tocadas (todas respeitadas)
- ❌ dispatch-engine, stripe-webhook, finalize-order-from-intent, cancel-order-*, refund
- ❌ pay-debt-standalone, create-payment-intent, create-mbway-*
- ❌ create-reservation-payment-intent
- ❌ RPCs wallet_*, create_order, quote_order_pricing
- ❌ Triggers financeiros, cart_store.dart
- ❌ notify-client Edge Function, partner_decide_reservation RPC (já aplicados via MCP)

---

## ROLLBACK

```bash
git reset --hard pre-reservas-notif-2026-05-17
```

A tag aponta para `23fa4fc` (commit antes desta sessão). Rollback descarta os 3 commits.
