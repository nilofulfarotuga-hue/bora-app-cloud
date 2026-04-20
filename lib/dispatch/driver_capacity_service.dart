import '../models/driver_model.dart';
import '../models/order_model.dart';

class DriverCapacityService {
  /// Maximum concurrent orders a driver may carry across all service types.
  static const int maxBatchOrders = 3;

  DriverCapacityService({
    // Legacy named params kept for API compatibility — no longer used.
    double partnerRadiusMeters = 800,
    int partnerMaxOrders = 2,
    int nonPartnerMaxOrders = 3,
  });

  /// Returns true when [order] can be assigned to [driver].
  ///
  /// Rules:
  /// - Driver must be online.
  /// - Up to [maxBatchOrders] concurrent orders allowed.
  /// - Dispatch engine (server) decides assignment via FIFO ≤ 200 m + distance.
  bool canAssignOrder(DriverModel driver, OrderModel order) {
    if (!driver.isOnline) return false;
    final assignments = driver.activeAssignments;
    if (assignments.isEmpty) return true;
    if (assignments.length >= maxBatchOrders) return false;
    return true;
  }

  /// Returns true when [driver] should be prioritised for [order] because
  /// they already carry an order from the same vendor.
  bool shouldPrioritize(OrderModel order, DriverModel driver) {
    final vendorName = order.vendorName;
    if (vendorName == null) return false;
    return driver.activeAssignments.any(
      (info) => info.vendorName != null && info.vendorName == vendorName,
    );
  }
}
