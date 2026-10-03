import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../config/app_colors.dart';
import 'foreground_service.dart';

/// GPS do motorista/estafeta ONLINE à espera de trabalho — sempre vivo.
///
/// ## Porque é que isto existe (2026-09-23)
///
/// Corrida real `1e13a6ea`: o cliente pediu às 14:54:22 e a oferta só chegou
/// ao único motorista online (o Danilo, a conduzir a ~88 km/h) aos 33 s — o
/// cliente cancelou aos 37 s. No instante do pedido o motorista estava fora
/// do matching porque a posição em `driver_locations` estava velha.
///
/// Causa na raiz, no telemóvel:
///   1. o GPS "à espera" do TVDE corria SEM serviço em primeiro plano de tipo
///      localização — com a app em fundo o Android estrangula-o a poucas
///      posições por hora;
///   2. `distanceFilter: 50` — parado num semáforo ou na praça não sai
///      posição NENHUMA, por muito tempo que passe;
///   3. o envio ao servidor tinha travão de 45 s.
///
/// Aqui: serviço em primeiro plano de localização (o do geolocator, já no
/// manifesto com `foregroundServiceType="location"`), uma posição a cada
/// ~15 s mesmo parado, e o envio passa a ~15 s
/// (`DriverLocationPingService.minIntervalSeconds`).
class LocalizacaoOnline {
  LocalizacaoOnline._();

  /// Compasso do GPS enquanto online (mesmo parado).
  static const Duration intervalo = Duration(seconds: 15);

  static const String _kPedidoSempre = 'bora_app.pediu_localizacao_sempre_v1';

  /// Definições do stream de GPS "online, à espera de trabalho".
  ///
  /// Android: só liga o serviço em primeiro plano quando o Android 14+ o
  /// permite (localização ligada + permissão concedida) — sem isso o
  /// `startForeground()` rebenta com `SecurityException`. Nesse caso devolve
  /// as mesmas definições sem serviço (funciona, mas estrangulado em fundo).
  static Future<LocationSettings> definicoes({
    required String titulo,
    required String texto,
  }) async {
    if (kIsWeb) {
      return const LocationSettings(accuracy: LocationAccuracy.medium);
    }
    if (defaultTargetPlatform == TargetPlatform.iOS) {
      return AppleSettings(
        accuracy: LocationAccuracy.medium,
        distanceFilter: 0,
        // Parado não pode significar "calado": o iOS pausaria as posições.
        pauseLocationUpdatesAutomatically: false,
        showBackgroundLocationIndicator: true,
        activityType: ActivityType.automotiveNavigation,
        allowBackgroundLocationUpdates: true,
      );
    }
    if (defaultTargetPlatform != TargetPlatform.android) {
      return const LocationSettings(accuracy: LocationAccuracy.medium);
    }
    final podeServico = await _podeServicoLocalizacao();
    return AndroidSettings(
      accuracy: LocationAccuracy.high,
      // 0 = posição a cada `intervalo` mesmo sem sair do sítio.
      distanceFilter: 0,
      intervalDuration: intervalo,
      foregroundNotificationConfig: podeServico
          ? ForegroundNotificationConfig(
              notificationTitle: titulo,
              notificationText: texto,
              notificationChannelName: 'Bora — Online',
              // O CPU não pode adormecer entre posições com o ecrã desligado.
              enableWakeLock: true,
              setOngoing: true,
              notificationIcon: const AndroidResource(
                  name: 'ic_launcher', defType: 'mipmap'),
            )
          : null,
    );
  }

  static Future<bool> _podeServicoLocalizacao() async {
    try {
      if (!await Geolocator.isLocationServiceEnabled()) return false;
      final p = await Geolocator.checkPermission();
      return p == LocationPermission.always ||
          p == LocationPermission.whileInUse;
    } catch (e) {
      debugPrint('[LocalizacaoOnline] verificação falhou: $e');
      return false;
    }
  }

  /// Ao ficar online — UMA vez por instalação — pede a localização "sempre"
  /// e a isenção de otimização de bateria, com uma explicação simples antes.
  ///
  /// Nunca bloqueia ficar online: recusar é permitido (o serviço em primeiro
  /// plano continua a dar GPS com a app minimizada). O "sempre" é o que deixa
  /// o batimento de reserva do serviço Bora mandar a posição mesmo depois de
  /// a app ser fechada de lado.
  static Future<void> pedirUmaVez(BuildContext context) async {
    if (kIsWeb) return;
    if (defaultTargetPlatform != TargetPlatform.android &&
        defaultTargetPlatform != TargetPlatform.iOS) {
      return;
    }
    try {
      final prefs = await SharedPreferences.getInstance();
      if (prefs.getBool(_kPedidoSempre) == true) return;
      final atual = await Geolocator.checkPermission();
      if (atual == LocationPermission.always) {
        await prefs.setBool(_kPedidoSempre, true);
        return;
      }
      if (!context.mounted) return;
      final aceitou = await showDialog<bool>(
            context: context,
            barrierDismissible: false,
            builder: (_) => const _ExplicacaoSempre(),
          ) ??
          false;
      await prefs.setBool(_kPedidoSempre, true);
      if (!aceitou) return;
      var p = atual;
      if (p == LocationPermission.denied) {
        p = await Geolocator.requestPermission();
      }
      // Com "durante a utilização" já dada, o geolocator pede o
      // ACCESS_BACKGROUND_LOCATION (Android 11+ abre a página "Permitir
      // sempre"; iOS mostra o "Permitir sempre").
      if (p == LocationPermission.whileInUse) {
        await Geolocator.requestPermission();
      }
      if (defaultTargetPlatform == TargetPlatform.android) {
        await BoraForegroundService.ensureBatteryOptimization();
      }
    } catch (e) {
      debugPrint('[LocalizacaoOnline] pedirUmaVez: $e');
    }
  }
}

class _ExplicacaoSempre extends StatelessWidget {
  const _ExplicacaoSempre();

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: AppColors.surface,
      icon: const Icon(Icons.bolt, color: AppColors.primary, size: 40),
      title: const Text(
        'Recebe as corridas na hora',
        textAlign: TextAlign.center,
        style: TextStyle(fontWeight: FontWeight.w700, fontSize: 18),
      ),
      content: const Text(
        'Para te chegarem as corridas e os pedidos logo que o cliente pede — '
        'mesmo a conduzir, com a app em fundo ou o ecrã desligado:\n\n'
        '• na localização escolhe "Permitir sempre";\n'
        '• na bateria escolhe "Não otimizar".\n\n'
        'Só usamos a tua localização enquanto estás online.',
        style: TextStyle(fontSize: 14, height: 1.4),
      ),
      actionsAlignment: MainAxisAlignment.spaceBetween,
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('Agora não'),
        ),
        FilledButton(
          style: FilledButton.styleFrom(backgroundColor: AppColors.primary),
          onPressed: () => Navigator.of(context).pop(true),
          child: const Text('Continuar'),
        ),
      ],
    );
  }
}
