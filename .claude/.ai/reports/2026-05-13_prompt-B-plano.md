# PROMPT B — Plano Detalhado (Model + UI Cliente)

**Data:** 2026-05-13
**Modelo:** Opus 4.7
**Branch:** `autonomous-night-2026-04-29` · HEAD `0b01bd7`
**Status:** PLANO. Aguarda aprovação. Não executar.

---

## 0. Decisões consolidadas (Danilo, 2026-05-13)

| # | Decisão |
|---|---|
| D1 | Cartões condicionais individuais (1/2/3 cartões) |
| D2 | Sem reservas + sem takeaway → direto ao menu |
| D3 | Adicionar `OrderServiceType.takeaway` ao enum |
| D4 | **Eliminar `_isTakeaway`** — migrar tudo para `_serviceType == OrderServiceType.takeaway` |
| D5 | `notify-client`: DB query (não payload) — PROMPT C |
| D6 | Imutabilidade curbside: **UI-only** (TextField/Checkbox disabled após `payment_status='paid'`) |
| D7 | `takeaway_pickup_code` já é 6 chars (servidor) — `OrderModel` parseia como `String?` |
| D8 | `OrderStatus.readyForPickup` ENTRE `preparing` e `callingDriver` (index = 2) |
| D9 | Som parceiro (BUG-PT-006) — prompt separado |
| D10 | SQLs `partner_takeaway_*` em PROMPT C (último commit) |

---

## 1. Tag git de segurança (executar PRIMEIRO no início da execução)

```bash
cd bora_app
git tag -a pre-takeaway-flutter-2026-05-13 -m "Snapshot antes de PROMPT B (takeaway client flow)"
git tag --list | grep takeaway   # verificar
```

**Não fazer push da tag.** Rollback = `git reset --hard pre-takeaway-flutter-2026-05-13`.

---

## 2. Escopo — 16 ficheiros tocados, 2 novos

### Camada modelo / serviço (6 ficheiros)
1. [lib/models/order_service_type.dart](bora_app/lib/models/order_service_type.dart) — adicionar `takeaway`
2. [lib/models/order_model.dart](bora_app/lib/models/order_model.dart) — enum reorder, 6 campos novos, remover `isTakeaway`, label, switch
3. [lib/models/restaurant_model.dart](bora_app/lib/models/restaurant_model.dart) — 3 campos
4. [lib/stores/cart_store.dart](bora_app/lib/stores/cart_store.dart) — remover `_isTakeaway`, getter compatível
5. [lib/stores/restaurant_store.dart](bora_app/lib/stores/restaurant_store.dart) — parsing 3 campos + cache update
6. [lib/stores/order_store.dart](bora_app/lib/stores/order_store.dart) — eliminar param `isTakeaway` no path de criação

### Camada UI cliente (8 ficheiros)
7. [lib/screens/restaurants_screen.dart](bora_app/lib/screens/restaurants_screen.dart) — guard `showOptions`
8. [lib/screens/restaurant_options_screen.dart](bora_app/lib/screens/restaurant_options_screen.dart) — cartões condicionais + serviceType
9. [lib/screens/cart_screen.dart](bora_app/lib/screens/cart_screen.dart) — checkbox curbside + matrícula (compatível com getter)
10. [lib/screens/order_tracking_screen.dart](bora_app/lib/screens/order_tracking_screen.dart) — case `readyForPickup` + bloco takeaway UI
11. [lib/screens/order_details_screen.dart](bora_app/lib/screens/order_details_screen.dart) — 4 switches
12. [lib/screens/orders_screen.dart](bora_app/lib/screens/orders_screen.dart) — `_StatusChip._color`
13. [lib/services/order_eta_service.dart](bora_app/lib/services/order_eta_service.dart) — case `readyForPickup`
14. [lib/screens/driver_map_screen.dart](bora_app/lib/screens/driver_map_screen.dart) — case defensivo

### Componentes NOVOS (2 ficheiros)
15. `lib/widgets/takeaway/curbside_inputs.dart` (NOVO) — checkbox+textfield com guard imutabilidade
16. `lib/widgets/takeaway/pickup_code_card.dart` (NOVO) — cartão grande com código + nome restaurante + timer ready_at

---

## 3. Diffs exactos

### 3.1 `lib/models/order_service_type.dart`

```diff
 enum OrderServiceType {
   restaurant,
   storeShopping,
   carryGroceries,
   sendPackage,
+  takeaway,
 }

 extension OrderServiceTypeLabel on OrderServiceType {
   String get label {
     switch (this) {
       case OrderServiceType.restaurant:
         return "Restaurantes";
       case OrderServiceType.storeShopping:
         // ... existente
+      case OrderServiceType.takeaway:
+        return "Para levantar";
     }
   }
 }
```

