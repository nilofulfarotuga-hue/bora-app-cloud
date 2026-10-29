import 'package:flutter/material.dart';

import '../../config/app_colors.dart';
import '../../models/order_edit.dart';
import '../../models/order_model.dart';
import '../../services/order_edit_service.dart';
import '../../utils/conta_curta_dinheiro.dart';

/// Estafeta: a loja parceira mudou a lista do pedido que ele leva (PT-PT).
/// A lista e o valor a cobrar já chegam actualizados pelo tempo real de
/// `orders`; isto só diz O QUÊ mudou, para ele não estranhar na recolha.
class DriverOrderEditNotice extends StatefulWidget {
  const DriverOrderEditNotice({super.key, required this.order});

  final OrderModel order;

  @override
  State<DriverOrderEditNotice> createState() => _DriverOrderEditNoticeState();
}

class _DriverOrderEditNoticeState extends State<DriverOrderEditNotice> {
  // Criados UMA vez: o ecrã do estafeta redesenha a cada posição GPS e um
  // stream novo por redesenho abria um canal de tempo real novo de cada vez.
  late final Future<bool> _ativo = OrderEditService.instance.ativo();
  late final Stream<List<OrderEditGrupo>> _grupos =
      OrderEditService.instance.gruposDoPedido(widget.order.id);

  @override
  Widget build(BuildContext context) {
    final order = widget.order;
    if (!order.isPartnerStore) return const SizedBox.shrink();
    return FutureBuilder<bool>(
      future: _ativo,
      builder: (context, on) {
        if (on.data != true) return const SizedBox.shrink();
        return _conteudo(order);
      },
    );
  }

  Widget _conteudo(OrderModel order) {
    return StreamBuilder<List<OrderEditGrupo>>(
      stream: _grupos,
      builder: (context, snap) {
        final aplicados = (snap.data ?? const <OrderEditGrupo>[])
            .where((g) => g.estado == OrderEditEstado.aplicado)
            .toList();
        if (aplicados.isEmpty) return const SizedBox.shrink();
        final linhas = aplicados
            .map((g) => '${g.eTirar ? 'Saiu' : 'Entrou'}: ${g.resumo}')
            .join('\n');
        // 28/10/2026 (C3): com saldo/tokens, a conta curta diz de onde vem o
        // valor (a mesma linha dos cartões e da faixa laranja).
        final curta = contaCurtaDinheiro(order);
        final cobrar = order.paymentMethod == PaymentMethod.cash
            ? '\nCobra ${order.totalToCollectCash.toStringAsFixed(2).replaceAll('.', ',')} € na entrega.'
                '${curta != null ? '\n$curta' : ''}'
            : '';
        return Container(
          width: double.infinity,
          margin: const EdgeInsets.only(top: 8),
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: AppColors.info.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: AppColors.info.withValues(alpha: 0.4)),
          ),
          child: Text(
            'A loja alterou o pedido.\n$linhas$cobrar',
            style: const TextStyle(fontSize: 13, height: 1.35),
          ),
        );
      },
    );
  }
}
