# Sessão `reservas-notif-avaliacao` — FASE 0 (Investigação)

**Data:** 2026-05-17
**Branch:** `autonomous-night-2026-04-29`
**Tag rollback:** `pre-reservas-notif-2026-05-17`
**Estado:** Investigação concluída — AGUARDA APROVAÇÃO antes da FASE 2

---

## BUG 1 — "As minhas reservas" → "Ocorreu um erro"

### Causa raiz (confirmada via MCP)

A query em [lib/stores/reservation_store.dart:117-120](bora_app/lib/stores/reservation_store.dart#L117-L120) pede:

```dart
.from('reservations')
.select('*, restaurants(id, name, photo_url, image_url)')
```

Mas a tabela `restaurants` **não tem** coluna `image_url`. Colunas reais (confirmadas via `information_schema`):

| Pedido pela query | Existe no DB? |
|-------------------|---------------|
| `id` | ✅ |
| `name` | ✅ |
| `photo_url` | ✅ |
| **`image_url`** | ❌ **NÃO EXISTE** |

→ PostgREST devolve erro `42703 column restaurants.image_url does not exist`.
→ `catch (e)` em `fetchMyReservations` define `_error = 'Não foi possível carregar as reservas. Tenta de novo.'`
→ A UI mostra esse erro (`_ErrorState` em [client_reservations_screen.dart:474](bora_app/lib/screens/client_reservations_screen.dart#L474)).

### RLS — descartado como causa

`restaurants_public_read` permite SELECT a `approval_status='approved' OR is_admin()` (roles `-` = público) — **JOIN funciona** com restaurantes aprovados.

### Fix proposto

Linha única em [reservation_store.dart:118](bora_app/lib/stores/reservation_store.dart#L118):

```diff
- .select('*, restaurants(id, name, photo_url, image_url)')
+ .select('*, restaurants(id, name, photo_url)')
```

Procurar outras ocorrências do mesmo padrão (idem `subscribeMyReservations`, etc.) — mas `.stream()` não suporta JOIN, então só a fetch usa este select.

---

## BUG 2 — Auditoria notificações + push em reserva confirmada/rejeitada

### Estado actual (DB + Edge Functions confirmado)

**Triggers actuais em `reservations`:**

| Trigger | Quando | Notifica |
|---------|--------|----------|
| `trg_reservation_notify_partner_new` | INSERT `status='pending'` | Push **parceiro** via pg_net → `notify-partner` ✅ |
| `trg_reservation_late_cancel` | UPDATE `status` | Push **parceiro** se cancel late (>2h) |
| `trg_reservation_seated` | UPDATE `seated_at` | Interno (settle) |
| `trg_reservation_finished` | UPDATE `finished_at` | Interno |

**RPC `partner_decide_reservation` (accept/reject):**

```sql
UPDATE reservations SET status = 'approved'|'rejected_refunded', decided_at = NOW() ...

PERFORM _push_in_app_notification(   -- ❌ só in-app feed local, NÃO é FCM
  v_rsv.client_user_id, 'reservation',
  CASE WHEN p_accept THEN 'Reserva aprovada' ELSE 'Reserva rejeitada — reembolso' END,
  ...
);
```

→ **CLIENTE NÃO RECEBE PUSH FCM** quando parceiro aprova/rejeita.

### Mapa de auditoria completo (eventos × audiência)

| Evento | Cliente FCM | Parceiro FCM | Estafeta FCM | Admin |
|--------|:-:|:-:|:-:|:-:|
| Pedido criado (`created`) | — | ✅ `notify-partner` (NotificationService) | — | — |
| Pedido aceite (`preparing`) | ✅ `notify-client` | — | — | — |
| À procura estafeta (`callingDriver`) | ✅ `notify-client` | — | — | — |
| Estafeta aceitou (`driverAccepted`) | ✅ `notify-client` | — | ✅ `notify-driver` (dispatch) | — |
| Recolhido (`pickedUp`) | ✅ `notify-client` | — | — | — |
| A caminho (`onTheWay`) | ✅ `notify-client` | — | — | — |
| Entregue (`delivered`) | ✅ `notify-client` | — | — | — |
| Cancelado cliente | ✅ `notify-client` | ✅ `notify-partner` | ✅ se atribuído | ✅ urgent se >5€ |
| Cancelado admin | ✅ `notify-client` | ✅ | ✅ | — |
| Takeaway pronto (`readyForPickup`) | ✅ `notify-client` v14 | — | — | — |
| Sacos adicionados (mercado) | ✅ `notify-client` (Sessão 1.x) | — | — | — |
| Chat message | ✅/✅/✅ `notify-chat-message` v3 | dito | dito | — |
| **Nova reserva** | — | ✅ trigger pg_net → `notify-partner` | — | ❌ **gap menor** |
| **Reserva aprovada** | ❌ **só in-app** | — | — | — |
| **Reserva rejeitada** | ❌ **só in-app** | — | — | — |
| **Reserva cancelada cliente** | — | ✅ (apenas late >2h via `trg_late_cancel`) | — | — |
| **Reserva no-show** | — | ❌ não há push | — | — |
| Lembrete reserva 24h | ✅ cron `_reservas_pro_cron_send_reminders_24h` | — | — | — |
| Lembrete reserva 2h | ✅ cron `_reservas_pro_cron_send_reminders_2h` | — | — | — |
| Cliente chegou (markArrived) | — | ✅ push parceiro | — | — |
| Avaliação baixa parceiro | — | ✅ `notify-partner-low-rating` | — | — |

### Gaps confirmados (a corrigir)

1. **🔥 CRÍTICO — Reserva aprovada: cliente não recebe FCM.** Só `_push_in_app_notification`.
2. **🔥 CRÍTICO — Reserva rejeitada: cliente não recebe FCM.** Idem.
3. **🟡 OPCIONAL — Reserva no-show: parceiro/cliente sem push.** (decide Danilo se in-scope)
4. **🟡 OPCIONAL — Nova reserva: admin sem push.** (decide Danilo — Danilo é único admin)

### Fix proposto BUG 2

**Migration SQL** + **edição RPC**:

a) Criar helper `_reservas_pro_notify_client_push(p_client_user_id uuid, p_kind text, p_title text, p_body text, p_related_id text)` SECURITY DEFINER — mesmo pattern de `_reservas_pro_notify_partner_push`:
   - `_push_in_app_notification` (mantém feed in-app)
   - `net.http_post('/functions/v1/notify-client', body={ clientId, orderId: related_id, title, body, kind: 'reservation_decision' })`
   - Usa vault.decrypted_secrets (`project_url`, `service_role_key`)

b) Substituir em `partner_decide_reservation`:
   ```sql
   -- antes
   PERFORM _push_in_app_notification(v_rsv.client_user_id, 'reservation', ...);
   -- depois
   PERFORM _reservas_pro_notify_client_push(v_rsv.client_user_id, 'reservation', title, body, p_reservation_id::text);
   ```

c) `notify-client` Edge Function — aceitar campos `customTitle`/`customBody`/`kind` quando vêm preenchidos (já feito para notify-partner; replicar o pattern). Manter retrocompat com order status. Bump versão (v15).

d) **(Opcional) trigger no-show** + **push admin nova reserva** — apresentar separado para Danilo decidir scope.

