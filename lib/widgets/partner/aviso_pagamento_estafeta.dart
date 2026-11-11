import 'package:flutter/material.dart';

import '../../config/app_colors.dart';
import '../../l10n/tr.dart';
import '../../models/order_model.dart';
import '../../utils/euros.dart';
import '../payments/loja_pagamento.dart';

/// pagar-na-loja (10/11/2026, business_rules 2.4.2) — painel do PARCEIRO.
///
/// Em cada pedido com entrega diz, em destaque, como o estafeta paga — com os
/// números do servidor (`orders.loja_pagamento_estado` / `loja_pagar_valor`):
///
/// * app + dinheiro: "O estafeta paga-te X € em dinheiro quando vier buscar o
///   pedido." (depois da recolha: "Recebeste X € em mão do estafeta …");
/// * cartão/MB Way: "Já pago pela app — não cobres nada ao estafeta. Recebes
///   no fecho semanal."
///
/// "Parceiro chama estafeta" e "ir buscar" ficam como estavam (nada aqui).
class AvisoPagamentoEstafeta extends StatelessWidget {
  const AvisoPagamentoEstafeta({super.key, required this.order});

  final OrderModel order;

  /// O texto do aviso, ou null quando não há aviso (pura, para os testes).
  static String? texto(OrderModel o) {
    switch (o.lojaPagamento) {
      case LojaPagamento.pagarLoja:
        final recolhido = o.status == OrderStatus.pickedUp ||
            o.status == OrderStatus.onTheWay ||
            o.status == OrderStatus.delivered;
        if (recolhido) {
          return 'Recebeste {0} em mão do estafeta na recolha.'
              .trArgs([eur(o.finalPurchaseValue ?? o.lojaPagarValor)]);
        }
        return 'O estafeta paga-te {0} em dinheiro quando vier buscar o pedido.'
            .trArgs([eur(o.lojaPagarValor)]);
      case LojaPagamento.jaPago:
        return 'Já pago pela app — não cobres nada ao estafeta. Recebes no fecho semanal.'
            .tr;
      case LojaPagamento.fazerCompra:
      case LojaPagamento.parceiroChamou:
      case LojaPagamento.irBuscar:
      case null:
        return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = texto(order);
    if (t == null) return const SizedBox.shrink();
    final dinheiro = order.lojaPagamento == LojaPagamento.pagarLoja;
    final cor = dinheiro ? AppColors.accent : AppColors.primary;
    return Container(
      key: const Key('aviso_pagamento_estafeta'),
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: cor.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: cor, width: 2),
      ),
      child: Row(
        children: [
          Icon(dinheiro ? Icons.payments : Icons.check_circle,
              color: cor, size: 28),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              t,
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w800,
                color: AppColors.textPrimary,
                height: 1.25,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
