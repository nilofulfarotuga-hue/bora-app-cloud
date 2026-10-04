import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:geolocator/geolocator.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'driver_location_ping_service.dart';
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
///
/// [ronda-fecho A10, 23/09/2026] Online = heartbeat E GPS fresco. O servidor
/// deixa de oferecer a quem tem `driver_locations.last_updated` com mais de
/// `dispatch_gps_fresh_seconds` (180 s) e põe offline acima de
/// `dispatch_gps_offline_seconds`. Na app nativa a posição só era escrita
/// pelo stream de GPS (distanceFilter 50 m): um estafeta PARADO à espera
/// ficava sem sinal e, sem se mexer, sem pedidos. Agora cada tick (30 s)
/// manda também uma posição — mesmo com o FGS a correr, porque o FGS só bate
/// o heartbeat (`driver_heartbeat_by_id`), não a posição.
///
/// [ronda 04/10 · app-estafeta #2] UM SÓ BATIMENTO na app inteira. O ecrã das
/// entregas abre POR CIMA do ecrã TVDE (os dois ficam vivos) e cada um tinha
/// o seu `HeartbeatService` com o seu `Timer` — dois heartbeats e duas
/// posições pedidas ao GPS a cada 30 s. Agora as instâncias partilham um
/// relógio só (`_relogio`): a primeira a arrancar liga-o, a última a parar
/// desliga-o; cada tick corre uma vez e o resultado (sem ligação / posto
/// offline pelo servidor) é copiado para todas as instâncias ativas.
/// `pararTodos()` (sair da conta, botão Offline) desliga tudo de uma vez.
///
/// [ronda 04/10 · #8] Posição a cada ~60 s mesmo PARADO (pedido do Danilo de
/// 23/09): o batimento continua a 30 s, a posição sai em ticks alternados
/// (~60 s) e só se nenhum outro caminho (stream de GPS a andar) a tiver
/// mandado no último minuto — poupa bateria a quem anda e a quem está parado.
class HeartbeatService {
  HeartbeatService({Duration interval = const Duration(seconds: 30)})
      : _interval = interval;

  final Duration _interval;
  bool _running = false;

  bool get isRunning => _running;

  // ── Relógio partilhado entre todas as instâncias ──────────────────────
  static final Set<HeartbeatService> _ativas = <HeartbeatService>{};
  static Timer? _relogio;
  static int _ticksPartilhados = 0;

  /// Quantas instâncias estão ligadas (para testes/diagnóstico).
  @visibleForTesting
  static int get instanciasAtivas => _ativas.length;

  /// Há um relógio de batimento a correr (sair da conta usa isto).
  static bool get relogioAtivo => _relogio != null;

  /// Pára TODOS os batimentos da app (sair da conta / ficar offline). Sem
  /// isto, um ecrã por baixo (TVDE) continuava a bater e o servidor voltava
  /// a pôr o estafeta online (driver_heartbeat põe online com GPS vivo).
  static Future<void> pararTodos() async {
    for (final s in _ativas.toList()) {
      await s.stop();
    }
    _relogio?.cancel();
    _relogio = null;
  }

  static Future<void> _tickPartilhado() async {
    if (_ativas.isEmpty) return;
    _ticksPartilhados++;
    final lider = _ativas.first;
    await lider._tick(comPosicao: _ticksPartilhados % 2 == 1);
    for (final o in _ativas) {
      if (identical(o, lider)) continue;
      o._consecutiveFailures = lider._consecutiveFailures;
      if (o.serverAck.value != lider.serverAck.value) {
        o.serverAck.value = lider.serverAck.value;
      }
    }
  }

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
  Future<void> pingNow() => _tick(comPosicao: true);

  Future<void> start() async {
    if (_running) return;
    _running = true;
    _pausedAwaitingUser = false;
    serverMarkedOffline.value = false;
    if (kIsWeb) {
      _wireVisibility();
      unawaited(WebPresence.instance.requestWakeLock());
    }
    final jaHaviaRelogio = _relogio != null && _ativas.isNotEmpty;
    _ativas.add(this);
    if (jaHaviaRelogio) {
      // Outro ecrã já bate: herda o estado dele, não cria segundo relógio.
      final lider = _ativas.first;
      _consecutiveFailures = lider._consecutiveFailures;
      serverAck.value = lider.serverAck.value;
      return;
    }
    // Imediato + periódico (não esperar pelo primeiro tick).
    _relogio?.cancel();
    _ticksPartilhados = 0;
    unawaited(_tickPartilhado());
    _relogio = Timer.periodic(_interval, (_) => _tickPartilhado());
  }

