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

  double get customerTotal => subtotal + serviceFee + deliveryFee;

  const OrderPricingBreakdown({
    required this.distanceKm,
    required this.subtotal,
    required this.deliveryFee,
    required this.serviceFee,
    required this.platformCommission,
    required this.driverEarnings,
    this.apartmentSurcharge = 0,
    this.apartmentDelivery = false,
  });
}

class PricingService {
  static const double defaultDistanceKm = 1;

    static const double _partnerDeliveryFee = 2.5;
  static const double _driverBasePay = 4.0;
  static const double _driverPerKmRate = 0.2;
  static const double _partnerCommissionRate = 0.20;

  static const double _nonPartnerMarkupRate = 0.15;
  static const double _nonPartnerPurchaseFee = 2.5;
  static const double _nonPartnerPurchaseBonus = 1.0;
  static const double _driverPlatformShareRate = 0.20;

  static const double _packageBaseFee = 6.0;
  static const double _packageBaseDistanceKm = 4.0;
  static const double _packageExtraPerKm = 0.5;
  static const double _packagePlatformShare = 2.0;

  static const double _apartmentSurchargeTotal = 1.5;
  static const double _apartmentDriverShare = 1.0;
  static const double _apartmentPlatformShare = 0.5;


  /// Returns the customer-facing final total from the driver's real purchase value.
  /// Uses the flat non-partner fee structure (default 1 km distance).
  /// For order-accurate totals that include actual distance, use [calculateBreakdown].
  static double calculateFinalTotalFromPurchase(double purchaseValue) {
    return _roundCurrency(
        _sanitizeAmount(purchaseValue) + _nonPartnerPurchaseFee + _partnerDeliveryFee);
  }

  /// Returns the pre-authorisation amount for non-partner orders:
  /// [estimatedTotal] × 1.15 (15% buffer to cover price fluctuations at store).
  /// The surplus is refunded or the deficit charged after driver confirms receipt.
  static double calculateBufferedTotal(double estimatedTotal) {
    return _roundCurrency(estimatedTotal * 1.15);
  }

  /// Returns [basePrice] with the non-partner markup applied when [isPartner]
  /// is false. Partner prices are returned unchanged.
  /// This is the single source of truth for markup — call only from CartStore.
  static double applyMarkup(double basePrice, bool isPartner) {
    if (isPartner) return basePrice;
    return _roundCurrency(basePrice * (1 + _nonPartnerMarkupRate));
  }

  static OrderPricingBreakdown calculateBreakdown({
    required OrderServiceType serviceType,
    required double subtotal,
    required double distanceKm,
    bool isPartnerStore = false,
    bool apartmentDelivery = false,
  }) {
        final normalizedDistance = _sanitizeDistance(distanceKm);
    final normalizedSubtotal = _sanitizeAmount(subtotal);
    final apartmentSurcharge = apartmentDelivery ? _apartmentSurchargeTotal : 0.0;
    final apartmentDriverBonus = apartmentDelivery ? _apartmentDriverShare : 0.0;
    final apartmentPlatformBonus = apartmentDelivery ? _apartmentPlatformShare : 0.0;

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
    final bool isPackageService =
        serviceType == OrderServiceType.sendPackage ||
        serviceType == OrderServiceType.carryGroceries;

    if (isPartnerRestaurant || isPartnerRetail) {
      final extraDistancePartner = math.max(0.0, normalizedDistance - _packageBaseDistanceKm);
      deliveryFee = _partnerDeliveryFee + (extraDistancePartner * _packageExtraPerKm) + apartmentSurcharge;
      platformCommission = normalizedSubtotal * _partnerCommissionRate + apartmentPlatformBonus;
      driverEarnings = _driverBasePay + (_driverPerKmRate * normalizedDistance) + apartmentDriverBonus;
    } else if (isNonPartnerOrder) {
      // The 15% markup is already applied to item prices in CartStore.addItem()
      // and is baked into normalizedSubtotal. Only the flat purchase fee is
      // added here — adding markup again would double-count.
      const purchaseFee = _nonPartnerPurchaseFee;

      serviceFee = purchaseFee;
      deliveryFee = _partnerDeliveryFee + apartmentSurcharge;
      platformCommission = purchaseFee + apartmentPlatformBonus;
      driverEarnings = _driverBasePay +
          (_driverPerKmRate * normalizedDistance) +
          _nonPartnerPurchaseBonus +
          (_driverPlatformShareRate * purchaseFee) +
          apartmentDriverBonus;
        } else if (isPackageService) {
      final extraDistance = math.max(0.0, normalizedDistance - _packageBaseDistanceKm);
      deliveryFee = _packageBaseFee + (extraDistance * _packageExtraPerKm) + apartmentSurcharge;
      platformCommission = _packagePlatformShare + apartmentPlatformBonus;
      driverEarnings = _driverBasePay + (extraDistance * _packageExtraPerKm) + apartmentDriverBonus;

    } else {
      deliveryFee = _partnerDeliveryFee + apartmentSurcharge;
      platformCommission = normalizedSubtotal * _partnerCommissionRate + apartmentPlatformBonus;
      driverEarnings = _driverBasePay + (_driverPerKmRate * normalizedDistance) + apartmentDriverBonus;
    }

    return OrderPricingBreakdown(
      distanceKm: normalizedDistance,
      subtotal: normalizedSubtotal,
      deliveryFee: _roundCurrency(deliveryFee),
      serviceFee: _roundCurrency(serviceFee),
      platformCommission: _roundCurrency(platformCommission),
      driverEarnings: _roundCurrency(driverEarnings),
      apartmentSurcharge: _roundCurrency(apartmentSurcharge),
      apartmentDelivery: apartmentDelivery,
    );
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