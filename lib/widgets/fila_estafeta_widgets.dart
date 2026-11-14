// Fila do estafeta no mapa (14/11/2026 — compra guardada + adenda 1).
//
// - PedidosAtivosSeletor: com mais de um pedido ativo (mesma loja), mostra
//   qual está ABERTO (loja e cliente) e troca com um toque. Nunca troca sozinho.
// - FilaEmEsperaContador: "Tens N na fila" — os aceites por cima do pedido em
//   curso, pela ordem em que vão abrir (só leitura: abrem quando ele entregar).

import 'package:flutter/material.dart';

import '../models/order_model.dart';
import '../services/fila_estafeta.dart';
import 'cliente_nome_destaque.dart';

String _tipoPedido(OrderModel o) {
  if (o.serviceType == OrderServiceType.errand) {
    return FilaEstafeta.classe(o) == 1 ? 'Favor urgente' : 'Favor';
  }
  return switch (o.serviceType) {
    OrderServiceType.restaurant => 'Restaurante',
    OrderServiceType.storeShopping => 'Compras',
    OrderServiceType.carryGroceries => 'Levar compras',
    OrderServiceType.sendPackage => 'Encomenda',
    _ => 'Pedido',
  };
}

String _loja(OrderModel o) {
  final v = o.vendorName?.trim() ?? '';
  return v.isNotEmpty ? v : _tipoPedido(o);
}

/// "Auchan — cliente Maria" (o mesmo texto no aviso "Próximo pedido").
String descreverPedidoFila(OrderModel o) {
  final cliente = ClienteNomeDestaque.limpo(o.customerName);
  final base = o.serviceType == OrderServiceType.errand
      ? _tipoPedido(o)
      : '${_tipoPedido(o)} · ${_loja(o)}';
  return cliente == null || cliente.isEmpty ? base : '$base — cliente $cliente';
}

class PedidosAtivosSeletor extends StatelessWidget {
  const PedidosAtivosSeletor({
    super.key,
    required this.pedidos,
    required this.abertoId,
    this.onEscolher,
  });

  final List<OrderModel> pedidos;
  final String abertoId;
  final ValueChanged<String>? onEscolher;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Pedido aberto',
          style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: Colors.grey.shade700),
        ),
        const SizedBox(height: 6),
        Wrap(
          spacing: 8,
          runSpacing: 6,
          children: [
            for (final o in pedidos)
              ChoiceChip(
                key: ValueKey('pedido_ativo_${o.id}'),
                selected: o.id == abertoId,
                showCheckmark: true,
                selectedColor: Colors.green.shade100,
                label: Text(
                  descreverPedidoFila(o),
                  style: const TextStyle(fontSize: 12.5),
                  overflow: TextOverflow.ellipsis,
                ),
                onSelected: onEscolher == null || o.id == abertoId
                    ? null
                    : (_) => onEscolher!(o.id),
              ),
          ],
        ),
      ],
    );
  }
}

class FilaEmEsperaContador extends StatelessWidget {
  const FilaEmEsperaContador({super.key, required this.emEspera});

  final List<OrderModel> emEspera;

  void _verFila(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Pedidos na fila',
                  style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
              const SizedBox(height: 4),
              Text(
                'Abrem por esta ordem, um de cada vez, quando entregares o '
                'pedido atual.',
                style: TextStyle(fontSize: 13, color: Colors.grey.shade700),
              ),
              const SizedBox(height: 12),
              for (var i = 0; i < emEspera.length; i++)
                ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  leading: CircleAvatar(
                    radius: 14,
                    backgroundColor: Colors.orange.shade100,
                    child: Text('${i + 1}',
                        style: TextStyle(
                            fontWeight: FontWeight.w700,
                            color: Colors.orange.shade900)),
                  ),
                  title: Text(descreverPedidoFila(emEspera[i])),
                  subtitle: FilaEstafeta.classe(emEspera[i]) == 1
                      ? const Text('Urgente: abre logo a seguir ao atual')
                      : null,
                ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final n = emEspera.length;
    return Semantics(
      identifier: 'fila_em_espera',
      button: true,
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => _verFila(context),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: Colors.orange.shade50,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.orange.shade200),
          ),
          child: Row(
            children: [
              Icon(Icons.queue, size: 18, color: Colors.orange.shade800),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  n == 1 ? 'Tens 1 pedido na fila' : 'Tens $n pedidos na fila',
                  style: const TextStyle(
                      fontWeight: FontWeight.w700, fontSize: 14),
                ),
              ),
              Text('Abre ao entregar',
                  style: TextStyle(fontSize: 12, color: Colors.grey.shade700)),
              const SizedBox(width: 4),
              Icon(Icons.chevron_right, color: Colors.grey.shade600),
            ],
          ),
        ),
      ),
    );
  }
}
