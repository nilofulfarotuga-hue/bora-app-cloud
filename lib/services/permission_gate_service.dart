import 'package:flutter/material.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:flutter_overlay_window/flutter_overlay_window.dart' as fow;

import 'foreground_service.dart';

/// Sessão 2026-05-22 — Permission gate estilo Uber/Glovo: ANTES de deixar
/// o estafeta ficar Online, força a concessão de 3 permissões críticas em
/// sequência. Sem isto, o overlay de pedido novo não aparece quando a app
/// vai para background — exactamente o sintoma reportado pelo Danilo.
///
/// As 3 permissões obrigatórias:
///   1. POST_NOTIFICATIONS (Android 13+) — para foreground service notif +
///      canal urgente `bora_orders_urgent`
///   2. SYSTEM_ALERT_WINDOW — para flutter_overlay_window desenhar o card
///      sobre outras apps
///   3. Ignore battery optimizations — para Android 12+ não matar o FGS
///      em background longo
///
/// Cada falha mostra um diálogo explicativo (não silencioso) e abre o picker
/// nativo. Retorna true só quando as 3 estão concedidas.
class PermissionGateService {
  PermissionGateService._();

  /// Tenta garantir as 3 permissões para o driver ficar Online.
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

    // 3) Ignore battery optimizations — sem isto Android 12+ pode matar o
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

  // ── 3. Battery optimization ───────────────────────────────────────────────

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

  /// Verifica silenciosamente o estado actual das 3 permissões.
  /// Usado no initState do driver_home para detectar revogações
  /// (utilizador foi às definições e tirou uma perm enquanto online).
  static Future<bool> areAllGranted() async {
    try {
      final notifStatus =
          await FlutterForegroundTask.checkNotificationPermission();
      if (notifStatus != NotificationPermission.granted) return false;
      if (!await fow.FlutterOverlayWindow.isPermissionGranted()) return false;
      if (!await FlutterForegroundTask.isIgnoringBatteryOptimizations) {
        return false;
      }
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
