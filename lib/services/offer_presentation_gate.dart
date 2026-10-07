// Sessão 2026-05-25 (exec6.16) — Autoridade única de apresentação de oferta.
// Arquitectura HÍBRIDA Stuart/Uber, sem CallKit/CallStyle.
//
// REGRA por estado (2 estados, sem lockedOrDead):
//   1. FOREGROUND (AppLifecycleState.resumed):
//        → tela laranja in-app (driver_home_screen._handleNewOrders)
//        → gate liberta IMEDIATAMENTE (UI gerida pela tela)
//   2. BACKGROUND (qualquer outro lifecycle):
//        → FlutterOverlayWindow.showOverlay → SOBREPOSIÇÃO por cima de outras apps
//        → sem CallKit, sem CallStyle, sem Material full-screen dialog
//
// DEDUP por orderId: _activeGateOrderId + _handledOrderIds (FIFO 50).
//
// MAIN ISOLATE HEARTBEAT (CAMADA 3 support): main isolate escreve
// 'bora_main_alive_ts' a cada 5s; FGS task isolate lê para saber se main
// está vivo (se stale > 5s → fullScreenIntent local notif acorda Activity).
//
// FG HEARTBEAT (legacy mas mantido p/ bg handler skip): 'bora_fg_heartbeat'
// timestamp escrito enquanto resumed (cada 30s); 0 quando paused/detached.

import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'notification_service.dart';

/// Estados que o gate distingue. App em FG resumed vs anything-else.
enum _AppState { foreground, background }

class OfferPresentationGate {
  OfferPresentationGate._();

  /// Lifecycle conhecido (actualizado por WidgetsBindingObserver no main).
  static AppLifecycleState _lifecycle = AppLifecycleState.resumed;

  /// Dedup global. Libertado em markActionCompleted ou expirado.
  static String? _activeGateOrderId;

  /// orderIds que JÁ FORAM tratados (rejeitados, aceites, expirados, ou
  /// oferta revogada pelo backend). Bloqueia re-trigger do mesmo orderId
  /// em qualquer UI/path. Limite 50 entries (FIFO).
  static final List<String> _handledOrderIds = <String>[];
  static const int _handledMaxSize = 50;

  // [07/10/2026 · oferta repetida] Antes o "já tratado" era só pelo orderId e
  // nunca expirava: quando o mesmo pedido voltava a ser oferecido ao mesmo
  // estafeta (só ele ligado, o despacho repete a cada minuto), a app calava-se
  // e só tocava o aviso simples do sistema, uma vez. Caso real: McDonald's
  // 947f7206 de 06/10, 20 ofertas ao Danilo, ninguém aceitou, cliente perdida.
  // Agora cada oferta é identificada pelo seu prazo (driver_offer_expires_at):
  // prazo novo = oferta nova = volta a tocar em loop, como na Uber/Glovo.
  /// Prazo (ms desde epoch, em texto) da oferta de cada orderId já tratado.
  static final Map<String, String> _handledOfferExp = <String, String>{};
  /// Quando cada orderId foi marcado como tratado (ms desde epoch).
  static final Map<String, int> _handledAt = <String, int>{};
  /// Prazo da oferta que o gate apresentou por último para cada orderId.
  static final Map<String, String> _presentedOfferExp = <String, String>{};

  /// Normaliza um prazo de oferta (ISO 8601 do servidor) para ms em texto, para
  /// comparar igual venha do FCM, do realtime ou do serviço em segundo plano.
  static String? normExp(Object? v) {
    if (v == null) return null;
    final s = v.toString().trim();
    if (s.isEmpty || s == 'null') return null;
    final d = DateTime.tryParse(s);
    return d?.millisecondsSinceEpoch.toString();
  }

