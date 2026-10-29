import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../auth/auth_store.dart';
import '../../config/app_colors.dart';
import '../../config/app_spacing.dart';
import '../../l10n/tr.dart';
import '../../models/order_model.dart';
import '../../screens/orders_screen.dart' show pedirDeNovoPedido;
import '../../services/interruptores_app.dart';
import '../../services/reorder_service.dart';
import '../../stores/order_store.dart';
import '../../utils/euros.dart';

/// Os pedidos que a página inicial oferece como "habituais": os últimos [max]
/// pedidos ENTREGUES de restaurante ou loja, sem repetir o mesmo pedido (mesma
/// loja e mesmos produtos nas mesmas quantidades). O mais recente primeiro.
List<OrderModel> escolherHabituais(Iterable<OrderModel> pedidosDoCliente,
    {int max = 3}) {
  final entregues = pedidosDoCliente
      .where((o) =>
          o.status == OrderStatus.delivered && ReorderService.isReorderable(o))
      .toList()
    ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
  final vistos = <String>{};
  final out = <OrderModel>[];
  for (final o in entregues) {
    if (vistos.add(_assinatura(o))) out.add(o);
    if (out.length == max) break;
  }
  return out;
}

String _assinatura(OrderModel o) {
  final linhas = o.items.map((i) => '${i.productId}x${i.quantity}').toList()
    ..sort();
  return '${(o.vendorName ?? '').toLowerCase()}|${linhas.join(',')}';
}

/// "2× Menu Boom, 1× Coca-Cola" (corta com reticências quando é longo).
String resumoDosProdutos(OrderModel o, {int maxLinhas = 2}) {
  final linhas = o.items.map((i) => '${i.quantity}× ${i.name}').toList();
  if (linhas.length <= maxLinhas) return linhas.join(', ');
  return '${linhas.take(maxLinhas).join(', ')} +${linhas.length - maxLinhas}';
}

/// "Os meus habituais" no topo da página inicial (adendo 4 · item 6,
/// 29/10/2026): até 3 pedidos anteriores com um toque para repetir, pelo
/// mesmo fluxo do "Pedir de novo" da lista de pedidos (mesmas travas: loja
/// fechada, loja que já não existe, carrinho com artigos de outra loja).
/// Só aparece com pedidos entregues e com `feature_habituais_home` ligado.
class MeusHabituais extends StatefulWidget {
  const MeusHabituais({super.key, this.aoRepetir});

  /// Para testes: o que fazer ao tocar. Por defeito, o "Pedir de novo".
  final void Function(OrderModel pedido)? aoRepetir;

  @override
  State<MeusHabituais> createState() => _MeusHabituaisState();
}

class _MeusHabituaisState extends State<MeusHabituais> {
  bool _ligado = true;

  @override
  void initState() {
    super.initState();
    InterruptoresApp.instance.ligado(InterruptoresApp.habituaisHome).then((v) {
      if (mounted && v != _ligado) setState(() => _ligado = v);
    });
  }

  @override
  Widget build(BuildContext context) {
    if (!_ligado) return const SizedBox.shrink();
    final auth = context.watch<AuthStore>();
    final store = context.watch<OrderStore>();
    final doCliente = store.ordersForCurrentClient(
        phone: auth.currentClient?.phone, userId: auth.userId);
    final habituais = escolherHabituais(doCliente);
    if (habituais.isEmpty) return const SizedBox.shrink();
    return Padding(
      key: const Key('meus_habituais'),
      padding: const EdgeInsets.only(bottom: Spacing.xl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Os meus habituais'.tr,
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: Spacing.sm),
          SizedBox(
            height: 132,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: habituais.length,
              separatorBuilder: (_, __) => const SizedBox(width: Spacing.sm),
              itemBuilder: (context, i) {
                final o = habituais[i];
                return _CartaoHabitual(
                  pedido: o,
                  onRepetir: () => (widget.aoRepetir ?? (p) {
                    pedirDeNovoPedido(context, p);
                  })(o),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _CartaoHabitual extends StatelessWidget {
  const _CartaoHabitual({required this.pedido, required this.onRepetir});

  final OrderModel pedido;
  final VoidCallback onRepetir;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 270,
      padding: const EdgeInsets.all(Spacing.md),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(Radii.lg),
        boxShadow: AppColors.shadowCard,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            pedido.vendorName ?? pedido.serviceType.label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 2),
          Text(
            resumoDosProdutos(pedido),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
                fontSize: 16, color: AppColors.textSecondary, height: 1.25),
          ),
          const Spacer(),
          Row(
            children: [
              Expanded(
                child: Text(
                  eur(pedido.total),
                  style: const TextStyle(
                      fontSize: 16, fontWeight: FontWeight.w600),
                ),
              ),
              FilledButton.icon(
                key: Key('repetir_${pedido.id}'),
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  minimumSize: const Size(0, 44),
                ),
                onPressed: onRepetir,
                icon: const Icon(Icons.refresh, size: 20),
                label: Text('Repetir'.tr),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
