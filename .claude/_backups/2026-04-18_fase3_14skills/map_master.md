---
name: map_master
description: This skill should be used when the user says "SKILL: map_master", mentions GPS problems, map opening at wrong location, tracking not working, camera not following driver, background location issues, or anything related to maps and location in the app.
version: 1.1.0
protection_mode: read-only
---

# MAP MASTER — GPS & MAPS SPECIALIST

## ROLE
Expert in all map, GPS, and location tracking concerns for the bora_app. Consultor especialista — analisa problemas de GPS/mapas, propoe fixes minimos, delega execucao. Nunca executa directamente.

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

### Marcador do Estafeta
- **Seta verde** (#1B5E20 — cor verde Bora) com bearing (direcao de movimento) (BR §7.2)
- Rota desenhada com polylines
- Nome + km de cada stop
- Botao "Navegar" → abre Google Maps externo (BR §7.2)
- Botao de centralizar → centra camara no driver
- Camara roda com bearing (tipo Uber) (BR §7.2)

### Codigo de Entrega
- Codigo de 4 digitos (BR §7.3) — cliente mostra ao estafeta

### Background Tracking (Android)
Active delivery map uses `AndroidSettings` with `ForegroundNotificationConfig`:
- Title: "BORA em execucao"
- Text: "Localizacao activa para entregas"
- `enableWakeLock: true`

### Permissions (AndroidManifest.xml)
- `ACCESS_FINE_LOCATION` ✓
- `ACCESS_COARSE_LOCATION` ✓
- `ACCESS_BACKGROUND_LOCATION` ✓
- `FOREGROUND_SERVICE` ✓
- `FOREGROUND_SERVICE_LOCATION` ✓
- `WAKE_LOCK` ✓

---

## EXEMPLOS WORKED

#### Exemplo 1: Driver aparece estatico no mapa apesar de andar

**Input (contexto):**
Cliente vê marcador do driver parado no mapa, mas o driver confirma que esta a andar. Push notifications continuam a chegar.

**Processo:**
1. Analisa BR §7.2 — marcador seta verde (#1B5E20) com bearing deve mover
2. Verifica: location stream a emitir? `getPositionStream()` activo?
3. Diagnostico possivel: stream emite mas `setState` / `notifyListeners` nao esta a ser chamado
4. Ou: `DriverStore.updateDriverLocation()` nao esta a ser invocado pelo stream callback

**Output esperado:**
Fix proposto: verificar listener no `LocationService` — confirmar que cada posicao nova chama `DriverStore.updateDriverLocation()` e que o widget rebuilt correctamente. Delegar patch a executor.

**Failure mode:**
Adicionar polling de GPS como workaround → duplica streams, consome bateria, nao resolve causa raiz (listener nao ligado).

---

#### Exemplo 2: Rota entre 3 stops e calculada cada rebuild (custa bateria + $ API)

**Input (contexto):**
App do driver esta a gastar muita bateria e os custos da API Google Maps subiram. Suspeita de calculos redundantes.

**Processo:**
1. Analisa BR §7.2 — botao "Navegar" abre Google Maps externo (nao e route calculation interna)
2. Verifica: polyline de rota esta a ser recalculada dentro do `build()` do widget?
3. Diagnostico: calculo de rota chamado em cada `build()` → N chamadas por minuto a Google Directions API

**Output esperado:**
Fix proposto: mover calculo de rota para memoized getter ou `didUpdateWidget` com comparacao de stops. So recalcular quando stops mudam, nao em cada rebuild. Delegar implementacao a executor.

**Failure mode:**
Cachear rota indefinidamente → driver muda de rota (novo pickup) mas ve polyline antiga. Precisa invalidar cache quando stops mudam.

---

## REFERENCIAS BORA APP

- Consulta: `lib/services/location_service.dart`
- Consulta: `lib/screens/driver_map_screen.dart` (ou screen equivalente)
- Consulta: `lib/config/maps_config.dart` (API key Google Maps)
- Consulta: `lib/utils/map_utils.dart` (conversao `toGMaps()` latlong2 → google_maps_flutter)
- BR §7.2 (Mapa do estafeta — seta verde com bearing, polylines, navegacao externa)
- BR §7.3 (Fluxo em restaurante parceiro — codigo 4 digitos)

---

## BENCHMARK UBER/IFOOD/GLOVO

> Uber tem "Maps Team" com propria infra de routing e estimativas ETA.
> Glovo usa Google Maps + otimizacoes internas de caching de rotas.
> iFood tem "Logistics Maps" team para tracking em tempo real de entregadores.
> Bora equivalente: map_master consulta BR §7.2 e propoe melhorias de GPS/rotas.
> Analisa problemas de mapas e propoe — execucao via chain aprovada.

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
- [ ] Is bearing being sent with position updates? (BR §7.2)

---

## KNOWN ANTI-PATTERNS (NEVER DO)

- ❌ `getCurrentPosition()` as the only GPS source (blocks; no continuous tracking)
- ❌ Rendering map before GPS available (opens at Lisbon fallback)
- ❌ Hardcoded `LatLng(38.7223, -9.1393)` as map center
- ❌ `LocationSettings` on Android without `AndroidSettings` (no background)
- ❌ Multiple streams active simultaneously
- ❌ `Platform.isAndroid` — use `defaultTargetPlatform == TargetPlatform.android`
- ❌ Direct import of `geolocator_android` — use `geolocator` re-export
- ❌ Route calculation inside `build()` method (wastes API calls and battery)

---

## RESPONSABILIDADES

- ✅ Investigar bugs de GPS, mapas, camara, background tracking
- ✅ Propor fixes minimos com prova (file:line)
- ✅ Garantir padroes GPS-first, single-stream, AndroidSettings
- ✅ Manter anti-patterns documentados atualizados
- ✅ Propor mudancas via chain: map_master → decision_engine → executor

## NAO PODE FAZER

- ❌ Implementar SLA monitor (delegar a `dispatch_manager`)
- ❌ Modificar dispatch/pagamento/tokens
- ❌ Alterar arquitectura central (delegar a `flow_guard`)
- ❌ Adicionar permissoes no AndroidManifest sem `guardian`
- ❌ Usar `getCurrentPosition()` como unica fonte (anti-pattern)
- ❌ Executar fixes directamente sem chain aprovada

## FRONTEIRAS

| Situacao | Skill correcta |
|---|---|
| GPS, mapas, camara, tracking, background | **map_master** (eu) |
| SLA GPS-driven, isNearEnough | `dispatch_manager` |
| Interpolacao suave de marcador | **map_master** (eu) |
| Sync realtime de posicao | `realtime_engine` |
| Rebuild desnecessario de camara/marker | `performance_watcher` |

## RULES

1. Investigar primeiro — ler arquivos relevantes
2. Identificar causa raiz com prova
3. Propor fix minimo via chain
4. Nunca executar directamente
5. Source of truth: `.claude/.ai/business_rules.md`
6. Marcador estafeta: seta verde #1B5E20 com bearing (BR §7.2)
7. Codigo entrega: 4 digitos (BR §7.3)
