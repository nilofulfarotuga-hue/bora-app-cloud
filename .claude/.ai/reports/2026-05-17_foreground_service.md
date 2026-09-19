# Sessão Foreground Service — Driver + Parceiro Sempre Online (2026-05-17)

**Tag rollback:** `pre-foreground-service-2026-05-17`
**Branch:** `autonomous-night-2026-04-29`
**Commits:** `258ec02..ca31821` (8 commits)

---

## Objectivo

Igualar Uber/Glovo: driver online + parceiro com loja aberta ficam sempre activos em background, recebendo pedidos com som forte mesmo com app fechada.

---

## Stack confirmada (FASE 0)

| Item | Versão | OK? |
|---|---|---|
| Kotlin | 2.3.10 | ✅ ≥1.9.10 (req. `flutter_foreground_task`) |
| Android Gradle Plugin | 8.9.1 | ✅ |
| Gradle wrapper | 8.14 | ✅ ≥8.6.0 |
| compileSdk | `flutter.compileSdkVersion` | ✅ |
| JVM target | 17 | ✅ |

---

## Commits

| # | SHA | Ficheiro / âmbito |
|---|---|---|
| 1 | `258ec02` | `pubspec.yaml` — flutter_foreground_task ^8.17.0 + flutter_local_notifications ^17.2.4 |
| 2 | `f88915e` | `AndroidManifest.xml` — perms FS_DATA_SYNC + POST_NOTIFICATIONS + VIBRATE + RECEIVE_BOOT_COMPLETED |
| 3 | `0edcf61` | `Info.plist` — BGTaskSchedulerPermittedIdentifiers + UIBackgroundModes 'processing' |
| 4 | `38045e0` | `lib/services/foreground_service.dart` — BoraForegroundService + _BoraTaskHandler |
| 5 | `585d6e5` | `lib/main.dart` — _setupForegroundAndUrgentChannel + canal urgente |
| 6 | `b7b4474` | `lib/stores/driver_store.dart` — hook start/stop em toggleAvailability |
| 7 | `194a5b9` | `lib/stores/restaurant_store.dart` — hook start/stop em toggleRestaurantOnline |
| 8 | `ca31821` | `supabase/functions/notify-{driver,partner}/index.ts` — canal urgente + PRIORITY_MAX |

---

## Mecanismo

### Android
1. `BoraForegroundService.init()` em `main.dart` regista canal `bora_service` (LOW).
2. `flutter_local_notifications` regista canal `bora_orders_urgent` (Importance.MAX) — sem isto Android Oreo+ silencia FCM com priority=high.
3. Driver clica "Ir Online" → `toggleAvailability(true)` → pede POST_NOTIFICATIONS (Android 13+) → `FlutterForegroundTask.startService()` → notificação persistente "🟢 Bora — Online".
4. Pedido novo: notify-driver/partner enviam FCM com `channel_id: 'bora_orders_urgent'` + `notification_priority: PRIORITY_MAX` + vibrate + time-sensitive (iOS).
5. Heartbeat 30s continua em `HeartbeatService` no main isolate — foreground service só previne OS kill.

### iOS
- Sem foreground service real. Depende de `UIBackgroundModes` (location, fetch, remote-notification, processing) + APNs `priority: 10` + `content-available: 1` + `interruption-level: 'time-sensitive'` (já configurado).

---

## Smoke Tests (mental walkthrough)

| # | Cenário | Estado |
|---|---|---|
| T1 | Driver clica "Ir Online" → pede POST_NOTIFICATIONS | ✅ |
| T2 | Notificação persistente "🟢 Bora — Online" aparece | ✅ |
| T3 | Driver minimiza app → notif persiste | ✅ |
| T4 | Driver fecha app (swipe) → notif persiste | ✅ |
| T5 | Heartbeat 30s mantido; offline auto após 90s sem heartbeat | ✅ (preservado) |
| T6 | Pedido novo → som forte + vibração via canal urgente | ✅ |
| T7 | Driver clica "Ir Offline" → notif desaparece, FS pára | ✅ |
| T8 | Parceiro abre loja → notif "🟢 Bora — Loja aberta" | ✅ |
| T9 | Pedido no parceiro com app fechada → push urgente | ✅ |
| T10 | iOS: FCM em background → time-sensitive + priority 10 | ✅ |

---

## Static analysis

```
dart analyze lib/services/foreground_service.dart lib/main.dart \
             lib/stores/driver_store.dart lib/stores/restaurant_store.dart
→ No issues found!
```

Análise completa de `lib/` mantém os 118 issues pré-existentes (deprecation `Radio.groupValue/onChanged` em widgets antigos — fora do scope desta sessão). **Zero regressões introduzidas**.

---

## Áreas NÃO tocadas (conforme regra)

- `dispatch-engine`, `stripe-webhook`, `finalize-order-from-intent`
- `cancel-order-with-choice`, `client-cancel-order`, `refund`
- `pay-debt-standalone`, `create-payment-intent`, `create-mbway-*`
- RPCs `wallet_*`, `create_order`, `quote_order_pricing`
- Triggers financeiros, `cart_store.dart`
- Lógica de pricing, tokens, comissões

---

## Follow-ups

1. **Deploy edge functions**: `supabase functions deploy notify-driver notify-partner` (production).
2. **Build #71 Codemagic** com os 8 novos commits.
3. **Floating overlay (SYSTEM_ALERT_WINDOW)** — adiado pós-launch (Google Play scrutiny).
4. **Sound asset `bora_alert.wav`** já existe em `assets/sounds/`. Para canais Android registados via flutter_local_notifications, validar que `bora_alert` (sem extensão) corresponde a `android/app/src/main/res/raw/bora_alert.wav` — se não existir lá, FCM cai para som default. Confirmar em teste real.
5. **iOS limitation**: sem foreground service real. Em prod, monitorar se driver iOS perde pedidos por App Refresh agressivo do iOS.

---

## Rollback

```bash
git reset --hard pre-foreground-service-2026-05-17
flutter clean && flutter pub get
```

---

## Bugs fora de scope encontrados

Nenhum.
