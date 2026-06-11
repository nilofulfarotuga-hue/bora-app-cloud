import 'dart:math' as math;

import '../models/order_service_type.dart';

class OrderPricingBreakdown {
  final double distanceKm;
  final double subtotal;
  final double deliveryFee;
  final double serviceFee;
  final double platformCommission;
  final double driverEarnings;
  final double apartmentSurcharge;
  final bool apartmentDelivery;

  /// Bag fee charged to the customer. €0.30 for restaurant orders (automatic).
  final double bagFee;

  /// Hidden 5% markup embedded in partner product prices (not shown to client).
  /// Only populated for partner orders. For reporting/settlement purposes.
  final double partnerMarkupHidden;

  /// True when partner called the driver directly (cliente comprou direto com o
  /// parceiro). Comissão (10%) é descontada da receita do parceiro no acerto
  /// semanal — nunca cobrada ao cliente. O cliente paga apenas subtotal +
  /// taxa serviço (5%) + taxa entrega.
  final bool isPartnerSelfDispatch;

  double get customerTotal {
    return subtotal + serviceFee + deliveryFee + bagFee;
  }

  const OrderPricingBreakdown({
    required this.distanceKm,
    required this.subtotal,
    required this.deliveryFee,
    required this.serviceFee,
    required this.platformCommission,
    required this.driverEarnings,
    this.apartmentSurcharge = 0,
    this.apartmentDelivery = false,
    this.bagFee = 0,
    this.partnerMarkupHidden = 0,
    this.isPartnerSelfDispatch = false,
  });
}

class PricingService {
  static const double defaultDistanceKm = 1;

  static const double _partnerDeliveryFee = 2.5;

  /// Charged automatically for all restaurant orders (takeaway bag).
  static const double _restaurantBagFee = 0.30;

  /// Charged per bag for storeShopping orders. The checkout always sends
  /// bag_count=1, and the server (`pricing_calculate`) charges
  /// €0.10 × GREATEST(1, bag_count) — mirror it so the summary matches.
  static const double _marketBagFeePerBag = 0.10;
  // ── Driver earnings — delivery (partner + non-partner) ───────────────────
  static const double _driverBasePay = 3.80;
  static const double _driverPerKmRate = 0.2;

  // Partner commission split: 10% visible (partner pays) + 5% hidden markup
  // (in product prices) + 5% service fee (client pays at checkout) = 20% total.
  static const double _partnerCommissionRate = 0.10;     // visible to partner
  static const double _partnerServiceFeeRate = 0.05;     // charged to client
  static const double _partnerMarkupHiddenRate = 0.05;   // embedded in prices

  /// Bonus paid to driver for a 2nd stacked partner order.
  static const double _partnerStackingBonus = 3.00;

  static const double _nonPartnerMarkupRate = 0.15;
  static const double _nonPartnerPurchaseFee = 2.5;

  // Extra pay for storeShopping, carryGroceries, sendPackage drivers (they shop/carry AND deliver).
  static const double _shoppingDriverBonus = 0.80;

  // 30% of Bora net profit shared with driver (non-partner orders).
  static const double _driverProfitShareRate = 0.30;

  static const double _packageBaseFee = 6.0;
  static const double _packageBaseDistanceKm = 4.0;
  static const double _packageExtraPerKm = 0.5;
  static const double _packagePlatformShare = 2.0;
  // ── Driver earnings — logistics (carryGroceries / sendPackage) ───────────
  static const double _logisticsDriverBasePay = 4.00;
  static const double _logisticsDriverPerKmRate = 0.50;

  static const double _apartmentSurchargeTotal = 1.5;
  static const double _apartmentDriverShare = 1.0;
  static const double _apartmentPlatformShare = 0.5;

  /// Returns the customer-facing final total from the driver's real purchase value.
  /// Uses the flat non-partner fee structure (default 1 km distance).
  /// For order-accurate totals that include actual distance, use [calculateBreakdown].
  static double calculateFinalTotalFromPurchase(double purchaseValue) {
    return _roundCurrency(_sanitizeAmount(purchaseValue) +
        _nonPartnerPurchaseFee +
        _partnerDeliveryFee);
  }

  /// Returns the pre-authorisation amount for non-partner orders:
  /// [estimatedTotal] × 1.15 (15% buffer to cover price fluctuations at store).
  /// The surplus is refunded or the deficit charged after driver confirms receipt.
  static double calculateBufferedTotal(double estimatedTotal) {
    return _roundCurrency(estimatedTotal * 1.15);
  }

