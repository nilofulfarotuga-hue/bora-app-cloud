import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Thrown by [AdminDriverService] when an admin RPC / Edge Function fails.
/// Carries the canonical [code] (parsed from the server's `RAISE EXCEPTION`)
/// and a Portuguese [message] suitable for direct display in a toast/snackbar.
class AdminDriverException implements Exception {
  AdminDriverException({
    required this.code,
    required this.message,
    this.cause,
  });

  final String code;
  final String message;
  final Object? cause;

  @override
  String toString() => 'AdminDriverException($code): $message';
}

/// Client wrapper around the FASE 3 BUG 2 admin endpoints.
///
/// Endpoints:
///   - `admin_ban_driver`            → [banDriver]
///   - `admin_reactivate_driver`     → [reactivateDriver]
///   - `admin_update_driver`         → [updateDriver]
///   - `admin_soft_delete_driver`    → [softDeleteDriver]
///   - Edge Function `admin-force-driver-logout` → [forceLogout]
///
/// Every public method translates server-side errors into Portuguese and
/// throws [AdminDriverException]. Successful calls return the JSONB body
/// from the RPC as a `Map<String, dynamic>`.
class AdminDriverService {
  AdminDriverService({SupabaseClient? client})
      : _client = client ?? Supabase.instance.client;

  final SupabaseClient _client;

  // ── Public API ────────────────────────────────────────────────────────────

  /// Bans a driver. [bannedUntil] NULL = permanent; future timestamp =
  /// temporary suspension (auto-expires via `driver_effective_status`).
  Future<Map<String, dynamic>> banDriver({
    required String driverId,
    required String reasonCode, // ban_reason_code: fraud / misconduct / documents_invalid / inactivity / safety / other
    required String reason,
    DateTime? bannedUntil,
  }) async {
    return _callRpc('admin_ban_driver', <String, dynamic>{
      'p_driver_id': driverId,
      'p_reason_code': reasonCode,
      'p_reason': reason,
      'p_banned_until': bannedUntil?.toUtc().toIso8601String(),
    });
  }

  /// Clears ban / suspension / soft-delete state in one call.
  Future<Map<String, dynamic>> reactivateDriver({
    required String driverId,
    String? note,
  }) async {
    return _callRpc('admin_reactivate_driver', <String, dynamic>{
      'p_driver_id': driverId,
      'p_note': note,
    });
  }

  /// Whitelisted typed update. NULL parameter = no change.
  /// IBAN and NIF are flagged sensitive in the audit log (values redacted).
  Future<Map<String, dynamic>> updateDriver({
    required String driverId,
    required String reason,
    String? name,
    String? phone,
    String? vehicleType, // 'motorcycle' | 'car' | 'bicycle'
    String? licensePlate,
    String? iban,
    String? nif,
    String? vehicleColor, // TVDE — cor do carro (cartão do passageiro)
    String? vehicleMakeModel, // TVDE — marca/modelo
  }) async {
    return _callRpc('admin_update_driver', <String, dynamic>{
      'p_driver_id': driverId,
      'p_reason': reason,
      'p_name': name,
      'p_phone': phone,
      'p_vehicle_type': vehicleType,
      'p_license_plate': licensePlate,
      'p_iban': iban,
      'p_nif': nif,
      if (vehicleColor != null) 'p_vehicle_color': vehicleColor,
      if (vehicleMakeModel != null) 'p_vehicle_make_model': vehicleMakeModel,
    });
  }

  /// Soft-delete with three guards (active orders / non-zero balance /
  /// pending settlements). Throws with a user-readable message if any guard
  /// fails — message contains the offending count or amount.
  Future<Map<String, dynamic>> softDeleteDriver({
    required String driverId,
    required String reason,
  }) async {
    return _callRpc('admin_soft_delete_driver', <String, dynamic>{
      'p_driver_id': driverId,
      'p_reason': reason,
    });
  }

  /// Revokes ALL active sessions for the driver (Supabase auth admin SDK
  /// `signOut(user_id, 'global')`), clears `fcm_token`, sets `is_online=false`,
  /// stamps `last_forced_logout_*`, and writes the audit row.
  ///
  /// Routed through the Edge Function `admin-force-driver-logout` because
  /// session revocation requires the service-role admin SDK that the client
  /// must not hold.
  Future<Map<String, dynamic>> forceLogout({
    required String driverId,
    required String reason,
  }) async {
    try {
      final response = await _client.functions.invoke(
        'admin-force-driver-logout',
        body: <String, dynamic>{
          'driver_id': driverId,
          'reason': reason,
        },
      );

      final body = response.data;
      if (body is! Map<String, dynamic>) {
        throw AdminDriverException(
          code: 'invalid_response',
          message: 'Resposta inesperada do servidor.',
        );
      }
      // Edge Function returns {error:'…'} with non-2xx OR {success:true,…}.
      if (response.status >= 400 || body['error'] != null) {
        final code = (body['error'] ?? 'http_${response.status}').toString();
        throw AdminDriverException(
          code: code,
          message: _humanizeForceLogoutError(code, response.status),
        );
      }
      return body;
    } on AdminDriverException {
      rethrow;
    } catch (e) {
      debugPrint('[AdminDriverService] forceLogout failed: $e');
      throw AdminDriverException(
        code: 'network',
        message: 'Falha de rede a forçar logout. Tenta de novo.',
        cause: e,
      );
    }
  }

  // ── Internals ─────────────────────────────────────────────────────────────

