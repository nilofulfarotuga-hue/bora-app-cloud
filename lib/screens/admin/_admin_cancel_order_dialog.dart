import 'package:flutter/material.dart';

import '../../config/app_colors.dart';
import '../../config/app_spacing.dart';
import '../../services/admin/admin_order_service.dart';

/// Modal para o admin cancelar um pedido. Recolhe `reason_code` (dropdown
/// das 9 categorias canónicas) + `reason` livre (≥10 chars). Mostra banner
/// amarelo se a ordem está paga (refund automático será gerado).
///
/// Uso:
/// ```dart
/// final result = await showDialog<AdminCancelOrderResult>(
///   context: context,
///   builder: (_) => AdminCancelOrderDialog(order: order),
/// );
/// if (result != null) { /* refresh list */ }
/// ```
class AdminCancelOrderDialog extends StatefulWidget {
  const AdminCancelOrderDialog({super.key, required this.order});

  final Map<String, dynamic> order;

  @override
  State<AdminCancelOrderDialog> createState() => _AdminCancelOrderDialogState();
}

class _AdminCancelOrderDialogState extends State<AdminCancelOrderDialog> {
  static const _kReasonMinChars = 10;

  static const List<(String, String)> _reasonCodes = [
    ('client_request',     'Pedido do cliente'),
    ('partner_unable',     'Parceiro indisponível'),
    ('driver_unavailable', 'Entregador indisponível'),
    ('payment_failed',     'Pagamento falhou'),
    ('fraud_suspected',    'Suspeita de fraude'),
    ('system_error',       'Erro técnico'),
    ('address_invalid',    'Endereço inválida'),
    ('food_quality_issue', 'Problema de qualidade'),
    ('other',              'Outro'),
  ];

  String _code = 'client_request';
  final TextEditingController _reason = TextEditingController();
  bool _busy = false;

  @override
  void dispose() {
    _reason.dispose();
    super.dispose();
  }

  /// True se a ordem é card/mbway com pagamento confirmado e há
  /// payment_intent_id — i.e. a confirmação vai disparar refund Stripe.
  bool get _willRefund {
    final method = widget.order['payment_method'] as String?;
    final status = widget.order['payment_status'] as String?;
    final pi     = widget.order['payment_intent_id'] as String?;
    return (method == 'card' || method == 'mbway') &&
           status == 'paid' &&
           (pi != null && pi.isNotEmpty);
  }

  double get _total {
    final v = widget.order['total'] ?? widget.order['final_total'] ?? widget.order['price'];
    return (v is num) ? v.toDouble() : 0.0;
  }

  Future<void> _confirm() async {
    final reasonText = _reason.text.trim();
    if (reasonText.length < _kReasonMinChars) return;
    final orderId = widget.order['id'] as String?;
    if (orderId == null) return;

    setState(() => _busy = true);
    try {
      final result = await AdminOrderService().cancelOrder(
        orderId:    orderId,
        reasonCode: _code,
        reason:     reasonText,
      );
      if (!mounted) return;
      Navigator.of(context).pop(result);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(result.summary),
        backgroundColor: result.refundFailed ? AppColors.error : null,
        duration: const Duration(seconds: 5),
      ));
    } on AdminOrderException catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(e.message),
        backgroundColor: AppColors.error,
        duration: const Duration(seconds: 5),
      ));
    }
  }

  @override
  Widget build(BuildContext context) {
    final reasonOk = _reason.text.trim().length >= _kReasonMinChars;

    return AlertDialog(
      shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(Radii.lg)),
      title: const Text('Cancelar pedido'),
      content: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            DropdownButtonFormField<String>(
              value: _code,
              decoration: const InputDecoration(labelText: 'Categoria'),
              items: _reasonCodes
                  .map((c) => DropdownMenuItem(value: c.$1, child: Text(c.$2)))
                  .toList(),
              onChanged: _busy ? null : (v) => setState(() => _code = v ?? 'other'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _reason,
              decoration: InputDecoration(
                labelText: 'Motivo (mínimo $_kReasonMinChars caracteres)',
                helperText: 'Visível em audit log. Cliente vê uma versão genérica.',
              ),
              minLines: 2,
              maxLines: 5,
              enabled: !_busy,
              onChanged: (_) => setState(() {}),
            ),
            if (_willRefund) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: AppColors.warning.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: AppColors.warning.withValues(alpha: 0.4)),
                ),
                child: Row(children: [
                  const Icon(Icons.warning_amber_rounded, color: AppColors.warning, size: 20),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Esta acção vai gerar um reembolso automático de '
                      '€${_total.toStringAsFixed(2)} via Stripe.',
                      style: const TextStyle(fontSize: 12),
                    ),
                  ),
                ]),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _busy ? null : () => Navigator.pop(context),
          child: const Text('Voltar'),
        ),
        ElevatedButton.icon(
          onPressed: (!reasonOk || _busy) ? null : _confirm,
          icon: _busy
              ? const SizedBox(
                  width: 16, height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
              : const Icon(Icons.cancel),
          label: Text(_busy ? 'A cancelar…' : 'Confirmar cancelamento'),
          style: ElevatedButton.styleFrom(backgroundColor: AppColors.error),
        ),
      ],
    );
  }
}