**Atenção:** auditar TODOS os switches `OrderServiceType` (grep) e adicionar caso `takeaway`. Lista a confirmar no início da execução com `grep -rn 'case OrderServiceType\.' lib/`.

---

### 3.2 `lib/models/order_model.dart` — enum reorder

**Antes (linhas 11-21):**
```dart
enum OrderStatus {
  created,
  preparing,
  callingDriver,
  driverAccepted,
  pickedUp,
  onTheWay,
  delivered,
  rejected,
  cancelled,
}
```

**Depois:**
```dart
enum OrderStatus {
  created,
  preparing,
  readyForPickup, // ← novo, takeaway only
  callingDriver,
  driverAccepted,
  pickedUp,
  onTheWay,
  delivered,
  rejected,
  cancelled,
}
```

**⚠️ Impacto crítico do `.index`:**
- Antes: `callingDriver.index=2`. Depois: `callingDriver.index=3`.
- [lib/stores/restaurant_store.dart](bora_app/lib/stores/restaurant_store.dart) `_shouldKeepOrder`: `order.status.index <= OrderStatus.callingDriver.index` — usa nome simbólico → continua correcto.
- Qualquer comparação numérica hardcoded quebra. Grep audit: `grep -rn 'status\.index' lib/` antes da execução.

---

### 3.3 `lib/models/order_model.dart` — 6 campos novos + getter `isTakeaway`

**Remover (linhas 153-155):**
```dart
-  /// Whether the client chose takeaway (BR §14.9). Partner restaurants only.
-  /// When true, dispatch is bypassed — the client picks up directly.
-  bool isTakeaway;
```

**Adicionar (depois de `bool isPurchaseFinalized;` ~linha 100):**
```dart
  /// BR §14.11 — código alfanumérico 6 chars gerado pelo servidor ao criar
  /// pedido takeaway. Cliente apresenta no balcão. NULL para delivery.
  final String? takeawayPickupCode;

  /// Timestamp quando partner_takeaway_accept foi chamado, dando ETA ao cliente.
  /// = createdAt + takeawayPrepMinutes. NULL para delivery.
  final DateTime? takeawayReadyAt;

  /// Timestamp quando parceiro marcou levantado. NULL até levantamento.
  final DateTime? takeawayPickedUpAt;

  /// Minutos de preparação anunciados pelo parceiro (3/5/10/15/20/30/45/60).
  /// Default vem de restaurants.takeaway_default_prep_minutes. NULL para delivery.
  final int? takeawayPrepMinutes;

  /// True se cliente vai esperar no carro (curbside). Default false.
  final bool takeawayIsCurbside;

  /// Texto livre cliente preencheu para curbside (matrícula/cor/modelo).
  /// Imutável pós payment_status='paid' (D6, UI-only guard).
  final String? takeawayCurbsideInfo;
```

**Adicionar getter (depois de `extension OrderModelX`):**
```dart
  /// Compatibilidade com call sites antigos (cart_screen, order_store).
  /// Substitui o antigo campo bool. Fonte de verdade: serviceType.
  bool get isTakeaway => serviceType == OrderServiceType.takeaway;
```

**Construtor — remover `this.isTakeaway = false,` (linha 251) e adicionar 6 novos:**
```dart
    // remover:
-    this.isTakeaway = false,
    // adicionar (antes de `Map<String, bool>? substitutionResponses,`):
+    this.takeawayPickupCode,
+    this.takeawayReadyAt,
+    this.takeawayPickedUpAt,
+    this.takeawayPrepMinutes,
+    this.takeawayIsCurbside = false,
+    this.takeawayCurbsideInfo,
```

**`fromSupabase` — remover linha 420 e adicionar 6 parses (após `tipCents:` linha 419):**
```dart
-      isTakeaway: data['is_takeaway'] as bool? ?? false,
+      takeawayPickupCode: data['takeaway_pickup_code'] as String?,
+      takeawayReadyAt: data['takeaway_ready_at'] != null
+          ? DateTime.tryParse(data['takeaway_ready_at'].toString())
+          : null,
+      takeawayPickedUpAt: data['takeaway_picked_up_at'] != null
+          ? DateTime.tryParse(data['takeaway_picked_up_at'].toString())
+          : null,
+      takeawayPrepMinutes: (data['takeaway_prep_minutes'] as num?)?.toInt(),
+      takeawayIsCurbside: data['takeaway_is_curbside'] as bool? ?? false,
+      takeawayCurbsideInfo: data['takeaway_curbside_info'] as String?,
```

