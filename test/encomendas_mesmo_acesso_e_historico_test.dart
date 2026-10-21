// N2 (21/10/2026, fechar-pendencias): Encomendas = cópia exacta do Bora Motorista.
//  (1) Histórico do cliente: com uma encomenda na lista o título diz "corridas e
//      encomendas" e a linha leva "📦 Encomenda"; só passageiros = como antes.
//  (2) O ladrilho "Enviar Encomenda" (interruptor ligado) passa pela MESMA porta
//      de acesso do Bora Motorista (TvdeEntradaScreen), não directamente ao ecrã
//      de pedir — o servidor recusa `no_tvde_access` nos dois tipos
//      (migração 20261021195814).
import 'dart:io';

import 'package:bora_app/models/ride_kind.dart';
import 'package:bora_app/models/tvde_ride.dart';
import 'package:bora_app/screens/client/tvde/tvde_entrada_screen.dart';
import 'package:bora_app/screens/client/tvde/tvde_rides_history_screen.dart';
import 'package:bora_app/stores/tvde_store.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

TvdeRide _ride(String id, String kind) => TvdeRide.fromMap({
      'id': id,
      'client_id': 'cli-demo',
      'status': 'finalizada',
      'ride_kind': kind,
      'origin_label': 'Sé da Guarda',
      'dest_label': 'Estação',
      'est_fare_cents': 500,
      'final_fare_cents': 500,
      'payment_method': 'cash',
      'created_at': '2026-10-21T19:30:00Z',
    });

class _Historico extends TvdeStore {
  _Historico(this._l);
  final List<TvdeRide> _l;
  @override
  List<TvdeRide> get history => _l;
  @override
  bool get historyLoaded => true;
  @override
  bool get historyLoading => false;
  @override
  bool get historyFailed => false;
  @override
  Future<void> loadHistory() async {}
}

Future<void> _abrir(WidgetTester tester, List<TvdeRide> rides) async {
  await tester.pumpWidget(ChangeNotifierProvider<TvdeStore>.value(
    value: _Historico(rides),
    child: const MaterialApp(home: TvdeRidesHistoryScreen()),
  ));
  await tester.pump();
}

void main() {
  testWidgets('histórico só com passageiros: título e linhas como antes', (tester) async {
    await _abrir(tester, [_ride('11111111-0000-0000-0000-000000000001', 'passageiros')]);
    expect(find.text('As minhas corridas'), findsOneWidget);
    expect(find.text('As minhas corridas e encomendas'), findsNothing);
    expect(find.byKey(const Key('historico_etiqueta_encomenda')), findsNothing);
  });

  testWidgets('histórico com uma encomenda: título com as duas e etiqueta só na encomenda',
      (tester) async {
    await _abrir(tester, [
      _ride('11111111-0000-0000-0000-000000000001', 'passageiros'),
      _ride('22222222-0000-0000-0000-000000000002', 'encomendas'),
    ]);
    expect(find.text('As minhas corridas e encomendas'), findsOneWidget);
    expect(find.byKey(const Key('historico_etiqueta_encomenda')), findsOneWidget);
    expect(find.text('📦 Encomenda'), findsOneWidget);
  });

  test('porta de acesso: TvdeEntradaScreen guarda o tipo (passageiros por omissão)', () {
    expect(const TvdeEntradaScreen().rideKind, RideKind.passageiros);
    expect(const TvdeEntradaScreen(rideKind: RideKind.encomendas).rideKind,
        RideKind.encomendas);
  });

  test('ladrilho Enviar Encomenda passa pela porta do Bora Motorista (mesmo acesso)', () {
    final home = File('lib/screens/client_home_screen.dart').readAsStringSync();
    expect(home.contains('TvdeEntradaScreen(rideKind: RideKind.encomendas)'), isTrue,
        reason: 'as encomendas têm de passar pela mesma porta de acesso');
    expect(home.contains('TvdeRequestRideScreen(rideKind: RideKind.encomendas)'), isFalse,
        reason: 'abrir o ecrã de pedir directamente salta a regra de acesso');
    final entrada = File('lib/screens/client/tvde/tvde_entrada_screen.dart').readAsStringSync();
    expect(entrada.contains('TvdeRequestRideScreen(rideKind: widget.rideKind)'), isTrue);
  });
}
