import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Thin wrapper around Supabase Auth — single source of truth for the current
/// Supabase user identity (anonymous or authenticated).
class AuthService {
  final _supabase = Supabase.instance.client;

  User? get currentUser => _supabase.auth.currentUser;

  String? get userId => _supabase.auth.currentUser?.id;

  Stream<AuthState> get authStateChanges => _supabase.auth.onAuthStateChange;

  /// Ensures there is always a Supabase session. If none exists, creates an
  /// anonymous one so that every order can be linked to a stable user_id.
  Future<void> ensureSession() async {
    if (_supabase.auth.currentUser != null) return;
    try {
      await _supabase.auth.signInAnonymously();
    } catch (e) {
      // Non-fatal: orders will be created without a user_id.
      debugPrint('AuthService.ensureSession error => $e');
    }
  }
}
