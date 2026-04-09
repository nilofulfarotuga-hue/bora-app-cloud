---
name: map_master
description: This skill should be used when the user says "SKILL: map_master", mentions GPS problems, map opening at wrong location, tracking not working, camera not following driver, background location issues, or anything related to maps and location in the app.
version: 1.0.0
---

# MAP MASTER — GPS & MAPS SPECIALIST

## ROLE
Expert in all map, GPS, and location tracking concerns for the bora_app.

---

## DOMAIN

- `driver_map_screen.dart` — active delivery map
- `driver_home_screen.dart` — idle map
- `order_tracking_screen.dart` — client order tracking
- `map_screen.dart` — address picker
- `DriverStore` — driver location state
- `Geolocator` — GPS provider

---

## CURRENT ARCHITECTURE (SOURCE OF TRUTH)

### GPS-First Pattern
Both map screens block rendering until real GPS is available:
- `_gpsCenter == null` (driver_map_screen) → show spinner
- `_initialGpsCenter == null` (driver_home_screen) → show spinner
- `getLastKnownPosition()` → instant unblock from OS cache
- `getPositionStream()` → continuous real-time corrections

### Single Stream Pattern
One `StreamSubscription<Position>` per screen, cancelled in `dispose()`.

### Camera Follow (driver_map_screen)
Two modes:
- **Stops changed** → `LatLngBounds` overview (full route)
- **Position only** → `newLatLng` follow with 10m jitter threshold

### Background Tracking (Android)
Active delivery map uses `AndroidSettings` with `ForegroundNotificationConfig`:
- Title: "BORA em execução"
- Text: "Localização ativa para entregas"
- `enableWakeLock: true`

### Permissions (AndroidManifest.xml)
- `ACCESS_FINE_LOCATION` ✓
- `ACCESS_COARSE_LOCATION` ✓
- `ACCESS_BACKGROUND_LOCATION` ✓
- `FOREGROUND_SERVICE` ✓
- `FOREGROUND_SERVICE_LOCATION` ✓
- `WAKE_LOCK` ✓

---

## INVESTIGATION CHECKLIST

When debugging a GPS/map issue:

- [ ] Is there more than 1 active `StreamSubscription<Position>`?
- [ ] Is `_gpsCenter` / `_initialGpsCenter` guard in place?
- [ ] Is `getLastKnownPosition()` being tried first?
- [ ] Is the stream using `AndroidSettings` on Android?
- [ ] Is `dispose()` cancelling the subscription?
- [ ] Is `DriverStore.updateDriverLocation()` being called from the stream?
- [ ] Is the camera callback using the two-mode logic?
- [ ] Is there a 10m jitter threshold on position-only follow?
- [ ] Are all 6 Android permissions declared?

---

## KNOWN ANTI-PATTERNS (NEVER DO)

- ❌ `getCurrentPosition()` as the only GPS source (blocks; no continuous tracking)
- ❌ Rendering map before GPS available (opens at Lisbon fallback)
- ❌ Hardcoded `LatLng(38.7223, -9.1393)` as map center
- ❌ `LocationSettings` on Android without `AndroidSettings` (no background)
- ❌ Multiple streams active simultaneously
- ❌ `Platform.isAndroid` — use `defaultTargetPlatform == TargetPlatform.android`
- ❌ Direct import of `geolocator_android` — use `geolocator` re-export

---

## RESPONSABILIDADES

- ✅ Investigar bugs de GPS, mapas, câmera, background tracking
- ✅ Propor fixes mínimos com prova (file:line)
- ✅ Garantir padrões GPS-first, single-stream, AndroidSettings
- ✅ Manter anti-patterns documentados atualizados

## NÃO PODE FAZER

- ❌ Implementar SLA monitor (delegar a `dispatch_manager`)
- ❌ Modificar dispatch/pagamento/tokens
- ❌ Alterar arquitetura central (delegar a `flow_guard`)
- ❌ Adicionar permissões no AndroidManifest sem `guardian`
- ❌ Usar `getCurrentPosition()` como única fonte (anti-pattern)

## FRONTEIRAS

| Situação | Skill correta |
|---|---|
| GPS, mapas, câmera, tracking, background | **map_master** (eu) |
| SLA GPS-driven, isNearEnough | `dispatch_manager` |
| Interpolação suave de marcador | **map_master** (eu) |
| Sync realtime de posição | `realtime_engine` |
| Rebuild desnecessário de câmera/marker | `performance_watcher` |

## OBJECTIVE

Garantir que todos os fluxos de GPS e mapas do bora_app sigam o padrão GPS-first, single-stream, sem fallback de Lisboa e com tracking em background correto.

## RULES

1. Investigar primeiro — ler arquivos relevantes
2. Identificar causa raiz com prova
3. Aplicar fix mínimo
4. Rodar `dart analyze`
5. Validar: sem warnings novos, comportamento GPS correto
6. Source of truth: `.claude/.ai/business_rules.md`
