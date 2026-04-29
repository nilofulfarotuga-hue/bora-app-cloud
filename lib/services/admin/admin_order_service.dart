import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Thrown by [AdminOrderService] when the admin-cancel-order Edge Function
/// fails. Carries the canonical [code] (parsed from the server response or
/// HTTP status) and a Portuguese [message] for direct display in a snackbar.
class AdminOrderException implements Exception {
  AdminOrderException({
    required this.code,
    required this.message,
    this.cause,
  });

  final String code;
  final String message;
  final Object? cause;

  @override
  String toString() => 'AdminOrderException($code): $message';
}

/// Outcome of a successful [AdminOrderService.cancelOrder] call. The
/// [summary] is a one-line PT message ready for a toast.
class AdminCancelOrderResult {
  AdminCancelOrderResult({
    required this.success,
    required this.idempotent,
    required this.previousStatus,
    required this.refundResult,
    required this.refundAmount,
    required this.refundStripeId,
    required this.refundError,
    required this.notifications,
    required this.summary,
    required this.raw,
  });

  final bool success;
  final bool idempotent;
  final String? previousStatus;
  final String? refundResult; // succeeded / failed / skipped / not_applicable
  final double? refundAmount;
  final String? refundStripeId;
  final String? refundError;
  final Map<String, dynamic> notifications;
  final String summary;
  final Map<String, dynamic> raw;

  bool get refundSucceeded => refundResult == 'succeeded';
  bool get refundFailed    => refundResult == 'failed';
  bool get refundSkipped   => refundResult == 'skipped';
  bool get refundNotApplicable => refundResult == 'not_applicable';
}

/// Client wrapper around the FASE 4 BUG 3 admin-cancel-order Edge Function.
class AdminOrderService {
  AdminOrderService({SupabaseClient? client})
      : _client = client ?? Supabase.instance.client;

  final SupabaseClient _client;

  /// Cancels an order via the admin-cancel-order Edge Function. Throws
  /// [AdminOrderException] on any failure path (HTTP error, RPC error,
  /// validation error). Returns [AdminCancelOrderResult] on success
  /// (including idempotent paths).
  Future<AdminCancelOrderResult> cancelOrder({
    required String orderId,
    required String reasonCode, // ENUM cancellation_reason_code as string
    required String reason,
  }) async {
    try {
      final response = await _client.functions.invoke(
        'admin-cancel-order',
        body: <String, dynamic>{
          'order_id': orderId,
          'reason_code': reasonCode,
          'reason': reason,
        },
      );

      final body = response.data;
      if (body is! Map<String, dynamic>) {
        throw AdminOrderException(
          code: 'invalid_response',
          message: 'Resposta inesperada do servidor.',
        );
      }

      // Edge Function returns {error:'…'} with non-2xx OR {success:true,…}.
      if (response.status >= 400 || body['error'] != null) {
        final code = (body['error'] ?? 'http_${response.status}').toString();
        final detail = body['detail']?.toString();
        throw AdminOrderException(
          code: code,
          message: _humanizeError(code, response.status, detail),
        );
      }

      if (body['success'] != true) {
        throw AdminOrderException(
          code: 'unexpected',
          message: 'Resposta sem success do servidor.',
        );
      }

      final idempotent = body['idempotent'] == true;
      final refund = (body['refund'] as Map?)?.cast<String, dynamic>();
      final notifications = (body['notifications'] as Map?)?.cast<String, dynamic>() ?? <String, dynamic>{};

      final refundResult = refund?['result'] as String?;
      final refundAmount = (refund?['amount'] as num?)?.toDouble();
      final refundStripeId = refund?['stripe_id'] as String?;
      final refundError = refund?['error'] as String?;

      return AdminCancelOrderResult(
        success: true,
        idempotent: idempotent,
        previousStatus: body['previous_status'] as String?,
        refundResult: refundResult,
        refundAmount: refundAmount,
        refundStripeId: refundStripeId,
        refundError: refundError,
        notifications: notifications,
        summary: _buildSummary(idempotent, refundResult, refundAmount, refundError, notifications),
        raw: body,
      );
    } on AdminOrderException {
      rethrow;
    } catch (e) {
      debugPrint('[AdminOrderService] cancelOrder failed: $e');
      throw AdminOrderException(
        code: 'network',
        message: 'Falha de rede a cancelar pedido. Tenta de novo.',
        cause: e,
      );
    }
  }

  // ── Internals ───────────────────────────────────────────────────────────

  String _buildSummary(
    bool idempotent,
    String? refundResult,
    double? refundAmount,
    String? refundError,
    Map<String, dynamic> notifications,
  ) {
    if (idempotent) {
      return 'Pedido já tinha sido cancelado anteriormente — sem alteração.';
    }
    final notifyCount = notifications.values
        .whereType<Map>()
        .where((n) => n['ok'] == true)
        .length;
    final notifyTotal = notifications.length;
    final notifySuffix = notifyTotal > 0
        ? ' Notificações enviadas: $notifyCount/$notifyTotal.'
        : '';

    switch (refundResult) {
      case 'succeeded':
        final amt = refundAmount?.toStringAsFixed(2) ?? '?';
        return 'Pedido cancelado e reembolsado €$amt via Stripe.$notifySuffix';
      case 'failed':
        return 'Pedido cancelado mas refund FALHOU — verifica Stripe manualmente'
            '${refundError != null ? " ($refundError)" : ""}.$notifySuffix';
      case 'skipped':
        return 'Pedido cancelado. Refund já tinha sido feito previamente (skipped).$notifySuffix';
      case 'not_applicable':
        return 'Pedido cancelado (sem pagamento por reembolsar).$notifySuffix';
      default:
        return 'Pedido cancelado.$notifySuffix';
    }
  }

  String _humanizeError(String code, int status, String? detail) {
    switch (code) {
      case 'missing_token':
      case 'unauthorized':
        return 'Sessão de admin expirada. Faz login novamente.';
      case 'admin_required':
        return 'Sem permissões de admin para cancelar pedidos.';
      case 'invalid_body':
        return 'Pedido inválido — body malformado.';
      case 'invalid_order_id':
        return 'ID de pedido inválido.';
      case 'invalid_reason_code':
        return 'Categoria de cancelamento inválida.';
      case 'reason_required':
        return 'Tens de preencher o motivo (mínimo 3 caracteres).';
      case 'method_not_allowed':
        return 'Método HTTP inválido (interno).';
      case 'server_misconfigured':
        return 'Servidor mal configurado. Avisa o suporte.';
      case 'rpc_unexpected':
        return 'Resposta inesperada da base de dados.';
      case 'rpc_error':
        // detail vem do RAISE EXCEPTION da RPC — extrair mensagem PT
        if (detail != null) {
          if (detail.startsWith('order_not_found')) {
            return 'Pedido não encontrado. Refresca a lista.';
          }
          if (detail.startsWith('order_already_delivered')) {
            return 'Pedido já foi entregue — não pode ser cancelado.';
          }
          if (detail.startsWith('order_already_terminal')) {
            return 'Pedido já está num estado terminal (rejeitado).';
          }
          if (detail.startsWith('reason_required')) {
            return 'Tens de preencher o motivo (mínimo 3 caracteres).';
          }
          if (detail.startsWith('reason_code_required')) {
            return 'Escolhe a categoria do cancelamento.';
          }
          if (detail.startsWith('admin_required')) {
            return 'Sem permissões de admin (validação no servidor).';
          }
          return 'Erro do servidor: $detail';
        }
        return 'Erro do servidor (sem detalhe).';
      default:
        return 'Falha a cancelar pedido (HTTP $status, $code).';
    }
  }
}
