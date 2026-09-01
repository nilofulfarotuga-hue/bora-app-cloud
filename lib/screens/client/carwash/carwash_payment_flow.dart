import 'dart:async';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';

import '../../../config/app_colors.dart';
import '../../../config/app_spacing.dart';
import '../../../models/carwash_models.dart';
import '../../../services/payment_service.dart';
import '../../../services/saved_card_checkout.dart';
import '../../../stores/carwash_store.dart';

import '../../../l10n/tr.dart';

/// LAVAGEM AUTO — pagamento do cliente.
///
/// Molde: `CleaningPaymentFlow` (vivo em produção). Tudo server-side na Edge
/// isolada `carwash-checkout`; o Dart nunca manda valores — só o id do pedido.
///
/// Cartão: PaymentIntent que cobra na hora → PaymentSheet → mark_held.
/// MB WAY: pedido na app MB WAY → poll ao mark_held até 120 s.
/// Dinheiro: nada a fazer, paga-se ao lavador na entrega.
class CarwashPaymentFlow {
  CarwashPaymentFlow._();

  /// Devolve true quando o pagamento ficou fechado. Dinheiro devolve sempre
  /// true. Falhar aqui NÃO cancela o pedido — o cliente pode voltar a tentar
  /// no ecrã de acompanhamento.
  static Future<bool> pay(
    BuildContext context,
    CarwashStore store,
    CarwashBooking booking,
  ) async {
    switch (booking.paymentMethod) {
      case 'card':
        return _payCard(context, store, booking);
      case 'mbway':
        return _payMbway(context, store, booking);
      default:
        return true; // dinheiro — paga na entrega
    }
  }

  // ── cartão ────────────────────────────────────────────────────────────────

  static Future<bool> _payCard(
    BuildContext context,
    CarwashStore store,
    CarwashBooking booking,
  ) async {
    if (kIsWeb) {
      _snack(context, 'O pagamento por cartão está disponível na app móvel.'.tr);
      return false;
    }

    // Carteira Única: cartão guardado + digital/rosto ANTES de criar o
    // PaymentIntent. Recusar aqui não cobra nada.
    final auth = await SavedCardCheckout.instance
        .authorize(amountEur: booking.totalCents / 100.0);
    if (!context.mounted) return false;
    if (auth.cancelled) {
      _snack(context, 'Pagamento cancelado. Não foi cobrado nada.'.tr);
      return false;
    }

    final created =
        await store.createCardPayment(booking.id, savedPmId: auth.savedPmId);
    if (!context.mounted) return false;
    if (created == null) {
      _snack(context, 'Não foi possível iniciar o pagamento.'.tr);
      return false;
    }

    try {
      final clientSecret = created['clientSecret'] as String;
      if (auth.usesSavedCard) {
        // Já confirmado off_session; só abre o sheet se o banco pedir 3DS.
        final ok = await PaymentService().confirmSavedCardPayment(
          clientSecret: clientSecret,
          requiresAction: (created['requiresAction'] as bool?) ?? false,
        );
        if (!ok) {
          if (context.mounted) _snack(context, 'Pagamento não concluído.'.tr);
          return false;
        }
      } else {
        await PaymentService().processPayment(clientSecret);
      }
    } catch (_) {
      if (context.mounted) _snack(context, 'Pagamento não concluído.'.tr);
      return false;
    }

    // O cartão fica fechado de imediato — 3 tentativas chegam.
    for (var i = 0; i < 3; i++) {
      final ok = await store.markPaymentHeld(
          booking.id, created['paymentIntentId'] as String);
      if (ok) return true;
      await Future<void>.delayed(const Duration(seconds: 2));
    }
    if (context.mounted) {
      _snack(context, 'Pagamento em validação — confirma no ecrã do pedido.'.tr);
    }
    return false;
  }

  // ── MB WAY ────────────────────────────────────────────────────────────────

