import 'dart:io';

import 'package:bora_app/services/localizacao_online.dart';
import 'package:bora_app/services/tvde_corrida_localizacao_service.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';

/// [GPS em fundo · 07/10/2026 · debug_crash_logs] "Starting FGS with type
/// location ... targetSDK=36 requires ... and the app must be in the eligible
/// state/exemptions to access the foreground only permission" — telemóvel do
/// Danilo (Android 16), 26/09, 27/09, 29/09 e 03/10, sempre segundos depois de
/// terminar uma corrida: o ecrã da corrida fecha, devolve o GPS à home, e a
/// home religava-o COM serviço em primeiro plano com a app em fundo e a
/// permissão só "enquanto se usa". O Android recusa e o Flutter só regista o
/// erro: o GPS que alimenta o despacho ficava calado até reabrir a app.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('regra: pode ligar o serviço de localização agora?', () {
    bool pode(LocationPermission p, AppLifecycleState? e, {bool ligada = true}) =>
        podeLigarServicoDeLocalizacao(
            localizacaoLigada: ligada, permissao: p, estadoDaApp: e);

    test('"enquanto se usa" só com a app à frente (o caso do Danilo)', () {
      expect(pode(LocationPermission.whileInUse, AppLifecycleState.resumed),
          isTrue);
      for (final e in [
        AppLifecycleState.paused,
        AppLifecycleState.inactive,
        AppLifecycleState.hidden,
        AppLifecycleState.detached,
        null,
      ]) {
        expect(pode(LocationPermission.whileInUse, e), isFalse,
            reason: 'ligava o serviço com a app em $e');
      }
    });

    test('"sempre" pode em qualquer altura (não se piora quem já funciona)',
        () {
      for (final e in [...AppLifecycleState.values, null]) {
        expect(pode(LocationPermission.always, e), isTrue, reason: '$e');
      }
    });

    test('sem permissão ou com a localização desligada, nunca', () {
      for (final p in [
        LocationPermission.denied,
        LocationPermission.deniedForever,
        LocationPermission.unableToDetermine,
      ]) {
        expect(pode(p, AppLifecycleState.resumed), isFalse, reason: '$p');
      }
      expect(
          pode(LocationPermission.always, AppLifecycleState.resumed,
              ligada: false),
          isFalse);
    });
  });

  group('o GPS ligado em fundo sem serviço é reconhecido para se religar', () {
    final semServico = AndroidSettings(accuracy: LocationAccuracy.high);
    final comServico = AndroidSettings(
      accuracy: LocationAccuracy.high,
      foregroundNotificationConfig: const ForegroundNotificationConfig(
        notificationTitle: 't',
        notificationText: 'x',
      ),
    );

    test('em fundo e sem serviço → religar; à frente ou com serviço → não',
        () {
      final b = TestWidgetsFlutterBinding.instance;
      b.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      b.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      b.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
      b.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      expect(gpsLigadoSemServicoPorEstarEmFundo(semServico), isTrue);
      expect(gpsLigadoSemServicoPorEstarEmFundo(comServico), isFalse);
      expect(
          gpsLigadoSemServicoPorEstarEmFundo(
              const LocationSettings(accuracy: LocationAccuracy.high)),
          isFalse,
          reason: 'iPhone/web não usam o serviço do Android');

      b.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
      b.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      b.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      expect(gpsLigadoSemServicoPorEstarEmFundo(semServico), isFalse,
          reason: 'à frente e sem serviço é falta de permissão, não fundo');
    });
  });

  group('iPhone: o GPS da corrida e da entrega continua com a app em fundo', () {
    tearDown(() => debugDefaultTargetPlatformOverride = null);

    test('a corrida TVDE no iPhone pede localização em fundo, sem pausas', () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      final d = await TvdeCorridaLocalizacao.definicoesDeCorrida();
      expect(d, isA<AppleSettings>(),
          reason: 'definições simples param o GPS quando a app vai para fundo');
      final a = d as AppleSettings;
      expect(a.allowBackgroundLocationUpdates, isTrue);
      expect(a.pauseLocationUpdatesAutomatically, isFalse);
      expect(a.activityType, ActivityType.automotiveNavigation);
      expect(a.accuracy, LocationAccuracy.bestForNavigation);
    });

    test('o mapa da entrega no iPhone também, e o Android segue a regra', () {
      final f = File('lib/screens/driver_map_screen.dart').readAsStringSync();
      expect(f, contains('locationSettings = AppleSettings('));
      expect(f, contains('allowBackgroundLocationUpdates: true'));
      expect(f, contains('foregroundNotificationConfig: comServico'));
      expect(f, contains('_gpsSemServicoPorFundo = gpsLigadoSemServicoPorEstarEmFundo(locationSettings);'));
      expect(f, contains('AppLifecycleListener(onResume:'));
      final plist = File('ios/Runner/Info.plist').readAsStringSync();
      expect(plist, contains('<string>location</string>'),
          reason: 'sem o modo de fundo "location" o iPhone rebenta com isto');
    });
  });

  test('dois arranques sobrepostos nunca deixam uma subscrição de GPS órfã', () {
    for (final c in [
      'lib/screens/driver/tvde/tvde_driver_home_screen.dart',
      'lib/screens/driver/tvde/tvde_ride_active_screen.dart',
      'lib/screens/driver_home_screen.dart',
      'lib/screens/driver_map_screen.dart',
    ]) {
      final f = File(c).readAsStringSync();
      expect(f, contains('final geracao = ++_gpsGeracao;'), reason: c);
      expect(f, contains('geracao != _gpsGeracao'), reason: c);
      expect(f, contains('if (anterior != null) unawaited(anterior.cancel());'),
          reason: '$c: a subscrição anterior tem de sair antes da nova');
    }
    final corrida = File('lib/screens/driver/tvde/tvde_ride_active_screen.dart')
        .readAsStringSync();
    final escuta = corrida.indexOf('Geolocator.getPositionStream(locationSettings: settings).listen(');
    expect(corrida.substring(escuta, corrida.indexOf('_assumirGps();', escuta)),
        contains('if (!mounted) return;'),
        reason: 'uma leitura depois de o ecrã fechar tirava o GPS à home para sempre');
  });

  test('os três sítios que ligam o GPS religam-no ao voltar à frente', () {
    String ler(String c) => File(c).readAsStringSync();
    final tvdeHome = ler('lib/screens/driver/tvde/tvde_driver_home_screen.dart');
    final corrida = ler('lib/screens/driver/tvde/tvde_ride_active_screen.dart');
    final entregas = ler('lib/screens/driver_home_screen.dart');
    final servicoCorrida = ler('lib/services/tvde_corrida_localizacao_service.dart');
    final online = ler('lib/services/localizacao_online.dart');

    for (final (nome, f) in [
      ('home TVDE', tvdeHome),
      ('corrida', corrida),
      ('entregas', entregas),
    ]) {
      expect(f, contains('_gpsSemServicoPorFundo = gpsLigadoSemServicoPorEstarEmFundo('),
          reason: '$nome não marca o GPS ligado em fundo');
    }
    expect(tvdeHome, contains('if (_gpsSemServicoPorFundo &&'));
    expect(entregas, contains('if (_gpsSemServicoPorFundo && _positionSubscription != null)'));
    expect(corrida, contains('AppLifecycleListener(onResume:'));
    expect(servicoCorrida, contains('podeLigarServicoDeLocalizacao('));
    expect(online, contains('estadoDaApp: WidgetsBinding.instance.lifecycleState'));
  });
}
