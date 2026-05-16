import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Dialog modal exibido enquanto se aguarda confirmação MBWay para reserva.
///
/// Padrão idêntico a `_MBWayWaitingDialog` em `payment_method_screen.dart`,
/// mas faz polling em `reservations.status` (em vez de `orders.payment_status`).
///
/// Status flow: `pending_payment` → `pending` (após webhook
/// `confirm_reservation_payment_webhook`).
///
/// Returns `true` se reserva confirmada (status='pending'), `false` se timeout
/// ou cancelamento.
class ReservationMBWayWaitingDialog extends StatefulWidget {
  const ReservationMBWayWaitingDialog({
    super.key,
    required this.reservationId,
    required this.amount,
  });

  final String reservationId;
  final double amount;

  @override
  State<ReservationMBWayWaitingDialog> createState() =>
      _ReservationMBWayWaitingDialogState();
}

class _ReservationMBWayWaitingDialogState
    extends State<ReservationMBWayWaitingDialog> {
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
        final row = await Supabase.instance.client
            .from('reservations')
            .select('status')
            .eq('id', widget.reservationId)
            .maybeSingle();
        final status = row?['status'] as String?;
        // Sucesso: webhook avançou pending_payment → pending.
        // Falha: webhook (ou RPC orphan cleanup) marcou cancelled.
        if (status != null && status != 'pending_payment' && mounted && !_done) {
          _done = true;
          // Accept any terminal status (pending, approved, cancelled, etc.).
          // pending_payment is the only "still waiting" state; everything else
          // means the webhook has acted — pop(true) for non-cancelled statuses.
          Navigator.of(context).pop(status != 'cancelled' && status != 'rejected');
        }
      } catch (_) {}
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
          const Text('Aguarda confirmação MBWay'),
        ],
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(height: 4),
          Text(
            'Enviámos um pedido de €${widget.amount.toStringAsFixed(2)} '
            'para o teu telemóvel.\nAbre o MBWay e confirma.',
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
