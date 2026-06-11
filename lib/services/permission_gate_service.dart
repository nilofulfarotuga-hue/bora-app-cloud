import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_overlay_window/flutter_overlay_window.dart' as fow;

import 'foreground_service.dart';

/// Sessão 2026-05-22 — Permission gate estilo Uber/Glovo: ANTES de deixar
/// o estafeta ficar Online, força a concessão de 4 permissões críticas em
/// sequência. Sem isto, o overlay/fullScreenIntent de pedido novo não
/// aparece quando a app vai para background — exactamente o sintoma
/// reportado pelo Danilo.
///
/// As 4 permissões obrigatórias:
///   1. POST_NOTIFICATIONS (Android 13+) — para foreground service notif +
///      canal urgente `bora_orders_urgent_v2`
///   2. SYSTEM_ALERT_WINDOW — para flutter_overlay_window desenhar o card
///      sobre outras apps (ecrã desbloqueado)
///   3. USE_FULL_SCREEN_INTENT (Android 14+) — para a notificação de novo
///      pedido abrir a MainActivity em fullscreen por cima de outras apps
///      / lockscreen. Em Android <14 é auto-granted via manifest.
///   4. Ignore battery optimizations — para Android 12+ não matar o FGS
///      em background longo
///
/// Cada falha mostra um diálogo explicativo (não silencioso) e abre o picker
/// nativo. Retorna true só quando as 4 estão concedidas.
class PermissionGateService {
  PermissionGateService._();

  /// Bridge nativa registada em MainActivity.kt (NATIVE_BRIDGE).
  static const MethodChannel _nativeBridge =
      MethodChannel('pt.boraapp.bora/native');

  /// Estado REAL de USE_FULL_SCREEN_INTENT via
  /// NotificationManager.canUseFullScreenIntent() (API 34+).
  ///
  /// Sessão 2026-06-11 — root cause do "ecrã bloqueado não acorda": a Play
  /// Store revoga esta permissão na instalação (Android 14+) para apps que
  /// não são de chamadas/alarmes; o fullScreenIntent passa a ser ignorado
  /// em silêncio. Devolve:
  ///   true  → concedida (ou Android <14, auto via manifest)
  ///   false → revogada/negada — notif de pedido NÃO acorda o ecrã
  ///   null  → indeterminado (bridge indisponível; não-Android)
  static Future<bool?> checkFullScreenIntentAllowed() async {
    try {
      final res =
          await _nativeBridge.invokeMethod<bool>('canUseFullScreenIntent');
      return res;
    } catch (e) {
      debugPrint('[BORA-FSI] checkFullScreenIntentAllowed indeterminado: $e');
      return null;
    }
  }

  /// Tenta garantir as 4 permissões para o driver ficar Online.
  /// Mostra diálogos explicativos antes de cada pedido nativo.
  /// Devolve true só quando todas concedidas — UI deve abortar caso false.
  static Future<bool> ensureDriverOnlinePermissions(BuildContext context) async {
    // 1) POST_NOTIFICATIONS (Android 13+) — primeiro porque o foreground
    //    service nem arranca sem isto.
    final notifOk = await _ensureNotificationPermission(context);
    if (!notifOk) return false;
    if (!context.mounted) return false;

    // 2) SYSTEM_ALERT_WINDOW — sem isto o overlay não desenha em background.
    final overlayOk = await _ensureOverlayPermission(context);
    if (!overlayOk) return false;
    if (!context.mounted) return false;

    // 3) USE_FULL_SCREEN_INTENT (Android 14+) — sem isto a notif de novo
    //    pedido nunca abre a activity em fullscreen sobre outra app/lock.
    //    Em Android <14 é always-granted; o método é no-op silencioso.
    final fsiOk = await _ensureFullScreenIntentPermission(context);
    if (!fsiOk) return false;
    if (!context.mounted) return false;

    // 4) Ignore battery optimizations — sem isto Android 12+ pode matar o
    //    foreground service em background longo (>30 min).
    final batteryOk = await _ensureBatteryOptimization(context);
    if (!batteryOk) return false;

    return true;
  }

  // ── 1. Notifications ──────────────────────────────────────────────────────

