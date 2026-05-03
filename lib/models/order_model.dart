export 'order_service_type.dart';

import 'package:latlong2/latlong.dart';
import 'package:uuid/uuid.dart';

import 'cart_item.dart';
import 'order_service_type.dart';

const double _platformCommissionRate = 0.20;

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

enum OrderType {
  partnerRestaurant,
  nonPartnerPurchase,
}

enum PaymentMethod {
  card,
  mbway,
  cash,
}

enum PaymentStatus {
  pending, // awaiting payment confirmation
  paid, // fully settled
  failed, // payment failed
  refundPending, // reconciliation: surplus to return to client
  refunded, // backend processed the refund
  extraRequired, // reconciliation: shortfall to collect from client
}

class OrderModel {
  final String id;
  DateTime? driverOfferExpiresAt;
  final OrderServiceType serviceType;
  final double subtotal;
  final double deliveryFee;
  final double serviceFee;
  final double platformCommission;
  final double driverEarnings;
  final double distanceKm;
  final double deliveryPrice;
  final double total;
  final LatLng? pickupLocation;
  final LatLng? destination;
  final String? vendorName;
  final String? pickupAddress;
  final String? pickupStreet;
  final String? pickupCity;
  final String? pickupPostalCode;
  final String? dropoffAddress;
  final String? dropoffStreet;
  final String? dropoffCity;
  final String? dropoffPostalCode;
  final String? customerNotes;
  final bool isPartnerStore;
  final bool apartmentDelivery;
  final bool isDistanceEstimated;
  final bool requiresCar;
  final OrderType orderType;
  final PaymentMethod paymentMethod;
  // Mutable: updated by finalizePurchase reconciliation and processRefund/processExtraCharge.
  PaymentStatus paymentStatus;
  String? paymentIntentId;
  final DateTime createdAt;
  final String? clientPhone;

  /// Original total computed at cart checkout — never overwritten after creation.
  final double estimatedTotal;

  /// Actual amount the driver spent at the store (non-partner orders only).
  double? finalPurchaseValue;

  /// Customer-facing total recalculated from [finalPurchaseValue] + fees.
  double? finalTotal;

  /// True once the driver has confirmed the real purchase value.
  bool isPurchaseFinalized;

  /// Estimated total pre-authorised at checkout (estimatedTotal × 1.15 buffer).
  /// Non-partner only — equals [estimatedTotal] for partner orders.
  double paymentBufferTotal;

  /// Positive amount to refund when [finalTotal] < [paymentBufferTotal].
  double? refundAmount;

  /// Refund destination chosen by the cliente at cancellation:
  ///   - 'wallet' → instant credit into client_wallets (free balance + tokens)
  ///   - 'stripe' → async refund via Stripe (5–10 business days)
  /// NULL when no cancellation has happened yet.
  String? refundMethod;

  /// Cents paid from the cliente's saldo Bora (free_balance_cents) at
  /// create_order. Stripe/MBWay charge = price*100 - walletAppliedCents.
  int walletAppliedCents;

  /// §18 v2: cents from a restaurant_menu_credits applied at create_order
  /// (cliente arrived at a previous reservation). Stripe charge subtracts it.
  int menuCreditAppliedCents;

  /// Positive extra charge when [finalTotal] > [paymentBufferTotal].
  double? extraChargeAmount;

  /// Total a cobrar em dinheiro ao cliente (cash + extras como sacos mercado).
  /// NULL = usar [finalTotal] como fallback. Preenchido apenas pela RPC
  /// `finalize_storeshopping_purchase` quando `payment_method=cash` e há extra
  /// (ex.: sacos mercado a €0.10/saco).
  double? cashTotalDue;

  /// Items added by the driver during storeShopping (caso A: cliente
  /// pediu via chat; caso B: substituição de produto faltando). Each entry:
  /// `{name, price_base_cents, price_final_cents, qty, reason, added_at,
  /// added_by}`. `price_final_cents` already includes the +15%
  /// `non_partner_markup_pct`. Populated server-side by RPC
  /// `finalize_storeshopping_purchase`.
  List<Map<String, dynamic>> itemsAdded;

  final String? customerName;
  final String? userId;
  List<CartItem> items;

  /// Client gratuity in EUR cents (BR §4.5). Split 80/20 is handled downstream.
  int tipCents;

