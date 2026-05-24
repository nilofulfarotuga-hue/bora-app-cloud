import 'dart:async';
import 'dart:convert';

import 'package:connectycube_flutter_call_kit/connectycube_flutter_call_kit.dart';
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
import '../widgets/driver_full_screen_offer_dialog.dart';
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

  // ── Parceiro: novo pedido em background ─────────────────────────────────
  if (data['type'] == 'new_order') {
    final orderId = data['orderId']?.toString() ?? '';
    final items = data['items']?.toString() ?? 'Novo pedido';
    final total = data['total']?.toString() ?? '0.00';
    try {
      final plugin = FlutterLocalNotificationsPlugin();
      final androidImpl = plugin.resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>();
      await androidImpl?.createNotificationChannel(
        const AndroidNotificationChannel(
          'bora_partner_orders',
          'Bora — Pedidos parceiro',
          description: 'Notificações de novos pedidos para parceiros',
          importance: Importance.max,
          playSound: true,
          sound: RawResourceAndroidNotificationSound('bora_alert'),
          enableVibration: true,
        ),
      );
      const androidDetails = AndroidNotificationDetails(
        'bora_partner_orders',
        'Bora — Pedidos parceiro',
        channelDescription: 'Notificações de novos pedidos para parceiros',
        importance: Importance.max,
        priority: Priority.max,
        playSound: true,
        sound: RawResourceAndroidNotificationSound('bora_alert'),
        enableVibration: true,
        autoCancel: true,
        visibility: fln.NotificationVisibility.public,
        actions: <AndroidNotificationAction>[
          AndroidNotificationAction('accept_partner_order', '✅ Aceitar',
              showsUserInterface: false, cancelNotification: true),
          AndroidNotificationAction('reject_partner_order', '❌ Rejeitar',
              showsUserInterface: false, cancelNotification: true),
        ],
      );
      await plugin.show(
        orderId.isNotEmpty ? orderId.hashCode : 9999,
        '🔔 Novo pedido!',
        '$items • €$total',
        const NotificationDetails(android: androidDetails),
        payload: jsonEncode({'orderId': orderId, 'type': 'new_order'}),
      );
      debugPrint('[FCM BG] partner new_order notif shown order=$orderId');
    } catch (e) {
      debugPrint('[FCM BG] partner notif error: $e');
    }
    return;
  }

  if (data['type'] != 'new_order_offer') return;

  final orderId = data['orderId']?.toString() ?? '';
  final vendorName = data['vendorName']?.toString() ?? 'Novo pedido';
  final total = data['total']?.toString() ?? '0.00';
  final distanceKm = data['distanceKm']?.toString() ?? '0';
  final driverEarnings = data['driverEarnings']?.toString() ?? '0.00';
  final dropoffAddress = data['dropoffAddress']?.toString() ?? '';
  final notifBody = dropoffAddress.isNotEmpty
      ? '$vendorName • €$total • ${distanceKm}km • €$driverEarnings\n📍 $dropoffAddress'
      : '$vendorName • €$total • ${distanceKm}km • €$driverEarnings';

  // ── 1) Local notification com fullScreenIntent ─────────────────────────
  // Em Android <14 abre MainActivity por cima de tudo (showWhenLocked +
  // turnScreenOn no manifest). Em Android 14+ requer USE_FULL_SCREEN_INTENT
  // concedida pelo utilizador — sem ela, heads-up.
  try {
    final plugin = FlutterLocalNotificationsPlugin();
    final androidImpl = plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    // Sessão 2026-05-24 (exec2 FIX A) — canal v3 com som EXPLÍCITO.
    // MainActivity.kt cria o mesmo ID em Kotlin com setSound() correcto
    // (AudioAttributes USAGE_NOTIFICATION_RINGTONE). Criamos aqui também
    // para o caso de o BG handler correr antes de o utilizador abrir
    // alguma vez a MainActivity. Idempotente — se o canal já existe,
    // Android ignora; mas o som FICA o que foi posto na 1ª criação.
    await androidImpl?.createNotificationChannel(
      const AndroidNotificationChannel(
        'bora_orders_urgent_v3',
        'Bora — Novos pedidos',
        description: 'Som contínuo + vibração para novos pedidos urgentes.',
        importance: Importance.max,
        playSound: true,
        sound: RawResourceAndroidNotificationSound('bora_alert'),
        enableVibration: true,
      ),
    );
    const androidDetails = AndroidNotificationDetails(
      'bora_orders_urgent_v3',
      'Bora — Pedidos urgentes',
      channelDescription:
          'Notificação prioritária com som para novos pedidos',
      importance: Importance.max,
      priority: Priority.max,
      category: AndroidNotificationCategory.call,
      fullScreenIntent: true,
      playSound: true,
      sound: RawResourceAndroidNotificationSound('bora_alert'),
      enableVibration: true,
      visibility: fln.NotificationVisibility.public,
      autoCancel: false,
      ongoing: true,
      ticker: 'Novo pedido Bora',
      actions: <AndroidNotificationAction>[
        AndroidNotificationAction('accept_order', '✅ Aceitar',
            showsUserInterface: false, cancelNotification: true),
        AndroidNotificationAction('reject_order', '❌ Rejeitar',
            showsUserInterface: false, cancelNotification: true),
      ],
    );
    await plugin.show(
      orderId.hashCode,
      '🛵 Novo pedido!',
      notifBody,
      const NotificationDetails(android: androidDetails),
      payload: jsonEncode({
        'type': 'new_order_offer',
        'orderId': orderId,
        'vendorName': vendorName,
        'total': total,
        'distanceKm': distanceKm,
        'driverEarnings': driverEarnings,
      }),
    );
    debugPrint('[FCM BG] fullScreenIntent notif shown order=$orderId');
  } catch (e) {
    debugPrint('[FCM BG] local notif error: $e');
  }

  // ── 1.5) Bridge SharedPreferences → FGS onRepeatEvent ────────────────────
  // O BG handler NÃO pode chamar MethodChannels (overlay), mas PODE escrever
  // em SharedPreferences. O FGS onRepeatEvent lê este valor e chama
  // sendDataToMain, que dispara showDriverOfferOverlay no main isolate.
  try {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('pending_offer', jsonEncode({
      'type': 'new_order_offer',
      'orderId': orderId,
      'vendorName': vendorName,
      'total': total,
      'distanceKm': distanceKm,
      'driverEarnings': driverEarnings,
    }));
    debugPrint('[FCM BG] pending_offer saved SharedPrefs order=$orderId');
  } catch (e) {
    debugPrint('[FCM BG] SharedPrefs bridge error: $e');
  }

  // ── 2) Ponte FCM→FGS→main para overlay SYSTEM_ALERT_WINDOW ─────────────
  try {
    if (await FlutterForegroundTask.isRunningService) {
      FlutterForegroundTask.sendDataToTask(<String, String>{
        'type': 'new_order_offer',
        'orderId': orderId,
        'vendorName': vendorName,
        'total': total,
        'distanceKm': distanceKm,
        'driverEarnings': driverEarnings,
      });
      debugPrint('[FCM BG] forwarded to FGS task (order=$orderId)');
    } else {
      debugPrint('[FCM BG] FGS not running — overlay bridge skipped');
    }
  } catch (e) {
    debugPrint('[FCM BG] bridge error: $e');
  }

  // Exec3 PIVOT (2026-05-24): removido fast-path `fow.FlutterOverlayWindow
  // .shareData` daqui. O overlay-por-cima foi DEMOVIDO do fluxo de background
  // — Android 14+/16 bloqueia draw a partir do bg isolate quando MainActivity
  // invisível. A notif local fullScreenIntent acima (canal v3) acorda o ecrã
  // + lança MainActivity (showWhenLocked); o realtime entrega a oferta ao
  // OrderStore que empurra o `DriverFullScreenOfferDialog`. Som: SOLE source
  // = canal da notif (bora_alert), evitando duplicação com SoundService.
}

