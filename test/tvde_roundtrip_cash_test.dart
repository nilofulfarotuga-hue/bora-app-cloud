import 'package:bora_app/models/tvde_ride.dart';
import 'package:bora_app/widgets/tvde/tvde_roundtrip_driver_notice.dart';
import 'package:flutter_test/flutter_test.dart';

/// [Fase B] Contrato do pacote €8 ida-e-volta.
///
/// A regra que estes testes travam é uma só: **os €8 são o preço das DUAS
/// pernas**. Uma perna ligada ao vale é PREPAGA — se a app deixar de a
/// reconhecer, o motorista cobra a tarifa por cima dos €8 e o cliente paga €13.
TvdeRide _leg({
  String? creditId,
  bool isReturn = false,
  String paymentMethod = 'cash',
  int driverEarnCents = 400,
}) =>
    TvdeRide.fromMap({
      'id': 'r1',
      'client_id': 'c1',
      'status': 'solicitada',
      'origin_lat': 40.5,
      'origin_lng': -7.26,
      'dest_lat': 40.6,
      'dest_lng': -7.3,
      'est_distance_km': 8.0,
      'est_fare_cents': 500,
      'payment_method': paymentMethod,
      'driver_earn_cents': driverEarnCents,
      if (creditId != null) 'roundtrip_credit_id': creditId,
      'is_return_leg': isReturn,
    });

void main() {
  group('modelo — perna do pacote', () {
    test('vale ligado ⇒ isRoundtripLeg (é o que marca "prepaga")', () {
      expect(_leg(creditId: 'v1').isRoundtripLeg, isTrue);
      expect(_leg(creditId: 'v1').isReturnLeg, isFalse);
    });

    test('sem vale ⇒ corrida normal', () {
      final r = _leg();
      expect(r.isRoundtripLeg, isFalse,
          reason: 'uma corrida sem vale cobra a tarifa — não pode ser tratada '
              'como prepaga');
      expect(r.roundtripCreditId, isNull);
    });

    test('volta é reconhecida como volta', () {
      expect(_leg(creditId: 'v1', isReturn: true).isReturnLeg, isTrue);
    });

    test('colunas ausentes não rebentam (backend antigo)', () {
      final r = TvdeRide.fromMap({
        'id': 'r1',
        'client_id': 'c1',
        'status': 'solicitada',
        'origin_lat': 40.5,
        'origin_lng': -7.26,
        'dest_lat': 40.6,
        'dest_lng': -7.3,
        'est_distance_km': 8.0,
        'est_fare_cents': 500,
      });
      expect(r.isRoundtripLeg, isFalse);
      expect(r.isReturnLeg, isFalse);
    });
  });

  group('aviso ao motorista (PT-PT)', () {
    test('ida em dinheiro: diz o ganho E que os €8 não são dele', () {
      final msg = TvdeRoundtripDriverNotice.messageFor(
          _leg(creditId: 'v1', driverEarnCents: 400), 800);
      expect(msg, contains('€4.00'));
      expect(msg, contains('€8.00'));
      expect(msg, contains('NÃO são'));
      expect(msg, contains('recolhes em mão'));
    });

    test('ida paga online: manda NÃO cobrar nada', () {
      final msg = TvdeRoundtripDriverNotice.messageFor(
          _leg(creditId: 'v1', paymentMethod: 'card', driverEarnCents: 400),
          800);
      expect(msg, contains('já pagou'));
      expect(msg, contains('não cobres nada'));
      expect(msg, isNot(contains('recolhes em mão')),
          reason: 'mandar recolher €8 numa corrida já paga é cobrar duas vezes');
    });

    test('volta: grátis para o cliente, motorista ganha a sua parte', () {
      final msg = TvdeRoundtripDriverNotice.messageFor(
          _leg(creditId: 'v1', isReturn: true, driverEarnCents: 350), 800);
      expect(msg, contains('€3.50'));
      expect(msg, contains('não cobres nada'));
      expect(msg, isNot(contains('€8.00')),
          reason: 'os €8 já foram pagos na ida — repeti-los na volta confunde');
    });

    test('usa o preço do servidor, não um €8 hardcoded', () {
      final msg = TvdeRoundtripDriverNotice.messageFor(
          _leg(creditId: 'v1', driverEarnCents: 400), 900);
      expect(msg, contains('€9.00'));
      expect(msg, isNot(contains('€8.00')));
    });
  });
}
