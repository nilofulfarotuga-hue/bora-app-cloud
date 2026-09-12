import 'package:bora_app/models/tvde_fare_view.dart';
import 'package:bora_app/models/tvde_ride.dart';
import 'package:flutter_test/flutter_test.dart';

/// Contrato da fonte ÚNICA de preço TVDE (`TvdeFareView`).
///
/// Duas regressões travadas aqui:
///  1. **O "€13"** — uma perna do pacote €8 nunca pode cobrar a tarifa base por
///     cima do pacote, e o cliente e o motorista têm de ver o MESMO número.
///  2. **A dupla contagem das paradas** — depois do finish, numa corrida normal
///     o `final_fare_cents` já inclui as paradas; numa perna do pacote traz SÓ
///     as paradas (a `tvde_finish_ride` faz `v_fare := v_stops_fee`).
const _pkg = 800; // tvde_roundtrip_price_cents (€8)

TvdeRide _ride({
  String? creditId,
  bool isReturn = false,
  String paymentMethod = 'cash',
  int estFareCents = 500,
  int? finalFareCents,
  int stopsFeeCents = 0,
  int stopsCount = 0,
  bool usedPlan = false,
}) =>
    TvdeRide.fromMap({
      'id': 'r1',
      'client_id': 'c1',
      'status': 'em_andamento',
      'origin_lat': 40.5,
      'origin_lng': -7.26,
      'dest_lat': 40.6,
      'dest_lng': -7.3,
      'est_distance_km': 8.0,
      'est_fare_cents': estFareCents,
      if (finalFareCents != null) 'final_fare_cents': finalFareCents,
      'payment_method': paymentMethod,
      'extra_stops_count': stopsCount,
      'extra_stops_fee_cents': stopsFeeCents,
      'used_subscription_ride': usedPlan,
      if (creditId != null) 'roundtrip_credit_id': creditId,
      'is_return_leg': isReturn,
    });

TvdeFareView _view(TvdeRide r) => TvdeFareView.of(r, packageCents: _pkg);

void main() {
  group('ida do pacote €8 (dinheiro)', () {
    test('sem paradas ⇒ €8 ao cliente E ao motorista (nunca a tarifa de €5)',
        () {
      final f = _view(_ride(creditId: 'v1'));
      expect(f.clientTotalCents, 800);
      expect(f.driverCollectCents, 800);
      expect(f.clientLabel, contains('ida + volta'));
      // A regressão do "€5,00 numa corrida do pacote €8".
      expect(f.clientTotalCents, isNot(500));
    });

    test('com 1 parada ⇒ €10 dos DOIS lados (pacote €8 + €2)', () {
      final f = _view(_ride(creditId: 'v1', stopsCount: 1, stopsFeeCents: 200));
      expect(f.clientTotalCents, 1000);
      expect(f.driverCollectCents, 1000);
    });

    test('depois do finish o final traz SÓ as paradas ⇒ continua €10', () {
      // tvde_finish_ride: v_prepaid ⇒ v_fare := v_stops_fee.
      final f = _view(_ride(
          creditId: 'v1',
          stopsCount: 1,
          stopsFeeCents: 200,
          finalFareCents: 200));
      expect(f.clientTotalCents, 1000);
      expect(f.driverCollectCents, 1000);
    });

    test('nunca cobra a tarifa por cima do pacote (o €13)', () {
      final f = _view(_ride(creditId: 'v1', estFareCents: 500));
      expect(f.clientTotalCents, isNot(1300));
      expect(f.driverCollectCents, isNot(1300));
    });

    test(
        'servidor a gravar a receita do vale no final NÃO dobra a cobrança '
        '(o €16 da Sandra, 30/08)', () {
      // Contrato quebrado: final_fare_cents=800 (receita do vale) em vez de
      // só as paradas. O app tem de ignorar o final na perna do pacote.
      final f = _view(_ride(
          creditId: 'v1',
          finalFareCents: 800,
          stopsFeeCents: 0));
      expect(f.clientTotalCents, 800); // €8, nunca €16
      expect(f.driverCollectCents, 800);
      expect(f.clientTotalCents, isNot(1600));
    });
  });

  group('volta do pacote €8', () {
    test('sem paradas ⇒ €0 e diz que está incluída', () {
      final f = _view(_ride(creditId: 'v1', isReturn: true));
      expect(f.clientTotalCents, 0);
      expect(f.driverCollectCents, 0);
      expect(f.clientLabel, contains('incluída no pacote'));
    });

    test('com 1 parada em dinheiro ⇒ motorista recolhe só os €2', () {
      final f = _view(_ride(
          creditId: 'v1', isReturn: true, stopsCount: 1, stopsFeeCents: 200));
      expect(f.clientTotalCents, 200);
      expect(f.driverCollectCents, 200);
    });

    test('volta com final contaminado pelo servidor ⇒ continua €0', () {
      final f = _view(_ride(
          creditId: 'v1', isReturn: true, finalFareCents: 800));
      expect(f.clientTotalCents, 0);
      expect(f.driverCollectCents, 0);
    });
  });

  group('corrida normal', () {
    test('antes do finish soma as paradas ao estimado', () {
      final f = _view(_ride(stopsCount: 1, stopsFeeCents: 200));
      expect(f.clientTotalCents, 700); // 500 + 200
      expect(f.approx, isTrue);
    });

    test('depois do finish NÃO soma as paradas outra vez', () {
      // O backend já as incluiu no final_fare_cents.
      final f = _view(
          _ride(stopsCount: 1, stopsFeeCents: 200, finalFareCents: 700));
      expect(f.clientTotalCents, 700);
      expect(f.approx, isFalse);
    });
  });

  group('pago online', () {
    test('motorista não recolhe nada, mas o cliente vê o total', () {
      final f = _view(_ride(paymentMethod: 'card', stopsFeeCents: 200));
      expect(f.driverCollectCents, 0);
      expect(f.clientTotalCents, 700);
      expect(f.isPaidOnline, isTrue);
    });

    test('ida do pacote paga no cartão ⇒ motorista não cobra os €8', () {
      final f = _view(_ride(creditId: 'v1', paymentMethod: 'mbway'));
      expect(f.driverCollectCents, 0);
      expect(f.clientTotalCents, 800);
    });
  });

  group('coberta pelo plano', () {
    test('sem paradas ⇒ €0 e marcada como coberta', () {
      final f = _view(_ride(usedPlan: true));
      expect(f.clientTotalCents, 0);
      expect(f.coveredByPlan, isTrue);
    });

    test('com parada ⇒ paga só a parada (a parada não entra no plano)', () {
      final f = _view(_ride(usedPlan: true, stopsCount: 1, stopsFeeCents: 200));
      expect(f.clientTotalCents, 200);
      expect(f.driverCollectCents, 200);
    });
  });
}
