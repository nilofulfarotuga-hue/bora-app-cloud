import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_stripe/flutter_stripe.dart' show StripeException;

import '../../config/app_colors.dart';
import '../../l10n/tr.dart';
import '../../models/order_edit.dart';
import '../../models/order_model.dart';
import '../../services/order_edit_service.dart';
import '../../services/payment_service.dart';

/// Cliente vê o que a loja parceira mudou no pedido (PT-PT):
///   • "A loja quer acrescentar X (+€Y)" → Aceitar / Recusar (e paga a diferença
///     no mesmo meio: dinheiro soma ao total, cartão cobra o cartão guardado,
///     MB Way pede um MB Way só da diferença).
///   • "Produto em falta: X — foram devolvidos €Y" (cartão / carteira / menos na entrega).
/// Nunca mostra comissão nem markup: só totais do cliente.
class ClientOrderEditBanner extends StatefulWidget {
  const ClientOrderEditBanner({super.key, required this.order});

  final OrderModel order;

  @override
  State<ClientOrderEditBanner> createState() => _ClientOrderEditBannerState();
}

class _ClientOrderEditBannerState extends State<ClientOrderEditBanner> {
  late final Future<bool> _ativo = OrderEditService.instance.ativo();
  late final Stream<List<OrderEditGrupo>> _grupos =
      OrderEditService.instance.gruposDoPedido(widget.order.id);

  /// Trava por proposta (nunca um "ocupado" global — PADRAO 3.13).
  final Set<String> _aTratar = {};

  String _eur(double v) => '€${v.abs().toStringAsFixed(2)}';

  @override
  Widget build(BuildContext context) {
    if (!widget.order.isPartnerStore) return const SizedBox.shrink();
    return FutureBuilder<bool>(
      future: _ativo,
      builder: (context, on) =>
          on.data == true ? _lista(context) : const SizedBox.shrink(),
    );
  }

  Widget _lista(BuildContext context) {
    return StreamBuilder<List<OrderEditGrupo>>(
      stream: _grupos,
      builder: (context, snap) {
        final grupos = (snap.data ?? const <OrderEditGrupo>[])
            .where((g) =>
                g.estado == OrderEditEstado.pendenteCliente ||
                g.aguardaPagamento ||
                (g.estado == OrderEditEstado.aplicado && g.eTirar))
            .toList();
        if (grupos.isEmpty) return const SizedBox.shrink();
        return Column(
          children: [for (final g in grupos) _cartao(context, g)],
        );
      },
    );
  }