  /// Whether the client chose takeaway (BR §14.9). Partner restaurants only.
  /// When true, dispatch is bypassed — the client picks up directly.
  bool isTakeaway;

  String? assignedDriverId;
  String? currentDriverOfferId;
  String? driverPhone;

  /// Number of carrier bags used by the driver.
  int bagCount;

  /// Total bag fee charged (restaurant: fixed €0.30; market: bagCount × €0.10).
  double bagFee;

  /// DEPRECATED — single source of truth is now
  /// `DriverStore.currentDriver.location`, synced through the `drivers` table
  /// Realtime subscription. These fields are kept only for binary
  /// compatibility with call sites that still reference them; they are no
  /// longer written to, read from Supabase, or serialised back.
  @Deprecated('Use DriverStore.currentDriver.location')
  double? driverLat;
  @Deprecated('Use DriverStore.currentDriver.location')
  double? driverLng;
  final List<String> driverOfferHistory;
  final List<String> triedDriverIds;
  bool pickupWarningIssued;

  /// Tracks client responses to driver substitution proposals.
  /// Key = original product name; value = true (approved) / false (rejected).
  final Map<String, bool> substitutionResponses;

  OrderStatus status;

  OrderModel({
    required this.total,
    required this.serviceType,
    this.subtotal = 0,
    this.deliveryFee = 0,
    this.serviceFee = 0,
    this.platformCommission = 0,
    this.driverEarnings = 0,
    this.distanceKm = 0,
    this.deliveryPrice = 0,
    this.pickupLocation,
    this.destination,
    this.vendorName,
    this.pickupAddress,
    this.pickupStreet,
    this.pickupCity,
    this.pickupPostalCode,
    this.dropoffAddress,
    this.dropoffStreet,
    this.dropoffCity,
    this.dropoffPostalCode,
    this.customerNotes,
    this.isPartnerStore = false,
    this.apartmentDelivery = false,
    this.isDistanceEstimated = false,
    this.requiresCar = false,
    this.orderType = OrderType.nonPartnerPurchase,
    this.paymentMethod = PaymentMethod.cash,
    this.paymentStatus = PaymentStatus.pending,
    this.paymentIntentId,
    this.status = OrderStatus.created,
    String? id,
    DateTime? createdAt,
    this.clientPhone,
    this.customerName,
    this.userId,
    List<CartItem>? items,
    this.assignedDriverId,
    this.currentDriverOfferId,
    this.driverPhone,
    this.bagCount = 0,
    this.bagFee = 0,
    List<String>? driverOfferHistory,
    List<String>? triedDriverIds,
    this.pickupWarningIssued = false,
    this.driverOfferExpiresAt,
    this.driverLat,
    this.driverLng,
    double? estimatedTotal,
    this.finalPurchaseValue,
    this.finalTotal,
    this.isPurchaseFinalized = false,
    double? paymentBufferTotal,
    this.refundAmount,
    this.refundMethod,
    this.walletAppliedCents = 0,
    this.menuCreditAppliedCents = 0,
    this.extraChargeAmount,
    this.cashTotalDue,
    List<Map<String, dynamic>>? itemsAdded,
    this.tipCents = 0,
    this.isTakeaway = false,
    Map<String, bool>? substitutionResponses,
  })  : estimatedTotal = estimatedTotal ?? total,
        paymentBufferTotal = paymentBufferTotal ?? total,
        itemsAdded = itemsAdded ?? <Map<String, dynamic>>[],
        substitutionResponses = substitutionResponses ?? <String, bool>{},
        items = List<CartItem>.unmodifiable(items ?? const <CartItem>[]),
        id = id ?? const Uuid().v4(),
        createdAt = createdAt ?? DateTime.now(),
        driverOfferHistory = driverOfferHistory ?? <String>[],
        triedDriverIds = triedDriverIds ?? <String>[];

