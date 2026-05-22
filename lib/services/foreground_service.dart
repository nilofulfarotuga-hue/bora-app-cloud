import 'package:flutter/foundation.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';

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
        eventAction: ForegroundTaskEventAction.repeat(60000),
        autoRunOnBoot: false,
        autoRunOnMyPackageReplaced: false,
        allowWakeLock: true,
        allowWifiLock: false,
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
  @override
  Future<void> onStart(DateTime timestamp, TaskStarter starter) async {
    debugPrint('[BoraTaskHandler] onStart @ $timestamp (starter=$starter)');
  }

  @override
  void onRepeatEvent(DateTime timestamp) {
    // No-op: heartbeat efectivo corre no main isolate via HeartbeatService.
    // Este callback existe apenas para manter o foreground service vivo —
    // Android mantém o processo principal activo enquanto isto correr.
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
