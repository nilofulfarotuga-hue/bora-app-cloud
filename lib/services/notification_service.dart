import 'dart:async';
import 'dart:convert';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
// Prefix `fln` para evitar colisão com flutter_foreground_task (também exporta
// NotificationVisibility). Usado só para AndroidNotificationDetails e enums.
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart'
    as fln;
// Alias para evitar colisão de `NotificationVisibility` com flutter_local_notifications.
import 'package:flutter_overlay_window/flutter_overlay_window.dart' as fow;
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/chat_message.dart';
import '../models/order_model.dart';
import '../screens/chat_screen.dart';
import '../screens/notifications_screen.dart';
import 'offer_presentation_gate.dart';
import 'push_token_service.dart';
import 'sound_service.dart';

/// Background message handler — must be a top-level function (not a closure).
///
/// Sessão 2026-05-22 (fullScreenIntent definitivo) — cadeia tripla de
/// redundância para garantir que o estafeta vê o pedido em qualquer estado:
///
///   1. Local notification com `fullScreenIntent: true` no canal
///      bora_orders_urgent_v2 (IMPORTANCE_MAX). Em Android <14, abre a
///      MainActivity (que tem showWhenLocked + turnScreenOn) por cima de
///      qualquer outra app/lockscreen. Em Android 14+ requer perm explícita
///      USE_FULL_SCREEN_INTENT — sem ela, downgraded para heads-up.
///   2. Ponte FCM→FGS→main isolate via `sendDataToTask` — quando o foreground
///      service está vivo, o main isolate pode chamar `showDriverOfferOverlay`
///      (SYSTEM_ALERT_WINDOW) por cima de outras apps com ecrã desbloqueado.
///   3. Heads-up automático pelo FCM SDK (bloco `notification` da msg) —
///      último fallback visual quando 1 e 2 falham.
///
/// Importa criar o canal aqui também: o BG isolate NÃO partilha estado com o
/// main, e Android exige que o canal exista no momento do show().
@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  try {
    await Firebase.initializeApp();
  } catch (_) {
    // already initialized
  }
  final data = message.data;
  debugPrint('[FCM BG] received: type=${data['type']} '
      'orderId=${data['orderId']} '
      'notif=${message.notification?.title}');

  // ── Chat: nova mensagem em background (exec6.23) ───────────────────────
  // Antes: caía no default sound-only sem notificação visual → user perdia
  // mensagens. Agora rich notif c/ BigText + Responder + canal v3 + som.
  if (data['type'] == 'chat' || data['type'] == 'chat_message') {
    final orderId = data['order_id']?.toString() ?? data['orderId']?.toString() ?? '';
    final messageId = data['message_id']?.toString() ?? '';
    final senderType = data['sender_type']?.toString() ?? '';
    final senderName = data['sender_name']?.toString() ?? data['senderName']?.toString() ?? '';
    final bodyMsg = data['body']?.toString() ?? data['message']?.toString() ?? 'Nova mensagem';
    final title = data['title']?.toString() ?? '💬 Nova mensagem';
    try {
      final plugin = FlutterLocalNotificationsPlugin();
      final androidImpl = plugin.resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>();
      await androidImpl?.createNotificationChannel(
        const AndroidNotificationChannel(
          'bora_orders_urgent_v3',
          'Bora — Novos pedidos',
          description: 'Som contínuo + vibração para novos pedidos e mensagens.',
          importance: Importance.max,
          playSound: true,
          sound: RawResourceAndroidNotificationSound('bora_alert'),
          enableVibration: true,
          showBadge: true,
        ),
      );
      final androidDetails = AndroidNotificationDetails(
        'bora_orders_urgent_v3',
        'Bora — Novos pedidos',
        channelDescription: 'Mensagem nova — tap para responder.',
        importance: Importance.max,
        priority: Priority.max,
        playSound: true,
        sound: const RawResourceAndroidNotificationSound('bora_alert'),
        enableVibration: true,
        category: AndroidNotificationCategory.message,
        fullScreenIntent: false,
        ongoing: false,
        autoCancel: true,
        onlyAlertOnce: false,
        ticker: 'Mensagem de ${senderName.isNotEmpty ? senderName : "alguém"}',
        visibility: fln.NotificationVisibility.public,
        styleInformation: BigTextStyleInformation(
          bodyMsg,
          contentTitle: senderName.isNotEmpty ? '💬 $senderName' : title,
          summaryText: 'Bora chat',
        ),
      );
      await plugin.show(
        messageId.isNotEmpty ? messageId.hashCode : orderId.hashCode,
        senderName.isNotEmpty ? '💬 $senderName' : title,
        bodyMsg,
        NotificationDetails(android: androidDetails),
        payload: jsonEncode({
          'orderId': orderId,
          'type': 'chat',
          'sender_type': senderType,
          'message_id': messageId,
        }),
      );
      debugPrint('[FCM BG] chat rich notif posted msg=$messageId order=$orderId');
    } catch (e) {
      debugPrint('[FCM BG] chat notif error: $e');
    }
    return;
  }

  // ── Parceiro: novo pedido em background ─────────────────────────────────
  if (data['type'] == 'new_order') {
    final orderId = data['orderId']?.toString() ?? '';
    final items = data['items']?.toString() ?? 'Novo pedido';
    final total = data['total']?.toString() ?? '0.00';
    final customer = data['customerName']?.toString() ?? '';
    try {
      final plugin = FlutterLocalNotificationsPlugin();
      final androidImpl = plugin.resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>();
      // Exec6.22 (2026-05-26) — partner alinhado com canal v3 unificado
      // (mesmo do driver). Notif PERSISTENTE c/ FLAG_INSISTENT (som loop) +
      // BigText (items + cliente + total) + actions Aceitar/Rejeitar via
      // RPCs partner_accept_order / partner_reject_order. Padrão Uber.
      await androidImpl?.createNotificationChannel(
        const AndroidNotificationChannel(
          'bora_orders_urgent_v3',
          'Bora — Novos pedidos',
          description: 'Som contínuo + vibração para novos pedidos urgentes.',
          importance: Importance.max,
          playSound: true,
          sound: RawResourceAndroidNotificationSound('bora_alert'),
          enableVibration: true,
          showBadge: true,
        ),
      );
      final androidDetails = AndroidNotificationDetails(
        'bora_orders_urgent_v3',
        'Bora — Novos pedidos',
        channelDescription: 'Pedido novo — tap Aceitar ou Rejeitar.',
        importance: Importance.max,
        priority: Priority.max,
        playSound: true,
        sound: const RawResourceAndroidNotificationSound('bora_alert'),
        enableVibration: true,
        category: AndroidNotificationCategory.call,
        fullScreenIntent: true,
        ongoing: true,
        autoCancel: false,
        onlyAlertOnce: false,
        ticker: '🔔 Novo pedido — €$total',
        visibility: fln.NotificationVisibility.public,
        colorized: true,
        color: const Color(0xFF2E7D32),
        styleInformation: BigTextStyleInformation(
          '$items${customer.isNotEmpty ? "\n👤 $customer" : ""}\n💰 Total: €$total',
          contentTitle: '🔔 Novo pedido!',
          summaryText: 'Bora — Loja',
        ),
        additionalFlags: Int32List.fromList(<int>[4]),
        actions: const <AndroidNotificationAction>[
          AndroidNotificationAction('accept_partner_order', '✅ Aceitar',
              showsUserInterface: false, cancelNotification: true),
          AndroidNotificationAction('reject_partner_order', '❌ Rejeitar',
              showsUserInterface: false, cancelNotification: true),
        ],
      );
      await plugin.show(
        orderId.isNotEmpty ? orderId.hashCode : 9999,
        '🔔 Novo pedido — €$total',
        '$items${customer.isNotEmpty ? " • $customer" : ""}',
        NotificationDetails(android: androidDetails),
        payload: jsonEncode({'orderId': orderId, 'type': 'new_order'}),
      );
      debugPrint('[FCM BG] partner rich notif posted order=$orderId');
    } catch (e) {
      debugPrint('[FCM BG] partner notif error: $e');
    }
    return;
  }

  if (data['type'] != 'new_order_offer') return;
  debugPrint('[BORA-OFFER] FCM BG handler RECEIVED new_order_offer payload=${jsonEncode(data)}');

  final orderId = data['orderId']?.toString() ?? '';
  final vendorName = data['vendorName']?.toString() ?? 'Novo pedido';
  final total = data['total']?.toString() ?? '0.00';
  final distanceKm = data['distanceKm']?.toString() ?? '0';
  final driverEarnings = data['driverEarnings']?.toString() ?? '0.00';
  final dropoffAddress = data['dropoffAddress']?.toString() ?? '';

  // ── Exec6 GATE (2026-05-25) ─────────────────────────────────────────────
  // ANTIGO: bg handler disparava 3 UIs em paralelo (local notif fullScreenIntent
  // + CallKit + shareData overlay) → empilhamento, som duplicado, "Aceitar não
  // responde". REMOVIDO. Agora um SÓ gate central decide qual UI mostrar.
  //
  // 1) Persistir pending_offer (rehydrate consome quando app sobe ao FG).
  // 2) Chamar gate.present(fromBgIsolate=true) — gate decide CallKit
  //    (locked/dead, caminho seguro a partir do BG isolate).
  // 3) FGS bridge mantém-se como backup para garantir que main isolate
  //    é avisado quando estiver vivo.
  try {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('pending_offer', jsonEncode({
      'type': 'new_order_offer',
      'orderId': orderId,
      'vendorName': vendorName,
      'total': total,
      'distanceKm': distanceKm,
      'driverEarnings': driverEarnings,
      'dropoffAddress': dropoffAddress,
      'ts': DateTime.now().millisecondsSinceEpoch,
    }));
    debugPrint('[BORA-OFFER] pending_offer SAVED order=$orderId');
  } catch (e) {
    debugPrint('[FCM BG] SharedPrefs error: $e');
  }

  // EXEC6 FIX (07:01): se FG handler já tratou este orderId nos últimos 8s,
  // SKIP CallKit (Samsung entrega data-only a ambos os caminhos em FG —
  // realtime broadcast + bg handler — sem isto, CallKit competia com laranja).
  // EXEC6.5: também verificar lista persistida de handled orderIds (cobre
  // BG-unlocked rejeitado/aceite — sem isto CallKit tocava após pop da bonita).
  try {
    final prefs = await SharedPreferences.getInstance();
    final fgOrder = prefs.getString('gate_fg_handled_orderId');
    final fgTs = prefs.getInt('gate_fg_handled_ts') ?? 0;
    if (fgOrder == orderId) {
      final age = DateTime.now().millisecondsSinceEpoch - fgTs;
      if (age < 8000) {
        debugPrint(
            '[FCM BG] FG-handled SKIP order=$orderId age=${age}ms');
        return;
      }
    }
    final handledList =
        prefs.getStringList('gate_handled_orderids') ?? const <String>[];
    if (handledList.contains(orderId)) {
      debugPrint('[FCM BG] HANDLED SKIP (SP persistent list) order=$orderId');
      return;
    }
  } catch (_) {}

  // Exec6.11 (2026-05-25) — FG heartbeat check.
  // OfferPresentationGate escreve 'bora_fg_heartbeat' a cada 30s enquanto
  // app está em foreground resumed; escreve 0 ao fazer pause.
  // Se age < 45s → app estava activa em FG → skip (main isolate trata via
  // realtime subscription → cartão laranja). Sem CallKit duplicado.
  // Se age ≥ 45s → app morta ou bloqueada → continuar para CallKit.
  try {
    final prefs = await SharedPreferences.getInstance();
    final int hb = prefs.getInt('bora_fg_heartbeat') ?? 0;
    final int hbAge = DateTime.now().millisecondsSinceEpoch - hb;
    debugPrint('[BORA-OFFER] FCM BG heartbeat_age=${hbAge}ms');
    if (hbAge < 45000) {
      debugPrint('[BORA-OFFER] FG activo (age=${hbAge}ms) → skip CallKit, main isolate trata');
      return;
    }
  } catch (e) {
    debugPrint('[BORA-OFFER] FCM BG heartbeat read error: $e — continua para CallKit');
  }

  // Exec6.20 (2026-05-26) S4 — overlay v0.4.5 não renderiza visualmente (bug
  // do plugin; shareData/listener silent). Pivot: a notificação É o cartão.
  // Rich notif com BigText + actions Aceitar/Rejeitar. User actua direct do
  // banner sem precisar de overlay. fullScreenIntent acorda ecrã também.
  try {
    final plugin = FlutterLocalNotificationsPlugin();
    final androidImpl = plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    await androidImpl?.createNotificationChannel(
      const AndroidNotificationChannel(
        'bora_orders_urgent_v3',
        'Bora — Novos pedidos',
        description: 'Som contínuo + vibração para novos pedidos urgentes.',
        importance: Importance.max,
        playSound: true,
        sound: RawResourceAndroidNotificationSound('bora_alert'),
        enableVibration: true,
        showBadge: true,
      ),
    );
    final androidDetails = AndroidNotificationDetails(
      'bora_orders_urgent_v3',
      'Bora — Novos pedidos',
      channelDescription: 'Pedido novo — tap Aceitar ou Rejeitar.',
      importance: Importance.max,
      priority: Priority.max,
      playSound: true,
      sound: const RawResourceAndroidNotificationSound('bora_alert'),
      enableVibration: true,
      category: AndroidNotificationCategory.call,
      fullScreenIntent: true,
      ongoing: true,
      autoCancel: false,
      // exec6.21 — Anti-swipe + sempre expandido + alarm-style
      onlyAlertOnce: false,
      timeoutAfter: null,
      ticker: '🛵 Novo pedido — €$driverEarnings',
      visibility: fln.NotificationVisibility.public,
      colorized: true,
      color: const Color(0xFFE65100),
      indeterminate: false,
      // FLAG_INSISTENT (Android Notification flag 0x4) → som toca EM LOOP
      // até user dismisses ou age na notif. Padrão Glovo/Uber.
      additionalFlags: Int32List.fromList(<int>[4]),
      styleInformation: BigTextStyleInformation(
        '$vendorName\n💰 €$total  •  📍 ${distanceKm}km\n✅ Ganho: €$driverEarnings',
        contentTitle: '🛵 Novo pedido!',
        summaryText: 'Bora',
      ),
      actions: const <AndroidNotificationAction>[
        // showsUserInterface: false → handler BG corre direto sem abrir app
        AndroidNotificationAction('accept_order', '✅ Aceitar',
            showsUserInterface: false, cancelNotification: true),
        AndroidNotificationAction('reject_order', '❌ Rejeitar',
            showsUserInterface: false, cancelNotification: true),
      ],
    );
    await plugin.show(
      orderId.hashCode,
      '🛵 Novo pedido — €$driverEarnings',
      '$vendorName • €$total • ${distanceKm}km',
      NotificationDetails(android: androidDetails),
      payload: jsonEncode({'orderId': orderId, 'type': 'new_order_offer'}),
    );
    debugPrint('[BORA-OFFER] rich offer notif posted order=$orderId');
  } catch (e) {
    debugPrint('[BORA-OFFER] rich offer notif error: $e');
  }

  // Exec6.18b — RESTRIÇÃO: shareData NÃO funciona no bg FCM isolate
  // (MethodChannel x-slayer/overlay não está registado → await trava).
  // Conclusão: este caminho está REMOVIDO daqui. Único caminho fiável é
  // via main isolate (rehydrate loop OU realtime broadcast OU FGS task
  // que envia sendDataToMain). Bg handler só persiste pending_offer.

  // 800ms delay + dedup overlay activa (caso main isolate já tenha tratado).
  await Future<void>.delayed(const Duration(milliseconds: 800));
  try {
    final prefs = await SharedPreferences.getInstance();
    await prefs.reload();
    if (prefs.getString('bora_overlay_active_orderid') == orderId) {
      debugPrint('[FCM BG] SKIP — overlay window activa para order=$orderId (main isolate tratou)');
      return;
    }
    final handledList =
        prefs.getStringList('gate_handled_orderids') ?? const <String>[];
    if (handledList.contains(orderId)) {
      debugPrint('[FCM BG] post-delay SKIP — main isolate já tratou order=$orderId');
      return;
    }
  } catch (_) {}

  // FGS bridge — forward para o task isolate que reencaminha ao main isolate
  // (via sendDataToMain → _onForegroundTaskData → gate.present → overlay).
  // Se main isolate morto, o FGS task detecta via bora_main_alive_ts e
  // dispara postWakeActivityNotification (fullScreenIntent acorda Activity).
  debugPrint('[FGS_BRIDGE] BG handler reached FGS forward block');
  try {
    final isRunning = await FlutterForegroundTask.isRunningService;
    debugPrint('[FGS_BRIDGE] isRunningService=$isRunning');
    if (isRunning) {
      debugPrint('[FGS_BRIDGE] about to call sendDataToTask order=$orderId');
      FlutterForegroundTask.sendDataToTask(<String, String>{
        'type': 'new_order_offer',
        'orderId': orderId,
        'vendorName': vendorName,
        'total': total,
        'distanceKm': distanceKm,
        'driverEarnings': driverEarnings,
        'dropoffAddress': dropoffAddress,
      });
      debugPrint('[FGS_BRIDGE] sendDataToTask returned (sync) order=$orderId');
    } else {
      debugPrint('[FGS_BRIDGE] SKIP — FGS service not running');
    }
  } catch (e, st) {
    debugPrint('[FGS_BRIDGE] FGS bridge EXCEPTION: $e');
    debugPrint('[FGS_BRIDGE] stack: ${st.toString().split("\n").take(5).join(" | ")}');
  }
}

