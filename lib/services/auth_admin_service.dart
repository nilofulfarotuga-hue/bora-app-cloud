import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Single source of truth for "is the current user an admin?".
///
/// **UI gates only.** Server-side `admin_*` RPCs and RLS policies enforce
/// `app_metadata.role='admin'` (migration `20260428000005_admin_gate_app_metadata.sql`).
///
/// Só `app_metadata.role == 'admin'` conta (o utilizador não o pode escrever).
/// O `user_metadata.bora_role` é editável pelo próprio utilizador com
/// `auth.updateUser`, por isso deixou de abrir o painel (checkup 15/11/2026,
/// e2e fora-de-scope-admin-user-metadata). O único admin real tem o
/// `app_metadata.role` (SELECT a auth.users, 15/11).
///
/// If the claim is missing ( — very old refresh token), the caller
/// can opt-in to a one-shot `auth.refreshSession()` via [refreshAndCheckIsAdmin].
class AuthAdminService {
  const AuthAdminService._();

  /// Returns true if the current Supabase session belongs to an admin.
  static bool isAdmin() {
    final user = Supabase.instance.client.auth.currentUser;
    if (user == null) return false;

    // Tier 1 — canonical: app_metadata.role
    final appRole = user.appMetadata['role'];
    return appRole is String && appRole == 'admin';
  }

  /// Forces a JWT refresh, then checks isAdmin again. Use this when the
  /// claim might be missing AND we suspect the session is stale.
  static Future<bool> refreshAndCheckIsAdmin() async {
    if (isAdmin()) return true;
    try {
      await Supabase.instance.client.auth.refreshSession();
    } catch (e) {
      debugPrint('[AuthAdminService] refreshSession failed: $e');
    }
    return isAdmin();
  }
}
