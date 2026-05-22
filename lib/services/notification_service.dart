import 'dart:async';
import 'dart:convert';

import 'package:connectycube_flutter_call_kit/connectycube_flutter_call_kit.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
// Alias para evitar colisão de `NotificationVisibility` com flutter_local_notifications.
import 'package:flutter_overlay_window/flutter_overlay_window.dart' as fow;
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/chat_message.dart';
import '../models/order_model.dart';
import '../screens/chat_screen.dart';
import '../screens/notifications_screen.dart';
import 'push_token_service.dart';
import 'sound_service.dart';

/// Background message handler — must be a top-level function (not a closure).
/// Called by FCM when a DATA-ONLY message arrives (sem campo `notification`)
/// e a app está em background OU terminada/fechada.
///
/// Sessão 2026-05-18 — estilo Uber/Glovo: a Edge Function notify-driver envia
/// apenas `data` para forçar este handler a correr. Aqui disparamos uma
/// notificação local com fullScreenIntent (acorda o ecrã), som bora_alert e
/// vibração agressiva — exactamente como Uber/Glovo fazem para que o estafeta
/// nunca perca uma oferta com o telemóvel bloqueado.
@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  // Firebase pode não estar inicializado neste isolate em background.
  try {
    await Firebase.initializeApp();
  } catch (_) {
    // already initialized
  }

  final data = message.data;
  final type = data['type'];

  debugPrint('[NotificationService BG] data=$data');

  if (type != 'new_order_offer') return;

  final orderId = (data['orderId'] ?? '').toString();
  final title = (data['title'] ?? '🔔 Novo pedido!').toString();
  final body = (data['body'] ?? 'Novo pedido disponível').toString();

  // 2026-05-20 — estilo chamada (Uber/Glovo): notificação não dispensável,
  // som contínuo via FLAG_INSISTENT (=4), action buttons aceitar/rejeitar
  // que abrem o app no card da oferta. Auto-cancel acontece quando o
  // realtime detecta `current_driver_offer_id` revogado (ver OrderStore).
  final androidDetails = AndroidNotificationDetails(
    'bora_orders_urgent_v2',
    'Bora — Pedidos urgentes',
    channelDescription:
        'Notificações de novos pedidos (alta prioridade + som contínuo).',
    importance: Importance.max,
    priority: Priority.max,
    fullScreenIntent: true,
    playSound: true,
    sound: const RawResourceAndroidNotificationSound('bora_alert'),
    enableVibration: true,
    vibrationPattern: Int64List.fromList(<int>[0, 500, 200, 500, 200, 500]),
    category: AndroidNotificationCategory.call,
    visibility: NotificationVisibility.public,
    ticker: 'Novo pedido!',
    ongoing: true, // não dispensável por swipe (estilo chamada)
    autoCancel: true, // tap (body ou action) silencia + abre o app
    // FLAG_INSISTENT (=4) — Android toca o som em loop até o utilizador
    // interagir. É o que diferencia uma oferta de uma notificação normal.
    additionalFlags: Int32List.fromList(<int>[4]),
    actions: <AndroidNotificationAction>[
      const AndroidNotificationAction(
        'bora_offer_accept',
        '✅ Aceitar',
        showsUserInterface: true,
        cancelNotification: true,
      ),
      const AndroidNotificationAction(
        'bora_offer_reject',
        '❌ Rejeitar',
        showsUserInterface: true,
        cancelNotification: true,
      ),
    ],
  );

  final details = NotificationDetails(android: androidDetails);

  final plugin = FlutterLocalNotificationsPlugin();

  // Garante canal criado neste isolate (caso o handler corra antes do main).
  await plugin
      .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>()
      ?.createNotificationChannel(
        const AndroidNotificationChannel(
          'bora_orders_urgent_v2',
          'Bora — Pedidos urgentes',
          description:
              'Notificações de novos pedidos (alta prioridade + som).',
          importance: Importance.max,
          playSound: true,
          sound: RawResourceAndroidNotificationSound('bora_alert'),
          enableVibration: true,
          showBadge: true,
        ),
      );

  await plugin.show(
    orderId.hashCode,
    title,
    body,
    details,
    payload: jsonEncode(data),
  );

  // Sessão 2026-05-21 — Lockscreen CallKit (estilo chamada Uber/Glovo).
  // Quando o ecrã está bloqueado, flutter_overlay_window não atravessa o
  // lockscreen. CallKit usa CallActivity nativa (showWhenLocked + turnScreenOn)
  // que aparece estilo chamada entrante sobre o lockscreen. Aceitar abre o
  // app; rejeitar dispara onCallRejected → driver_reject_offer RPC.
  try {
    final vendorName = (data['vendorName'] ?? 'Pedido novo').toString();
    final callEvent = CallEvent(
      sessionId: orderId,
      callType: 1, // 1 = VIDEO (ecrã maior — mais visibilidade no lockscreen)
      callerId: 1,
      callerName: vendorName,
      opponentsIds: const <int>{1},
      callPhoto: '',
      userInfo: <String, String>{
        'order_id': orderId,
        'vendor_name': vendorName,
        'total': (data['total'] ?? '').toString(),
        'distance_km': (data['distanceKm'] ?? '').toString(),
        'driver_earnings': (data['driverEarnings'] ?? '').toString(),
      },
    );
    await ConnectycubeFlutterCallKit.showCallNotification(callEvent);
  } catch (e) {
    debugPrint('[NotificationService BG] callkit show error: $e');
  }

  // Sessão 2026-05-21 — Overlay system_alert_window por cima de outras apps.
  // Estilo Uber/Glovo: o estafeta vê o card mesmo se estiver noutra app.
  // Som contínuo + vibração ficam na local notification acima (que toca em
  // paralelo). Aqui é apenas a UI visual com botões aceitar/rejeitar.
  try {
    final granted = await fow.FlutterOverlayWindow.isPermissionGranted();
    if (!granted) return;
    final alreadyActive = await fow.FlutterOverlayWindow.isActive();
    if (alreadyActive) {
      // Já há um overlay aberto (oferta anterior em andamento) — apenas
      // actualiza os dados em vez de duplicar.
      await fow.FlutterOverlayWindow.shareData(<String, dynamic>{
        'orderId': orderId,
        'vendorName': data['vendorName'],
        'total': data['total'],
        'distanceKm': data['distanceKm'],
        'driverEarnings': data['driverEarnings'],
      });
      return;
    }
    await fow.FlutterOverlayWindow.showOverlay(
      enableDrag: false,
      overlayTitle: 'Novo pedido!',
      overlayContent: (data['vendorName'] ?? 'Pedido').toString(),
      flag: fow.OverlayFlag.defaultFlag,
      visibility: fow.NotificationVisibility.visibilityPublic,
      positionGravity: fow.PositionGravity.auto,
      height: 420,
      width: fow.WindowSize.matchParent,
    );
    // Pequeno delay para garantir que o isolate da overlay arrancou + se
    // subscreveu ao stream antes de enviarmos os dados.
    await Future<void>.delayed(const Duration(milliseconds: 300));
    await fow.FlutterOverlayWindow.shareData(<String, dynamic>{
      'orderId': orderId,
      'vendorName': data['vendorName'],
      'total': data['total'],
      'distanceKm': data['distanceKm'],
      'driverEarnings': data['driverEarnings'],
    });
  } catch (e) {
    debugPrint('[NotificationService BG] overlay show error: $e');
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
      final orderId = d['orderId']?.toString();
      if (action == null) return;
      debugPrint(
          '[NotificationService] overlay action=$action order=$orderId');
    });

    _initialized = true;
    debugPrint('[NotificationService] initialized.');
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
