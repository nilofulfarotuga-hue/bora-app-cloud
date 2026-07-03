import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../stores/tvde_store.dart';

/// [Item A · MB Way] Dialog de espera da confirmação MB Way do PLANO TVDE.
///
/// Clone do `AppointmentMBWayWaitingDialog` (paridade), mas o confirmador é a
/// ação `activate` da Edge Function ISOLADA `tvde-plan-payment`, que faz retrieve
/// do PaymentIntent na Stripe e ativa a subscrição quando `succeeded` — sem
/// depender do webhook Stripe. O poll chama [TvdeStore.activatePlan]:
///   • sucesso (plano ativo) → pop(true);
///   • 402 `payment_not_completed` ou erro transitório (invoke lança) → continua;
///   • timeout (120 s) → pop(false).
///
/// Não-dispensável (barrierDismissible:false no showDialog) — evita re-toque que
/// criasse um segundo PaymentIntent enquanto este confirma.
class PlanMbwayWaitingDialog extends StatefulWidget {
  const PlanMbwayWaitingDialog({
    super.key,
    required this.plan,
    required this.paymentIntentId,
    required this.amount,
  });

  final String plan;
  final String paymentIntentId;
  final double amount;

  @override
  State<PlanMbwayWaitingDialog> createState() => _PlanMbwayWaitingDialogState();
}

class _PlanMbwayWaitingDialogState extends State<PlanMbwayWaitingDialog> {
  static const _timeoutSeconds = 120;
  int _secondsLeft = _timeoutSeconds;
  bool _done = false;

  @override
  void initState() {
    super.initState();
    _countdown();
    _poll();
  }

  void _countdown() async {
    while (_secondsLeft > 0 && mounted && !_done) {
      await Future.delayed(const Duration(seconds: 1));
      if (mounted && !_done) setState(() => _secondsLeft--);
    }
    if (mounted && !_done) Navigator.of(context).pop(false);
  }

  void _poll() async {
    final store = context.read<TvdeStore>();
    while (mounted && !_done) {
      await Future.delayed(const Duration(seconds: 3));
      if (!mounted || _done) break;
      try {
        // `activate` faz retrieve do PI; só passa quando status='succeeded'.
        await store.activatePlan(widget.plan, widget.paymentIntentId);
        if (!mounted || _done) break;
        _done = true;
        Navigator.of(context).pop(true);
      } catch (_) {
        // PI ainda não pago (402) ou erro transitório → próximo poll (3 s).
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: Row(
        children: [
          Icon(Icons.phone_iphone, color: Colors.red.shade700),
          const SizedBox(width: 8),
          const Expanded(child: Text('Aguarda confirmação MBWay')),
        ],
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(height: 4),
          Text(
            'Enviámos um pedido de €${widget.amount.toStringAsFixed(2)} '
            'para o teu telemóvel.\nAbre o MBWay e confirma para ativar o plano.',
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 16),
          const CircularProgressIndicator(),
          const SizedBox(height: 12),
          Text(
            'A aguardar confirmação... $_secondsLeft s',
            style: TextStyle(color: Colors.grey.shade600, fontSize: 13),
          ),
        ],
      ),
    );
  }
}
