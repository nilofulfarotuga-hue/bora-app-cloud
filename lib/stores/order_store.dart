import 'dart:async';

import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../auth/auth_store.dart';
import '../config/business_rules.dart';
import '../dispatch/dispatch_engine.dart';
import '../services/driver_location_service.dart';
import '../models/cart_item.dart';
import '../models/chat_message.dart';
import '../models/order_model.dart';
import '../models/partner_product.dart';
import '../models/rating_model.dart';
import '../models/restaurant_model.dart';
import '../services/distance_service.dart';
import '../services/maps_service.dart';
import '../services/notification_service.dart';
import '../services/offer_presentation_gate.dart';
import '../services/offline_status_queue.dart';
import '../services/payment_service.dart';
import '../services/pricing_service.dart';
import 'driver_store.dart';
import 'restaurant_store.dart';

class PartnerOrderLine {
  const PartnerOrderLine({
    required this.product,
    required this.quantity,
  }) : assert(quantity > 0);

  final PartnerProduct product;
  final int quantity;

  double get lineTotal => product.price * quantity;
}

/// Sessão 4C: validação de productId enviado para create_order RPC / Edge Fn.
/// Não usa regex de prefixo — produção tem 9+ formatos válidos
/// (pd, cnt, auc, merc, glv, cm, lidl, prod, UUIDs hex puros, sentinelas
/// `extra_<timestamp>`). Critério: não vazio + sem espaço + 3-200 chars.
bool isValidProductId(String id) {
  if (id.isEmpty) return false;
  if (id.contains(' ')) return false;
  if (id.length < 3 || id.length > 200) return false;
  return true;
}

/// Sessão 4C: bloqueia ordens órfãs de entrarem no servidor.
/// Percorre `product_lines` no payload e valida cada `product_id`.
/// Lança [FormatException] se algum productId inválido — caller apanha
/// e mostra erro UI sem chegar à RPC. Defesa em profundidade adicional
/// à mitigação SQL 4B5 (unit_price fallback server-side).
void validateOrderPayload(Map<String, dynamic> payload) {
  final lines = payload['product_lines'] as List?;
  if (lines == null || lines.isEmpty) return; // logistics: sem product_lines.
  for (final raw in lines) {
    final line = raw as Map<String, dynamic>;
    final pid = (line['product_id'] ?? '').toString();
    if (!isValidProductId(pid)) {
      final itemName = line['name']?.toString() ?? '<sem nome>';
      debugPrint(
          '[FLOW] validateOrderPayload INVALID_PRODUCT_ID pid="$pid" item="$itemName"');
      throw FormatException(
          'Invalid productId no payload: "$pid" (item: $itemName)');
    }
  }
}

class OrderStore extends ChangeNotifier {
  final supabase = Supabase.instance.client;

  StreamSubscription<List<Map<String, dynamic>>>? _ordersSubscription;

  // Driver-specific filtered streams (started only after real driverId is known).
  // Two streams are needed because a driver needs to see:
  //   - Pending offers   : current_driver_offer_id = driverId
  //   - Active deliveries: assigned_driver_id       = driverId
  StreamSubscription<List<Map<String, dynamic>>>? _driverOffersSubscription;
  StreamSubscription<List<Map<String, dynamic>>>? _driverActiveSubscription;
  // Explicit UPDATE-event channel so offers are caught even when the
  // .stream().eq() filter misses the NULL → driverId transition.
  RealtimeChannel? _driverOfferNotifyChannel;
  // Same pattern for active deliveries — catches assigned_driver_id NULL→driverId.
  RealtimeChannel? _driverActiveNotifyChannel;
  // Fallback UPDATE channel for the client — catches status changes that the
  // .stream().eq('user_id') subscription may miss during reconnects.
  RealtimeChannel? _clientOrdersChannel;

  // Tracks which order IDs each driver stream last delivered so we can
  // remove stale rows when the stream re-emits a shorter list.
  final Set<String> _driverOfferIds = {};
  final Set<String> _driverActiveIds = {};

  // OrderStore's own record of the last driverId it acted on.
  // MUST be independent of _driverStore.currentDriverId because
  // ChangeNotifierProxyProvider passes the same Dart object reference on
  // every update call — by the time updateDriverStore() runs, the object's
  // field is already mutated, so reading _driverStore.currentDriverId for
  // both "before" and "after" always yields the same value.
  String _cachedDriverId = '';

  // Cached isOnline value so updateDriverStore() can detect when the driver
  // goes online/offline and re-notify listeners — causing _onOrderStoreChanged
  // to fire and availableOrders to be re-evaluated. Without this, toggling
  // online/offline would NOT trigger the offer dialog because updateDriverStore
  // returns early (same UID) without calling notifyListeners().
  bool _cachedIsOnline = false;
  bool _driverReconnectScheduled = false;

  static const Map<OrderStatus, Set<OrderStatus>> _statusFlow = {
    OrderStatus.created: {
      OrderStatus.preparing,
      OrderStatus.rejected,
      OrderStatus.cancelled,
    },
    OrderStatus.preparing: {
      OrderStatus.callingDriver,
      OrderStatus.cancelled,
    },
    OrderStatus.callingDriver: {
      OrderStatus.driverAccepted,
      OrderStatus.cancelled,
    },
    OrderStatus.driverAccepted: {
      OrderStatus.pickedUp,
      OrderStatus.cancelled,
    },
    OrderStatus.pickedUp: {
      OrderStatus.onTheWay,
      OrderStatus.cancelled,
    },
    OrderStatus.onTheWay: {
      OrderStatus.delivered,
      OrderStatus.cancelled,
    },
    OrderStatus.delivered: <OrderStatus>{},
    OrderStatus.rejected: <OrderStatus>{},
    OrderStatus.cancelled: <OrderStatus>{},
  };

  String? _lastUpdateError;
  String? get lastUpdateError => _lastUpdateError;

  bool _isLoading = false;
  bool get isLoading => _isLoading;

  OrderStore({
    required DriverStore driverStore,
  }) : _driverStore = driverStore {
    _bootstrap();
  }

  void _bootstrap() {
    _subscribeToOrders();
    // BUG #2 (sessão exec post-test 2026-05-12) — defensive fix:
    // reduzir notifyListeners de 3s para 30s. Em produção apareciam
    // 3-4 GET /rest/v1/orders por segundo (centenas em 60s) — hipótese
    // é cascade de rebuilds disparados por este timer. Timer só existe
    // como fallback se Realtime stream stalar; 30s ainda é seguro.
    // TODO: sessão dedicada com flutter run --verbose para identificar
    // origem real do loop (pode ser realtime emit em vez do timer).
    _fallbackRefreshTimer = Timer.periodic(
      const Duration(seconds: 30),
      (_) => notifyListeners(),
    );
  }

