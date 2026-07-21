import 'dart:async';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';

import '../../../config/app_colors.dart';
import '../../../config/app_spacing.dart';
import '../../../models/cleaning_models.dart';
import '../../../services/payment_service.dart';
import '../../../services/saved_card_checkout.dart';
import '../../../stores/cleaning_store.dart';

/// LIMPEZA — fluxo de pagamento partilhado (wizard + tracking).
/// Cartão: PaymentIntent normal (COBRA na reserva) → PaymentSheet → mark_held.
/// MB Way: create_mbway (push na app MB WAY) → poll mark_held até 120 s.
/// Cancelamento estorna automaticamente o que exceder a taxa ('reverse').
/// Tudo server-side na Edge Fn isolada cleaning-checkout (Lista Vermelha).
class CleaningPaymentFlow {
  CleaningPaymentFlow._();

  /// Executa o pagamento da reserva. Devolve true quando ficou 'held'
  /// (retido no cartão / cobrado no MB Way). Cash devolve sempre true.
  static Future<bool> pay(
    BuildContext context,
    CleaningStore store,
    CleaningBooking booking,
  ) async {
    switch (booking.paymentMethod) {
      case 'card':
        return _payCard(context, store, booking);
      case 'mbway':
        return _payMbway(context, store, booking);
      default:
        return true; // cash — paga-se no local
    }
  }

  // ── cartão ────────────────────────────────────────────────────────────────

  static Future<bool> _payCard(
    BuildContext context,
    CleaningStore store,
    CleaningBooking booking,
  ) async {
    if (kIsWeb) {
      _snack(context, 'O pagamento por cartão está disponível na app móvel.');
      return false;
    }
    // Carteira Unica (2026-07-21): cartao padrao + digital/rosto ANTES de
    // criar o PaymentIntent. Recusar nao cobra nada.
    final auth = await SavedCardCheckout.instance
        .authorize(amountEur: booking.totalCents / 100.0);
    if (!context.mounted) return false;
    if (auth.cancelled) {
      _snack(context, 'Pagamento cancelado. Não foi cobrado nada.');
      return false;
    }

    final created =
        await store.createCardPayment(booking.id, savedPmId: auth.savedPmId);
    if (!context.mounted) return false;
    if (created == null) {
      _snack(context, 'Não foi possível iniciar o pagamento.');
      return false;
    }
    try {
      final clientSecret = created['clientSecret'] as String;
      if (auth.usesSavedCard) {
        // PI ja confirmado off_session; so abre o sheet se o banco pedir 3DS.
        final ok = await PaymentService().confirmSavedCardPayment(
          clientSecret: clientSecret,
          requiresAction: (created['requiresAction'] as bool?) ?? false,
        );
        if (!ok) {
          if (context.mounted) _snack(context, 'Pagamento não concluído.');
          return false;
        }
      } else {
        await PaymentService().processPayment(clientSecret);
      }
    } catch (_) {
      if (context.mounted) _snack(context, 'Pagamento não concluído.');
      return false;
    }
    // Cartão fica 'requires_capture' imediatamente — 3 tentativas chegam.
    for (var i = 0; i < 3; i++) {
      final ok = await store.markPaymentHeld(
          booking.id, created['paymentIntentId'] as String);
      if (ok) return true;
      await Future<void>.delayed(const Duration(seconds: 2));
    }
    if (context.mounted) {
      _snack(context, 'Pagamento em validação — verifica no ecrã da reserva.');
    }
    return false;
  }

  // ── MB Way ────────────────────────────────────────────────────────────────

  static Future<bool> _payMbway(
    BuildContext context,
    CleaningStore store,
    CleaningBooking booking,
  ) async {
    final phone = await _askMbwayPhone(context);
    if (phone == null || !context.mounted) return false;

    final created = await store.createMbwayPayment(booking.id, phone);
    if (!context.mounted) return false;
    if (created == null) {
      _snack(context,
          'Não foi possível iniciar o MB Way. Confirma o número e tenta de novo.');
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
      _snack(context,
          'Não recebemos a confirmação MB Way. Se pagaste, reabre a reserva; '
          'senão tenta de novo.');
    }
    return ok == true;
  }

  static Future<String?> _askMbwayPhone(BuildContext context) async {
    final ctrl = TextEditingController();
    return showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Número MB Way'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          keyboardType: TextInputType.phone,
          decoration: const InputDecoration(
            labelText: 'Telemóvel',
            hintText: '9XX XXX XXX',
            prefixText: '+351 ',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancelar'),
          ),
          TextButton(
            onPressed: () {
              final digits = ctrl.text.replaceAll(RegExp(r'\D'), '');
              if (digits.length < 9) return;
              Navigator.pop(ctx, digits);
            },
            child: const Text('Pagar'),
          ),
        ],
      ),
    );
  }

  static void _snack(BuildContext context, String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }
}

/// Dialog de espera da confirmação MB Way (clone do padrão TVDE/Reservas):
/// poll a mark_held de 4 em 4 s até 120 s. Não-dispensável para evitar
/// segundo PaymentIntent enquanto este confirma.
class _MbwayWaitingDialog extends StatefulWidget {
  const _MbwayWaitingDialog({
    required this.store,
    required this.bookingId,
    required this.paymentIntentId,
    required this.amountCents,
  });

  final CleaningStore store;
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
      title: const Text('Confirma na app MB WAY'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(height: Spacing.sm),
          const CircularProgressIndicator(),
          const SizedBox(height: Spacing.lg),
          Text(
            'Enviámos um pedido de ${CleaningLabels.euro(widget.amountCents)} '
            'para o teu MB WAY. Aprova-o para confirmar a reserva.',
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