  Future<Map<String, dynamic>> _callRpc(
    String fn,
    Map<String, dynamic> params,
  ) async {
    try {
      final response = await _client.rpc(fn, params: params);
      if (response is Map) {
        return Map<String, dynamic>.from(response);
      }
      throw AdminDriverException(
        code: 'invalid_response',
        message: 'Resposta inesperada do servidor ($fn).',
      );
    } on PostgrestException catch (e) {
      final parsed = _parsePgError(e.message);
      throw AdminDriverException(
        code: parsed.code,
        message: parsed.message,
        cause: e,
      );
    } catch (e) {
      debugPrint('[AdminDriverService] $fn failed: $e');
      throw AdminDriverException(
        code: 'network',
        message: 'Falha de rede ($fn). Tenta de novo.',
        cause: e,
      );
    }
  }

  /// Parses a `RAISE EXCEPTION` message and returns the canonical code +
  /// Portuguese message. Falls through to a generic server-error message.
  _ParsedError _parsePgError(String raw) {
    final msg = raw.trim();

    // ── Hard guards (admin_soft_delete_driver) ──────────────────────────────
    // These come VERBATIM from the server (already user-readable English with
    // numbers); we translate to PT.
    final activeOrders = RegExp(r'^Cannot delete: driver has (\d+) active order')
        .firstMatch(msg);
    if (activeOrders != null) {
      final n = activeOrders.group(1);
      return _ParsedError(
        'driver_has_active_orders',
        'Não é possível remover: este estafeta tem $n entrega(s) activa(s). '
        'Aguarda que termine ou re-atribui.',
      );
    }
    final balance = RegExp(r'^Cannot delete: driver has non-zero balance of EUR (\S+)')
        .firstMatch(msg);
    if (balance != null) {
      return _ParsedError(
        'driver_balance_not_zero',
        'Não é possível remover: o estafeta tem saldo de €${balance.group(1)} '
        'por liquidar.',
      );
    }
    final pending = RegExp(r'^Cannot delete: driver has (\d+) pending cash settlement')
        .firstMatch(msg);
    if (pending != null) {
      return _ParsedError(
        'driver_pending_settlements',
        'Não é possível remover: existem ${pending.group(1)} liquidações '
        'pendentes deste estafeta.',
      );
    }

    // ── Codes prefixed `code: detail` ──────────────────────────────────────
    if (msg.startsWith('admin_required')) {
      return const _ParsedError('admin_required',
          'Sem permissões de admin para esta acção.');
    }
    if (msg.startsWith('driver_not_found')) {
      return const _ParsedError('driver_not_found',
          'Estafeta não encontrado. Refresca a lista.');
    }
    if (msg.startsWith('driver_already_banned')) {
      return const _ParsedError('driver_already_banned',
          'Este estafeta já está banido. Reactiva primeiro para alterar.');
    }
    if (msg.startsWith('driver_already_active')) {
      return const _ParsedError('driver_already_active',
          'Este estafeta já está activo — não tem ban nem soft-delete para limpar.');
    }
    if (msg.startsWith('driver_already_deleted')) {
      return const _ParsedError('driver_already_deleted',
          'Este estafeta já foi removido. Reactiva se necessário.');
    }
    if (msg.startsWith('driver_deleted')) {
      return const _ParsedError('driver_deleted',
          'Estafeta removido. Reactiva primeiro para esta acção.');
    }
    if (msg.startsWith('reason_required')) {
      return const _ParsedError('reason_required',
          'Tens de preencher o motivo (mínimo 3 caracteres).');
    }
    if (msg.startsWith('reason_code_required')) {
      return const _ParsedError('reason_code_required',
          'Escolhe a categoria do ban.');
    }
    if (msg.startsWith('banned_until_in_past')) {
      return const _ParsedError('banned_until_in_past',
          'A data fim da suspensão tem de ser no futuro.');
    }
    if (msg.startsWith('invalid_vehicle_type')) {
      return const _ParsedError('invalid_vehicle_type',
          'Tipo de veículo inválido. Permitidos: motociclo, carro, bicicleta.');
    }
    if (msg.startsWith('no_changes')) {
      return const _ParsedError('no_changes',
          'Nada para alterar — todos os valores são iguais aos actuais.');
    }
    if (msg.startsWith('justification_required')) {
      return const _ParsedError('justification_required',
          'Tens de preencher a justificação (mínimo 3 caracteres).');
    }
    if (msg.startsWith('missing_docs:')) {
      return _ParsedError('missing_docs',
          'Documentos em falta: ${msg.substring("missing_docs:".length).trim()}');
    }
    return _ParsedError('server_error', 'Erro do servidor: $msg');
  }

  String _humanizeForceLogoutError(String code, int status) {
    switch (code) {
      case 'missing_token':
      case 'unauthorized':
        return 'Sessão de admin expirada. Faz login novamente.';
      case 'admin_required':
        return 'Sem permissões de admin para forçar logout.';
      case 'invalid_driver_id':
      case 'invalid_body':
        return 'Pedido inválido. Refresca a lista e tenta de novo.';
      case 'driver_not_found':
        return 'Estafeta não encontrado.';
      case 'method_not_allowed':
        return 'Método HTTP inválido (interno).';
      case 'lookup_failed':
      case 'update_failed':
      case 'server_misconfigured':
        return 'Erro do servidor a forçar logout. Tenta de novo em segundos.';
      default:
        return 'Falha a forçar logout (HTTP $status, $code).';
    }
  }
}

class _ParsedError {
  const _ParsedError(this.code, this.message);
  final String code;
  final String message;
}
