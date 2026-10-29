import 'package:flutter/material.dart';
import '../config/app_colors.dart';
import '../services/wallet_service.dart';

import '../l10n/tr.dart';

/// Diálogo apresentado ao cliente quando cancela um pedido PAGO (MB Way ou
/// cartão) e há dinheiro a devolver.
///
/// Regra do Danilo (29/10/2026, adendo 3 da missão publica-2026-10-29): o
/// cliente ESCOLHE sempre, com duas opções grandes e claras, nenhuma marcada
/// à partida:
///   1) Carteira Bora — fica já disponível (100% em saldo);
///   2) Devolver para a minha conta — MB Way (normalmente na hora) ou cartão
///      (5 a 10 dias úteis).
/// O valor é igual nas duas (sem 80/20). Se o pedido usou tokens, os tokens
/// voltam como tokens. Pedido a dinheiro ou por pagar: não há escolha (o
/// ecrã do pedido não abre este diálogo). A conta é do servidor
/// (cancel-order-with-choice); aqui só se escolhe.
///
/// Uso:
/// ```dart
/// final res = await showRefundChoiceDialog(
///   context,
///   orderId: order.id,
///   refundableEur: 8.50,
///   originalPaymentMethod: order.paymentMethod.name, // 'card' | 'mbway'
///   tokensEur: order.tokensAppliedValueCents / 100,
/// );
/// // res == null se o utilizador voltou atrás
/// // res.refundMethod == 'stripe' | 'wallet'
/// ```
Future<RefundChoiceResult?> showRefundChoiceDialog(
  BuildContext context, {
  required String orderId,
  required double refundableEur,
  required String originalPaymentMethod,
  double tokensEur = 0,
  CancelarComEscolha? cancelar,
}) {
  return showDialog<RefundChoiceResult>(
    context: context,
    builder: (_) => RefundChoiceDialog(
      orderId: orderId,
      refundableEur: refundableEur,
      originalPaymentMethod: originalPaymentMethod,
      tokensEur: tokensEur,
      cancelar: cancelar,
    ),
  );
}

/// Quem faz o cancelamento no servidor (por defeito o WalletService; nos
/// testes, uma função falsa).
typedef CancelarComEscolha = Future<void> Function({
  required String orderId,
  required String reason,
  required String refundMethod,
});

class RefundChoiceResult {
  final String refundMethod; // 'stripe' | 'wallet'
  final String reason;
  RefundChoiceResult({required this.refundMethod, required this.reason});
}

/// Há escolha de reembolso a fazer? Só quando o pedido foi pago por MB Way
/// ou cartão e já está pago. A dinheiro (ou por pagar) não há nada a devolver.
bool escolhaDeReembolsoNecessaria({
  required String paymentMethod,
  required bool pago,
}) {
  return pago && (paymentMethod == 'card' || paymentMethod == 'mbway');
}

/// Texto do prazo da devolução ao meio original, conforme o meio.
String prazoDevolucaoAoMeio(String paymentMethod) {
  if (paymentMethod == 'mbway') {
    return 'MB Way: chega normalmente na hora.'.tr;
  }
  return 'Cartão: 5 a 10 dias úteis.'.tr;
}

String _eur(double v) => v.toStringAsFixed(2).replaceAll('.', ',');

class RefundChoiceDialog extends StatefulWidget {
  final String orderId;
  final double refundableEur;
  final String originalPaymentMethod;
  final double tokensEur;
  final CancelarComEscolha? cancelar;
  const RefundChoiceDialog({
    super.key,
    required this.orderId,
    required this.refundableEur,
    required this.originalPaymentMethod,
    this.tokensEur = 0,
    this.cancelar,
  });

  @override
  State<RefundChoiceDialog> createState() => _RefundChoiceDialogState();
}

class _RefundChoiceDialogState extends State<RefundChoiceDialog> {
  String? _method; // nenhuma opção marcada à partida (regra do Danilo)
  final _reasonCtrl = TextEditingController();
  bool _submitting = false;
  String? _error;

