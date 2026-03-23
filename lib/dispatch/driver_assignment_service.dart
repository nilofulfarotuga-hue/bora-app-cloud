import 'package:latlong2/latlong.dart';

import '../models/driver_model.dart';
import '../models/order_model.dart';
import '../stores/driver_store.dart';
import 'driver_capacity_service.dart';

class DriverAssignmentService {
  DriverAssignmentService({
    required DriverStore driverStore,
    required DriverCapacityService capacityService,
    Distance? distance,
  })  : _driverStore = driverStore,
        _capacityService = capacityService,
        _distance = distance ?? const Distance();

  final DriverStore _driverStore;
  final DriverCapacityService _capacityService;
  final Distance _distance;

  List<DriverModel> findEligibleDrivers(OrderModel order) {
    final pickupPoint = order.pickupLocation ?? order.destination;
    final candidates = <_DriverCandidate>[];

    for (final driver in _driverStore.onlineDrivers) {
      if (!driver.supportsService(order.serviceType)) {
        continue;
      }
      if (order.driverOfferHistory.contains(driver.id)) {
        continue;
      }
      if (!_capacityService.canAssignOrder(driver, order)) {
        continue;
      }

      final distanceKm = pickupPoint == null
          ? double.infinity
          : _distance.as(LengthUnit.Kilometer, driver.location, pickupPoint);

      final isPriority = _capacityService.shouldPrioritize(order, driver);

      candidates.add(
        _DriverCandidate(
          driver: driver,
          distanceKm: distanceKm,
          priority: isPriority,
        ),
      );
    }

    candidates.sort((a, b) {
      if (a.priority != b.priority) {
        return a.priority ? -1 : 1;
      }
      return a.distanceKm.compareTo(b.distanceKm);
    });

    return candidates.map((candidate) => candidate.driver).toList(growable: false);
  }

  DriverModel? findBestDriver(OrderModel order) {
    final candidates = findEligibleDrivers(order);
    if (candidates.isEmpty) {
      return null;
    }
    return candidates.first;
  }

  bool isDriverEligible(
    DriverModel driver,
    OrderModel order, {
    bool ignoreHistory = false,
  }) {
    if (!driver.isOnline) return false;
    if (!driver.supportsService(order.serviceType)) return false;
    if (!ignoreHistory && order.driverOfferHistory.contains(driver.id)) {
      return false;
    }
    return _capacityService.canAssignOrder(driver, order);
  }
}

class _DriverCandidate {
  const _DriverCandidate({
    required this.driver,
    required this.distanceKm,
    required this.priority,
  });

  final DriverModel driver;
  final double distanceKm;
  final bool priority;
}
