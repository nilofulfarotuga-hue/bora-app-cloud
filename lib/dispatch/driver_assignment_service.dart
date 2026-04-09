import 'package:flutter/foundation.dart';
import 'package:latlong2/latlong.dart';

import '../models/driver_model.dart';
import '../models/order_model.dart';
import '../stores/driver_store.dart';
import 'dispatch_service.dart';
import 'driver_capacity_service.dart';

class DriverAssignmentService {
  DriverAssignmentService({
    required DriverStore driverStore,
    required DriverCapacityService capacityService,
    Distance? distance,
    double costPerKm = 1.0,
  })  : _driverStore = driverStore,
        _capacityService = capacityService,
        _distance = distance ?? const Distance(),
        _dispatchService = DispatchService(
          driverStore: driverStore,
          capacityService: capacityService,
          costPerKm: costPerKm,
        );

  final DriverStore _driverStore;
  final DriverCapacityService _capacityService;
  final Distance _distance;

  /// Improved ranking delegate — uses Haversine + composite score + ETA.
  final DispatchService _dispatchService;

  // ── Public API ─────────────────────────────────────────────────────────────

  /// Returns drivers eligible for [order], ranked best-first.
  ///
  /// Tries [DispatchService] first (Haversine + score).
  /// Falls back to the original distance-only sort if the improved service
  /// returns an empty list (e.g. missing coordinates, unexpected error).
  List<DriverModel> findEligibleDrivers(OrderModel order) {
    // ── Attempt: improved ranking ──────────────────────────────────────────
    final ranked = _dispatchService.rankDrivers(
      order,
      attemptedIds: order.driverOfferHistory,
    );

    if (ranked.isNotEmpty) {
      debugPrint(
        '[DriverAssignment] scored ranking returned ${ranked.length} driver(s) '
        'for order=${order.id}',
      );
      return ranked.map((r) => r.driver).toList(growable: false);
    }

    // ── Fallback: original distance-only logic (unchanged) ─────────────────
    debugPrint(
      '[DriverAssignment] falling back to original distance-only ranking '
      'for order=${order.id}',
    );
    return _originalFindEligibleDrivers(order);
  }

  /// Returns the single best driver for [order], or `null` if none found.
  DriverModel? findBestDriver(OrderModel order) {
    final candidates = findEligibleDrivers(order);
    if (candidates.isEmpty) return null;
    return candidates.first;
  }

  /// Returns the [DispatchResult] for the best driver, including ETA.
  /// Returns `null` when no scored candidates are available (use [findBestDriver]
  /// instead in that case).
  DispatchResult? findBestDriverWithEta(OrderModel order) {
    return _dispatchService.findBestDriver(
      order,
      attemptedIds: order.driverOfferHistory,
    );
  }

  bool isDriverEligible(
    DriverModel driver,
    OrderModel order, {
    bool ignoreHistory = false,
  }) {
    if (!driver.isOnline) return false;
    if (!driver.supportsService(order.serviceType,
        requiresCar: order.requiresCar)) return false;
    if (!ignoreHistory && order.driverOfferHistory.contains(driver.id)) {
      return false;
    }
    return _capacityService.canAssignOrder(driver, order);
  }

  // ── Original logic (fallback — DO NOT MODIFY) ─────────────────────────────

  List<DriverModel> _originalFindEligibleDrivers(OrderModel order) {
    final pickupPoint = order.pickupLocation ?? order.destination;
    final candidates = <_DriverCandidate>[];

    for (final driver in _driverStore.onlineDrivers) {
      if (!driver.supportsService(order.serviceType,
          requiresCar: order.requiresCar)) {
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

    return candidates.map((c) => c.driver).toList(growable: false);
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
