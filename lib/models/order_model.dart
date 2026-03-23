export 'order_service_type.dart';

import 'package:latlong2/latlong.dart';
import 'package:uuid/uuid.dart';

import 'cart_item.dart';
import 'order_service_type.dart';

const double _platformCommissionRate = 0.20;
const double _restaurantEarningsRate = 1 - _platformCommissionRate;

enum OrderStatus {
  created,
  preparing,
  callingDriver,
  driverAccepted,
  pickedUp,
  onTheWay,
  delivered,
  rejected,
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
  pending,       // awaiting payment confirmation
  paid,          // fully settled
  failed,        // payment failed
  refundPending, // reconciliation: surplus to return to client
  refunded,      // backend processed the refund
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

  /// Positive extra charge when [finalTotal] > [paymentBufferTotal].
  double? extraChargeAmount;

  final String? customerName;
  final String? userId;
  final List<CartItem> items;

  String? assignedDriverId;
  String? currentDriverOfferId;
  String? driverPhone;

  /// Real-time driver coordinates — written by [DriverLocationService] via
  /// Supabase UPDATE and received on the client via Realtime.
  double? driverLat;
  double? driverLng;
  final List<String> driverOfferHistory;
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
    List<String>? driverOfferHistory,
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
    this.extraChargeAmount,
    Map<String, bool>? substitutionResponses,
  })  : estimatedTotal = estimatedTotal ?? total,
        paymentBufferTotal = paymentBufferTotal ?? total,
        substitutionResponses = substitutionResponses ?? <String, bool>{},
        items = List<CartItem>.unmodifiable(items ?? const <CartItem>[]),
        id = id ?? const Uuid().v4(),
        createdAt = createdAt ?? DateTime.now(),
        driverOfferHistory = driverOfferHistory ?? <String>[];

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
    final offerHistory = historyRaw is List
        ? List<String>.from(historyRaw)
        : <String>[];

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
      pickupLocation: pickupLocation,
      destination: destination,
      createdAt: data['created_at'] != null
          ? DateTime.tryParse(data['created_at'].toString()) ?? DateTime.now()
          : DateTime.now(),
      driverOfferExpiresAt: driverOfferExpiresAt,
      driverOfferHistory: offerHistory,
      paymentStatus: paymentStatus,
      paymentIntentId: data['payment_intent_id'] as String?,
      estimatedTotal: (data['estimated_total'] as num?)?.toDouble(),
      finalPurchaseValue: (data['final_purchase_value'] as num?)?.toDouble(),
      finalTotal: (data['final_total'] as num?)?.toDouble(),
      isPurchaseFinalized: data['is_purchase_finalized'] as bool? ?? false,
      paymentBufferTotal: (data['payment_buffer_total'] as num?)?.toDouble(),
      refundAmount: (data['refund_amount'] as num?)?.toDouble(),
      extraChargeAmount: (data['extra_charge_amount'] as num?)?.toDouble(),
      driverLat: (data['driver_lat'] as num?)?.toDouble(),
      driverLng: (data['driver_lng'] as num?)?.toDouble(),
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
      if (extraChargeAmount != null) 'extra_charge_amount': extraChargeAmount,
      if (paymentIntentId != null) 'payment_intent_id': paymentIntentId,
      if (finalPurchaseValue != null) 'final_purchase_value': finalPurchaseValue,
      if (finalTotal != null) 'final_total': finalTotal,
      if (substitutionResponses.isNotEmpty)
        'substitution_responses': substitutionResponses,
      if (pickupLocation != null) 'pickup_lat': pickupLocation!.latitude,
      if (pickupLocation != null) 'pickup_lng': pickupLocation!.longitude,
      if (destination != null) 'dropoff_lat': destination!.latitude,
      if (destination != null) 'dropoff_lng': destination!.longitude,
      if (driverLat != null) 'driver_lat': driverLat,
      if (driverLng != null) 'driver_lng': driverLng,
    };
  }
}

extension OrderModelX on OrderModel {
  bool get isPartnerOrder => orderType == OrderType.partnerRestaurant;
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