import 'package:bora_app/models/tvde_ride.dart';
import 'package:flutter_test/flutter_test.dart';

/// Contrato do estado `aguarda_pagamento` (corrida criada mas ESTACIONADA: o
/// cron de dispatch ignora-a, logo não há motorista a ser chamado).
///
/// Estes testes existem para travar a regressão mais cara possível: mostrar
/// "à procura de motorista" a um cliente que ainda não pagou.
TvdeRide _ride(String status, {String? paymentMethod, String? paymentStatus}) =>
    TvdeRide.fromMap({
      'id': 'r1',
      'client_id': 'c1',
      'status': status,
      'origin_lat': 40.5,
      'origin_lng': -7.26,
      'dest_lat': 40.6,
      'dest_lng': -7.3,
      'est_distance_km': 8.0,
      'est_fare_cents': 700,
      if (paymentMethod != null) 'payment_method': paymentMethod,
      if (paymentStatus != null) 'payment_status': paymentStatus,
    });

void main() {
  group('aguarda_pagamento', () {
    test('é reconhecido e NÃO é "à procura de motorista"', () {
      final r = _ride('aguarda_pagamento');
      expect(r.isAwaitingPayment, isTrue);
      expect(r.isSearching, isFalse,
          reason: 'mostrar a procura antes de pagar é o bug que isto trava');
    });

    test('tem rótulo em PT-PT (nunca a string crua do backend)', () {
      expect(_ride('aguarda_pagamento').statusLabel, 'A aguardar pagamento…');
      expect(_ride('aguarda_pagamento').statusLabel,
          isNot(contains('aguarda_pagamento')));
    });

    test('é "live" — o cliente tem de reencontrar o ecrã se sair da app', () {
      expect(_ride('aguarda_pagamento').isLive, isTrue);
    });

    test('não é terminal nem atribuída/em curso', () {
      final r = _ride('aguarda_pagamento');
      expect(r.isTerminal, isFalse);
      expect(r.isAssigned, isFalse);
      expect(r.isInProgress, isFalse);
      expect(r.isCancelled, isFalse);
      expect(r.isNoDriver, isFalse);
    });
  });

  group('não contamina os outros estados', () {
    test('solicitada continua a ser a procura', () {
      final r = _ride('solicitada');
      expect(r.isSearching, isTrue);
      expect(r.isAwaitingPayment, isFalse);
      expect(r.statusLabel, 'À procura de motorista…');
      expect(r.isLive, isTrue);
    });

    test('finalizada continua terminal e fora de live', () {
      final r = _ride('finalizada');
      expect(r.isAwaitingPayment, isFalse);
      expect(r.isTerminal, isTrue);
      expect(r.isLive, isFalse);
    });

    test('em_andamento inalterado', () {
      final r = _ride('em_andamento');
      expect(r.isInProgress, isTrue);
      expect(r.isAwaitingPayment, isFalse);
      expect(r.isLive, isTrue);
    });
  });

  group('payment_status', () {
    test('é lido do mapa', () {
      expect(
          _ride('aguarda_pagamento', paymentStatus: 'processing').paymentStatus,
          'processing');
    });

    test('é null em dinheiro (nunca há PaymentIntent)', () {
      final r = _ride('solicitada', paymentMethod: 'cash');
      expect(r.paymentStatus, isNull);
      expect(r.isPaidOnline, isFalse);
    });

    test('cartão e mbway contam como pagos online', () {
      expect(_ride('solicitada', paymentMethod: 'card').isPaidOnline, isTrue);
      expect(_ride('solicitada', paymentMethod: 'mbway').isPaidOnline, isTrue);
    });
  });
}
