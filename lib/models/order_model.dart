export 'order_service_type.dart';

import 'package:latlong2/latlong.dart';
import 'package:uuid/uuid.dart';

import 'cart_item.dart';
import 'order_service_type.dart';

const double _platformCommissionRate = 0.20;

enum OrderStatus {
  created,
  preparing,
  // BR §14.11 — takeaway only. Status do parceiro depois de marcar pronto;
  // cliente apresenta takeaway_pickup_code no balcão. Inserido entre
  // preparing e callingDriver para preservar semântica de comparações
  // `.index <= callingDriver.index` (mantém pedido takeaway como activo
  // até cliente levantar).
  readyForPickup,
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
  // BUG 7 (2026-05-15) — adicionados para cobrir todos os service_types.
  // .name é o que é gravado em orders.order_type (sem CHECK constraint em DB).
  takeaway,
  sendPackage,
  carryGroceries,
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
  /// orders.restaurant_id — UUID/text do parceiro (restaurant/supermarket).
  /// Use este campo (não vendorName) como subject_id em ratings partner.
  final String? restaurantId;
  /// orders.purchase_flow_version — 1=legacy v1, 2=novo fluxo storeShopping v2.
  /// UI client decide se mostra badges/breakdown novos com base neste campo.
  final int purchaseFlowVersion;
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

  /// True quando o pedido foi marcado como teste (admin/QA).
  /// Filtrado por defeito do painel admin para nao poluir metricas reais.
  /// Coluna DB: orders.is_test_order (BOOLEAN DEFAULT false).
  final bool isTestOrder;
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

  /// BUG #1 frontend (§54 / 2026-05-12) — cents da dívida prévia da wallet
  /// do cliente que é cobrada via este pedido. Populado pela RPC create_order
  /// quando v_wallet_balance_pre<0. Default 0. Driver UI em CASH cobra:
  /// totalToCollectCash = (cashTotalDue ?? finalTotal ?? total) + debtCollectedCents/100.
  final int debtCollectedCents;

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

  /// BR §14.11 — código alfanumérico 6 chars gerado pelo servidor ao criar
  /// pedido takeaway. Cliente apresenta no balcão. NULL para delivery.
  final String? takeawayPickupCode;

  /// Timestamp quando partner_takeaway_accept foi chamado, dando ETA ao cliente.
  /// = createdAt + takeawayPrepMinutes. NULL para delivery.
  final DateTime? takeawayReadyAt;

  /// Timestamp quando parceiro marcou levantado (status → delivered).
  /// NULL até levantamento.
  final DateTime? takeawayPickedUpAt;

  /// Minutos de preparação anunciados pelo parceiro ao aceitar (3/5/10/15/20/30/45/60).
  /// Default vem de restaurants.takeaway_default_prep_minutes. NULL para delivery.
  final int? takeawayPrepMinutes;

  /// True se cliente vai esperar no carro (curbside). Default false.
  /// Imutável pós payment_status='paid' (D6, UI-only guard).
  final bool takeawayIsCurbside;

  /// Texto livre cliente preencheu para curbside (matrícula/cor/modelo).
  /// Imutável pós payment_status='paid' (D6, UI-only guard).
  final String? takeawayCurbsideInfo;

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
    this.restaurantId,
    this.purchaseFlowVersion = 1,
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
    this.isTestOrder = false,
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
    this.debtCollectedCents = 0,
    this.extraChargeAmount,
    this.cashTotalDue,
    List<Map<String, dynamic>>? itemsAdded,
    this.tipCents = 0,
    this.takeawayPickupCode,
    this.takeawayReadyAt,
    this.takeawayPickedUpAt,
    this.takeawayPrepMinutes,
    this.takeawayIsCurbside = false,
    this.takeawayCurbsideInfo,
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

