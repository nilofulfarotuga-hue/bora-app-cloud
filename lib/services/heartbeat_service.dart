import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Mantém `drivers.last_heartbeat_at` actualizado a cada 30s enquanto o
/// estafeta está online. Backend cron (`mark_stale_drivers_offline`)
/// marca offline qualquer driver com last_heartbeat_at > 90s atrás.
///
/// Owner: driver_home_screen.dart
///   - start() ao toggle Online ou se já online no initState
///   - stop()  ao toggle Offline, logout, dispose, app paused
///   - app resumed → start() se ainda online localmente
class HeartbeatService {
  HeartbeatService({Duration interval = const Duration(seconds: 30)})
      : _interval = interval;

  final Duration _interval;
  Timer? _timer;
  bool _running = false;

  bool get isRunning => _running;

  Future<void> start() async {
    if (_running) return;
    _running = true;
    // Imediato + periódico (não esperar pelo primeiro tick).
    unawaited(_tick());
    _timer = Timer.periodic(_interval, (_) => _tick());
  }

  Future<void> stop() async {
    _timer?.cancel();
    _timer = null;
    _running = false;
  }

  Future<void> _tick() async {
    try {
      await Supabase.instance.client.rpc('driver_heartbeat');
    } catch (e) {
      // Swallow: se o app perde rede, próximo tick recupera. Não cancelar
      // o timer aqui — o cron backend já trata staleness se for prolongado.
      debugPrint('[HeartbeatService] tick failed: $e');
    }
  }
}
