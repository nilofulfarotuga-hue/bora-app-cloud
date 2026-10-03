import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:bora_app/screens/admin/admin_tvde_reservas_screen.dart';

/// Painel admin (23/09): /admin/tvde/reservas mostra o pacote ida-e-volta de
/// cada perna, e a lista de corridas mostra o atraso da oferta.
String _q(String? iso) => iso ?? '—';

void main() {
  test('reserva normal: sem linhas de pacote', () {
    expect(pacoteLinhasPtBr({'pacote': null}, _q), isEmpty);
  });

  test('IDA com volta marcada mostra a volta ligada e o vale', () {
    final l = pacoteLinhasPtBr({
      'is_return_leg': false,
      'pacote': {
        'status': 'reservado',
        'paid_cents': 800,
        'pago_online': true,
        'return_mode': 'marcada',
        'return_scheduled_at': '2026-09-24T18:00',
      },
      'perna_ligada': {
        'status': 'agendada',
        'reservation_status': 'a_procurar',
      },
    }, _q);
    final m = {for (final x in l) x.$1: x.$2};
    expect(m['Pacote'], contains('IDA'));
    expect(m['Pacote'], contains('€8.00 pago online'));
    expect(m['Volta'], contains('marcada para 2026-09-24T18:00'));
    expect(m['Volta'], contains('a_procurar'));
    expect(m['Vale da volta'], contains('ida ainda por fazer'));
  });

  test('IDA com "cliente chama" e VOLTA ligada à ida', () {
    final ida = pacoteLinhasPtBr({
      'pacote': {'status': 'ativo', 'return_mode': 'cliente_chama'},
    }, _q);
    expect(ida.firstWhere((x) => x.$1 == 'Volta').$2,
        contains('cliente chama'));
    final volta = pacoteLinhasPtBr({
      'is_return_leg': true,
      'pacote': {'status': 'usado'},
      'perna_ligada': {'status': 'finalizada', 'driver_name': 'Ney'},
    }, _q);
    expect(volta.first.$2, contains('VOLTA'));
    expect(volta.firstWhere((x) => x.$1 == 'Ida ligada').$2,
        contains('finalizada · Ney'));
  });

  test('guardas: atraso da oferta no painel e settings novas editáveis', () {
    final rides =
        File('lib/screens/admin/admin_tvde_rides_screen.dart').readAsStringSync();
    expect(rides, contains("data['offer_delay_s']"));
    expect(rides, contains('Atraso da oferta'));
    final settings = File('lib/screens/admin/admin_platform_settings_screen.dart')
        .readAsStringSync();
    for (final k in [
      'tvde_heartbeat_window_seconds',
      'tvde_roundtrip_reservation_enabled',
      'tvde_roundtrip_return_min_gap_minutes',
    ]) {
      expect(settings, contains("'$k'"));
    }
  });
}
