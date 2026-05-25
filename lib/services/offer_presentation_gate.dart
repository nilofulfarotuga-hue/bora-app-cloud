// Sessão 2026-05-25 (exec6 GATE CENTRAL) — Autoridade única de apresentação
// de oferta. Antes deste gate, 3 UIs disparavam em paralelo para o mesmo
// orderId (CallKit + DriverFullScreenOfferDialog + local notif heads-up),
// sem se conhecerem → ecrãs empilhados, som duplicado, "Aceitar não responde".
//
// REGRA FIXA por estado (3 estados):
//   1. FOREGROUND (AppLifecycleState.resumed):
//        → tela laranja in-app já existente (driver_home_screen._showNewOrderDialog)
//        → SoundService loop (in-app, controlado pela tela)
//        → ANTES de mostrar, cancela qualquer CallKit/notif para este orderId
//
//   2. BACKGROUND com ecrã ligado (não bloqueado):
//        → DriverFullScreenOfferDialog full-screen (via navigatorKey)
//        → ringtone via canal de notif (Samsung respeita)
//        → bring MainActivity to foreground via Intent nativo
//
//   3. BLOQUEADO ou APP MORTA:
//        → CallKit (connectycube) — Samsung respeita CallStyle+showWhenLocked
//        → ringtone CallKit nativo (sem som extra)
//        → Atender → driver_accept_offer RPC + bring app to FG
//
// DEDUP por orderId: _activeGateOrderId. Libertar SÓ em
// markActionCompleted() — accept/reject/expired confirmados.
//
// Som: por agora ringtone normal. bora_alert fica para passo posterior
// (garantir primeiro que toca; embelezar depois).

import 'dart:async';

import 'package:connectycube_flutter_call_kit/connectycube_flutter_call_kit.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'notification_service.dart';

/// Estados que o gate distingue. App em FG resumed vs anything-else.
enum _AppState { foreground, backgroundUnlocked, lockedOrDead }

class OfferPresentationGate {
  OfferPresentationGate._();

  /// Lifecycle conhecido (actualizado por WidgetsBindingObserver no main).
  static AppLifecycleState _lifecycle = AppLifecycleState.resumed;

  /// Dedup global. Libertado em markActionCompleted ou expirado.
  static String? _activeGateOrderId;

  /// Exec6.5 (2026-05-25) — orderIds que JÁ FORAM tratados (rejeitados,
  /// aceites, expirados, ou oferta revogada pelo backend). Bloqueia
  /// re-trigger do mesmo orderId em qualquer UI/path. Limite 50 entries
  /// (FIFO) para não vazar memória ao longo do dia.
  static final List<String> _handledOrderIds = <String>[];
  static const int _handledMaxSize = 50;

  static void _addHandled(String orderId) {
    if (orderId.isEmpty) return;
    _handledOrderIds.remove(orderId); // re-add no fim p/ refresh ordem
    _handledOrderIds.add(orderId);
    while (_handledOrderIds.length > _handledMaxSize) {
      _handledOrderIds.removeAt(0);
    }
  }

  /// Para casos onde re-oferta legítima do dispatch precisa de re-disparar
  /// (ex: cycle reset). Limpa o orderId da lista handled.
  static void clearHandled(String orderId) {
    _handledOrderIds.remove(orderId);
  }

  /// MethodChannel nativo (criado em exec2). `isDeviceLocked` devolve bool.
  static const _nativeBridge = MethodChannel('pt.boraapp.bora/native');

  /// Pendurado pelo `_MyAppState.didChangeAppLifecycleState`.
  static void updateLifecycle(AppLifecycleState s) {
    _lifecycle = s;
    debugPrint('[GATE] lifecycle=$s');
  }

