import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Single source of truth for "is the current user an admin?".
///
/// **UI gates only.** Server-side `admin_*` RPCs and RLS policies enforce
/// `app_metadata.role='admin'` (migration `20260428000005_admin_gate_app_metadata.sql`).
///
/// Lookup order (2-tier, fail-soft):
///   1. `app_metadata.role == 'admin'`        ← canonical, immutable by client
///   2. `user_metadata.bora_role == 'admin'`  ← legacy (UI fallback only,
///                                              warns to refresh session)
///
/// If both return null (claim missing — very old refresh token), the caller
/// can opt-in to a one-shot `auth.refreshSession()` via [refreshAndCheckIsAdmin].
class AuthAdminService {
  const AuthAdminService._();

  /// Returns true if the current Supabase session belongs to an admin.
  static bool isAdmin() {
    final user = Supabase.instance.client.auth.currentUser;
    if (user == null) return false;

    // Tier 1 — canonical: app_metadata.role
    final appRole = user.appMetadata['role'];
    if (appRole is String && appRole == 'admin') return true;

    // Tier 2 — legacy fallback: user_metadata.bora_role
    final userMetadata = user.userMetadata ?? <String, dynamic>{};
    final boraRole = userMetadata['bora_role'];
    if (boraRole is String && boraRole == 'admin') {
      debugPrint(
        '[AuthAdminService] tier-2 fallback: user_metadata.bora_role=admin '
        '(app_metadata.role missing). Consider signout+signin to refresh JWT.',
      );
      return true;
    }

    return false;
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
