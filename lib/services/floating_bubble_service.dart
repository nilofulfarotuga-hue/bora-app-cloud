// lib/services/floating_bubble_service.dart
//
// Bora App — Floating Bubble Manager (Sessão 2026-05-19)
// Bolinha flutuante estilo Uber/Glovo. Aparece quando driver Online e app
// vai para background; desaparece quando app volta ao foreground ou Offline.
// Android-only — iOS não suporta system overlays sobre outras apps.
//
// Pacote: floating_bubble_overlay ^1.0.5 (Dez/2025, Android-only, minSdk 21).
// API real (instance-based, BubbleOptions/NotificationOptions ficam em src/):
//   FloatingBubbleOverlay.instance.startBubble(...)
//   FloatingBubbleOverlay.instance.stopBubble()
// O package auto-merge AndroidManifest com:
//   - <service .src.BubbleService foregroundServiceType="specialUse">
//   - SYSTEM_ALERT_WINDOW + FOREGROUND_SERVICE + POST_NOTIFICATIONS
//   - FOREGROUND_SERVICE_SPECIAL_USE
// Bubble icon: null → usa github_bubble bundled no package. Trocar quando
// criarmos asset Bora dedicado em drawable/.
//
// ignore_for_file: implementation_imports — BubbleOptions/NotificationOptions
// vivem em src/ e o package não os re-exporta (decisão deles, ver
// floating_bubble_overlay.dart). O example oficial faz import idêntico.

import '../utils/io_compat.dart';

import 'package:flutter/widgets.dart';
import 'package:floating_bubble_overlay/floating_bubble_overlay.dart';
import 'package:floating_bubble_overlay/src/enums/enums.dart';
import 'package:floating_bubble_overlay/src/models/models.dart';

class BoraBubbleService {
  static bool _driverIsOnline = false;
  static bool _appIsInBackground = false;
  static bool _bubbleVisible = false;

  /// Pede permissão SYSTEM_ALERT_WINDOW. Idempotente.
  /// Retorna true se concedida (já estava ou foi agora).
  static Future<bool> ensureOverlayPermission() async {
    if (!Platform.isAndroid) return false;
    try {
      final has = await FloatingBubbleOverlay.instance.hasOverlayPermission();
      if (has) return true;
      return await FloatingBubbleOverlay.instance.requestOverlayPermission();
    } catch (e) {
      debugPrint('[BoraBubble] ensureOverlayPermission error: $e');
      return false;
    }
  }

  /// Chamar quando driver muda de Online/Offline.
  /// Online + app em background → mostra. Offline → esconde.
  static Future<void> setDriverOnline(bool isOnline) async {
    _driverIsOnline = isOnline;
    if (!Platform.isAndroid) return;
    if (!isOnline) {
      await _hideBubble();
    } else if (_appIsInBackground) {
      await _showBubble();
    }
  }

  /// Hook para WidgetsBindingObserver.didChangeAppLifecycleState.
  /// Foreground → esconde. Background → mostra se driver online.
  static Future<void> onAppLifecycleChange(AppLifecycleState state) async {
    if (!Platform.isAndroid) return;

    final wentToBackground = state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive ||
        state == AppLifecycleState.detached;
    final cameToForeground = state == AppLifecycleState.resumed;

    if (wentToBackground && !_appIsInBackground) {
      _appIsInBackground = true;
      if (_driverIsOnline) await _showBubble();
    } else if (cameToForeground && _appIsInBackground) {
      _appIsInBackground = false;
      await _hideBubble();
    }
  }

  static Future<void> _showBubble() async {
    if (_bubbleVisible) return;
    try {
      final hasPerm =
          await FloatingBubbleOverlay.instance.hasOverlayPermission();
      if (!hasPerm) {
        debugPrint('[BoraBubble] sem permissão overlay — skip');
        return;
      }
      final ok = await FloatingBubbleOverlay.instance.startBubble(
        bubbleOptions: BubbleOptions(
          bubbleIcon: null,
          startLocationX: 0,
          startLocationY: 120,
          bubbleSize: 60,
          opacity: 0.95,
          enableClose: false,
          closeBehavior: CloseBehavior.following,
          distanceToClose: 100,
          enableAnimateToEdge: true,
          enableBottomShadow: true,
          keepAliveWhenAppExit: false,
        ),
        notificationOptions: NotificationOptions(
          id: 2001,
          title: 'Bora Estafeta',
          body: 'Online — toca para voltar à app',
          channelId: 'bora_bubble',
          channelName: 'Bora — Bolinha de estafeta',
        ),
        onTap: () {
          debugPrint('[BoraBubble] tap — app traz-se ao foreground (built-in)');
        },
      );
      _bubbleVisible = ok;
      debugPrint('[BoraBubble] startBubble => $ok');
    } catch (e) {
      debugPrint('[BoraBubble] _showBubble error: $e');
    }
  }

  static Future<void> _hideBubble() async {
    if (!_bubbleVisible) return;
    try {
      await FloatingBubbleOverlay.instance.stopBubble();
      _bubbleVisible = false;
      debugPrint('[BoraBubble] stopBubble OK');
    } catch (e) {
      debugPrint('[BoraBubble] _hideBubble error: $e');
    }
  }
}