  /// Liberta o dedup quando a UI da oferta termina (accept/reject/expired).
  /// Chamado pelo DriverFullScreenOfferDialog.dispose, pelo _onBoraCallAccepted,
  /// pelo _onBoraCallRejected, pelo cancelDriverOfferNotification, e pelos
  /// helpers RPC. Exec6.5: também marca como "handled" para bloquear
  /// re-trigger do mesmo orderId noutra UI (laranja → bonita "salto").
  static void markActionCompleted(String orderId) {
    if (_activeGateOrderId == orderId) {
      debugPrint('[GATE] release order=$orderId');
      _activeGateOrderId = null;
    }
    _addHandled(orderId);
    debugPrint('[GATE] handled+=$orderId (size=${_handledOrderIds.length})');
    // Exec6.5 — persistir em SP para o BG isolate (FCM bg handler) ver
    // que orderId já foi tratado, evitando disparar CallKit depois do
    // dono rejeitar/aceitar a bonita.
    _persistHandledToSp(orderId);
  }

  static Future<void> _persistHandledToSp(String orderId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final list = prefs.getStringList('gate_handled_orderids') ?? <String>[];
      list.remove(orderId);
      list.add(orderId);
      while (list.length > _handledMaxSize) {
        list.removeAt(0);
      }
      await prefs.setStringList('gate_handled_orderids', list);
    } catch (_) {}
  }

  /// Entrada única. TODOS os triggers (FCM bg, realtime UPDATE, realtime
  /// broadcast, FGS bridge, rehydrate) passam por aqui.
  ///
  /// `fromBgIsolate` = true quando chamado a partir do isolate de background
  /// (FCM bg handler) — não tem acesso a WidgetsBinding/lifecycle, assume
  /// "lockedOrDead" como caminho mais seguro.
  static Future<void> present({
    required String orderId,
    required String vendorName,
    required String total,
    required String distanceKm,
    required String driverEarnings,
    String dropoffAddress = '',
    bool fromBgIsolate = false,
  }) async {
    if (orderId.isEmpty) return;

    // Dedup forte por orderId.
    if (_activeGateOrderId == orderId) {
      debugPrint('[GATE] DEDUP — order=$orderId já tem UI activa');
      return;
    }

    // Exec6.5 — bloquear re-trigger se já foi tratado (rejeitado/aceite/
    // expirado/revogado). Impede o "salto" entre UIs (laranja → bonita).
    if (_handledOrderIds.contains(orderId)) {
      debugPrint('[GATE] HANDLED — order=$orderId já foi tratado, skip');
      return;
    }

    final state = await _detectState(fromBgIsolate: fromBgIsolate);
    debugPrint(
        '[GATE] present order=$orderId state=$state fromBg=$fromBgIsolate');

    _activeGateOrderId = orderId;

    try {
      switch (state) {
        case _AppState.foreground:
          await _showInAppOrange(
            orderId: orderId,
            vendorName: vendorName,
            total: total,
            distanceKm: distanceKm,
            driverEarnings: driverEarnings,
            dropoffAddress: dropoffAddress,
          );
          break;
        case _AppState.backgroundUnlocked:
          await _showFullScreenDialog(
            orderId: orderId,
            vendorName: vendorName,
            total: total,
            distanceKm: distanceKm,
            driverEarnings: driverEarnings,
            dropoffAddress: dropoffAddress,
          );
          break;
        case _AppState.lockedOrDead:
          await _showCallKit(
            orderId: orderId,
            vendorName: vendorName,
            total: total,
            distanceKm: distanceKm,
            driverEarnings: driverEarnings,
          );
          break;
      }
    } catch (e) {
      debugPrint('[GATE] present error: $e — libertando dedup');
      _activeGateOrderId = null;
    }
  }

  /// Detecta estado actual com fall-backs seguros.
  ///   • fromBgIsolate=true → sempre lockedOrDead (caminho CallKit, único
  ///     fiável a partir do BG isolate em Samsung Android 16).
  ///   • FG resumed → foreground.
  ///   • Não resumed + ecrã desbloqueado → backgroundUnlocked.
  ///   • Não resumed + ecrã bloqueado → lockedOrDead.
  static Future<_AppState> _detectState({required bool fromBgIsolate}) async {
    if (fromBgIsolate) return _AppState.lockedOrDead;
    if (_lifecycle == AppLifecycleState.resumed) return _AppState.foreground;
    try {
      final locked = await _nativeBridge.invokeMethod<bool>('isDeviceLocked');
      if (locked == true) return _AppState.lockedOrDead;
    } catch (_) {
      // MethodChannel falhou (engine partilhado offline?) — usar CallKit (seguro).
      return _AppState.lockedOrDead;
    }
    return _AppState.backgroundUnlocked;
  }

  // ── Implementações por estado ─────────────────────────────────────────────

  /// FG: a tela laranja in-app aparece automaticamente quando OrderStore
  /// detecta a oferta via realtime UPDATE. Aqui só garantimos que CallKit
  /// e notifs locais ficam silenciados para este orderId.
  ///
  /// EXEC6 FIX (2026-05-25 02:23): na FG branch NÃO há widget que chame
  /// markActionCompleted (a tela laranja é gerida 100% pelo driver_home_screen
  /// com o seu próprio dedup `_alreadyAlertedOrderIds`). Por isso libertamos
  /// o gate IMEDIATAMENTE — senão fica preso forever neste orderId e bloqueia
  /// todas as re-tentativas/re-ofertas.
  static Future<void> _showInAppOrange({
    required String orderId,
    required String vendorName,
    required String total,
    required String distanceKm,
    required String driverEarnings,
    required String dropoffAddress,
  }) async {
    debugPrint('[GATE] FG → in-app orange (driver_home_screen) para order=$orderId');
    // Cancelar qualquer CallKit/notif que esteja a competir.
    try {
      await ConnectycubeFlutterCallKit.reportCallEnded(sessionId: orderId);
    } catch (_) {}
    await cancelDriverOfferNotification(orderId);
    // EXEC6 FIX (07:01): persist flag para bg handler saber FG tratou —
    // evita CallKit duplicado quando FCM data-only entrega TANTO ao
    // realtime broadcast (FG) COMO ao bg handler em paralelo.
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('gate_fg_handled_orderId', orderId);
      await prefs.setInt(
          'gate_fg_handled_ts', DateTime.now().millisecondsSinceEpoch);
    } catch (_) {}
    // Libertar gate JÁ — driver_home_screen gere a sua própria UI/dedup.
    markActionCompleted(orderId);
  }

  /// BG ecrã desbloqueado: empurra o DriverFullScreenOfferDialog +
  /// bring MainActivity ao topo.
  static Future<void> _showFullScreenDialog({
    required String orderId,
    required String vendorName,
    required String total,
    required String distanceKm,
    required String driverEarnings,
    required String dropoffAddress,
  }) async {
    debugPrint('[GATE] BG-unlocked → full-screen dialog para order=$orderId');
    // Garantir que CallKit não está activo para este orderId.
    try {
      await ConnectycubeFlutterCallKit.reportCallEnded(sessionId: orderId);
    } catch (_) {}
    await NotificationService.instance.showFullScreenOfferDialog(
      orderId: orderId,
      vendorName: vendorName,
      total: total,
      distanceKm: distanceKm,
      driverEarnings: driverEarnings,
      dropoffAddress: dropoffAddress,
    );
  }

  /// Locked/dead: SÓ CallKit (sem dialog full-screen sobreposto).
  /// Quando dono aceitar → main.dart::_onBoraCallAccepted chama RPC.
  static Future<void> _showCallKit({
    required String orderId,
    required String vendorName,
    required String total,
    required String distanceKm,
    required String driverEarnings,
  }) async {
    debugPrint('[GATE] locked/dead → CallKit para order=$orderId');
    try {
      final callEvent = CallEvent(
        sessionId: orderId,
        callType: 0,
        callerId: 1,
        callerName: '🛵 ${vendorName.isEmpty ? "Novo pedido" : vendorName}',
        opponentsIds: const <int>{1},
        userInfo: <String, String>{
          'order_id': orderId,
          'vendor_name': vendorName,
          'total': total,
          'distance_km': distanceKm,
          'driver_earnings': driverEarnings,
        },
      );
      await ConnectycubeFlutterCallKit.showCallNotification(callEvent);
    } catch (e) {
      debugPrint('[GATE] CallKit show error: $e');
    }
  }
}
