import 'package:latlong2/latlong.dart';

import '../models/driver_model.dart';
import '../models/order_model.dart';

class DriverCapacityService {
  /// Maximum concurrent orders a driver may carry across all service types.
  static const int maxBatchOrders = 3;

  /// Radius within which different-vendor pickups may be batched.
  static const double _batchRadiusKm = 1.0;

  DriverCapacityService({
    Distance? distance,
    // Legacy named params kept for API compatibility — no longer used.
    double partnerRadiusMeters = 800,
    int partnerMaxOrders = 2,
    int nonPartnerMaxOrders = 3,
  }) : _distance = distance ?? const Distance();

  final Distance _distance;

  /// Returns true when [order] can be assigned to [driver].
  ///
  /// Rules:
  /// - Driver must be online.
  /// - Partner restaurant orders cannot be batched in either direction
  ///   (neither a new partner-restaurant order nor an existing assignment
  ///   of that type allows further stacking).
  /// - All other service types (non-partner, store shopping, carry-groceries,
  ///   send-package) may be batched up to [maxBatchOrders], provided the new
  ///   pickup shares a vendor with an existing assignment OR is within
  ///   [_batchRadiusKm] km of one.
  bool canAssignOrder(DriverModel driver, OrderModel order) {
    if (!driver.isOnline) return false;

    final assignments = driver.activeAssignments;
    if (assignments.isEmpty) return true;

    // Partner restaurant orders cannot be batched in either direction.
    if (_isPartnerRestaurant(order)) return false;
    if (assignments.any(_isPartnerRestaurantAssignment)) return false;

    // Hard cap on concurrent orders.
    if (assignments.length >= maxBatchOrders) return false;

    // New pickup must share a vendor OR be within 1 km of an existing pickup.
    return _isCompatibleWithExisting(assignments, order);
  }

  /// Returns true when [driver] should be prioritised for [order] because
  /// they already carry an order from the same vendor.
  bool shouldPrioritize(OrderModel order, DriverModel driver) {
    if (_isPartnerRestaurant(order)) return false;
    final vendorName = order.vendorName;
    if (vendorName == null) return false;
    return driver.activeAssignments.any(
      (info) => info.vendorName != null && info.vendorName == vendorName,
    );
  }

  bool _isCompatibleWithExisting(
    List<DriverAssignmentInfo> assignments,
    OrderModel order,
  ) {
    // A picked-up order locks the driver to that vendor — different vendor is incompatible.
    final hasPickedUpConflict = assignments.any(
      (info) =>
          info.hasBeenPickedUp &&
          info.vendorName != null &&
          info.vendorName != order.vendorName,
    );
    if (hasPickedUpConflict) return false;

    // Same vendor is always compatible regardless of distance.
    final vendorName = order.vendorName;
    if (vendorName != null) {
      final hasSameVendor = assignments.any(
        (info) => info.vendorName != null && info.vendorName == vendorName,
      );
      if (hasSameVendor) return true;
    }

    // Different vendor — require new pickup to be within 1 km of an existing one.
    final pickup = order.pickupLocation;
    if (pickup == null) return false;

    return assignments.any((info) {
      final existingPickup = info.pickupLocation;
      if (existingPickup == null) return false;
      final distanceKm =
          _distance.as(LengthUnit.Kilometer, existingPickup, pickup);
      return distanceKm <= _batchRadiusKm;
    });
  }

  bool _isPartnerRestaurant(OrderModel order) =>
      order.serviceType == OrderServiceType.restaurant && order.isPartnerStore;

  bool _isPartnerRestaurantAssignment(DriverAssignmentInfo info) =>
      info.isPartnerOrder && info.serviceType == OrderServiceType.restaurant;
}