**`toSupabase` — substituir linha 489:**
```dart
-      if (isTakeaway) 'is_takeaway': true,
+      // takeaway_* columns são gravadas pelo servidor via create_order RPC
+      // (Claude.ai confirmou). Cliente envia apenas service_type='takeaway'
+      // + takeaway_is_curbside + takeaway_curbside_info no payload do RPC.
+      // toSupabase é usado para UPSERT direto (legacy); para takeaway, o
+      // create_order RPC é o único caminho válido.
+      if (takeawayIsCurbside) 'takeaway_is_curbside': true,
+      if (takeawayCurbsideInfo != null && takeawayCurbsideInfo!.isNotEmpty)
+        'takeaway_curbside_info': takeawayCurbsideInfo,
```

**Atenção:** `is_takeaway` (coluna boolean) ainda existe no DB? Confirmar com Claude.ai. Se existe e é redundante com `service_type='takeaway'`, deixar de gravar (server `create_order` pode preencher ambas).

**`OrderStatusLabel` (após linha 542 `preparing:`):**
```dart
       case OrderStatus.preparing:
         return 'Restaurante preparando';
+      case OrderStatus.readyForPickup:
+        return 'Pronto para levantar';
       case OrderStatus.callingDriver:
```

---

### 3.4 `lib/models/restaurant_model.dart` — 3 campos novos

**Após linha 174 (`final bool reservationsEnabled;`):**
```dart
+  /// BR §14.9 — restaurante aceita pedidos takeaway (cliente levanta no balcão).
+  /// Default false. Partner toggles no dashboard.
+  final bool takeawayEnabled;
+
+  /// BR §14.9b — restaurante suporta curbside (cliente espera no carro).
+  /// Default false. Só efectivo se takeawayEnabled=true.
+  final bool curbsideEnabled;
+
+  /// BR §14.9c — ETA default em minutos quando parceiro aceita o pedido sem
+  /// escolher manualmente (3/5/10/15/20/30/45/60). Default 15.
+  final int takeawayDefaultPrepMinutes;
```

**Construtor — depois de `this.reservationsEnabled = false,` (linha 153):**
```dart
+    this.takeawayEnabled = false,
+    this.curbsideEnabled = false,
+    this.takeawayDefaultPrepMinutes = 15,
```

**copyWith — params (após `bool? reservationsEnabled,`) e body (após `reservationsEnabled: reservationsEnabled ?? this.reservationsEnabled,`):**
```dart
   RestaurantModel copyWith({
     bool? isOnline,
     double? lat,
     double? lng,
     bool? reservationsEnabled,
+    bool? takeawayEnabled,
+    bool? curbsideEnabled,
+    int? takeawayDefaultPrepMinutes,
     BusinessHours? businessHours,
     double? avgRating,
     int? ratingsCount,
   }) {
     return RestaurantModel(
       // ... campos existentes
       reservationsEnabled: reservationsEnabled ?? this.reservationsEnabled,
+      takeawayEnabled: takeawayEnabled ?? this.takeawayEnabled,
+      curbsideEnabled: curbsideEnabled ?? this.curbsideEnabled,
+      takeawayDefaultPrepMinutes:
+          takeawayDefaultPrepMinutes ?? this.takeawayDefaultPrepMinutes,
       businessHours: businessHours ?? this.businessHours,
       avgRating: avgRating ?? this.avgRating,
       ratingsCount: ratingsCount ?? this.ratingsCount,
     );
   }
```

---

### 3.5 `lib/stores/restaurant_store.dart` — parsing + cache update

**`_restaurantFromRecord` (após `reservationsEnabled:`, ~linha 903):**
```dart
       reservationsEnabled: data['reservations_enabled'] as bool? ?? false,
+      takeawayEnabled: data['takeaway_enabled'] as bool? ?? false,
+      curbsideEnabled: data['curbside_enabled'] as bool? ?? false,
+      takeawayDefaultPrepMinutes:
+          (data['takeaway_default_prep_minutes'] as num?)?.toInt() ?? 15,
       businessHours: BusinessHours.fromJson(data['business_hours']),
```

**`adminUpdatePartnerData` cache rebuild (~linha 807) — adicionar 3 linhas no construtor manual:**
```dart
         reservationsEnabled: old.reservationsEnabled,
+        takeawayEnabled: old.takeawayEnabled,
+        curbsideEnabled: old.curbsideEnabled,
+        takeawayDefaultPrepMinutes: old.takeawayDefaultPrepMinutes,
         businessHours: old.businessHours,
```

**Outros usages de copyWith (linhas 680, ...) NÃO precisam alteração** — herdam via `??`.

---

### 3.6 `lib/stores/cart_store.dart` — eliminar `_isTakeaway`