---

## BUG 3 — Avaliação só aparece ao reabrir app

### Estado actual

`client_home_screen.dart` (lines 38-66):
- `WidgetsBindingObserver` + `addPostFrameCallback` → `_checkUnratedOrders()`  ✅ corre no init
- `didChangeAppLifecycleState.resumed` → `_checkUnratedOrders()`  ✅ corre ao voltar da background

`order_tracking_screen.dart` (lines 145-180):
- `_maybeOpenRating(order)` chamado no `build` quando status==delivered → push RatingScreen
- Flag `_ratingNavigated` previne duplicação

### Cenário que falha (confirmado por leitura)

**Caminho A — Utilizador em `client_home_screen` quando vem delivered via Realtime:**
1. Cliente está em home, browse a restaurantes
2. Estafeta marca pedido como entregue
3. `OrderStore` recebe Realtime UPDATE → status=delivered
4. Home rebuild — **mas nada chama `_checkUnratedOrders()`**
5. Cliente continua a usar app, nunca vê dialog
6. Só quando fecha+reabre (ou app vai para background+resume) é que dialog aparece

**Caminho B — Utilizador em outro ecrã (e.g. order_details, restaurant_screen):**
- Idem — só `client_home_screen.initState` + `resumed` corre o check.
- `order_tracking_screen` SIM mostra rating quando ele próprio recebe delivered (porque o `build` corre).

### Fix proposto BUG 3

Em `client_home_screen.dart`:

