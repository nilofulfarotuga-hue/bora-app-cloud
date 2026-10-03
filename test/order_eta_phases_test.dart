import 'package:bora_app/models/order_model.dart';
import 'package:bora_app/models/order_service_type.dart';
import 'package:bora_app/services/order_eta_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';

/// [botoes-navbar-eta 31/08] Contrato do ETA por fases (estilo Glovo) e do
/// fallback por velocidade. As settings entram pelos estáticos — aqui
/// fixamo-los à mão (o ensureConfigured é rede, não entra em teste).
void main() {
  // Loja e cliente ~2,22 km em linha reta (0,02° de latitude).
  const store = LatLng(40.5000, -7.2600);
  const client = LatLng(40.5200, -7.2600);
  // Estafeta longe (~4,45 km do cliente) e perto (~1,11 km).
  const driverFar = LatLng(40.4800, -7.2600);
  const driverNear = LatLng(40.5100, -7.2600);

  setUp(() {
    OrderEtaService.avgSpeedKmh = 30;
    OrderEtaService.shoppingMinutesMin = 30;
    OrderEtaService.shoppingMinutesMax = 45;
  });

  OrderModel shoppingOrder(OrderStatus status) => OrderModel(
        total: 20,
        serviceType: OrderServiceType.storeShopping,
        status: status,
        pickupLocation: store,
        destination: client,
      );

  group('compra não-parceira em curso → intervalo honesto', () {
    test('sem estafeta atribuído: compra + loja→cliente', () {
      final o = shoppingOrder(OrderStatus.callingDriver);
      final w = OrderEtaService.shoppingWindowMinutes(o)!;
      // drop 2,22 km a 30 km/h ≈ 4,45 min → [34,45..49,45] → 30–50.
      expect(w.$1, 30);
      expect(w.$2, 50);
      expect(OrderEtaService.label(o), 'Entrega estimada: 30–50 min');
    });

    test('estafeta a caminho da loja soma a deslocação até lá', () {
      final o = shoppingOrder(OrderStatus.driverAccepted);
      // driverFar→loja ≈ 2,22 km ≈ 4,45 min extra.
      final w = OrderEtaService.shoppingWindowMinutes(o, driverPos: driverFar)!;
      expect(w.$1, 35); // 38,9 → floor5
      expect(w.$2, 55); // 53,9 → ceil5
    });

    test('a velocidade das settings alimenta o intervalo (não é cravada)', () {
      OrderEtaService.avgSpeedKmh = 10; // drop 2,22 km ≈ 13,3 min
      final o = shoppingOrder(OrderStatus.callingDriver);
      final w = OrderEtaService.shoppingWindowMinutes(o)!;
      expect(w.$1, 40); // 43,3 → floor5
      expect(w.$2, 60); // 58,3 → ceil5
    });

    test('comprado (pickedUp) → deixa o intervalo, passa ao número vivo', () {
      final o = shoppingOrder(OrderStatus.pickedUp);
      final label = OrderEtaService.label(o, driverPos: store);
      expect(label, isNotNull);
      expect(label, isNot(contains('–'))); // já não é intervalo
      expect(label, contains('Chega em'));
    });
  });

  group('fallback por velocidade, VIVO (o número segue a posição)', () {
    test('estafeta mais perto ⇒ ETA menor — nunca congela no inicial', () {
      final o = shoppingOrder(OrderStatus.onTheWay);
      final longe =
          OrderEtaService.minutesRemaining(o, driverPos: driverFar)!;
      final perto =
          OrderEtaService.minutesRemaining(o, driverPos: driverNear)!;
      expect(perto, lessThan(longe));
      // 4,45 km a 30 km/h ≈ 8,9 min → round5 = 10; 1,11 km ≈ 2,2 → 5.
      expect(longe, 10);
      expect(perto, 5);
    });
  });

  group('parceiro com tempo de preparação anunciado', () {
    test('prep_time_minutes substitui o buffer fixo', () {
      final base = OrderModel(
        total: 15,
        serviceType: OrderServiceType.restaurant,
        status: OrderStatus.preparing,
        distanceKm: 2, // 2 km a 30 km/h = 4 min de viagem
        pickupLocation: store,
        destination: client,
      );
      // Sem prep anunciado: 4 + 8 (buffer) = 12 → 15.
      expect(OrderEtaService.minutesRemaining(base), 15);
      final comPrep = OrderModel(
        total: 15,
        serviceType: OrderServiceType.restaurant,
        status: OrderStatus.preparing,
        distanceKm: 2,
        prepTimeMinutes: 30,
        pickupLocation: store,
        destination: client,
      );
      // Com prep 30: 4 + 30 = 34 → 35.
      expect(OrderEtaService.minutesRemaining(comPrep), 35);
    });
  });
}