**Remover (linhas 223-229):**
```dart
-  // Takeaway flag for partner restaurants (BR §14.9).
-  bool _isTakeaway = false;
-  bool get isTakeaway => _isTakeaway;
-  void setTakeaway(bool v) {
-    _isTakeaway = v;
-    notifyListeners();
-  }
```

**Adicionar (mesma posição):**
```dart
+  // BR §14.9 — takeaway é determinado por _serviceType (single source of truth).
+  // O getter público mantém compatibilidade com call sites existentes
+  // (cart_screen.dart, order_store.dart) que verificam cartStore.isTakeaway.
+  bool get isTakeaway => _serviceType == OrderServiceType.takeaway;
+
+  /// Setter usado por RestaurantOptionsScreen: alterna entre takeaway e
+  /// restaurant. Cart deve estar vazio se a troca muda o contexto.
+  void setServiceTypeFromOption(OrderServiceType type) {
+    if (_serviceType == type) return;
+    _serviceType = type;
+    notifyListeners();
+  }
+
+  // Curbside (D6) — mantido localmente até checkout; gravado em
+  // toSupabase()/create_order_rpc payload.
+  bool _isCurbside = false;
+  bool get isCurbside => _isCurbside;
+  void setCurbside(bool v) {
+    _isCurbside = v;
+    notifyListeners();
+  }
+
+  String? _curbsideInfo;
+  String? get curbsideInfo => _curbsideInfo;
+  void setCurbsideInfo(String? v) {
+    _curbsideInfo = (v != null && v.trim().isEmpty) ? null : v?.trim();
+    notifyListeners();
+  }
```

**`clearCart()` (linha 415) — substituir `_isTakeaway = false;`:**
```dart
-    _isTakeaway = false;
+    // serviceType é resetado para restaurant (default) ao limpar carrinho.
+    _serviceType = OrderServiceType.restaurant;
+    _isCurbside = false;
+    _curbsideInfo = null;
```

**`createOrder()` payload (~linha 572) — remover `isTakeaway: _isTakeaway,`:**
```dart
-      isTakeaway: _isTakeaway,
+      // service_type='takeaway' já comunica a intenção; campo bool removido.
+      takeawayIsCurbside: _isCurbside,
+      takeawayCurbsideInfo: _curbsideInfo,
```

**Linha 580 (provavelmente reset noutro caminho):**
```dart
-    _isTakeaway = false;
+    _serviceType = OrderServiceType.restaurant;
+    _isCurbside = false;
+    _curbsideInfo = null;
```

**`isShoppingOrder` checks (linhas 437, 500) — auditar:**
- Takeaway TEM items (cliente escolhe pratos), tal como `restaurant`/`storeShopping`.
- Mudar para incluir takeaway:
```dart
-    final isShoppingOrder = _serviceType == OrderServiceType.restaurant ||
-        _serviceType == OrderServiceType.storeShopping;
+    final isShoppingOrder = _serviceType == OrderServiceType.restaurant ||
+        _serviceType == OrderServiceType.storeShopping ||
+        _serviceType == OrderServiceType.takeaway;
```

**Pricing call (`pricingBreakdown`, ~linha 130) — auditar se `PricingService.calculateBreakdown` trata `OrderServiceType.takeaway`:**
- Se NÃO trata: adicionar branch local que zera deliveryFee/serviceFee/bagFee quando takeaway.
- Se trata: confirmar via [pricing_service.dart](bora_app/lib/services/pricing_service.dart).
- **Acção:** ler `PricingService` no início da execução; se não suporta takeaway, adicionar caso.

---

### 3.7 `lib/stores/order_store.dart`

**Linha 849 (criação local de OrderModel) — remover `isTakeaway:`:**
```dart
-        isTakeaway: isTakeaway,
+        // takeaway agora é derivado de serviceType (getter); não é necessário
+        // passar param. Caller que precisa de "marcar como takeaway" deve
+        // passar serviceType: OrderServiceType.takeaway.
```

**Linha 1812 (`if (order.isTakeaway)`):** funciona sem alterações (getter delega para serviceType).

**Adicionar guarda em `_advanceStatus`** (defensivo):
```dart
+    // Takeaway: cliente Flutter NÃO avança status. Server-side RPCs
+    // (partner_takeaway_*) são authoritative. Esta guarda evita que
+    // qualquer caller chame _advanceStatus em pedidos takeaway.
+    if (order.serviceType == OrderServiceType.takeaway &&
+        next != OrderStatus.cancelled &&
+        next != OrderStatus.rejected) {
+      debugPrint('OrderStore: _advanceStatus blocked for takeaway order ${order.id}');
+      return;
+    }
```
*Posicionar no topo do método, depois das null checks.*

---

### 3.8 `lib/screens/restaurants_screen.dart` — guard `showOptions`

