import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../l10n/tr.dart';

/// Dialog modal exibido enquanto se aguarda confirmação MBWay do PAGAMENTO de
/// uma MARCAÇÃO (M7 — paridade com ReservationMBWayWaitingDialog).
///
/// Diferença vs reservas: o stripe-webhook não trata appointment_deposit, por
/// isso o polling é à Edge Fn `confirm-mbway-appointment-payment`, que verifica
/// o PaymentIntent no Stripe (server-side) e confirma a marcação quando
/// succeeded — o próprio poll é o confirmador.
///
/// Returns `true` se a marcação ficou confirmada, `false` se timeout ou
/// pagamento cancelado.
class AppointmentMBWayWaitingDialog extends StatefulWidget {
  const AppointmentMBWayWaitingDialog({
    super.key,
    required this.appointmentId,
    required this.amount,
  });

  final String appointmentId;
  final double amount;

  @override
  State<AppointmentMBWayWaitingDialog> createState() =>
      _AppointmentMBWayWaitingDialogState();
}

class _AppointmentMBWayWaitingDialogState
    extends State<AppointmentMBWayWaitingDialog> {
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
    while (mounted && !_done) {
      await Future.delayed(const Duration(seconds: 3));
      if (!mounted || _done) break;
      try {
        final res = await Supabase.instance.client.functions.invoke(
          'confirm-mbway-appointment-payment',
          body: {'appointment_id': widget.appointmentId},
        );
        final data = res.data is Map
            ? Map<String, dynamic>.from(res.data as Map)
            : const <String, dynamic>{};
        final status = data['status'] as String?;
        if (!mounted || _done) break;
        if (status == 'confirmed') {
          _done = true;
          Navigator.of(context).pop(true);
        } else if (status == 'canceled') {
          _done = true;
          Navigator.of(context).pop(false);
        }
        // 'pending' → continua a aguardar.
      } catch (_) {
        // Erro transitório — próximo poll (3s) tenta de novo.
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
          Text('Aguarda confirmação MBWay'.tr),
        ],
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(height: 4),
          Text(
            'Enviámos um pedido de €{0} para o teu telemóvel.\nAbre o MBWay e confirma.'.trArgs([widget.amount.toStringAsFixed(2)]),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 16),
          const CircularProgressIndicator(),
          const SizedBox(height: 12),
          Text(
            'A aguardar confirmação... {0} s'.trArgs([_secondsLeft]),
            style: TextStyle(color: Colors.grey.shade600, fontSize: 13),
          ),
        ],
      ),
    );
  }
}
