import 'dart:convert';

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

import 'sound_service.dart';

/// Background handler — must be a top-level function.
@pragma('vm:entry-point')
Future<void> _firebaseBackgroundHandler(RemoteMessage message) async {
  // FCM delivers the notification + sound natively when the app is in
  // background/terminated. No extra work needed here.
  debugPrint('NotificationService background: ${message.messageId}');
}

/// Wraps Firebase Cloud Messaging for BORA APP.
///
/// Usage:
///   await NotificationService.instance.init();
///
/// Native setup required (see README):
///   Android: google-services.json in android/app/
///            bora_alert.wav in android/app/src/main/res/raw/
///   iOS:     GoogleService-Info.plist in ios/Runner/
///            bora_alert.wav in ios/Runner/ (added to Runner target)
class NotificationService {
  NotificationService._();
  static final NotificationService instance = NotificationService._();

  /// Backend base URL — override via --dart-define=BACKEND_BASE_URL=...
  static const _baseUrl = String.fromEnvironment(
    'BACKEND_BASE_URL',
    defaultValue: 'http://localhost:3000',
  );

  final _supabase = Supabase.instance.client;
  final _sound = SoundService();

  bool _initialized = false;
  String? _fcmToken;

  String? get fcmToken => _fcmToken;

  // ── Lifecycle ─────────────────────────────────────────────────────────────

  Future<void> init() async {
    if (_initialized) return;
    if (kIsWeb) {
      debugPrint('NotificationService: FCM not supported on web — skipped');
      return;
    }
    try {
      FirebaseMessaging.onBackgroundMessage(_firebaseBackgroundHandler);
      await _requestPermission();
      _fcmToken = await FirebaseMessaging.instance.getToken();
      debugPrint('NotificationService: FCM token = $_fcmToken');

      // Keep token fresh across refreshes.
      FirebaseMessaging.instance.onTokenRefresh.listen((token) {
        _fcmToken = token;
        debugPrint('NotificationService: FCM token refreshed');
      });

      _listenForeground();
      _initialized = true;
    } catch (e) {
      // Non-fatal: app works without push notifications.
      debugPrint('NotificationService.init error => $e');
    }
  }

  Future<void> _requestPermission() async {
    final settings = await FirebaseMessaging.instance.requestPermission(
      alert: true,
      badge: true,
      sound: true,
    );
    debugPrint(
        'NotificationService: permission = ${settings.authorizationStatus}');
  }

  /// When app is in foreground FCM does NOT play sound automatically.
  /// This listener plays bora_alert.wav manually via audioplayers.
  void _listenForeground() {
    FirebaseMessaging.onMessage.listen((RemoteMessage message) {
      debugPrint(
          'NotificationService: foreground message ${message.notification?.title}');
      _sound.playOnce();
    });
  }

  // ── Token persistence ─────────────────────────────────────────────────────

  /// Persists the current FCM token to `drivers.fcm_token` for [driverId].
  /// Call after successful driver login.
  Future<void> saveTokenForDriver(String driverId) async {
    if (_fcmToken == null) return;
    try {
      await _supabase
          .from('drivers')
          .update({'fcm_token': _fcmToken})
          .eq('id', driverId);
      debugPrint('NotificationService: token saved for driver $driverId');
    } catch (e) {
      debugPrint('NotificationService.saveTokenForDriver error => $e');
    }
  }

  // ── Send helpers (call backend — backend holds the FCM server key) ─────────

  /// Notifies all online drivers that a new order is available.
  ///
  /// Backend endpoint: POST /notify-drivers
  /// Body: { orderId, title, body, sound }
  Future<void> notifyDriversNewOrder({
    required String orderId,
    required String vendorName,
    required double total,
  }) async {
    await _post('/notify-drivers', {
      'orderId': orderId,
      'title': 'Novo pedido disponível 🛵',
      'body': '$vendorName • €${total.toStringAsFixed(2)}',
      'sound': 'bora_alert',
    });
  }

  /// Sends a push notification to a specific client identified by phone.
  ///
  /// Backend endpoint: POST /notify-client
  /// Body: { clientPhone, title, body, sound }
  Future<void> notifyClient({
    required String clientPhone,
    required String title,
    required String body,
  }) async {
    await _post('/notify-client', {
      'clientPhone': clientPhone,
      'title': title,
      'body': body,
      'sound': 'bora_alert',
    });
  }

  Future<void> _post(String path, Map<String, dynamic> payload) async {
    try {
      await http.post(
        Uri.parse('$_baseUrl$path'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode(payload),
      );
    } catch (e) {
      debugPrint('NotificationService._post($path) error => $e');
    }
  }

  // ── Dispose ───────────────────────────────────────────────────────────────

  void dispose() {
    _sound.dispose();
  }
}