/// Tap na notificação local enquanto app em foreground ou background.
/// Traz a app para o primeiro plano — driver home screen já mostra o card
/// de aceitar/rejeitar via Realtime.
void _onLocalNotifTap(NotificationResponse response) {
  // ignore: avoid_print
  print('[NOTIF TAP] FG actionId=${response.actionId} payload=${response.payload} type=${response.notificationResponseType}');
  // Se foi action button, delegar ao handler de BG (mesma lógica RPC).
  if (response.actionId == 'accept_order' || response.actionId == 'reject_order') {
    onBackgroundNotificationAction(response);
    return;
  }
  FlutterForegroundTask.launchApp('/');
}

/// Acção nos botões da notificação quando app em background/terminada.
/// Executa aceitar/rejeitar sem abrir a app (raw HTTP — sem Supabase client).
@pragma('vm:entry-point')
Future<void> onBackgroundNotificationAction(NotificationResponse response) async {
  // ignore: avoid_print
  print('[NOTIF ACTION] ENTRY actionId=${response.actionId} payload=${response.payload} input=${response.input} notificationResponseType=${response.notificationResponseType}');
  final actionId = response.actionId;
  final payload = response.payload;
  if (actionId == null || payload == null) {
    // ignore: avoid_print
    print('[NOTIF ACTION] SKIP — actionId or payload null');
    return;
  }
  try {
    final data = jsonDecode(payload) as Map<String, dynamic>;
    final orderId = data['orderId']?.toString() ?? '';
    if (orderId.isEmpty) return;

    final prefs = await SharedPreferences.getInstance();
    final accessToken = prefs.getString('bora_access_token') ?? '';
    if (accessToken.isEmpty) {
      debugPrint('[NOTIF ACTION] bora_access_token vazio — ação ignorada');
      return;
    }

    var supabaseUrl = const String.fromEnvironment('SUPABASE_URL');
    var anonKey = const String.fromEnvironment('SUPABASE_ANON_KEY');
    if (supabaseUrl.isEmpty) {
      supabaseUrl = prefs.getString('bora_supabase_url') ?? '';
      anonKey = prefs.getString('bora_supabase_anon_key') ?? '';
    }
    if (supabaseUrl.isEmpty) {
      debugPrint('[NOTIF ACTION] supabaseUrl vazio — ação ignorada');
      return;
    }

    final headers = <String, String>{
      'apikey': anonKey,
      'Authorization': 'Bearer $accessToken',
      'Content-Type': 'application/json',
      'Prefer': 'return=minimal',
    };

    if (actionId == 'accept_order') {
      // Sessão 2026-05-24 (exec2 FIX D) — usar RPC atómica em vez de PATCH
      // raw. A RPC valida `current_driver_offer_id = auth.uid()` ATÓMICAMENTE
      // e devolve {ok:false, error:'offer_expired_or_taken'} se já tiver
      // expirado/sido tomada — em vez de PATCH bloqueado em silêncio pela RLS.
      final res = await http
          .post(
            Uri.parse('$supabaseUrl/rest/v1/rpc/driver_accept_offer'),
            headers: {
              ...headers,
              'Prefer': 'return=representation',
            },
            body: jsonEncode({'p_order_id': orderId}),
          )
          .timeout(const Duration(seconds: 5));
      // Parse defensivo: a RPC devolve jsonb. Se 4xx/5xx, status já reflecte.
      String? rpcError;
      try {
        final body = res.body;
        if (body.isNotEmpty) {
          final parsed = jsonDecode(body);
          if (parsed is Map && parsed['ok'] == false) {
            rpcError = parsed['error']?.toString();
          }
        }
      } catch (_) {}
      await prefs.remove('pending_offer');
      if (rpcError == 'offer_expired_or_taken') {
        debugPrint(
            '[NOTIF ACTION] accept_order EXPIRED order=$orderId — closing notif');
        // Limpa notif e overlay; main isolate (se vivo) verá via realtime
        // que current_driver_offer_id mudou. Não há snackbar no bg isolate.
        try {
          await FlutterLocalNotificationsPlugin().cancel(orderId.hashCode);
        } catch (_) {}
      } else if (res.statusCode >= 400) {
        debugPrint(
            '[NOTIF ACTION] accept_order HTTP ${res.statusCode} order=$orderId body=${res.body}');
      } else {
        debugPrint('[NOTIF ACTION] accept_order OK order=$orderId');
      }
    } else if (actionId == 'reject_order') {
      await http
          .post(
            Uri.parse('$supabaseUrl/rest/v1/rpc/driver_reject_offer'),
            headers: headers,
            body: jsonEncode({'p_order_id': orderId}),
          )
          .timeout(const Duration(seconds: 5));
      await prefs.remove('pending_offer');
      debugPrint('[NOTIF ACTION] reject_order OK order=$orderId');
    } else if (actionId == 'accept_partner_order') {
      // Exec6.22 — RPC partner_accept_order (SECURITY DEFINER, atomic).
      // Valida status='created' antes de transitar p/ 'preparing'.
      final res = await http
          .post(
            Uri.parse('$supabaseUrl/rest/v1/rpc/partner_accept_order'),
            headers: {...headers, 'Prefer': 'return=representation'},
            body: jsonEncode({'p_order_id': orderId}),
          )
          .timeout(const Duration(seconds: 5));
      debugPrint('[NOTIF ACTION] partner_accept_order ${res.statusCode} body=${res.body}');
      try { await FlutterLocalNotificationsPlugin().cancel(orderId.hashCode); } catch (_) {}
    } else if (actionId == 'reject_partner_order') {
      final res = await http
          .post(
            Uri.parse('$supabaseUrl/rest/v1/rpc/partner_reject_order'),
            headers: {...headers, 'Prefer': 'return=representation'},
            body: jsonEncode({'p_order_id': orderId}),
          )
          .timeout(const Duration(seconds: 5));
      debugPrint('[NOTIF ACTION] partner_reject_order ${res.statusCode} body=${res.body}');
      try { await FlutterLocalNotificationsPlugin().cancel(orderId.hashCode); } catch (_) {}
    }
  } catch (e) {
    debugPrint('[NOTIF ACTION] error: $e');
  }
}

