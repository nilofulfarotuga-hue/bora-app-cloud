import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../stores/tvde_store.dart';

/// `true` pago · `false` ainda a aguardar · `null` falhou definitivamente.
typedef MbwayPaidCheck = Future<bool?> Function(TvdeStore store);

/// Dialog de espera da confirmação MB Way no TVDE — serve a **corrida** e o
/// **pacote ida-e-volta**.
///
/// Irmão do `PlanMbwayWaitingDialog` (plano) e do `AppointmentMBWayWaitingDialog`
/// (marcações): o MB Way confirma-se na app do banco, por isso o cliente tem de
/// esperar por um estado terminal em vez de seguir logo. Não-dispensável
/// (`barrierDismissible:false`) — evita que um re-toque dispare uma 2.ª cobrança.
///
/// [checkPaid] corre a cada 3 s; timeout de 120 s → pop(false).
/// Fábricas: [TvdeRideMbwayWaitingDialog.forRide] e [.forRoundtrip].
class TvdeRideMbwayWaitingDialog extends StatefulWidget {
  const TvdeRideMbwayWaitingDialog({
    super.key,
    required this.amountEur,
    required this.message,
    required this.checkPaid,
  });

  /// Espera o `payment_status` da corrida em `tvde_rides` chegar a 'succeeded'
  /// — a Edge Function `tvde-payment` grava lá o estado do PaymentIntent.
  factory TvdeRideMbwayWaitingDialog.forRide({
    Key? key,
    required String rideId,
    required double amountEur,
  }) {
    // Estados da Stripe em que o pagamento já não vai acontecer.
    const failed = {'canceled', 'requires_payment_method'};
    return TvdeRideMbwayWaitingDialog(
      key: key,
      amountEur: amountEur,
      message: 'Abre o MBWay e confirma para a corrida seguir.',
      checkPaid: (store) async {
        final status = await store.fetchRidePaymentStatus(rideId);
        if (status == 'succeeded') return true;
        if (status != null && failed.contains(status)) return null;
        return false;
      },
    );
  }

  /// Espera o pacote €8. O confirmador é a própria ação `activate_roundtrip` da
  /// Edge Function `tvde-plan-payment`: faz retrieve do PaymentIntent e só cria
  /// o vale (ligando-o à corrida de ida) quando o estado é `succeeded`. Enquanto
  /// não estiver pago devolve 402 → o store devolve `false` e o poll continua.
  /// É idempotente, por isso repetir a chamada é seguro.
  factory TvdeRideMbwayWaitingDialog.forRoundtrip({
    Key? key,
    required String outboundRideId,
    required String paymentIntentId,
    required double amountEur,
  }) {
    return TvdeRideMbwayWaitingDialog(
      key: key,
      amountEur: amountEur,
      message: 'Abre o MBWay e confirma para garantir a tua volta.',
      checkPaid: (store) =>
          store.activateRoundtrip(outboundRideId, paymentIntentId),
    );
  }

  final double amountEur;

  /// Segunda linha do texto — o que acontece quando o cliente confirmar.
  final String message;
  final MbwayPaidCheck checkPaid;

  @override
  State<TvdeRideMbwayWaitingDialog> createState() =>
      _TvdeRideMbwayWaitingDialogState();
}

class _TvdeRideMbwayWaitingDialogState
    extends State<TvdeRideMbwayWaitingDialog> {
  static const _timeoutSeconds = 120;

  int _secondsLeft = _timeoutSeconds;
  bool _done = false;

  @override
  void initState() {
    super.initState();
    _countdown();
    _poll();
  }

  void _finish(bool ok) {
    if (!mounted || _done) return;
    _done = true;
    Navigator.of(context).pop(ok);
  }

  void _countdown() async {
    while (_secondsLeft > 0 && mounted && !_done) {
      await Future.delayed(const Duration(seconds: 1));
      if (mounted && !_done) setState(() => _secondsLeft--);
    }
    _finish(false);
  }

  void _poll() async {
    final store = context.read<TvdeStore>();
    while (mounted && !_done) {
      await Future.delayed(const Duration(seconds: 3));
      if (!mounted || _done) break;
      final result = await widget.checkPaid(store);
      if (!mounted || _done) break;
      if (result == true) {
        _finish(true);
        break;
      }
      if (result == null) {
        _finish(false);
        break;
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
            'Enviámos um pedido de €${widget.amountEur.toStringAsFixed(2)} '
            'para o teu telemóvel.\n${widget.message}',
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 16),
          const CircularProgressIndicator(),
          const SizedBox(height: 12),
          Text('$_secondsLeft s',
              style: const TextStyle(fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }
}