  Future<void> stop() async {
    final estavaAtiva = _ativas.remove(this);
    if (_ativas.isEmpty) {
      _relogio?.cancel();
      _relogio = null;
      if (kIsWeb && estavaAtiva) {
        unawaited(WebPresence.instance.releaseWakeLock());
      }
    }
    _running = false;
    _pausedAwaitingUser = false;
    serverMarkedOffline.value = false;
    // Offline intencional não é falha de ligação.
    _consecutiveFailures = 0;
    serverAck.value = true;
  }

  /// A UI respondeu "sim, voltar a ficar online": retoma os ticks já.
  Future<void> resumeAfterUserConfirmed() async {
    _pausedAwaitingUser = false;
    serverMarkedOffline.value = false;
    await _tick(comPosicao: true);
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
    unawaited(_tick(comPosicao: true));
  }

  Future<void> _tick({bool comPosicao = true}) async {
    if (_pausedAwaitingUser) return;
    // [ronda-fecho A10, 23/09/2026] Posição na app nativa antes do salto do
    // FGS: online = heartbeat E GPS fresco (ver cabeçalho). [04/10] ticks
    // alternados (~60 s) e só se a última posição enviada tiver ≥ 55 s.
    if (!kIsWeb &&
        comPosicao &&
        DriverLocationPingService.instance.segundosDesdeUltimoPing >= 55) {
      unawaited(_pingLocationNative());
    }
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
      if (kIsWeb && comPosicao) unawaited(_pingLocationWeb(client));
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

  /// A última posição conhecida ainda serve se tiver menos de 5 min. Idade
  /// negativa (relógio do telemóvel adiantado) conta como recente.
  @visibleForTesting
  static bool posicaoRecente(DateTime timestamp, {DateTime? agora}) =>
      (agora ?? DateTime.now()).difference(timestamp).abs() <
      const Duration(minutes: 5);

  /// [ronda-fecho A10, 23/09/2026] Nativo: a cada tick manda a posição para
  /// `driver_locations` (via `DriverLocationPingService`, que já limita a
  /// 1 ping/45 s — logo no máximo ~1 por minuto). Usa a última posição
  /// conhecida se tiver menos de 5 min; senão pede uma nova, com limite de
  /// tempo. Sem permissão, sem posição ou sem tempo → não faz nada: nada
  /// pergunta, nada lança, nada bloqueia (PADRAO §1.26). O tick seguinte
  /// tenta outra vez.
  Future<void> _pingLocationNative() async {
    if (_locationInFlight) return;
    _locationInFlight = true;
    try {
      // Só lê a permissão, nunca a pede daqui (o toggle Online já a pediu; e
      // no iOS um getCurrentPosition sem permissão abriria o diálogo).
      final perm = await Geolocator.checkPermission().timeout(
        const Duration(seconds: 5),
        onTimeout: () => LocationPermission.denied,
      );
      if (perm == LocationPermission.denied ||
          perm == LocationPermission.deniedForever) {
        return;
      }
      Position? pos;
      try {
        pos = await Geolocator.getLastKnownPosition().timeout(
          const Duration(seconds: 5),
        );
      } catch (e) {
        debugPrint('[HeartbeatService] última posição: $e');
      }
      if (pos == null || !posicaoRecente(pos.timestamp)) {
        pos = await Geolocator.getCurrentPosition(
          locationSettings: const LocationSettings(
            accuracy: LocationAccuracy.medium,
          ),
        ).timeout(const Duration(seconds: 10));
      }
      await DriverLocationPingService.instance.ping(
        latitude: pos.latitude,
        longitude: pos.longitude,
        heading: pos.heading.isFinite ? pos.heading : null,
        speedKmh: pos.speed.isFinite ? pos.speed * 3.6 : null,
      );
    } catch (e) {
      debugPrint('[HeartbeatService] posição nativa: $e');
    } finally {
      _locationInFlight = false;
    }
  }

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
