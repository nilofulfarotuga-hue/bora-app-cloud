import 'package:latlong2/latlong.dart';

import '../models/order_model.dart';

/// Computes a rough ETA (minutes remaining) until the client receives the
/// order. Uses haversine distance + a fixed average scooter speed. Not meant
/// to be precise — this matches what Uber Eats / Glovo show on their cards.
class OrderEtaService {
  // roundResult:false — o latlong2 arredonda AO QUILOMETRO INTEIRO por
  // defeito. Com o default, um restaurante a 380 m dava "0 km" e tres
  // fast-food a 2,03 / 2,12 / 2,36 km davam todos "2 km" — e essa distancia
  // alimenta a TAXA DE ENTREGA ESTIMADA mostrada na lista e na ficha da loja
  // (PricingService.estimatedDeliveryFee), alem do ETA.
  // O teste order_eta_service_distance_test ja apanhava isto: esperava 4
  // distancias distintas e recebia 2.
  // Nao mexe no que e COBRADO — quem manda no preco final e o servidor.
  static const _distance = Distance(roundResult: false);

  /// Average urban scooter speed used for all trip legs.
  static const double avgSpeedKmh = 25.0;

  /// Restaurant prep time buffer (applied while status is still at the
  /// restaurant — created / preparing / callingDriver).
  static const int prepBufferMin = 8;

  /// Handoff buffer added when the driver is on the way to the pickup —
  /// accounts for parking + picking up the bag.
  static const int pickupBufferMin = 2;

  /// Returns estimated minutes remaining, rounded up to the nearest 5 min
  /// (minimum 5). Returns null when we cannot compute a meaningful value.
  static int? minutesRemaining(OrderModel order) {
    switch (order.status) {
      case OrderStatus.delivered:
      case OrderStatus.rejected:
      case OrderStatus.cancelled:
      case OrderStatus.readyForPickup:
        // Takeaway: sem driver, sem ETA de entrega. UI mostra `takeawayReadyAt`
        // ou `takeawayPrepMinutes` directamente (PickupCodeCard).
        return null;
      case OrderStatus.created:
      case OrderStatus.preparing:
      case OrderStatus.callingDriver:
        // Driver not assigned yet — assume full trip + prep buffer.
        final km = _fullTripKm(order);
        if (km == null) return null;
        return _round5((km / avgSpeedKmh) * 60 + prepBufferMin);
      case OrderStatus.driverAccepted:
        // Driver moving to pickup → then pickup → drop.
        final driver = _driverLatLng(order);
        final pickup = order.pickupLocation;
        final drop = order.destination;
        if (driver == null || pickup == null || drop == null) {
          final km = _fullTripKm(order);
          if (km == null) return null;
          return _round5((km / avgSpeedKmh) * 60 + pickupBufferMin);
        }
        final toPickup =
            _distance.as(LengthUnit.Kilometer, driver, pickup);
        final toDrop = _distance.as(LengthUnit.Kilometer, pickup, drop);
        return _round5(
            ((toPickup + toDrop) / avgSpeedKmh) * 60 + pickupBufferMin);
      case OrderStatus.pickedUp:
      case OrderStatus.onTheWay:
        // Driver heading to the client — only the last leg matters.
        final driver = _driverLatLng(order);
        final drop = order.destination;
        if (driver == null || drop == null) return null;
        final km = _distance.as(LengthUnit.Kilometer, driver, drop);
        return _round5((km / avgSpeedKmh) * 60);
    }
  }

  /// Delivery window (min,max) minutes for a restaurant card preview.
  /// Uses haversine client↔restaurant distance + prep buffer. Returns null
  /// when we don't have enough coords to guess.
  static (int, int)? deliveryWindowMinutes({
    required LatLng? clientLocation,
    required LatLng? restaurantLocation,
  }) {
    if (clientLocation == null || restaurantLocation == null) return null;
    final km = _distance.as(
        LengthUnit.Kilometer, clientLocation, restaurantLocation);
    final base = (km / avgSpeedKmh) * 60 + prepBufferMin;
    final minMin = _round5Floor(base);
    final maxMin = minMin + 10;
    return (minMin, maxMin);
  }

  static int _round5Floor(double minutes) {
    if (minutes <= 10) return 10;
    return ((minutes / 5).floor()) * 5;
  }

  /// Straight-line km client↔restaurant (for the card badge).
  static double? distanceKmBetween(LatLng? a, LatLng? b) {
    if (a == null || b == null) return null;
    return _distance.as(LengthUnit.Kilometer, a, b);
  }

  static String? label(OrderModel order) {
    final m = minutesRemaining(order);
    if (m == null) return null;
    return 'Chega em ~$m min';
  }

  static double? _fullTripKm(OrderModel order) {
    if (order.distanceKm > 0) return order.distanceKm;
    final pickup = order.pickupLocation;
    final drop = order.destination;
    if (pickup == null || drop == null) return null;
    return _distance.as(LengthUnit.Kilometer, pickup, drop);
  }

  static LatLng? _driverLatLng(OrderModel order) {
    final lat = order.driverLat;
    final lng = order.driverLng;
    if (lat == null || lng == null) return null;
    return LatLng(lat, lng);
  }

  static int _round5(double minutes) {
    if (minutes <= 5) return 5;
    return ((minutes / 5).ceil()) * 5;
  }
}
