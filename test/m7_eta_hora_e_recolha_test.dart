import 'package:bora_app/models/order_model.dart';
import 'package:bora_app/services/order_eta_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';

/// M7 (08/11/2026) — paridade Bora Motorista → entregas: o cliente vê a HORA
/// de chegada e o aviso "o estafeta já chegou para levantar o pedido".
void main() {
  const loja = LatLng(40.5000, -7.2600);
  const cliente = LatLng(40.5200, -7.2600);
  const estafetaNaPorta = LatLng(40.5005, -7.2600); // ~56 m da loja
  const estafetaLonge = LatLng(40.4800, -7.2600); // ~2,2 km da loja

  setUp(() {
    OrderEtaService.avgSpeedKmh = 30;
    OrderEtaService.shoppingMinutesMin = 30;
    OrderEtaService.shoppingMinutesMax = 45;
  });

  OrderModel pedido(OrderStatus status) => OrderModel(
        total: 20,
        serviceType: OrderServiceType.restaurant,
        status: status,
        pickupLocation: loja,
        destination: cliente,
      );

  group('hora de chegada', () {
    test('é agora + os minutos do ETA (a mesma conta do "Chega em")', () {
      final agora = DateTime(2026, 11, 8, 20, 0);
      final o = pedido(OrderStatus.onTheWay);
      final m = OrderEtaService.minutesRemaining(o,
          driverPos: estafetaLonge, now: agora)!;
      final hora = OrderEtaService.horaChegada(o,
          driverPos: estafetaLonge, now: agora)!;
      expect(hora, agora.add(Duration(minutes: m)));
      expect(hora.isAfter(agora), isTrue);
    });

    test('sem ETA não inventa hora (entregue / cancelado)', () {
      final agora = DateTime(2026, 11, 8, 20, 0);
      expect(
          OrderEtaService.horaChegada(pedido(OrderStatus.delivered),
              driverPos: estafetaLonge, now: agora),
          isNull);
      expect(
          OrderEtaService.horaChegada(pedido(OrderStatus.cancelled),
              driverPos: estafetaLonge, now: agora),
          isNull);
    });
  });

  group('estafeta no sítio de recolha', () {
    test('aceitou e está a menos de 150 m da loja → chegou', () {
      expect(
          OrderEtaService.estafetaNaRecolha(pedido(OrderStatus.driverAccepted),
              driverPos: estafetaNaPorta),
          isTrue);
    });

    test('aceitou mas ainda está longe → não chegou', () {
      expect(
          OrderEtaService.estafetaNaRecolha(pedido(OrderStatus.driverAccepted),
              driverPos: estafetaLonge),
          isFalse);
    });

    test('depois de levantar (a caminho do cliente) já não diz "chegou à loja"', () {
      expect(
          OrderEtaService.estafetaNaRecolha(pedido(OrderStatus.onTheWay),
              driverPos: estafetaNaPorta),
          isFalse);
    });

    test('sem posição do estafeta ou sem morada de recolha → falso', () {
      expect(
          OrderEtaService.estafetaNaRecolha(pedido(OrderStatus.driverAccepted)),
          isFalse);
      final semRecolha = OrderModel(
        total: 20,
        serviceType: OrderServiceType.restaurant,
        status: OrderStatus.driverAccepted,
        destination: cliente,
      );
      expect(
          OrderEtaService.estafetaNaRecolha(semRecolha,
              driverPos: estafetaNaPorta),
          isFalse);
    });
  });
}
