import 'dart:async';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';

import '../../../config/app_colors.dart';
import '../../../config/app_spacing.dart';
import '../../../l10n/tr.dart';
import '../../../models/casa_models.dart';
import '../../../services/payment_service.dart';
import '../../../services/saved_card_checkout.dart';
import '../../../services/stripe_contas.dart';
import '../../../stores/casa_store.dart';

/// CASA & MANUTENÇÃO — pagamento do cliente por cartão ou MB Way (m11, 09/11/2026).
///
/// Molde: `CarwashPaymentFlow` (vivo em produção). Tudo server-side na Edge isolada `casa-checkout`;
/// o Dart nunca manda valores — só o id do pedido. O pedido só vai aos profissionais quando o
/// servidor confirma o pagamento.
///
/// Cartão: pagamento que cobra na hora → PaymentSheet → mark_held.
/// MB WAY: pedido na app MB WAY → poll ao mark_held até 120 s.
/// Dinheiro: nada a fazer, paga-se ao profissional no fim.
class CasaPagamentoFlow {
  CasaPagamentoFlow._();

  /// true quando o pagamento ficou fechado. Falhar aqui NÃO cancela o pedido: fica "À espera do
  /// pagamento" e o cliente pode tentar de novo no ecrã do pedido (cai sozinho ao fim de 30 min).
  static Future<bool> pagar(
    BuildContext context,
    CasaStore store,
    CasaPedido pedido,
  ) async {
    switch (pedido.paymentMethod) {
      case 'card':
        return _cartao(context, store, pedido);
      case 'mbway':
        return _mbway(context, store, pedido);
      default:
        return true; // dinheiro — paga no fim
    }
  }

  static Future<bool> _cartao(
    BuildContext context,
    CasaStore store,
    CasaPedido pedido,
  ) async {
    if (kIsWeb) {
      _snack(context, 'O pagamento por cartão está disponível na app móvel.'.tr);
      return false;
    }

    // Carteira Única: cartão guardado + digital/rosto ANTES de criar o pagamento.
    // Recusar aqui não cobra nada.
    final auth = await SavedCardCheckout.instance
        .authorize(context: context, amountEur: pedido.totalCents / 100.0);
    if (!context.mounted) return false;
    if (auth.cancelled) {
      _snack(context, 'Pagamento cancelado. Não foi cobrado nada.'.tr);
      return false;
    }

    final criado =
        await store.criarPagamentoCartao(pedido.id, savedPmId: auth.savedPmId);
    if (!context.mounted) return false;
    if (criado == null) {
      _snack(context, 'Não foi possível iniciar o pagamento.'.tr);
      return false;
    }

    try {
      final clientSecret = criado['clientSecret'] as String;
      if (auth.usesSavedCard) {
        // Já confirmado off_session; só abre a folha se o banco pedir 3DS.
        final ok = await PaymentService().confirmSavedCardPayment(
          clientSecret: clientSecret,
          requiresAction: (criado['requiresAction'] as bool?) ?? false,
          publishableKey: StripeContas.chaveDaResposta(criado), // duas contas
        );
        if (!ok) {
          if (context.mounted) _snack(context, 'Pagamento não concluído.'.tr);
          return false;
        }
      } else {
        await PaymentService().processPayment(
          clientSecret,
          publishableKey: StripeContas.chaveDaResposta(criado), // duas contas
        );
      }
    } catch (_) {
      if (context.mounted) _snack(context, 'Pagamento não concluído.'.tr);
      return false;
    }

    // O cartão fica fechado de imediato — 3 tentativas chegam.
    for (var i = 0; i < 3; i++) {
      final ok = await store.marcarPagamento(
          pedido.id, criado['paymentIntentId'] as String);
      if (ok) return true;
      await Future<void>.delayed(const Duration(seconds: 2));
    }
    if (context.mounted) {
      _snack(context, 'Pagamento em validação — confirma no ecrã do pedido.'.tr);
    }
    return false;
  }

  static Future<bool> _mbway(
    BuildContext context,
    CasaStore store,
    CasaPedido pedido,
  ) async {
    final telemovel = await _pedirTelemovel(context);
    if (telemovel == null || !context.mounted) return false;

    final criado = await store.criarPagamentoMbway(pedido.id, telemovel);
    if (!context.mounted) return false;
    if (criado == null) {
      _snack(context,
          'Não foi possível iniciar o MB WAY. Confirma o número e tenta de novo.'.tr);
      return false;
    }

    final ok = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _EsperaMbway(
        store: store,
        pedidoId: pedido.id,
        paymentIntentId: criado['paymentIntentId'] as String,
        totalCents: pedido.totalCents,
      ),
    );
    if (ok != true && context.mounted) {
      _snack(context,
          'Não recebemos a confirmação MB WAY. Se pagaste, reabre o pedido; senão tenta de novo.'.tr);
    }
    return ok == true;
  }

  static Future<String?> _pedirTelemovel(BuildContext context) async {
    final ctrl = TextEditingController();
    return showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Número MB WAY'.tr),
        content: TextField(
          key: const Key('casa_mbway_telemovel'),
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
              onPressed: () => Navigator.pop(ctx), child: Text('Cancelar'.tr)),
          TextButton(
            onPressed: () {
              final digitos = ctrl.text.replaceAll(RegExp(r'\D'), '');
              if (digitos.length < 9) return;
              Navigator.pop(ctx, digitos);
            },
            child: Text('Pagar'.tr),
          ),
        ],
      ),
    );
  }

  static void _snack(BuildContext context, String msg) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(msg)));
  }
}

/// Espera pela confirmação MB WAY: poll de 4 em 4 s até 120 s. Não-dispensável, para não nascer um
/// segundo pagamento enquanto este ainda confirma.
class _EsperaMbway extends StatefulWidget {
  const _EsperaMbway({
    required this.store,
    required this.pedidoId,
    required this.paymentIntentId,
    required this.totalCents,
  });

  final CasaStore store;
  final String pedidoId;
  final String paymentIntentId;
  final int totalCents;

  @override
  State<_EsperaMbway> createState() => _EsperaMbwayState();
}

class _EsperaMbwayState extends State<_EsperaMbway> {
  static const _segundos = 120;
  int _faltam = _segundos;
  bool _feito = false;
  Timer? _relogio;
  Timer? _poll;

  @override
  void initState() {
    super.initState();
    _relogio = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      setState(() => _faltam -= 1);
      if (_faltam <= 0) _acabar(false);
    });
    _poll = Timer.periodic(const Duration(seconds: 4), (_) => _ver());
    _ver();
  }

  @override
  void dispose() {
    _relogio?.cancel();
    _poll?.cancel();
    super.dispose();
  }

  Future<void> _ver() async {
    if (_feito) return;
    final ok =
        await widget.store.marcarPagamento(widget.pedidoId, widget.paymentIntentId);
    if (ok) _acabar(true);
  }

  void _acabar(bool ok) {
    if (_feito || !mounted) return;
    _feito = true;
    _relogio?.cancel();
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
            'Enviámos um pedido de {0} para o teu MB WAY. Aprova-o para confirmar o serviço.'
                .trArgs([casaEuro(widget.totalCents)]),
            textAlign: TextAlign.center,
            style: const TextStyle(color: AppColors.textSecondary, height: 1.4),
          ),
          const SizedBox(height: Spacing.md),
          Text('$_faltam s',
              style: const TextStyle(
                  fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
        ],
      ),
    );
  }
}
