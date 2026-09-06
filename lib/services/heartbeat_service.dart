import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Mantém `drivers.last_heartbeat_at` actualizado a cada 30s enquanto o
/// estafeta está online. Backend cron (`mark_stale_drivers_offline`)
/// marca offline qualquer driver com last_heartbeat_at > 90s atrás.
///
/// Owner: driver_home_screen.dart
///   - start() ao toggle Online ou se já online no initState
///   - stop()  ao toggle Offline, logout, dispose, app paused
///   - app resumed → start() se ainda online localmente
///
/// Sessão 2026-05-24 (Fix #1): este serviço passa a ser FALLBACK de
/// foreground. Quando o FGS está a correr (driver Online), o heartbeat
/// efectivo bate no task isolate dentro do `_BoraTaskHandler._poll()` —
/// que sobrevive a Doze/background, ao contrário deste Timer no main
/// isolate. Para evitar duplo POST, `_tick` saltam quando o FGS está vivo.
class HeartbeatService {
  HeartbeatService({Duration interval = const Duration(seconds: 30)})
      : _interval = interval;

  final Duration _interval;
  Timer? _timer;
  bool _running = false;

  bool get isRunning => _running;

  /// F4B (2026-08-16) — presença HONESTA: false após 3 falhas consecutivas do
  /// heartbeat (~90s sem o servidor confirmar). A UI do motorista escuta isto
  /// para mostrar "sem ligação" em vez de um verdinho mentiroso.
  final ValueNotifier<bool> serverAck = ValueNotifier<bool>(true);
  int _consecutiveFailures = 0;

  /// Tick imediato fora do timer (botão "Tentar já" do banner de reconexão).
  Future<void> pingNow() => _tick();

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
    // Offline intencional não é falha de ligação.
    _consecutiveFailures = 0;
    serverAck.value = true;
  }

  Future<void> _tick() async {
    try {
      // Sessão 2026-05-24 (Fix #1) — se o FGS task isolate está vivo, é ele
      // que bate (com auth.uid()=NULL ⇒ usa driver_heartbeat_by_id). Evita
      // duplo POST e mantém este serviço como fallback de foreground puro.
      if (await FlutterForegroundTask.isRunningService) {
        return;
      }
      await Supabase.instance.client.rpc('driver_heartbeat');
      _consecutiveFailures = 0;
      if (!serverAck.value) serverAck.value = true;
    } catch (e) {
      // Swallow: se o app perde rede, próximo tick recupera. Não cancelar
      // o timer aqui — o cron backend já trata staleness se for prolongado.
      debugPrint('[HeartbeatService] tick failed: $e');
      // F4B: 3 falhas seguidas (~90s) = servidor já nos marcou offline — a UI
      // tem de dizer a verdade em vez do verdinho.
      _consecutiveFailures++;
      if (_consecutiveFailures >= 3 && serverAck.value) {
        serverAck.value = false;
      }
    }
  }
}
