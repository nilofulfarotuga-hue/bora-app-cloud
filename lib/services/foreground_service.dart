import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

/// Foreground service wrapper para manter driver/parceiro sempre activos
/// em background com notificação persistente (padrão Glovo/Uber Eats).
///
/// Sessão 2026-05-17:
/// - Driver: ao ir Online → notificação "🟢 Bora — Online | À espera de pedidos"
/// - Parceiro: ao abrir loja → notificação "🟢 Bora — Loja aberta"
/// - Android: foreground service real (sobrevive app fechada via swipe).
/// - iOS: usa UIBackgroundModes + APNs priority 10 (não há FS real no iOS).
///
/// Heartbeat 30s continua em [HeartbeatService] no main isolate — a presença
/// do foreground service garante que o processo não é morto pelo OS, pelo que
/// o Timer existente continua a executar.
class BoraForegroundService {
  static const int _serviceId = 1001;
  static const String _channelId = 'bora_service';
  static const String _channelName = 'Bora — Serviço de pedidos';
  static const String _channelDescription =
      'Mantém a app activa para receber pedidos em background.';

  static bool _initialized = false;

  /// Configura o canal Android + opções iOS. Idempotente.
  /// Chamar uma única vez durante o boot da app (ver `main.dart`).
  static Future<void> init() async {
    if (_initialized) return;
    // Persistir credenciais no SharedPreferences para o FGS isolate usar como
    // fallback via getData — necessário porque String.fromEnvironment pode ficar
    // vazio no isolate separado dependendo do build runner.
    const initUrl = String.fromEnvironment('SUPABASE_URL');
    const initKey = String.fromEnvironment('SUPABASE_ANON_KEY');
    if (initUrl.isNotEmpty) {
      await FlutterForegroundTask.saveData(key: 'fgs_supabase_url', value: initUrl);
    }
    if (initKey.isNotEmpty) {
      await FlutterForegroundTask.saveData(key: 'fgs_supabase_key', value: initKey);
    }
    // Guarda também em SharedPreferences standard — o handler de acção de
    // notificação em background não tem acesso ao FlutterForegroundTask.
    final prefs = await SharedPreferences.getInstance();
    if (initUrl.isNotEmpty) await prefs.setString('bora_supabase_url', initUrl);
    if (initKey.isNotEmpty) await prefs.setString('bora_supabase_anon_key', initKey);
    FlutterForegroundTask.init(
      androidNotificationOptions: AndroidNotificationOptions(
        channelId: _channelId,
        channelName: _channelName,
        channelDescription: _channelDescription,
        channelImportance: NotificationChannelImportance.LOW,
        priority: NotificationPriority.LOW,
        showWhen: false,
      ),
      iosNotificationOptions: const IOSNotificationOptions(
        showNotification: false,
        playSound: false,
      ),
      foregroundTaskOptions: ForegroundTaskOptions(
        // Sessão 2026-05-24 — alinhado com cron mark_stale_drivers_offline (90s).
        // Heartbeat bate dentro de _poll() todos os ticks ⇒ frescura ≤30s.
        // Fallback polling REST de ofertas mantém-se cá, mas a primeira linha
        // é o realtime broadcast (driver_store) + FCM data-only — ambos <5s.
        eventAction: ForegroundTaskEventAction.repeat(30000),
        autoRunOnBoot: true,
        autoRunOnMyPackageReplaced: true,
        allowWakeLock: true,
        allowWifiLock: true,
      ),
    );
    _initialized = true;
    debugPrint('[BoraForegroundService] initialised');
  }

  /// Pede exclusão da optimização de bateria (Android 6+).
  /// Sem isto o OS pode matar o foreground service em background longo.
  static Future<void> ensureBatteryOptimization() async {
    try {
      if (!await FlutterForegroundTask.isIgnoringBatteryOptimizations) {
        await FlutterForegroundTask.requestIgnoreBatteryOptimization();
      }
    } catch (e) {
      debugPrint('[BoraForegroundService] battery opt error: $e');
    }
  }

  /// Pede permissão POST_NOTIFICATIONS (Android 13+) se ainda não concedida.
  /// Returns `true` quando o utilizador concedeu.
  static Future<bool> ensureNotificationPermission() async {
    try {
      final status = await FlutterForegroundTask.checkNotificationPermission();
      if (status == NotificationPermission.granted) return true;
      final granted =
          await FlutterForegroundTask.requestNotificationPermission();
      return granted == NotificationPermission.granted;
    } catch (e) {
      debugPrint('[BoraForegroundService] permission error: $e');
      return false;
    }
  }

  /// Persiste o driverId para o FGS task poder fazer polling.
  static Future<void> saveDriverId(String driverId) async {
    await FlutterForegroundTask.saveData(key: 'driverId', value: driverId);
  }

