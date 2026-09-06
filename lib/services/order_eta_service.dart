import 'package:flutter/foundation.dart';
import 'package:latlong2/latlong.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/order_model.dart';
import '../models/order_service_type.dart';

/// Computes a rough ETA (minutes remaining) until the client receives the
/// order. Uses haversine distance + average speed. Not meant to be precise —
/// this matches what Uber Eats / Glovo show on their cards.
///
/// [botoes-navbar-eta 31/08] Passou a ler as definições da plataforma
/// (`eta_avg_speed_kmh`, `eta_shopping_minutes_nonpartner_min`/`_max`) via
/// [ensureConfigured] — o Danilo afina no admin, nada fica cravado. E ganhou
/// o ETA por FASES estilo Glovo para compras não-parceiro: enquanto o
/// estafeta ainda não comprou, o cliente vê um INTERVALO honesto
/// (deslocação à loja + intervalo de compra + loja→cliente); comprado, passa
/// ao ETA vivo só da deslocação.
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

  /// Average urban speed used for all trip legs. Sobrescrita por
  /// `platform_settings.eta_avg_speed_kmh` no [ensureConfigured]; 25 é só o
  /// valor de arranque antes de a leitura chegar.
  static double avgSpeedKmh = 25.0;

  /// Intervalo de compra (min/max) para storeShopping NÃO-parceiro, em
  /// minutos. Sobrescrito por `eta_shopping_minutes_nonpartner_min`/`_max`.
  static int shoppingMinutesMin = 30;
  static int shoppingMinutesMax = 45;

  static bool _configured = false;

  /// Lê as três chaves `eta_*` das definições, uma vez por sessão.
  /// Best-effort: sem rede ficam os fallbacks (28 / 30 / 45). Idempotente —
  /// chamar à vontade nos initState dos ecrãs que mostram ETA.
  static Future<void> ensureConfigured() async {
    if (_configured) return;
    _configured = true;
    Future<int> lerInt(String key, int fallback) async {
      try {
        final res = await Supabase.instance.client
            .rpc('get_setting', params: {'p_key': key});
        return int.tryParse(res?.toString() ?? '') ?? fallback;
      } catch (e) {
        debugPrint('OrderEtaService.ensureConfigured($key) => $e');
        return fallback;
      }
    }

    final results = await Future.wait([
      lerInt('eta_avg_speed_kmh', 28),
      lerInt('eta_shopping_minutes_nonpartner_min', 30),
      lerInt('eta_shopping_minutes_nonpartner_max', 45),
    ]);
    if (results[0] > 0) avgSpeedKmh = results[0].toDouble();
    if (results[1] > 0) shoppingMinutesMin = results[1];
    if (results[2] >= results[1]) shoppingMinutesMax = results[2];
  }

  /// Restaurant prep time buffer (applied while status is still at the
  /// restaurant — created / preparing / callingDriver).
  static const int prepBufferMin = 8;

  /// Handoff buffer added when the driver is on the way to the pickup —
  /// accounts for parking + picking up the bag.
  static const int pickupBufferMin = 2;

  /// Returns estimated minutes remaining, rounded up to the nearest 5 min
  /// (minimum 5). Returns null when we cannot compute a meaningful value.
  ///
  /// [driverPos] — posição VIVA do estafeta (realtime do DriverStore), quando
  /// o ecrã a tem: mais fresca do que a gravada na linha do pedido.
  static int? minutesRemaining(OrderModel order, {LatLng? driverPos}) {
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
        // Driver not assigned yet — assume full trip + prep. Parceiro com
        // tempo de preparação anunciado (prep_time_minutes) usa-o; senão o
        // buffer fixo de sempre.
        final km = _fullTripKm(order);
        if (km == null) return null;
        return _round5((km / avgSpeedKmh) * 60 +
            (order.prepTimeMinutes ?? prepBufferMin));
      case OrderStatus.driverAccepted:
        // Driver moving to pickup → then pickup → drop.
        final driver = driverPos ?? _driverLatLng(order);
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
        // Driver heading to the client — only the last leg matters. Vivo:
        // recalculado a cada posição nova do estafeta que o ecrã passar.
        final driver = driverPos ?? _driverLatLng(order);
        final drop = order.destination;
        if (driver == null || drop == null) return null;
        final km = _distance.as(LengthUnit.Kilometer, driver, drop);
        return _round5((km / avgSpeedKmh) * 60);
    }
  }

  /// [31/08] True enquanto a COMPRA de um storeShopping não-parceiro ainda
  /// não acabou (o "picked up" é o momento "comprei, vou a caminho").
  static bool _shoppingEmCurso(OrderModel order) {
    if (order.serviceType != OrderServiceType.storeShopping) return false;
    switch (order.status) {
      case OrderStatus.created:
      case OrderStatus.preparing:
      case OrderStatus.callingDriver:
      case OrderStatus.driverAccepted:
        return true;
      default:
        return false;
    }
  }

  /// [31/08] Intervalo honesto (min, max) em minutos para storeShopping
  /// não-parceiro em compra — estilo Glovo: deslocação até à loja (se já
  /// houver estafeta com posição) + intervalo de compra das definições +
  /// deslocação loja→cliente. Null sem coordenadas suficientes.
  static (int, int)? shoppingWindowMinutes(OrderModel order,
      {LatLng? driverPos}) {
    final pickup = order.pickupLocation;
    final drop = order.destination;
    if (pickup == null || drop == null) return null;
    final driver = driverPos ?? _driverLatLng(order);
    final toStoreMin = (driver != null && order.status == OrderStatus.driverAccepted)
        ? (_distance.as(LengthUnit.Kilometer, driver, pickup) / avgSpeedKmh) *
            60
        : 0.0;
    final dropMin =
        (_distance.as(LengthUnit.Kilometer, pickup, drop) / avgSpeedKmh) * 60;
    final minTotal = toStoreMin + shoppingMinutesMin + dropMin;
    final maxTotal = toStoreMin + shoppingMinutesMax + dropMin;
    var lo = _round5Floor(minTotal);
    var hi = _round5(maxTotal);
    if (hi <= lo) hi = lo + 5;
    return (lo, hi);
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

  static String? label(OrderModel order, {LatLng? driverPos}) {
    // Compra não-parceiro ainda em curso → intervalo estilo Glovo, nunca um
    // número seco que não podemos prometer.
    if (_shoppingEmCurso(order)) {
      final w = shoppingWindowMinutes(order, driverPos: driverPos);
      if (w != null) return 'Entrega estimada: ${w.$1}–${w.$2} min';
    }
    final m = minutesRemaining(order, driverPos: driverPos);
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
