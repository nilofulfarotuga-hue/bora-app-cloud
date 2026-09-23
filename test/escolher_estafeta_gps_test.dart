import 'package:bora_app/widgets/admin/escolher_estafeta_sheet.dart';
import 'package:flutter_test/flutter_test.dart';

/// [ronda-fecho-2026-09-22 · A10] O "Escolher entregador" lê `gps_age_s` e
/// `gps_fresco` da RPC admin_drivers_for_assignment e, quando o heartbeat está
/// vivo mas o GPS parou, é ESSE o motivo que vai para o aviso vermelho e para
/// a auditoria ("ATRIBUÍDO MESMO ASSIM (GPS parado há 19 min)").
///
/// Modelo puro (`EstafetaParaAtribuir.fromRow`): testa-se sem Supabase.
void main() {
  Map<String, dynamic> linha({
    bool isOnline = true,
    bool onlineAgora = true,
    DateTime? heartbeat,
    bool temNotificacoes = true,
    Object? gpsAgeS = 5,
    Object? gpsFresco = true,
    bool semColunasGps = false,
  }) {
    final r = <String, dynamic>{
      'user_id': 'u1',
      'driver_id': 'd1',
      'name': 'Euliney',
      'phone': '910000000',
      'is_online': isOnline,
      'online_agora': onlineAgora,
      'last_heartbeat_at':
          (heartbeat ?? DateTime.now().toUtc()).toIso8601String(),
      'tem_notificacoes': temNotificacoes,
      'last_platform': 'android_app',
      'pedidos_em_curso': 0,
      'distancia_km': null,
    };
    if (!semColunasGps) {
      r['gps_age_s'] = gpsAgeS;
      r['gps_fresco'] = gpsFresco;
    }
    return r;
  }

  test('lê gps_age_s e gps_fresco da linha da RPC', () {
    final d =
        EstafetaParaAtribuir.fromRow(linha(gpsAgeS: 1140, gpsFresco: false));
    expect(d.gpsAgeS, 1140);
    expect(d.gpsFresco, isFalse);
  });

  test(
      'heartbeat vivo + GPS parado (o caso Euliney): não vai receber e o motivo é o GPS',
      () {
    final d = EstafetaParaAtribuir.fromRow(linha(
      isOnline: true,
      onlineAgora: false, // o servidor já exige GPS fresco
      gpsAgeS: 19 * 3600,
      gpsFresco: false,
    ));
    expect(d.vaiReceber, isFalse);
    expect(d.sinalFresco, isTrue);
    expect(d.motivoNaoRecebe, 'GPS parado há mais de 1 h');
  });

  test('GPS parado há 19 min lê-se com os minutos', () {
    final d = EstafetaParaAtribuir.fromRow(
        linha(onlineAgora: false, gpsAgeS: 1140, gpsFresco: false));
    expect(d.motivoNaoRecebe, 'GPS parado há 19 min');
  });

  test(
      'sem heartbeat há mais de 90 s a causa continua a ser o sinal, não o GPS',
      () {
    final d = EstafetaParaAtribuir.fromRow(linha(
      onlineAgora: false,
      heartbeat: DateTime.utc(2020, 1, 1),
      gpsAgeS: 1140,
      gpsFresco: false,
    ));
    expect(d.sinalFresco, isFalse);
    expect(d.motivoNaoRecebe, 'sem sinal há mais de 90 s');
  });

  test('desligado na tabela diz "desligado", como antes', () {
    final d = EstafetaParaAtribuir.fromRow(linha(
        isOnline: false, onlineAgora: false, gpsAgeS: null, gpsFresco: false));
    expect(d.motivoNaoRecebe, 'desligado');
  });

  test('GPS parado E sem notificações: os dois motivos, ligados por "e"', () {
    final d = EstafetaParaAtribuir.fromRow(linha(
      onlineAgora: false,
      temNotificacoes: false,
      gpsAgeS: 400,
      gpsFresco: false,
    ));
    expect(d.motivoNaoRecebe,
        'GPS parado há 7 min e sem notificações neste aparelho');
  });

  test('ligado agora com GPS fresco e notificações: vai receber, sem motivo',
      () {
    final d = EstafetaParaAtribuir.fromRow(linha());
    expect(d.vaiReceber, isTrue);
    expect(d.gpsFresco, isTrue);
    expect(d.motivoNaoRecebe, '');
  });

  test('RPC antiga sem as colunas de GPS não inventa alarme', () {
    final d = EstafetaParaAtribuir.fromRow(linha(semColunasGps: true));
    expect(d.gpsFresco, isTrue);
    expect(d.gpsAgeS, isNull);
  });

  test('nunca mandou posição: gps_age_s nulo lê-se como "sem GPS"', () {
    final d = EstafetaParaAtribuir.fromRow(
        linha(onlineAgora: false, gpsAgeS: null, gpsFresco: false));
    expect(d.gpsAgeS, isNull);
    expect(d.motivoNaoRecebe, 'sem GPS');
  });
}