  Future<void> loadOrders() async {
    if (_authStore == null) return;

    _isLoading = true;
    notifyListeners();
    try {
      final userId = _authStore?.userId;
      final isClient = _authStore?.currentClient != null;

      // Never fetch without an authenticated Supabase session — avoids
      // unauthenticated requests that return empty via RLS and clear the list.
      if (userId == null) return;

      final response = await (isClient
              ? supabase.from('orders').select().eq('user_id', userId)
              : supabase.from('orders').select())
          .order('created_at', ascending: false)
          .timeout(const Duration(seconds: 8));

      _orders.clear();
      for (final data in response) {
        final order = OrderModel.fromSupabase(data);
        _orders.add(order);
      }
      notifyListeners();
    } catch (e) {
      debugPrint('OrderStore: loadOrders error => $e');
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  DriverStore _driverStore;
  RestaurantStore? _restaurantStore;
  AuthStore? _authStore;
  final PaymentService _paymentService = PaymentService();
  final DriverLocationService _driverLocationService = DriverLocationService();

  // FIX 4 (2026-05-15) — orderId do pedido mais recentemente criado por
  // createOrder(). Robusto contra reordenações de _orders por realtime
  // (ao contrário de orders.first.id).
  String? _lastCreatedOrderId;
  String? get lastCreatedOrderId => _lastCreatedOrderId;

  /// B1 (2026-06-12): último erro devolvido pela RPC create_order — permite
  /// ao checkout mapear códigos conhecidos (ex. delivery_distance_exceeded)
  /// para mensagens PT-PT em vez do fallback genérico.
  String? lastCreateOrderError;

  String? _pendingClientSecret;
  String? consumePendingClientSecret() {
    final cs = _pendingClientSecret;
    _pendingClientSecret = null;
    return cs;
  }

  final List<OrderModel> _orders = [];
  final Map<String, List<ChatMessage>> _chatMessages = {};
  final List<RatingModel> _ratings = [];
  final Map<String, Timer> _partnerPreparationTimers = {};
  // Fallback periodic refresh — ensures UI stays live if stream stalls.
  Timer? _fallbackRefreshTimer;
  final Map<String, DateTime> _lastDispatchCall = {};

  // BUG 3 (2026-05-17) — Rating dialog Realtime trigger.
  // ClientHomeScreen reads `lastDeliveredAt` and fires _checkUnratedOrders
  // whenever a new order transitions to delivered, so the rating dialog
  // appears within seconds of the actual delivery — no app reopen needed.
  //
  // Detection runs inside notifyListeners() so it covers every code path
  // that mutates _orders (main client stream, fallback channel, driver
  // streams, _advanceStatus). The first notify only seeds the seen-set
  // with delivered orders that already exist on startup, so historical
  // orders never trigger the dialog.
  final Set<String> _seenDeliveredOrderIds = <String>{};
  DateTime? _lastDeliveredAt;
  bool _deliveredTrackingInitialised = false;
  DateTime? get lastDeliveredAt => _lastDeliveredAt;

  /// Order IDs locally dismissed by this driver (reject or cancel).
  final Set<String> _dismissedOrderIds = {};

  // BUG 3 (2026-05-17) — Run delivered-transition detection on every notify.
  // Seeds the seen-set on the first call (so historical delivered orders
  // are ignored); subsequent calls mark `_lastDeliveredAt` when a NEW
  // delivered orderId appears, signalling ClientHomeScreen to re-check
  // unrated orders without waiting for app resume.
  //
  // APK-FIX-DUPLICATE-DEF (2026-05-18) — merge com override anterior que
  // sincronizava partner orders ao restaurant store. Em release mode dart
  // compile aborta com duplicate_definition. Comportamento idêntico ao
  // anterior, apenas consolidado num único override.
  @override
  void notifyListeners() {
    _trackDeliveredTransitions();
    super.notifyListeners();
    _restaurantStore?.syncPartnerOrders(_orders);
  }

  void _trackDeliveredTransitions() {
    for (final o in _orders) {
      if (o.status != OrderStatus.delivered) continue;
      if (_seenDeliveredOrderIds.add(o.id) && _deliveredTrackingInitialised) {
        _lastDeliveredAt = DateTime.now();
      }
    }
    _deliveredTrackingInitialised = true;
  }

  List<OrderModel> get orders => List.unmodifiable(_orders);

  String get _currentDriverId => _driverStore.currentDriverId;

  bool get isDriverAvailable => _driverStore.currentDriver?.isOnline ?? false;

  List<OrderModel> get availableOrders {
    if (!isDriverAvailable) return const [];
    final driverId = _currentDriverId;
    if (driverId.isEmpty) return const [];
    return _orders.where((order) {
      return order.status == OrderStatus.callingDriver &&
          order.assignedDriverId == null &&
          order.currentDriverOfferId == driverId &&
          !_dismissedOrderIds.contains(order.id);
    }).toList();
  }

  List<OrderModel> get myOrders => _orders
      .where((o) =>
          o.assignedDriverId == _currentDriverId &&
          (o.status == OrderStatus.driverAccepted ||
              o.status == OrderStatus.pickedUp ||
              o.status == OrderStatus.onTheWay))
      .toList();

  List<OrderModel> get completedOrders => _orders
      .where((o) =>
          o.status == OrderStatus.delivered &&
          o.assignedDriverId == _currentDriverId)
      .toList();

  List<OrderModel> ordersForClient(String phone) {
    if (phone.isEmpty) return const [];
    return _orders.where((o) => o.clientPhone == phone).toList()
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
  }

  /// Orders for the current client, preferring phone match and falling back
  /// to the auth user_id when phone is unavailable on first render (fixes
  /// the empty Orders tab right after login).
  List<OrderModel> ordersForCurrentClient({String? phone, String? userId}) {
    final p = phone ?? '';
    if (p.isNotEmpty) {
      final byPhone = _orders.where((o) => o.clientPhone == p).toList();
      if (byPhone.isNotEmpty || userId == null) {
        byPhone.sort((a, b) => b.createdAt.compareTo(a.createdAt));
        return byPhone;
      }
    }
    if (userId == null || userId.isEmpty) return const [];
    return _orders.where((o) => o.userId == userId).toList()
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
  }

  OrderModel? get activeDriverOrder {
    for (final order in _orders) {
      if (order.assignedDriverId == _currentDriverId &&
          (order.status == OrderStatus.driverAccepted ||
              order.status == OrderStatus.pickedUp ||
              order.status == OrderStatus.onTheWay)) {
        return order;
      }
    }
    return null;
  }

  Future<void> updateAuthStore(AuthStore authStore) async {
    _authStore = authStore;
    if (_authStore != null) {
      await loadOrders();
      // Restart the general stream now that _authStore is set so the
      // user_id filter and client notify channel are applied correctly.
      // Skip if driver-specific streams are already active.
      if (_driverOffersSubscription == null &&
          _driverActiveSubscription == null) {
        _ordersSubscription?.cancel();
        _clientOrdersChannel?.unsubscribe();
        _ordersSubscription = null;
        _clientOrdersChannel = null;
        _subscribeToOrders();
      }
    }
  }

  void updateDriverStore(DriverStore driverStore) {
    _driverStore = driverStore;
    final newId = _driverStore.currentDriverId;
    final newIsOnline = _driverStore.currentDriver?.isOnline ?? false;

    // Compare against _cachedDriverId — NOT against _driverStore.currentDriverId
    // read a second time. ChangeNotifierProxyProvider passes the same Dart object
    // on every rebuild, so by the time this method is called the object's field is
    // already mutated. Reading the field before and after the assignment always
    // yields the same value, making the guard "previousId == newId" always true
    // and the driver streams never started.
    if (newId == _cachedDriverId) {
      // UID unchanged — only notify when isOnline changed.
      // This covers the case where the driver toggles online/offline: without
      // this notification, availableOrders (which checks isDriverAvailable) would
      // never be re-evaluated by _onOrderStoreChanged, so an order already in
      // _orders would not trigger the offer dialog until the next OrderStore event.
      // Location-only updates (isOnline unchanged) are intentionally skipped to
      // avoid flooding the UI with unnecessary rebuilds.
      if (newIsOnline != _cachedIsOnline) {
        _cachedIsOnline = newIsOnline;
        debugPrint(
            '[OrderStore] isOnline changed → $newIsOnline — notifying listeners');
        notifyListeners();
      }
      return;
    }

    debugPrint('[OrderStore] driverId changed: $_cachedDriverId → $newId');
    _cachedDriverId = newId;
    _cachedIsOnline = newIsOnline;

    final isRealDriver = newId.isNotEmpty && newId != 'driver-main';
    if (isRealDriver) {
      // Real identity confirmed — start the two driver-specific filtered
      // streams. This also cancels the general stream so only this driver's
      // rows are delivered, preventing RLS gaps and broadcast leakage.
      _subscribeToDriverStreams(newId);
    } else {
      // Logout / guest / client session — the driver-specific streams (if
      // any) must be cancelled so they stop emitting rows filtered by a
      // now-dead UID, and the general unfiltered stream must be re-started
      // for non-driver consumers. Without this the store enters a zombie
      // state with no active listener after a driver logs out.
      _revertToGeneralStream();
    }

    // Always notify so DriverHomeScreen._onOrderStoreChanged fires and
    // _handleNewOrders re-evaluates availableOrders with the new driverId.
    notifyListeners();
  }

  /// Cancels any active driver-specific streams and restarts the general
  /// unfiltered stream. Called when the driver identity disappears (logout,
  /// guest, client login). Idempotent — safe to call when already in the
  /// "general stream" state.
  void _revertToGeneralStream() {
    _driverOffersSubscription?.cancel();
    _driverActiveSubscription?.cancel();
    _ordersSubscription?.cancel();
    _driverOfferNotifyChannel?.unsubscribe();
    _driverActiveNotifyChannel?.unsubscribe();
    _clientOrdersChannel?.unsubscribe();
    _driverOffersSubscription = null;
    _driverActiveSubscription = null;
    _ordersSubscription = null;
    _driverOfferNotifyChannel = null;
    _driverActiveNotifyChannel = null;
    _clientOrdersChannel = null;
    _driverOfferIds.clear();
    _driverActiveIds.clear();
    _dismissedOrderIds.clear();
    _orders.clear();
    debugPrint('[OrderStore] reverting to general stream (no driver filter)');
    _subscribeToOrders();
  }

  void updateRestaurantStore(RestaurantStore store) {
    _restaurantStore = store;
    _restaurantStore?.syncPartnerOrders(_orders);
  }

  // Kept for Provider wiring compatibility — DispatchEngine is now a no-op stub.
  // ignore: avoid_unused_parameters
  void updateDispatchEngine(DispatchEngine dispatchEngine) {}

  // APK-FIX-DUPLICATE-DEF (2026-05-18) — override `notifyListeners` foi
  // consolidado em L256 (acima) com `_trackDeliveredTransitions` + sync
  // do partner restaurant store. Esta duplicação aqui causava erro fatal
  // em dart compile release (duplicate_definition).

  // BUG #5 (2026-05-13) — retornar bool para a UI poder mostrar snackbar
  // quando o toggle é rejeitado (pedidos activos genuinamente em curso).
  bool toggleDriverAvailability(bool value) {
    final success = _driverStore.toggleAvailability(_currentDriverId, value);
    if (success) {
      notifyListeners();
    }
    return success;
  }

  /// BUG 1 / Fase 2 (2026-04-30) — Card payment-first flow.
  ///
  /// Builds the `cart_input` payload (same shape as the create_order RPC)
  /// and invokes the `create-payment-intent` Edge Function in NEW mode.
  /// **Does NOT create an order** — order is created server-side by
  /// `finalize-order-from-intent` after the Stripe webhook fires
  /// `payment_intent.succeeded`.
  ///
  /// Returns `{clientSecret, paymentIntentId, draftId, amountCents}` on
  /// success, or `null` on validation/network error.
  Future<Map<String, dynamic>?> startCardPaymentDraft({
    required OrderServiceType serviceType,
    required double itemsSubtotal,
    required LatLng destination,
    List<CartItem>? items,
    LatLng? pickupLocation,
    double? distanceKm,
    bool isPartnerStore = false,
    bool apartmentDelivery = false,
    bool requiresCar = false,
    String? vendorName,
    String? pickupAddress,
    String? pickupStreet,
    String? pickupCity,
    String? pickupPostalCode,
    String? dropoffAddress,
    String? dropoffStreet,
    String? dropoffCity,
    String? dropoffPostalCode,
    String? customerNotes,
    String? clientPhone,
    String? customerName,
    int walletAppliedCents = 0,
    String? savedPmId,
  }) async {
    final liveUserId = supabase.auth.currentUser?.id;
    if (liveUserId == null ||
        (_authStore?.isGuestSession ?? true) ||
        _authStore?.currentClient == null) {
      debugPrint('[FLOW] startCardPaymentDraft BLOCKED — no authenticated client session');
      return null;
    }

    double? googleDistance;
    if (pickupLocation != null) {
      try {
        googleDistance = await MapsService.getDistanceKm(pickupLocation, destination);
      } catch (e) {
        debugPrint('startCardPaymentDraft: MapsService error => $e');
      }
    }
    final resolvedDistance = _resolveDistance(
      pickup: pickupLocation,
      destination: destination,
      providedDistance: googleDistance ?? distanceKm,
    );

    final clonedItems = items
        ?.map(
          (item) => CartItem(
            productId: item.productId,
            name: item.name,
            price: item.price,
            quantity: item.quantity,
            basePrice: item.basePrice,
            selectedOptions: item.selectedOptions,
          ),
        )
        .toList();

    if (isPartnerStore && serviceType == OrderServiceType.restaurant) {
      final restaurant = _restaurantStore?.restaurantByName(vendorName);
      if (restaurant != null && !restaurant.isOpenNow()) return null;
    }

    final cartInput = <String, dynamic>{
      'service_type': serviceType.name,
      if (vendorName != null) 'vendor_name': vendorName,
      'is_partner_store': isPartnerStore,
      'distance_km': resolvedDistance,
      'payment_method': 'card',
      'subtotal': itemsSubtotal,
      'apartment_delivery': apartmentDelivery,
      'order_type': _resolveOrderType(
        serviceType: serviceType,
        isPartnerStore: isPartnerStore,
      ).name,
      // BUG #3 (2026-05-12) — bag_count dinâmico por service_type.
      // Server (pricing_calculate) aplica:
      //   restaurant → bag_fee_restaurant_cents=30 fixo se bag_count>=1
      //   storeShopping → bag_fee_supermarket_per_bag_cents=10 × bag_count
      //   carry/sendPackage → 0
      'bag_count': _resolveBagCount(serviceType, 1),
      'requires_car': requiresCar,
      'wallet_applied_cents': walletAppliedCents,
      if (pickupLocation != null) 'pickup_lat': pickupLocation.latitude,
      if (pickupLocation != null) 'pickup_lng': pickupLocation.longitude,
      'dropoff_lat': destination.latitude,
      'dropoff_lng': destination.longitude,
      if (pickupAddress != null) 'pickup_address': pickupAddress,
      if (pickupStreet != null) 'pickup_street': pickupStreet,
      if (pickupCity != null) 'pickup_city': pickupCity,
      if (pickupPostalCode != null) 'pickup_postal_code': pickupPostalCode,
      if (dropoffAddress != null) 'dropoff_address': dropoffAddress,
      if (dropoffStreet != null) 'dropoff_street': dropoffStreet,
      if (dropoffCity != null) 'dropoff_city': dropoffCity,
      if (dropoffPostalCode != null) 'dropoff_postal_code': dropoffPostalCode,
      if (customerNotes != null) 'customer_notes': customerNotes,
      if (customerName != null) 'customer_name': customerName,
      if (clientPhone != null) 'client_phone': clientPhone,
      'items': clonedItems?.map((i) => i.toJson()).toList() ?? [],
      if ((serviceType == OrderServiceType.restaurant ||
              serviceType == OrderServiceType.storeShopping) &&
          clonedItems != null)
        'product_lines': clonedItems
            .map((i) => {
                  'product_id': i.productId,
                  'quantity': i.quantity,
                  // B1 (2026-06-11): unit_price = preço PURO (fallback do
                  // quote_order_pricing quando o id não existe em products;
                  // o servidor aplica ×1.15 por cima — ver create_order).
                  'unit_price': i.basePrice ?? i.price,
                  'name': i.name,
                })
            .toList(),
      // 2026-05-14 — cartao guardado (Edge Fn v28 lê + remove do payload draft).
      if (savedPmId != null) 'saved_pm_id': savedPmId,
    };

    // Sessão 4C: defesa pré-RPC contra productId inválido.
    // Bloqueia chegada de "nome" como product_id ao Edge Fn / RPC.
    try {
      validateOrderPayload(cartInput);
    } on FormatException catch (e) {
      debugPrint('[FLOW] startCardPaymentDraft BLOCKED — $e');
      return null;
    }

    debugPrint('[FLOW] startCardPaymentDraft → invoking create-payment-intent (new mode)');
    try {
      final response = await supabase.functions.invoke(
        'create-payment-intent',
        body: {'cart_input': cartInput},
      );
      final body = response.data as Map<String, dynamic>?;
      if (body == null ||
          body['clientSecret'] == null ||
          body['paymentIntentId'] == null ||
          body['draftId'] == null) {
        debugPrint('[FLOW] startCardPaymentDraft: incomplete response: $body');
        return null;
      }
      debugPrint('[FLOW] startCardPaymentDraft OK — draft=${body['draftId']} '
          'pi=${body['paymentIntentId']} status=${body['status']} '
          'requiresAction=${body['requiresAction']}');
      return body;
    } catch (e) {
      debugPrint('[FLOW] startCardPaymentDraft FAILED: $e');
      return null;
    }
  }

  /// Polls `payment_drafts` for `used_at NOT NULL` after Stripe charge
  /// confirmed. Returns the new `order_id` once webhook+finalize created
  /// the order, or `null` on timeout (default 30s).
  Future<String?> waitForOrderFromDraft(
    String draftId, {
    Duration timeout = const Duration(seconds: 30),
    Duration pollInterval = const Duration(seconds: 2),
  }) async {
    final deadline = DateTime.now().add(timeout);
    while (DateTime.now().isBefore(deadline)) {
      try {
        final row = await supabase
            .from('payment_drafts')
            .select('order_id, used_at')
            .eq('id', draftId)
            .maybeSingle();
        if (row != null && row['used_at'] != null && row['order_id'] != null) {
          final orderId = row['order_id'] as String;
          debugPrint('[FLOW] waitForOrderFromDraft: order created → $orderId');
          return orderId;
        }
      } catch (e) {
        debugPrint('[FLOW] waitForOrderFromDraft poll error (continuing): $e');
      }
      await Future.delayed(pollInterval);
    }
    debugPrint('[FLOW] waitForOrderFromDraft TIMEOUT for draft=$draftId');
    return null;
  }

  /// BUG #3 (2026-05-12) — resolve bag_count baseado em service_type.
  /// Server (pricing_calculate) usa este valor para calcular bag_fee via settings:
  ///   restaurant: bag_fee_restaurant_cents=30 (fixo se bag_count>=1)
  ///   storeShopping: bag_fee_supermarket_per_bag_cents=10 × bag_count
  ///   carry/sendPackage: sem bag_fee.
  /// Default requestedBagCount=1 (cliente normal). Pode ser refinado em futura
  /// versão para receber input "Quantos sacos?" no checkout storeShopping.
  int _resolveBagCount(OrderServiceType serviceType, int requestedBagCount) {
    switch (serviceType) {
      case OrderServiceType.restaurant:
        return 1; // server aplica €0.30 fixo
      case OrderServiceType.storeShopping:
        return requestedBagCount.clamp(1, 99); // server aplica €0.10 × N
      case OrderServiceType.carryGroceries:
      case OrderServiceType.sendPackage:
        return 0;
      case OrderServiceType.takeaway:
        // Confirmado via MCP: create_order RPC zera todas as fees para
        // takeaway (delivery=0, service=0, bag=0). Cliente só paga subtotal.
        return 0;
    }
  }

  Future<bool> createOrder({
    required OrderServiceType serviceType,
    required double itemsSubtotal,
    required LatLng destination,
    required PaymentMethod paymentMethod,
    List<CartItem>? items,
    LatLng? pickupLocation,
    double? distanceKm,
    bool isPartnerStore = false,
    bool apartmentDelivery = false,
    bool requiresCar = false,
    String? vendorName,
    String? pickupAddress,
    String? pickupStreet,
    String? pickupCity,
    String? pickupPostalCode,
    String? dropoffAddress,
    String? dropoffStreet,
    String? dropoffCity,
    String? dropoffPostalCode,
    String? customerNotes,
    String? clientPhone,
    String? customerName,
    PaymentStatus paymentStatus = PaymentStatus.pending,
    String? paymentIntentId,
    double tokenDiscountEur = 0.0,
    String? packagePhotoUrl,
    String? groceriesPhotoUrl,
    // D4 — `isTakeaway` removido. Caller deve passar
    // `serviceType: OrderServiceType.takeaway` via OrderModel (cart_store
    // já o faz através de _serviceType).
    bool takeawayIsCurbside = false,
    String? takeawayCurbsideInfo,
    int tipCents = 0,
    int walletAppliedCents = 0,
  }) async {
    // ── Authenticated-user guard ────────────────────────────────────────────
    // Read the user id directly from the live Supabase session (not from any
    // cached in-memory value) and refuse to create the order if:
    //   - there is no Supabase session at all, OR
    //   - the session is the anonymous guest (guest@bora.com), OR
    //   - AuthStore has no _currentClient set (UI login incomplete).
    // This prevents the regression where client login fell back to the guest
    // session and every order was persisted with user_id='f9ad894e-…' and
    // customer_name='Cliente Demo'.
    final liveUserId = supabase.auth.currentUser?.id;
    if (liveUserId == null ||
        (_authStore?.isGuestSession ?? true) ||
        _authStore?.currentClient == null) {
      debugPrint(
          '[FLOW] createOrder BLOCKED — no authenticated client session '
          '(liveUserId=$liveUserId isGuest=${_authStore?.isGuestSession} '
          'hasClient=${_authStore?.currentClient != null})');
      return false;
    }

    double? googleDistance;
    if (pickupLocation != null) {
      try {
        googleDistance =
            await MapsService.getDistanceKm(pickupLocation, destination);
      } catch (e) {
        debugPrint(
            'OrderStore.createOrder: MapsService.getDistanceKm error => $e');
      }
    }
    final isDistanceEstimated = googleDistance == null;

    final resolvedDistance = _resolveDistance(
      pickup: pickupLocation,
      destination: destination,
      providedDistance: googleDistance ?? distanceKm,
    );

    final deliveryPrice = _computeDeliveryPrice(resolvedDistance);

    // ── Local pricing — PREVIEW ONLY, not written to DB ─────────────────────
    // Used solely for the cash limit pre-check UX guard.
    // All server-trusted financial values come from the create_order RPC below.
    final localPricing = PricingService.calculateBreakdown(
      serviceType: serviceType,
      subtotal: itemsSubtotal,
      distanceKm: resolvedDistance,
      isPartnerStore: isPartnerStore,
      apartmentDelivery: apartmentDelivery,
    );

    final orderType = _resolveOrderType(
      serviceType: serviceType,
      isPartnerStore: isPartnerStore,
    );

    final clonedItems = items
        ?.map(
          (item) => CartItem(
            productId: item.productId, // T16: preserve UUID/id for server lookup
            name: item.name,
            price: item.price,
            quantity: item.quantity,
            // B1 (2026-06-11): preservar basePrice (unit_price puro nas
            // product_lines) e selectedOptions (antes eram descartadas neste
            // clone — orders.items do fluxo cash/MBWay perdia as opções).
            basePrice: item.basePrice,
            selectedOptions: item.selectedOptions,
          ),
        )
        .toList();

    if (isPartnerStore && serviceType == OrderServiceType.restaurant) {
      final restaurant = _restaurantStore?.restaurantByName(vendorName);
      if (restaurant != null && !restaurant.isOpenNow()) {
        return false;
      }
    }

    // ── Cash limit guard (UX only — backend trigger is the source of truth) ─
    // Cash has no Stripe pre-auth, so the +15% buffer (non-partner) does not
    // apply — compare against the real customer total minus token discount.
    if (paymentMethod == PaymentMethod.cash) {
      final cashCustomerTotal = localPricing.customerTotal - tokenDiscountEur;
      if (cashCustomerTotal > BRBusiness.CASH_MAX_ORDER_VALUE_EUR) {
        debugPrint('[FLOW] createOrder BLOCKED — cash limit exceeded '
            '(total=$cashCustomerTotal max=${BRBusiness.CASH_MAX_ORDER_VALUE_EUR})');
        return false;
      }
    }

    // ── Build RPC input ───────────────────────────────────────────────────────
    // All financial values (delivery_fee, driver_earnings, etc.) are calculated
    // server-side by pricing_calculate() inside create_order. Client sends only
    // inputs — never pre-computed totals.
    final rpcInput = <String, dynamic>{
      'service_type': serviceType.name,
      if (vendorName != null) 'vendor_name': vendorName,
      'is_partner_store': isPartnerStore,
      'distance_km': resolvedDistance,
      'payment_method': paymentMethod.name,
      'subtotal': itemsSubtotal,
      'apartment_delivery': apartmentDelivery,
      'order_type': orderType.name,
      // BUG #3 (2026-05-12) — bag_count dinâmico por service_type.
      'bag_count': _resolveBagCount(serviceType, 1),
      'requires_car': requiresCar,
      // S1.4: Wallet debit happens atomically inside create_order RPC.
      // Pre-validates balance with FOR UPDATE lock; throws on insufficient.
      'wallet_applied_cents': walletAppliedCents,
      if (pickupLocation != null) 'pickup_lat': pickupLocation.latitude,
      if (pickupLocation != null) 'pickup_lng': pickupLocation.longitude,
      'dropoff_lat': destination.latitude,
      'dropoff_lng': destination.longitude,
      if (pickupAddress != null) 'pickup_address': pickupAddress,
      if (pickupStreet != null) 'pickup_street': pickupStreet,
      if (pickupCity != null) 'pickup_city': pickupCity,
      if (pickupPostalCode != null) 'pickup_postal_code': pickupPostalCode,
      if (dropoffAddress != null) 'dropoff_address': dropoffAddress,
      if (dropoffStreet != null) 'dropoff_street': dropoffStreet,
      if (dropoffCity != null) 'dropoff_city': dropoffCity,
      if (dropoffPostalCode != null) 'dropoff_postal_code': dropoffPostalCode,
      if (customerNotes != null) 'customer_notes': customerNotes,
      if (customerName != null) 'customer_name': customerName,
      if (clientPhone != null) 'client_phone': clientPhone,
      if (paymentIntentId != null) 'payment_intent_id': paymentIntentId,
      'items': clonedItems?.map((i) => i.toJson()).toList() ?? [],
      // restaurant / storeShopping: pass product_lines so RPC recalculates
      // subtotal from DB prices (server-trusted subtotal — Opção B).
      // carryGroceries / sendPackage: no product_lines → RPC trusts client subtotal.
      // T16: include product_id (UUID when available) so create_order can do
      //      DB lookup first; falls back to unit_price if not found.
      if ((serviceType == OrderServiceType.restaurant ||
              serviceType == OrderServiceType.storeShopping) &&
          clonedItems != null)
        'product_lines': clonedItems
            .map((i) => {
                  'product_id': i.productId,
                  'quantity': i.quantity,
                  // B1 (2026-06-11): unit_price = preço PURO de catálogo.
                  // O servidor só o usa como fallback quando o product_id não
                  // existe em `products` (ex. variantes) e aplica ×1.15 por
                  // cima — enviar i.price (já com markup) duplicaria o markup.
                  'unit_price': i.basePrice ?? i.price,
                  'name': i.name,
                })
            .toList(),
    };

    // Sessão 4C: defesa pré-RPC contra productId inválido.
    // Bloqueia chegada de "nome" como product_id à RPC create_order.
    try {
      validateOrderPayload(rpcInput);
    } on FormatException catch (e) {
      debugPrint('[FLOW] createOrder BLOCKED — $e');
      return false;
    }

    debugPrint(
        '[FLOW] createOrder START → RPC create_order type=${serviceType.name}');
    lastCreateOrderError = null;

    // serverOrder declared outside try so the catch block can roll back if
    // anything after the RPC (photos, push, simulate) throws.
    OrderModel? serverOrder;

    try {
      // ── Server-trusted order creation ────────────────────────────────────
      final dynamic rpcResult =
          await supabase.rpc('create_order', params: {'p_input': rpcInput});
      final rpcData = Map<String, dynamic>.from(rpcResult as Map);

      debugPrint(
          '[FLOW] createOrder RPC OK → id=${rpcData['order_id']} total=${rpcData['price']}');

      serverOrder = OrderModel(
        id: rpcData['order_id'] as String,
        total: (rpcData['price'] as num).toDouble(),
        serviceType: serviceType,
        subtotal: (rpcData['subtotal'] as num).toDouble(),
        deliveryFee: (rpcData['delivery_fee'] as num).toDouble(),
        serviceFee: (rpcData['service_fee'] as num).toDouble(),
        platformCommission: (rpcData['platform_commission'] as num).toDouble(),
        driverEarnings: (rpcData['driver_earnings'] as num).toDouble(),
        bagFee: (rpcData['bag_fee'] as num? ?? 0).toDouble(),
        distanceKm: resolvedDistance,
        deliveryPrice: deliveryPrice,
        items: clonedItems,
        pickupLocation: pickupLocation,
        destination: destination,
        vendorName: vendorName,
        pickupAddress: pickupAddress,
        pickupStreet: pickupStreet,
        pickupCity: pickupCity,
        pickupPostalCode: pickupPostalCode,
        dropoffAddress: dropoffAddress,
        dropoffStreet: dropoffStreet,
        dropoffCity: dropoffCity,
        dropoffPostalCode: dropoffPostalCode,
        customerNotes: customerNotes,
        isPartnerStore: isPartnerStore,
        apartmentDelivery: apartmentDelivery,
        isDistanceEstimated: isDistanceEstimated,
        requiresCar: requiresCar,
        orderType: orderType,
        paymentMethod: paymentMethod,
        paymentStatus: paymentStatus,
        paymentIntentId: paymentIntentId,
        clientPhone: clientPhone,
        customerName: customerName,
        userId: liveUserId,
        // paymentBufferTotal from server already includes the ×1.15 buffer for
        // non-partner orders. Token discount is subtracted here so the Stripe
        // pre-auth amount (validated ±5% against this field) matches what the
        // client actually charges.
        paymentBufferTotal:
            (rpcData['payment_buffer_total'] as num).toDouble() -
                tokenDiscountEur,
        tipCents: tipCents,
        // D4 — takeaway agora vem implícito via serviceType. Curbside é
        // gravado pelo servidor via create_order RPC (server-trusted) e
        // espelhado abaixo no UPDATE side-effect.
        takeawayIsCurbside: takeawayIsCurbside,
        takeawayCurbsideInfo: takeawayCurbsideInfo,
        walletAppliedCents:
            (rpcData['wallet_applied_cents'] as num?)?.toInt() ?? 0,
        menuCreditAppliedCents:
            (rpcData['menu_credit_applied_cents'] as num?)?.toInt() ?? 0,
      );

      final order = serverOrder;
      _orders.insert(0, order);
      _lastCreatedOrderId = order.id;
      notifyListeners();

      debugPrint('[FLOW] createOrder: RPC + local state OK');

      // Persist mandatory photos for sendPackage / carryGroceries (BR §7.5/7.6)
      // + curbside info (D6). Side-effect update after insert.
      // Coluna `is_takeaway` foi APAGADA do servidor — NÃO gravar.
      final hasCurbsideData = takeawayIsCurbside ||
          (takeawayCurbsideInfo != null && takeawayCurbsideInfo.isNotEmpty);
      if (packagePhotoUrl != null ||
          groceriesPhotoUrl != null ||
          hasCurbsideData) {
        try {
          await supabase.from('orders').update({
            if (packagePhotoUrl != null) 'package_photo_url': packagePhotoUrl,
            if (groceriesPhotoUrl != null)
              'groceries_photo_url': groceriesPhotoUrl,
            if (takeawayIsCurbside) 'takeaway_is_curbside': true,
            if (takeawayCurbsideInfo != null &&
                takeawayCurbsideInfo.isNotEmpty)
              'takeaway_curbside_info': takeawayCurbsideInfo,
          }).eq('id', order.id);
        } catch (e) {
          debugPrint(
              '[FLOW] createOrder: photo/curbside update failed => $e');
        }
      }

      if (!_orders.any((o) => o.id == order.id)) {
        debugPrint('[FLOW] createOrder: re-inserting after concurrent clear');
        _orders.insert(0, order);
        notifyListeners();
      }

      // S1.4: Wallet debit no longer post-RPC — done atomically inside
      // create_order. The RPC return now exposes wallet_applied_cents and
      // fully_paid_by_wallet so callers can branch on payment flow.
      if (walletAppliedCents > 0) {
        debugPrint(
            '[FLOW] createOrder: wallet applied ${rpcData['wallet_applied_cents']} cents '
            '(charge=${rpcData['charge_total']}, fully_paid=${rpcData['fully_paid_by_wallet']})');
      }

      // Notify partner restaurant of new order via FCM push (fire-and-forget).
      // Only for partner restaurant orders — supermarket/logistics flows are handled differently.
      // MBWay: notificação feita pelo stripe-webhook após payment_intent.succeeded
      // para não notificar o parceiro antes do pagamento estar confirmado.
      if (order.isPartnerStore &&
          order.serviceType == OrderServiceType.restaurant &&
          order.paymentMethod != PaymentMethod.mbway) {
        final restaurant = _restaurantStore?.restaurantByName(order.vendorName);
        if (restaurant != null) {
          final itemsSummary = order.items
              .take(3)
              .map((i) => '${i.quantity}x ${i.name}')
              .join(', ');
          NotificationService.instance
              .notifyPartnerNewOrder(
                orderId: order.id,
                restaurantId: restaurant.id,
                items: itemsSummary,
                total: order.total,
              )
              .ignore();
          debugPrint(
              '[FLOW] createOrder: partner push queued for ${restaurant.name}');
        }
      }

      // NOTE: MBWay confirmation is server-only via stripe-webhook (Stripe
      // PaymentIntent succeeded → flips payment_status to 'paid'). The client
      // does NOT trigger confirmation directly — that would make the
      // "server-trusted" path trivially forgeable.

      // Fire-and-forget: status simulation is a best-effort side-effect.
      // createOrder returns true as soon as the order is committed to the server.
      _simulateRestaurantFlow(order).ignore();
      debugPrint('[FLOW] createOrder DONE id=${order.id} — RPC committed, simulate async');
      return true;
    } catch (e) {
      debugPrint('[FLOW] createOrder FAILED: $e');
      lastCreateOrderError = e.toString();
      if (serverOrder != null) {
        // RPC committed the order to the server — do NOT roll back local state.
        // Ensure the order is visible in the UI and return success.
        final committed = serverOrder; // non-nullable capture for closure safety
        if (!_orders.any((o) => o.id == committed.id)) {
          _orders.insert(0, committed);
        }
        notifyListeners();
        return true;
      }
      // RPC itself failed — order was never persisted on the server.
      notifyListeners();
      return false;
    }
  }

  Future<void> _simulateRestaurantFlow(OrderModel order) async {
    try {
    debugPrint(
        '[FLOW] _simulateFlow START id=${order.id} type=${order.serviceType.name} partner=${order.isPartnerStore} status=${order.status.name}');

    final isPartnerRestaurantOrder =
        order.serviceType == OrderServiceType.restaurant &&
            order.isPartnerStore;

    if (isPartnerRestaurantOrder) {
      debugPrint(
          '[FLOW] _simulateFlow: partner restaurant — waiting for dashboard');
      return;
    }

    final requiresPreparation =
        order.serviceType == OrderServiceType.restaurant ||
            (order.serviceType == OrderServiceType.storeShopping &&
                order.isPartnerStore);

    debugPrint(
        '[FLOW] _simulateFlow: requiresPreparation=$requiresPreparation');

    final progressed = await _advanceStatus(order, OrderStatus.preparing);
    debugPrint(
        '[FLOW] _simulateFlow: preparing result=$progressed status=${order.status.name}');
    if (!progressed) {
      debugPrint('[FLOW] _simulateFlow: BLOCKED at preparing — aborting');
      return;
    }

    final delay = requiresPreparation
        ? const Duration(seconds: 3)
        : const Duration(milliseconds: 500);

    debugPrint('[FLOW] _simulateFlow: waiting ${delay.inMilliseconds}ms');
    await Future.delayed(delay);

    if (!_orders.any((o) => o.id == order.id)) {
      debugPrint('[FLOW] _simulateFlow: order gone after delay — re-inserting');
      _orders.insert(0, order);
      notifyListeners();
    }

    debugPrint(
        '[FLOW] _simulateFlow: advancing to callingDriver (localStatus=${order.status.name})');

    // ── Payment gate — order must be paid before dispatch.
    // Payment is now confirmed in the UI before createOrder() is called, so
    // orders should always arrive here with paymentStatus == paid.
    // This guard is a safety net against any future regression.
    if (order.paymentStatus != PaymentStatus.paid) {
      debugPrint(
          '⛔ Dispatch bloqueado: pagamento não confirmado (id=${order.id} method=${order.paymentMethod.name} status=${order.paymentStatus.name})');
      return;
    }
    debugPrint('[FLOW] payment confirmed — proceeding to dispatch');

    final reached = await _advanceStatus(order, OrderStatus.callingDriver);

    debugPrint('[FLOW] _simulateFlow: callingDriver result=$reached');

    if (!reached) {
      debugPrint(
          '[FLOW] ERROR: failed to reach callingDriver — dispatch will NOT run');
    }
    } catch (e, st) {
      debugPrint('[FLOW] _simulateFlow ERROR (background, order safe on server): $e\n$st');
    }
  }

  /// No-op: dispatch após pagamento por cartão agora é inteiramente controlado
  /// pelo stripe-webhook (server-trusted).
  ///
  /// O webhook faz:
  ///   1. payment_status → paid
  ///   2. status → callingDriver  (para orders não-parceiro)
  ///   3. invoca dispatch-engine diretamente
  ///
  /// O Flutter observa via Realtime — nunca escreve payment_status.
  Future<void> resumeDispatchAfterPayment(String orderId) async {
    debugPrint(
        '[FLOW] resumeDispatchAfterPayment: dispatch agora é webhook-driven — noop (id=$orderId)');
  }

  Future<bool> _advanceStatus(
      OrderModel order, OrderStatus targetStatus) async {
    debugPrint(
        '[FLOW] _advanceStatus: ${order.status.name} → ${targetStatus.name} id=${order.id}');

    // D8 — takeaway: cliente Flutter NÃO avança status. Servidor (RPCs
    // partner_takeaway_*) é authoritative. Apenas cancelamento/rejeição
    // são permitidos por este caminho.
    if (order.serviceType == OrderServiceType.takeaway &&
        targetStatus != OrderStatus.cancelled &&
        targetStatus != OrderStatus.rejected) {
      debugPrint(
          '[FLOW] _advanceStatus: BLOCKED — takeaway only mutated server-side (id=${order.id})');
      return false;
    }

    final inList = _orders.any((o) => o.id == order.id);
    if (!inList) {
      debugPrint(
          '[FLOW] _advanceStatus: BLOCKED — order not in _orders (len=${_orders.length})');
      return false;
    }

    if (order.status == targetStatus) {
      debugPrint(
          '[FLOW] _advanceStatus: BLOCKED — already at ${targetStatus.name}');
      return false;
    }

    if (!_canTransition(order.status, targetStatus)) {
      final allowed = _statusFlow[order.status];
      debugPrint(
          '[FLOW] _advanceStatus: BLOCKED — ${order.status.name}→${targetStatus.name} not in $allowed');
      return false;
    }

    // NOTE: driver_offer_expires_at is intentionally NOT set here.
    // Only the dispatch engine (Edge Function) owns that field — it sets it
    // when a real offer is made. Flutter setting a speculative expiry here
    // pollutes the state and can cause the dispatch engine to skip the order
    // if it reads an unexpected non-null value in the wrong context.
    debugPrint('[FLOW] _advanceStatus: DB update status=${targetStatus.name}');
    final success = await _updateOrderStatusInDatabase(order, targetStatus);

    if (!success) {
      debugPrint('[FLOW] _advanceStatus: DB UPDATE FAILED');
      // 2026-05-21 — A8: enfileira transição do estafeta para retry quando
      // rede voltar. OfflineStatusQueue filtra apenas pickedUp/onTheWay/delivered.
      unawaited(OfflineStatusQueue.enqueue(
        orderId: order.id,
        targetStatusName: targetStatus.name,
      ));
      return false;
    }

    // 2026-05-21 — A8: rede voltou → drena fila pendente sem aguardar.
    unawaited(_drainOfflineStatusQueue());

    order.status = targetStatus;
    notifyListeners();
    _handlePartnerPreparationFlow(order);

    // Fire-and-forget client push for lifecycle transitions. Edge Function
    // no-ops if the client has no FCM token or Firebase is not configured.
    _notifyClientForStatus(order, targetStatus);

    if (targetStatus == OrderStatus.callingDriver) {
      debugPrint(
          '[FLOW] ★★★ callingDriver REACHED ★★★ id=${order.id} — invoking dispatch-engine directly');
      // Invoke the Edge Function directly from Flutter as the PRIMARY dispatch
      // mechanism. The DB trigger is a secondary safety net only — it has a
      // service-role-key placeholder that makes it fail with 401 until the
      // SQL is re-run with the real key. Direct invocation guarantees dispatch
      // fires on every callingDriver transition regardless of trigger state.
      unawaited(_invokeDispatch(order.id));
    }
    return true;
  }

  // 2026-05-21 — A8: drena fila offline de transições do estafeta.
  // Chamado após uma transição bem-sucedida (indicador de rede OK).
  Future<void> _drainOfflineStatusQueue() async {
    try {
      final pending = await OfflineStatusQueue.peek();
      if (pending.isEmpty) return;
      debugPrint('[OfflineQueue] draining ${pending.length} pending');
      for (final entry in pending) {
        OrderModel? order;
        for (final o in _orders) {
          if (o.id == entry.orderId) {
            order = o;
            break;
          }
        }
        if (order == null) {
          // Ordem já não está em memória — descarta (não bloqueia fila).
          await OfflineStatusQueue.remove(
            orderId: entry.orderId,
            targetStatusName: entry.targetStatusName,
          );
          continue;
        }
        final target = OrderStatus.values.firstWhere(
          (s) => s.name == entry.targetStatusName,
          orElse: () => OrderStatus.created,
        );
        if (target == order.status) {
          // Já foi para esse estado (provavelmente via realtime) — limpa.
          await OfflineStatusQueue.remove(
            orderId: entry.orderId,
            targetStatusName: entry.targetStatusName,
          );
          continue;
        }
        final ok = await _updateOrderStatusInDatabase(order, target);
        if (ok) {
          order.status = target;
          notifyListeners();
          await OfflineStatusQueue.remove(
            orderId: entry.orderId,
            targetStatusName: entry.targetStatusName,
          );
        } else {
          // Ainda offline — pára aqui, mantém fila.
          break;
        }
      }
    } catch (e) {
      debugPrint('[OfflineQueue] drain error: $e');
    }
  }

  /// Fire-and-forget: sends a status-specific push to the client.
  /// Skips statuses that don't warrant a client notification (created, rejected).
  void _notifyClientForStatus(OrderModel order, OrderStatus status) {
    // Only statuses covered by the notify-client Edge Function map.
    const notifiable = {
      OrderStatus.preparing,
      OrderStatus.callingDriver,
      OrderStatus.driverAccepted,
      OrderStatus.pickedUp,
      OrderStatus.onTheWay,
      OrderStatus.delivered,
    };
    if (!notifiable.contains(status)) return;
    final clientId = order.userId;
    if (clientId == null || clientId.isEmpty) return;

    // Look up vendor + driver names for richer copy (best-effort).
    final vendor = _restaurantStore?.restaurantByName(order.vendorName)?.name
        ?? order.vendorName;
    final driver = order.assignedDriverId == null
        ? null
        : _driverStore.getDriverById(order.assignedDriverId!)?.name;

    NotificationService.instance
        .notifyClientOrderStatus(
          clientId: clientId,
          orderId: order.id,
          status: status.name,
          vendorName: vendor,
          driverName: driver,
        )
        .ignore();
  }

  bool _canTransition(OrderStatus current, OrderStatus target) {
    final allowedTargets = _statusFlow[current];
    if (allowedTargets == null) return false;
    return allowedTargets.contains(target);
  }

  Future<bool> markPreparing(OrderModel order) =>
      _advanceStatus(order, OrderStatus.preparing);

  Future<bool> markReadyForDriver(OrderModel order) async {
    return _advanceStatus(order, OrderStatus.callingDriver);
  }

  bool rejectAvailableOrder(OrderModel order) {
    if (order.status != OrderStatus.callingDriver) return false;
    _dismissedOrderIds.add(order.id);
    // Exec6.5 — marca handled no gate para impedir re-trigger noutra UI
    // (laranja rejeitada → bonita NÃO pode aparecer para o mesmo pedido).
    OfferPresentationGate.markActionCompleted(order.id);
    notifyListeners();
    // Notify backend immediately so the next driver is dispatched without
    // waiting for the 40-second offer timeout to expire.
    unawaited(_rejectOrderInBackend(order));
    return true;
  }

  Future<void> _rejectOrderInBackend(OrderModel order) async {
    final driverId = _currentDriverId;
    if (driverId.isEmpty) return;
    if (order.assignedDriverId != null) return;
    try {
      // Sessão 2026-05-22 — usar RPC driver_reject_offer (SECURITY DEFINER) que:
      //   1) limpa current_driver_offer_id + expires_at atomicamente
      //   2) ADICIONA o driver a tried_driver_ids (sem isto, dispatch-engine
      //      cycle-reset não dispara e o pedido fica preso no estafeta antigo
      //      por 40s até timeout)
      //   3) invoca dispatch-engine via invoke_dispatch_engine RPC
      // CallKit reject (main.dart) também usa esta RPC.
      final res = await supabase.rpc(
        'driver_reject_offer',
        params: {'p_order_id': order.id},
      );
      debugPrint('[OrderStore] _rejectOrderInBackend: RPC result=$res for order=${order.id}');
      // Cancelar notificação persistente de oferta após rejeitar.
      unawaited(cancelDriverOfferNotification(order.id));
    } catch (e) {
      debugPrint('[OrderStore] _rejectOrderInBackend RPC error: $e');
    }
  }

  /// Cancels an already-accepted order via the SECURITY DEFINER RPC
  /// `driver_cancel_order`. The RPC handles the DB-side transition back to
  /// `callingDriver` and re-triggers dispatch. Flutter only needs to remove
  /// the row from local state so the driver UI updates immediately.
  ///
  /// Sessão 7-UI-BUG004: a RPC devolve um JSON com `ok`, `error`,
  /// `support_required` e `message`. Pós status `pickedUp` o backend
  /// recusa com `support_required:true` (BUG-7E-B-004 fix em 7-FIX,
  /// migration 20260507223338). Devolvemos o Map para a UI poder
  /// abrir o bottom sheet de redirecção ao suporte.
  Future<Map<String, dynamic>> driverCancelAcceptedOrder(
      OrderModel order) async {
    try {
      final response = await supabase.rpc(
        'driver_cancel_order',
        params: {'p_order_id': order.id},
      );
      final result = (response is Map)
          ? Map<String, dynamic>.from(response)
          : <String, dynamic>{'ok': false, 'error': 'invalid_response'};
      if (result['ok'] == true) {
        _orders.removeWhere((o) => o.id == order.id);
        notifyListeners();
      }
      return result;
    } catch (e) {
      debugPrint('[OrderStore] driverCancelAcceptedOrder: $e');
      return <String, dynamic>{
        'ok': false,
        'error': 'rpc_exception',
        'message': e.toString(),
      };
    }
  }

  Future<bool> cancelDelivery(OrderModel order) async {
    final driverId = _currentDriverId;
    if (order.assignedDriverId != driverId) return false;
    if (order.status != OrderStatus.driverAccepted) return false;

    try {
      // Blacklist the cancelling driver so dispatch doesn't re-offer the
      // same order back to them. Merge with any existing tried_driver_ids.
      final mergedTried = <String>{
        ...order.triedDriverIds,
        driverId,
      }.toList();

      await supabase.from('orders').update({
        'assigned_driver_id': null,
        'current_driver_offer_id': null,
        'driver_offer_expires_at': null,
        'status': OrderStatus.callingDriver.name,
        'tried_driver_ids': mergedTried,
      }).eq('id', order.id);

      await _driverLocationService.stopTracking();
      _driverStore.stopTracking(order.id);
      _dismissedOrderIds.add(order.id);

      // Re-trigger dispatch so another driver receives this order immediately.
      unawaited(_invokeDispatch(order.id));

      debugPrint(
          'OrderStore.cancelDelivery: OK driver=$driverId order=${order.id}');
      return true;
    } catch (e) {
      debugPrint('OrderStore.cancelDelivery: error => $e');
      return false;
    }
  }

  /// Driver requests help from a secondary driver (BR §5.2).
  ///
  /// Calls the SECURITY DEFINER RPC `request_driver_help` which:
  ///   1. Validates caller is the primary driver.
  ///   2. Rejects if order is from a partner restaurant.
  ///   3. Rejects if service_type not in (storeShopping, carryGroceries).
  ///   4. Marks `needs_helper=true` and locks the €4 helper fee.
  ///
  /// NOTE: Wiring of the helper dispatch (40s offer to nearest driver) goes
  /// through the existing dispatch-engine (protected zone) — not modified
  /// here. The helper assignment and payout split are handled downstream.
  Future<bool> requestDriverHelp(OrderModel order) async {
    try {
      await supabase.rpc(
        'request_driver_help',
        params: {'p_order_id': order.id},
      );
      return true;
    } catch (e) {
      debugPrint('[OrderStore] requestDriverHelp: $e');
      return false;
    }
  }

  /// Cancels an order from the client side (BR §8.3).
  ///
  /// Fee tiers:
  ///   • created/preparing/callingDriver → €1.00
  ///   • driverAccepted                  → €2.50
  ///   • pickedUp/onTheWay               → 100% of total (no refund)
  ///
  /// Delegates to the `client-cancel-order` Edge Function which:
  ///   1. Locks the row, recomputes the fee server-side.
  ///   2. Issues Stripe refund if paid by card (for non-100% tiers).
  ///   3. Updates orders row: status='cancelled', cancel_fee, cancel_reason,
  ///      cancelled_at, payment_status='refunded' or 'partial_refund'.
  ///
  /// Never touches pricing_service or finalizePurchase. The local state is
  /// refreshed via the realtime UPDATE event that follows the DB write.
  Future<ClientCancelResult> clientCancelOrder(
    OrderModel order, {
    String? reason,
  }) async {
    try {
      final response = await supabase.functions.invoke(
        'client-cancel-order',
        body: {
          'order_id': order.id,
          if (reason != null && reason.trim().isNotEmpty)
            'reason': reason.trim(),
        },
      );
      if (response.status >= 400) {
        final data = response.data;
        final msg = (data is Map && data['error'] is String)
            ? data['error'] as String
            : 'cancel_failed';
        return ClientCancelResult.failure(msg);
      }
      final data = response.data;
      final feeEur = (data is Map && data['fee_eur'] != null)
          ? (data['fee_eur'] as num).toDouble()
          : null;
      return ClientCancelResult.success(feeEur: feeEur);
    } catch (e) {
      debugPrint('[OrderStore] clientCancelOrder: $e');
      return ClientCancelResult.failure(e.toString());
    }
  }

  Future<bool> acceptOrder(OrderModel order) async {
    if (!isDriverAvailable) return false;
    if (order.assignedDriverId != null &&
        order.assignedDriverId != _currentDriverId) {
      return false;
    }
    if (!_driverStore.canAcceptOrder(_currentDriverId, order)) return false;
    if (!_orders.any((o) => o.id == order.id)) return false;
    if (!_canTransition(order.status, OrderStatus.driverAccepted)) return false;

    final driver = _driverStore.getDriverById(_currentDriverId);
    final success = await _acceptOrderInDatabase(
      order,
      driverId: _currentDriverId,
      driverPhone: driver?.phone,
    );
    if (!success) return false;
    // Cancelar notificação persistente de oferta após aceitar com sucesso.
    unawaited(cancelDriverOfferNotification(order.id));
    // Exec6.5 — marca handled no gate (impede CallKit/dialog de reaparecer
    // para o mesmo orderId depois de aceite).
    OfferPresentationGate.markActionCompleted(order.id);

    order.status = OrderStatus.driverAccepted;
    order.assignedDriverId = _currentDriverId;
    order.currentDriverOfferId = null;
    order.driverPhone = driver?.phone;
    notifyListeners();
    _handlePartnerPreparationFlow(order);

    final registered =
        _driverStore.registerOrderForDriver(_currentDriverId, order);
    if (registered) {
      _driverStore.startTracking(order);
    }
    _driverLocationService.startTracking(order.id);

    return true;
  }

  Future<void> acceptOrderById(String orderId, String driverId) async {
    try {
      await supabase.from('orders').update({
        'assigned_driver_id': driverId,
        'status': OrderStatus.driverAccepted.name,
      }).eq('id', orderId);
      debugPrint(
          'OrderStore.acceptOrderById: OK order=$orderId driver=$driverId');
      await loadOrders();
    } catch (e) {
      debugPrint('OrderStore.acceptOrderById: error => $e');
    }
  }

  Future<bool> pickUpOrder(OrderModel order) async {
    final advanced = await _advanceStatus(order, OrderStatus.pickedUp);
    if (advanced) {
      order.pickupWarningIssued = false;
      _driverStore.updateTrackingTarget(order);
      final driver = _driverStore.getDriverById(_currentDriverId);
      driver?.activeAssignments
          .where((a) => a.orderId == order.id)
          .forEach((a) => a.hasBeenPickedUp = true);
    }
    return advanced;
  }

  Future<bool> startDelivery(OrderModel order) async {
    final advanced = await _advanceStatus(order, OrderStatus.onTheWay);
    if (advanced) {
      _driverStore.updateTrackingTarget(order);
    }
    return advanced;
  }

  Future<bool> finishOrder(OrderModel order) async {
    final advanced = await _advanceStatus(order, OrderStatus.delivered);
    if (advanced && order.assignedDriverId != null) {
      _driverStore.releaseOrderForDriver(order.assignedDriverId!, order.id);
      _driverStore.stopTracking(order.id);
      _driverLocationService.stopTracking();
      order.pickupWarningIssued = false;
    }
    return advanced;
  }

  /// BUG 6 (Fase 3 / 2026-04-30) — Alarga guard p/ aceitar `driverAccepted`.
  ///
  /// O UI (`driver_map_screen.dart` _FinalizePurchaseButton) já mostra o botão
  /// em `driverAccepted` por design (estafeta finaliza compra ANTES de marcar
  /// pickup). A guarda anterior só aceitava `pickedUp/onTheWay`, causando
  /// rejeição silenciosa e estafeta preso (Order 6746d61f preso 36h).
  ///
  /// Retorna `null` em sucesso, ou um `String` com a razão da falha — caller
  /// deve mostrar a mensagem ao utilizador em vez do snackbar genérico.
  Future<String?> finalizePurchaseWithReason({
    required String orderId,
    required double purchaseValue,
  }) async {
    if (purchaseValue <= 0) return 'Valor inválido (deve ser > 0).';

    final index = _orders.indexWhere((o) => o.id == orderId);
    if (index == -1) return 'Pedido não encontrado localmente.';

    final order = _orders[index];

    final isEligible = order.serviceType == OrderServiceType.storeShopping ||
        !order.isPartnerStore;
    if (!isEligible) {
      return 'Confirmar compra não disponível para parceiros.';
    }

    // BUG 6 fix: aceitar driverAccepted (estafeta finaliza ANTES de pickup).
    if (order.status != OrderStatus.driverAccepted &&
        order.status != OrderStatus.pickedUp &&
        order.status != OrderStatus.onTheWay) {
      return 'Estado do pedido (${order.status.name}) não permite finalizar compra.';
    }

    if (order.isPurchaseFinalized) {
      return 'Compra já foi finalizada.';
    }
    return await _finalizePurchaseUnchecked(order, purchaseValue);
  }

  /// Wrapper bool legado — mantém retrocompatibilidade com chamadores antigos.
  Future<bool> finalizePurchase({
    required String orderId,
    required double purchaseValue,
  }) async {
    final reason = await finalizePurchaseWithReason(
      orderId: orderId,
      purchaseValue: purchaseValue,
    );
    return reason == null;
  }

  /// Lógica interna sem guards — só chamada após validação em finalizePurchaseWithReason.
  Future<String?> _finalizePurchaseUnchecked(OrderModel order, double purchaseValue) async {
    final orderId = order.id;

    final breakdown = PricingService.calculateBreakdown(
      serviceType: order.serviceType,
      subtotal: purchaseValue,
      distanceKm: order.distanceKm,
      isPartnerStore: false,
      apartmentDelivery: order.apartmentDelivery,
    );
    // For storeShopping: add bag_fee (count × €0.10, set by updateBagCount).
    // For restaurant non-partner: bag_fee €0.30 already included in breakdown.customerTotal.
    final computedFinalTotal = breakdown.customerTotal +
        (order.serviceType == OrderServiceType.storeShopping ? order.bagFee : 0.0);

    final diff = double.parse(
        (computedFinalTotal - order.paymentBufferTotal).toStringAsFixed(2));
    final refund = diff < 0 ? -diff : 0.0;
    final extra = diff > 0 ? diff : 0.0;
    // Client NEVER writes 'paid'. Only refundPending / extraRequired are safe
    // client-driven transitions (they downgrade, not promote). If neither, the
    // row stays whatever server-trusted status it already has (webhook-set).
    final PaymentStatus? newPaymentStatus = refund > 0
        ? PaymentStatus.refundPending
        : extra > 0
            ? PaymentStatus.extraRequired
            : null;

    try {
      final update = <String, dynamic>{
        'final_purchase_value': purchaseValue,
        'final_total': computedFinalTotal,
        'is_purchase_finalized': true,
        'refund_amount': refund,
        'extra_charge_amount': extra,
      };
      if (newPaymentStatus != null) {
        update['payment_status'] = newPaymentStatus.name;
      }
      await supabase.from('orders').update(update).eq('id', orderId);
    } catch (e) {
      debugPrint('OrderStore: finalizePurchase DB error => $e');
      return 'Erro a gravar na base de dados: $e';
    }

    order.finalPurchaseValue = purchaseValue;
    order.finalTotal = computedFinalTotal;
    order.isPurchaseFinalized = true;
    order.refundAmount = refund;
    order.extraChargeAmount = extra;
    if (newPaymentStatus != null) {
      order.paymentStatus = newPaymentStatus;
    }
    notifyListeners();

    if (order.paymentMethod == PaymentMethod.card) {
      if (refund > 0) {
        await processRefund(order);
      } else if (extra > 0) {
        await processExtraCharge(order);
      }
    }

    return null;
  }

  bool hasPaymentAdjustment(OrderModel order) {
    return (order.refundAmount ?? 0) > 0 || (order.extraChargeAmount ?? 0) > 0;
  }

  /// New finalize for storeShopping non-partner — calls the SECURITY DEFINER
  /// RPC `finalize_storeshopping_purchase`. The RPC bypasses the
  /// `enforce_financial_immutability` trigger via a session GUC and computes
  /// final_total / refund / extra_charge server-side from items_status +
  /// items_added. Returns null on success, or a String reason on failure.
  ///
  /// Replaces the old "Valor da nota fiscal" flow which UPDATEd financial
  /// columns directly and was blocked by the trigger (BUG 16).
  Future<String?> finalizePurchaseV2({
    required String orderId,
    required List<CartItem> items,
    List<Map<String, dynamic>> itemsAdded = const [],
    int? bagCount,
  }) async {
    final index = _orders.indexWhere((o) => o.id == orderId);
    if (index == -1) return 'Pedido não encontrado localmente.';
    final order = _orders[index];

    if (order.serviceType != OrderServiceType.storeShopping &&
        order.serviceType != OrderServiceType.restaurant) {
      return 'Confirmar compra só está disponível para storeShopping ou restaurant.';
    }
    if (order.status != OrderStatus.driverAccepted &&
        order.status != OrderStatus.pickedUp &&
        order.status != OrderStatus.onTheWay) {
      return 'Estado do pedido (${order.status.name}) não permite finalizar compra.';
    }
    if (order.isPurchaseFinalized) {
      return 'Compra já foi finalizada.';
    }

    try {
      final response = await supabase.rpc(
        'finalize_storeshopping_purchase',
        params: <String, dynamic>{
          'p_order_id': orderId,
          'p_items_status': items.map((i) => i.toJson()).toList(),
          'p_items_added': itemsAdded,
          if (bagCount != null) 'p_bag_count': bagCount,
        },
      );

      // Apply server-computed totals to local state (realtime UPDATE will
      // overwrite shortly with the same values).
      if (response is Map) {
        final finalCents = (response['final_total_cents'] as num?)?.toInt() ?? 0;
        final refundCents = (response['refund_cents'] as num?)?.toInt() ?? 0;
        final extraCents =
            (response['extra_charge_cents'] as num?)?.toInt() ?? 0;
        final newPaymentStatusName = response['payment_status'] as String?;

        order.finalTotal = finalCents / 100.0;
        // RPC corrigida (2026-05-22): cash_total_due passa a espelhar final_total.
        // Limpar localmente força o getter totalToCollectCash a cair em finalTotal
        // (autoritativo da RPC), evitando que um cashTotalDue antigo herdado de
        // fromSupabase (pré-fix RPC) sobreviva e mostre "RECEBER €X" errado ao estafeta.
        order.cashTotalDue = null;
        order.refundAmount = refundCents > 0 ? refundCents / 100.0 : null;
        order.extraChargeAmount = extraCents > 0 ? extraCents / 100.0 : null;
        order.isPurchaseFinalized = true;
        order.items = List<CartItem>.unmodifiable(items);
        final bagFeeCents = (response['bag_fee_cents'] as num?)?.toInt();
        if (bagFeeCents != null) order.bagFee = bagFeeCents / 100.0;
        final bagCountResp = (response['bag_count'] as num?)?.toInt();
        if (bagCountResp != null) order.bagCount = bagCountResp;
        final rawAdded = response['items_added'];
        if (rawAdded is List) {
          order.itemsAdded = rawAdded
              .map((e) => Map<String, dynamic>.from(e as Map))
              .toList();
        }
        if (newPaymentStatusName != null) {
          order.paymentStatus = PaymentStatus.values.firstWhere(
            (e) => e.name == newPaymentStatusName,
            orElse: () => order.paymentStatus,
          );
        }
        notifyListeners();

        // Card/wallet: trigger automatic charge/refund via Edge Functions.
        if (order.paymentMethod == PaymentMethod.card ||
            order.paymentMethod == PaymentMethod.mbway) {
          if (refundCents > 0) {
            unawaited(processRefund(order));
          } else if (extraCents > 0) {
            unawaited(processExtraCharge(order));
          }
        }
        // Cash: driver collects diff at delivery (handled in driver UI).

        final warning = response['warning'] as String?;
        if (warning != null && warning.isNotEmpty) {
          debugPrint('[OrderStore] finalizePurchaseV2 warning: $warning');
        }
      }

      return null;
    } catch (e) {
      debugPrint('OrderStore: finalizePurchaseV2 RPC error => $e');
      return 'Erro ao finalizar compra: $e';
    }
  }

  /// BUG 1 — Finaliza compra storeShopping V2 não-parceiro com foto talão +
  /// valor digitado pelo estafeta. Decisão NOVA 2026-05-11: foto+valor
  /// obrigatórios em TODOS payment_methods (cash + card + mbway) para
  /// auditoria. Chama RPC finalize_storeshopping_purchase_v2 (paralelo
  /// a v1). Returns null on success, String reason on failure.
  ///
  /// [photoStoragePath] — path no bucket 'receipts', e.g. 'receipts/<order_id>.jpg'
  /// [driverTypedTotalCents] — valor que o estafeta digitou do talão
  /// [items] — items canónicos do pedido com purchaseStatus decidido
  /// [itemsAdded] — items adicionados pelo estafeta
  Future<String?> finalizeStoreShoppingV2WithReceipt({
    required String orderId,
    required String photoStoragePath,
    required int driverTypedTotalCents,
    required List<CartItem> items,
    List<Map<String, dynamic>> itemsAdded = const [],
    int bagCount = 1,
  }) async {
    final index = _orders.indexWhere((o) => o.id == orderId);
    if (index == -1) return 'Pedido não encontrado localmente.';
    final order = _orders[index];

    if (order.serviceType != OrderServiceType.storeShopping ||
        order.isPartnerStore) {
      return 'V2 só aplica a storeShopping não-parceiro.';
    }

    // Build p_items payload aligned com order_purchase_items_v2 schema v2.
    final payload = <Map<String, dynamic>>[];
    for (final it in items) {
      final statusV2 = it.purchaseStatus == 'bought'
          ? 'purchased'
          : it.purchaseStatus == 'unavailable'
              ? 'unavailable'
              : 'purchased'; // pending shouldn't happen (allDecided gate)
      payload.add({
        'original_item_id': it.productId,
        'original_name': it.name,
        'original_price_cents': (it.price * 100).round(),
        'original_qty': it.quantity,
        'status': statusV2,
      });
    }
    for (final added in itemsAdded) {
      payload.add({
        'original_name': (added['name'] as String?) ?? '',
        'original_price_cents': 0,
        'original_qty': (added['qty'] as int?) ?? 1,
        'status': 'added',
        'actual_name': (added['name'] as String?) ?? '',
        'actual_price_cents': (added['price_base_cents'] as int?) ?? 0,
        'actual_qty': (added['qty'] as int?) ?? 1,
      });
    }

    try {
      final response = await supabase.rpc(
        'finalize_storeshopping_purchase_v2',
        params: <String, dynamic>{
          'p_order_id': orderId,
          'p_driver_typed_total_cents': driverTypedTotalCents,
          'p_receipt_photo_url': photoStoragePath,
          'p_items': payload,
          'p_bag_count': bagCount,
        },
      );

      debugPrint('[OrderStore] finalize_storeshopping_purchase_v2 OK: $response');

      // Local state: o realtime UPDATE eventualmente refletirá. Update
      // mínimo aqui para UX imediata (status onTheWay + purchase_finalized).
      order.isPurchaseFinalized = true;
      order.bagCount = bagCount;
      order.bagFee = bagCount * 0.10;
      // RPC v2 corrigida (2026-05-22): cash_total_due = final_total. Limpar
      // localmente força totalToCollectCash a usar finalTotal autoritativo
      // que chega via realtime, evitando que cashTotalDue antigo de
      // fromSupabase mostre "RECEBER €X" errado ao estafeta.
      order.cashTotalDue = null;
      // status onTheWay vem via realtime; não força aqui.
      notifyListeners();

      return null;
    } catch (e) {
      debugPrint('OrderStore: finalize_storeshopping_purchase_v2 RPC error => $e');
      return 'Erro ao finalizar compra (v2): $e';
    }
  }

  Future<bool> respondToSubstitution({
    required String orderId,
    required String productName,
    required bool approved,
  }) async {
    final index = _orders.indexWhere((o) => o.id == orderId);
    if (index == -1) return false;

    final order = _orders[index];

    final updatedMap = Map<String, bool>.from(order.substitutionResponses);
    updatedMap[productName] = approved;

    try {
      await supabase
          .from('orders')
          .update({'substitution_responses': updatedMap}).eq('id', orderId);
    } catch (e) {
      debugPrint('OrderStore.respondToSubstitution DB error => $e');
      return false;
    }

    order.substitutionResponses[productName] = approved;
    notifyListeners();
    return true;
  }

  Future<bool> processRefund(OrderModel order) async {
    final amount = order.refundAmount ?? 0;
    if (amount <= 0) return false;
    if (order.paymentIntentId == null) return false;

    try {
      await _paymentService.refund(
        paymentIntentId: order.paymentIntentId!,
        amount: amount,
      );
    } catch (e) {
      debugPrint('OrderStore.processRefund error => $e');
      return false;
    }

    try {
      await supabase.from('orders').update(
          {'payment_status': PaymentStatus.refunded.name}).eq('id', order.id);
    } catch (e) {
      debugPrint('OrderStore.processRefund DB error => $e');
      return false;
    }

    order.paymentStatus = PaymentStatus.refunded;
    notifyListeners();
    return true;
  }

  Future<bool> processExtraCharge(OrderModel order) async {
    final amount = order.extraChargeAmount ?? 0;
    if (amount <= 0) return false;

    try {
      await _paymentService.chargeExtra(amount: amount);
    } catch (e) {
      debugPrint('OrderStore.processExtraCharge error => $e');
      return false;
    }

    try {
      await supabase.from('orders').update(
          {'payment_status': PaymentStatus.paid.name}).eq('id', order.id);
    } catch (e) {
      debugPrint('OrderStore.processExtraCharge DB error => $e');
      return false;
    }

    order.paymentStatus = PaymentStatus.paid;
    notifyListeners();
    return true;
  }

  void refresh() {
    notifyListeners();
  }

  // BUG 7 (2026-05-15) — mapeamento completo por service_type. Antes
  // retornava sempre partnerRestaurant ou nonPartnerPurchase, perdendo
  // takeaway/sendPackage/carryGroceries (que eram gravados como
  // nonPartnerPurchase). Sem CHECK constraint em DB; nomes do enum vão
  // directamente para orders.order_type via .name.
  OrderType _resolveOrderType({
    required OrderServiceType serviceType,
    required bool isPartnerStore,
  }) {
    switch (serviceType) {
      case OrderServiceType.takeaway:
        return OrderType.takeaway;
      case OrderServiceType.sendPackage:
        return OrderType.sendPackage;
      case OrderServiceType.carryGroceries:
        return OrderType.carryGroceries;
      case OrderServiceType.restaurant:
        return isPartnerStore
            ? OrderType.partnerRestaurant
            : OrderType.nonPartnerPurchase;
      case OrderServiceType.storeShopping:
        return OrderType.nonPartnerPurchase;
    }
  }

  Future<bool> restaurantAcceptOrder(OrderModel order) async {
    if (!order.isPartnerStore ||
        order.serviceType != OrderServiceType.restaurant) {
      return false;
    }
    if (order.status != OrderStatus.created) return false;
    return _advanceStatus(order, OrderStatus.preparing);
  }

  Future<bool> restaurantRejectOrder(OrderModel order) async {
    if (!order.isPartnerStore ||
        order.serviceType != OrderServiceType.restaurant) {
      return false;
    }
    if (order.status != OrderStatus.created) return false;
    return _advanceStatus(order, OrderStatus.rejected);
  }

  Future<bool> restaurantMarkReady(OrderModel order) async {
    if (!order.isPartnerStore ||
        order.serviceType != OrderServiceType.restaurant) {
      return false;
    }
    if (order.status != OrderStatus.preparing) return false;
    // BR §14.9 — takeaway: cliente vai buscar, sem estafeta. Não chamar dispatch.
    // Pedido fica em `preparing`; notificação externa ao cliente por parte do
    // parceiro. Transição final (→ delivered) será feita quando o cliente
    // confirmar a recolha — fora do âmbito deste item.
    if (order.isTakeaway) {
      debugPrint(
          '[FLOW] restaurantMarkReady: takeaway — dispatch skipped (BR §14.9)');
      return true;
    }
    return _advanceStatus(order, OrderStatus.callingDriver);
  }

  List<OrderModel> partnerOrdersForRestaurant(String restaurantName) {
    final normalized = restaurantName.trim().toLowerCase();
    return _orders.where((order) {
      final vendor = order.vendorName;
      if (vendor == null) return false;
      // 2026-05-14 fix: takeaway tambem e' um pedido de partner-restaurant.
      // Antes este filtro excluia silenciosamente service_type='takeaway',
      // pelo que o parceiro nao via os pedidos takeaway no dashboard
      // (apesar do som/realtime estarem OK). Aceitar ambos os tipos.
      if (order.serviceType != OrderServiceType.restaurant &&
          order.serviceType != OrderServiceType.takeaway) {
        return false;
      }
      if (!order.isPartnerStore &&
          order.orderType != OrderType.partnerRestaurant) {
        return false;
      }
      return vendor.trim().toLowerCase() == normalized;
    }).toList()
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
  }

  Future<OrderModel> createPartnerDeliveryRequest({
    required RestaurantModel restaurant,
    required String customerName,
    required String customerPhone,
    required String deliveryAddress,
    required List<PartnerOrderLine> items,
    LatLng? dropoffLocation,
    String? notes,
  }) async {
    if (items.isEmpty) {
      throw ArgumentError(
          'Partner delivery request requires at least one item.');
    }

    final subtotal = items.fold<double>(0, (sum, line) => sum + line.lineTotal);
    if (subtotal <= 0) {
      throw ArgumentError('Subtotal must be greater than zero.');
    }

    final pickupLatLng = restaurant.location;
    double resolvedDistanceKm;
    bool isDistanceEstimated = true;
    if (pickupLatLng != null && dropoffLocation != null) {
      try {
        final apiDistance =
            await MapsService.getDistanceKm(pickupLatLng, dropoffLocation);
        if (apiDistance != null) {
          resolvedDistanceKm = apiDistance;
          isDistanceEstimated = false;
        } else {
          resolvedDistanceKm = const Distance()
              .as(LengthUnit.Kilometer, pickupLatLng, dropoffLocation);
        }
      } catch (e) {
        debugPrint(
            'OrderStore.createPartnerDeliveryRequest: MapsService error => $e');
        resolvedDistanceKm = const Distance()
            .as(LengthUnit.Kilometer, pickupLatLng, dropoffLocation);
      }
    } else {
      resolvedDistanceKm = PricingService.defaultDistanceKm;
    }

    final pricing = PricingService.calculateBreakdown(
      serviceType: OrderServiceType.restaurant,
      subtotal: subtotal,
      distanceKm: resolvedDistanceKm,
      isPartnerStore: true,
      apartmentDelivery: false,
      // Parceiro chama estafeta por conta própria (cliente comprou direto).
      // Comissão 15% (sem markup escondido) + cliente paga o pacote completo
      // em dinheiro ao estafeta. Ver business_rules.md §2.4.1.
      isPartnerSelfDispatch: true,
    );

    final orderNotes = _composePartnerOrderNotes(items: items, notes: notes);

    final order = OrderModel(
      total: pricing.customerTotal,
      serviceType: OrderServiceType.restaurant,
      subtotal: pricing.subtotal,
      deliveryFee: pricing.deliveryFee,
      serviceFee: pricing.serviceFee,
      platformCommission: pricing.platformCommission,
      driverEarnings: pricing.driverEarnings,
      distanceKm: pricing.distanceKm,
      vendorName: restaurant.name,
      pickupAddress: restaurant.address,
      pickupLocation: pickupLatLng,
      dropoffAddress: deliveryAddress,
      destination: dropoffLocation,
      customerNotes: orderNotes,
      isPartnerStore: true,
      apartmentDelivery: false,
      isDistanceEstimated: isDistanceEstimated,
      orderType: OrderType.partnerRestaurant,
      paymentMethod: PaymentMethod.cash,
      status: OrderStatus.callingDriver,
      clientPhone: customerPhone,
      customerName: customerName,
      items: items
          .map(
            (line) => CartItem(
              productId: line.product.id,
              name: line.product.name,
              price: line.product.price,
              quantity: line.quantity,
            ),
          )
          .toList(),
    );

    _orders.insert(0, order);
    notifyListeners();

    try {
      await _saveOrderToDatabase(order);
    } catch (e) {
      _orders.remove(order);
      notifyListeners();
      debugPrint('OrderStore: createPartnerDeliveryRequest failed => $e');
      rethrow;
    }

    // Partner orders start directly as callingDriver — invoke dispatch now.
    // The DB trigger is unreliable (placeholder key); Flutter is the primary path.
    unawaited(_invokeDispatch(order.id));

    return order;
  }

  List<ChatMessage> messagesForOrder(String orderId) {
    return List.unmodifiable(_chatMessages[orderId] ?? const <ChatMessage>[]);
  }

  void sendChatMessage({
    required String orderId,
    required ChatSenderType senderType,
    required String message,
  }) {
    final trimmed = message.trim();
    if (trimmed.isEmpty) return;

    final messages = _chatMessages.putIfAbsent(orderId, () => <ChatMessage>[]);
    messages.add(
      ChatMessage(
        id: DateTime.now().microsecondsSinceEpoch.toString(),
        orderId: orderId,
        senderType: senderType,
        message: trimmed,
        timestamp: DateTime.now(),
      ),
    );
    notifyListeners();
  }

  RatingModel? ratingForOrder(String orderId) {
    try {
      return _ratings.firstWhere((rating) => rating.orderId == orderId);
    } catch (_) {
      return null;
    }
  }

  void submitRating({
    required String orderId,
    required String driverId,
    required int rating,
    String? comment,
  }) {
    _ratings.removeWhere((existing) => existing.orderId == orderId);
    _ratings.add(
      RatingModel(
        orderId: orderId,
        driverId: driverId,
        rating: rating,
        comment: comment?.trim().isEmpty == true ? null : comment?.trim(),
      ),
    );
    notifyListeners();
  }

  void _handlePartnerPreparationFlow(OrderModel order) {
    if (!_isPartnerRestaurantOrder(order)) {
      _cancelPartnerPreparationTimer(order.id);
      return;
    }

    if (order.status == OrderStatus.preparing) {
      _schedulePartnerPreparationTimer(order);
    } else {
      _cancelPartnerPreparationTimer(order.id);
    }
  }

  void _schedulePartnerPreparationTimer(OrderModel order) {
    _cancelPartnerPreparationTimer(order.id);
    _partnerPreparationTimers[order.id] = Timer(const Duration(minutes: 5), () {
      if (!_orders.any((o) => o.id == order.id)) return;
      if (order.status != OrderStatus.preparing) return;
      _advanceStatus(order, OrderStatus.callingDriver);
    });
  }

  void _cancelPartnerPreparationTimer(String orderId) {
    _partnerPreparationTimers.remove(orderId)?.cancel();
  }

  // ── Stream listeners ──────────────────────────────────────────────────────

  /// General unfiltered stream — used for clients and restaurant partners.
  /// Cancelled and replaced by [_subscribeToDriverStreams] once a valid
  /// driverId is known, and re-started by [_revertToGeneralStream] on logout.
  ///
  /// Idempotent: if a general subscription is already active the call is a
  /// no-op. Callers that intentionally want to replace it must set
  /// `_ordersSubscription = null` (after cancelling) before calling.
  void _subscribeToOrders() {
    if (_ordersSubscription != null) {
      debugPrint('[OrderStore] cancelling previous general subscription before re-subscribe');
      _ordersSubscription?.cancel();
      _ordersSubscription = null;
    }
    final uid = _authStore?.userId;
    final isClient = _authStore?.currentClient != null;

    // Cliente sem uid → NÃO subscrever. Sem filtro `user_id`, qualquer tick
    // vazio do RLS varre `_orders` e provoca loading infinito ao reentrar
    // no tab Pedidos. `updateAuthStore` chama `_subscribeToOrders` outra vez
    // assim que a sessão carrega — não há risco de ficarmos por subscrever.
    if (isClient && uid == null) {
      debugPrint('[OrderStore] skipping subscribe: client has no uid yet');
      return;
    }
    debugPrint(
        '[OrderStore] general subscription started (isClient=$isClient uid=${uid ?? "n/a"})');
    // 2026-05-21 — A8: ao (re)subscrever stream a rede está OK → drena fila offline.
    unawaited(_drainOfflineStatusQueue());
    _ordersSubscription = (isClient
            ? supabase
                .from('orders')
                .stream(primaryKey: ['id']).eq('user_id', uid!)
            : supabase.from('orders').stream(primaryKey: ['id']))
        .order('created_at', ascending: false)
        .listen(
      (rows) {
        debugPrint(
            '[OrderStore] orders received=${rows.length} (general stream)');
        // Empty-fire guards (anti-wipe):
        //  1. JWT ainda não estabelecido → ignorar.
        //  2. Já temos pedidos cacheados → ignorar tick vazio (provável
        //     reconnect transitório). Próximo tick confirma se de facto
        //     a lista deve esvaziar.
        if (rows.isEmpty) {
          if (supabase.auth.currentUser == null) return;
          if (_orders.isNotEmpty) {
            debugPrint(
                '[OrderStore] empty tick ignored — keeping ${_orders.length} cached orders');
            return;
          }
        }
        _orders.clear();
        for (final data in rows) {
          _orders.add(OrderModel.fromSupabase(data));
        }
        _handleSoundForCurrentDriver();
        notifyListeners();
      },
      onError: (Object e) {
        debugPrint(
            '[OrderStore] general stream error: $e — reconnecting in 5s');
        _ordersSubscription = null;
        Future.delayed(const Duration(seconds: 5), _subscribeToOrders);
      },
      onDone: () {
        debugPrint('[OrderStore] general stream closed — reconnecting in 5s');
        _ordersSubscription = null;
        Future.delayed(const Duration(seconds: 5), _subscribeToOrders);
      },
    );

    // Client notify channel — catches UPDATE events missed by .stream().eq()
    // during NULL→value transitions or brief reconnect gaps.
    if (isClient && uid != null) {
      _clientOrdersChannel?.unsubscribe();
      _clientOrdersChannel =
          supabase.channel('client_orders_$uid').onPostgresChanges(
                event: PostgresChangeEvent.update,
                schema: 'public',
                table: 'orders',
                callback: (payload) {
                  final rec = payload.newRecord;
                  if (rec.isEmpty || rec['user_id'] != uid) return;
                  final orderId = rec['id'] as String?;
                  if (orderId == null) return;
                  final updated = OrderModel.fromSupabase(rec);
                  final idx = _orders.indexWhere((o) => o.id == orderId);
                  if (idx >= 0) {
                    _orders[idx] = updated;
                  } else {
                    _orders.insert(0, updated);
                  }
                  debugPrint(
                      '[OrderStore] client notify: order=$orderId status=${updated.status}');
                  notifyListeners();
                },
              )..subscribe();
    }
  }

  /// Driver-specific filtered streams. Called the moment a real driverId is
  /// available. Cancels the general stream so only driver-relevant rows arrive.
  ///
  /// Two subscriptions are required because [SupabaseStreamBuilder] does not
  /// support OR filters — one stream covers pending offers, the other covers
  /// orders already accepted/active.
  void _subscribeToDriverStreams(String driverId) {
    // Cancel everything that was running before and null the handles so the
    // idempotency guard in _subscribeToOrders knows the slot is free on a
    // future revert.
    _driverOffersSubscription?.cancel();
    _driverActiveSubscription?.cancel();
    _ordersSubscription?.cancel();
    _driverOfferNotifyChannel?.unsubscribe();
    _driverActiveNotifyChannel?.unsubscribe();
    _clientOrdersChannel?.unsubscribe();
    _driverOffersSubscription = null;
    _driverActiveSubscription = null;
    _ordersSubscription = null;
    _driverOfferNotifyChannel = null;
    _driverActiveNotifyChannel = null;
    _clientOrdersChannel = null;

    // Clear stale data so the UI starts fresh from DB state.
    _orders.clear();
    _driverOfferIds.clear();
    _driverActiveIds.clear();

    debugPrint('[OrderStore] driverId=$driverId');

    // ── 1. Pending-offer stream ────────────────────────────────────────────
    debugPrint(
        '[OrderStore] subscription started → orders.eq(current_driver_offer_id, $driverId)');
    _driverOffersSubscription = supabase
        .from('orders')
        .stream(primaryKey: ['id'])
        .eq('current_driver_offer_id', driverId)
        .order('created_at', ascending: false)
        .listen(
          (rows) {
            debugPrint(
                '[OrderStore] orders received=${rows.length} (offers stream, driverId=$driverId)');
            _mergeDriverRows(rows, _driverOfferIds);
          },
          onError: (Object e) {
            debugPrint(
                '[OrderStore] offers stream error: $e — reconnecting in 5s');
            _scheduleDriverReconnect();
          },
          onDone: () {
            debugPrint(
                '[OrderStore] offers stream closed — reconnecting in 5s');
            _scheduleDriverReconnect();
          },
        );

    // ── 2. Offer notify channel (catches NULL→driverId UPDATE transitions) ──
    // .stream().eq() only evaluates the OLD record for UPDATE events, so it
    // misses the moment dispatch sets current_driver_offer_id for the first
    // time. This channel has NO server-side filter — it receives every UPDATE
    // on orders and checks client-side, guaranteeing delivery.
    _driverOfferNotifyChannel?.unsubscribe();
    _driverOfferNotifyChannel =
        supabase.channel('driver_offer_notify_$driverId').onPostgresChanges(
              event: PostgresChangeEvent.update,
              schema: 'public',
              table: 'orders',
              callback: (payload) {
                final rec = payload.newRecord;
                if (rec.isEmpty) return;
                final offerId = rec['current_driver_offer_id'] as String?;
                final orderId = rec['id'] as String?;
                if (orderId == null) return;
                if (offerId == driverId) {
                  debugPrint(
                      '[OrderStore] onPostgresChanges: offer→$driverId order=$orderId');
                  _mergeDriverRows([rec], _driverOfferIds);
                  // Exec3 PIVOT (2026-05-24): full-screen dialog em vez de overlay
                  // system_alert (bloqueado por Android 14+/16 em bg). FGS mantém
                  // o Flutter engine activo; navigatorKey empurra o dialog em <500ms.
                  debugPrint('[BORA-OFFER] order_store realtime UPDATE → gate.present order=$orderId');
                  if (!_dismissedOrderIds.contains(orderId)) {
                    // Exec6 GATE (2026-05-25) — gate central decide qual UI.
                    OfferPresentationGate.present(
                      orderId: orderId,
                      vendorName: (rec['restaurant_name'] as String?) ?? 'Pedido novo',
                      total: (rec['total'] as num?)?.toStringAsFixed(2) ?? '0.00',
                      distanceKm: (rec['distance_km'] as num?)?.toStringAsFixed(1) ?? '0',
                      driverEarnings: (rec['driver_earnings'] as num?)?.toStringAsFixed(2) ?? '0.00',
                      dropoffAddress: (rec['dropoff_address'] as String?) ?? '',
                    ).ignore();
                  }
                } else if (_driverOfferIds.contains(orderId)) {
                  // Offer revoked — remove only this order, not all pending offers.
                  debugPrint(
                      '[OrderStore] onPostgresChanges: offer revoked order=$orderId');
                  _driverOfferIds.remove(orderId);
                  _orders.removeWhere((o) => o.id == orderId);
                  // 2026-05-20 — cancela a notificação persistente estilo chamada
                  // (FLAG_INSISTENT em loop) assim que a oferta expira/é revogada.
                  unawaited(cancelDriverOfferNotification(orderId));
                  // Exec6.5 — marca handled no gate para impedir re-trigger
                  // (ex: novo evento realtime do mesmo orderId que ressuscite UI).
                  OfferPresentationGate.markActionCompleted(orderId);
                  notifyListeners();
                }
              },
            )..subscribe();

    // ── 3. Active-delivery stream ──────────────────────────────────────────
    debugPrint(
        '[OrderStore] subscription started → orders.eq(assigned_driver_id, $driverId)');
    _driverActiveSubscription = supabase
        .from('orders')
        .stream(primaryKey: ['id'])
        .eq('assigned_driver_id', driverId)
        .order('created_at', ascending: false)
        .listen(
          (rows) {
            debugPrint(
                '[OrderStore] orders received=${rows.length} (active stream, driverId=$driverId)');
            _mergeDriverRows(rows, _driverActiveIds);
          },
          onError: (Object e) {
            debugPrint(
                '[OrderStore] active stream error: $e — reconnecting in 5s');
            _scheduleDriverReconnect();
          },
          onDone: () {
            debugPrint(
                '[OrderStore] active stream closed — reconnecting in 5s');
            _scheduleDriverReconnect();
          },
        );

    // ── 4. Active-delivery notify channel ─────────────────────────────────
    // .stream().eq() evaluates the OLD record for UPDATE events, so it misses
    // the NULL → driverId transition when assigned_driver_id is first set.
    // This unfiltered channel catches every orders UPDATE and merges rows
    // assigned to this driver, guaranteeing myOrders updates immediately
    // after acceptOrder() writes to the DB.
    _driverActiveNotifyChannel?.unsubscribe();
    _driverActiveNotifyChannel =
        supabase.channel('driver_active_notify_$driverId').onPostgresChanges(
              event: PostgresChangeEvent.update,
              schema: 'public',
              table: 'orders',
              callback: (payload) {
                final rec = payload.newRecord;
                if (rec.isEmpty) return;
                final assignedId = rec['assigned_driver_id'] as String?;
                final orderId = rec['id'] as String?;
                if (orderId == null) return;
                if (assignedId == driverId) {
                  debugPrint(
                      '[OrderStore] active notify: assigned→$driverId order=$orderId');
                  _mergeDriverRows([rec], _driverActiveIds);

                  // BUG #5 (2026-05-13) — quando pedido chega a estado
                  // terminal via Realtime (delivered/cancelled/rejected),
                  // libertar activeAssignments local. Sem isto,
                  // driver_store.toggleAvailability bloqueia o toggle
                  // offline porque activeAssignments fica stale.
                  // finishOrder local já trata o caso síncrono — este
                  // path cobre updates externos (admin, trigger, outro
                  // device).
                  final status = rec['status'] as String?;
                  const terminal = {'delivered', 'cancelled', 'rejected'};
                  if (status != null && terminal.contains(status)) {
                    _driverStore.releaseOrderForDriver(driverId, orderId);
                    _driverStore.stopTracking(orderId);
                  }
                } else if (_driverActiveIds.contains(orderId)) {
                  debugPrint(
                      '[OrderStore] active notify: assignment removed order=$orderId');
                  _driverActiveIds.remove(orderId);
                  _orders.removeWhere((o) => o.id == orderId);
                  // BUG #5 (2026-05-13) — assignment_driver_id foi anulado
                  // server-side; libertar a assignment local também.
                  _driverStore.releaseOrderForDriver(driverId, orderId);
                  _driverStore.stopTracking(orderId);
                  notifyListeners();
                }
              },
            )..subscribe();
  }

  void _scheduleDriverReconnect() {
    if (_driverReconnectScheduled) return;
    _driverReconnectScheduled = true;
    Future.delayed(const Duration(seconds: 5), () {
      _driverReconnectScheduled = false;
      final id = _cachedDriverId;
      if (id.isNotEmpty && id != 'driver-main') {
        _subscribeToDriverStreams(id);
      }
    });
  }

  /// Merges a stream emission into [_orders] using [trackedIds] to remove
  /// rows that were in the previous emission but are no longer present
  /// (e.g. offer expired and was reassigned to another driver).
  void _mergeDriverRows(
    List<Map<String, dynamic>> rows,
    Set<String> trackedIds,
  ) {
    // Remove rows that belonged to this stream in the last emission.
    _orders.removeWhere((o) => trackedIds.contains(o.id));
    trackedIds.clear();

    for (final data in rows) {
      final order = OrderModel.fromSupabase(data);
      trackedIds.add(order.id);

      // If this order was previously dismissed (driver rejected it) but the
      // backend has now issued a NEW offer (different driver_offer_expires_at),
      // remove the dismissed flag so the dialog can fire again.
      // This is what enables the A → B → A rotation: when A re-receives the
      // order after B rejects, the new expiry timestamp clears A's dismiss flag.
      if (_dismissedOrderIds.contains(order.id)) {
        final storedIdx = _orders.indexWhere((o) => o.id == order.id);
        final oldExpiry =
            storedIdx >= 0 ? _orders[storedIdx].driverOfferExpiresAt : null;
        final newExpiry = order.driverOfferExpiresAt;
        if (newExpiry != null && newExpiry != oldExpiry) {
          _dismissedOrderIds.remove(order.id);
          debugPrint(
            '[OrderStore] un-dismissed order=${order.id} — '
            'new offer expires=$newExpiry (was $oldExpiry)',
          );
        }
      }

      final idx = _orders.indexWhere((o) => o.id == order.id);
      if (idx >= 0) {
        _orders[idx] = order;
      } else {
        _orders.add(order);
      }
    }

    _handleSoundForCurrentDriver();
    notifyListeners();
  }

  // ── Sound ──────────────────────────────────────────────────────────────────

  void _handleSoundForCurrentDriver() {
    if (!isDriverAvailable) return;

    final driverId = _currentDriverId;
    final hasAvailable = driverId.isNotEmpty &&
        _orders.any((o) =>
            o.status == OrderStatus.callingDriver &&
            o.currentDriverOfferId == driverId);

    debugPrint(
        '[OrderStore] _handleSoundForCurrentDriver: hasAvailable=$hasAvailable driverId=$driverId');
  }

  // ── Lifecycle ─────────────────────────────────────────────────────────────

  @override
  void dispose() {
    _ordersSubscription?.cancel();
    _driverOffersSubscription?.cancel();
    _driverActiveSubscription?.cancel();
    _driverOfferNotifyChannel?.unsubscribe();
    _driverActiveNotifyChannel?.unsubscribe();
    _fallbackRefreshTimer?.cancel();
    _ordersSubscription = null;
    _driverOffersSubscription = null;
    _driverActiveSubscription = null;
    _driverOfferNotifyChannel = null;
    _driverActiveNotifyChannel = null;
    _fallbackRefreshTimer = null;
    _driverLocationService.dispose();
    for (final timer in _partnerPreparationTimers.values) {
      timer.cancel();
    }
    _partnerPreparationTimers.clear();
    super.dispose();
  }

  bool _isPartnerRestaurantOrder(OrderModel order) {
    return order.serviceType == OrderServiceType.restaurant &&
        order.isPartnerStore;
  }

  double _resolveDistance({
    LatLng? pickup,
    required LatLng destination,
    double? providedDistance,
  }) {
    if (providedDistance != null && providedDistance > 0) {
      return providedDistance;
    }
    if (pickup != null) {
      return DistanceService.calculateDistanceKm(
        pickup.latitude,
        pickup.longitude,
        destination.latitude,
        destination.longitude,
      );
    }
    return PricingService.defaultDistanceKm;
  }

  String _composePartnerOrderNotes({
    required List<PartnerOrderLine> items,
    String? notes,
  }) {
    final buffer = StringBuffer('Itens do pedido:\n');
    for (final line in items) {
      final lineTotal = _roundCurrency(line.lineTotal);
      buffer.writeln(
          '- ${line.quantity}× ${line.product.name} (€${line.product.price.toStringAsFixed(2)} cada) • €${lineTotal.toStringAsFixed(2)}');
    }
    final normalizedNotes = notes?.trim();
    if (normalizedNotes != null && normalizedNotes.isNotEmpty) {
      buffer
        ..writeln()
        ..writeln('Observações: $normalizedNotes');
    }
    return buffer.toString().trim();
  }

  double _roundCurrency(double value) => (value * 100).roundToDouble() / 100;

  static const double _deliveryBasePrice = 2.50;
  static const double _deliveryBaseKm = 4.0;
  static const double _deliveryExtraPerKm = 0.50;

  double _computeDeliveryPrice(double km) {
    final extra = km > _deliveryBaseKm
        ? (km - _deliveryBaseKm) * _deliveryExtraPerKm
        : 0.0;
    return double.parse((_deliveryBasePrice + extra).toStringAsFixed(2));
  }

  /// Calls the dispatch-engine Edge Function for [orderId].
  ///
  /// This is the PRIMARY dispatch trigger — more reliable than the DB trigger
  /// because it does not depend on the service-role-key being configured in
  /// the SQL trigger body. The Edge Function itself uses env-var credentials
  /// to access the DB; the caller only needs a valid Supabase session JWT,
  /// which the Flutter Supabase client attaches automatically.
  Future<void> _invokeDispatch(String orderId) async {
    // ── DEBOUNCE: ignore bursts within 2 seconds per order ────────────────
    final now = DateTime.now();
    final last = _lastDispatchCall[orderId];
    if (last != null && now.difference(last).inMilliseconds < 2000) {
      debugPrint('[DISPATCH] debounced order=$orderId (< 2s since last call)');
      return;
    }
    _lastDispatchCall[orderId] = now;

    // ── SERVER-TRUSTED DISPATCH GATE ──────────────────────────────────────
    // Re-fetch the order row from the DB (never trust local state, cache or
    // client flags). Dispatch is only allowed when ONE of the following is
    // true, read live from Postgres:
    //   1. payment_status == 'paid'   (stripe-webhook handles card + MBWay)
    //   2. payment_method == 'cash'   (COD partner orders — no server confirmation path)
    // Any other combination blocks the Edge Function invocation entirely.
    try {
      final row = await supabase
          .from('orders')
          .select('payment_status, payment_method')
          .eq('id', orderId)
          .maybeSingle();

      if (row == null) {
        debugPrint('⛔ [DISPATCH] BLOCKED order=$orderId — row not found in DB');
        return;
      }

      final paymentStatus = row['payment_status'] as String?;
      final paymentMethod = row['payment_method'] as String?;
      final isPaid = paymentStatus == 'paid';
      final isCash = paymentMethod == 'cash';

      if (!isPaid && !isCash) {
        debugPrint('⛔ [DISPATCH] BLOCKED order=$orderId — unconfirmed payment '
            '(db.payment_status=$paymentStatus db.payment_method=$paymentMethod)');
        return;
      }

      debugPrint(
          '[DISPATCH] gate OK order=$orderId status=$paymentStatus method=$paymentMethod');
    } catch (e) {
      debugPrint(
          '⛔ [DISPATCH] BLOCKED order=$orderId — gate re-fetch failed: $e');
      return;
    }

    // SYSTEM-LEVEL: dispatch must ALWAYS run, regardless of auth session state.
    // The Edge Function is deployed with --no-verify-jwt and uses its own
    // SUPABASE_SERVICE_ROLE_KEY env-var — no client JWT required.
    try {
      debugPrint('[DISPATCH] invoking for order=$orderId');
      await supabase.functions.invoke(
        'dispatch-engine',
        body: {'orderId': orderId},
      );
      debugPrint('[DISPATCH] invoke OK for order=$orderId');
    } catch (e) {
      debugPrint('[DISPATCH] invoke error for order=$orderId: $e');
    }
  }

  /// Records how many carrier bags the driver used for a market order.
  /// Calls the SECURITY DEFINER RPC `update_bag_count_bypass` which bypasses
  /// the `enforce_financial_immutability` trigger via a session GUC and
  /// computes bag_fee server-side from platform_settings.
  /// Sends a push to the client when count > 0 (fire-and-forget).
  ///
  /// Replaces the old direct UPDATE which failed silently against the
  /// financial immutability trigger (BUG 27).
  Future<void> updateBagCount(String orderId, int count) async {
    try {
      final response = await supabase.rpc(
        'update_bag_count_bypass',
        params: {'p_order_id': orderId, 'p_count': count},
      );
      int finalCount = count;
      double finalFee = _roundCurrency(count * 0.10);
      if (response is Map) {
        final respCount = (response['bag_count'] as num?)?.toInt();
        if (respCount != null) finalCount = respCount;
        final cents = (response['bag_fee_cents'] as num?)?.toInt();
        if (cents != null) finalFee = cents / 100.0;
      }
      final idx = _orders.indexWhere((o) => o.id == orderId);
      String? clientId;
      if (idx != -1) {
        _orders[idx].bagCount = finalCount;
        _orders[idx].bagFee = finalFee;
        clientId = _orders[idx].userId;
        notifyListeners();
      }
      if (finalCount > 0 && clientId != null && clientId.isNotEmpty) {
        NotificationService.instance.notifyClientBagCount(
          clientId: clientId,
          orderId: orderId,
          bagCount: finalCount,
          bagFee: finalFee,
        ).ignore();
      }
    } catch (e) {
      debugPrint('OrderStore.updateBagCount error: $e');
    }
  }

  Future<bool> updateOrderItems(
    String orderId,
    List<CartItem> items, {
    int bagCount = 0,
    double bagFee = 0,
  }) async {
    try {
      await supabase.from('orders').update({
        'items': items.map((i) => i.toJson()).toList(),
        'bag_count': bagCount,
        'bag_fee': bagFee,
      }).eq('id', orderId);
      // Update local order so UI reflects the change immediately.
      final idx = _orders.indexWhere((o) => o.id == orderId);
      if (idx != -1) {
        _orders[idx].items = items;
        _orders[idx].bagCount = bagCount;
        _orders[idx].bagFee = bagFee;
        notifyListeners();
      }
      return true;
    } catch (e) {
      debugPrint('[FLOW] updateOrderItems error: $e');
      return false;
    }
  }

  Future<void> _saveOrderToDatabase(OrderModel order) async {
    final data = order.toSupabase();
    debugPrint('[FLOW] _saveOrderToDatabase: id=${order.id}');
    try {
      await supabase.from('orders').insert(data);
      debugPrint('[FLOW] _saveOrderToDatabase: OK');
    } catch (e, stack) {
      debugPrint('[FLOW] _saveOrderToDatabase: ERROR => $e');
      debugPrint('[FLOW] _saveOrderToDatabase: stack => $stack');
      rethrow;
    }
  }

  Future<bool> _updateOrderStatusInDatabase(
    OrderModel order,
    OrderStatus newStatus, {
    DateTime? driverOfferExpiresAt,
  }) async {
    final payload = <String, dynamic>{'status': newStatus.name};
    if (driverOfferExpiresAt != null) {
      payload['driver_offer_expires_at'] =
          driverOfferExpiresAt.toIso8601String();
    }
    debugPrint('[FLOW] _updateStatusDB: id=${order.id} payload=$payload');
    _lastUpdateError = null;
    try {
      await supabase.from('orders').update(payload).eq('id', order.id);
      debugPrint('[FLOW] _updateStatusDB: OK');
      return true;
    } catch (e) {
      _lastUpdateError = e.toString();
      debugPrint('[FLOW] _updateStatusDB: EXCEPTION => $e');
      // If failure was caused by driver_offer_expires_at column, retry status-only.
      if (driverOfferExpiresAt != null) {
        debugPrint('[FLOW] _updateStatusDB: retrying status-only');
        try {
          await supabase
              .from('orders')
              .update({'status': newStatus.name}).eq('id', order.id);
          debugPrint('[FLOW] _updateStatusDB: retry OK');
          return true;
        } catch (e2) {
          _lastUpdateError = e2.toString();
          debugPrint('[FLOW] _updateStatusDB: retry FAILED => $e2');
        }
      }
      return false;
    }
  }

  Future<bool> _acceptOrderInDatabase(
    OrderModel order, {
    required String driverId,
    String? driverPhone,
  }) async {
    try {
      // Optimistic lock: only succeed if this driver currently holds the offer.
      // Clears current_driver_offer_id to prevent duplicate dispatch.
      final result = await supabase
          .from('orders')
          .update({
            'status': OrderStatus.driverAccepted.name,
            'assigned_driver_id': driverId,
            'current_driver_offer_id': null,
            'driver_offer_expires_at': null,
            'driver_phone': driverPhone,
          })
          .eq('id', order.id)
          .eq('current_driver_offer_id', driverId)
          .select();

      if (result.isEmpty) {
        debugPrint(
            'OrderStore: _acceptOrderInDatabase — offer no longer valid (lost race) order=${order.id}');
        return false;
      }
      return true;
    } catch (e) {
      debugPrint('OrderStore: _acceptOrderInDatabase error => $e');
      return false;
    }
  }
}

/// Result of a client-initiated cancellation (BR §8.3).
class ClientCancelResult {
  const ClientCancelResult._({
    required this.success,
    this.feeEur,
    this.error,
  });

  factory ClientCancelResult.success({double? feeEur}) =>
      ClientCancelResult._(success: true, feeEur: feeEur);

  factory ClientCancelResult.failure(String error) =>
      ClientCancelResult._(success: false, error: error);

  final bool success;
  final double? feeEur;
  final String? error;
}
