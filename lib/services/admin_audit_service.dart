import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Records administrative actions in `public.admin_audit_log` via the
/// `log_admin_action` SECURITY DEFINER RPC (migration
/// `20260428000000_admin_audit_log.sql`).
///
/// Design rules:
/// - **Never break UX.** Audit logging is always best-effort: if the RPC
///   fails (network, RLS, etc.) we swallow the error and `debugPrint` it.
///   The caller's flow MUST continue regardless.
/// - **Server reads identity.** `admin_id` and `admin_email` come from
///   `auth.uid()` / `auth.jwt()` server-side — clients cannot spoof them.
/// - **Append-only.** No update / delete API exposed.
///
/// Action naming convention: `<entity>_<verb>` lowercase snake_case.
/// Examples: `partner_toggle`, `driver_approve`, `driver_ban`, `order_cancel`,
/// `order_refund`, `tokens_adjust`.
class AdminAuditService {
  const AdminAuditService._();

  /// Logs an administrative action. Never throws.
  ///
  /// Returns the new log row's `id` on success, or `null` if logging failed.
  /// Callers should treat `null` as a soft failure and continue normally.
  ///
  /// - [action]      Required. Snake_case verb describing what happened
  ///                 (e.g. `partner_toggle`).
  /// - [entityType]  Optional. The kind of thing acted upon (e.g.
  ///                 `restaurant`, `driver`, `order`, `user`).
  /// - [entityId]    Optional. UUID of the entity. Pass `null` for
  ///                 entities with non-UUID PKs (e.g. `restaurants.id` is
  ///                 `text`) — put the textual id inside [details] instead.
  /// - [details]     Optional. Arbitrary JSON-serialisable payload (e.g.
  ///                 `{old: false, new: true}` for a toggle). Keep small.
  static Future<String?> logAction({
    required String action,
    String? entityType,
    String? entityId,
    Map<String, dynamic>? details,
  }) async {
    try {
      final response = await Supabase.instance.client.rpc(
        'log_admin_action',
        params: <String, dynamic>{
          'p_action': action,
          'p_entity_type': entityType,
          'p_entity_id': entityId,
          'p_details': details ?? <String, dynamic>{},
        },
      );

      // RPC returns the inserted row's UUID as a scalar.
      if (response is String) return response;
      return response?.toString();
    } catch (e, st) {
      // Best-effort logging; never propagate to the UI layer.
      debugPrint('[AdminAuditService] logAction("$action") failed: $e');
      assert(() {
        debugPrintStack(stackTrace: st);
        return true;
      }());
      return null;
    }
  }
}
