# SYSTEM MEMORY (ACTIVE)

## BUG HISTORY

---

BUG: `_deliveryCode` getter removed but call site not updated
CAUSA: order_details_screen.dart used local getter that was deleted in a previous session
SOLUÇÃO: replaced `_deliveryCode` with `order.deliveryCode` at call site
RESULTADO: resolved

---

BUG: `unused_local_variable` — `navigator` declared but never used in driver_map_screen.dart
CAUSA: `willFinish` path extracted to `_showDeliveryCodeDialog()` but `navigator` capture left behind
SOLUÇÃO: removed the orphaned `final navigator = Navigator.of(context)` declaration
RESULTADO: resolved

---

BUG: `use_build_context_synchronously` in driver_home_screen.dart (token refresh after push)
CAUSA: `context.read<DriverStore>()` called inside `.then()` callback after async `Navigator.push()`
SOLUÇÃO: captured `final driverStore = context.read<DriverStore>()` before `Navigator.push()`
RESULTADO: resolved

---

BUG: `unused_field` — `_packageDriverShareRate` in pricing_service.dart
CAUSA: logistics driver earnings formula changed from percentage to flat+per-km, old constant orphaned
SOLUÇÃO: removed `_packageDriverShareRate = 0.70` constant
RESULTADO: resolved

---

BUG: Type mismatch in token trigger — `orders.id` (TEXT) vs `bora_tokens.source_order_id` (UUID)
CAUSA: orders table uses TEXT for id, bora_tokens uses UUID; direct assignment fails
SOLUÇÃO: wrapped cast in `BEGIN...EXCEPTION WHEN invalid_text_representation` block
RESULTADO: resolved

---

BUG: Map opens at Lisbon fallback instead of driver real position
CAUSA: `initialCameraPosition` used `driverPosition` from DriverStore which had Lisbon hardcoded as default; no GPS fetch before rendering
SOLUÇÃO: GPS-first guard — `_gpsCenter == null` shows spinner; `getLastKnownPosition()` for instant unblock; `getPositionStream()` for continuous updates
RESULTADO: resolved

---

BUG: `geolocator_android` direct import causing `unnecessary_import` + `depend_on_referenced_packages` warnings
CAUSA: `geolocator_android` is already re-exported by the `geolocator` package; direct import unnecessary
SOLUÇÃO: replaced `import 'package:geolocator_android/...'` + `dart:io Platform` with `defaultTargetPlatform == TargetPlatform.android` from `flutter/foundation.dart`
RESULTADO: resolved

---

## PATTERNS

- Always use `getLastKnownPosition()` + `getPositionStream()` together — never `getCurrentPosition()` alone for maps
- Always guard async `BuildContext` use: capture store reference before `await` or `Navigator.push()`
- Always remove unused constants/variables immediately — analyzer catches them as warnings not info
- Supabase trigger type mismatches: TEXT↔UUID — always wrap casts in exception handlers
- `dispose()` must cancel: `_positionSubscription`, `_debounceTimer`, `_positionSubscription` (home screen)

---

## DECISIONS

- Pricing rates (as of 2026-04-04):
  - Driver base pay: €3.80
  - Driver per-km: €0.20
  - Shopping bonus: €0.80
  - Logistics base: €4.00, per-km: €0.50
  - Partner delivery fee: €2.50
  - Non-partner purchase fee: €2.50
  - Non-partner markup: 15%
  - Package base: €6.00 (first 4km), +€0.50/km after
  - Apartment surcharge: €1.50 (€1.00 driver / €0.50 platform)

- Token system:
  - 1 token = €0.01
  - Max discount at checkout: 30% of order total
  - FIFO consumption by `expires_at ASC, created_at ASC`
  - Earning: trigger-based, server-side only (ON CONFLICT DO NOTHING)

- Android location settings:
  - Delivery map: `distanceFilter: 5`, `intervalDuration: 3s`, foreground service ON
  - Idle map: `distanceFilter: 10`, `intervalDuration: 5s`, no foreground service

---

## OPERATIONAL PATTERN (OFFICIAL)

> Padrão obrigatório para todas as tarefas do projecto BORA APP.
> Definido em 2026-04-04. Não alterar sem decisão explícita.

### FLUXO PADRÃO

```
1. product_analyst  → gerar sugestões / analisar o que fazer
2. (validação externa) → confirmar com o utilizador antes de executar
3. executor         → implementar a mudança aprovada
4. tester           → validar o resultado
5. auto_debug       → se houver erro, investigar antes de voltar ao executor
6. memory           → registar apenas decisões permanentes e bugs resolvidos
```

### REGRAS PERMANENTES

- `product_analyst` deve ser consultado no início de qualquer nova feature
- Nunca executar sem validação externa quando o impacto for ALTO
- `memory` não guarda dados temporários, debug, nem tentativas falhadas
- Evitar activar múltiplas skills em paralelo — uma de cada vez, em sequência
- Execução sempre controlada: investigar → analisar → executar → validar

### OBJECTIVO

- Consistência entre sessões
- Redução de erros por execução precipitada
- Desenvolvimento mais rápido por padrão claro
- Qualidade garantida por validação obrigatória

---

## LAST LEARNINGS

- Skills must have frontmatter with `name`, `description`, `version` to be invocable via `/skill-name`
- `SnackBarAction.onPressed` accepts static method tear-offs as `const`
- `Platform.isAndroid` requires `dart:io` — prefer `defaultTargetPlatform` from `flutter/foundation.dart` (works on web too)
- Camera follow needs jitter threshold (10m) to prevent micro-animations at standstill
- Two-mode camera: stops-changed → bounds overview; position-only → smooth follow