  // BUG #1 frontend (§54 / 2026-05-12) — Driver UI helpers em CASH
  /// Total a cobrar do cliente em dinheiro: pedido + dívida prévia (se houver).
  /// Hierarquia: cashTotalDue (set pelo finalize_storeshopping_purchase para sacos)
  /// → finalTotal (set pelo finalize quando há reconcile) → total (price original).
  /// + dívida em cents convertida a EUR.
  double get totalToCollectCash =>
      (cashTotalDue ?? finalTotal ?? total) + debtCollectedCents / 100.0;

  /// True se este pedido inclui cobrança de dívida prévia da wallet do cliente.
  bool get hasCashDebt => debtCollectedCents > 0;

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
      isTestOrder: data['is_test_order'] as bool? ?? false,
      apartmentDelivery: data['apartment_delivery'] as bool? ?? false,
      isDistanceEstimated: data['is_distance_estimated'] as bool? ?? false,
      requiresCar: data['requires_car'] as bool? ?? false,
      vendorName: data['vendor_name'] as String?,
      restaurantId: data['restaurant_id'] as String?,
      purchaseFlowVersion: (data['purchase_flow_version'] as num?)?.toInt() ?? 1,
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
      debtCollectedCents:
          (data['debt_collected_cents'] as num?)?.toInt() ?? 0,
      extraChargeAmount: (data['extra_charge_amount'] as num?)?.toDouble(),
      cashTotalDue: (data['cash_total_due'] as num?)?.toDouble(),
      itemsAdded: parsedItemsAdded,
      tipCents: (data['tip_amount_cents'] as num?)?.toInt() ?? 0,
      takeawayPickupCode: data['takeaway_pickup_code'] as String?,
      takeawayReadyAt: data['takeaway_ready_at'] != null
          ? DateTime.tryParse(data['takeaway_ready_at'].toString())
          : null,
      takeawayPickedUpAt: data['takeaway_picked_up_at'] != null
          ? DateTime.tryParse(data['takeaway_picked_up_at'].toString())
          : null,
      takeawayPrepMinutes: (data['takeaway_prep_minutes'] as num?)?.toInt(),
      takeawayIsCurbside: data['takeaway_is_curbside'] as bool? ?? false,
      takeawayCurbsideInfo: data['takeaway_curbside_info'] as String?,
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
      // Apenas serializa quando true (rows existentes assumem default false).
      if (isTestOrder) 'is_test_order': isTestOrder,
      'apartment_delivery': apartmentDelivery,
      'is_distance_estimated': isDistanceEstimated,
      'requires_car': requiresCar,
      'vendor_name': vendorName,
      if (restaurantId != null) 'restaurant_id': restaurantId,
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
      if (debtCollectedCents > 0) 'debt_collected_cents': debtCollectedCents,
      if (extraChargeAmount != null) 'extra_charge_amount': extraChargeAmount,
      if (cashTotalDue != null) 'cash_total_due': cashTotalDue,
      if (itemsAdded.isNotEmpty) 'items_added': itemsAdded,
      // BR §4.5 — canonical tip column is `tip_amount_cents` (not `tip_cents`).
      // rating_screen.dart also writes to this column + sets tip_added_at.
      'tip_amount_cents': tipCents,
      if (tipCents > 0) 'tip_added_at': DateTime.now().toUtc().toIso8601String(),
      // Coluna `is_takeaway` foi APAGADA do servidor (2026-05-13).
      // Fonte de verdade: service_type='takeaway'. Curbside é cliente-input
      // gravado pelo RPC create_order — UPSERT directo aqui inclui apenas
      // estes 2 campos.
      if (takeawayIsCurbside) 'takeaway_is_curbside': true,
      if (takeawayCurbsideInfo != null && takeawayCurbsideInfo!.isNotEmpty)
        'takeaway_curbside_info': takeawayCurbsideInfo,
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

  /// BR §14.11 — getter compatível com call sites antigos. Substitui o
  /// campo bool `isTakeaway` removido. Fonte de verdade: serviceType.
  bool get isTakeaway => serviceType == OrderServiceType.takeaway;

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
      case OrderStatus.readyForPickup:
        return 'Pronto para levantar';
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