  static Future<bool> _ensureNotificationPermission(
      BuildContext context) async {
    try {
      final status = await FlutterForegroundTask.checkNotificationPermission();
      if (status == NotificationPermission.granted) return true;
      if (!context.mounted) return false;
      final go = await _showRationale(
        context,
        title: '🔔 Notificações',
        body:
            'A Bora precisa de mostrar notificações para te avisar de novos '
            'pedidos mesmo com a app fechada.\n\nSem esta permissão não vais '
            'receber pedidos em background.',
      );
      if (go != true) return false;
      final granted =
          await FlutterForegroundTask.requestNotificationPermission();
      return granted == NotificationPermission.granted;
    } catch (e) {
      debugPrint('[PermissionGate] notif error: $e');
      return false;
    }
  }

  // ── 2. Overlay (SYSTEM_ALERT_WINDOW) ──────────────────────────────────────

  static Future<bool> _ensureOverlayPermission(BuildContext context) async {
    try {
      if (await fow.FlutterOverlayWindow.isPermissionGranted()) return true;
      if (!context.mounted) return false;
      final go = await _showRationale(
        context,
        title: '📲 Mostrar sobre outras apps',
        body:
            'A Bora precisa de mostrar o card do pedido por cima de outras '
            'apps para tu poderes aceitar/rejeitar sem abrir a Bora.\n\n'
            'Sem esta permissão os pedidos só aparecem quando regressas à app.',
      );
      if (go != true) return false;
      await fow.FlutterOverlayWindow.requestPermission();
      // O picker do Android é assíncrono — verificamos o estado actual.
      return await fow.FlutterOverlayWindow.isPermissionGranted();
    } catch (e) {
      debugPrint('[PermissionGate] overlay error: $e');
      return false;
    }
  }

  // ── 3. Full-screen intent (Android 14+) ───────────────────────────────────

  /// Android 14 (API 34) restringiu fullScreenIntent: apps de delivery não
  /// recebem auto-grant. Sem esta perm, a notif do FCM em background é
  /// downgraded para heads-up — o pedido fica visível mas NÃO aparece por
  /// cima da outra app que o estafeta está a usar.
  ///
  /// O `flutter_local_notifications` ^17.x expõe
  /// `requestFullScreenIntentPermission()` que abre o picker do sistema
  /// (Settings.ACTION_MANAGE_APP_USE_FULL_SCREEN_INTENTS). Em Android <14
  /// devolve true imediatamente (always-granted via manifest).
  static Future<bool> _ensureFullScreenIntentPermission(
      BuildContext context) async {
    try {
      // Sessão 2026-06-11 — verificar o estado REAL primeiro (a Play revoga
      // esta permissão na instalação em Android 14+). Se já está concedida,
      // não chatear o estafeta com diálogo nenhum.
      final allowed = await checkFullScreenIntentAllowed();
      debugPrint('[BORA-FSI] gate online: canUseFullScreenIntent=$allowed');
      if (allowed == true) return true;

      final plugin = FlutterLocalNotificationsPlugin();
      final androidImpl = plugin.resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>();
      if (androidImpl == null) return true; // não-Android
      if (!context.mounted) return false;
      final go = await _showRationale(
        context,
        title: '📱 Pedidos com o ecrã bloqueado',
        body:
            'Para a chamada de pedido acordar o teu telemóvel (mesmo '
            'bloqueado ou com a Bora fechada), o Android 14+ exige uma '
            'autorização especial que a Play Store desliga na instalação.\n\n'
            'Vais ser levado às definições — activa a opção de ecrã '
            'inteiro para a Bora. Sem isto, o pedido chega só como '
            'notificação normal e podes perdê-lo.',
      );
      if (go != true) return false;
      // Abre Settings.ACTION_MANAGE_APP_USE_FULL_SCREEN_INTENT e devolve o
      // estado REAL no regresso (verificado no source do plugin 17.2.4:
      // onActivityResult → canUseFullScreenIntent()).
      final granted = await androidImpl.requestFullScreenIntentPermission();
      // Re-check defensivo pela bridge nativa — fonte de verdade única.
      final after = await checkFullScreenIntentAllowed();
      debugPrint('[BORA-FSI] pós-settings: plugin=$granted bridge=$after');
      return after ?? granted ?? true;
    } catch (e) {
      debugPrint('[BORA-FSI] gate error (não bloqueia Online): $e');
      // Falha do plugin não bloqueia o estafeta — fallback heads-up funciona.
      return true;
    }
  }

  // ── 4. Battery optimization ───────────────────────────────────────────────