  /// Decide se uma oferta que chega para um pedido já tratado é NOVA.
  /// `handledExp`/`handledAtMs` descrevem a oferta tratada; `exp` a que chega.
  static bool isNewOffer({
    required String? exp,
    required String? handledExp,
    required int handledAtMs,
  }) {
    if (exp == null) {
      // Sem prazo não dá para distinguir: só bloqueia logo a seguir ao fecho.
      return DateTime.now().millisecondsSinceEpoch - handledAtMs > 90000;
    }
    if (handledExp != null) return exp != handledExp;
    // Tratado sem prazo conhecido: nova se acaba bem depois do fecho.
    return (int.tryParse(exp) ?? 0) > handledAtMs + 20000;
  }

  static void _addHandled(String orderId, {String? exp}) {
    if (orderId.isEmpty) return;
    _handledOrderIds.remove(orderId);
    _handledOrderIds.add(orderId);
    _handledAt[orderId] = DateTime.now().millisecondsSinceEpoch;
    final e = exp ?? _presentedOfferExp[orderId];
    if (e != null) {
      _handledOfferExp[orderId] = e;
    } else {
      _handledOfferExp.remove(orderId);
    }
    while (_handledOrderIds.length > _handledMaxSize) {
      final old = _handledOrderIds.removeAt(0);
      _handledOfferExp.remove(old);
      _handledAt.remove(old);
      _presentedOfferExp.remove(old);
    }
  }

  /// Para casos onde re-oferta legítima do dispatch precisa de re-disparar
  /// (ex: cycle reset). Limpa o orderId da lista handled.
  static void clearHandled(String orderId) {
    _handledOrderIds.remove(orderId);
    _handledOfferExp.remove(orderId);
    _handledAt.remove(orderId);
  }

  // ── HEARTBEATS ──────────────────────────────────────────────────────────

  // FG heartbeat: bg handler FCM lê para saber se app está em FG (skip).
  static Timer? _fgHeartbeatTimer;

  // Main isolate alive heartbeat: FGS task isolate lê para saber se main
  // está vivo (se stale → fullScreenIntent acorda Activity). Roda SEMPRE
  // (resumed OU paused) enquanto main isolate vivo.
  static Timer? _mainAliveTimer;

