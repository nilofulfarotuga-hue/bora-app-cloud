import 'dart:async';

import 'package:flutter/foundation.dart' show kIsWeb;
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

class OrderStore extends ChangeNotifier {
  final supabase = Supabase.instance.client;

  StreamSubscription<List<Map<String, dynamic>>>? _ordersSubscription;

  // Driver-specific filtered streams (started only after real driverId is known).
  // Two streams are needed because a driver needs to see:
  //   - Pending offers   : current_driver_offer_id = driverId
  //   - Active deliveries: assigned_driver_id       = driverId
  StreamSubscription<List<Map<String, dynamic>>>? _driverOffersSubscription;
  StreamSubscription<List<Map<String, dynamic>>>? _driverActiveSubscription;

  // Tracks which order IDs each driver stream last delivered so we can
  // remove stale rows when the stream re-emits a shorter list.
  final Set<String> _driverOfferIds  = {};
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

  static const Map<OrderStatus, Set<OrderStatus>> _statusFlow = {
    OrderStatus.created: {
      OrderStatus.preparing,
      OrderStatus.rejected,
    },
    OrderStatus.preparing: {OrderStatus.callingDriver},
    OrderStatus.callingDriver: {OrderStatus.driverAccepted},
    OrderStatus.driverAccepted: {OrderStatus.pickedUp},
    OrderStatus.pickedUp: {OrderStatus.onTheWay},
    OrderStatus.onTheWay: {OrderStatus.delivered},
    OrderStatus.delivered: <OrderStatus>{},
    OrderStatus.rejected: <OrderStatus>{},
  };

  OrderStore({
    required DriverStore driverStore,
  }) : _driverStore = driverStore {
    _bootstrap();
  }

  void _bootstrap() {
    _subscribeToOrders();
  }

  Future<void> loadOrders() async {
    if (_authStore == null) return;

    try {
      final userId = _authStore?.userId;
      final isClient = _authStore?.currentClient != null;

      final response = await (isClient && userId != null
              ? supabase
                  .from('orders')
                  .select()
                  .eq('user_id', userId)
              : supabase.from('orders').select())
          .order('created_at', ascending: false);

      _orders.clear();
      for (final data in response) {
        final order = OrderModel.fromSupabase(data);
        _orders.add(order);
      }
      notifyListeners();
    } catch (e) {
      debugPrint('OrderStore: loadOrders error => $e');
    }
  }

  DriverStore _driverStore;
  RestaurantStore? _restaurantStore;
  AuthStore? _authStore;
  final PaymentService _paymentService = PaymentService();
  final DriverLocationService _driverLocationService = DriverLocationService();


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

  /// Order IDs locally dismissed by this driver (reject or cancel).
  final Set<String> _dismissedOrderIds = {};

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
    return _orders
        .where((o) => o.clientPhone == phone)
        .toList()
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
        debugPrint('[OrderStore] isOnline changed → $newIsOnline — notifying listeners');
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
    _driverOffersSubscription = null;
    _driverActiveSubscription = null;
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

  @override
  void notifyListeners() {
    super.notifyListeners();
    _restaurantStore?.syncPartnerOrders(_orders);
  }

  void toggleDriverAvailability(bool value) {
    final success = _driverStore.toggleAvailability(_currentDriverId, value);
    if (success) {
      notifyListeners();
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
  }) async {
    double? googleDistance;
    if (pickupLocation != null) {
      try {
        googleDistance = await MapsService.getDistanceKm(pickupLocation, destination);
      } catch (e) {
        debugPrint('OrderStore.createOrder: MapsService.getDistanceKm error => $e');
      }
    }
    final isDistanceEstimated = googleDistance == null;

    final resolvedDistance = _resolveDistance(
      pickup: pickupLocation,
      destination: destination,
      providedDistance: googleDistance ?? distanceKm,
    );

    final deliveryPrice = _computeDeliveryPrice(resolvedDistance);

    final pricing = PricingService.calculateBreakdown(
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
            name: item.name,
            price: item.price,
            quantity: item.quantity,
          ),
        )
        .toList();

    final order = OrderModel(
      total: pricing.customerTotal,
      serviceType: serviceType,
      subtotal: pricing.subtotal,
      deliveryFee: pricing.deliveryFee,
      serviceFee: pricing.serviceFee,
      platformCommission: pricing.platformCommission,
      driverEarnings: pricing.driverEarnings,
      distanceKm: pricing.distanceKm,
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
      userId: _authStore?.userId,
      paymentBufferTotal: !isPartnerStore
          ? PricingService.calculateBufferedTotal(pricing.subtotal)
              + pricing.deliveryFee
              + pricing.serviceFee
          : pricing.customerTotal,
    );