/// Cancela a notificação persistente de uma oferta quando:
///   • o estafeta aceitou via UI
///   • o backend revogou (timeout / outro driver aceitou / cliente cancelou)
///   • realtime detectou `current_driver_offer_id != myDriverId`
///
/// Idempotente — chamar duas vezes não dá erro. Usado por OrderStore no
/// realtime handler (sessão 2026-05-20).
Future<void> cancelDriverOfferNotification(String orderId) async {
  if (orderId.isEmpty) return;
  try {
    await FlutterLocalNotificationsPlugin().cancel(orderId.hashCode);
    debugPrint('[NotificationService] cancelled offer notif order=$orderId');
  } catch (e) {
    debugPrint('[NotificationService] cancel error: $e');
  }
  // Limpar bridge SharedPreferences para o FGS não re-enviar oferta cancelada.
  try {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('pending_offer');
  } catch (_) {}
  // Fecha o overlay system_alert_window (sessão 2026-05-21).
  try {
    final active = await fow.FlutterOverlayWindow.isActive();
    if (active) await fow.FlutterOverlayWindow.closeOverlay();
  } catch (_) {/* silent */}
}

Future<void> cancelPartnerOrderNotification(String orderId) async {
  if (orderId.isEmpty) return;
  try {
    await FlutterLocalNotificationsPlugin().cancel(orderId.hashCode);
    debugPrint('[NotificationService] cancelled partner notif order=$orderId');
  } catch (e) {
    debugPrint('[NotificationService] cancel partner error: $e');
  }
}