  /// Limpa o driverId quando driver fica offline (polling pára).
  static Future<void> clearDriverId() async {
    await FlutterForegroundTask.removeData(key: 'driverId');
  }

  /// Inicia o serviço com a notificação "🟢 Bora — Online".
  /// Idempotente — se já estiver a correr, devolve `true` sem reiniciar.
  static Future<bool> startDriver() async {
    return _start(
      title: '🟢 Bora — Online',
      text: 'À espera de pedidos...',
    );
  }

  /// Inicia o serviço com a notificação "🟢 Bora — Loja aberta".
  static Future<bool> startPartner() async {
    return _start(
      title: '🟢 Bora — Loja aberta',
      text: 'A receber pedidos...',
    );
  }

  static Future<bool> _start({
    required String title,
    required String text,
  }) async {
    try {
      await ensureBatteryOptimization();
      if (await FlutterForegroundTask.isRunningService) {
        await FlutterForegroundTask.updateService(
          notificationTitle: title,
          notificationText: text,
        );
        return true;
      }
      final result = await FlutterForegroundTask.startService(
        serviceId: _serviceId,
        notificationTitle: title,
        notificationText: text,
        callback: boraForegroundCallback,
      );
      final ok = _resultIsSuccess(result);
      debugPrint('[BoraForegroundService] startService($title) => $ok');
      return ok;
    } catch (e) {
      debugPrint('[BoraForegroundService] start error: $e');
      return false;
    }
  }

  /// Pára o serviço. Idempotente.
  static Future<bool> stop() async {
    try {
      if (!await FlutterForegroundTask.isRunningService) return true;
      final result = await FlutterForegroundTask.stopService();
      final ok = _resultIsSuccess(result);
      debugPrint('[BoraForegroundService] stopService => $ok');
      return ok;
    } catch (e) {
      debugPrint('[BoraForegroundService] stop error: $e');
      return false;
    }
  }

  static bool _resultIsSuccess(dynamic result) {
    if (result == null) return true;
    if (result is bool) return result;
    try {
      return (result as dynamic).success as bool? ?? true;
    } catch (_) {
      return true;
    }
  }
}

/// Entry point top-level requerido pelo flutter_foreground_task.
/// Corre num isolate separado — não dependemos dele para heartbeat
/// (esse fica no main isolate via HeartbeatService).
@pragma('vm:entry-point')
void boraForegroundCallback() {
  FlutterForegroundTask.setTaskHandler(_BoraTaskHandler());
}

class _BoraTaskHandler extends TaskHandler {
  // Compile-time constants — disponíveis em todos os isolates.
  static const _supabaseUrl = String.fromEnvironment('SUPABASE_URL');
  static const _anonKey = String.fromEnvironment('SUPABASE_ANON_KEY');

  bool _isPolling = false;
  String? _lastOfferedOrderId;

  @override
  Future<void> onStart(DateTime timestamp, TaskStarter starter) async {
    debugPrint('[BoraTaskHandler] onStart @ $timestamp (starter=$starter)');
  }

  @override
  void onRepeatEvent(DateTime timestamp) {
    debugPrint('[FGS_POLL] onRepeatEvent tick — isPolling=$_isPolling ts=$timestamp');
    if (_isPolling) return;
    _isPolling = true;
    _poll().whenComplete(() => _isPolling = false);
  }