a) Adicionar listener ao `OrderStore` no `initState`:
   ```dart
   _orderStoreListener = () {
     final orderStore = context.read<OrderStore>();
     // Detectar transição → delivered em últimos 30s
     if (orderStore.hasRecentDeliveredOrder()) {
       _checkUnratedOrders();
     }
   };
   context.read<OrderStore>().addListener(_orderStoreListener);
   ```

b) Em `OrderStore`, expor sinal `lastDeliveredAt` (DateTime?) — actualizado quando uma order transita para delivered via Realtime.

c) `_checkUnratedOrders` já tem debounce/skip-counter — chamadas extra são seguras.

d) Anti-spam preservado: SharedPreferences `rating_skipped_${orderId}_count` (DEFAULT padrão Glovo) já existe.

**Resultado esperado:** rating dialog aparece dentro de ~1-2s do delivered, sem reabrir app.

---

## Áreas tocadas vs proibidas

### Tocadas (permitido)
- `lib/stores/reservation_store.dart` — BUG 1 (1 linha)
- `lib/stores/order_store.dart` — BUG 3 (adicionar getter `lastDeliveredAt` + notify)
- `lib/screens/client_home_screen.dart` — BUG 3 (listener)
- `supabase/functions/notify-client/index.ts` — BUG 2 (aceitar customTitle/customBody/kind, bump v15)
- `supabase/migrations/<nova>` — BUG 2 (criar helper + alterar `partner_decide_reservation`)

### NÃO tocadas (proibidas)
- ❌ `dispatch-engine`, `stripe-webhook`, `finalize-order-from-intent`
- ❌ `cancel-order-with-choice`, `client-cancel-order`, `refund`
- ❌ `pay-debt-standalone`, `create-payment-intent`, `create-mbway-*`
- ❌ `create-reservation-payment-intent` (não tocar)
- ❌ RPCs wallet_*, `create_order`, `quote_order_pricing`
- ❌ Triggers financeiros, `orders_financial_lock`
- ❌ `cart_store.dart`

---

## Smoke tests (a executar pós-fix)

| # | Teste | Critério |
|---|-------|----------|
| T1 | Abrir "As minhas reservas" | Sem erro — lista carrega |
| T2 | Tab "Próximas" | Mostra reservas com `reservedFor` futuro |
| T3 | Tab "Passadas" | Mostra reservas concluídas |
| T4 | Tab "Canceladas" | Mostra rejeitadas/canceladas |
| T5 | Reserva pending → parceiro aceita | Cliente recebe push FCM "Reserva aprovada" |
| T6 | Reserva pending → parceiro rejeita | Cliente recebe push FCM "Reserva rejeitada — reembolso" |
| T7 | Pedido on-the-way → driver marca delivered | Dialog avaliação aparece ≤3s sem reabrir app |
| T8 | Dialog "Agora não" | Fecha, não repete neste pedido |
| T9 | Dialog "Avaliar" | RatingScreen abre |
| T10 | Reabrir app após T8 | Dialog NÃO aparece (skip counter ≥2) |

---

## Bugs fora de scope encontrados (a reportar)

1. **`subscribeMyReservations`** usa `.stream(primaryKey: ['id'])` — `.stream()` do Supabase **não suporta JOIN**, então as reservas que entram via Realtime perdem `restaurant_name/photo_url`. O store já tenta `copyWithRestaurantInfo` por merge com fetch inicial, mas reservas **novas** (criadas após o initState) terão restaurantName=null até refresh manual.
   - Severidade: baixa (cosmético — só afecta reservas criadas em foreground).
   - Fix sugerido (não nesta sessão): após cada Realtime emit de uma row sem restaurantName, fazer fetch leve `restaurants(id,name,photo_url).eq('id', row.restaurant_id)`.

2. **`subscribeMyReservations` activada por `MyReservationListsScreen.initState`** — mas o ecrã principal de reservas é `ClientReservationsScreen`. Risco: se o utilizador nunca abre o ecrã de waitlist/notify, não há subscription, e a lista das reservas no ecrã principal não actualiza em tempo real (só em pull-to-refresh).
   - Fix sugerido (não nesta sessão): chamar `subscribeMyReservations()` no `initState` de `ClientReservationsScreen` também.

---

## Próximos passos

**A AGUARDAR APROVAÇÃO DE DANILO antes de FASE 2.**

Decisões pendentes:
1. BUG 2 — incluir push admin para nova reserva? (gap menor)
2. BUG 2 — incluir push parceiro+cliente em no-show? (gap menor)
3. Confirmar ordem de commits: (a) reservas image_url, (b) notify-client kind+helper, (c) RPC partner_decide, (d) Realtime rating trigger.