  /// Returns [basePrice] with the non-partner markup applied when [isPartner]
  /// is false. Partner prices are returned unchanged.
  ///
  /// Single source of truth para o preço EXIBIDO/COBRADO por unidade — chamar
  /// de todos os call sites que criam CartItem ou mostram preço de catálogo
  /// (B1 2026-06-11). NÃO arredonda: o servidor (`create_order`) aplica o
  /// markup à SOMA dos preços base e arredonda UMA vez no fim — arredondar
  /// por unidade divergia ±1 cêntimo com quantidade > 1. Arredondar apenas
  /// na formatação (`toStringAsFixed(2)`).
  static double applyMarkup(double basePrice, bool isPartner) {
    if (isPartner) return basePrice;
    return basePrice * (1 + _nonPartnerMarkupRate);
  }

  static OrderPricingBreakdown calculateBreakdown({
    required OrderServiceType serviceType,
    required double subtotal,
    required double distanceKm,
    bool isPartnerStore = false,
    bool apartmentDelivery = false,
    /// Set to true when this is the 2nd stacked partner order — adds €3 driver bonus.
    bool isStackedPartnerBonus = false,
    /// Set to true for "partner-calls-driver" flow (parceiro chama estafeta
    /// por conta própria — cliente comprou direto). Sem markup escondido
    /// (cliente já sabe o preço real). Comissão total = 15% em vez de 20%.
    bool isPartnerSelfDispatch = false,
    /// Number of bags for storeShopping orders. Checkout charges min. 1 bag
    /// (server: GREATEST(1, bag_count)) — keep default 1 to match.
    int bagCount = 1,
  }) {
    final normalizedDistance = _sanitizeDistance(distanceKm);
    final normalizedSubtotal = _sanitizeAmount(subtotal);
    final apartmentSurcharge =
        apartmentDelivery ? _apartmentSurchargeTotal : 0.0;
    final apartmentDriverBonus =
        apartmentDelivery ? _apartmentDriverShare : 0.0;
    final apartmentPlatformBonus =
        apartmentDelivery ? _apartmentPlatformShare : 0.0;

    double deliveryFee = 0;
    double serviceFee = 0;
    double platformCommission = 0;
    double driverEarnings = 0;

    final bool isPartnerRestaurant =
        serviceType == OrderServiceType.restaurant && isPartnerStore;
    final bool isPartnerRetail =
        serviceType == OrderServiceType.storeShopping && isPartnerStore;
    final bool isNonPartnerOrder =
        (serviceType == OrderServiceType.storeShopping && !isPartnerStore) ||
            (serviceType == OrderServiceType.restaurant && !isPartnerStore);
    final bool isPackageService = serviceType == OrderServiceType.sendPackage ||
        serviceType == OrderServiceType.carryGroceries;

    if (isPartnerRestaurant || isPartnerRetail) {
      // ── PARTNER ORDER ──────────────────────────────────────────────────────
      // Commission split: 10% visible (partner pays) + 5% client service fee
      // + 5% hidden markup (already embedded in product prices via CartStore).
      final extraDistancePartner =
          math.max(0.0, normalizedDistance - _packageBaseDistanceKm);
      deliveryFee = _partnerDeliveryFee +
          (extraDistancePartner * _packageExtraPerKm) +
          apartmentSurcharge;
      serviceFee = _roundCurrency(normalizedSubtotal * _partnerServiceFeeRate);
      platformCommission =
          _roundCurrency(normalizedSubtotal * _partnerCommissionRate) +
          apartmentPlatformBonus;
      // Driver: base + km + apartment + optional stacking bonus (2nd order).
      driverEarnings = _roundCurrency(_driverBasePay +
          (_driverPerKmRate * normalizedDistance) +
          apartmentDriverBonus +
          (isStackedPartnerBonus ? _partnerStackingBonus : 0.0));
    } else if (isNonPartnerOrder) {
      // ── NON-PARTNER ORDER ──────────────────────────────────────────────────
      // The 15% markup is already embedded in item prices via CartStore.addItem()
      // and is baked into normalizedSubtotal. No additional markup is applied here.
      // customerTotal = subtotal + purchaseFee + deliveryFee
      const purchaseFee = _nonPartnerPurchaseFee; // €2.50

      final extraDistanceNP =
          math.max(0.0, normalizedDistance - _packageBaseDistanceKm);
      serviceFee = purchaseFee;
      deliveryFee = _partnerDeliveryFee +
          (extraDistanceNP * _packageExtraPerKm) +
          apartmentSurcharge;
      platformCommission = purchaseFee + apartmentPlatformBonus;

      // €0.80 bonus only for storeShopping (those drivers shop + deliver).
      // Restaurant non-partner drivers do NOT get the shopping bonus.
      final shoppingBonus =
          serviceType == OrderServiceType.storeShopping ? _shoppingDriverBonus : 0.0;
      final driverFixed = _roundCurrency(_driverBasePay +
          shoppingBonus +
          (_driverPerKmRate * normalizedDistance) +
          apartmentDriverBonus);

      // Driver shares 30% of Bora net profit.
      // Bora gross = markup (already in prices) + delivery fee + service fee.
      // Bora net  = gross − driver fixed pay (before profit share).
      final boraMarkup = _roundCurrency(normalizedSubtotal * _nonPartnerMarkupRate);
      final boraGross = boraMarkup + deliveryFee + serviceFee;
      final boraNat = math.max(0.0, boraGross - driverFixed);
      driverEarnings =
          _roundCurrency(driverFixed + _roundCurrency(boraNat * _driverProfitShareRate));
    } else if (isPackageService) {
      // ── LOGISTICS (carryGroceries / sendPackage) ───────────────────────────
      final extraDistance =
          math.max(0.0, normalizedDistance - _packageBaseDistanceKm);
      final packageFee = _packageBaseFee + (extraDistance * _packageExtraPerKm);
      deliveryFee = packageFee + apartmentSurcharge;
      platformCommission = _packagePlatformShare + apartmentPlatformBonus;
      // Driver: base pay + per-km rate applied only to km beyond base distance.
      // No _shoppingDriverBonus — logistics base already accounts for the
      // collection effort (logistics_driver_base_cents = 400 cents = €4.00).
      driverEarnings = _roundCurrency(_logisticsDriverBasePay +
          (_logisticsDriverPerKmRate * extraDistance) +
          apartmentDriverBonus);
    } else {
      // ── FALLBACK (should not normally be reached) ──────────────────────────
      deliveryFee = _partnerDeliveryFee + apartmentSurcharge;
      platformCommission =
          _roundCurrency(normalizedSubtotal * _partnerCommissionRate) +
          apartmentPlatformBonus;
      driverEarnings = _roundCurrency(_driverBasePay +
          (_driverPerKmRate * normalizedDistance) +
          apartmentDriverBonus);
    }

    // Mirror of server `pricing_calculate` (B1 2026-06-11): restaurant €0.30
    // fixo; storeShopping €0.10 × GREATEST(1, bags) cobrado no checkout.
    final double bagFee = serviceType == OrderServiceType.restaurant
        ? _restaurantBagFee
        : serviceType == OrderServiceType.storeShopping
            ? _roundCurrency(_marketBagFeePerBag * math.max(1, bagCount))
            : 0.0;

    final bool isPartner = isPartnerRestaurant || isPartnerRetail;
    // Partner-calls-driver: SEM markup escondido. Cliente comprou direto com
    // o parceiro e já conhece o preço real, portanto a Bora não pode embutir
    // 5% no preço do produto neste fluxo.
    final double computedMarkupHidden = (isPartner && !isPartnerSelfDispatch)
        ? _roundCurrency(normalizedSubtotal * _partnerMarkupHiddenRate)
        : 0.0;
    return OrderPricingBreakdown(
      distanceKm: normalizedDistance,
      subtotal: normalizedSubtotal,
      deliveryFee: _roundCurrency(deliveryFee),
      serviceFee: _roundCurrency(serviceFee),
      platformCommission: _roundCurrency(platformCommission),
      driverEarnings: _roundCurrency(driverEarnings),
      apartmentSurcharge: _roundCurrency(apartmentSurcharge),
      apartmentDelivery: apartmentDelivery,
      bagFee: bagFee,
      partnerMarkupHidden: computedMarkupHidden,
      isPartnerSelfDispatch: isPartnerSelfDispatch && isPartner,
    );
  }

  /// Quick estimate of the delivery fee for a restaurant card preview.
  /// Matches the breakdown formula: base partner fee + €0.50/km beyond 4 km.
  static double estimatedDeliveryFee({
    required double distanceKm,
    required bool isPartner,
  }) {
    final d = _sanitizeDistance(distanceKm);
    final overage = d > 4 ? (d - 4) * 0.5 : 0.0;
    return _roundCurrency(_partnerDeliveryFee + overage);
  }

  static double _sanitizeDistance(double distanceKm) {
    if (!distanceKm.isFinite || distanceKm <= 0) {
      return defaultDistanceKm;
    }
    return distanceKm;
  }

  static double _sanitizeAmount(double value) {
    if (!value.isFinite || value <= 0) {
      return 0.0;
    }
    return _roundCurrency(value);
  }

  static double _roundCurrency(double value) {
    return double.parse(value.toStringAsFixed(2));
  }
}