**Linha 154:**
```dart
-    final showOptions = business.isPartner && business.reservationsEnabled;
+    // D1+D2: mostrar ecrã de opções se houver PELO MENOS uma opção além
+    // do menu directo. Sem reservas e sem takeaway → menu directo.
+    final showOptions = business.isPartner &&
+        (business.reservationsEnabled || business.takeawayEnabled);
```

---

### 3.9 `lib/screens/restaurant_options_screen.dart` — cartões condicionais

**Substituir `_openMenu(BuildContext, {required bool takeaway})` por:**
```dart
   void _openMenu(BuildContext context, OrderServiceType type) {
-    context.read<CartStore>().setTakeaway(takeaway);
+    context.read<CartStore>().setServiceTypeFromOption(type);
     Navigator.push(
       context,
       MaterialPageRoute(
         builder: (_) => RestaurantMenuScreen(
           restaurant: restaurant,
           restaurantId: restaurantId,
         ),
       ),
     );
   }
```

**Build method — substituir os 3 cartões fixos por condicionais:**
```dart
           const SizedBox(height: Spacing.lg),
+          // D1: cartão "Entrega" só se entrega for válida (sempre, hoje).
           BoraTileCard(
             label: 'Entrega',
             gradient: AppColors.tileRestaurants,
             iconData: Icons.delivery_dining,
-            onTap: () => _openMenu(context, takeaway: false),
+            onTap: () => _openMenu(context, OrderServiceType.restaurant),
           ),
-          const SizedBox(height: Spacing.md),
-          BoraTileCard(
-            label: 'Ir buscar',
-            gradient: AppColors.tileCarryGroceries,
-            iconData: Icons.shopping_bag_outlined,
-            onTap: () => _openMenu(context, takeaway: true),
-          ),
-          const SizedBox(height: Spacing.md),
-          BoraTileCard(
-            label: 'Reservar mesa',
-            gradient: AppColors.tileReserveTable,
-            iconData: Icons.event_seat_outlined,
-            onTap: () => _openReservation(context),
-          ),
+          if (business.takeawayEnabled) ...[
+            const SizedBox(height: Spacing.md),
+            BoraTileCard(
+              label: 'Ir buscar',
+              gradient: AppColors.tileCarryGroceries,
+              iconData: Icons.shopping_bag_outlined,
+              onTap: () => _openMenu(context, OrderServiceType.takeaway),
+            ),
+          ],
+          if (business.reservationsEnabled) ...[
+            const SizedBox(height: Spacing.md),
+            BoraTileCard(
+              label: 'Reservar mesa',
+              gradient: AppColors.tileReserveTable,
+              iconData: Icons.event_seat_outlined,
+              onTap: () => _openReservation(context),
+            ),
+          ],
```

---

### 3.10 Switches `OrderStatus.readyForPickup` (4 ficheiros)

**`lib/screens/orders_screen.dart` `_StatusChip._color()` (após `delivered`):**
```dart
       case OrderStatus.delivered:
         return AppColors.success;
+      case OrderStatus.readyForPickup:
+        return AppColors.success; // takeaway pronto = positivo
```

**`lib/screens/order_details_screen.dart` (4 switches):**
- `_isCancelable` (~linha 126): `case readyForPickup: return false;`
- `_refundableEur` (~linha 274): cobrir via `default: return 0;` que já existe ✓ (auditar)
- `_statusColor` (~linha 338): `case readyForPickup: return AppTheme.primary;`
- `_statusIcon` (~linha 357): `case readyForPickup: return Icons.storefront_outlined;`

**`lib/screens/order_tracking_screen.dart`:**
- `_statusColor` (linha 883): tem default → já cobre, mas explicitar para clareza:
  `case readyForPickup: return AppColors.success;` (antes do `default`).
- `_feeLabelForStatus` (linha 898): exhaustive sem default → `case readyForPickup: return '—';`
- Switch ~linha 1177: tem default → já cobre. Adicionar string explícita para takeaway flow:
  `case readyForPickup: return 'Pronto para levantar — código ${order.takeawayPickupCode ?? "—"}';`

**`lib/services/order_eta_service.dart` (~linha 25):**
```dart
       case OrderStatus.delivered:
       case OrderStatus.rejected:
       case OrderStatus.cancelled:
+      case OrderStatus.readyForPickup:
+        // Takeaway: ETA de entrega = null (cliente levanta). ETA de
+        // preparação (ready_at) é calculada separadamente em UI.
         return null;
```

