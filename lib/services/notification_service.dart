import 'dart:convert';

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

import 'push_token_service.dart';
import 'sound_service.dart';

/// Background message handler — must be a top-level function (not a closure).
/// Called by FCM when a data message arrives and the app is terminated/background.
@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  debugPrint(
      '[NotificationService BG] ${message.notification?.title}: ${message.notification?.body}');
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
    FirebaseMessaging.onMessage.listen((RemoteMessage msg) {
      debugPrint(
        '[NotificationService FG] ${msg.notification?.title} — ${msg.notification?.body}',
      );
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

    _initialized = true;
    debugPrint('[NotificationService] initialized.');
  }

  // ── Token persistence ─────────────────────────────────────────────────────

  /// Saves the FCM token to `drivers.fcm_token` for the given [driverId].
  /// Call this after a driver successfully logs in.
  Future<void> saveTokenForDriver(String driverId) async {
    if (!_consentGranted) return;
    final token = _fcmToken;
    if (token == null) {
      debugPrint('[NotificationService] saveTokenForDriver: no FCM token yet');
      return;
    }
    _boundRole = 'driver';
    _boundId = driverId;

    // BUG 2 fix — multi-device PRIMEIRO (independente de drivers.update,
    // que pode falhar por RLS strict em drivers não-aprovados).
    PushTokenService.registerForRole('driver').ignore();

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

  /// Saves the FCM token to `restaurants.fcm_token` for the given [restaurantId].
  /// Call this after a partner successfully logs in.
  Future<void> saveTokenForPartner(String restaurantId) async {
    if (!_consentGranted) return;
    final token = _fcmToken;
    if (token == null) {
      debugPrint(
          '[NotificationService] saveTokenForPartner: no FCM token yet');
      return;
    }
    try {
      await Supabase.instance.client
          .from('restaurants')
          .update({'fcm_token': token}).eq('id', restaurantId);
      _boundRole = 'partner';
      _boundId = restaurantId;
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

  // ── Dispose ───────────────────────────────────────────────────────────────

  void dispose() {
    _sound.dispose();
  }
}
