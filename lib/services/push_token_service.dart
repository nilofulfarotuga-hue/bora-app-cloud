// 5G — PushTokenService
//
// Multi-device FCM token registration (Decisão A).
// Registers the current FCM token in `client_push_tokens` or
// `driver_push_tokens` via the `register_push_token` RPC (UPSERT).
//
// NÃO substitui `NotificationService` legacy (que escreve em
// `users.fcm_token`, `drivers.fcm_token`, `restaurants.fcm_token`) — corre
// em paralelo durante a transição. Ambos são idempotentes.
//
// Multi-device: re-registo nunca apaga tokens antigos (cada device tem
// linha própria). Edge Fns enviam para TODOS os tokens activos do user.
//
// Decisão C: tokens inválidos (FCM 4xx UNREGISTERED/INVALID_ARGUMENT) são
// marcados active=false após fail_count>=3 via RPC mark_token_failed
// (chamada server-side pelas Edge Fns; nunca pelo cliente).

import 'dart:async';
import 'dart:io' show Platform;

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'notification_service.dart';

class PushTokenService {
  PushTokenService._();

  static StreamSubscription<String>? _refreshSub;
  static bool _registering = false;
  static String? _lastRegisteredToken;
  static String? _lastRegisteredRole;

  /// Registers the current device for the given [role] ('client' | 'driver').
  /// Idempotent: safe to call multiple times. Re-uses the FCM token from
  /// [NotificationService.instance.fcmToken] when available.
  ///
  /// Skips silently if:
  ///   • Not authenticated
  ///   • Role is not 'client' or 'driver'
  ///   • No FCM token available (e.g. iOS simulator, web)
  static Future<void> registerForRole(String role) async {
    if (_registering) return;
    if (role != 'client' && role != 'driver') {
      debugPrint('[PushTokenService] skip — invalid role: $role');
      return;
    }

    final client = Supabase.instance.client;
    if (client.auth.currentUser == null) {
      debugPrint('[PushTokenService] skip — not authenticated');
      return;
    }

    _registering = true;
    try {
      // Reuse existing token from NotificationService when possible.
      String? token = NotificationService.instance.fcmToken;
      if (token == null || token.isEmpty) {
        try {
          token = await FirebaseMessaging.instance.getToken();
        } catch (e) {
          debugPrint('[PushTokenService] getToken() failed: $e');
          return;
        }
      }
      if (token == null || token.isEmpty) {
        debugPrint('[PushTokenService] no FCM token available — skipping');
        return;
      }

      await _registerRpc(role: role, token: token);

      // Wire token-refresh exactly once per session, keyed by role.
      _refreshSub ??= FirebaseMessaging.instance.onTokenRefresh.listen(
        (newToken) async {
          final r = _lastRegisteredRole;
          if (r == null) return;
          await _registerRpc(role: r, token: newToken);
        },
      );
    } finally {
      _registering = false;
    }
  }

  static Future<void> _registerRpc({
    required String role,
    required String token,
  }) async {
    // Skip duplicate registration if same role+token within session.
    if (_lastRegisteredToken == token && _lastRegisteredRole == role) {
      return;
    }
    try {
      await Supabase.instance.client.rpc(
        'register_push_token',
        params: {
          'p_role':         role,
          'p_fcm_token':    token,
          'p_device_label': _deviceLabel(),
          'p_platform':     _platform(),
        },
      );
      _lastRegisteredToken = token;
      _lastRegisteredRole = role;
      debugPrint('[PushTokenService] ✓ token registered for $role');
    } catch (e) {
      debugPrint('[PushTokenService] register failed: $e');
    }
  }

  /// Decisão A — Multi-device: NÃO apaga tokens em logout. O token deste
  /// device continua activo para receber pushes futuros se o user
  /// re-autenticar. Tokens só ficam inactivos via mark_token_failed após
  /// 3 falhas FCM consecutivas.
  ///
  /// Esta função é um no-op explícito — exposta apenas por simetria com
  /// AdminPushService API. Reset local apenas.
  static void resetSessionState() {
    _lastRegisteredToken = null;
    _lastRegisteredRole = null;
  }

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