/// Exec6.16 (2026-05-25) — Wake Activity via fullScreenIntent local notif.
/// Usado pelo FGS task isolate quando detecta oferta E o main isolate não
/// responde (bora_main_alive_ts stale). A notificação tem fullScreenIntent:true
/// + category: call → Android acorda o ecrã e lança MainActivity, que ao
/// resumir consome pending_offer SP via rehydrate → gate.present → overlay.
///
/// IMPORTANTE: isto NÃO é CallStyle visual (sem layout Atender/Decline).
/// É só o mecanismo Android para acordar ecrã + lançar Activity. O utilizador
/// vê é o overlay (SOBREPOSIÇÃO) depois da Activity boot.
///
/// Top-level: callable de MAIN, BG e FGS isolates (flutter_local_notifications
/// está registado em todos). Reusa canal v3 (IMPORTANCE_HIGH + sound bora_alert
/// + bypass DND). Acções 'accept_order' / 'reject_order' têm handler em
/// onBackgroundNotificationAction.
@pragma('vm:entry-point')
Future<void> postWakeActivityNotification({
  required String orderId,
  required String vendorName,
  required String total,
  required String distanceKm,
  required String driverEarnings,
}) async {
  try {
    final plugin = FlutterLocalNotificationsPlugin();
    final androidImpl = plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    await androidImpl?.createNotificationChannel(
      const AndroidNotificationChannel(
        'bora_orders_urgent_v3',
        'Bora — Novos pedidos',
        description: 'Som contínuo + vibração para novos pedidos urgentes.',
        importance: Importance.max,
        playSound: true,
        sound: RawResourceAndroidNotificationSound('bora_alert'),
        enableVibration: true,
        showBadge: true,
      ),
    );
    final androidDetails = AndroidNotificationDetails(
      'bora_orders_urgent_v3',
      'Bora — Novos pedidos',
      channelDescription: 'Wake Activity para mostrar SOBREPOSIÇÃO.',
      importance: Importance.max,
      priority: Priority.max,
      playSound: true,
      sound: const RawResourceAndroidNotificationSound('bora_alert'),
      enableVibration: true,
      // fullScreenIntent: acorda ecrã + lança MainActivity (não é CallStyle).
      category: AndroidNotificationCategory.call,
      fullScreenIntent: true,
      ongoing: true,
      autoCancel: false,
      visibility: fln.NotificationVisibility.public,
      ticker: 'Novo pedido — €$driverEarnings',
      actions: const <AndroidNotificationAction>[
        // showsUserInterface: false → handler BG corre direto sem abrir app
        AndroidNotificationAction('accept_order', '✅ Aceitar',
            showsUserInterface: false, cancelNotification: true),
        AndroidNotificationAction('reject_order', '❌ Rejeitar',
            showsUserInterface: false, cancelNotification: true),
      ],
    );
    await plugin.show(
      orderId.hashCode,
      '🛵 Novo pedido — €$driverEarnings',
      '$vendorName • €$total • ${distanceKm}km',
      NotificationDetails(android: androidDetails),
      payload: jsonEncode({'orderId': orderId, 'type': 'new_order_offer'}),
    );
    debugPrint('[BORA-OFFER] postWakeActivityNotification posted order=$orderId');
  } catch (e) {
    debugPrint('[BORA-OFFER] postWakeActivityNotification error: $e');
  }
}

/// Wraps Firebase Cloud Messaging for BORA APP.
///
/// Responsibilities:
///   • Request notification permission (iOS / Android 13+)
///   • Obtain and persist FCM token to `drivers.fcm_token` in Supabase
///   • Obtain and persist FCM token to `restaurants.fcm_token` in Supabase
///   • Handle foreground, background, and terminated notification events
///   • Provide HTTP helpers for notify-driver / notify-partner / notify-client endpoints
///
/// To activate after adding google-services.json / GoogleService-Info.plist:
///   1. Place google-services.json → android/app/
///   2. Place GoogleService-Info.plist → ios/Runner/
///   3. Uncomment Firebase.initializeApp() + this service's init() in main.dart
///   4. Run: flutter pub get
///   See README_FIREBASE_SETUP.md for full instructions.
class NotificationService {
  NotificationService._();
  static final NotificationService instance = NotificationService._();

  static final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

  final _sound = SoundService();
  bool _initialized = false;
  bool _consentGranted = true;
  String? _fcmToken;

  /// Tracks last saved binding so we can clear on logout.
  /// _boundRole ∈ {'client','driver','partner'}.
  String? _boundRole;
  String? _boundId;

  String? get fcmToken => _fcmToken;

  // ── Consent enforcement ───────────────────────────────────────────────────

  /// Called by [ConsentStore] whenever the user saves their GDPR preferences.
  /// If [allowed] is false: clears the FCM token from DB, resets the token
  /// in memory, and marks the service as uninitialised so that a future
  /// consent grant can re-initialise FCM cleanly.
  void applyNotificationConsent(bool allowed) {
    _consentGranted = allowed;
    if (!allowed) {
      clearTokenForCurrentUser().ignore();
      _fcmToken = null;
      _initialized = false;
      debugPrint('[NotificationService] consent revoked — FCM disabled');
    }
  }

  // ── Broadcast deep-link ───────────────────────────────────────────────────

  static bool _broadcastDeepLinkWired = false;

  /// Routes admin_broadcast / admin_message FCM taps to NotificationsScreen.
  /// Idempotent — safe to call from build().
  static void setupBroadcastDeepLink(BuildContext context) {
    if (_broadcastDeepLinkWired) return;
    _broadcastDeepLinkWired = true;
    final navigator = Navigator.of(context);
    void openInbox() => navigator.push(
          MaterialPageRoute(builder: (_) => const NotificationsScreen()),
        );
    FirebaseMessaging.onMessageOpenedApp.listen((msg) {
      final t = msg.data['type'];
      if (t == 'admin_broadcast' || t == 'admin_message') openInbox();
    });
    FirebaseMessaging.instance.getInitialMessage().then((msg) {
      if (msg == null) return;
      final t = msg.data['type'];
      if (t == 'admin_broadcast' || t == 'admin_message') openInbox();
    });
  }

  // ── Lifecycle ─────────────────────────────────────────────────────────────

  Future<void> init() async {
    if (_initialized) return;
    if (kIsWeb) return;
    if (!_consentGranted) {
      debugPrint('[NotificationService] init skipped — notifications consent not granted');
      return;
    }

    // Inicializar flutter_local_notifications para registar o callback de tap.
    // Sem este initialize(), onDidReceiveNotificationResponse nunca é chamado
    // e tocar na notificação persistente não abre o ecrã de aceitar/rejeitar.
    await FlutterLocalNotificationsPlugin().initialize(
      const InitializationSettings(
        android: AndroidInitializationSettings('@mipmap/ic_launcher'),
      ),
      onDidReceiveNotificationResponse: _onLocalNotifTap,
      onDidReceiveBackgroundNotificationResponse: onBackgroundNotificationAction,
    );

    // Persiste access token sempre que a sessão Supabase muda — o background
    // notification action handler precisa dele para fazer HTTP autenticado.
    try {
      Supabase.instance.client.auth.onAuthStateChange.listen((data) {
        final token = data.session?.accessToken;
        if (token != null && token.isNotEmpty) {
          SharedPreferences.getInstance().then(
            (prefs) => prefs.setString('bora_access_token', token),
          );
        }
      });
    } catch (_) {}

    // Register background handler BEFORE any other FCM call.
    FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);