  // ─────────────────────────────────────────────────────────────────────────
  // FIX (CRITICAL): Previously fromSupabase hardcoded
  //   serviceType: OrderServiceType.storeShopping
  //   status: OrderStatus.created
  // regardless of what was in the DB row. This meant that every Realtime
  // UPDATE event received by other devices was deserialized with the WRONG
  // status, making it look like nothing had changed. Fixed by mapping every
  // persisted column back to its correct Dart type.
  // ─────────────────────────────────────────────────────────────────────────
  factory OrderModel.fromSupabase(Map<String, dynamic> data) {
    final statusStr = data['status'] as String? ?? 'created';
    final status = OrderStatus.values.firstWhere(
      (e) => e.name == statusStr,
      orElse: () => OrderStatus.created,
    );

    final serviceTypeStr = data['service_type'] as String? ?? 'storeShopping';
    final serviceType = OrderServiceType.values.firstWhere(
      (e) => e.name == serviceTypeStr,
      orElse: () => OrderServiceType.storeShopping,
    );

    final orderTypeStr = data['order_type'] as String? ?? 'nonPartnerPurchase';
    final orderType = OrderType.values.firstWhere(
      (e) => e.name == orderTypeStr,
      orElse: () => OrderType.nonPartnerPurchase,
    );

    final paymentStr = data['payment_method'] as String? ?? 'cash';
    final paymentMethod = PaymentMethod.values.firstWhere(
      (e) => e.name == paymentStr,
      orElse: () => PaymentMethod.cash,
    );

    final paymentStatusStr = data['payment_status'] as String? ?? 'pending';
    final paymentStatus = PaymentStatus.values.firstWhere(
      (e) => e.name == paymentStatusStr,
      orElse: () => PaymentStatus.pending,
    );

    DateTime? driverOfferExpiresAt;
    final expiresRaw = data['driver_offer_expires_at'];
    if (expiresRaw != null) {
      driverOfferExpiresAt = DateTime.tryParse(expiresRaw.toString());
    }

    LatLng? pickupLocation;
    final pickupLat = data['pickup_lat'];
    final pickupLng = data['pickup_lng'];
    if (pickupLat != null && pickupLng != null) {
      pickupLocation =
          LatLng((pickupLat as num).toDouble(), (pickupLng as num).toDouble());
    }

    LatLng? destination;
    final dropLat = data['dropoff_lat'];
    final dropLng = data['dropoff_lng'];
    if (dropLat != null && dropLng != null) {
      destination =
          LatLng((dropLat as num).toDouble(), (dropLng as num).toDouble());
    }

    final historyRaw = data['driver_offer_history'];
    final offerHistory =
        historyRaw is List ? List<String>.from(historyRaw) : <String>[];

    final triedRaw = data['tried_driver_ids'];
    final triedDriverIds =
        triedRaw is List ? List<String>.from(triedRaw) : <String>[];

    final rawItems = data['items'] as List?;
    final parsedItems = rawItems
        ?.map((e) => CartItem.fromJson(Map<String, dynamic>.from(e as Map)))
        .toList();

    final rawItemsAdded = data['items_added'] as List?;
    final parsedItemsAdded = rawItemsAdded
            ?.map((e) => Map<String, dynamic>.from(e as Map))
            .toList() ??
        <Map<String, dynamic>>[];

    return OrderModel(
      id: data['id'] as String,
      total: (data['price'] as num? ?? 0).toDouble(),
      subtotal: (data['subtotal'] as num? ?? 0).toDouble(),
      deliveryFee: (data['delivery_fee'] as num? ?? 0).toDouble(),
      serviceFee: (data['service_fee'] as num? ?? 0).toDouble(),
      platformCommission: (data['platform_commission'] as num? ?? 0).toDouble(),
      driverEarnings: (data['driver_earnings'] as num? ?? 0).toDouble(),
      distanceKm: (data['distance_km'] as num? ?? 0).toDouble(),
      deliveryPrice: (data['delivery_price'] as num? ?? 0).toDouble(),
      serviceType: serviceType,
      status: status,
      orderType: orderType,
      paymentMethod: paymentMethod,
      isPartnerStore: data['is_partner_store'] as bool? ?? false,
      apartmentDelivery: data['apartment_delivery'] as bool? ?? false,
      isDistanceEstimated: data['is_distance_estimated'] as bool? ?? false,
      requiresCar: data['requires_car'] as bool? ?? false,
      vendorName: data['vendor_name'] as String?,
      pickupAddress: data['pickup_address'] as String?,
      pickupStreet: data['pickup_street'] as String?,
      pickupCity: data['pickup_city'] as String?,
      pickupPostalCode: data['pickup_postal_code'] as String?,
      dropoffAddress: data['dropoff_address'] as String?,
      dropoffStreet: data['dropoff_street'] as String?,
      dropoffCity: data['dropoff_city'] as String?,
      dropoffPostalCode: data['dropoff_postal_code'] as String?,
      customerNotes: data['customer_notes'] as String?,
      clientPhone: data['client_phone'] as String?,
      customerName: data['customer_name'] as String?,
      userId: data['user_id'] as String?,
      assignedDriverId: data['assigned_driver_id'] as String?,
      currentDriverOfferId: data['current_driver_offer_id'] as String?,
      driverPhone: data['driver_phone'] as String?,
      bagCount: data['bag_count'] as int? ?? 0,
      bagFee: (data['bag_fee'] as num? ?? 0).toDouble(),
      pickupLocation: pickupLocation,
      destination: destination,
      createdAt: data['created_at'] != null
          ? DateTime.tryParse(data['created_at'].toString()) ?? DateTime.now()
          : DateTime.now(),
      driverOfferExpiresAt: driverOfferExpiresAt,
      driverOfferHistory: offerHistory,
      triedDriverIds: triedDriverIds,
      paymentStatus: paymentStatus,
      paymentIntentId: data['payment_intent_id'] as String?,
      estimatedTotal: (data['estimated_total'] as num?)?.toDouble(),
      finalPurchaseValue: (data['final_purchase_value'] as num?)?.toDouble(),
      finalTotal: (data['final_total'] as num?)?.toDouble(),
      isPurchaseFinalized: data['is_purchase_finalized'] as bool? ?? false,
      paymentBufferTotal: (data['payment_buffer_total'] as num?)?.toDouble(),
      refundAmount: (data['refund_amount'] as num?)?.toDouble(),
      refundMethod: data['refund_method'] as String?,
      walletAppliedCents: (data['wallet_applied_cents'] as num?)?.toInt() ?? 0,
      menuCreditAppliedCents:
          (data['menu_credit_applied_cents'] as num?)?.toInt() ?? 0,
      extraChargeAmount: (data['extra_charge_amount'] as num?)?.toDouble(),
      cashTotalDue: (data['cash_total_due'] as num?)?.toDouble(),
      itemsAdded: parsedItemsAdded,
      tipCents: (data['tip_amount_cents'] as num?)?.toInt() ?? 0,
      isTakeaway: data['is_takeaway'] as bool? ?? false,
      // driver_lat / driver_lng intentionally NOT read — single source of
      // truth is DriverStore.currentDriver.location (drivers table realtime).
      items: parsedItems,
      substitutionResponses:
          (data['substitution_responses'] as Map<String, dynamic>?)
              ?.map((k, v) => MapEntry(k, v == true)),
    );
  }

