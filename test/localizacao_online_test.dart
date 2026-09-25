import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';

import 'package:bora_app/services/driver_location_ping_service.dart';
import 'package:bora_app/services/localizacao_online.dart';

/// Oferta na hora (23/09): o GPS "online à espera" tem de mandar posição
/// mesmo PARADO e a um compasso curto — senão o motorista sai do matching
/// com a app em fundo (corrida real 1e13a6ea, oferta aos 33 s).
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('Android: posição a cada 15 s, sem filtro de distância', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    try {
      final s = await LocalizacaoOnline.definicoes(titulo: 't', texto: 'x');
      expect(s, isA<AndroidSettings>());
      final a = s as AndroidSettings;
      expect(a.distanceFilter, 0);
      expect(a.intervalDuration, const Duration(seconds: 15));
      // Sem plugin nativo (teste) não há permissão confirmada → nunca liga o
      // serviço em primeiro plano às cegas (SecurityException no Android 14+).
      expect(a.foregroundNotificationConfig, isNull);
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });

  test('iOS: localização em fundo ligada e sem pausa automática', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    try {
      final s = await LocalizacaoOnline.definicoes(titulo: 't', texto: 'x');
      expect(s, isA<AppleSettings>());
      final a = s as AppleSettings;
      expect(a.allowBackgroundLocationUpdates, isTrue);
      expect(a.pauseLocationUpdatesAutomatically, isFalse);
      expect(a.distanceFilter, 0);
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });

  test('envio da posição ao servidor no máximo ~15 s (era 45 s)', () {
    expect(DriverLocationPingService.minIntervalSeconds, lessThanOrEqualTo(15));
  });
}