**`lib/screens/driver_map_screen.dart` `_StatusBadge._color` (~linha 1779):**
```dart
       case OrderStatus.delivered:
         return Colors.green;
+      case OrderStatus.readyForPickup:
+        // Defensivo: driver não deve receber takeaway, mas evita crash
+        // se realtime entregar order de outro tipo por engano.
+        return Colors.grey;
       case OrderStatus.rejected:
       case OrderStatus.cancelled:
         return Colors.red;
```

---

### 3.11 `lib/screens/cart_screen.dart` — UI curbside

**Adicionar (após o widget "Entrega (takeaway)" ~linha 322):**
```dart
+          if (cartStore.isTakeaway &&
+              (restaurantStore.currentRestaurant?.curbsideEnabled ?? false))
+            CurbsideInputs(
+              isCurbside: cartStore.isCurbside,
+              curbsideInfo: cartStore.curbsideInfo,
+              isLocked: false, // sempre editável pre-paid (cart_screen é pre-checkout)
+              onCurbsideChanged: cartStore.setCurbside,
+              onInfoChanged: cartStore.setCurbsideInfo,
+            ),
```

**Linhas 30, 289, 306, 322, 323:** funcionam sem alteração (getter compatível).

---

### 3.12 NOVO — `lib/widgets/takeaway/curbside_inputs.dart`

```dart
import 'package:flutter/material.dart';
import '../../config/app_colors.dart';
import '../../config/app_spacing.dart';

/// D6 — Inputs curbside (cliente espera no carro).
/// Mostra checkbox "Vou esperar no carro" + textfield para matrícula/cor.
/// Quando [isLocked]=true (após payment_status='paid'), ambos ficam disabled.
class CurbsideInputs extends StatelessWidget {
  const CurbsideInputs({
    super.key,
    required this.isCurbside,
    required this.curbsideInfo,
    required this.isLocked,
    required this.onCurbsideChanged,
    required this.onInfoChanged,
  });

  final bool isCurbside;
  final String? curbsideInfo;
  final bool isLocked;
  final ValueChanged<bool> onCurbsideChanged;
  final ValueChanged<String?> onInfoChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        CheckboxListTile(
          value: isCurbside,
          onChanged: isLocked ? null : (v) => onCurbsideChanged(v ?? false),
          title: const Text('Vou esperar no carro'),
          subtitle: const Text('O parceiro leva o pedido até à viatura'),
        ),
        if (isCurbside) ...[
          const SizedBox(height: Spacing.sm),
          TextField(
            enabled: !isLocked,
            controller: TextEditingController(text: curbsideInfo ?? '')
              ..selection = TextSelection.collapsed(
                  offset: (curbsideInfo ?? '').length),
            onChanged: onInfoChanged,
            decoration: InputDecoration(
              labelText: 'Matrícula + cor (ex: AA-12-BB cinza)',
              border: const OutlineInputBorder(),
              helperText: isLocked
                  ? 'Não editável após pagamento confirmado'
                  : null,
            ),
          ),
        ],
      ],
    );
  }
}
```

---

### 3.13 NOVO — `lib/widgets/takeaway/pickup_code_card.dart`

```dart
import 'package:flutter/material.dart';
import '../../config/app_colors.dart';
import '../../config/app_spacing.dart';
import '../../models/order_model.dart';

/// Cartão grande mostrado em order_tracking_screen quando status=readyForPickup.
/// Mostra: vendor name, código 6 chars (zoom), info curbside se aplicável,
/// ready_at timestamp.
class PickupCodeCard extends StatelessWidget {
  const PickupCodeCard({super.key, required this.order});

  final OrderModel order;

  @override
  Widget build(BuildContext context) {
    final code = order.takeawayPickupCode ?? '—';
    return Card(
      color: AppColors.success.withValues(alpha: 0.08),
      child: Padding(
        padding: const EdgeInsets.all(Spacing.lg),
        child: Column(
          children: [
            Text('Pronto para levantar',
                style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: Spacing.sm),
            if (order.vendorName != null)
              Text(order.vendorName!,
                  style: Theme.of(context).textTheme.bodyLarge),
            const SizedBox(height: Spacing.md),
            Container(
              padding: const EdgeInsets.symmetric(
                  horizontal: Spacing.xl, vertical: Spacing.md),
              decoration: BoxDecoration(
                color: AppColors.success,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                code,
                style: const TextStyle(
                  fontSize: 36,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                  letterSpacing: 6,
                ),
              ),
            ),
            const SizedBox(height: Spacing.md),
            if (order.takeawayIsCurbside)
              Text(
                'Curbside · ${order.takeawayCurbsideInfo ?? "—"}',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
          ],
        ),
      ),
    );
  }
}
```

---

## 4. Mock visual — Ecrã de Checkout (cart_screen.dart com takeaway+curbside)

