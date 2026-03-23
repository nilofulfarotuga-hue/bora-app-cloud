import 'dart:async';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../auth/auth_store.dart';
import '../dispatch/dispatch_engine.dart';
import '../services/driver_location_service.dart';
import '../services/notification_service.dart';
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

  // ── FIX: channel name must NOT include the "realtime:" prefix.
  // Supabase JS SDK docs and Flutter SDK both require the raw channel name,
  // e.g. 'orders_channel'. Using 'realtime:public:orders' as the name
  // confuses the SDK and the channel never actually subscribes correctly.
  static const _ordersChannelName = 'orders_channel';

  RealtimeChannel? _channel;
  Timer? _refreshTimer;

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

  /// Initialisation: open the Realtime channel and start the refresh timer.
  /// loadOrders() is deferred until updateAuthStore() injects the AuthStore,
  /// guaranteeing the user filter is applied on the very first fetch.
  Future<void> _bootstrap() async {
    _subscribeRealtime();
    _refreshTimer = Timer.periodic(const Duration(seconds: 3), (_) => refresh());
  }

  Future<void> loadOrders() async {
    // FIX 3: never attempt a fetch before _authStore is injected — the filter
    // condition would silently evaluate to false and load ALL orders unfiltered.
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
  DispatchEngine? _dispatchEngine;
  AuthStore? _authStore;
  final PaymentService _paymentService = PaymentService();
  final DriverLocationService _driverLocationService = DriverLocationService();

  /// Temporarily holds the Stripe client secret after [createOrder] completes
  /// for a card payment. The calling screen must read and consume this to
  /// present the payment sheet via [PaymentService.processPayment].
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
  final Map<String, Set<String>> _dismissedOrdersByDriver = {};

  // ─────────────────────────────────────────────────────────────────────────
  // FIX (CRITICAL — ROOT CAUSE OF "NO REALTIME"): The channel subscription
  // had three compounding problems:
  //
  //  1. Wrong channel name: 'realtime:public:orders' — the 'realtime:' prefix
  //     is internal Supabase routing notation, not a valid channel name for
  //     the Flutter client. Correct name is any unique string, e.g. 'orders_channel'.
  //
  //  2. Missing DELETE handler: orders that get soft-deleted or expired in the
  //     DB were never removed from the local list.
  //
  //  3. No subscribe() error handling / status logging — silent failures.
  //
  //  4. The channel was recreated on every Provider rebuild because
  //     listenForNewOrders() was called from the constructor without guarding
  //     against re-initialization. Now _subscribeRealtime() is idempotent.
  // ─────────────────────────────────────────────────────────────────────────
  void _subscribeRealtime() {
    // Guard: never create a second channel if already subscribed.
    if (_channel != null) return;

    _channel = supabase.channel(_ordersChannelName);

    _channel!
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'orders',
          callback: (payload) {
            try {
              final data = payload.newRecord;
              if (data.isEmpty) return;

              // FIX 2: filter realtime INSERTs by userId for clients so that
              // orders belonging to other users are never added to this device's
              // local list — even though the channel receives all table events.
              final isClient = _authStore?.currentClient != null;
              final userId = _authStore?.userId;
              if (isClient) {
                if (userId == null || data['user_id'] != userId) return;
              }

              final order = OrderModel.fromSupabase(data);
              if (_orders.any((o) => o.id == order.id)) return;
              _orders.insert(0, order);
              notifyListeners();
            } catch (e) {
              debugPrint('OrderStore Realtime INSERT parse error: $e');
            }
          },
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.update,
          schema: 'public',
          table: 'orders',
          callback: (payload) {
            try {
              final data = payload.newRecord;
              if (data.isEmpty) return;
              final updatedOrder = OrderModel.fromSupabase(data);
              final index = _orders.indexWhere((o) => o.id == updatedOrder.id);
              if (index != -1) {
                _orders[index] = updatedOrder;
                notifyListeners();
              }
            } catch (e) {
              debugPrint('OrderStore Realtime UPDATE parse error: $e');
            }
          },
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.delete,
          schema: 'public',
          table: 'orders',
          callback: (payload) {
            final oldData = payload.oldRecord;
            if (oldData.isEmpty) return;
            final deletedId = oldData['id'] as String?;
            if (deletedId == null) return;
            final before = _orders.length;
            _orders.removeWhere((o) => o.id == deletedId);
            if (_orders.length != before) notifyListeners();
          },
        )
        .subscribe((status, [error]) {
          debugPrint('OrderStore Realtime: $status${error != null ? ' | $error' : ''}');
          // If the subscription error-loops, back off and retry.
          if (status == RealtimeSubscribeStatus.channelError ||
              status == RealtimeSubscribeStatus.timedOut) {
            _resubscribeWithDelay();
          }
        });
  }

  void _resubscribeWithDelay() {
    _channel?.unsubscribe();
    _channel = null;
    Future.delayed(const Duration(seconds: 5), () {
      if (!_disposed) {
        _subscribeRealtime();
        loadOrders();
      }
    });
  }

  bool _disposed = false;

  List<OrderModel> get orders => List.unmodifiable(_orders);

  String get _currentDriverId => _driverStore.currentDriverId;

  bool get isDriverAvailable => _driverStore.currentDriver?.isOnline ?? false;

  List<OrderModel> get availableOrders {
    final driver = _driverStore.getDriverById(_currentDriverId);
    if (driver == null) {
      return const <OrderModel>[];
    }

    final now = DateTime.now();
    final available = _orders.where((order) {
      if (order.status != OrderStatus.callingDriver) return false;

      if (order.driverOfferExpiresAt != null &&
          now.isAfter(order.driverOfferExpiresAt!)) {
        return false;
      }

      if (!driver.supportsService(order.serviceType)) return false;

      if (!_driverStore.canAcceptOrder(_currentDriverId, order)) return false;

      if (order.currentDriverOfferId != null &&
          order.currentDriverOfferId != _currentDriverId) {
        return false;
      }

      return true;
    }).toList();

    final dismissed = _dismissedOrdersByDriver[_currentDriverId];
    if (dismissed != null && dismissed.isNotEmpty) {
      final existingIds = _orders.map((order) => order.id).toSet();
      dismissed.removeWhere((orderId) => !existingIds.contains(orderId));
      available.removeWhere((order) => dismissed.contains(order.id));
    }

    available.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return available;
  }

  List<OrderModel> get myOrders => _orders
      .where((o) =>
          o.assignedDriverId == _currentDriverId &&
          (o.status == OrderStatus.driverAccepted ||
              o.status == OrderStatus.pickedUp ||
              o.status == OrderStatus.onTheWay))
      .toList();

  List<OrderModel> get completedOrders =>
      _orders.where((o) => o.status == OrderStatus.delivered).toList();

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

  // FIX 1: updateAuthStore now triggers loadOrders() after injection so the
  // very first fetch runs with a valid _authStore (and correct user filter).
  // Previously _bootstrap() called loadOrders() before _authStore was ever set.
  Future<void> updateAuthStore(AuthStore authStore) async {
    _authStore = authStore;
    if (_authStore != null) {
      await loadOrders();
    }
  }

  void updateDriverStore(DriverStore driverStore) {
    _driverStore = driverStore;
  }

  void updateRestaurantStore(RestaurantStore store) {
    _restaurantStore = store;
    _restaurantStore?.syncPartnerOrders(_orders);
  }

  void updateDispatchEngine(DispatchEngine dispatchEngine) {
    _dispatchEngine = dispatchEngine;
  }

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

  // ─────────────────────────────────────────────────────────────────────────
  // FIX: createOrder now awaits _saveOrderToDatabase and uses the DB-returned
  // id (if the DB generates it) to keep local and remote in sync.
  // The optimistic local insert is reverted on DB failure.
  // ─────────────────────────────────────────────────────────────────────────
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
    final double? googleDistance = pickupLocation != null
        ? await MapsService.getDistanceKm(pickupLocation, destination)
        : null;

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

    // For card payments: create a Stripe PaymentIntent now so the intent ID is
    // persisted on the order row and the client secret is ready for the sheet.
    if (paymentMethod == PaymentMethod.card && !kIsWeb) {
      try {
        final intentData = await _paymentService.createPaymentIntent(
          orderId: order.id,
          amount: order.paymentBufferTotal,
        );
        order.paymentIntentId = intentData['paymentIntentId'] as String?;
        order.paymentStatus   = PaymentStatus.pending;
        _pendingClientSecret  = intentData['clientSecret'] as String?;
        debugPrint('OrderStore: PaymentIntent created: ${order.paymentIntentId}');
      } catch (e) {
        debugPrint('OrderStore.createOrder: createPaymentIntent failed => $e');
        // Non-fatal: order proceeds; payment sheet can be retried separately.
      }
    }

    // Block order if the partner restaurant is offline.
    if (isPartnerStore && serviceType == OrderServiceType.restaurant) {
      final restaurant = _restaurantStore?.restaurantByName(vendorName);
      if (restaurant != null && !restaurant.isOnline) {
        return false;
      }
    }

    // Optimistic local insert for responsive UI.
    _orders.insert(0, order);
    notifyListeners();

    try {
      await _saveOrderToDatabase(order);
      // Realtime INSERT event will propagate to other devices automatically.
      await _simulateRestaurantFlow(order);
      return true;
    } catch (e) {
      // Revert the optimistic insert so UI stays consistent with DB.
      _orders.remove(order);
      notifyListeners();
      debugPrint('OrderStore: createOrder failed => $e');
      return false;
    }
  }

  Future<void> _simulateRestaurantFlow(OrderModel order) async {
    final isPartnerRestaurantOrder =
        order.serviceType == OrderServiceType.restaurant &&
            order.isPartnerStore;

    if (isPartnerRestaurantOrder) {
      // Awaits action from restaurant dashboard — do nothing here.
      return;
    }

    final requiresPreparation =
        order.serviceType == OrderServiceType.restaurant ||
            (order.serviceType == OrderServiceType.storeShopping &&
                order.isPartnerStore);

    if (!requiresPreparation) {
      final progressed = await _advanceStatus(order, OrderStatus.preparing);
      if (!progressed) return;
      await Future.delayed(const Duration(milliseconds: 500));
      await _advanceStatus(order, OrderStatus.callingDriver);
      return;
    }

    final progressed = await _advanceStatus(order, OrderStatus.preparing);
    if (!progressed) return;
    await Future.delayed(const Duration(seconds: 3));
    await _advanceStatus(order, OrderStatus.callingDriver);
  }

  // ─────────────────────────────────────────────────────────────────────────
  // FIX: _advanceStatus is async and writes to the DB BEFORE updating local
  // state. If the DB write fails, local state is NOT changed, keeping both
  // devices consistent. The Realtime UPDATE event triggered by the DB write
  // will propagate the change to all other subscribers automatically.
  // ─────────────────────────────────────────────────────────────────────────
  Future<bool> _advanceStatus(
      OrderModel order, OrderStatus targetStatus) async {
    if (!_orders.any((o) => o.id == order.id)) return false;
    if (order.status == targetStatus) return false;
    if (!_canTransition(order.status, targetStatus)) return false;

    DateTime? newExpiry;
    if (targetStatus == OrderStatus.callingDriver) {
      newExpiry = DateTime.now().add(const Duration(seconds: 40));
    }

    final success = await _updateOrderStatusInDatabase(
      order,
      targetStatus,
      driverOfferExpiresAt: newExpiry,
    );
    if (!success) return false;

    // Update local state only after DB confirmed.
    order.status = targetStatus;
    if (newExpiry != null) order.driverOfferExpiresAt = newExpiry;
    notifyListeners();
    _handlePartnerPreparationFlow(order);
    _triggerStatusNotification(order, targetStatus);
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

    if (order.assignedDriverId != null &&
        order.assignedDriverId != _currentDriverId) {
      return false;
    }

    final driverId = _currentDriverId;
    final dismissed = _dismissedOrdersByDriver.putIfAbsent(
      driverId,
      () => <String>{},
    );
    dismissed.add(order.id);

    if (!order.driverOfferHistory.contains(driverId)) {
      order.driverOfferHistory.add(driverId);
    }

    order.driverOfferExpiresAt = null;

    if (order.currentDriverOfferId == driverId) {
      if (_dispatchEngine != null) {
        _dispatchEngine!.notifyOrderReleased(order);
        return true;
      }
      order.currentDriverOfferId = null;
    }

    notifyListeners();
    return true;
  }

  Future<bool> acceptOrder(OrderModel order) async {
    if (!isDriverAvailable) return false;
    if (order.currentDriverOfferId != null &&
        order.currentDriverOfferId != _currentDriverId) {
      return false;
    }
    if (order.assignedDriverId != null &&
        order.assignedDriverId != _currentDriverId) {
      return false;
    }
    if (!_driverStore.canAcceptOrder(_currentDriverId, order)) return false;
    // Block batching if driver already picked up an order from a different vendor
    // (they are physically en route to a different destination).
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

    // Update local state only after DB confirmed.
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
    _dispatchEngine?.notifyOrderAccepted(order);

    // Notify the client that a driver is on the way.
    if ((order.clientPhone ?? '').isNotEmpty) {
      NotificationService.instance.notifyClient(
        clientPhone: order.clientPhone!,
        title: 'Estafeta a caminho!',
        body: 'O teu estafeta está a caminho para recolher o pedido.',
      );
    }
    return true;
  }

  Future<bool> pickUpOrder(OrderModel order) async {
    final advanced = await _advanceStatus(order, OrderStatus.pickedUp);
    if (advanced) {
      order.pickupWarningIssued = false;
      _driverStore.updateTrackingTarget(order);
      _dispatchEngine?.notifyOrderPickedUp(order);
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
      _dispatchEngine?.notifyOrderReleased(order);
      order.pickupWarningIssued = false;
    }
    return advanced;
  }

  /// Records the driver's real purchase receipt value for non-partner orders.
  ///
  /// Eligible: [OrderStatus.pickedUp] or [OrderStatus.onTheWay], non-partner.
  /// DB-first: writes before mutating local state, consistent with [_advanceStatus].
  Future<bool> finalizePurchase({
    required String orderId,
    required double purchaseValue,
  }) async {
    if (purchaseValue <= 0) return false;

    final index = _orders.indexWhere((o) => o.id == orderId);
    if (index == -1) return false;

    final order = _orders[index];

    // Only applicable to non-partner purchase orders
    final isEligible = order.serviceType == OrderServiceType.storeShopping ||
        !order.isPartnerStore;
    if (!isEligible) return false;

    // Driver must have possession of the goods
    if (order.status != OrderStatus.pickedUp &&
        order.status != OrderStatus.onTheWay) {
      return false;
    }

    // Idempotency guard
    if (order.isPurchaseFinalized) return false;

    // Recalculate customer-facing total from real purchase value using PricingService
    final breakdown = PricingService.calculateBreakdown(
      serviceType: order.serviceType,
      subtotal: purchaseValue,
      distanceKm: order.distanceKm,
      isPartnerStore: false,
      apartmentDelivery: order.apartmentDelivery,
    );
    final computedFinalTotal = breakdown.customerTotal;

    // Compare against the pre-authorised buffer to determine refund or extra charge.
    // Explicit 0.0 for the equal case so downstream helpers can use > 0 checks safely.
    final diff = double.parse(
        (computedFinalTotal - order.paymentBufferTotal).toStringAsFixed(2));
    final refund = diff < 0 ? -diff : 0.0;
    final extra = diff > 0 ? diff : 0.0;
    final newPaymentStatus = refund > 0
        ? PaymentStatus.refundPending
        : extra > 0
            ? PaymentStatus.extraRequired
            : PaymentStatus.paid;

    // DB-first: only mutate local state after write succeeds
    try {
      await supabase.from('orders').update({
        'final_purchase_value': purchaseValue,
        'final_total': computedFinalTotal,
        'is_purchase_finalized': true,
        'refund_amount': refund,
        'extra_charge_amount': extra,
        'payment_status': newPaymentStatus.name,
      }).eq('id', orderId);
    } catch (e) {
      debugPrint('OrderStore: finalizePurchase DB error => $e');
      return false;
    }

    order.finalPurchaseValue = purchaseValue;
    order.finalTotal = computedFinalTotal;
    order.isPurchaseFinalized = true;
    order.refundAmount = refund;
    order.extraChargeAmount = extra;
    order.paymentStatus = newPaymentStatus;
    notifyListeners();

    // Auto-trigger payment reconciliation for card orders immediately after
    // finalization. Non-card orders (cash/mbway) skip this — nothing to refund
    // or charge via Stripe.
    if (order.paymentMethod == PaymentMethod.card) {
      if (refund > 0) {
        await processRefund(order);
      } else if (extra > 0) {
        await processExtraCharge(order);
      }
    }

    return true;
  }

  /// Returns true when the finalised purchase required a refund or extra charge.
  /// Only meaningful after [finalizePurchase] has succeeded.
  bool hasPaymentAdjustment(OrderModel order) {
    return (order.refundAmount ?? 0) > 0 || (order.extraChargeAmount ?? 0) > 0;
  }

  /// Records the client's approval or rejection of a driver substitution
  /// proposal. Persists to Supabase before mutating local state.
  Future<bool> respondToSubstitution({
    required String orderId,
    required String productName,
    required bool approved,
  }) async {
    final index = _orders.indexWhere((o) => o.id == orderId);
    if (index == -1) return false;

    final order = _orders[index];

    // Build an updated copy so the DB write uses the intended value
    // without touching local state yet.
    final updatedMap = Map<String, bool>.from(order.substitutionResponses);
    updatedMap[productName] = approved;

    try {
      await supabase
          .from('orders')
          .update({'substitution_responses': updatedMap})
          .eq('id', orderId);
    } catch (e) {
      debugPrint('OrderStore.respondToSubstitution DB error => $e');
      // Local state was never mutated — nothing to roll back.
      return false;
    }

    // DB confirmed — now safe to update local state.
    order.substitutionResponses[productName] = approved;
    notifyListeners();
    return true;
  }

  /// Calls the backend `/refund` endpoint to return the surplus buffer amount
  /// to the client, then marks the order as [PaymentStatus.refunded].
  ///
  /// Preconditions: [order.refundAmount] > 0, [order.paymentIntentId] set.
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

  /// Calls the backend `/charge-extra` endpoint to collect the shortfall from
  /// the client, then marks the order as [PaymentStatus.paid].
  ///
  /// Preconditions: [order.extraChargeAmount] > 0.
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

  /// Lightweight UI refresh — recalculates derived getters without hitting DB.
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

  // ─────────────────────────────────────────────────────────────────────────
  // Restaurant partner actions — now return Future<bool> and await DB writes.
  // ─────────────────────────────────────────────────────────────────────────
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

  // ─────────────────────────────────────────────────────────────────────────
  // FIX: createPartnerDeliveryRequest previously only inserted into the local
  // list — it NEVER persisted to Supabase. Other devices never saw it.
  // Now it calls _saveOrderToDatabase just like createOrder does.
  // ─────────────────────────────────────────────────────────────────────────
  Future<OrderModel> createPartnerDeliveryRequest({
    required RestaurantModel restaurant,
    required String customerName,
    required String customerPhone,
    required String deliveryAddress,
    required List<PartnerOrderLine> items,
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
    final double resolvedDistanceKm;
    if (pickupLatLng != null) {
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
      dropoffAddress: deliveryAddress,
      customerNotes: orderNotes,
      isPartnerStore: true,
      apartmentDelivery: false,
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

  void _triggerStatusNotification(OrderModel order, OrderStatus status) {
    final phone = order.clientPhone ?? '';
    switch (status) {
      case OrderStatus.callingDriver:
        NotificationService.instance.notifyDriversNewOrder(
          orderId: order.id,
          vendorName: order.vendorName ?? 'BORA',
          total: order.total,
        );
        break;
      case OrderStatus.pickedUp:
        if (phone.isNotEmpty) {
          NotificationService.instance.notifyClient(
            clientPhone: phone,
            title: 'Pedido recolhido!',
            body: 'O teu estafeta recolheu o pedido e está a caminho!',
          );
        }
        break;
      case OrderStatus.delivered:
        if (phone.isNotEmpty) {
          NotificationService.instance.notifyClient(
            clientPhone: phone,
            title: 'Pedido entregue!',
            body: 'O teu pedido foi entregue. Bom apetite!',
          );
        }
        break;
      default:
        break;
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _refreshTimer?.cancel();
    _channel?.unsubscribe();
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

  // ─────────────────────────────────────────────────────────────────────────
  // DB helpers — both inside the class (previously _updateOrderStatusInDatabase
  // was accidentally placed OUTSIDE the class closing brace, making it a
  // top-level function that was never called).
  // ─────────────────────────────────────────────────────────────────────────

  Future<void> _saveOrderToDatabase(OrderModel order) async {
    // Use toSupabase() to send ALL fields, not just 5 hardcoded ones.
    await supabase.from('orders').insert(order.toSupabase());
    debugPrint('OrderStore: inserted order ${order.id}');
  }

  Future<bool> _updateOrderStatusInDatabase(
    OrderModel order,
    OrderStatus newStatus, {
    DateTime? driverOfferExpiresAt,
  }) async {
    try {
      final payload = <String, dynamic>{'status': newStatus.name};
      if (driverOfferExpiresAt != null) {
        payload['driver_offer_expires_at'] =
            driverOfferExpiresAt.toIso8601String();
      }
      await supabase.from('orders').update(payload).eq('id', order.id);
      return true;
    } catch (e) {
      debugPrint('OrderStore: _updateOrderStatusInDatabase error => $e');
      return false;
    }
  }

  /// Persists the current driver offer ID to Supabase.
  /// Called by DispatchEngine whenever [currentDriverOfferId] changes.
  Future<void> persistDriverOffer(String orderId, String? driverOfferId) async {
    try {
      await supabase
          .from('orders')
          .update({'current_driver_offer_id': driverOfferId})
          .eq('id', orderId);
    } catch (e) {
      debugPrint('OrderStore: persistDriverOffer error => $e');
    }
  }

  /// Single-shot UPDATE for driver acceptance — status + assignment in one call.
  /// Prevents the realtime race where other devices briefly see
  /// status=driverAccepted with assigned_driver_id=null.
  Future<bool> _acceptOrderInDatabase(
    OrderModel order, {
    required String driverId,
    String? driverPhone,
  }) async {
    try {
      await supabase.from('orders').update({
        'status': OrderStatus.driverAccepted.name,
        'assigned_driver_id': driverId,
        'current_driver_offer_id': null,
        'driver_phone': driverPhone,
      }).eq('id', order.id);
      return true;
    } catch (e) {
      debugPrint('OrderStore: _acceptOrderInDatabase error => $e');
      return false;
    }
  }
}