    final messaging = FirebaseMessaging.instance;

    // Request permission (required on iOS; Android 13+ shows a dialog too).
    final settings = await messaging.requestPermission(
      alert: true,
      badge: true,
      sound: true,
    );
    debugPrint(
        '[NotificationService] permission: ${settings.authorizationStatus}');

    // Fetch initial token. May return null on iOS simulators without APNS.
    _fcmToken = await messaging.getToken();
    debugPrint('[NotificationService] FCM token: $_fcmToken');

    // Refresh token (device re-registers, app reinstall, etc.).
    messaging.onTokenRefresh.listen((token) {
      _fcmToken = token;
      debugPrint('[NotificationService] token refreshed: $token');
      // Re-persist for the currently bound user so DB stays in sync.
      final role = _boundRole;
      final id = _boundId;
      if (role != null && id != null) {
        switch (role) {
          case 'client':
            saveTokenForClient(id);
            break;
          case 'driver':
            saveTokenForDriver(id);
            break;
          case 'partner':
            saveTokenForPartner(id);
            break;
        }
      }
    });

    // Foreground messages: show in-app sound; UI already shows via Realtime.
    // new_order is handled by _handleNewOrders (realtime stream) — skip to
    // avoid double-sound when MBWay payment is confirmed.
    FirebaseMessaging.onMessage.listen((RemoteMessage msg) {
      debugPrint(
        '[NotificationService FG] data=${msg.data}',
      );
      final type = msg.data['type'];
      // new_order / new_order_offer: o realtime channel já renderiza o card
      // com countdown + dispara o som via UI. Skipar aqui evita double-sound.
      if (type == 'new_order') return;
      if (type == 'new_order_offer') return;
      if (type == 'chat') {
        _showChatBanner(msg);
        return;
      }
      _sound.playOnce();
    });

    // Notification tap while app was in background.
    FirebaseMessaging.onMessageOpenedApp.listen((RemoteMessage msg) {
      debugPrint('[NotificationService opened] ${msg.notification?.title}');
    });

    // Notification tap while app was terminated.
    final initial = await messaging.getInitialMessage();
    if (initial != null) {
      debugPrint(
          '[NotificationService initial] ${initial.notification?.title}');
    }

    // Sessão 2026-05-21 — overlay system_alert_window: o isolate da overlay
    // envia `{action: accept|reject|expired, orderId: ...}` quando o estafeta
    // decide. O som contínuo + ofertas reais são tratados pela local
    // notification + realtime channel; aqui apenas logamos a decisão.
    fow.FlutterOverlayWindow.overlayListener.listen((dynamic d) {
      if (d is! Map) return;
      final action = d['action']?.toString();
      final orderId = d['orderId']?.toString() ?? '';
      if (action == null) return;
      debugPrint(
          '[NotificationService] overlay action=$action order=$orderId');
      // Cancelar notificação persistente após decisão do driver.
      if (action == 'accept' || action == 'reject' || action == 'expired') {
        cancelDriverOfferNotification(orderId).ignore();
        // Fix #2 (2026-05-24) — libertar dedup para permitir re-oferta
        // futura do mesmo orderId (cycle reset do dispatch-engine).
        resetOfferDedup();
        // Exec6.12 (2026-05-25) — liberta o gate central. Sem isto,
        // próximo pedido fica HANDLED forever e overlay não re-dispara.
        OfferPresentationGate.markActionCompleted(orderId);
      }
      // Sessão 2026-05-24 (exec2 FIX D) — overlay isolate NÃO tem Supabase;
      // o accept/reject só era cancelar a notif, NÃO chamava as RPCs ⇒
      // pedido ficava preso. Agora o main isolate (que tem Supabase) chama
      // a RPC quando recebe a acção do overlay.
      if (action == 'accept' && orderId.isNotEmpty) {
        _invokeAcceptOffer(orderId);
      } else if (action == 'reject' && orderId.isNotEmpty) {
        _invokeRejectOffer(orderId);
      }
    });

    // Bridge FCM→FGS→main: recebe payload new_order_offer que o
    // _BoraTaskHandler reencaminhou via sendDataToMain.
    FlutterForegroundTask.addTaskDataCallback(_onForegroundTaskData);

    // Exec4 (2026-05-24): rehydrate pending_offer (caso app morta arrancada
    // por fullScreenIntent — realtime perdeu o UPDATE que aconteceu antes).
    _startRehydrateLoop();

