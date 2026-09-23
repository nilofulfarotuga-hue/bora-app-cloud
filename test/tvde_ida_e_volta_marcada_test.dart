import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:bora_app/models/tvde_ride.dart';
import 'package:bora_app/screens/client/tvde/tvde_volta_sheet.dart';
import 'package:bora_app/screens/driver/tvde/tvde_driver_agenda_screen.dart';
import 'package:bora_app/stores/tvde_store.dart';

/// Ida-e-volta com reserva (23/09): marcar a IDA e escolher a VOLTA
/// ("chamo quando terminar" ou hora marcada), pacote pago na marcação.
TvdeRide _ride({String? credit, bool volta = false}) => TvdeRide.fromMap({
      'id': 'r1',
      'client_id': 'c1',
      'status': 'agendada',
      'origin_lat': 40.5,
      'origin_lng': -7.2,
      'dest_lat': 40.6,
      'dest_lng': -7.3,
      'est_distance_km': 4.8,
      'est_fare_cents': volta ? 0 : 500,
      'roundtrip_credit_id': credit,
      'is_return_leg': volta,
      'scheduled_at': '2026-09-24T10:00:00Z',
    });

void main() {
  group('hora da volta', () {
    final ida = DateTime(2026, 9, 24, 22, 0);

    test('hora antes da ida passa para o dia seguinte', () {
      final v = tvdeHoraDaVolta(ida, const TimeOfDay(hour: 1, minute: 30));
      expect(v, DateTime(2026, 9, 25, 1, 30));
    });

    test('mesmo dia quando é depois da ida', () {
      final v = tvdeHoraDaVolta(ida, const TimeOfDay(hour: 23, minute: 15));
      expect(v, DateTime(2026, 9, 24, 23, 15));
    });

    test('limites iguais aos do servidor: 30 min a 12 h', () {
      expect(tvdeValidaVolta(ida, ida.add(const Duration(minutes: 29))),
          isNotNull);
      expect(tvdeValidaVolta(ida, ida.add(const Duration(minutes: 30))),
          isNull);
      expect(tvdeValidaVolta(ida, ida.add(const Duration(hours: 12))),
          isNull);
      expect(
          tvdeValidaVolta(
              ida, ida.add(const Duration(hours: 12, minutes: 1))),
          isNotNull);
    });
  });

  group('pedido à Edge Function', () {
    test('chamo quando terminar: sem return_at', () {
      final b = buildTvdeRoundtripReservationChargeBody(
        originLat: 1, originLng: 2, destLat: 3, destLng: 4,
        distanceKm: 4.8,
        outboundAt: DateTime.utc(2026, 9, 24, 10),
        method: 'mbway', mbwayPhone: '912345678',
      );
      expect(b['action'], 'charge_roundtrip_reservation');
      expect(b.containsKey('return_at'), isFalse);
      expect(b['outbound_at'], '2026-09-24T10:00:00.000Z');
      expect(b['phone'], '912345678');
    });

    test('volta marcada: leva return_at em UTC', () {
      final b = buildTvdeRoundtripReservationChargeBody(
        originLat: 1, originLng: 2, destLat: 3, destLng: 4,
        distanceKm: 4.8,
        outboundAt: DateTime.utc(2026, 9, 24, 10),
        returnAt: DateTime.utc(2026, 9, 24, 13),
        method: 'card', savedPmId: 'pm_1',
      );
      expect(b['return_at'], '2026-09-24T13:00:00.000Z');
      expect(b['saved_pm_id'], 'pm_1');
    });
  });

  group('agenda do motorista', () {
    test('Ida / Volta do pacote marcadas; reserva normal sem rótulo', () {
      expect(tvdePernaDoPacote(_ride(credit: 'v1')), contains('Ida'));
      expect(tvdePernaDoPacote(_ride(credit: 'v1', volta: true)),
          contains('Volta'));
      expect(tvdePernaDoPacote(_ride()), isNull);
    });
  });

  group('erros em palavras', () {
    test('volta cedo/tarde demais não diz "hora em cima"', () {
      expect(traduzErroReserva(Exception('return_too_soon')),
          contains('30 minutos'));
      expect(traduzErroReserva(Exception('return_too_far')),
          contains('12 horas'));
      expect(traduzErroReserva(Exception('roundtrip_reservations_disabled')),
          contains('ida-e-volta'));
    });
  });

  testWidgets('folha da volta: "Chamo quando terminar" vem escolhida',
      (tester) async {
    TvdeEscolhaVolta? escolha;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (ctx) => TextButton(
            onPressed: () async {
              escolha = await showModalBottomSheet<TvdeEscolhaVolta>(
                context: ctx,
                builder: (_) =>
                    TvdeVoltaSheet(ida: DateTime(2026, 9, 24, 10)),
              );
            },
            child: const Text('abrir'),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('abrir'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('volta_chamo_quando_terminar')), findsOneWidget);
    await tester.tap(find.text('Continuar'));
    await tester.pumpAndSettle();
    expect(escolha, isNotNull);
    expect(escolha!.hora, isNull);
  });
}
