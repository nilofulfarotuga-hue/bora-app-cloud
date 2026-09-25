import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../config/app_colors.dart';
import '../services/wallet_service.dart';

import '../l10n/tr.dart';

/// Diálogo apresentado ao cliente quando cancela um pedido com refund.
///
/// Padrão iFood: cliente escolhe **Cartão (5-10 dias)** ou **App (instantâneo
/// 80% saldo livre + 20% tokens)**. Decisão Danilo 2026-04-30.
///
/// Uso:
/// ```dart
/// final res = await showRefundChoiceDialog(
///   context,
///   orderId: order.id,
///   refundableEur: 8.50,
///   originalPaymentMethod: order.paymentMethod, // 'card' | 'mbway' | 'cash'
/// );
/// // res == null se utilizador cancelou
/// // res.refundMethod == 'stripe' | 'wallet'
/// ```
Future<RefundChoiceResult?> showRefundChoiceDialog(
  BuildContext context, {
  required String orderId,
  required double refundableEur,
  required String originalPaymentMethod,
}) {
  return showDialog<RefundChoiceResult>(
    context: context,
    builder: (_) => _RefundChoiceDialog(
      orderId: orderId,
      refundableEur: refundableEur,
      originalPaymentMethod: originalPaymentMethod,
    ),
  );
}

class RefundChoiceResult {
  final String refundMethod; // 'stripe' | 'wallet'
  final String reason;
  RefundChoiceResult({required this.refundMethod, required this.reason});
}

class _RefundChoiceDialog extends StatefulWidget {
  final String orderId;
  final double refundableEur;
  final String originalPaymentMethod;
  const _RefundChoiceDialog({
    required this.orderId,
    required this.refundableEur,
    required this.originalPaymentMethod,
  });

  @override
  State<_RefundChoiceDialog> createState() => _RefundChoiceDialogState();
}

class _RefundChoiceDialogState extends State<_RefundChoiceDialog> {
  String _method = 'wallet'; // default = app (mais valioso para retenção)
  final _reasonCtrl = TextEditingController();
  bool _submitting = false;
  String? _error;

  // Split preview (lê platform_settings.wallet_split_free_pct)
  double _splitFreePct = 0.80;

  @override
  void initState() {
    super.initState();
    _loadSettings();
    if (widget.originalPaymentMethod != 'card') {
      // Sem payment_intent → Stripe não disponível, força wallet
      _method = 'wallet';
    }
  }

  Future<void> _loadSettings() async {
    try {
      final supa = Supabase.instance.client;
      final pct = await supa.rpc('get_setting', params: {'p_key': 'wallet_split_free_pct'});
      if (!mounted) return;
      setState(() {
        if (pct != null) _splitFreePct = double.tryParse(pct.toString()) ?? 0.80;
      });
    } catch (_) {/* keeps defaults */}
  }

  @override
  void dispose() {
    _reasonCtrl.dispose();
    super.dispose();
  }

  ({int freeCents, int tokensCount, int tokensCents}) _previewSplit() {
    final totalCents = (widget.refundableEur * 100).round();
    final freeCents = (totalCents * _splitFreePct).round();
    final tokensCents = totalCents - freeCents;
    final tokensCount = tokensCents * 20; // = cents * 100 / 5
    return (freeCents: freeCents, tokensCount: tokensCount, tokensCents: tokensCents);
  }

  Future<void> _submit() async {
    final reason = _reasonCtrl.text.trim();
    if (reason.length < 3) {
      setState(() => _error = 'Indica um motivo (mínimo 3 caracteres)'.tr);
      return;
    }
    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      await WalletService.instance.cancelWithChoice(
        orderId: widget.orderId,
        reason: reason,
        refundMethod: _method,
      );
      if (mounted) {
        Navigator.of(context).pop(RefundChoiceResult(refundMethod: _method, reason: reason));
      }
    } catch (e) {
      if (mounted) {
        setState(() => _error = 'Não foi possível cancelar. Tenta de novo.'.tr);
      }
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final preview = _previewSplit();
    final canStripe = widget.originalPaymentMethod == 'card';

    return AlertDialog(
      title: Text('Como queres receber o reembolso de €{0}?'.trArgs([widget.refundableEur.toStringAsFixed(2).replaceAll('.', ',')])),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            RadioListTile<String>(
              value: 'stripe',
              groupValue: _method,
              onChanged: canStripe ? (v) => setState(() => _method = v!) : null,
              title: Text('Cartão'.tr),
              subtitle: Text(canStripe
                  ? 'Demora 5-10 dias úteis a aparecer no cartão.'.tr
                  : 'Indisponível — pedido não foi pago com cartão.'),
            ),
            RadioListTile<String>(
              value: 'wallet',
              groupValue: _method,
              onChanged: (v) => setState(() => _method = v!),
              title: Text('Saldo Bora — instantâneo'.tr),
              subtitle: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '€{0} saldo livre + {1} tokens (≈€{2})'.trArgs([(preview.freeCents / 100).toStringAsFixed(2).replaceAll('.', ','), preview.tokensCount, (preview.tokensCents / 100).toStringAsFixed(2).replaceAll('.', ',')]),
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Saldo livre nunca expira. Tokens dão até 50% desconto no checkout.'.tr,
                    style: const TextStyle(fontSize: 11, color: AppColors.textSecondary),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _reasonCtrl,
              maxLines: 3,
              decoration: InputDecoration(
                labelText: 'Motivo do cancelamento'.tr,
                border: const OutlineInputBorder(),
              ),
            ),
            if (_error != null) ...[
              const SizedBox(height: 8),
              Text(_error!, style: const TextStyle(color: AppColors.error)),
            ],
            const SizedBox(height: 8),
            Text(
              'Saldo não reembolsável em dinheiro.'.tr,
              style: const TextStyle(fontSize: 11, color: AppColors.textSubtle),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _submitting ? null : () => Navigator.pop(context),
          child: Text('Voltar'.tr),
        ),
        FilledButton(
          onPressed: _submitting ? null : _submit,
          child: _submitting
              ? const SizedBox(
                  width: 16, height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2))
              : Text('Confirmar'.tr),
        ),
      ],
    );
  }
}