  static Future<bool> _payMbway(
    BuildContext context,
    CarwashStore store,
    CarwashBooking booking,
  ) async {
    final phone = await _askMbwayPhone(context, booking.clientPhone);
    if (phone == null || !context.mounted) return false;

    final created = await store.createMbwayPayment(booking.id, phone);
    if (!context.mounted) return false;
    if (created == null) {
      _snack(context,
          'Não foi possível iniciar o MB WAY. Confirma o número e tenta de novo.'.tr);
      return false;
    }

    final ok = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _MbwayWaitingDialog(
        store: store,
        bookingId: booking.id,
        paymentIntentId: created['paymentIntentId'] as String,
        amountCents: booking.totalCents,
      ),
    );
    if (ok != true && context.mounted) {
      _snack(
          context,
          'Não recebemos a confirmação MB WAY. Se pagaste, reabre o pedido; senão tenta de novo.'.tr);
    }
    return ok == true;
  }

  static Future<String?> _askMbwayPhone(
      BuildContext context, String sugestao) async {
    final ctrl = TextEditingController(
        text: sugestao.replaceAll(RegExp(r'\D'), ''));
    return showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Número MB WAY'.tr),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          keyboardType: TextInputType.phone,
          decoration: InputDecoration(
            labelText: 'Telemóvel'.tr,
            hintText: '9XX XXX XXX'.tr,
            prefixText: '+351 ',
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text('Cancelar'.tr)),
          TextButton(
            onPressed: () {
              final digits = ctrl.text.replaceAll(RegExp(r'\D'), '');
              if (digits.length < 9) return;
              Navigator.pop(ctx, digits);
            },
            child: Text('Pagar'.tr),
          ),
        ],
      ),
    );
  }

  static void _snack(BuildContext context, String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }
}

/// Espera pela confirmação MB WAY: poll de 4 em 4 s até 120 s.
/// Não-dispensável, para não nascer um segundo PaymentIntent enquanto este
/// ainda confirma.
class _MbwayWaitingDialog extends StatefulWidget {
  const _MbwayWaitingDialog({
    required this.store,
    required this.bookingId,
    required this.paymentIntentId,
    required this.amountCents,
  });

  final CarwashStore store;
  final String bookingId;
  final String paymentIntentId;
  final int amountCents;

  @override
  State<_MbwayWaitingDialog> createState() => _MbwayWaitingDialogState();
}

class _MbwayWaitingDialogState extends State<_MbwayWaitingDialog> {
  static const _timeoutSeconds = 120;
  int _secondsLeft = _timeoutSeconds;
  bool _done = false;
  Timer? _tick;
  Timer? _poll;

  @override
  void initState() {
    super.initState();
    _tick = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      setState(() => _secondsLeft -= 1);
      if (_secondsLeft <= 0) _finish(false);
    });
    _poll = Timer.periodic(const Duration(seconds: 4), (_) => _check());
    _check();
  }

  @override
  void dispose() {
    _tick?.cancel();
    _poll?.cancel();
    super.dispose();
  }

  Future<void> _check() async {
    if (_done) return;
    final ok = await widget.store
        .markPaymentHeld(widget.bookingId, widget.paymentIntentId);
    if (ok) _finish(true);
  }

  void _finish(bool ok) {
    if (_done || !mounted) return;
    _done = true;
    _tick?.cancel();
    _poll?.cancel();
    Navigator.pop(context, ok);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('Confirma na app MB WAY'.tr),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(height: Spacing.sm),
          const CircularProgressIndicator(),
          const SizedBox(height: Spacing.lg),
          Text(
            'Enviámos um pedido de {0} € para o teu MB WAY. Aprova-o para confirmar a lavagem.'.trArgs([(widget.amountCents / 100).toStringAsFixed(2)]),
            textAlign: TextAlign.center,
            style: const TextStyle(color: AppColors.textSecondary, height: 1.4),
          ),
          const SizedBox(height: Spacing.md),
          Text('$_secondsLeft s',
              style: const TextStyle(
                  fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
        ],
      ),
    );
  }
}
