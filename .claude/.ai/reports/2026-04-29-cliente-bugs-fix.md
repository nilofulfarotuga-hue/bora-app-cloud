# Fix — 3 Bugs Cliente + 1 Admin

**Data:** 2026-04-29
**Modo:** Plano end-to-end aprovado pelo Danilo (autonomy multi-phase).
**Base de investigação:** `2026-04-29-cliente-bugs-investigacao.md`.

---

## Ficheiros alterados

| Ficheiro | Tipo |
|---|---|
| `lib/utils/constants.dart` | NOVO — `kGuardaLat`, `kGuardaLng`, `kGuardaCenter` |
| `lib/screens/order_tracking_screen.dart` | fallback Lisboa→Guarda |
| `lib/auth/auth_store.dart` | default driver lat/lng → Guarda |
| `lib/screens/driver_map_screen.dart` | `_defaultFallbackCenter` → Guarda |
| `lib/screens/driver_home_screen.dart` | `_initialGpsCenter` fallback → Guarda |
| `lib/screens/driver_signup_screen.dart` | upsert driver lat/lng → Guarda |
| `lib/stores/driver_store.dart` | 3 fallbacks (2× LatLng + 1× JSON) → Guarda |
| `lib/data/postal_coordinates.dart` | adicionado CP Guarda 6300 + lookup com fallback de prefixo 4 dígitos |
| `lib/stores/order_store.dart` | guard anti-subscribe sem uid + guard anti-wipe em ticks vazios |
| `lib/screens/orders_screen.dart` | removido `didChangeDependencies` redundante; `showInitialLoader` flag |
| `lib/screens/admin/admin_order_detail_screen.dart` | `address` → `dropoff_address` + `pickup_address` (SELECT + UI) |

---

## BUG 1 — Pedidos loading infinito (cliente)

### Mudanças

**`lib/stores/order_store.dart`** (`_subscribeToOrders`):
- **Guard 1 (não subscrever sem uid):** Cliente sem `uid` → `return` antes de criar a stream. `updateAuthStore` re-chama `_subscribeToOrders` quando o uid lande, portanto não há risco de ficar sem subscrição.
- **Guard 2 (anti-wipe):** Tick com `rows.isEmpty` → se já temos `_orders` cacheados, ignorar (provável reconnect transitório). Antes, qualquer empty fire pós-auth limpava `_orders` → loader infinito.

**`lib/screens/orders_screen.dart`**:
- Removido `didChangeDependencies` que disparava `loadOrders` extra a cada rebuild do Provider.
- Removidos campos `_lastLoadedPhone` / `_lastLoadedUserId` (não usados).
- `showInitialLoader = store.isLoading && orders.isEmpty` — mantém comportamento mas com nome explícito; combinado com o anti-wipe, o caso "isLoading preso true + orders vazio" desaparece.

### Build necessário?
**SIM** — Dart code change.

---

## BUG 2 — Mapa Lisboa → Guarda

### Mudanças

**`lib/utils/constants.dart`** (NOVO):
```dart
const double kGuardaLat = 40.5378;
const double kGuardaLng = -7.2683;
const LatLng kGuardaCenter = LatLng(kGuardaLat, kGuardaLng); // latlong2
```

**Substituições aplicadas (8 sítios + 1 entrada postal):**
1. `order_tracking_screen.dart:214` — fallback do `mapCenter` cliente
2. `auth_store.dart:677-678` — default lat/lng no upsert da tabela `drivers` (registo async)
3. `driver_map_screen.dart:66` — `_defaultFallbackCenter`
4. `driver_home_screen.dart:241` — `_initialGpsCenter` no `_resolveGpsFallback`
5. `driver_signup_screen.dart:225-226` — upsert driver no signup form
6. `driver_store.dart:183` — fallback em `syncDriverWithAuth`
7. `driver_store.dart:227` — fallback em `configurePrimaryDriver`
8. `driver_store.dart:285-286` — fallback no `_upsertDriverRow`
9. `postal_coordinates.dart` — adicionado `"6300"` (Guarda) + lookup tenta prefixo 4 dígitos quando match exacto falha (cobre todos os sub-CP da Guarda sem listar 200+ entradas)

### Build necessário?
**SIM** — Dart code change.

---

## BUG 3 — Admin: `orders.address does not exist`

### Mudanças

**`lib/screens/admin/admin_order_detail_screen.dart`**:
- `_refresh()` SELECT linha 54: `address` → `dropoff_address, pickup_address`
- `_SummaryTab` linha 206: `_row(Icons.location_on, 'Morada', order['address'])` → 2 linhas distintas:
  - `'Entrega'` ← `dropoff_address`
  - `'Recolha'` ← `pickup_address`
- `OrderModel` (`lib/models/order_model.dart:62, 306`) já mapeia `dropoff_address` correctamente — sem mudança necessária.

### Build necessário?
**SIM** — Dart code change. Web admin precisa de `flutter build web` + redeploy.

---

## Bugs / Anomalias FORA DO SCOPE

| # | Bug | Ficheiro | Severidade |
|---|-----|----------|-----------|
| OS-1 | `auth/auth_store.dart` `currentClient?.phone` é usado para filtrar pedidos pelo cliente — para clientes anónimos / sem phone, o filtro pode comportar-se mal | `lib/screens/orders_screen.dart:73` | BAIXA |
| OS-2 | `order_store.dart:1565,1570` — reconexão de stream com `Future.delayed(5s)` sem backoff exponencial; em rede instável pode entrar em loop | `lib/stores/order_store.dart` | MÉDIA |
| OS-3 | `loadOrders` engole erros (`debugPrint` only) — utilizador não vê falha de fetch | `lib/stores/order_store.dart:155` | MÉDIA |
| OS-4 | `register_client_screen.dart:391-393` engole silenciosamente falha de upload de avatar | `lib/screens/register_client_screen.dart` | MÉDIA |
| OS-5 | `postal_coordinates.dart` ainda tem 7 CP de Lisboa legacy — não bloqueia mas polui o helper | `lib/data/postal_coordinates.dart:10-16` | BAIXA |
| OS-6 | `address_resolver.dart:59` — comentário doc com coords de Lisboa como exemplo. Cosmético | `lib/utils/address_resolver.dart` | TRIVIAL |

---

## Validação

- `grep -E "38\.7223|-9\.13|-9\.14" lib/` confirma: zero ocorrências executáveis fora de:
  - `postal_coordinates.dart` (entradas Lisboa legacy intencionais)
  - `utils/constants.dart` (comentário a explicar a substituição)
  - `utils/address_resolver.dart` (doc comment, não executável)
- `flutter analyze` — corrido após edits.

---

## Knowledge Protocol

Não houve mudança de regra de negócio — apenas correcção de bugs. Nenhum update a `bora_app/.claude/.ai/business_rules.md` necessário.

`§19.2` (path foto cliente `avatars/{userId}.jpg`) **continua divergente** da implementação real (`avatars/{userId}/avatar.jpg`) — fica para próximo ciclo.
