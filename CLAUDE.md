# ⚠️ PRIORITY CONTEXT (READ FIRST)

## Project: BORA APP

### Core Rules (ALWAYS FOLLOW)
- Follow: Model → Store → Screen
- NEVER use String for status
- ALWAYS use OrderStatus enum:
  created → preparing → callingDriver → driverAccepted → pickedUp → onTheWay → delivered
- NEVER break existing working features
- ALWAYS maintain Supabase compatibility

### Current Focus
- Fix realtime sync between devices
- Complete driver flow
- Fix auth/session persistence

### Important Notes
- OrderStore uses ID comparison (not reference)
- Realtime replaces objects → never rely on object identity
- DispatchEngine is memory-based with DB sync for offers
## Skill Usage Rule

- ALWAYS prefer using skills instead of long prompts
- When a task matches a skill, EXECUTE the skill immediately
- Do not ask for clarification if skill context is sufficient
- Combine skill + short context instead of large explanations
## Validation Gate (MANDATORY)

Before executing ANY task that touches:
- Payments (Stripe, MBWay, cash flow)
- Database (tables, triggers, migrations, seeds)
- Security (RLS policies, auth, permissions)
- OR has estimated effort > 1h

**STOP and output exactly this message first:**

⚠️ VALIDAÇÃO RECOMENDADA — Envia esta resposta ao Claude.ai para validação antes de aprovar.

Do NOT proceed until the user explicitly approves.

## Execution Mode

- Always execute tasks end-to-end without stopping midway
- Do not ask for confirmation unless absolutely necessary
- When fixing a problem:
  1. Identify cause
  2. Apply fix
  3. Validate result
  4. Repeat until fully resolved

- If the task is not completed:
  - Continue automatically
  - Do not stop at partial solutions

- Always simulate the result mentally before finishing
- Only finish when the system is fully working
# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Commands

```bash
flutter pub get          # install dependencies
flutter run              # run on connected device/emulator
flutter analyze          # static analysis (must return 0 errors)
flutter clean            # clear build cache (run before analyze if seeing stale errors)
flutter build apk        # build Android release
```

There are no custom scripts or Makefile. No test suite exists in this project.

---

## Schema source of truth

`supabase/schema.sql` é a **fonte da verdade declarativa do schema actual**
(snapshot CREATE TABLE consolidado). É documento, **não migration aplicável**.
Migrations efectivas estão em `supabase/migrations/` (ordem cronológica).

Notas:
- `restaurants.id`, `products.id`, `orders.id` são **TEXT** em prod (legado).
  Migration plan em `decisions/2026-04-29-restaurants-id-uuid-refactor.md`.
- `migration_trigger_dispatch.sql` (raiz `supabase/`) é boot scaffold legado
  — substituído pelas migrations `dispatch_trigger_pgcron` e
  `dispatch_ttl_auto_reject`. Não re-aplicar.
- `debug_dispatch.sql` é diagnóstico ad-hoc; não é parte do schema.

## Architecture Overview

### Three User Roles

Every feature is scoped to one of three roles: **client**, **driver**, **partner**. The role is persisted in `SessionStore` (SharedPreferences key `bora_app.user_role`) and drives the entire navigation tree.

### Navigation: `_RootNavigator` (widget-rebuild pattern)

All navigation is handled by `_RootNavigator` in `main.dart`. It watches `SessionStore` and `AuthStore` and returns different widgets based on state — it is **not** a Navigator. There are **no** `Navigator.push/pushReplacement` calls to the main screens. Any login or role change simply calls `sessionStore.setRole(...)` or sets auth state, and `_RootNavigator` rebuilds automatically.

Breaking this pattern (e.g., using `pushReplacement` from `RoleScreen`) removes `_RootNavigator` from the widget tree and makes auto-navigation stop working entirely.

### State Management: Provider chain

Providers are declared in `main.dart` in dependency order:

```
SessionStore (value, pre-created — await sessionStore.load() before runApp)
AuthStore    (create:)
CartStore
DriverStore
RestaurantStore
PartnerProductStore  ← ChangeNotifierProxyProvider<RestaurantStore>
OrderStore           ← ChangeNotifierProxyProvider2<DriverStore, RestaurantStore>
DispatchEngine       ← ProxyProvider2<DriverStore, OrderStore>
```

`OrderStore` receives `DriverStore` and `RestaurantStore` via `update:` callbacks. `DispatchEngine` is attached via `engine.attach(orderStore, driverStore)` on every provider rebuild — this call is idempotent.

### Authentication: Dual-layer

`AuthStore` has two layers:
1. **In-memory maps**: `_clientsByEmail`, `_driversByPhone`, `_partnersByEmail` — populated from hardcoded demo accounts, registrations, and SharedPreferences on startup.
2. **Supabase Auth fallback**: `loginClientAsync / loginDriverAsync / loginPartnerAsync` check in-memory first; if not found, call `supabase.auth.signInWithPassword` and verify `user.userMetadata['bora_role']`.

Driver emails in Supabase are synthetic: `{phone}@driver.bora.app`. Partners use their real email.

Non-demo accounts are persisted to SharedPreferences (keys `bora_auth.driver_account` / `bora_auth.partner_account`) so they survive app restarts. `_initFromPrefs()` is called fire-and-forget from the constructor.

**Demo accounts** hardcoded in the constructor (always available offline):
- Client: `cliente@bora.app` / `123456`
- Driver: phone `910000000` / `123456`
- No hardcoded partner demo.

### Realtime: Supabase channels

`OrderStore` subscribes to `orders_channel` on the `orders` table (INSERT / UPDATE / DELETE). The subscription is idempotent — guarded by `if (_channel != null) return`. On error it retries after 5 s via `_resubscribeWithDelay`. A fallback `Timer.periodic(3 s)` calls `refresh()` (only `notifyListeners`, not a DB fetch).

`DriverStore` subscribes to `public:drivers` for realtime driver location updates with smooth animation (12 steps × 80 ms).

### Order lifecycle & `_advanceStatus`

`OrderStatus` enum values and the strict transition flow in `OrderStore._statusFlow`:

```
created → preparing | rejected
preparing → callingDriver
callingDriver → driverAccepted
driverAccepted → pickedUp
pickedUp → onTheWay
onTheWay → delivered
```

Every transition:
1. Writes to DB first (`_updateOrderStatusInDatabase`)
2. Only mutates local state after DB confirms

**Critical**: `_advanceStatus` checks `_orders.any((o) => o.id == order.id)` (ID comparison, not object reference). Realtime UPDATE events replace the object in `_orders` with a fresh `fromSupabase` instance, so reference equality (`contains`) would silently fail.

### Driver batching rules (`DriverCapacityService`)

`lib/dispatch/driver_capacity_service.dart` controls whether a driver can be assigned an order:

- **Logistics orders** (`carryGroceries`, `sendPackage`): cannot be batched — driver must be completely free.
- **Partner orders**: max 2 simultaneous; second order must be from the same vendor OR within 800 m of the existing pickup.
- **Non-partner orders**: max 3 simultaneous; all must be from the same vendor.
- `DispatchEngine` also calls `shouldPrioritize()` to rank drivers who already have an assignment from the same non-partner vendor.

### DispatchEngine

`DispatchEngine` is a pure in-memory engine. It listens to `OrderStore` and `DriverStore` changes and cycles through eligible drivers using a timer-based offer system (`_offerTimeout = 10 s` by default).

When `currentDriverOfferId` is set, it is persisted to Supabase (`persistDriverOffer` on `OrderStore`) so other devices see the active offer and do not restart the dispatch loop.

`driverOfferHistory` is **not** persisted in the DB — it lives only in memory for the current session.

### Pricing

All fee calculation goes through `PricingService.calculateBreakdown(serviceType, subtotal, distanceKm, isPartnerStore, apartmentDelivery)`. It returns `OrderPricingBreakdown` with `deliveryFee`, `serviceFee`, `platformCommission`, `driverEarnings`, `customerTotal`. Never compute fees manually in screens.