  Widget _cartao(BuildContext context, OrderEditGrupo g) {
    final aTratar = _aTratar.contains(g.grupoId);
    if (g.estado == OrderEditEstado.aplicado && g.eTirar) {
      final comoVolta = switch (widget.order.paymentMethod) {
        PaymentMethod.cash => 'Pagas menos {0} na entrega.'.trArgs([_eur(g.diferenca)]),
        PaymentMethod.card => 'Foram devolvidos {0} ao teu cartão.'.trArgs([_eur(g.diferenca)]),
        _ => 'Foram devolvidos {0} à tua carteira Bora.'.trArgs([_eur(g.diferenca)]),
      };
      return _Caixa(
        cor: AppColors.info,
        icone: Icons.remove_shopping_cart_outlined,
        titulo: 'Produto em falta'.tr,
        texto: '${g.resumo}. $comoVolta',
      );
    }

    final pagar = g.aguardaPagamento;
    return _Caixa(
      cor: AppColors.warning,
      icone: Icons.add_shopping_cart_outlined,
      titulo: pagar
          ? 'Falta pagar o que acrescentaste'.tr
          : 'A loja quer acrescentar ao teu pedido'.tr,
      texto: '${g.resumo} (+${_eur(g.diferenca)}). '
          '${'Total novo: {0}'.trArgs([_eur(g.totalDepois)])}',
      acoes: [
        if (!pagar)
          TextButton(
            key: const Key('btn_recusar_edicao'),
            onPressed: aTratar ? null : () => _responder(g, false),
            child: Text('Recusar'.tr),
          ),
        FilledButton(
          key: const Key('btn_aceitar_edicao'),
          onPressed: aTratar ? null : () => pagar ? _pagar(g) : _responder(g, true),
          child: aTratar
              ? const SizedBox(
                  width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
              : Text(pagar ? 'Pagar diferença'.tr : 'Aceitar'.tr),
        ),
      ],
    );
  }

  Future<void> _responder(OrderEditGrupo g, bool aceitar) async {
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _aTratar.add(g.grupoId));
    try {
      final res = await OrderEditService.instance.responder(g.grupoId, aceitar);
      if (res['ok'] == false) {
        messenger.showSnackBar(SnackBar(
            content: Text(res['erro'] == 'JA_RECOLHIDO'
                ? 'O pedido já saiu da loja — ficou como estava.'.tr
                : 'Esta proposta já foi respondida.'.tr)));
        return;
      }
      if (!aceitar) {
        messenger.showSnackBar(SnackBar(content: Text('Recusado. O pedido fica como estava.'.tr)));
        return;
      }
      if (res['precisa_pagamento'] == true) {
        await _pagar(g, jaMarcado: true);
      } else {
        messenger.showSnackBar(SnackBar(content: Text('Aceite. A loja vai juntar ao teu pedido.'.tr)));
      }
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(mensagemErroEdicao(e))));
    } finally {
      if (mounted) setState(() => _aTratar.remove(g.grupoId));
    }
  }

  /// Cobra a diferença no mesmo meio de pagamento do pedido.
  Future<void> _pagar(OrderEditGrupo g, {bool jaMarcado = false}) async {
    final messenger = ScaffoldMessenger.of(context);
    final svc = OrderEditService.instance;
    if (!jaMarcado) setState(() => _aTratar.add(g.grupoId));
    try {
      final c = await svc.cobrarDiferenca(g.grupoId);
      if (c['ok'] != true) {
        messenger.showSnackBar(SnackBar(content: Text('Não foi possível cobrar. Tenta outra vez.'.tr)));
        return;
      }
      if (c['pago'] == true || c['ja_aplicado'] == true) {
        messenger.showSnackBar(SnackBar(content: Text('Pago. A loja vai juntar ao teu pedido.'.tr)));
        return;
      }
      final pi = c['payment_intent_id'] as String?;
      if (pi == null) return;

      if (c['metodo'] == 'mbway') {
        messenger.showSnackBar(SnackBar(
            content: Text('Confirma o pagamento na app MB WAY.'.tr),
            duration: const Duration(seconds: 6)));
        // espera até 5 minutos pela confirmação (MB Way expira antes disso)
        for (var i = 0; i < 60 && mounted; i++) {
          await Future<void>.delayed(const Duration(seconds: 5));
          final r = await svc.confirmarPagamento(g.grupoId, pi);
          if (r['pago'] == true) {
            messenger.showSnackBar(SnackBar(content: Text('Pago. A loja vai juntar ao teu pedido.'.tr)));
            return;
          }
          final st = r['status'];
          if (st == 'canceled' || st == 'requires_payment_method') break;
        }
        messenger.showSnackBar(SnackBar(content: Text('O MB WAY não foi confirmado. Podes tentar outra vez.'.tr)));
        return;
      }

      // cartão: o banco pediu confirmação → Payment Sheet
      final secret = c['client_secret'] as String?;
      if (secret == null) return;
      await PaymentService().processPayment(secret,
          vertical: 'order_edit', referenciaId: widget.order.id, paymentIntentId: pi);
      final r = await svc.confirmarPagamento(g.grupoId, pi);
      messenger.showSnackBar(SnackBar(
          content: Text(r['pago'] == true
              ? 'Pago. A loja vai juntar ao teu pedido.'.tr
              : 'O pagamento ainda não ficou confirmado.'.tr)));
    } on StripeException {
      messenger.showSnackBar(SnackBar(content: Text('Pagamento cancelado.'.tr)));
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(mensagemErroEdicao(e))));
    } finally {
      if (mounted) setState(() => _aTratar.remove(g.grupoId));
    }
  }
}

class _Caixa extends StatelessWidget {
  const _Caixa({
    required this.cor,
    required this.icone,
    required this.titulo,
    required this.texto,
    this.acoes = const [],
  });

  final Color cor;
  final IconData icone;
  final String titulo;
  final String texto;
  final List<Widget> acoes;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: cor.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: cor.withValues(alpha: 0.4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icone, color: cor, size: 20),
              const SizedBox(width: 8),
              Expanded(
                child: Text(titulo,
                    style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(texto, style: const TextStyle(fontSize: 13, height: 1.35)),
          if (acoes.isNotEmpty) ...[
            const SizedBox(height: 8),
            Row(mainAxisAlignment: MainAxisAlignment.end, children: acoes),
          ],
        ],
      ),
    );
  }
}