    _initialized = true;
    debugPrint('[NotificationService] initialized.');
  }

  void _onForegroundTaskData(Object data) {
    // Exec6.15 FASE 1 DIAGNÓSTICO.
    debugPrint('[FGS_BRIDGE] [_onForegroundTaskData] ENTRY (main isolate) data=$data');
    if (data is! Map) {
      debugPrint('[FGS_BRIDGE] [_onForegroundTaskData] SKIP — não é Map');
      return;
    }
    final type = data['type']?.toString();
    if (type != 'new_order_offer') {
      debugPrint('[FGS_BRIDGE] [_onForegroundTaskData] SKIP — type=$type');
      return;
    }
    final orderId = data['orderId']?.toString() ?? '';
    if (orderId.isEmpty) {
      debugPrint('[FGS_BRIDGE] [_onForegroundTaskData] SKIP — orderId vazio');
      return;
    }
    // Exec6 GATE (2026-05-25) — gate central decide UI por estado.
    debugPrint('[FGS_BRIDGE] [_onForegroundTaskData] → gate.present order=$orderId');
    OfferPresentationGate.present(
      orderId: orderId,
      vendorName: data['vendorName']?.toString() ?? 'Novo pedido',
      total: data['total']?.toString() ?? '0.00',
      distanceKm: data['distanceKm']?.toString() ?? '0',
      driverEarnings: data['driverEarnings']?.toString() ?? '0.00',
      dropoffAddress: data['dropoffAddress']?.toString() ?? '',
    );
  }

  // ── Overlay (system_alert_window) helpers ─────────────────────────────────

  /// Sessão 2026-05-21 — pede permissão ao Android para desenhar por cima de
  /// outras apps. Idempotente: devolve true se já estiver garantida. Quando
  /// abre o picker do sistema, devolve o estado actual sem esperar pelo
  /// resultado (o utilizador pode cancelar — chama de novo da próxima vez).
  Future<bool> ensureOverlayPermission() async {
    if (kIsWeb) return false;
    try {
      final granted = await fow.FlutterOverlayWindow.isPermissionGranted();
      if (granted) return true;
      await fow.FlutterOverlayWindow.requestPermission();
      return await fow.FlutterOverlayWindow.isPermissionGranted();
    } catch (e) {
      debugPrint('[NotificationService] ensureOverlayPermission error: $e');
      return false;
    }
  }

  /// Fecha o overlay activo (estafeta abriu o app e está a tratar da oferta
  /// pelo card normal, ou backend revogou a oferta). Idempotente.
  Future<void> closeOverlayIfActive() async {
    try {
      final active = await fow.FlutterOverlayWindow.isActive();
      if (active) await fow.FlutterOverlayWindow.closeOverlay();
    } catch (_) {/* silent */}
  }

  /// Pre-inicializa o overlay em standby quando driver vai Online.
  /// Chamado em FOREGROUND para que showOverlay() funcione sem restrições.
  /// O overlay fica activo mas invisível (flag=clickThrough) até que
  /// showDriverOfferOverlay() actualize o flag para defaultFlag.
  /// Quando chega a próxima oferta, shareData() é suficiente — sem
  /// necessidade de outro showOverlay() (que pode falhar em background).
  Future<void> initDriverStandbyOverlay() async {
    if (kIsWeb) return;
    try {
      final granted = await fow.FlutterOverlayWindow.isPermissionGranted();
      if (!granted) {
        debugPrint('[NotificationService] initDriverStandbyOverlay: sem permissão');
        return;
      }
      final alreadyActive = await fow.FlutterOverlayWindow.isActive();
      if (alreadyActive) {
        // Já activo — garantir que está em standby (click-through).
        // Exec6.13 — updateFlag pode falhar em v0.4.5; capturar silenciosamente.
        try {
          await fow.FlutterOverlayWindow.updateFlag(fow.OverlayFlag.clickThrough);
        } catch (e) {
          debugPrint('[NotificationService] updateFlag(clickThrough) falhou no plugin v0.4.5: $e');
        }
        return;
      }
      await fow.FlutterOverlayWindow.showOverlay(
        enableDrag: false,
        overlayTitle: '',
        overlayContent: '',
        flag: fow.OverlayFlag.clickThrough,
        visibility: fow.NotificationVisibility.visibilityPublic,
        positionGravity: fow.PositionGravity.auto,
        height: 420,
        width: fow.WindowSize.matchParent,
      );
      debugPrint('[NotificationService] initDriverStandbyOverlay: standby ready');
    } catch (e) {
      debugPrint('[NotificationService] initDriverStandbyOverlay error: $e');
    }
  }

  // ── Rehydrate pending offer (Exec4, 2026-05-24) ─────────────────────────
  //
  // Caso típico: app morta → FCM chega → bg handler escreve `pending_offer`
  // em SharedPreferences + mostra notif fullScreenIntent → Android lança
  // MainActivity → Flutter boota. Quando o NotificationService.init() corre,
  // o navigatorKey ainda não tem state (MaterialApp ainda não montou).
  // Este loop espera pelo navigator e empurra o dialog assim que existe.
  // Janela 60s (oferta tem TTL 40s).
  void _startRehydrateLoop() {
    Timer.periodic(const Duration(milliseconds: 600), (t) async {
      try {
        // Exec6.17 (2026-05-25) — REMOVIDO cap de 60s. O rehydrate loop é o
        // único caminho fiável para consumir pending_offer escrito pelo FCM bg
        // handler ou FGS task isolate. Sempre vivo. Custo: 1 SP read a cada 600ms.
        // Exec6.18 (2026-05-25) — REMOVIDO guard `navigatorKey.currentState == null`:
        // em BG o navigator pode parecer null mas FlutterOverlayWindow.showOverlay
        // (caminho do _showOverlay) NÃO precisa de navigator — só do plugin
        // registado no main isolate. Guard estava a bloquear consume em BG.
        final prefs = await SharedPreferences.getInstance();
        // Exec6.18c — CRÍTICO: reload força refresh do cache. bg isolate
        // escreve pending_offer mas main isolate tem cache stale → sem
        // reload() este loop NUNCA via o write. Causa-raiz do "rehydrate
        // não consome" em todos os testes anteriores.
        await prefs.reload();
        final pending = prefs.getString('pending_offer');
        if (pending == null || pending.isEmpty) {
          // Sem oferta pendente — espera mais um pouco. Não cancelar:
          // o utilizador pode receber uma oferta dentro da janela.
          return;
        }
        final data = jsonDecode(pending) as Map<String, dynamic>;
        final ts = data['ts'];
        if (ts is int) {
          final age = DateTime.now().millisecondsSinceEpoch - ts;
          if (age > 45000) {
            debugPrint('[BORA-OFFER] rehydrate skip — oferta expirada (age=${age}ms)');
            await prefs.remove('pending_offer');
            return;
          }
        }
        final orderId = data['orderId']?.toString() ?? '';
        if (orderId.isEmpty) {
          await prefs.remove('pending_offer');
          return;
        }
        debugPrint('[BORA-OFFER] REHYDRATE pending_offer order=$orderId → gate.present');
        await prefs.remove('pending_offer');
        // Exec6 GATE (2026-05-25) — empurra para o gate. Não passa fromBgIsolate=true
        // porque rehydrate corre no main isolate (já depois de Flutter resumed).
        await OfferPresentationGate.present(
          orderId: orderId,
          vendorName: data['vendorName']?.toString() ?? 'Novo pedido',
          total: data['total']?.toString() ?? '0.00',
          distanceKm: data['distanceKm']?.toString() ?? '0',
          driverEarnings: data['driverEarnings']?.toString() ?? '0.00',
          dropoffAddress: data['dropoffAddress']?.toString() ?? '',
        );
      } catch (e) {
        debugPrint('[BORA-OFFER] rehydrate error: $e');
      }
    });
  }

  // ── Accept/Reject RPCs (Fix D, 2026-05-24) ──────────────────────────────
  //
  // Chamadas a partir do overlayListener (acção vinda do overlay isolate),
  // do _onForegroundTaskData (ponte FGS→main) e directamente pelo card
  // in-app do estafeta. Centraliza tratamento de offer_expired_or_taken
  // para nunca deixar o pedido preso em silêncio.

  Future<void> _invokeAcceptOffer(String orderId) async {
    try {
      final res = await Supabase.instance.client
          .rpc('driver_accept_offer', params: {'p_order_id': orderId});
      // RPC devolve jsonb {ok:bool, ...}
      if (res is Map && res['ok'] == false) {
        final err = res['error']?.toString() ?? 'unknown';
        debugPrint(
            '[NotificationService] accept_offer FAILED order=$orderId error=$err');
        if (err == 'offer_expired_or_taken') {
          _sound.stop();
          cancelDriverOfferNotification(orderId).ignore();
          await closeOverlayIfActive();
        }
        return;
      }
      debugPrint('[NotificationService] accept_offer OK order=$orderId');
      _sound.stop();
      await closeOverlayIfActive();
    } catch (e) {
      debugPrint('[NotificationService] _invokeAcceptOffer error: $e');
    }
  }

  Future<void> _invokeRejectOffer(String orderId) async {
    try {
      await Supabase.instance.client
          .rpc('driver_reject_offer', params: {'p_order_id': orderId});
      debugPrint('[NotificationService] reject_offer OK order=$orderId');
      _sound.stop();
      await closeOverlayIfActive();
    } catch (e) {
      debugPrint('[NotificationService] _invokeRejectOffer error: $e');
    }
  }

  /// Sessão 2026-05-24 (Fix #2) — dedup cross-path. Os 3 caminhos do híbrido
  /// (FCM data-only BG, realtime broadcast `driver-offer:{driverId}`, FGS REST
  /// polling fallback) podem disparar quase ao mesmo tempo para o MESMO
  /// orderId. Sem esta guarda, o overlay reabriria + som tocaria 2-3x.
  /// Janela 10s cobre a corrida; após isso, mesma orderId pode reentrar
  /// (cenário cycle-reset do dispatch-engine v56 que re-oferece o mesmo
  /// pedido ao mesmo estafeta).
  static String? _lastShownOfferId;
  static DateTime? _lastShownOfferAt;
  static const Duration _offerDedupWindow = Duration(seconds: 10);

  /// Reset manual da janela de dedup. Chamar quando o overlay reporta uma
  /// acção (accept/reject/expired) — assim um eventual re-oferta posterior
  /// não é silenciada por engano.
  void resetOfferDedup() {
    _lastShownOfferId = null;
    _lastShownOfferAt = null;
  }

  /// Mostra o overlay de oferta de pedido por cima de outras apps.
  /// Quando o overlay já está em standby (initDriverStandbyOverlay chamado
  /// ao ir Online), usa updateFlag + shareData — funciona em background
  /// porque comunicar com um service já activo não requer foreground.
  Future<void> showDriverOfferOverlay({
    required String orderId,
    String vendorName = 'Novo pedido',
    String total = '0.00',
    String distanceKm = '0',
    String driverEarnings = '0.00',
  }) async {
    if (kIsWeb) return;
    // Dedup cross-path (FCM ↔ realtime ↔ FGS polling) — janela 10s.
    final now = DateTime.now();
    if (_lastShownOfferId == orderId &&
        _lastShownOfferAt != null &&
        now.difference(_lastShownOfferAt!) < _offerDedupWindow) {
      debugPrint(
          '[NotificationService] showDriverOfferOverlay: dedup HIT order=$orderId');
      return;
    }
    _lastShownOfferId = orderId;
    _lastShownOfferAt = now;
    final payload = <String, dynamic>{
      'orderId': orderId, 'vendorName': vendorName,
      'total': total, 'distanceKm': distanceKm, 'driverEarnings': driverEarnings,
    };
    try {
      final granted = await fow.FlutterOverlayWindow.isPermissionGranted();
      if (!granted) {
        debugPrint('[NotificationService] showDriverOfferOverlay: sem permissão SYSTEM_ALERT_WINDOW');
        return;
      }
      // Exec6.19 (2026-05-26) — ABANDONADO o caminho "standby + shareData".
      // shareData estava a chegar ao plugin nativo mas o widget overlay não
      // recebia (listener silencioso, sem [OVERLAY] _onData logs). Causa
      // provável: widget unmounted após ciclo anterior, isActive=true mas
      // sem listener vivo. Solução: close + showOverlay fresh sempre.
      final alreadyActive = await fow.FlutterOverlayWindow.isActive();
      debugPrint('[OVERLAY-MAIN] isActive=$alreadyActive');
      // CRITICAL exec6.19d (2026-05-26): NÃO fazer close+reopen quando isActive.
      // Close DESTRÓI o widget + listener mounted (initDriverStandbyOverlay).
      // Reabrir cria isolate fresco mas shareData chega ANTES do listener
      // resubscrever → evento perdido → overlay nunca renderiza.
      // Solução: se isActive, REUTILIZAR overlay existente (listener já vivo)
      // + shareData fire-and-forget direto.
      if (!alreadyActive) {
        debugPrint('[OVERLAY-MAIN] not active → showOverlay() to create');
        try {
          await fow.FlutterOverlayWindow.showOverlay(
            enableDrag: false,
            overlayTitle: 'Novo pedido!',
            overlayContent: vendorName,
            flag: fow.OverlayFlag.defaultFlag,
            visibility: fow.NotificationVisibility.visibilityPublic,
            positionGravity: fow.PositionGravity.auto,
            height: 420,
            width: fow.WindowSize.matchParent,
          );
          debugPrint('[OVERLAY-MAIN] showOverlay returned OK');
        } catch (e) {
          debugPrint('[OVERLAY-MAIN] showOverlay EXCEPTION: $e');
          rethrow;
        }
        // Wait widget mount + listener subscribe (overlayListener stream).
        await Future<void>.delayed(const Duration(milliseconds: 1200));
      } else {
        debugPrint('[OVERLAY-MAIN] already active → reusing existing widget+listener');
      }
      debugPrint('[OVERLAY-MAIN] about to call shareData (fire-and-forget)');
      fow.FlutterOverlayWindow.shareData(payload).then((res) {
        debugPrint('[OVERLAY-MAIN] shareData completed (async): $res');
      }).catchError((e) {
        debugPrint('[OVERLAY-MAIN] shareData EXCEPTION (async): $e');
      });
      debugPrint('[OVERLAY-MAIN] shareData fired (não await)');
    } catch (e) {
      debugPrint('[NotificationService] showDriverOfferOverlay error: $e');
    }
  }

  // ── Token persistence ─────────────────────────────────────────────────────

  /// Saves the FCM token to `drivers.fcm_token` for the given [driverId].
  /// Call this after a driver successfully logs in.
  Future<void> saveTokenForDriver(String driverId) async {
    if (!_consentGranted) return;
    // Bind ANTES do null check: onTokenRefresh precisa do _boundRole/_boundId
    // mesmo que o token ainda não esteja disponível agora.
    _boundRole = 'driver';
    _boundId = driverId;
    // PushTokenService tem retry próprio (1s/3s/9s) — chamar mesmo se
    // _fcmToken ainda é null; ele vai buscar o token por conta própria.
    PushTokenService.registerForRole('driver').ignore();

    final token = _fcmToken;
    if (token == null) {
      debugPrint('[NotificationService] saveTokenForDriver: FCM token null — PushTokenService will retry');
      return;
    }

    try {
      await Supabase.instance.client
          .from('drivers')
          .update({'fcm_token': token}).eq('id', driverId);
      debugPrint('[NotificationService] FCM token saved for driver $driverId');
    } catch (e) {
      debugPrint('[NotificationService] saveTokenForDriver error: $e');
    }
  }

  /// Saves the FCM token to `users.fcm_token` for the given [clientId].
  /// Call this after a client successfully logs in.
  Future<void> saveTokenForClient(String clientId) async {
    if (!_consentGranted) return;
    final token = _fcmToken;
    if (token == null) {
      debugPrint('[NotificationService] saveTokenForClient: no FCM token yet');
      return;
    }
    _boundRole = 'client';
    _boundId = clientId;

    // BUG 2 fix — multi-device PRIMEIRO (independente de users.upsert).
    PushTokenService.registerForRole('client').ignore();

    try {
      await Supabase.instance.client.from('users').upsert({
        'id': clientId,
        'fcm_token': token,
      });
      debugPrint('[NotificationService] FCM token saved for client $clientId');
    } catch (e) {
      debugPrint('[NotificationService] saveTokenForClient error: $e');
    }
  }

  /// Saves the FCM token for the given [restaurantId] partner.
  /// Call this after a partner successfully logs in.
  ///
  /// Writes to both:
  ///   • partner_push_tokens via register_push_token RPC (auth.uid() server-side)
  ///   • restaurants.fcm_token (legacy — mantido durante transição)
  Future<void> saveTokenForPartner(String restaurantId) async {
    if (!_consentGranted) return;
    final token = _fcmToken;
    if (token == null) {
      debugPrint(
          '[NotificationService] saveTokenForPartner: no FCM token yet');
      return;
    }
    // Set binding BEFORE try blocks so onTokenRefresh re-registers correctly.
    _boundRole = 'partner';
    _boundId = restaurantId;

    // Multi-device UPSERT via RPC register_push_token (usa auth.uid() server-side).
    PushTokenService.registerForRole('partner').ignore();

    try {
      await Supabase.instance.client
          .from('restaurants')
          .update({'fcm_token': token}).eq('id', restaurantId);
      debugPrint(
          '[NotificationService] FCM token saved for partner $restaurantId');
    } catch (e) {
      debugPrint('[NotificationService] saveTokenForPartner error: $e');
    }
  }

  /// Clears the FCM token from DB for the currently bound user.
  /// Call this BEFORE logout so the device stops receiving push notifications
  /// targeted at the previous session. Safe no-op if nothing is bound.
  Future<void> clearTokenForCurrentUser() async {
    final role = _boundRole;
    final id = _boundId;
    if (role == null || id == null) {
      debugPrint('[NotificationService] clearTokenForCurrentUser: no bound user');
      return;
    }
    try {
      final client = Supabase.instance.client;
      switch (role) {
        case 'client':
          await client.from('users').update({'fcm_token': null}).eq('id', id);
          break;
        case 'driver':
          await client.from('drivers').update({'fcm_token': null}).eq('id', id);
          break;
        case 'partner':
          await client
              .from('restaurants')
              .update({'fcm_token': null})
              .eq('id', id);
          break;
      }
      debugPrint('[NotificationService] FCM token cleared for $role $id');
    } catch (e) {
      debugPrint('[NotificationService] clearTokenForCurrentUser error: $e');
    } finally {
      _boundRole = null;
      _boundId = null;
    }
  }

  // ── Send helpers (HTTP → Supabase Edge Functions) ─────────────────────────

  /// Notifies the partner restaurant of a new incoming order via FCM push.
  /// [items] is a short human-readable summary, e.g. "2x Sushi, 1x Ramen".
  Future<void> notifyPartnerNewOrder({
    required String orderId,
    required String restaurantId,
    required String items,
    required double total,
  }) async {
    await _post('notify-partner', {
      'orderId': orderId,
      'restaurantId': restaurantId,
      'items': items,
      'total': total,
    });
  }

  Future<void> notifyDriversNewOrder({
    required String orderId,
    required String vendorName,
    required double total,
  }) async {
    await _post('notify-drivers', {
      'orderId': orderId,
      'title': 'Novo pedido disponível',
      'body': '$vendorName • €${total.toStringAsFixed(2)}',
    });
  }

  Future<void> notifyClient({
    required String clientPhone,
    required String title,
    required String body,
  }) async {
    await _post('notify-client', {
      'clientPhone': clientPhone,
      'title': title,
      'body': body,
    });
  }

  /// Notifies the client that the driver added carrier bags to a market order.
  /// [bagCount] is the number of bags; [bagFee] is the total fee (count × €0.10).
  /// Fire-and-forget — call with `.ignore()`.
  Future<void> notifyClientBagCount({
    required String clientId,
    required String orderId,
    required int bagCount,
    required double bagFee,
  }) async {
    final unit = bagCount == 1 ? 'saco' : 'sacos';
    final feeFormatted = bagFee.toStringAsFixed(2);
    await _post('notify-client', {
      'clientId': clientId,
      'orderId': orderId,
      'title': 'Sacos adicionados',
      'body': '🛍️ $bagCount $unit × €0.10 = €$feeFormatted',
    });
  }

  /// Sends a status-specific push to the client for a given order.
  /// Messages mirror Uber Eats tone: specific, short, action-oriented.
  ///
  /// [status] must be one of: preparing, callingDriver, driverAccepted,
  /// pickedUp, onTheWay, delivered. Unknown statuses are no-ops.
  Future<void> notifyClientOrderStatus({
    required String clientId,
    required String orderId,
    required String status,
    String? vendorName,
    String? driverName,
    int? etaMinutes,
    String? serviceType, // BUG 3 — 'restaurant' | 'storeShopping' | etc
  }) async {
    final msg = _statusMessageForClient(
      status: status,
      vendorName: vendorName,
      driverName: driverName,
      serviceType: serviceType,
      etaMinutes: etaMinutes,
    );
    if (msg == null) return;
    await _post('notify-client', {
      'clientId': clientId,
      'orderId': orderId,
      'status': status,
      'title': msg.$1,
      'body': msg.$2,
    });
  }

  /// Returns (title, body) for the given order status, or null if the status
  /// does not warrant a client push.
  (String, String)? _statusMessageForClient({
    required String status,
    String? vendorName,
    String? driverName,
    int? etaMinutes,
    String? serviceType,
  }) {
    final vendor = (vendorName ?? '').trim();
    final driver = (driverName ?? '').trim();
    // BUG 3 — texto dinâmico por service_type
    final isStore = serviceType == 'storeShopping';
    final pickupNoun = isStore ? 'loja' : 'restaurante';
    final pickupArticle = isStore ? 'A' : 'O';
    switch (status) {
      case 'preparing':
        return (
          'Pedido aceite',
          vendor.isEmpty
              ? '👨‍🍳 $pickupArticle $pickupNoun está a preparar o seu pedido'
              : '👨‍🍳 $vendor está a preparar o seu pedido',
        );
      case 'callingDriver':
        return (
          'À procura de estafeta',
          '🛵 A procurar o melhor estafeta para o seu pedido…',
        );
      case 'driverAccepted':
        return (
          'Estafeta a caminho d${isStore ? "a loja" : "o restaurante"}',
          driver.isEmpty
              ? '✅ Um estafeta aceitou o seu pedido'
              : '✅ $driver aceitou o seu pedido',
        );
      case 'pickedUp':
        return (
          'Pedido recolhido',
          '📦 O seu pedido foi recolhido e está a caminho',
        );
      case 'onTheWay':
        return (
          'A caminho!',
          etaMinutes == null || etaMinutes <= 0
              ? '🛵 O seu pedido está a caminho'
              : '🛵 A caminho! Chega em ~$etaMinutes min',
        );
      case 'delivered':
        return (
          'Entregue 🎉',
          'Como foi a sua experiência? Avalie o pedido e ajude outros clientes.',
        );
      default:
        return null;
    }
  }

  // Injected at build time via --dart-define-from-file=.dart_defines.
  // Must match the values passed to Supabase.initialize(...) in main.dart.
  static const String _supabaseUrl = String.fromEnvironment('SUPABASE_URL');
  static const String _anonKey = String.fromEnvironment('SUPABASE_ANON_KEY');

  Future<void> _post(String functionName, Map<String, dynamic> payload) async {
    const supabaseUrl = _supabaseUrl;
    const anonKey = _anonKey;
    try {
      await http.post(
        Uri.parse('$supabaseUrl/functions/v1/$functionName'),
        headers: {
          'Content-Type': 'application/json',
          'apikey': anonKey,
          'Authorization': 'Bearer $anonKey',
        },
        body: jsonEncode(payload),
      );
    } catch (e) {
      debugPrint('[NotificationService] _post($functionName) error: $e');
    }
  }

  // ── Foreground chat banner ────────────────────────────────────────────────

  void _showChatBanner(RemoteMessage message) {
    final overlayState = navigatorKey.currentState?.overlay;
    if (overlayState == null) return;

    final title = message.notification?.title ?? '💬 Nova mensagem';
    final body = message.notification?.body ?? '';
    final orderId = message.data['order_id'] as String?;

    late OverlayEntry entry;
    entry = OverlayEntry(
      builder: (ctx) => _ChatBannerWidget(
        title: title,
        body: body,
        onTap: () {
          entry.remove();
          if (orderId != null) _openChat(orderId);
        },
        onDismiss: () => entry.remove(),
      ),
    );
    overlayState.insert(entry);
    SystemSound.play(SystemSoundType.click);
  }

  void _openChat(String orderId) async {
    final senderType = switch (_boundRole) {
      'client' => ChatSenderType.client,
      'driver' => ChatSenderType.driver,
      'partner' => ChatSenderType.partner,
      _ => null,
    };
    if (senderType == null) return;

    final ctx = navigatorKey.currentContext;
    if (ctx == null) return;

    try {
      final data = await Supabase.instance.client
          .from('orders')
          .select()
          .eq('id', orderId)
          .maybeSingle();
      if (data == null || !ctx.mounted) return;
      final order = OrderModel.fromSupabase(data);
      Navigator.of(ctx).push(MaterialPageRoute<void>(
        builder: (_) => ChatScreen(
          order: order,
          senderType: senderType,
          conversationType: resolveConversationType(senderType, order.status, null),
        ),
      ));
    } catch (e) {
      debugPrint('[NotificationService] _openChat error: $e');
    }
  }

  // ── Dispose ───────────────────────────────────────────────────────────────

  void dispose() {
    _sound.dispose();
  }
}

