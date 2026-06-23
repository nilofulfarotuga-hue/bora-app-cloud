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

## Sistema de Agentes

- **Path:** `.claude/agents/` (no repo `bora_app/`). Ver `.claude/agents/README.md`.
- **Princípio:** Agentes **orquestram** skills (ferramentas); nunca duplicam a lógica delas.
  Quando existe um agente responsável por um domínio, usa o agente — ele chama as skills certas.
  Skills sem agente dono continuam a ser invocadas diretamente (ver "Skill Usage Rule").
  **O CEO-AI é o dispatcher master.** Todos os agentes leem `agent-memory.md` no arranque.
- **Regra obrigatória:** cada agente tem secção **"Admin Panel Needed?"**. Toda feature nova →
  invocar o agente `admin-sync` no final.

| Agente | Propósito |
|---|---|
| `obsidian-sync` | Sync unidirecional vault Obsidian → `knowledge/from-obsidian/` (SHA256, idempotente). |
| `catalogo-visual` | Catálogo de mercados (NÃO-PARCEIRO) + ícones/banners de categoria via nano-banana (Gemini). |
| `db-migrations` | Migrações Supabase seguras (dry-run + backup + rollback; bloqueia zonas financeiras). |
| `admin-sync` | Verifica se toda feature nova tem correspondência no admin panel (PT-BR). |
| `seguranca-rls` | SEC-1 (RLS em falta) + SEC-2 (storage buckets) + hardening contínuo. |
| `checkout-fixer` *(migrado)* | Diagnostica e corrige o checkout flow. |
| `design-system-applier` *(migrado)* | Aplica o design system (Verde `#16A34A` / Laranja `#F97316`) nos ecrãs. |
| `e2e-test-builder` *(migrado)* | Testes E2E (Flutter `integration_test`) de fluxos críticos. |
| `notifications-integrator` *(migrado)* | FCM push live + consent GDPR. |

- **Edge Functions (contagem real):** **44 funções locais** em `supabase/functions/*/index.ts`
  (a skill CEO-AI ainda diz "43 deployed / 38 locais" — **stale**, confirmar deployed via MCP
  `list_edge_functions` e atualizar `SKILL.md` com aprovação do Danilo).

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

---

## Karpathy Guidelines — Comportamento obrigatório do Claude Code

Behavioral guidelines to reduce common LLM coding mistakes.

**Tradeoff:** These guidelines bias toward caution over speed. For trivial tasks, use judgment.

### 1. Think Before Coding

**Don't assume. Don't hide confusion. Surface tradeoffs.**

Before implementing:
- State your assumptions explicitly. If uncertain, ask.
- If multiple interpretations exist, present them - don't pick silently.
- If a simpler approach exists, say so. Push back when warranted.
- If something is unclear, stop. Name what's confusing. Ask.

### 2. Simplicity First

**Minimum code that solves the problem. Nothing speculative.**

- No features beyond what was asked.
- No abstractions for single-use code.
- No "flexibility" or "configurability" that wasn't requested.
- No error handling for impossible scenarios.
- If you write 200 lines and it could be 50, rewrite it.

Ask yourself: "Would a senior engineer say this is overcomplicated?" If yes, simplify.

### 3. Surgical Changes

**Touch only what you must. Clean up only your own mess.**

When editing existing code:
- Don't "improve" adjacent code, comments, or formatting.
- Don't refactor things that aren't broken.
- Match existing style, even if you'd do it differently.
- If you notice unrelated dead code, mention it - don't delete it.

When your changes create orphans:
- Remove imports/variables/functions that YOUR changes made unused.
- Don't remove pre-existing dead code unless asked.

The test: Every changed line should trace directly to the user's request.

### 4. Goal-Driven Execution

**Define success criteria. Loop until verified.**

Transform tasks into verifiable goals:
- "Add validation" → "Write tests for invalid inputs, then make them pass"
- "Fix the bug" → "Write a test that reproduces it, then make it pass"
- "Refactor X" → "Ensure tests pass before and after"

For multi-step tasks, state a brief plan:
1. [Step] → verify: [check]
2. [Step] → verify: [check]
3. [Step] → verify: [check]

Strong success criteria let you loop independently. Weak criteria ("make it work") require constant clarification.

---

**These guidelines are working if:** fewer unnecessary changes in diffs, fewer rewrites due to overcomplication, and clarifying questions come before implementation rather than after mistakes.
