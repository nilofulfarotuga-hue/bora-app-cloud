# Investigação — 3 Bugs do Cliente (Telemóvel)

**Data:** 2026-04-29
**Modo:** Investigação pura (sem código). Sem fixes, sem migrations.
**Scope:** Foto perfil 400 · Pedidos loading infinito · Mapa em Lisboa.
**Business rules consultadas:** §8.6 (Perfil Cliente), §8.5 (Histórico), §19 (Storage), §21 (RLS), §8.2 (Acompanhamento).

---

## 1. PROBLEMA 1 — Foto perfil dá erro 400

### Causa raiz
**O código Flutter está correcto.** O upload já usa `upsert: true`.

- `lib/screens/profile_screen.dart:200-209`:
  ```dart
  final path = '$userId/avatar.jpg';
  await storage.from('avatars').uploadBinary(
        path,
        processed,
        fileOptions: const FileOptions(
          upsert: true,
          contentType: 'image/jpeg',
        ),
      );
  ```
- `lib/screens/register_client_screen.dart:372-379` — idêntico, também com `upsert: true`.

A premissa do enunciado ("Flutter faz sempre POST mesmo quando ficheiro existe") está parcialmente correcta — o SDK Supabase **sempre** envia `POST /object/avatars/{uid}/avatar.jpg`, mas com `upsert: true` adiciona o header `x-upsert: true` que faz o servidor tratar como UPSERT.

**Causa real do 400:** RLS policy do bucket `avatars` em `storage.objects` autoriza INSERT mas **não autoriza UPDATE** para o próprio dono. Resultado: primeiro upload ok (INSERT), segundo upload falha (UPDATE bloqueado pelo RLS).

Evidência colateral: a migração `supabase/migrations/20260419120000_fix_backend_bugs_phase1.sql:13` tem comentário explícito:
> "BUG #2 (avatars 403): backend RLS is correct; root cause is client-side"

Esse comentário foi escrito quando o erro era 403 e o cliente não enviava `upsert: true`. **Já não se aplica** — agora o cliente envia `upsert`, mas o RLS continua sem policy de UPDATE → 400.

**Nota business rule §19.2:** o doc diz path = `avatars/{userId}.jpg`. O código usa `avatars/{userId}/avatar.jpg` (subfolder por user). Esta divergência **não causa o 400** mas deve ser harmonizada (preferir subfolder, mais alinhado com convenção `auth.uid()::text = (storage.foldername(name))[1]` típica do Supabase).

### Plano de fix
1. Verificar policies actuais em `storage.objects` para bucket `avatars` (consulta SQL diagnóstica).
2. Garantir que existem 4 policies (SELECT/INSERT/UPDATE/DELETE) com `bucket_id='avatars' AND auth.uid()::text = (storage.foldername(name))[1]`.
3. A em falta deverá ser **UPDATE** — adicionar via migration nova.
4. Actualizar §19.2 do business_rules.md para reflectir o path real `avatars/{userId}/avatar.jpg`.

### Build necessário?
**NÃO.** Fix é só backend (migration SQL). App Flutter já está OK no APK actual.

---

## 2. PROBLEMA 2 — Pedidos loading infinito após sair e voltar

### Causa raiz
Duas causas combinadas em `lib/stores/order_store.dart`:

**A) Stream geral subscrita sem filtro de `user_id` no boot** — `_subscribeToOrders()` em `order_store.dart:1532-1572`:
```dart
_ordersSubscription = (isClient && uid != null
        ? supabase.from('orders').stream(primaryKey: ['id']).eq('user_id', uid)
        : supabase.from('orders').stream(primaryKey: ['id']))
```
Quando `_bootstrap()` corre antes da auth estar pronta, `uid == null` → cai no ramo **sem filtro**. RLS então devolve `rows.isEmpty`. O guard só protege se `auth.currentUser == null`:
```dart
if (rows.isEmpty && supabase.auth.currentUser == null) return;
_orders.clear();
```
Quando o utilizador autentica entretanto, qualquer tick subsequente com 0 rows (RLS) **limpa `_orders`**.

