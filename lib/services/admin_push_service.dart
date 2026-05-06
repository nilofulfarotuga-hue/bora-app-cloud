// 5F-β — AdminPushService
//
// Registers the current device's FCM token in `admin_push_tokens` so the
// trigger-driven `notify-admin-urgent` Edge Function can push to admin
// devices when a critical robot_crosstalk row is inserted.
//
// Reuses `NotificationService.instance.fcmToken` (singleton initialised in
// main.dart). Does NOT request permission again. Falls back to a fresh
// `FirebaseMessaging.getToken()` call if the singleton has no token yet.
//
// Idempotent: safe to call from `AdminDashboardScreen.initState()`. The
// token-refresh subscription is created at most once per app session.
//
// Deep link: tap on a `crosstalk_critical` push opens `/admin/crosstalk`
// (registered in main.dart as a named route).

import 'dart:async';
import 'dart:io' show Platform;

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'auth_admin_service.dart';
import 'notification_service.dart';

class AdminPushService {
  AdminPushService._();

  static StreamSubscription<String>? _refreshSub;
  static bool _deepLinksWired = false;
  static bool _registering = false;

  /// Registers the current FCM token in `admin_push_tokens` for the
  /// signed-in admin user. No-op for non-admin sessions or when no token
  /// is available.
  static Future<void> registerForAdmin() async {
    if (_registering) return;
    _registering = true;
    try {
      if (!AuthAdminService.isAdmin()) return;

      final messaging = FirebaseMessaging.instance;

      // Reuse the token already obtained by NotificationService in main()
      // when possible — avoids a second permission prompt / network round-trip.
      String? token = NotificationService.instance.fcmToken;
      token ??= await messaging.getToken();
      if (token == null || token.isEmpty) {
        debugPrint('[AdminPushService] no FCM token available — skipping');
        return;
      }

      await _registerRpc(token);

      // Wire token-refresh exactly once per session.
      _refreshSub ??= messaging.onTokenRefresh.listen((newToken) async {
        if (!AuthAdminService.isAdmin()) return;
        await _registerRpc(newToken);
      });
    } finally {
      _registering = false;
    }
  }

  static Future<void> _registerRpc(String token) async {
    try {
      await Supabase.instance.client.rpc(
        'admin_register_push_token',
        params: {
          'p_fcm_token':    token,
          'p_device_label': _deviceLabel(),
          'p_platform':     _platform(),
        },
      );
      debugPrint('[AdminPushService] FCM token registered for admin');
    } catch (e) {
      debugPrint('[AdminPushService] register failed: $e');
    }
  }

  /// Sets up listeners that route a `crosstalk_critical` push notification
  /// to `/admin/crosstalk` when the user taps it. Idempotent — calling
  /// multiple times during widget rebuilds is safe.
  static void setupDeepLinks(BuildContext context) {
    if (_deepLinksWired) return;
    _deepLinksWired = true;

    final navigator = Navigator.of(context);

    FirebaseMessaging.onMessageOpenedApp.listen((msg) {
      final type = msg.data['type'];
      if (type == 'crosstalk_critical') {
        navigator.pushNamed('/admin/crosstalk');
      }
    });

    // Cold-start: tap on push that launched the app.
    FirebaseMessaging.instance.getInitialMessage().then((msg) {
      if (msg == null) return;
      final type = msg.data['type'];
      if (type == 'crosstalk_critical') {
        navigator.pushNamed('/admin/crosstalk');
      }
    });
  }

  /// Best-effort device label without taking a `device_info_plus` dependency.
  static String? _deviceLabel() {
    if (kIsWeb) return 'web';
    try {
      return '${Platform.operatingSystem} ${Platform.operatingSystemVersion}';
    } catch (_) {
      return null;
    }
  }

  static String? _platform() {
    if (kIsWeb) return 'web';
    try {
      if (Platform.isAndroid) return 'android';
      if (Platform.isIOS) return 'ios';
    } catch (_) {/* fall through */}
    return null;
  }
}