```
┌──────────────────────────────────────┐
│  ←  Carrinho                          │
├──────────────────────────────────────┤
│                                       │
│  📍 Pizza Danilo                      │
│  Rua das Codornizes, 12 · Guarda      │
│                                       │
│  🍕 Margherita      €8,50    x1       │
│  🥗 Salada César    €5,00    x1       │
│                                       │
├──────────────────────────────────────┤
│  Modo de entrega                      │
│  ─────────────────                    │
│  ⚪ Entrega   ⚫ Ir buscar (takeaway) │
│                                       │
│  ☑ Vou esperar no carro               │
│  ┌──────────────────────────────────┐ │
│  │ AA-12-BB cinza                   │ │
│  └──────────────────────────────────┘ │
│                                       │
├──────────────────────────────────────┤
│  Subtotal              €13,50         │
│  Entrega (takeaway)    €0,00          │
│  Taxa serviço          €0,00          │
│  ─────────────                        │
│  Total                 €13,50         │
│                                       │
│  [        Pagar com cartão       ]    │
└──────────────────────────────────────┘
```

**Notas:**
- Switch "Entrega ⇄ Ir buscar" só visível se `restaurant.takeawayEnabled` (sobreposição com selecção em `restaurant_options_screen` — confirmar UX: redundante ou desejável override?).
- Checkbox curbside só visível se `serviceType=takeaway && restaurant.curbsideEnabled`.
- Após paid, ambos ficam disabled (`isLocked: order.paymentStatus == PaymentStatus.paid`).
- Fees zeram visualmente (PricingService precisa cooperar — verificar).

---

## 5. Mock visual — Ecrã de Tracking (order_tracking_screen.dart pós-paid takeaway)

### Estado: `status=preparing` (parceiro aceitou com ETA 15 min)
```
┌──────────────────────────────────────┐
│  ←  Acompanhar pedido      #A1B2C3    │
├──────────────────────────────────────┤
│                                       │
│  ⚪ ⚫ ⚪ ⚪    (progresso 2/4)        │
│  Criado · Preparar · Pronto · Levantado│
│                                       │
│  👨‍🍳 Pizza Danilo a preparar          │
│  Pronto às 19:35 (em ~12 min)         │
│                                       │
│  ┌──────────────────────────────────┐ │
│  │ Pizza Margherita    €8,50    x1 │ │
│  │ Salada César        €5,00    x1 │ │
│  └──────────────────────────────────┘ │
│                                       │
│  Curbside: AA-12-BB cinza             │
│  [Cancelar pedido (€1,00)]            │
└──────────────────────────────────────┘
```

### Estado: `status=readyForPickup`
```
┌──────────────────────────────────────┐
│  ←  Acompanhar pedido      #A1B2C3    │
├──────────────────────────────────────┤
│  ⚪ ⚪ ⚫ ⚪    (progresso 3/4)        │
│  Criado · Preparar · Pronto · Levantado│
│                                       │
│  ┌──────────────────────────────────┐ │
│  │   🎉 Pronto para levantar        │ │
│  │      Pizza Danilo                 │ │
│  │                                   │ │
│  │     ╔════════════╗                │ │
│  │     ║  A B 4 7 K M  ║              │ │
│  │     ╚════════════╝                │ │
│  │                                   │ │
│  │  Curbside · AA-12-BB cinza        │ │
│  └──────────────────────────────────┘ │
│                                       │
│  Apresente o código no balcão        │
│  ou aguarde no carro.                │
└──────────────────────────────────────┘
```

### Estado: `status=delivered` (parceiro marcou levantado)
```
┌──────────────────────────────────────┐
│  ←  Pedido entregue         #A1B2C3   │
├──────────────────────────────────────┤
│  ⚪ ⚪ ⚪ ⚫    (progresso 4/4)        │
│  Criado · Preparar · Pronto · Levantado│
│                                       │
│  ✅ Pedido levantado às 19:42         │
│                                       │
│  Como foi a sua experiência?          │
│  ⭐ ⭐ ⭐ ⭐ ⭐                       │
│  ┌──────────────────────────────────┐ │
│  │ Deixe um comentário (opcional)... │ │
│  └──────────────────────────────────┘ │
│                                       │
│  [        Enviar avaliação        ]   │
└──────────────────────────────────────┘
```

---

## 6. Sequência de execução (após Danilo aprovar)