**B) `OrdersScreen` (`lib/screens/orders_screen.dart:33-58`) chama `loadOrders()` em três sítios:**
- `initState` (post-frame callback) — linha 41
- `onAuthStateChange` listener — linha 37
- `didChangeDependencies` quando phone/userId muda — linha 56

Combinado com `IndexedStack` em `client_main_screen.dart` (mantém os 3 tabs vivos), ao voltar ao tab Pedidos, `didChangeDependencies` pode disparar e chamar `loadOrders()` mesmo quando `_orders` foi entretanto limpo pela stream. `loadOrders` põe `_isLoading=true` (linha 132), e o body do `OrdersScreen:89` faz:
```dart
body: (store.isLoading && orders.isEmpty) ? CircularProgressIndicator(...) : ...
```
→ se a query backend tem latência ou bloqueia (timeout 8s, linha 145), o utilizador vê **loading infinito** durante todo esse intervalo.

**Bónus que agrava:** `loadOrders` tem `if (_authStore == null) return;` ANTES de inicializar `_isLoading` — OK. Mas **não há cancelamento** se uma chamada nova começar enquanto outra está em curso → race condition entre múltiplas reentradas.

### Plano de fix
1. **Stream:** quando `uid == null`, **não subscrever** (ou subscrever mas marcar como "draft" e re-subscrever assim que auth lande). O `updateAuthStore` em `order_store.dart:266` já chama `_subscribeToOrders()` — basta evitar a subscrição inicial sem filtro.
2. **Guard mais forte:** `if (rows.isEmpty && _orders.isNotEmpty && uidFilterDisabled) return;` para nunca limpar lista em ticks com filtro ausente.
3. **OrdersScreen:** simplificar — chamar `loadOrders()` apenas em `initState`. Remover chamada em `didChangeDependencies` (já há stream realtime) ou debounce.
4. **Timeout UX:** mostrar erro/retry quando `loadOrders` falha o timeout em vez de `isLoading=true` indefinido + lista vazia.

### Build necessário?
**SIM.** Mudanças em código Dart (`order_store.dart` + `orders_screen.dart`) → recompilar APK.

---

## 3. PROBLEMA 3 — Mapa centra em Lisboa em vez de Guarda

### Causa raiz
`lib/screens/order_tracking_screen.dart` ~linha 175 (cálculo de `mapCenter` antes do `GoogleMap`):
```dart
final mapCenter = driverPosition ??
    order.destination ??
    order.pickupLocation ??
    const ll.LatLng(38.7223, -9.1393);  // ← LISBOA hardcoded
```
Cascata: driver → destino → pickup → **fallback Lisboa**.

O fallback dispara quando os 3 anteriores são null. Em pedidos novos antes do estafeta aceitar:
- `driverPosition` é null (sem estafeta atribuído ainda)
- `order.destination` deve vir do checkout (se estiver null = bug upstream no fluxo de checkout)
- `order.pickupLocation` deve vir do restaurante/loja (se null = restaurante/loja sem `lat/lng` no perfil)

Resultado prático: utilizador faz pedido, vai para tracking screen, estafeta ainda não aceitou → cai no fallback → **Lisboa**.

### Plano de fix
1. **Imediato (1 linha):** trocar fallback `LatLng(38.7223, -9.1393)` por **Guarda `LatLng(40.5378, -7.2683)`** em `order_tracking_screen.dart`. Constante centralizada (ex.: `BusinessRules.cityCenter` ou `AppConstants.guardaCenter`).
2. **Estrutural:** garantir que `order.destination` e `order.pickupLocation` **nunca** vêm null do checkout — adicionar validação no `OrderStore.createOrder`.
3. **Limpeza geral (out-of-scope mas relacionado):** ver bugs fora-de-scope abaixo.

