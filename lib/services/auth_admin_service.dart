import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Single source of truth for "is the current user an admin?".
///
/// **UI gates only.** Server-side `admin_*` RPCs and RLS policies are
/// strict on `app_metadata.role='admin'` (see migration
/// `20260428000005_admin_gate_app_metadata.sql`). This helper is more
/// permissive on purpose so a legacy session or a transient claim
/// problem doesn't lock the admin out of the UI — but any *action*
/// still has to pass the strict server check.
///
/// Lookup order (3-tier, fail-soft):
///   1. `app_metadata.role == 'admin'`     ← canonical, immutable by client
///   2. `user_metadata.bora_role == 'admin'` ← Phase-1 legacy (UI fallback only)
///   3. Email allowlist                    ← deprecated, debugPrint warning
///
/// If 1 and 2 return null (claim missing — happens with very old refresh
/// tokens), the caller can opt-in to a one-shot `auth.refreshSession()`
/// before falling back to email via [refreshAndCheckIsAdmin].
///
/// Telemetry: every fallback to tier 2 or tier 3 emits a debugPrint so
/// we can confirm "0 hits" before removing the fallback in a future
/// version.
class AuthAdminService {
  const AuthAdminService._();

  /// Hardcoded fallback emails. Roadmap: remove after X weeks of stable
  /// telemetry confirming no path hits tier 3.
  static const _kDeprecatedEmailAllowlist = <String>{
    'nilofulfarotuga@gmail.com',
    'nilofulfaro@gmail.com',
  };

  /// Returns true if the current Supabase session belongs to an admin.
  ///
  /// Synchronous — reads from the cached session in memory. If the
  /// session is stale (claim missing despite the user being admin in
  /// the DB), call [refreshAndCheckIsAdmin] instead.
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

    // Tier 3 — deprecated email allowlist
    final email = user.email;
    if (email != null && _kDeprecatedEmailAllowlist.contains(email)) {
      debugPrint(
        '[AuthAdminService] DEPRECATED tier-3 fallback: admin granted via '
        'email allowlist for "$email". JWT lacked both app_metadata.role and '
        'user_metadata.bora_role. Server-side actions will FAIL because the '
        'server enforces app_metadata.role only.',
      );
      return true;
    }

    return false;
  }

  /// Forces a JWT refresh, then checks isAdmin again. Use this when the
  /// claim might be missing AND we suspect the session is stale (e.g.
  /// refresh token issued before the migration).
  ///
  /// Returns true if either pre-refresh or post-refresh check succeeds.
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
