import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../stores/tvde_store.dart';

import '../../../l10n/tr.dart';

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
/// [checkPaid] corre a cada 3 s; ao fim de [timeoutSeconds] → pop(false).
/// Fábricas: [TvdeRideMbwayWaitingDialog.forRide], [.forRoundtrip] e [.forStop].
class TvdeRideMbwayWaitingDialog extends StatefulWidget {
  const TvdeRideMbwayWaitingDialog({
    super.key,
    required this.amountEur,
    required this.message,
    required this.checkPaid,
    this.timeoutSeconds = 120,
  });

  /// Espera a confirmação MB Way de uma **corrida**.
  ///
  /// O confirmador é a ação `confirm_ride_payment` da Edge Function
  /// `tvde-payment`: ela relê o PaymentIntent na Stripe e, quando está
  /// `succeeded`, liberta a corrida (`aguarda_pagamento` → `solicitada`, que é
  /// o que faz o dispatch arrancar). Ler só o `payment_status` da tabela não
  /// chegava — ninguém o atualizava sozinho.
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
      message: 'Abre o MBWay e confirma para a corrida seguir.'.tr,
      // 2026-08-13 — 120 s não chegava: o MB Way demora regularmente mais do
      // que isso e o cliente ficava com a corrida por marcar como paga (era o
      // poll, e não o webhook, o único a marcá-la — ver BUG 1). Com o ramo TVDE
      // no `stripe-webhook` o servidor deixa de depender deste poll, mas 300 s
      // dá margem real a quem confirma no banco com o telemóvel na mão.
      timeoutSeconds: 300,
      checkPaid: (store) async {
        final res = await store.confirmRidePayment(rideId);
        // Sem resposta do servidor (rede) → continuar a tentar, não desistir.
        if (res == null) return false;
        if (res['succeeded'] == true) return true;
        final status = res['payment_status'] as String?;
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
      message: 'Abre o MBWay e confirma para garantir a tua volta.'.tr,
      checkPaid: (store) =>
          store.activateRoundtrip(outboundRideId, paymentIntentId),
    );
  }

  /// Espera a confirmação MB Way de uma **parada extra** numa corrida paga
  /// online. O confirmador é `confirm_stop_payment`: quando o PaymentIntent
  /// está `succeeded` é o próprio backend que adiciona a parada (chama a
  /// `tvde_add_stop` com o PI ligado). A parada só existe depois disso.
  ///
  /// [onResponse] recebe cada resposta do servidor para o ecrã poder distinguir
  /// "devolvido" de "expirou" — o `bool` do pop não chega para isso.
  factory TvdeRideMbwayWaitingDialog.forStop({
    Key? key,
    required String paymentIntentId,
    required double amountEur,
    void Function(Map<String, dynamic> res)? onResponse,
  }) {
    // Estados da Stripe em que o pagamento já não vai acontecer.
    const failed = {'canceled', 'requires_payment_method'};
    return TvdeRideMbwayWaitingDialog(
      key: key,
      amountEur: amountEur,
      message: 'Abre o MBWay e confirma para adicionar a parada.'.tr,
      checkPaid: (store) async {
        final res = await store.confirmStopPayment(paymentIntentId);
        // Sem resposta do servidor (rede) → continuar a tentar, não desistir.
        if (res == null) return false;
        onResponse?.call(res);
        if (res['succeeded'] == true) return true;
        // Pagou mas a parada não entrou e o dinheiro já voltou — é terminal.
        if (res['refunded'] == true) return null;
        final status = res['status'] as String?;
        if (status != null && failed.contains(status)) return null;
        return false;
      },
    );
  }

  final double amountEur;

  /// Segunda linha do texto — o que acontece quando o cliente confirmar.
  final String message;
  final MbwayPaidCheck checkPaid;

  /// Quanto tempo esperar antes de desistir. A corrida usa 300 s (MB Way é
  /// lento); parada e pacote mantêm os 120 s de origem.
  final int timeoutSeconds;

  @override
  State<TvdeRideMbwayWaitingDialog> createState() =>
      _TvdeRideMbwayWaitingDialogState();
}

class _TvdeRideMbwayWaitingDialogState
    extends State<TvdeRideMbwayWaitingDialog> {
  late int _secondsLeft = widget.timeoutSeconds;
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
          Expanded(child: Text('Aguarda confirmação MBWay'.tr)),
        ],
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(height: 4),
          Text(
            'Enviámos um pedido de €{0} para o teu telemóvel.\n{1}'.trArgs([widget.amountEur.toStringAsFixed(2), widget.message]),
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
