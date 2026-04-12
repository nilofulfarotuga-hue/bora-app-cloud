import 'package:latlong2/latlong.dart';

import '../models/order_model.dart';

enum RouteStopType { pickup, delivery }

class RouteStop {
  const RouteStop({
    required this.type,
    required this.orderId,
    required this.location,
    this.label,
  });

  final RouteStopType type;
  final String orderId;
  final LatLng location;

  /// Human-readable address for display in the map panel.
  final String? label;

  bool get isPickup => type == RouteStopType.pickup;
}

class OptimizedRoute {
  const OptimizedRoute({
    required this.stops,
    required this.totalDistanceKm,
  });

  const OptimizedRoute.empty()
      : stops = const [],
        totalDistanceKm = 0;

  final List<RouteStop> stops;
  final double totalDistanceKm;

  bool get isEmpty => stops.isEmpty;

  List<LatLng> get allLocations =>
      stops.map((s) => s.location).toList(growable: false);
}

/// Greedy nearest-neighbour route optimizer for multi-order deliveries.
///
/// Phase 1 — pickups: sequences all pending pickup stops by proximity to
/// the driver, starting from [driverPosition].
///
/// Phase 2 — deliveries: sequences all delivery stops by proximity,
/// starting from the last pickup position (or driver if no pickups).
///
/// Orders already in [pickedUp] or [onTheWay] status skip the pickup phase.
class RouteOptimizer {
  static const _dist = Distance();

  static OptimizedRoute optimize(
    List<OrderModel> orders,
    LatLng driverPosition,
  ) {
    if (orders.isEmpty) return const OptimizedRoute.empty();

    final pendingPickups = orders
        .where(
          (o) =>
              o.status == OrderStatus.driverAccepted &&
              o.pickupLocation != null,
        )
        .toList();

    // Delivery stops are only added after the driver has physically collected
    // the order. While the driver is still heading to pickup (driverAccepted),
    // only the pickup stop is shown so the route is clear and unambiguous.
    final pendingDeliveries = orders
        .where(
          (o) =>
              o.destination != null &&
              (o.status == OrderStatus.pickedUp ||
                  o.status == OrderStatus.onTheWay),
        )
        .toList();

    final stops = <RouteStop>[];
    var current = driverPosition;
    double totalKm = 0;

    // Phase 1: sequence pickups (greedy nearest-neighbour).
    final remainingPickups = List<OrderModel>.of(pendingPickups);
    while (remainingPickups.isNotEmpty) {
      final nearest = _nearest(remainingPickups, current, (o) => o.pickupLocation!);
      final loc = nearest.pickupLocation!;
      totalKm += _dist.as(LengthUnit.Kilometer, current, loc);
      stops.add(RouteStop(
        type: RouteStopType.pickup,
        orderId: nearest.id,
        location: loc,
        label: nearest.pickupAddress,
      ));
      current = loc;
      remainingPickups.remove(nearest);
    }

    // Phase 2: sequence deliveries (greedy nearest-neighbour).
    final remainingDeliveries = List<OrderModel>.of(pendingDeliveries);
    while (remainingDeliveries.isNotEmpty) {
      final nearest = _nearest(remainingDeliveries, current, (o) => o.destination!);
      final loc = nearest.destination!;
      totalKm += _dist.as(LengthUnit.Kilometer, current, loc);
      stops.add(RouteStop(
        type: RouteStopType.delivery,
        orderId: nearest.id,
        location: loc,
        label: nearest.dropoffAddress,
      ));
      current = loc;
      remainingDeliveries.remove(nearest);
    }

    return OptimizedRoute(stops: stops, totalDistanceKm: totalKm);
  }

  static T _nearest<T>(List<T> items, LatLng from, LatLng Function(T) loc) {
    T? best;
    double minDist = double.infinity;
    for (final item in items) {
      final d = _dist.as(LengthUnit.Kilometer, from, loc(item));
      if (d < minDist) {
        minDist = d;
        best = item;
      }
    }
    return best!;
  }
}