  static void _startFgHeartbeat() {
    _fgHeartbeatTimer?.cancel();
    SharedPreferences.getInstance().then((prefs) {
      prefs.setInt('bora_fg_heartbeat', DateTime.now().millisecondsSinceEpoch);
    });
    _fgHeartbeatTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      SharedPreferences.getInstance().then((prefs) {
        prefs.setInt(
            'bora_fg_heartbeat', DateTime.now().millisecondsSinceEpoch);
      });
    });
    debugPrint('[GATE] FG heartbeat started');
  }

  static void _stopFgHeartbeat() {
    _fgHeartbeatTimer?.cancel();
    _fgHeartbeatTimer = null;
    SharedPreferences.getInstance().then((prefs) {
      prefs.setInt('bora_fg_heartbeat', 0);
    });
    debugPrint('[GATE] FG heartbeat stopped (SP=0)');
  }

  /// CAMADA 3 support — main isolate alive ping. Roda independente do
  /// lifecycle (a 5s) enquanto main isolate vivo. FGS task lê SP age para
  /// saber se precisa de fullScreenIntent acordar Activity.
  static void _startMainAliveHeartbeat() {
    _mainAliveTimer?.cancel();
    SharedPreferences.getInstance().then((prefs) {
      prefs.setInt(
          'bora_main_alive_ts', DateTime.now().millisecondsSinceEpoch);
    });
    _mainAliveTimer = Timer.periodic(const Duration(seconds: 3), (_) {
      SharedPreferences.getInstance().then((prefs) {
        prefs.setInt(
            'bora_main_alive_ts', DateTime.now().millisecondsSinceEpoch);
      });
    });
    debugPrint('[GATE] main-alive heartbeat started (3s)');
  }

  /// Bootstrap: deve ser chamado no main() para iniciar o main-alive
  /// heartbeat antes do utilizador navegar.
  static void bootstrapMainAlive() {
    _startMainAliveHeartbeat();
  }

  /// Pendurado pelo `_MyAppState.didChangeAppLifecycleState`.
  static void updateLifecycle(AppLifecycleState s) {
    _lifecycle = s;
    debugPrint('[GATE] lifecycle=$s');
    if (s == AppLifecycleState.resumed) {
      _startFgHeartbeat();
    } else if (s == AppLifecycleState.paused ||
        s == AppLifecycleState.detached) {
      _stopFgHeartbeat();
    }
    // inactive → no-op: interrupção breve (alerta, chamada); timer continua.
  }

  /// Liberta o dedup quando a UI da oferta termina (accept/reject/expired).
  /// Chamado por: overlay listener no notification_service, RPC helpers,
  /// cancelDriverOfferNotification, DriverFullScreenOfferDialog (legacy).
  static void markActionCompleted(String orderId, {String? offerExpiresAt}) {
    if (_activeGateOrderId == orderId) {
      debugPrint('[GATE] release order=$orderId');
      _activeGateOrderId = null;
    }
    _addHandled(orderId, exp: normExp(offerExpiresAt));
    debugPrint('[GATE] handled+=$orderId exp=${_handledOfferExp[orderId]} '
        '(size=${_handledOrderIds.length})');
    _persistHandledToSp(orderId);
  }

  /// [07/10] Lido pelo handler FCM em segundo plano (outro isolate): diz se a
  /// oferta que chegou é nova face à que ficou tratada para este pedido.
  /// Formato de cada entrada em `gate_handled_offer_exp`: "orderId|prazo|tratadoEm".
  static bool isNewOfferFromPrefs(
      SharedPreferences prefs, String orderId, String? offerExpiresAt) {
    final exp = normExp(offerExpiresAt);
    final list = prefs.getStringList('gate_handled_offer_exp') ?? const <String>[];
    for (final e in list) {
      final p = e.split('|');
      if (p.length == 3 && p[0] == orderId) {
        return isNewOffer(
          exp: exp,
          handledExp: p[1].isEmpty ? null : p[1],
          handledAtMs: int.tryParse(p[2]) ?? 0,
        );
      }
    }
    // Tratado por uma versão antiga da app (sem prazo): regra do "sem prazo".
    return isNewOffer(exp: exp, handledExp: null, handledAtMs: 0);
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
      final exps =
          prefs.getStringList('gate_handled_offer_exp') ?? <String>[];
      exps.removeWhere((e) => e.startsWith('$orderId|'));
      exps.add('$orderId|${_handledOfferExp[orderId] ?? ''}|'
          '${_handledAt[orderId] ?? DateTime.now().millisecondsSinceEpoch}');
      while (exps.length > _handledMaxSize) {
        exps.removeAt(0);
      }
      await prefs.setStringList('gate_handled_offer_exp', exps);
      // Limpa flag som dedup in-app (próximo pedido pode tocar).
      if (prefs.getString('gate_fullscreen_orderid') == orderId) {
        await prefs.remove('gate_fullscreen_orderid');
      }
      // Limpa flag overlay activa (bg handler deixa de skipar).
      if (prefs.getString('bora_overlay_active_orderid') == orderId) {
        await prefs.remove('bora_overlay_active_orderid');
      }
    } catch (_) {}
  }

  /// Entrada única. TODOS os triggers (FCM bg, realtime UPDATE, realtime
  /// broadcast, FGS bridge, rehydrate) passam por aqui.
  static Future<void> present({
    required String orderId,
    required String vendorName,
    required String total,
    required String distanceKm,
    required String driverEarnings,
    String dropoffAddress = '',
    bool fromBgIsolate = false,
    String? offerExpiresAt,
  }) async {
    if (orderId.isEmpty) return;
    final exp = normExp(offerExpiresAt);

    // [07/10] Oferta já vencida (evento atrasado): não toca.
    if (exp != null &&
        (int.tryParse(exp) ?? 0) < DateTime.now().millisecondsSinceEpoch - 2000) {
      debugPrint('[GATE] VENCIDA — order=$orderId exp=$exp, skip');
      return;
    }

    // Dedup forte por orderId.
    if (_activeGateOrderId == orderId) {
      debugPrint('[GATE] DEDUP — order=$orderId já tem UI activa');
      return;
    }

    if (_handledOrderIds.contains(orderId)) {
      if (isNewOffer(
        exp: exp,
        handledExp: _handledOfferExp[orderId],
        handledAtMs: _handledAt[orderId] ?? 0,
      )) {
        debugPrint('[GATE] OFERTA NOVA do mesmo pedido order=$orderId '
            'exp=$exp (antes ${_handledOfferExp[orderId]}) → volta a tocar');
        clearHandled(orderId);
      } else {
        debugPrint('[GATE] HANDLED — order=$orderId já foi tratado, skip');
        return;
      }
    }
    if (exp != null) _presentedOfferExp[orderId] = exp;

    final state = _detectState(fromBgIsolate: fromBgIsolate);
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
        case _AppState.background:
          await _showOverlay(
            orderId: orderId,
            vendorName: vendorName,
            total: total,
            distanceKm: distanceKm,
            driverEarnings: driverEarnings,
            dropoffAddress: dropoffAddress,
          );
          break;
      }
    } catch (e) {
      debugPrint('[GATE] present error: $e — libertando dedup');
      _activeGateOrderId = null;
    }
  }

  /// 2 estados — simplificado:
  ///   • fromBgIsolate=true → assume background (bg isolate não tem
  ///     WidgetsBinding; assumir BG é seguro porque MAIN trata FG via realtime)
  ///   • FG resumed → foreground
  ///   • qualquer outro → background
  static _AppState _detectState({required bool fromBgIsolate}) {
    if (fromBgIsolate) return _AppState.background;
    if (_lifecycle == AppLifecycleState.resumed) return _AppState.foreground;
    return _AppState.background;
  }

  // ── Implementações por estado ─────────────────────────────────────────────

  /// FG: cartão laranja in-app aparece via driver_home_screen._handleNewOrders
  /// quando OrderStore detecta oferta. Aqui só limpamos competidores e
  /// libertamos o gate (a UI é gerida pela tela).
  static Future<void> _showInAppOrange({
    required String orderId,
    required String vendorName,
    required String total,
    required String distanceKm,
    required String driverEarnings,
    required String dropoffAddress,
  }) async {
    debugPrint('[GATE] FG → in-app orange para order=$orderId');
    // Cancelar notif local que esteja a competir.
    await cancelDriverOfferNotification(orderId);
    // Persist flag para bg handler saber FG tratou — evita CallStyle/overlay
    // duplicado se FCM data-only entrega TANTO ao realtime (FG) COMO ao
    // bg handler em paralelo.
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('gate_fg_handled_orderId', orderId);
      await prefs.setInt(
          'gate_fg_handled_ts', DateTime.now().millisecondsSinceEpoch);
    } catch (_) {}
    // Liberta gate — driver_home_screen gere a sua própria UI/dedup.
    markActionCompleted(orderId);
  }

  /// BG: SOBREPOSIÇÃO via FlutterOverlayWindow (SYSTEM_ALERT_WINDOW).
  /// Aparece POR CIMA de outras apps — padrão Uber/Glovo.
  /// Sem CallKit, sem CallStyle, sem Material full-screen dialog.
  static Future<void> _showOverlay({
    required String orderId,
    required String vendorName,
    required String total,
    required String distanceKm,
    required String driverEarnings,
    required String dropoffAddress,
  }) async {
    debugPrint('[GATE] BG → SOBREPOSIÇÃO para order=$orderId');
    // Marca em SP para bg handler FCM saber que overlay já está activa.
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('bora_overlay_active_orderid', orderId);
      await prefs.setString('gate_fullscreen_orderid', orderId);
    } catch (_) {}
    await NotificationService.instance.showDriverOfferOverlay(
      orderId: orderId,
      vendorName: vendorName,
      total: total,
      distanceKm: distanceKm,
      driverEarnings: driverEarnings,
    );
  }
}