### Map integration

The project uses **two** map packages simultaneously:
- `google_maps_flutter` — rendered map widget (driver map, client map)
- `latlong2` — coordinate math and route data

`lib/utils/map_utils.dart` provides `toGMaps()` extension to convert `latlong2.LatLng` → `google_maps_flutter.LatLng`. `google_maps_flutter`'s `LatLng` is hidden at import: `import 'package:google_maps_flutter/google_maps_flutter.dart' hide LatLng;`.

### Data flow for fake/demo data

`lib/data/fake_data.dart` contains hardcoded restaurants, markets, and pharmacies used when Supabase has no data. `lib/data/postal_coordinates.dart` maps 7 Portuguese postal codes to coordinates for order placement without GPS.

### Payment integration

`PaymentService` (`lib/services/payment_service.dart`) handles three payment methods matching the `PaymentMethod` enum (`card`, `mbway`, `cash`):

- **Card**: Stripe (`flutter_stripe`), mobile-only (`kIsWeb` guard). Backend runs as **Supabase Edge Functions** — no `BACKEND_BASE_URL` needed. `PaymentService` calls `Supabase.instance.client.functions.invoke(...)` for:
  - `create-payment-intent` — public (verify_jwt=false), server-validates amount against `orders.payment_buffer_total` (±5% tolerance)
  - `refund` — admin-only (verify_jwt=true + JWT `role=service_role` check)
  - `charge-extra` — authenticated users (verify_jwt=true)
  - All three enforce Stripe's 0.50 EUR minimum.
  - The standalone Node backend at `backend/server.js` (deployed to Render) mirrors the same endpoints as a redundancy/backup — **not** currently called by the app.
  - `notify-partner` — authenticated users (verify_jwt=true, default), fire-and-forget after createOrder; no-ops gracefully if Firebase not configured.
- **MBWay**: real Supabase Edge Function `create-mbway-payment-intent` (verify_jwt=false) — creates Stripe PaymentIntent for `mb_way` + confirms server-side with phone in E.164 format → triggers push notification to MB WAY app. Webhook `stripe-webhook` handles `payment_intent.succeeded` → marks order paid + triggers dispatch. LIVE since 2026-04-24.
- **Cash**: handled locally, no backend required.

Stripe publishable key is initialised in `main()` (non-web only).

### Maps & address autocomplete

`lib/config/maps_config.dart` exports `googleApiKey` (used by `PlaceAutocompleteService` and other map services).

`lib/services/place_autocomplete_service.dart` uses conditional imports to pick the correct platform implementation at compile time:

```dart
import 'place_autocomplete_service_stub.dart'
    if (dart.library.html) 'place_autocomplete_service_web.dart'
    if (dart.library.io)   'place_autocomplete_service_io.dart'
    as impl;
```

Each file exports `createPlaceAutocompleteServiceImpl`. The stub returns empty results (safe default for unsupported platforms).

### Key conventions

- `assigned_driver_id` is intentionally TEXT (not UUID) for historical data compatibility. Triggers that need it as UUID cast explicitly (`assigned_driver_id::UUID`). Do NOT change the column type — the cast workaround is deliberate.
- `OrderModel.fromSupabase` / `toSupabase` — all DB serialisation goes through these. `fromSupabase` maps every column; never assume defaults.
- `OrderServiceType` — 4 types: `restaurant`, `storeShopping`, `carryGroceries`, `sendPackage`. Pricing rules differ per type.
- `BusinessCategory` — enum on `RestaurantModel`: `restaurant`, `supermarket`, `store`, `pharmacy`.
- `VehicleType` — on `DriverModel`: affects which service types a driver can handle (via `supportsService()`).
- Partner orders go through `restaurantAcceptOrder → restaurantMarkReady → callingDriver` flow; non-partner orders skip directly to `preparing → callingDriver` after a simulated delay.
