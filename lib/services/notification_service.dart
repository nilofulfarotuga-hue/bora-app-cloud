import 'dart:convert';

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

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
///   • Handle foreground, background, and terminated notification events
///   • Provide HTTP helpers for legacy notify-drivers / notify-client endpoints
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
  String? _fcmToken;

  String? get fcmToken => _fcmToken;

  // ── Lifecycle ─────────────────────────────────────────────────────────────

  Future<void> init() async {
    if (_initialized) return;
    if (kIsWeb) return;

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
    final token = _fcmToken;
    if (token == null) {
      debugPrint('[NotificationService] saveTokenForDriver: no FCM token yet');
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

  // ── Send helpers (HTTP → Supabase Edge Functions) ─────────────────────────

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

  Future<void> _post(String functionName, Map<String, dynamic> payload) async {
    const supabaseUrl = 'https://ojykpzwqrtusfeakzrna.supabase.co';
    const anonKey =
        'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Im9qeWtwendxcnR1c2ZlYWt6cm5hIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzMwMDA3MjgsImV4cCI6MjA4ODU3NjcyOH0.-yrhHFZV4bfjBagI5W-c1AvmP8Xkzs1kf2xuxPwdBh4';
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