// ── Chat banner widget ────────────────────────────────────────────────────────

class _ChatBannerWidget extends StatefulWidget {
  const _ChatBannerWidget({
    required this.title,
    required this.body,
    required this.onTap,
    required this.onDismiss,
  });

  final String title;
  final String body;
  final VoidCallback onTap;
  final VoidCallback onDismiss;

  @override
  State<_ChatBannerWidget> createState() => _ChatBannerWidgetState();
}

class _ChatBannerWidgetState extends State<_ChatBannerWidget>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<Offset> _slide;
  late final Animation<double> _fade;
  bool _dismissed = false;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 280),
    );
    _slide = Tween<Offset>(
      begin: const Offset(0, -1),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeOut));
    _fade = CurvedAnimation(parent: _ctrl, curve: Curves.easeIn);
    _ctrl.forward();
    Future.delayed(const Duration(seconds: 4), _dismiss);
  }

  void _dismiss() async {
    if (_dismissed || !mounted) return;
    _dismissed = true;
    await _ctrl.reverse();
    widget.onDismiss();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final topPadding = MediaQuery.of(context).padding.top;
    return Positioned(
      top: topPadding + 8,
      left: 16,
      right: 16,
      child: SlideTransition(
        position: _slide,
        child: FadeTransition(
          opacity: _fade,
          child: GestureDetector(
            onTap: widget.onTap,
            onVerticalDragEnd: (d) {
              if (d.velocity.pixelsPerSecond.dy < 0) _dismiss();
            },
            child: Material(
              elevation: 8,
              borderRadius: BorderRadius.circular(16),
              color: const Color(0xFF1C1C1E).withValues(alpha: 0.93),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                child: Row(
                  children: [
                    const Icon(Icons.chat_bubble_rounded,
                        color: Color(0xFF2E7D32), size: 26),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            widget.title,
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                              fontSize: 14,
                            ),
                          ),
                          if (widget.body.isNotEmpty)
                            Text(
                              widget.body,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: Colors.white70,
                                fontSize: 13,
                              ),
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
