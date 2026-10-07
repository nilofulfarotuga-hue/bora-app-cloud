import 'dart:io';

import 'package:bora_app/services/tvde_corrida_localizacao_service.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';

/// [Fluxo partilhado · 07/10/2026] O geolocator guarda UM fluxo de GPS por
/// app (`geolocator_android` 5.1.x `getPositionStream`: devolve o
/// `_positionStream` em cache enquanto houver quem o ouça; só o `onCancel` do
/// último ouvinte o põe a null). Enquanto a home TVDE ouvia, o ecrã da
/// corrida recebia o fluxo DELA, com as definições dela (15 s, sem os
/// 3 m / 700 ms). Conserto: depois de a home largar (primeira leitura →
/// `_assumirGps` → a home cancela), o ecrã da corrida subscreve de novo UMA
/// vez. Molde: `gps_servico_em_fundo_test.dart` (auditoria de 06/10).

/// Lê um ficheiro do repo com as quebras de linha normalizadas (o checkout
/// no Windows pode ter CRLF; os `contains` de várias linhas não podem
/// depender disso).
String _ler(String caminho) =>
    File(caminho).readAsStringSync().replaceAll('\r\n', '\n');

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('o ecrã da corrida religa o GPS com as definições da corrida', () {
    final f = _ler('lib/screens/driver/tvde/tvde_ride_active_screen.dart');

    test('religa UMA vez, só depois de assumir o GPS (a home já largou)', () {
      expect(f, contains('bool _religadoComDefinicoesDaCorrida = false;'));
      // Na própria leitura: primeiro assume (a home cancela), depois religa.
      final assume = f.indexOf('_assumirGps();\n          _alimentarServidor(p);');
      final religa = f.indexOf('if (!_religadoComDefinicoesDaCorrida) {');
      expect(assume, greaterThan(0));
      expect(religa, greaterThan(assume),
          reason: 'o religar tem de vir DEPOIS de a home largar o fluxo');
      expect(
          f,
          contains('_religadoComDefinicoesDaCorrida = true;\n'
              '            unawaited(_startGps());'));
    });

    test('ao devolver o GPS à home, volta a poder religar', () {
      final libertar = f.indexOf('void _libertarGps() {');
      final fim = f.indexOf('}', libertar);
      final corpo = f.substring(libertar, fim);
      expect(corpo, contains('_religadoComDefinicoesDaCorrida = false;'));
      expect(corpo, contains('tvdeCorridaControlaGps.value = false;'));
    });

    test('o religar cancela a subscrição herdada antes de subscrever de novo',
        () {
      // `_startGps` começa por ++geração e cancelar o `_gps` actual: é esse
      // cancel que, sendo o último ouvinte, faz o geolocator largar o fluxo da
      // home e criar um novo com as definições da corrida.
      final inicio = f.indexOf('Future<void> _startGps() async {');
      final corpo = f.substring(inicio, inicio + 2500);
      expect(corpo, contains('final geracao = ++_gpsGeracao;'));
      expect(corpo, contains('await _gps?.cancel();'));
      expect(corpo, contains('TvdeCorridaLocalizacao.definicoesDeCorrida()'));
    });

    test('a home continua a largar o fluxo quando a corrida o assume', () {
      final h = _ler('lib/screens/driver/tvde/tvde_driver_home_screen.dart');
      expect(
          h,
          contains('if (tvdeCorridaControlaGps.value) {\n'
              '      _gps?.cancel();\n'
              '      _gps = null;'));
    });
  });

  group('definições da corrida (as que agora valem mesmo)', () {
    tearDown(() => debugDefaultTargetPlatformOverride = null);

    test('Android: bestForNavigation, 3 m, 700 ms', () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      // Sem plugin nativo no teste, `_requisitosCumpridos` falha e cai em
      // "sem serviço" — as definições de cadência são as mesmas.
      final d = await TvdeCorridaLocalizacao.definicoesDeCorrida();
      expect(d, isA<AndroidSettings>());
      final a = d as AndroidSettings;
      expect(a.accuracy, LocationAccuracy.bestForNavigation);
      expect(a.distanceFilter, 3);
      expect(a.intervalDuration, const Duration(milliseconds: 700));
    });
  });

  group('cadência da posição para o servidor em corrida/entrega', () {
    test('a corrida lê tvde_ride_gps_interval_seconds e envia por TEMPO', () {
      final f = _ler('lib/screens/driver/tvde/tvde_ride_active_screen.dart');
      expect(f, contains("getSettingInt('tvde_ride_gps_interval_seconds', 5)"));
      expect(f, contains('intervaloMinimo: intervalo'));
      expect(f, isNot(contains('_metrosEntreEnviosAoServidor')),
          reason: 'o portão dos 50 m deixava o cliente ver "última posição '
              'há 60 s" com o carro parado num semáforo');
      expect(f, contains('_feedTicker = Timer.periodic'));
    });

    test('o mapa da entrega envia à mesma cadência, com heading', () {
      final f = _ler('lib/screens/driver_map_screen.dart');
      expect(f, contains('_alimentarServidor(position);'));
      expect(f, contains('RastreioSettings.rideGpsIntervalSeconds'));
      expect(f, contains('heading: p.heading.isFinite ? p.heading : null'));
    });

    test('a migração cria a definição (on conflict do nothing)', () {
      final m =
          _ler('supabase/migrations/20261007230000_rastreio_tempo_real.sql');
      expect(m, contains("('tvde_ride_gps_interval_seconds', '5'::jsonb"));
      expect(m, contains("('client_live_location_enabled', 'true'::jsonb"));
      expect(m,
          contains("('client_live_location_interval_seconds', '4'::jsonb"));
      expect(m, contains('ON CONFLICT (key) DO NOTHING'));
      // Só apaga em client_live_locations; nunca escreve em orders.
      final pedido = m.substring(
          m.indexOf('client_live_location_limpar_pedido()'),
          m.indexOf('trg_client_live_location_limpar_pedido'));
      expect(pedido, contains('DELETE FROM public.client_live_locations'));
      expect(pedido, isNot(contains('UPDATE public.orders')));
      expect(m, isNot(contains('DROP TRIGGER')));
    });
  });
}