    if (isPartnerStore && serviceType == OrderServiceType.restaurant) {
      final restaurant = _restaurantStore?.restaurantByName(vendorName);
      if (restaurant != null && !restaurant.isOnline) {
        return false;
      }
    }

    // ── Cash limit guard (UX only — backend trigger is the source of truth) ─
    if (paymentMethod == PaymentMethod.cash &&
        order.paymentBufferTotal > BRBusiness.CASH_MAX_ORDER_VALUE_EUR) {
      debugPrint('[FLOW] createOrder BLOCKED — cash limit exceeded '
          '(total=${order.paymentBufferTotal} max=${BRBusiness.CASH_MAX_ORDER_VALUE_EUR})');
      return false;
    }

    debugPrint('[FLOW] createOrder START id=${order.id} type=${order.serviceType.name}');

    _orders.insert(0, order);
    notifyListeners();

    try {
      await _saveOrderToDatabase(order);
      debugPrint('[FLOW] createOrder: DB insert OK');

      if (!_orders.any((o) => o.id == order.id)) {
        debugPrint('[FLOW] createOrder: re-inserting after concurrent clear');
        _orders.insert(0, order);
        notifyListeners();
      }

      // NOTE: MBWay confirmation is server-only. The client does NOT trigger
      // confirm-mbway-payment from here — that would make the "server-trusted"
      // path trivially forgeable. A real MBWay provider webhook (or a manual
      // operator call) is the only authorised way to flip payment_status.
      // Until that integration exists, MBWay orders block at the payment gate
      // by design (safe default).

      await _simulateRestaurantFlow(order);
      debugPrint('[FLOW] createOrder DONE id=${order.id} finalStatus=${order.status.name}');
      return true;
    } catch (e) {
      _orders.remove(order);
      notifyListeners();
      debugPrint('[FLOW] createOrder FAILED: $e');
      return false;
    }
  }

  Future<void> _simulateRestaurantFlow(OrderModel order) async {
  debugPrint('[FLOW] _simulateFlow START id=${order.id} type=${order.serviceType.name} partner=${order.isPartnerStore} status=${order.status.name}');

  final isPartnerRestaurantOrder =
      order.serviceType == OrderServiceType.restaurant &&
          order.isPartnerStore;

  if (isPartnerRestaurantOrder) {
    debugPrint('[FLOW] _simulateFlow: partner restaurant — waiting for dashboard');
    return;
  }

  final requiresPreparation =
      order.serviceType == OrderServiceType.restaurant ||
          (order.serviceType == OrderServiceType.storeShopping &&
              order.isPartnerStore);

  debugPrint('[FLOW] _simulateFlow: requiresPreparation=$requiresPreparation');

  final progressed = await _advanceStatus(order, OrderStatus.preparing);
  debugPrint('[FLOW] _simulateFlow: preparing result=$progressed status=${order.status.name}');
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

  debugPrint('[FLOW] _simulateFlow: advancing to callingDriver (localStatus=${order.status.name})');

  // ── Payment gate — payment MUST be confirmed server-side before dispatch.
  // Card  → Stripe webhook flips DB row to paid.
  // MBWay → confirm-mbway-payment Edge Function flips DB row to paid.
  // The client NEVER marks it paid itself.
  final requiresServerConfirmation =
      (order.paymentMethod == PaymentMethod.card && !kIsWeb) ||
          order.paymentMethod == PaymentMethod.mbway;

  if (requiresServerConfirmation) {
    debugPrint('[FLOW] waiting for server payment confirmation id=${order.id} method=${order.paymentMethod.name}');
    final confirmed = await _waitForPaymentConfirmation(order);
    if (!confirmed) {
      debugPrint('⛔ Dispatch bloqueado: pagamento não confirmado (id=${order.id} status=${order.paymentStatus.name})');
      return;
    }
    debugPrint('[FLOW] payment confirmed server-side — proceeding to dispatch');
  }

  final reached = await _advanceStatus(order, OrderStatus.callingDriver);

  debugPrint('[FLOW] _simulateFlow: callingDriver result=$reached');

  if (!reached) {
    debugPrint('[FLOW] ERROR: failed to reach callingDriver — dispatch will NOT run');
  }
}

  /// Polls `orders.payment_status` until the Stripe webhook flips it to
  /// `paid` (success) or `failed` (abort). Returns false on timeout so the
  /// dispatch gate can block the order from ever reaching `callingDriver`.
  Future<bool> _waitForPaymentConfirmation(
    OrderModel order, {
    Duration timeout = const Duration(seconds: 30),
    Duration interval = const Duration(seconds: 1),
  }) async {
    final deadline = DateTime.now().add(timeout);
    while (DateTime.now().isBefore(deadline)) {
      try {
        final row = await Supabase.instance.client
            .from('orders')
            .select('payment_status')
            .eq('id', order.id)
            .maybeSingle();
        final status = row?['payment_status'] as String?;
        debugPrint('[FLOW] _waitForPaymentConfirmation: db status=$status');
        if (status == 'paid') {
          order.paymentStatus = PaymentStatus.paid;
          notifyListeners();
          return true;
        }
        if (status == 'failed') {
          order.paymentStatus = PaymentStatus.failed;
          notifyListeners();
          return false;
        }
      } catch (e) {
        debugPrint('[FLOW] _waitForPaymentConfirmation poll error: $e');
      }
      await Future.delayed(interval);
    }
    debugPrint('[FLOW] _waitForPaymentConfirmation: TIMEOUT id=${order.id}');
    return false;
  }

  Future<bool> _advanceStatus(
      OrderModel order, OrderStatus targetStatus) async {
    debugPrint('[FLOW] _advanceStatus: ${order.status.name} → ${targetStatus.name} id=${order.id}');

    final inList = _orders.any((o) => o.id == order.id);
    if (!inList) {
      debugPrint('[FLOW] _advanceStatus: BLOCKED — order not in _orders (len=${_orders.length})');
      return false;
    }

    if (order.status == targetStatus) {
      debugPrint('[FLOW] _advanceStatus: BLOCKED — already at ${targetStatus.name}');
      return false;
    }

    if (!_canTransition(order.status, targetStatus)) {
      final allowed = _statusFlow[order.status];
      debugPrint('[FLOW] _advanceStatus: BLOCKED — ${order.status.name}→${targetStatus.name} not in $allowed');
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
      return false;
    }

    order.status = targetStatus;
    notifyListeners();
    _handlePartnerPreparationFlow(order);

    if (targetStatus == OrderStatus.callingDriver) {
      debugPrint('[FLOW] ★★★ callingDriver REACHED ★★★ id=${order.id} — invoking dispatch-engine directly');
      // Invoke the Edge Function directly from Flutter as the PRIMARY dispatch
      // mechanism. The DB trigger is a secondary safety net only — it has a
      // service-role-key placeholder that makes it fail with 401 until the
      // SQL is re-run with the real key. Direct invocation guarantees dispatch
      // fires on every callingDriver transition regardless of trigger state.
      unawaited(_invokeDispatch(order.id));
    }
    return true;
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
      // Clear the offer atomically — only acts if this driver still holds it.
      await supabase
          .from('orders')
          .update({
            'current_driver_offer_id': null,
            'driver_offer_expires_at': null,
          })
          .eq('id', order.id)
          .eq('current_driver_offer_id', driverId);

      // Immediately wake the dispatch engine to assign the next driver.
      await _invokeDispatch(order.id);
      debugPrint('[OrderStore] _rejectOrderInBackend: offer cleared, dispatch invoked for order=${order.id}');
    } catch (e) {
      debugPrint('[OrderStore] _rejectOrderInBackend error: $e');
    }
  }

  Future<bool> cancelDelivery(OrderModel order) async {
    final driverId = _currentDriverId;
    if (order.assignedDriverId != driverId) return false;
    if (order.status != OrderStatus.driverAccepted) return false;

    try {
      await supabase.from('orders').update({
        'assigned_driver_id': null,
        'current_driver_offer_id': null,
        'driver_offer_expires_at': null,
        'status': OrderStatus.callingDriver.name,
      }).eq('id', order.id);

      await _driverLocationService.stopTracking();
      _driverStore.stopTracking(order.id);
      _dismissedOrderIds.add(order.id);

      // Re-trigger dispatch so another driver receives this order immediately.
      unawaited(_invokeDispatch(order.id));

      debugPrint('OrderStore.cancelDelivery: OK driver=$driverId order=${order.id}');
      return true;
    } catch (e) {
      debugPrint('OrderStore.cancelDelivery: error => $e');
      return false;
    }
  }

  Future<bool> acceptOrder(OrderModel order) async {
    if (!isDriverAvailable) return false;
    if (order.assignedDriverId != null &&
        order.assignedDriverId != _currentDriverId) {
      return false;
    }
    if (!_driverStore.canAcceptOrder(_currentDriverId, order)) return false;
    for (final active in myOrders) {
      if (active.id == order.id) continue;
      if (active.status.index >= OrderStatus.pickedUp.index &&
          active.vendorName != order.vendorName) {
        return false;
      }
    }
    if (!_orders.any((o) => o.id == order.id)) return false;
    if (!_canTransition(order.status, OrderStatus.driverAccepted)) return false;

    final driver = _driverStore.getDriverById(_currentDriverId);
    final success = await _acceptOrderInDatabase(
      order,
      driverId: _currentDriverId,
      driverPhone: driver?.phone,
    );
    if (!success) return false;

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
      debugPrint('OrderStore.acceptOrderById: OK order=$orderId driver=$driverId');
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

  Future<bool> finalizePurchase({
    required String orderId,
    required double purchaseValue,
  }) async {
    if (purchaseValue <= 0) return false;

    final index = _orders.indexWhere((o) => o.id == orderId);
    if (index == -1) return false;

    final order = _orders[index];

    final isEligible = order.serviceType == OrderServiceType.storeShopping ||
        !order.isPartnerStore;
    if (!isEligible) return false;

    if (order.status != OrderStatus.pickedUp &&
        order.status != OrderStatus.onTheWay) {
      return false;
    }

    if (order.isPurchaseFinalized) return false;

    final breakdown = PricingService.calculateBreakdown(
      serviceType: order.serviceType,
      subtotal: purchaseValue,
      distanceKm: order.distanceKm,
      isPartnerStore: false,
      apartmentDelivery: order.apartmentDelivery,
    );
    final computedFinalTotal = breakdown.customerTotal;

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
      return false;
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

    return true;
  }

  bool hasPaymentAdjustment(OrderModel order) {
    return (order.refundAmount ?? 0) > 0 || (order.extraChargeAmount ?? 0) > 0;
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
          .update({'substitution_responses': updatedMap})
          .eq('id', orderId);
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
      await supabase
          .from('orders')
          .update({'payment_status': PaymentStatus.refunded.name})
          .eq('id', order.id);
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
      await supabase
          .from('orders')
          .update({'payment_status': PaymentStatus.paid.name})
          .eq('id', order.id);
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

  OrderType _resolveOrderType({
    required OrderServiceType serviceType,
    required bool isPartnerStore,
  }) {
    if (serviceType == OrderServiceType.restaurant && isPartnerStore) {
      return OrderType.partnerRestaurant;
    }
    return OrderType.nonPartnerPurchase;
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
    return _advanceStatus(order, OrderStatus.callingDriver);
  }

  List<OrderModel> partnerOrdersForRestaurant(String restaurantName) {
    final normalized = restaurantName.trim().toLowerCase();
    return _orders.where((order) {
      final vendor = order.vendorName;
      if (vendor == null) return false;
      if (order.serviceType != OrderServiceType.restaurant) return false;
      if (!order.isPartnerStore && order.orderType != OrderType.partnerRestaurant) return false;
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

    final subtotal =
        items.fold<double>(0, (sum, line) => sum + line.lineTotal);
    if (subtotal <= 0) {
      throw ArgumentError('Subtotal must be greater than zero.');
    }

    final pickupLatLng = restaurant.location;
    double resolvedDistanceKm;
    bool isDistanceEstimated = true;
    if (pickupLatLng != null && dropoffLocation != null) {
      try {
        final apiDistance = await MapsService.getDistanceKm(pickupLatLng, dropoffLocation);
        if (apiDistance != null) {
          resolvedDistanceKm = apiDistance;
          isDistanceEstimated = false;
        } else {
          resolvedDistanceKm = const Distance().as(LengthUnit.Kilometer, pickupLatLng, dropoffLocation);
        }
      } catch (e) {
        debugPrint('OrderStore.createPartnerDeliveryRequest: MapsService error => $e');
        resolvedDistanceKm = const Distance().as(LengthUnit.Kilometer, pickupLatLng, dropoffLocation);
      }
    } else if (pickupLatLng != null) {
      resolvedDistanceKm = const Distance().as(
        LengthUnit.Kilometer,
        pickupLatLng,
        const LatLng(38.7223, -9.1393),
      );
    } else {
      resolvedDistanceKm = PricingService.defaultDistanceKm;
    }

    final pricing = PricingService.calculateBreakdown(
      serviceType: OrderServiceType.restaurant,
      subtotal: subtotal,
      distanceKm: resolvedDistanceKm,
      isPartnerStore: true,
      apartmentDelivery: false,
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
    _partnerPreparationTimers[order.id] =
        Timer(const Duration(minutes: 5), () {
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
      debugPrint('[OrderStore] general subscription already active — skipping');
      return;
    }
    debugPrint('[OrderStore] general subscription started (no driver filter)');
    _ordersSubscription = supabase
        .from('orders')
        .stream(primaryKey: ['id'])
        .order('created_at', ascending: false)
        .listen(
          (rows) {
            debugPrint('[OrderStore] orders received=${rows.length} (general stream)');
            _orders.clear();
            for (final data in rows) {
              _orders.add(OrderModel.fromSupabase(data));
            }
            _handleSoundForCurrentDriver();
            notifyListeners();
          },
          onError: (Object e) =>
              debugPrint('[OrderStore] general stream error: $e'),
        );
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
    _driverOffersSubscription = null;
    _driverActiveSubscription = null;
    _ordersSubscription = null;

    // Clear stale data so the UI starts fresh from DB state.
    _orders.clear();
    _driverOfferIds.clear();
    _driverActiveIds.clear();

    debugPrint('[OrderStore] driverId=$driverId');

    // ── 1. Pending-offer stream ────────────────────────────────────────────
    debugPrint('[OrderStore] subscription started → orders.eq(current_driver_offer_id, $driverId)');
    _driverOffersSubscription = supabase
        .from('orders')
        .stream(primaryKey: ['id'])
        .eq('current_driver_offer_id', driverId)
        .order('created_at', ascending: false)
        .listen(
          (rows) {
            debugPrint('[OrderStore] orders received=${rows.length} (offers stream, driverId=$driverId)');
            _mergeDriverRows(rows, _driverOfferIds);
          },
          onError: (Object e) =>
              debugPrint('[OrderStore] offers stream error: $e'),
        );

    // ── 2. Active-delivery stream ──────────────────────────────────────────
    debugPrint('[OrderStore] subscription started → orders.eq(assigned_driver_id, $driverId)');
    _driverActiveSubscription = supabase
        .from('orders')
        .stream(primaryKey: ['id'])
        .eq('assigned_driver_id', driverId)
        .order('created_at', ascending: false)
        .listen(
          (rows) {
            debugPrint('[OrderStore] orders received=${rows.length} (active stream, driverId=$driverId)');
            _mergeDriverRows(rows, _driverActiveIds);
          },
          onError: (Object e) =>
              debugPrint('[OrderStore] active stream error: $e'),
        );
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
        final oldExpiry = storedIdx >= 0
            ? _orders[storedIdx].driverOfferExpiresAt
            : null;
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

    debugPrint('[OrderStore] _handleSoundForCurrentDriver: hasAvailable=$hasAvailable driverId=$driverId');
  }

  // ── Lifecycle ─────────────────────────────────────────────────────────────

  @override
  void dispose() {
    _ordersSubscription?.cancel();
    _driverOffersSubscription?.cancel();
    _driverActiveSubscription?.cancel();
    _ordersSubscription = null;
    _driverOffersSubscription = null;
    _driverActiveSubscription = null;
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
    final extra = km > _deliveryBaseKm ? (km - _deliveryBaseKm) * _deliveryExtraPerKm : 0.0;
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
    // ── SERVER-TRUSTED DISPATCH GATE ──────────────────────────────────────
    // Re-fetch the order row from the DB (never trust local state, cache or
    // client flags). Dispatch is only allowed when ONE of the following is
    // true, read live from Postgres:
    //   1. payment_status == 'paid'   (Stripe webhook OR confirm-mbway-payment)
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

      debugPrint('[DISPATCH] gate OK order=$orderId status=$paymentStatus method=$paymentMethod');
    } catch (e) {
      debugPrint('⛔ [DISPATCH] BLOCKED order=$orderId — gate re-fetch failed: $e');
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
    try {
      await supabase.from('orders').update(payload).eq('id', order.id);
      debugPrint('[FLOW] _updateStatusDB: OK');
      return true;
    } catch (e) {
      debugPrint('[FLOW] _updateStatusDB: EXCEPTION => $e');
      // If failure was caused by driver_offer_expires_at column, retry status-only.
      if (driverOfferExpiresAt != null) {
        debugPrint('[FLOW] _updateStatusDB: retrying status-only');
        try {
          await supabase
              .from('orders')
              .update({'status': newStatus.name})
              .eq('id', order.id);
          debugPrint('[FLOW] _updateStatusDB: retry OK');
          return true;
        } catch (e2) {
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
        debugPrint('OrderStore: _acceptOrderInDatabase — offer no longer valid (lost race) order=${order.id}');
        return false;
      }
      return true;
    } catch (e) {
      debugPrint('OrderStore: _acceptOrderInDatabase error => $e');
      return false;
    }
  }
}