1. Tag git `pre-takeaway-flutter-2026-05-13` (rollback safety)
2. Auditoria pré-edit: `grep -rn 'status\.index'`, `grep -rn 'case OrderServiceType\.'`, leitura de [pricing_service.dart](bora_app/lib/services/pricing_service.dart) para confirmar suporte takeaway
3. Camada Modelo (4 ficheiros): `order_service_type.dart`, `order_model.dart`, `restaurant_model.dart`, `restaurant_store.dart`
4. Camada Store (2 ficheiros): `cart_store.dart`, `order_store.dart`
5. Componentes novos (2 ficheiros)
6. Camada UI (8 ficheiros)
7. `flutter analyze` ⇒ esperado 0 erros
8. Verificação manual visual em `flutter run`:
   - (a) Restaurante com `takeawayEnabled=true` → ecrã opções mostra 2 cartões
   - (b) Cliente abre menu via "Ir buscar" → cart mostra "(takeaway)" e fees zerados
   - (c) Curbside checkbox aparece se `curbsideEnabled=true`
   - (d) Após pagar (mock), curbside fica disabled
   - (e) Order com `status=readyForPickup` mock → tracking mostra `PickupCodeCard`
9. Commit único: `feat(takeaway): client flow + model + readyForPickup status (PROMPT B)`

**Não executar:**
- ❌ Nenhuma alteração em SQL/migrations
- ❌ Nenhum deploy de Edge Function (PROMPT C)
- ❌ Nenhuma alteração no painel parceiro (PROMPT C)
- ❌ Nenhuma alteração em `notify-client` (PROMPT C)
- ❌ Sem push de tag ou de branch

---

## 7. Riscos identificados

| # | Risco | Mitigação |
|---|---|---|
| R1 | Reordenação do enum quebra qualquer comparação `.index` numérica hardcoded | Audit grep `status\.index` antes de iniciar edição |
| R2 | `PricingService` não trata `OrderServiceType.takeaway` | Auditar [pricing_service.dart](bora_app/lib/services/pricing_service.dart) primeiro; se falhar, adicionar caso local em cart_store |
| R3 | Switch `OrderServiceTypeLabel` exhaustive sem default — quebra build se esquecer | Adicionar `case takeaway` em TODOS os `case OrderServiceType.` |
| R4 | `_advanceStatus` em `order_store.dart` pode aceitar transições inválidas para takeaway | Adicionar guarda explícita (secção 3.7) |
| R5 | `cart_screen.dart` switch "Ir buscar" pode override a escolha do options_screen criando UX ambígua | Decidir: ocultar switch quando viemos de options_screen; OU manter para override (Q14 anterior — confirmar) |
| R6 | `OrderModel.toSupabase` ainda envia `is_takeaway: true` — coluna talvez deprecated mas existe | Manter ENQUANTO confirmar com Claude.ai. Não-bloqueante (server ignora) |
| R7 | `notify-client` chamado pelo Flutter ([NotificationService](bora_app/lib/services/notification_service.dart)) sem `serviceType` — mensagem errada para takeaway até PROMPT C | Aceitável temporariamente (Danilo aprovou D5 — Edge Fn faz DB query no PROMPT C); push pode ter texto genérico no intervalo |
| R8 | `DispatchEngine` itera orders em `_orders` e tenta criar offer para takeaway | Já mitigado: takeaway nunca passa por `callingDriver` (server-side); guarda R4 reforça |
| R9 | Componentes `CurbsideInputs` e `PickupCodeCard` precisam `app_colors` e `app_spacing` exports | Verificar imports antes da execução |
| R10 | Realtime substitui order — getter `isTakeaway` em order continua a funcionar bem (não depende de campo gravado) | OK por desenho |

---

## 8. Critério de feito

- [ ] Tag `pre-takeaway-flutter-2026-05-13` criada localmente
- [ ] 14 ficheiros alterados + 2 ficheiros novos
- [ ] `flutter analyze` → 0 erros
- [ ] `git diff --stat` revisto — sem alterações em `supabase/`, `backend/`, `scripts/`
- [ ] Verificação visual dos 3 estados de tracking (preparing/readyForPickup/delivered) e cart com curbside
- [ ] Commit único pronto para push manual pelo Danilo
- [ ] Relatório de execução em `.claude/.ai/reports/2026-05-13_prompt-B-execucao.md`

---

## 9. Após PROMPT B

Próximo prompt esperado (PROMPT C — Parceiro + Notifications + Migrations) NÃO inicia automaticamente. Aguarda decisão do Danilo após:
- Testar manualmente o fluxo cliente
- Validar pricing engine com Claude.ai
- Confirmar coluna `is_takeaway` redundante (R6)

---

⚠️ **VALIDAÇÃO RECOMENDADA** — Envia esta resposta ao Claude.ai para validação antes de aprovar a execução.

(Estimativa: 2-3h de edição + verificação. Toca pricing display mas NÃO o cálculo financeiro server-side. Sem alterações em DB/Edge Functions.)

**FIM DO PLANO. Aguarda aprovação do Danilo para iniciar execução.**