  /// Serialises ALL fields that the backend persists — used in INSERT and UPDATE.
  Map<String, dynamic> toSupabase() {
    return {
      'id': id,
      'created_at': createdAt.toIso8601String(),
      'status': status.name,
      'service_type': serviceType.name,
      'order_type': orderType.name,
      'payment_method': paymentMethod.name,
      'price': total,
      'subtotal': subtotal,
      'delivery_fee': deliveryFee,
      'service_fee': serviceFee,
      'platform_commission': platformCommission,
      'driver_earnings': driverEarnings,
      'distance_km': distanceKm,
      'delivery_price': deliveryPrice,
      'is_partner_store': isPartnerStore,
      'apartment_delivery': apartmentDelivery,
      'is_distance_estimated': isDistanceEstimated,
      'requires_car': requiresCar,
      'vendor_name': vendorName,
      'pickup_address': pickupAddress,
      'pickup_street': pickupStreet,
      'pickup_city': pickupCity,
      'pickup_postal_code': pickupPostalCode,
      'dropoff_address': dropoffAddress,
      'dropoff_street': dropoffStreet,
      'dropoff_city': dropoffCity,
      'dropoff_postal_code': dropoffPostalCode,
      'customer_notes': customerNotes,
      'client_phone': clientPhone,
      'customer_name': customerName,
      if (userId != null) 'user_id': userId,
      'assigned_driver_id': assignedDriverId,
      'current_driver_offer_id': currentDriverOfferId,
      'driver_phone': driverPhone,
      'driver_offer_expires_at': driverOfferExpiresAt?.toIso8601String(),
      'driver_offer_history': driverOfferHistory,
      'payment_status': paymentStatus.name,
      'estimated_total': estimatedTotal,
      'payment_buffer_total': paymentBufferTotal,
      'is_purchase_finalized': isPurchaseFinalized,
      if (refundAmount != null) 'refund_amount': refundAmount,
      if (refundMethod != null) 'refund_method': refundMethod,
      if (walletAppliedCents > 0) 'wallet_applied_cents': walletAppliedCents,
      if (menuCreditAppliedCents > 0)
        'menu_credit_applied_cents': menuCreditAppliedCents,
      if (extraChargeAmount != null) 'extra_charge_amount': extraChargeAmount,
      if (cashTotalDue != null) 'cash_total_due': cashTotalDue,
      if (itemsAdded.isNotEmpty) 'items_added': itemsAdded,
      // BR §4.5 — canonical tip column is `tip_amount_cents` (not `tip_cents`).
      // rating_screen.dart also writes to this column + sets tip_added_at.
      'tip_amount_cents': tipCents,
      if (tipCents > 0) 'tip_added_at': DateTime.now().toUtc().toIso8601String(),
      if (isTakeaway) 'is_takeaway': true,
      if (paymentIntentId != null) 'payment_intent_id': paymentIntentId,
      if (finalPurchaseValue != null)
        'final_purchase_value': finalPurchaseValue,
      if (finalTotal != null) 'final_total': finalTotal,
      if (substitutionResponses.isNotEmpty)
        'substitution_responses': substitutionResponses,
      'items': items.map((i) => i.toJson()).toList(),
      if (bagCount > 0) 'bag_count': bagCount,
      if (bagFee > 0) 'bag_fee': bagFee,
      if (pickupLocation != null) 'pickup_lat': pickupLocation!.latitude,
      if (pickupLocation != null) 'pickup_lng': pickupLocation!.longitude,
      if (destination != null) 'dropoff_lat': destination!.latitude,
      if (destination != null) 'dropoff_lng': destination!.longitude,
      // driver_lat / driver_lng intentionally NOT serialised — single source
      // of truth is DriverStore.currentDriver.location (drivers table).
    };
  }
}