/// Tap na notificação local enquanto app em foreground ou background.
/// Traz a app para o primeiro plano — driver home screen já mostra o card
/// de aceitar/rejeitar via Realtime.
void _onLocalNotifTap(NotificationResponse response) {
  FlutterForegroundTask.launchApp('/');
}

/// Acção nos botões da notificação quando app em background/terminada.
/// Executa aceitar/rejeitar sem abrir a app (raw HTTP — sem Supabase client).
@pragma('vm:entry-point')
Future<void> onBackgroundNotificationAction(NotificationResponse response) async {
  final actionId = response.actionId;
  final payload = response.payload;
  if (actionId == null || payload == null) return;
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
      await http
          .patch(
            Uri.parse('$supabaseUrl/rest/v1/orders?id=eq.$orderId'),
            headers: headers,
            body: jsonEncode({'status': 'preparing'}),
          )
          .timeout(const Duration(seconds: 5));
      debugPrint('[NOTIF ACTION] accept_partner_order OK order=$orderId');
    } else if (actionId == 'reject_partner_order') {
      await http
          .patch(
            Uri.parse('$supabaseUrl/rest/v1/orders?id=eq.$orderId'),
            headers: headers,
            body: jsonEncode({'status': 'rejected'}),
          )
          .timeout(const Duration(seconds: 5));
      debugPrint('[NOTIF ACTION] reject_partner_order OK order=$orderId');
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
  // 2026-05-21 — fecha também o ecrã CallKit (lockscreen) se ainda estiver
  // aberto. Idempotente: ConnectyCube ignora sessions inexistentes.
  try {
    await ConnectycubeFlutterCallKit.reportCallEnded(sessionId: orderId);
  } catch (e) {
    debugPrint('[NotificationService] callkit end error: $e');
  }
  // Também fecha o overlay system_alert_window (sessão 2026-05-21).
  try {
    final active = await fow.FlutterOverlayWindow.isActive();
    if (active) await fow.FlutterOverlayWindow.closeOverlay();
  } catch (_) {/* silent */}
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

    _initialized = true;
    debugPrint('[NotificationService] initialized.');
  }

  void _onForegroundTaskData(Object data) {
    if (data is! Map) return;
    final type = data['type']?.toString();
    if (type != 'new_order_offer') return;
    final orderId = data['orderId']?.toString() ?? '';
    if (orderId.isEmpty) return;
    // Exec3 PIVOT (2026-05-24): full-screen dialog em vez de overlay system_alert.
    showFullScreenOfferDialog(
      orderId: orderId,
      vendorName: data['vendorName']?.toString() ?? 'Novo pedido',
      total: data['total']?.toString() ?? '0.00',
      distanceKm: data['distanceKm']?.toString() ?? '0',
      driverEarnings: data['driverEarnings']?.toString() ?? '0.00',
      dropoffAddress: data['dropoffAddress']?.toString() ?? '',
    ).ignore();
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
        await fow.FlutterOverlayWindow.updateFlag(fow.OverlayFlag.clickThrough);
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

  // ── Full-screen offer dialog (exec3 PIVOT, 2026-05-24) ─────────────────
  //
  // PIVOT: abandonámos overlay-por-cima-das-apps como caminho principal —
  // o Android 14+/16 bloqueia draw do bg isolate quando MainActivity
  // invisível. Adoptámos o modelo REAL do Uber/Glovo: a notif local com
  // fullScreenIntent acorda o ecrã + lança MainActivity (showWhenLocked +
  // turnScreenOn já no manifest). Quando o Flutter sobe, OrderStore vê o
  // realtime e empurra ESTE dialog full-screen.
  //
  // Dedup cross-path (FCM, realtime broadcast, FGS bridge) garantido pelo
  // mesmo `_lastShownOfferId` + janela 10s.
  Future<void> showFullScreenOfferDialog({
    required String orderId,
    String vendorName = 'Novo pedido',
    String total = '0.00',
    String distanceKm = '0',
    String driverEarnings = '0.00',
    String dropoffAddress = '',
  }) async {
    if (kIsWeb || orderId.isEmpty) return;
    // Dedup cross-path — janela 10s.
    final now = DateTime.now();
    if (_lastShownOfferId == orderId &&
        _lastShownOfferAt != null &&
        now.difference(_lastShownOfferAt!) < _offerDedupWindow) {
      debugPrint(
          '[NotificationService] showFullScreenOfferDialog: dedup HIT order=$orderId');
      return;
    }
    _lastShownOfferId = orderId;
    _lastShownOfferAt = now;
    final nav = navigatorKey.currentState;
    if (nav == null) {
      debugPrint(
          '[NotificationService] navigatorKey sem state — Flutter engine ainda a subir? order=$orderId');
      return;
    }
    // Push full-screen route. PopScope no widget impede dismiss por back —
    // só ACEITAR/REJEITAR/expirar fecham.
    await nav.push(
      MaterialPageRoute<void>(
        fullscreenDialog: true,
        builder: (_) => DriverFullScreenOfferDialog(
          orderId: orderId,
          vendorName: vendorName,
          total: total,
          distanceKm: distanceKm,
          driverEarnings: driverEarnings,
          dropoffAddress: dropoffAddress,
        ),
      ),
    );
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
      final alreadyActive = await fow.FlutterOverlayWindow.isActive();
      if (alreadyActive) {
        // Overlay em standby — activar (remover click-through) + enviar dados.
        await fow.FlutterOverlayWindow.updateFlag(fow.OverlayFlag.defaultFlag);
        await fow.FlutterOverlayWindow.shareData(payload);
        debugPrint('[NotificationService] showDriverOfferOverlay: standby→active order=$orderId');
        return;
      }
      // Fallback: overlay não está activo (p.ex. driver foi online sem
      // initDriverStandbyOverlay ter sido chamado). Tenta showOverlay().
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
      await Future<void>.delayed(const Duration(milliseconds: 300));
      await fow.FlutterOverlayWindow.shareData(payload);
      debugPrint('[NotificationService] showDriverOfferOverlay: fallback shown order=$orderId');
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
