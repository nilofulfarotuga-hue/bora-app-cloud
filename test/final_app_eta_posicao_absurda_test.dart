// Auditoria final-app 29/10/2026 (bloco 7): a conta demo do estafeta tem a
// posição gravada na Califórnia e o cliente via "Entrega estimada: 19580–19600
// min" no acompanhamento. O ETA agora ignora uma posição do estafeta a mais de
// OrderEtaService.maxDriverDistanceKm da loja (ou do cliente) e cai para o
// cálculo sem estafeta. Quem anda perto continua a contar.
import 'package:bora_app/models/order_model.dart';
import 'package:bora_app/services/order_eta_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';

void main() {
  // Loja e cliente ~2,22 km em linha reta (0,02° de latitude).
  const store = LatLng(40.5000, -7.2600);
  const client = LatLng(40.5200, -7.2600);
  const driverNear = LatLng(40.5100, -7.2600); // ~1,1 km da loja
  const driverFar = LatLng(40.4800, -7.2600); // ~2,2 km da loja
  // Googleplex: onde o emulador (e a conta demo) deixou o estafeta.
  const driverCalifornia = LatLng(37.4219983, -122.084);

  setUp(() {
    OrderEtaService.avgSpeedKmh = 30;
    OrderEtaService.shoppingMinutesMin = 30;
    OrderEtaService.shoppingMinutesMax = 45;
  });

  OrderModel compra(OrderStatus status) => OrderModel(
        total: 20,
        serviceType: OrderServiceType.storeShopping,
        status: status,
        pickupLocation: store,
        destination: client,
      );

  OrderModel restaurante(OrderStatus status) => OrderModel(
        total: 20,
        serviceType: OrderServiceType.restaurant,
        status: status,
        pickupLocation: store,
        destination: client,
      );

  group('compra não-parceira (intervalo)', () {
    test('estafeta na Califórnia: dá o mesmo intervalo que sem estafeta', () {
      final o = compra(OrderStatus.driverAccepted);
      final semEstafeta = OrderEtaService.shoppingWindowMinutes(o)!;
      final californiano =
          OrderEtaService.shoppingWindowMinutes(o, driverPos: driverCalifornia)!;
      expect(californiano, semEstafeta);
      expect(californiano.$2, lessThan(120));
      expect(OrderEtaService.label(o, driverPos: driverCalifornia),
          'Entrega estimada: ${semEstafeta.$1}–${semEstafeta.$2} min');
    });

    test('a posição gravada no pedido também é filtrada', () {
      final o = OrderModel(
        total: 20,
        serviceType: OrderServiceType.storeShopping,
        status: OrderStatus.driverAccepted,
        pickupLocation: store,
        destination: client,
        driverLat: driverCalifornia.latitude,
        driverLng: driverCalifornia.longitude,
      );
      final w = OrderEtaService.shoppingWindowMinutes(o)!;
      expect(w.$2, lessThan(120));
    });

    test('estafeta perto continua a contar (mais longe = intervalo maior)', () {
      final o = compra(OrderStatus.driverAccepted);
      final perto =
          OrderEtaService.shoppingWindowMinutes(o, driverPos: driverNear)!;
      final longe =
          OrderEtaService.shoppingWindowMinutes(o, driverPos: driverFar)!;
      expect(longe.$1 >= perto.$1, isTrue);
      expect(longe.$2 >= perto.$2, isTrue);
    });
  });

  group('minutesRemaining com estafeta', () {
    test('a caminho da loja, estafeta na Califórnia: cai para o cálculo base',
        () {
      final o = restaurante(OrderStatus.driverAccepted);
      final californiano =
          OrderEtaService.minutesRemaining(o, driverPos: driverCalifornia)!;
      final semPosicao = OrderEtaService.minutesRemaining(o)!;
      expect(californiano, semPosicao);
      expect(californiano, lessThan(120));
    });

    test('a caminho da loja, estafeta perto: usa-o', () {
      final o = restaurante(OrderStatus.driverAccepted);
      final perto =
          OrderEtaService.minutesRemaining(o, driverPos: driverNear)!;
      expect(perto, lessThan(120));
      expect(perto, greaterThanOrEqualTo(5));
    });

    test('a caminho do cliente, estafeta na Califórnia: sem ETA em vez de '
        'milhares de minutos', () {
      final o = restaurante(OrderStatus.onTheWay);
      expect(
          OrderEtaService.minutesRemaining(o, driverPos: driverCalifornia),
          isNull);
      expect(OrderEtaService.label(o, driverPos: driverCalifornia), isNull);
    });

    test('a caminho do cliente, estafeta perto: calcula', () {
      final o = restaurante(OrderStatus.onTheWay);
      final m = OrderEtaService.minutesRemaining(o, driverPos: driverNear)!;
      expect(m, lessThan(60));
    });
  });

  test('o limite é de dezenas de km, não de poucos km', () {
    // Um estafeta a 30 km (Guarda a outra cidade da região) ainda é plausível.
    expect(OrderEtaService.maxDriverDistanceKm, greaterThanOrEqualTo(30));
    expect(OrderEtaService.maxDriverDistanceKm, lessThanOrEqualTo(100));
  });
}