extension OrderModelX on OrderModel {
  bool get isPartnerOrder => orderType == OrderType.partnerRestaurant;

  /// Human-readable order reference derived from the order UUID (e.g. `#A1B2C3`).
  /// Deterministic — no DB column needed.
  String get orderCode =>
      '#${id.replaceAll('-', '').substring(0, 6).toUpperCase()}';

  /// 4-digit delivery confirmation code derived from the order UUID (e.g. `4521`).
  /// Deterministic — no DB column needed.
  String get deliveryCode {
    final hex = id.replaceAll('-', '').substring(0, 4);
    final val = int.parse(hex, radix: 16) % 9000 + 1000;
    return val.toString();
  }
}

extension OrderFinancials on OrderModel {
  double get platformCommissionAmount {
    if (platformCommission > 0) {
      return platformCommission;
    }
    return total * _platformCommissionRate;
  }

  double get restaurantEarningsAmount => total - platformCommissionAmount;
}

extension OrderStatusLabel on OrderStatus {
  String get label {
    switch (this) {
      case OrderStatus.created:
        return 'Pedido criado';
      case OrderStatus.preparing:
        return 'Restaurante preparando';
      case OrderStatus.callingDriver:
        return 'Aguardando estafeta';
      case OrderStatus.driverAccepted:
        return 'Estafeta a caminho';
      case OrderStatus.pickedUp:
        return 'Encomenda recolhida';
      case OrderStatus.onTheWay:
        return 'Em entrega';
      case OrderStatus.delivered:
        return 'Entregue';
      case OrderStatus.rejected:
        return 'Pedido rejeitado';
      case OrderStatus.cancelled:
        return 'Pedido cancelado';
    }
  }
}

extension PaymentMethodLabel on PaymentMethod {
  String get label {
    switch (this) {
      case PaymentMethod.card:
        return 'Cartão';
      case PaymentMethod.mbway:
        return 'MBWay';
      case PaymentMethod.cash:
        return 'Dinheiro';
    }
  }
}
