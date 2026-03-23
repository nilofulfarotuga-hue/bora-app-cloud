import 'dart:convert';

// firebase_messaging temporarily disabled — requires google-services.json
// import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
// import 'package:supabase_flutter/supabase_flutter.dart'; // unused while FCM disabled
import 'sound_service.dart';

/// Wraps Firebase Cloud Messaging for BORA APP.
///
/// FCM token fetching is temporarily disabled (requires google-services.json).
/// HTTP notify methods (notifyDriversNewOrder, notifyClient) remain fully functional.
///
/// To re-enable FCM:
///   1. Add google-services.json to android/app/
///   2. Uncomment firebase_core and firebase_messaging in pubspec.yaml
///   3. Restore Firebase.initializeApp() in main.dart
///   4. Restore the full notification_service.dart from git history
class NotificationService {
  NotificationService._();
  static final NotificationService instance = NotificationService._();

  static const _baseUrl = String.fromEnvironment(
    'BACKEND_BASE_URL',
    defaultValue: 'http://localhost:3000',
  );

  // _supabase unused while FCM token persistence is disabled
  final _sound = SoundService();

  bool _initialized = false;

  // FCM token is null until Firebase is re-enabled.
  String? get fcmToken => null;

  // ── Lifecycle ─────────────────────────────────────────────────────────────

  Future<void> init() async {
    if (_initialized) return;
    if (kIsWeb) return;
    // Firebase.initializeApp() is disabled — nothing to initialise here.
    _initialized = true;
    debugPrint('NotificationService: FCM disabled (google-services.json missing). HTTP notify still active.');
  }

  // ── Token persistence ─────────────────────────────────────────────────────

  /// No-op while FCM is disabled.
  Future<void> saveTokenForDriver(String driverId) async {
    debugPrint('NotificationService.saveTokenForDriver: FCM disabled, skipping');
  }

  // ── Send helpers (HTTP → backend) ─────────────────────────────────────────

  Future<void> notifyDriversNewOrder({
    required String orderId,
    required String vendorName,
    required double total,
  }) async {
    await _post('/notify-drivers', {
      'orderId': orderId,
      'title': 'Novo pedido disponível',
      'body': '$vendorName • €${total.toStringAsFixed(2)}',
      'sound': 'bora_alert',
    });
  }

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
