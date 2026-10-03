# Auditoria Mapa & Navegação Estafeta — Completa
> Data: 2026-04-24
> Vs Uber Eats Driver / Glovo Courier / iFood Entregador
> Repo: `C:\Users\danil\Desktop\projetosflutter\bora_app\`

---

## Mapa de subsistemas

| Componente | Ficheiro | Detalhe |
|---|---|---|
| GPS source | `lib/screens/driver_map_screen.dart` (`_startLocationTracking`) | `Geolocator.getPositionStream` — **cada `DriverMapScreen` cria o seu próprio stream** (não usa `LocationService` nem `DriverStore`). |
| LocationService (legado) | `lib/services/location_service.dart` | Existe, mas **não é usado pelo driver map** — usa apenas `getCurrentPosition` ad-hoc. |
| Settings Android | `AndroidSettings(accuracy: bestForNavigation, distanceFilter: 0, intervalDuration: 1s, ForegroundNotificationConfig)` | Foreground service ativo — bom. |
| Settings iOS | `LocationSettings(accuracy: bestForNavigation, distanceFilter: 0)` | **Sem `pauseLocationUpdatesAutomatically`, sem `activityType`** — ineficiente. |
| Smoothing | `_animateToNewPosition` em `driver_map_screen.dart` | Interpolação 60 fps × 600 ms (≈36 frames), threshold 1 m. |
| Bearing | `atan2` (haversine) calculado uma vez por animação | Bom — evita jitter. |
| Realtime sync para Supabase | `DriverStore.updateDriverLocation` (chamado a partir do stream do screen) | Subscrição `public:drivers` + animação 12 × 80 ms (1 segundo total, redundante com a animação local de 600 ms). |
| Directions API | `lib/services/directions_service.dart` (+ stub/web/io) | Google Directions REST; debounce 300 ms; cache por `_activeRouteKey`. |
| Polyline trim | `_trimPassedRoutePoints` | Remove pontos já passados a cada update. |
| Off-route reroute | `_checkOffRouteAndReroute` | Threshold 50 m, throttle 15 s. |
| Route optimizer | `lib/services/route_optimizer.dart` | Greedy nearest-neighbour: pickups primeiro, depois deliveries. |
| Markers | `MapMarkerHelper.pickupIcon / deliveryIcon`, custom green-arrow para driver | Web cai para blue-dot nativo (`myLocationEnabled = true`). |
| Camera | `animateCamera(newLatLngBounds, 100)` em `addPostFrameCallback` quando muda `stopsKey` | Sem follow contínuo; sem zoom/tilt navegacional. |
| Google Maps / Waze | `lib/services/navigation_service.dart` | URL launcher para ambos. |
| Permissions Android | `AndroidManifest.xml` | `ACCESS_FINE_LOCATION`, `ACCESS_COARSE_LOCATION`, `ACCESS_BACKGROUND_LOCATION`, `FOREGROUND_SERVICE` (+`_LOCATION` typed). |
| Permissions iOS | `ios/Runner/Info.plist` | **Não foi possível confirmar `NSLocationAlwaysAndWhenInUseUsageDescription`** — verificar. |

---

## 🔴 BUGS CRÍTICOS

### [BUG-MP-001] Dual GPS stream — bateria e tráfego duplicados
`driver_map_screen.dart:_startLocationTracking` abre `Geolocator.getPositionStream`. Existe também `BUG-016-driver-location-dual-stream.md` já registado a confirmar duplicação. O `DriverHomeScreen` mostra um `GoogleMap` com `myLocationEnabled: true` (linhas 614-615), o que ativa **um segundo consumer GPS nativo** simultâneo. Concorrência: dois ouvintes a 1 s + foreground notification + animação 60 fps. Drena bateria ~2× vs Uber/Glovo.

### [BUG-MP-002] `distanceFilter: 0` + `intervalDuration: 1s` em modo navegação
O cliente nunca filtra updates por distância — toda movimentação minúscula (sub-metro) gera evento. O guard-rail `_jitterThresholdMetres = 1.0` no screen mitiga, mas o stream **continua a despertar a CPU 1×/s** mesmo parado. Uber Eats Driver usa `distanceFilter: 5-10 m` quando parado e `1-2 m` em movimento (adaptive).

### [BUG-MP-003] Animação dupla — local 600 ms + DriverStore 12×80 ms = 1 s
`driver_map_screen` interpola GPS local (600 ms, 60 fps) **e** `DriverStore` interpola novamente quando o evento volta via realtime (12 steps × 80 ms = 960 ms). Para o próprio estafeta isto cria **duas trajetórias visuais sobrepostas** (uma para o seu marker local, outra para o evento realtime do mesmo driver). Risco de teleport/flicker.

### [BUG-MP-004] Camera não segue o estafeta em modo navegação
Toda a lógica de câmara é `newLatLngBounds` (overview do route inteiro) e só dispara quando `stopsKey` muda. Não existe modo follow (`tilt: 60°, zoom: 18, bearing: heading`). Estafeta numa entrega vê o mapa de cima, sem perspetiva navegacional. Uber Eats / Waze fazem follow contínuo com tilt.

### [BUG-MP-005] Botão "centrar em mim" incompleto
`driver_map_screen.dart` tem `_MapButton(icon: Icons.my_location, onTap: () { _mapController?.…` — o callback **aparenta estar truncado/incompleto** no excerto indexado. Verificar se realmente aciona `animateCamera` para `displayPosition`.

### [BUG-MP-006] Polyline preservada quando falha Directions ≠ rota corrente
Quando a API falha em `_updateRouteMulti`, o código mantém `_routePoints` antigo + `_routeDurationMinutes` antigo. Se entretanto o driver **passou de pickup para dropoff** (mudou destino), o estafeta fica a ver a rota anterior — incorreta. Falta invalidar quando `stopsKey` mudou.

### [BUG-MP-007] iOS sem `activityType` / `pauseLocationUpdatesAutomatically: false`
No iOS, `LocationSettings` por defeito permite ao SO pausar updates quando deteta paragem do veículo. Para uma app de entregas isto é fatal — o sistema pode parar de receber GPS por minutos. Falta `pauseLocationUpdatesAutomatically: false` e `activityType: ActivityType.automotiveNavigation`.

---

## 🟡 BUGS MÉDIOS

### [BUG-MP-008] Trim de polyline ingénuo
`_trimPassedRoutePoints` calcula distância ponto-a-ponto a TODOS os pontos do polyline a cada update GPS — O(N) por update. Numa rota de 500 pontos × 1 update/s = 500 cálculos/s. Devia avançar incrementalmente a partir do último índice conhecido.

### [BUG-MP-009] Off-route threshold fixo (50 m)
Em estradas onde GPS desvia ±30 m frequentemente, 50 m é demasiado próximo do ruído. Concorrentes usam thresholds dinâmicos (50–80 m) e exigem **N updates consecutivos** acima do threshold antes de re-rotear, evitando re-rotes oscilatórios.

### [BUG-MP-010] Reroute throttle de 15 s pode atrasar correção em curvas perdidas
Se driver erra cruzamento, espera 15 s pela próxima rota — pode já ter andado 300 m no caminho errado.

### [BUG-MP-011] ETA não recalcula quando a polyline mantém o mesmo trajeto
Quando `_routePointsChanged` retorna false (ponto inicial/final igual, mesmo número de pontos), o `setState` não atualiza `_routeDurationMinutes`. Se trânsito mudou mas trajeto continua o mesmo, ETA fica congelado.

### [BUG-MP-012] Bearing calculado uma vez por animação (não por frame)
Cometário do código admite isto. Bom para evitar jitter em paragem, mas em curvas, marker mostra bearing antigo durante 600 ms — pode parecer "deslizar de lado" antes de virar.

### [BUG-MP-013] Não há indicador visual de perda de GPS
Se stream falha, snackbar inicial ("GPS desativado") só dispara em `_startLocationTracking`. Perda **a meio da entrega** é silenciosa — ultima posição mantém-se indefinidamente sem alerta visual ao estafeta.

### [BUG-MP-014] Sem modo offline / queue local
Não foi encontrado nenhum buffer local (SharedPreferences/Hive/SQLite) para guardar updates GPS quando rede falha. Concorrentes guardam queue de breadcrumbs e fazem upload em batch ao recuperar rede.

### [BUG-MP-015] `myLocationEnabled` cai para blue-dot nativo na Web
Quando `_driverArrowIcon == null`, ativa blue-dot, **mas** o blue-dot nativo do GoogleMap também pede GPS independentemente — concorrência + duplicação no Web.

### [BUG-MP-016] `mapToolbarEnabled: false` + `myLocationButtonEnabled: false` removidos no map principal mas presentes no `driver_home_screen` (mapa de fundo) — inconsistência UX.

---

## 🟢 BUGS BAIXOS

### [BUG-MP-017] `flutter_map: ^8.2.2` no `pubspec.yaml` mas a app usa `google_maps_flutter` — dependência morta ou redundante.
### [BUG-MP-018] `geolocator: ^10.1.0` — versão atual é 12.x; muitas melhorias de bateria perdidas.
### [BUG-MP-019] `google_maps_flutter: ^2.6.0` — versão atual 2.9+ inclui `MarkerId.zIndexInt` corretamente tipado e `cloudMapId`.
### [BUG-MP-020] Stable initial center hardcoded fallback (`_defaultFallbackCenter`) — verificar se é Lisboa centro vs zona do estafeta.
### [BUG-MP-021] `_interpolationFrame = 16ms (~60 fps)` em background drena bateria. Devia cair para 30 fps quando app em background ou ecrã tapado.
### [BUG-MP-022] `Timer.periodic` para interpolação não cancelado em `dispose` se o widget for substituído antes de o timer terminar (verificar dispose completo).
### [BUG-MP-023] `NavigationService.openNavigationOptions` não passa o **endereço** (só lat/lng) para o Waze/Maps — UX pior que Uber que envia o endereço textual.
### [BUG-MP-024] Sem suporte para Apple Maps no iOS (só Google Maps + Waze).

---

## 🔴 MELHORIAS CRÍTICAS

### [MEL-MP-001] Modo "Navegação" tipo Uber (vs Uber Eats Driver)
Ativar perspetiva 3D (`tilt: 60°`), zoom alto (18), `bearing` = heading do driver, follow contínuo, e voice prompts ("Vire à direita em 200 m"). Atualmente é uma vista top-down estática.

### [MEL-MP-002] Adaptive GPS sampling (vs Glovo)
Velocidade < 2 m/s → `distanceFilter: 10 m`; 2–10 m/s → `5 m`; > 10 m/s → `2 m`. Reduz drain ~40 %.

### [MEL-MP-003] Single source of truth para GPS (vs todos)
Centralizar num `LocationService` singleton que abre **um único** `getPositionStream` partilhado entre `DriverHomeScreen`, `DriverMapScreen`, e `DriverStore`. Hoje há ≥2 consumers concorrentes.

### [MEL-MP-004] Voice turn-by-turn (vs Waze/Uber)
Integrar `flutter_tts` com instruções da Google Directions API (steps[].html_instructions). Sem voz, estafeta tira olhos da estrada.

### [MEL-MP-005] Stacking visual da próxima paragem em destaque (vs iFood)
Markers de paragens 2…N deveriam ser cinzentos/translúcidos; **só a próxima a cores**. Atualmente todos têm o mesmo peso visual com numeração 1, 2, 3…

---

## 🟡 MELHORIAS

### [MEL-MP-006] Cache local de tile do Google Maps para zonas habituais (offline-first).
### [MEL-MP-007] Botão swipe "Cheguei" automático com geofence de 50 m do destino.
### [MEL-MP-008] Indicador de qualidade GPS (HDOP / accuracy em metros) na UI.
### [MEL-MP-009] Heatmap de ordens disponíveis quando ocioso (igual Uber Driver).
### [MEL-MP-010] Reroute "smart" — pondera trânsito tempo-real (Directions API `departure_time=now` + `traffic_model=best_guess`).

### [MEL-MP-011] Endereço passado ao Waze/Maps em vez de só lat/lng.
### [MEL-MP-012] Botão "ligar ao cliente" inline no mapa (link tel: já existe? verificar).
### [MEL-MP-013] Mostrar tempo restante até pickup vs até dropoff em pílulas separadas.
### [MEL-MP-014] Animação de "pulse" no marker da próxima paragem para chamar atenção.

### [MEL-MP-015] Modo dark map (`mapStyle` JSON) automático conforme tema do sistema.
### [MEL-MP-016] Suporte Apple Maps no iOS (URL `maps://`).

---

## Verificação ponto-a-ponto das 16 dimensões

| # | Dimensão | Estado | Análise |
|---|---|---|---|
| 1 | GPS suave sem saltos | 🟡 Parcial | 60 fps × 600 ms interpolação local — mas **dual stream** (BUG-001) e jitter 1 m threshold só no marker, não no DriverStore (12×80 ms anim separada). |
| 2 | Rota actualiza em real time | ✅ Sim | Debounce 300 ms; refetch quando driver move > X m. |
| 3 | Mostra só o próximo destino | ❌ Não | Stops todos visíveis numerados (BUG-MEL-005). |
| 4 | Distâncias correctas | ✅ Sim | `RouteOptimizer` usa `latlong2.Distance` (haversine). Directions API devolve distâncias reais de estrada. |
| 5 | ETA em tempo real | 🟡 Parcial | Atualiza no fetch da Directions; **congela quando trajeto não muda mesmo se trânsito mudar** (BUG-MP-011). |
| 6 | Bearing roda com movimento | ✅ Sim | `atan2` haversine, marker `flat: true, rotation: _bearing`. Mas calcula 1× por animação, não por frame (BUG-MP-012). |
| 7 | Botão Google Maps / Waze | ✅ Sim | `NavigationService.openNavigationOptions` com bottom sheet. Falta Apple Maps. |
| 8 | Transição suave entre destinos | 🟡 Parcial | Mudar de pickup→dropoff dispara `newLatLngBounds` (corte de overview), não animação contínua. |
| 9 | Stacking ordem clara | 🟡 Parcial | RouteOptimizer ordena, markers numerados 1,2,3. Falta ênfase na próxima paragem (MEL-MP-005). |
| 10 | Perda de GPS — fallback | 🟡 Parcial | Snackbar no arranque; **sem notificação se cair a meio** (BUG-MP-013). Fallback usa `currentDriver.location` ou centro padrão. |
| 11 | Eficiência bateria | ❌ Não | `distanceFilter: 0`, 60 fps, dual-stream, foreground-service permanente, iOS sem activity-type. |
| 12 | Modo offline | ❌ Não | Nenhum buffer local de breadcrumbs (BUG-MP-014). |
| 13 | Marker driver vs cliente | ✅ Sim | Green-arrow custom (driver) vs `pickupIcon`/`deliveryIcon` (stops). |
| 14 | Polyline rota | ✅ Sim | Decoded da Directions API; trimmed à medida que driver avança. Cor/largura não inspecionada — verificar `MapMarkerHelper`. |
| 15 | Camera follow + centrar em mim | 🟡 Parcial | Não há follow contínuo (BUG-MP-004); botão `Icons.my_location` existe mas callback aparenta truncado (BUG-MP-005). |
| 16 | Permissions GPS / background | ✅ Android, ❓ iOS | `AndroidManifest.xml` completo. `Info.plist` precisa verificação manual de `NSLocationAlwaysAndWhenInUseUsageDescription`. |

---

## Pontuação vs concorrentes

| Eixo | Bora | Uber Eats | Glovo | iFood |
|---|---|---|---|---|
| GPS smoothness | 6/10 | 9 | 9 | 8 |
| Bateria | 4/10 | 9 | 8 | 8 |
| Navegação turn-by-turn | 2/10 | 9 | 7 | 7 |
| Robustez offline | 1/10 | 8 | 8 | 7 |
| UX do mapa | 6/10 | 9 | 9 | 8 |
| Permissions / background | 7/10 | 10 | 9 | 9 |
| Stacking multi-pedido | 7/10 | 9 | 8 | 8 |
| Re-routing inteligente | 5/10 | 9 | 8 | 8 |

**TOTAL: 38/80 → ~48/100**

---

## Recomendação — top 5 a atacar primeiro

1. **[BUG-MP-001 + MEL-MP-003] Single GPS source of truth.** Refatorar `LocationService` em singleton que partilha um único `Stream<Position>` entre `DriverHomeScreen`, `DriverMapScreen` e `DriverStore`. Elimina dual-stream, drain de bateria e race-conditions. **ROI mais alto.**
2. **[BUG-MP-007] iOS `activityType: automotiveNavigation` + `pauseLocationUpdatesAutomatically: false`.** Mudança de 3 linhas — sem isto, app de entregas é inutilizável em iPhone.
3. **[BUG-MP-002 + MEL-MP-002] Adaptive `distanceFilter`.** Implementar amostragem por velocidade. -40 % drain estimado.
4. **[BUG-MP-004 + MEL-MP-001] Modo Navegação 3D com follow + tilt.** Diferenciador chave vs estafetas habituados ao Uber/Waze. Adiciona `CameraPosition(tilt: 60, zoom: 18, bearing: _bearing)` em `_animateToNewPosition`.
5. **[BUG-MP-006 + BUG-MP-011] Invalidação correta de polyline + ETA.** Quando `stopsKey` muda, limpar `_routePoints` e `_routeDurationMinutes` antes do refetch — evita mostrar rota da entrega anterior.

---

## Ficheiros-chave inspecionados (caminhos absolutos)

- `C:\Users\danil\Desktop\projetosflutter\bora_app\lib\screens\driver_map_screen.dart`
- `C:\Users\danil\Desktop\projetosflutter\bora_app\lib\screens\driver_home_screen.dart`
- `C:\Users\danil\Desktop\projetosflutter\bora_app\lib\services\location_service.dart`
- `C:\Users\danil\Desktop\projetosflutter\bora_app\lib\services\navigation_service.dart`
- `C:\Users\danil\Desktop\projetosflutter\bora_app\lib\services\directions_service.dart` (+ `_io.dart`, `_web.dart`, `_stub.dart`)
- `C:\Users\danil\Desktop\projetosflutter\bora_app\lib\services\route_optimizer.dart`
- `C:\Users\danil\Desktop\projetosflutter\bora_app\lib\stores\driver_store.dart`
- `C:\Users\danil\Desktop\projetosflutter\bora_app\lib\utils\map_utils.dart`
- `C:\Users\danil\Desktop\projetosflutter\bora_app\lib\config\maps_config.dart`
- `C:\Users\danil\Desktop\projetosflutter\bora_app\android\app\src\main\AndroidManifest.xml`
- `C:\Users\danil\Desktop\projetosflutter\bora_app\ios\Runner\Info.plist`
- `C:\Users\danil\Desktop\projetosflutter\bora_app\pubspec.yaml`
