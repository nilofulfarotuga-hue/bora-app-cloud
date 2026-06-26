import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:http/http.dart' as http;
import 'package:flutter_overlay_window/flutter_overlay_window.dart' as fow;
import 'package:shared_preferences/shared_preferences.dart';

import 'notification_service.dart' show postWakeActivityNotification;

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
        // Exec6.16 (2026-05-25) CAMADA 3 — polling cada 10s (era 30s).
        // Rede de segurança quando realtime WebSocket morre em BG longo.
        // Camada 2 (moveTaskToBack) mantém main isolate vivo para casos
        // rápidos; este polling cobre Doze mode + swipe-away.
        eventAction: ForegroundTaskEventAction.repeat(10000),
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
  // Heartbeat fires every 3rd tick (10s × 3 = 30s). FGS tick stays at 10s
  // so offer detection remains fast; only the DB heartbeat POST is throttled.
  int _heartbeatTickCount = 0;

  @override
  Future<void> onStart(DateTime timestamp, TaskStarter starter) async {
    debugPrint('[BoraTaskHandler] onStart @ $timestamp (starter=$starter)');
  }

  @override
  void onRepeatEvent(DateTime timestamp) {
    _heartbeatTickCount++;
    debugPrint('[FGS_POLL] onRepeatEvent tick=$_heartbeatTickCount — isPolling=$_isPolling ts=$timestamp');
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

      // ── HEARTBEAT (Sessão 2026-05-24, Fix #1 · 2026-06-26 throttle #1) ────
      // Fires every 3rd FGS tick (10s × 3 = 30s). Cron marks stale after 90s
      // → 30s gives 3× margin. FGS tick stays at 10s for fast offer detection.
      if (_heartbeatTickCount % 3 == 0) {
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
          debugPrint('[FGS_POLL] heartbeat OK driver=$driverId tick=$_heartbeatTickCount');
        } catch (e) {
          debugPrint('[FGS_POLL] heartbeat error: $e');
        }
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
      final payload = <String, dynamic>{
        'type': 'new_order_offer',
        'orderId': orderId,
        'vendorName': order['vendor_name']?.toString() ?? 'Pedido',
        'total': (order['price'] ?? 0).toString(),
        'distanceKm': (order['distance_km'] ?? 0).toString(),
        'driverEarnings': (order['driver_earnings'] ?? 0).toString(),
      };
      FlutterForegroundTask.sendDataToMain(payload);
      debugPrint('[BoraTaskHandler] offer found order=$orderId → sendDataToMain');
      // Exec6.16 (2026-05-25) CAMADA 3 auto-revive: se main isolate morto,
      // dispara fullScreenIntent local notif para acordar Activity. Quando
      // MainActivity sobe, rehydrate pending_offer SP → gate.present → overlay.
      await _wakeActivityIfMainDead(payload);
    } catch (e) {
      debugPrint('[BoraTaskHandler] poll error: $e');
    }
  }

  /// Verifica bora_main_alive_ts SP. Se age > 5s → main isolate morto →
  /// dispara postWakeActivityNotification (fullScreenIntent acorda Activity).
  /// Threshold 5s pq main isolate escreve a cada 3s; 5s = 1 batida + 2s grace.
  Future<void> _wakeActivityIfMainDead(Map<String, dynamic> payload) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.reload();
      final mainAliveTs = prefs.getInt('bora_main_alive_ts') ?? 0;
      final age = DateTime.now().millisecondsSinceEpoch - mainAliveTs;
      debugPrint('[FGS_AUTO_REVIVE] main_alive_age=${age}ms');
      if (age <= 5000) {
        debugPrint('[FGS_AUTO_REVIVE] main isolate vivo (age=${age}ms) — skip wake');
        return;
      }
      // Persist pending_offer para rehydrate consumir quando Activity sobe.
      await prefs.setString('pending_offer', jsonEncode({
        ...payload,
        'ts': DateTime.now().millisecondsSinceEpoch,
      }));
      debugPrint('[FGS_AUTO_REVIVE] main isolate MORTO (age=${age}ms) — postWakeActivity');
      await postWakeActivityNotification(
        orderId: payload['orderId']?.toString() ?? '',
        vendorName: payload['vendorName']?.toString() ?? 'Novo pedido',
        total: payload['total']?.toString() ?? '0.00',
        distanceKm: payload['distanceKm']?.toString() ?? '0',
        driverEarnings: payload['driverEarnings']?.toString() ?? '0.00',
      );
    } catch (e) {
      debugPrint('[FGS_AUTO_REVIVE] error: $e');
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
    debugPrint('[FGS_BRIDGE] [BoraTaskHandler.onReceiveData] ENTRY data=$data');
    try {
      FlutterForegroundTask.sendDataToMain(data);
      debugPrint('[FGS_BRIDGE] [BoraTaskHandler.onReceiveData] sendDataToMain OK');
    } catch (e, st) {
      debugPrint('[FGS_BRIDGE] sendDataToMain EXCEPTION: $e');
      debugPrint('[FGS_BRIDGE] stack: ${st.toString().split("\n").take(3).join(" | ")}');
    }
    // Exec6.18 S2 — tentar shareData directamente do FGS task isolate.
    // Overlay já em standby (driver_home_screen initDriverStandbyOverlay).
    // Se plugin registado neste isolate, overlay aparece sem depender do main.
    if (data is Map) {
      final m = Map<String, dynamic>.from(data);
      _tryShareDataToOverlay(m);
      _wakeActivityIfMainDead(m);
    }
  }

  Future<void> _tryShareDataToOverlay(Map<String, dynamic> payload) async {
    try {
      final granted = await fow.FlutterOverlayWindow.isPermissionGranted();
      if (!granted) {
        debugPrint('[FGS_OVERLAY] sem permissão SYSTEM_ALERT_WINDOW');
        return;
      }
      final active = await fow.FlutterOverlayWindow.isActive();
      if (!active) {
        debugPrint('[FGS_OVERLAY] overlay NOT active — standby ausente');
        return;
      }
      await fow.FlutterOverlayWindow.shareData(<String, dynamic>{
        'orderId': payload['orderId']?.toString() ?? '',
        'vendorName': payload['vendorName']?.toString() ?? 'Novo pedido',
        'total': payload['total']?.toString() ?? '0.00',
        'distanceKm': payload['distanceKm']?.toString() ?? '0',
        'driverEarnings': payload['driverEarnings']?.toString() ?? '0.00',
      });
      debugPrint('[FGS_OVERLAY] shareData OK order=${payload['orderId']}');
    } catch (e) {
      debugPrint('[FGS_OVERLAY] shareData FAILED: $e');
    }
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
