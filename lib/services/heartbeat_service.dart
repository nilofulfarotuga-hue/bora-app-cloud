import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:geolocator/geolocator.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'web_presence.dart';

/// Mantém `drivers.last_heartbeat_at` actualizado a cada 30s enquanto o
/// estafeta está online. Backend cron (`expire_stale_driver_presence`)
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
///
/// [Estafeta web 2026-09-16] NO NAVEGADOR este serviço é o ÚNICO sinal de
/// presença — e nunca tinha batido uma vez: `FlutterForegroundTask
/// .isRunningService` lança na web (plugin sem implementação), o `catch`
/// engolia, e o RPC nunca era chamado. Foi por isto que um estafeta real no
/// Safari do iPhone teve ZERO heartbeats em 24 h e nunca ficou disponível
/// para o dispatch (16/09). Agora, na web:
///   • o FGS é ignorado (não existe);
///   • cada tick manda `driver_heartbeat(p_platform)` (web_ios / web_android /
///     web_desktop → painel admin "como usa a Bora") E, se houver posição,
///     `driver_update_location` — os dois a cada 30 s no máximo;
///   • pede o Wake Lock (ecrã ligado) enquanto está online;
///   • quando a página volta a estar visível, verifica se o servidor o pôs
///     offline entretanto e, se sim, avisa a UI (`serverMarkedOffline`) para
///     perguntar "queres voltar a ficar online?" em vez de o religar às
///     escondidas.
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

  /// [Web 16/09] O servidor pôs-nos offline enquanto a página esteve
  /// escondida / o telemóvel bloqueado. A UI pergunta se quer voltar; até
  /// responder, o timer fica em pausa (não religa às escondidas).
  final ValueNotifier<bool> serverMarkedOffline = ValueNotifier<bool>(false);
  bool _pausedAwaitingUser = false;
  bool _visibilityWired = false;

  /// Tick imediato fora do timer (botão "Tentar já" do banner de reconexão).
  Future<void> pingNow() => _tick();

  Future<void> start() async {
    if (_running) return;
    _running = true;
    _pausedAwaitingUser = false;
    serverMarkedOffline.value = false;
    if (kIsWeb) {
      _wireVisibility();
      unawaited(WebPresence.instance.requestWakeLock());
    }
    // Imediato + periódico (não esperar pelo primeiro tick).
    unawaited(_tick());
    _timer = Timer.periodic(_interval, (_) => _tick());
  }

  Future<void> stop() async {
    _timer?.cancel();
    _timer = null;
    _running = false;
    _pausedAwaitingUser = false;
    serverMarkedOffline.value = false;
    // Offline intencional não é falha de ligação.
    _consecutiveFailures = 0;
    serverAck.value = true;
    if (kIsWeb) unawaited(WebPresence.instance.releaseWakeLock());
  }

  /// A UI respondeu "sim, voltar a ficar online": retoma os ticks já.
  Future<void> resumeAfterUserConfirmed() async {
    _pausedAwaitingUser = false;
    serverMarkedOffline.value = false;
    await _tick();
  }

  void _wireVisibility() {
    if (_visibilityWired) return;
    _visibilityWired = true;
    WebPresence.instance.addVisibilityListener(_onVisibility);
  }

  Future<void> _onVisibility(bool visible) async {
    if (!visible || !_running || _pausedAwaitingUser) return;
    // Voltou à página: o cron pode tê-lo posto offline entretanto (iPhone
    // bloqueado suspende o JS por completo). Pergunta-se em vez de religar.
    try {
      final uid = Supabase.instance.client.auth.currentUser?.id;
      if (uid == null) return;
      final row = await Supabase.instance.client
          .from('drivers')
          .select('is_online')
          .eq('user_id', uid)
          .maybeSingle()
          .timeout(const Duration(seconds: 8));
      final online = row?['is_online'] == true;
      if (!online) {
        _pausedAwaitingUser = true;
        serverMarkedOffline.value = true;
        return;
      }
    } catch (e) {
      debugPrint('[HeartbeatService] visibilidade: $e');
    }
    unawaited(_tick());
  }

  Future<void> _tick() async {
    if (_pausedAwaitingUser) return;
    try {
      // Sessão 2026-05-24 (Fix #1) — se o FGS task isolate está vivo, é ele
      // que bate (com auth.uid()=NULL ⇒ usa driver_heartbeat_by_id). Evita
      // duplo POST e mantém este serviço como fallback de foreground puro.
      // Na web não há FGS — e a chamada lançava (ver cabeçalho).
      if (!kIsWeb && await FlutterForegroundTask.isRunningService) {
        return;
      }
      final client = Supabase.instance.client;
      await client.rpc('driver_heartbeat', params: {
        'p_platform': WebPresence.instance.plataforma,
      });
      _consecutiveFailures = 0;
      if (!serverAck.value) serverAck.value = true;

      // Web: a posição não vem de um stream em background — vai buscar-se
      // uma no mesmo compasso do heartbeat (≤ 30 s), se houver permissão.
      if (kIsWeb) unawaited(_pingLocationWeb(client));
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

  bool _locationInFlight = false;

  Future<void> _pingLocationWeb(SupabaseClient client) async {
    if (_locationInFlight) return;
    _locationInFlight = true;
    try {
      final perm = await Geolocator.checkPermission()
          .timeout(const Duration(seconds: 5), onTimeout: () => LocationPermission.denied);
      if (perm == LocationPermission.denied ||
          perm == LocationPermission.deniedForever) {
        return;
      }
      final pos = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(accuracy: LocationAccuracy.medium),
      ).timeout(const Duration(seconds: 10));
      await client.rpc('driver_update_location', params: {
        'p_latitude': pos.latitude,
        'p_longitude': pos.longitude,
        if (pos.heading.isFinite) 'p_heading': pos.heading,
        if (pos.speed.isFinite) 'p_speed_kmh': pos.speed * 3.6,
        'p_is_online': true,
      });
    } catch (e) {
      debugPrint('[HeartbeatService] posição web: $e');
    } finally {
      _locationInFlight = false;
    }
  }
}