  Future<void> _poll() async {
    try {
      // ── Bridge SharedPreferences → main ──────────────────────────────────
      // O FCM background handler escreve 'pending_offer' em SharedPreferences
      // (não pode chamar MethodChannels directamente). O FGS lê aqui e
      // reencaminha via sendDataToMain → showDriverOfferOverlay no main isolate.
      try {
        final prefs = await SharedPreferences.getInstance();
        final pending = prefs.getString('pending_offer');
        if (pending != null && pending.isNotEmpty) {
          final data = jsonDecode(pending) as Map<String, dynamic>;
          final offerId = data['orderId']?.toString() ?? '';
          if (offerId.isNotEmpty && offerId != _lastOfferedOrderId) {
            _lastOfferedOrderId = offerId;
            FlutterForegroundTask.sendDataToMain(data);
            debugPrint('[FGS_POLL] pending_offer → sendDataToMain order=$offerId');
          }
          await prefs.remove('pending_offer');
        }
      } catch (e) {
        debugPrint('[FGS_POLL] pending_offer bridge error: $e');
      }

      final driverId = await FlutterForegroundTask.getData<String>(key: 'driverId');
      debugPrint('[FGS_POLL] fired — driverId=${driverId ?? "NULL"}');
      if (driverId == null || driverId.isEmpty) {
        debugPrint('[FGS_POLL] driverId vazio — skipping');
        return;
      }

      // Fallback: se dart-defines não resolveram no isolate FGS, usar os
      // valores guardados no init() via saveData.
      var url = _supabaseUrl;
      var apiKey = _anonKey;
      if (url.isEmpty) {
        url = await FlutterForegroundTask.getData<String>(key: 'fgs_supabase_url') ?? '';
        apiKey = await FlutterForegroundTask.getData<String>(key: 'fgs_supabase_key') ?? '';
        debugPrint('[FGS_POLL] dart-define vazio, fallback getData: url=${url.isEmpty ? "VAZIO!" : "OK"} key=${apiKey.isEmpty ? "VAZIO!" : "OK"}');
      }
      if (url.isEmpty || apiKey.isEmpty) {
        debugPrint('[FGS_POLL] credenciais vazias — skipping');
        return;
      }

      // ── HEARTBEAT (Sessão 2026-05-24, Fix #1) ──────────────────────────────
      // O `HeartbeatService` corre no MAIN isolate via Timer.periodic — esse
      // Timer pode ser pausado em Doze/background. O task isolate do
      // flutter_foreground_task é o único garantidamente vivo enquanto o FGS
      // existe. Bater aqui resolve o sintoma "driver fica preso online mas
      // last_heartbeat_at envelhece > 90s e cron mark_stale_drivers_offline
      // marca offline por engano". Usa `driver_heartbeat_by_id` (recebe id
      // explícito) porque `driver_heartbeat()` usa auth.uid() que é NULL
      // neste isolate (sem sessão).
      try {
        final hbUri = Uri.parse('$url/rest/v1/rpc/driver_heartbeat_by_id');
        await http.post(
          hbUri,
          headers: {
            'apikey': apiKey,
            'Authorization': 'Bearer $apiKey',
            'Content-Type': 'application/json',
          },
          body: jsonEncode({'p_driver_id': driverId}),
        ).timeout(const Duration(seconds: 4));
        debugPrint('[FGS_POLL] heartbeat OK driver=$driverId');
      } catch (e) {
        // Swallow — próximo tick (30s) recupera. Nunca crashar o serviço.
        debugPrint('[FGS_POLL] heartbeat error: $e');
      }

      final uri = Uri.parse(
        '$url/rest/v1/orders'
        '?status=eq.callingDriver'
        '&current_driver_offer_id=eq.$driverId'
        '&assigned_driver_id=is.null'
        '&select=id,vendor_name,price,distance_km,driver_earnings,driver_offer_expires_at'
        '&limit=1',
      );
      debugPrint('[FGS_POLL] GET $url/rest/v1/orders?driverId=$driverId');
      final response = await http.get(uri, headers: {
        'apikey': apiKey,
        'Authorization': 'Bearer $apiKey',
      }).timeout(const Duration(seconds: 4));

      if (response.statusCode != 200) return;
      final List<dynamic> orders = jsonDecode(response.body) as List<dynamic>;
      if (orders.isEmpty) {
        _lastOfferedOrderId = null; // sem oferta activa — reset dedup
        return;
      }
      final order = orders[0] as Map<String, dynamic>;
      final orderId = order['id']?.toString() ?? '';
      if (orderId.isEmpty || orderId == _lastOfferedOrderId) return;

      // Verificar se oferta não expirou
      final expiresAt = order['driver_offer_expires_at'] as String?;
      if (expiresAt != null) {
        if (DateTime.now().isAfter(DateTime.parse(expiresAt))) return;
      }

      _lastOfferedOrderId = orderId;
      FlutterForegroundTask.sendDataToMain(<String, dynamic>{
        'type': 'new_order_offer',
        'orderId': orderId,
        'vendorName': order['vendor_name']?.toString() ?? 'Pedido',
        'total': (order['price'] ?? 0).toString(),
        'distanceKm': (order['distance_km'] ?? 0).toString(),
        'driverEarnings': (order['driver_earnings'] ?? 0).toString(),
      });
      debugPrint('[BoraTaskHandler] offer found order=$orderId → sendDataToMain');
    } catch (e) {
      debugPrint('[BoraTaskHandler] poll error: $e');
    }
  }

  @override
  Future<void> onDestroy(DateTime timestamp) async {
    debugPrint('[BoraTaskHandler] onDestroy @ $timestamp');
  }

  /// Sessão 2026-05-22 (bridge FCM→FGS→main): o
  /// `_firebaseMessagingBackgroundHandler` envia aqui o payload de
  /// `new_order_offer` via `sendDataToTask`. Reencaminhamos imediatamente ao
  /// main isolate via `sendDataToMain`, onde `NotificationService` consegue
  /// desenhar o overlay (impossível a partir deste isolate de service em
  /// Android 14+).
  @override
  void onReceiveData(Object data) {
    debugPrint('[BoraTaskHandler] onReceiveData → forwarding to main: $data');
    FlutterForegroundTask.sendDataToMain(data);
  }

  @override
  void onNotificationButtonPressed(String id) {}

  @override
  void onNotificationPressed() {
    FlutterForegroundTask.launchApp('/');
  }

  @override
  void onNotificationDismissed() {}
}