  @override
  void dispose() {
    _reasonCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final method = _method;
    if (method == null) return;
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
      final cancelar = widget.cancelar ??
          ({required orderId, required reason, required refundMethod}) =>
              WalletService.instance.cancelWithChoice(
                orderId: orderId,
                reason: reason,
                refundMethod: refundMethod,
              );
      await cancelar(
        orderId: widget.orderId,
        reason: reason,
        refundMethod: method,
      );
      if (mounted) {
        Navigator.of(context)
            .pop(RefundChoiceResult(refundMethod: method, reason: reason));
      }
    } catch (e) {
      if (mounted) {
        setState(() => _error = 'Não foi possível cancelar. Tenta de novo.'.tr);
      }
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  Widget _opcao({
    required String value,
    required IconData icon,
    required String titulo,
    required String detalhe,
  }) {
    final selecionada = _method == value;
    final cor = Theme.of(context).colorScheme.primary;
    return Semantics(
      button: true,
      selected: selecionada,
      child: InkWell(
        onTap: _submitting ? null : () => setState(() => _method = value),
        borderRadius: BorderRadius.circular(14),
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: selecionada ? cor : AppColors.textSubtle,
              width: selecionada ? 2 : 1,
            ),
            color: selecionada ? cor.withValues(alpha: 0.08) : null,
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icon, color: selecionada ? cor : AppColors.textSecondary),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(titulo,
                        style: const TextStyle(
                            fontSize: 16, fontWeight: FontWeight.w700)),
                    const SizedBox(height: 4),
                    Text(detalhe,
                        style: const TextStyle(
                            fontSize: 13, color: AppColors.textSecondary)),
                    const SizedBox(height: 6),
                    Text('Recebes €{0}'.trArgs([_eur(widget.refundableEur)]),
                        style: const TextStyle(fontWeight: FontWeight.w600)),
                  ],
                ),
              ),
              Icon(
                selecionada
                    ? Icons.radio_button_checked
                    : Icons.radio_button_off,
                color: selecionada ? cor : AppColors.textSubtle,
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final podeConfirmar = _method != null && !_submitting;
    return AlertDialog(
      title: Text('Como queres receber o reembolso de €{0}?'
          .trArgs([_eur(widget.refundableEur)])),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _opcao(
              value: 'wallet',
              icon: Icons.account_balance_wallet_outlined,
              titulo: 'Carteira Bora'.tr,
              detalhe:
                  'Fica já disponível: podes usar na mesma hora no próximo pedido.'
                      .tr,
            ),
            const SizedBox(height: 10),
            _opcao(
              value: 'stripe',
              icon: Icons.undo_rounded,
              titulo: 'Devolver para a minha conta'.tr,
              detalhe: prazoDevolucaoAoMeio(widget.originalPaymentMethod),
            ),
            if (widget.tokensEur > 0.004) ...[
              const SizedBox(height: 10),
              Text(
                'Os teus tokens (€{0}) voltam como tokens, com a mesma validade.'
                    .trArgs([_eur(widget.tokensEur)]),
                style: const TextStyle(
                    fontSize: 12, color: AppColors.textSecondary),
              ),
            ],
            const SizedBox(height: 12),
            TextField(
              controller: _reasonCtrl,
              maxLines: 2,
              decoration: InputDecoration(
                labelText: 'Motivo do cancelamento'.tr,
                border: const OutlineInputBorder(),
              ),
            ),
            if (_error != null) ...[
              const SizedBox(height: 8),
              Text(_error!, style: const TextStyle(color: AppColors.error)),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _submitting ? null : () => Navigator.pop(context),
          child: Text('Voltar'.tr),
        ),
        FilledButton(
          onPressed: podeConfirmar ? _submit : null,
          child: _submitting
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2))
              : Text('Confirmar'.tr),
        ),
      ],
    );
  }
}