### Build necessário?
**SIM.** Mudança em Dart → recompilar APK.

---

## 4. Bugs / Anomalias FORA DO SCOPE

| # | Bug | Ficheiro | Severidade |
|---|-----|----------|-----------|
| OS-1 | Driver app fallback de localização também é Lisboa (`LatLng(38.7223, -9.1393)`) — estafetas em Guarda vêem Lisboa quando GPS falha | `lib/screens/driver_map_screen.dart:66`, `lib/screens/driver_home_screen.dart:241` | ALTA |
| OS-2 | `auth_store.dart:677-678` grava `lat: 38.7223, lng: -9.1393` como localização default do utilizador. Todos os clientes novos nascem "em Lisboa" se a permissão de GPS não for concedida | `lib/auth/auth_store.dart:677` | ALTA |
| OS-3 | `data/postal_coordinates.dart` contém **apenas códigos postais de Lisboa** (1050-, 1100-, 1200-, 1900-, 2720-, 2800-). Nenhum 6300- (Guarda). Cliente que use código postal para localização nunca terá match | `lib/data/postal_coordinates.dart:7-13` | ALTA |
| OS-4 | `OrderStore.loadOrders` engole erros (`debugPrint` sem propagar) — utilizador nunca sabe que falhou | `lib/stores/order_store.dart:155` | MÉDIA |
| OS-5 | Stream `_subscribeToOrders` faz `Future.delayed(5s)` para reconectar após erro/done — sem backoff exponencial, pode entrar em loop em caso de falha persistente | `lib/stores/order_store.dart:1565-1572` | BAIXA |
| OS-6 | `register_client_screen.dart:393` engole silenciosamente falha de upload de avatar (`debugPrint` apenas) — utilizador completa registo a achar que tem foto | `lib/screens/register_client_screen.dart:391-393` | MÉDIA |
| OS-7 | Comentário stale na migration `20260419120000_fix_backend_bugs_phase1.sql:13` afirma erro 403 quando agora é 400 — confunde futura debug | migration | BAIXA |

---

## 5. Recomendação — Fixar juntos ou separados?

**Fixar como 1 bundle, mas em 2 PRs/commits:**

### PR-1 (backend, sem build)
- PROBLEMA 1: migration adicionar policy UPDATE em `storage.objects` para `avatars`.
- Bónus OS-7: actualizar comentário da migration.

### PR-2 (Flutter, requer rebuild APK)
- PROBLEMA 2: corrigir `OrderStore._subscribeToOrders` (não subscrever sem uid) + guard mais forte no `rows.isEmpty` + simplificar triggers de `loadOrders` no `OrdersScreen`.
- PROBLEMA 3: trocar fallback Lisboa→Guarda em `order_tracking_screen.dart`.
- Bónus OS-1, OS-2: trocar fallbacks Lisboa→Guarda no driver app e auth_store (mesma linha de mudança, custo zero).
- Bónus OS-3: criar constante `kGuardaCenter` em `lib/config/` e usar em todos os fallbacks.

**Razão para bundle:** os 3 bugs são todos de UX visíveis no telemóvel do cliente — rebentar cada um em PR isolado triplica o tempo de testing manual. Bundle único permite **1 sessão de teste end-to-end** que valida tudo.

**Razão para 2 PRs:** PR-1 é **só SQL** (deploy zero-risk via Supabase migration), pode ir já. PR-2 obriga a rebuild + redistribuição de APK.

OS-4, OS-5, OS-6 ficam para outro ciclo (não bloqueiam lançamento).

---

## 6. PARAGEM OBRIGATÓRIA

Aguardar OK do Danilo antes de qualquer fix.

Decisões pendentes:
- ✅ Confirmar bundle PR-1 + PR-2?
- ✅ Adoptar `LatLng(40.5378, -7.2683)` como `kGuardaCenter` global?
- ✅ Aplicar OS-1, OS-2 no mesmo PR-2 (custo marginal)?