  static Future<bool> _ensureBatteryOptimization(BuildContext context) async {
    try {
      if (await FlutterForegroundTask.isIgnoringBatteryOptimizations) {
        return true;
      }
      if (!context.mounted) return false;
      final go = await _showRationale(
        context,
        title: '🔋 Optimização de bateria',
        body:
            'O Android está a optimizar a bateria da Bora — isto pode matar '
            'a app em background e fazer-te perder pedidos.\n\nVais ser '
            'levado às definições. Escolhe "Não optimizar".',
      );
      if (go != true) return false;
      await FlutterForegroundTask.requestIgnoreBatteryOptimization();
      // Picker é asyncrono — re-check estado actual.
      return await FlutterForegroundTask.isIgnoringBatteryOptimizations;
    } catch (e) {
      debugPrint('[PermissionGate] battery error: $e');
      return false;
    }
  }

  // ── Diagnóstico (sem prompts) ─────────────────────────────────────────────

  /// Snapshot individual das 4 permissões — para o ecrã de estado do
  /// estafeta (DriverPermissionsScreen). Nunca abre pickers nem diálogos.
  static Future<DriverPermissionsSnapshot> snapshot() async {
    bool notif = false;
    bool overlay = false;
    bool battery = false;
    bool? fsi;
    try {
      notif = await FlutterForegroundTask.checkNotificationPermission() ==
          NotificationPermission.granted;
    } catch (_) {}
    try {
      overlay = await fow.FlutterOverlayWindow.isPermissionGranted();
    } catch (_) {}
    try {
      battery = await FlutterForegroundTask.isIgnoringBatteryOptimizations;
    } catch (_) {}
    fsi = await checkFullScreenIntentAllowed();
    debugPrint('[BORA-FSI] snapshot notif=$notif overlay=$overlay '
        'battery=$battery fsi=$fsi');
    return DriverPermissionsSnapshot(
      notifications: notif,
      overlay: overlay,
      battery: battery,
      fullScreenIntent: fsi,
    );
  }

  /// Verifica silenciosamente o estado actual das 4 permissões.
  /// Usado no initState do driver_home para detectar revogações
  /// (utilizador foi às definições e tirou uma perm enquanto online,
  /// ou a Play revogou USE_FULL_SCREEN_INTENT numa reinstalação).
  static Future<bool> areAllGranted() async {
    try {
      final notifStatus =
          await FlutterForegroundTask.checkNotificationPermission();
      if (notifStatus != NotificationPermission.granted) return false;
      if (!await fow.FlutterOverlayWindow.isPermissionGranted()) return false;
      if (!await FlutterForegroundTask.isIgnoringBatteryOptimizations) {
        return false;
      }
      // Sessão 2026-06-11 — FSI fazia falta aqui: revogação pela Play era
      // invisível e o estafeta perdia pedidos com o ecrã bloqueado sem
      // qualquer aviso. null (indeterminado) não chumba o check.
      final fsi = await checkFullScreenIntentAllowed();
      debugPrint('[BORA-FSI] areAllGranted: canUseFullScreenIntent=$fsi');
      if (fsi == false) return false;
      return true;
    } catch (e) {
      debugPrint('[PermissionGate] areAllGranted error: $e');
      return false;
    }
  }

  // ── UI helper ─────────────────────────────────────────────────────────────

  static Future<bool?> _showRationale(
    BuildContext context, {
    required String title,
    required String body,
  }) {
    return showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: Text(body),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Agora não'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Conceder'),
          ),
        ],
      ),
    );
  }

  /// Atalho para garantir o init do BoraForegroundService antes do gate
  /// (idempotente). Útil quando o gate é chamado antes do main isolate
  /// terminar o init paralelo.
  static Future<void> ensureForegroundInitialized() =>
      BoraForegroundService.init();
}

/// Estado das 4 permissões críticas do estafeta num dado instante.
/// [fullScreenIntent] é nullable: null = indeterminado (bridge nativa
/// indisponível) — não deve ser tratado como falha.
class DriverPermissionsSnapshot {
  const DriverPermissionsSnapshot({
    required this.notifications,
    required this.overlay,
    required this.battery,
    required this.fullScreenIntent,
  });

  final bool notifications;
  final bool overlay;
  final bool battery;
  final bool? fullScreenIntent;

  bool get allOk =>
      notifications && overlay && battery && fullScreenIntent != false;
}
