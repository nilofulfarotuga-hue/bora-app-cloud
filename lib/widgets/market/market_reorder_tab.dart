import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../auth/auth_store.dart';
import '../../config/app_colors.dart';
import '../../models/order_model.dart';
import '../../screens/cart_screen.dart';
import '../../services/reorder_service.dart';
import '../../stores/cart_store.dart';
import '../../stores/order_store.dart';
import '../../stores/partner_product_store.dart';
import '../../stores/restaurant_store.dart';

/// Tab "Pedir de novo" — lista os pedidos anteriores do cliente nesta loja e
/// permite reordenar com um toque (Glovo/Uber "order again"). A lógica vive em
/// [ReorderService]; aqui só ligamos à UI. NÃO toca pricing/create_order — o
/// preço é recalculado pelo caminho normal do carrinho.
class MarketReorderTab extends StatelessWidget {
  const MarketReorderTab({
    super.key,
    required this.storeName,
    this.isPartnerStore = false,
  });

  final String storeName;
  final bool isPartnerStore;

  @override
  Widget build(BuildContext context) {
    final orderStore = context.watch<OrderStore>();
    final authStore = context.watch<AuthStore>();

    final phone = authStore.currentClient?.phone ?? '';
    final userId = authStore.userId;
    final past = orderStore
        .ordersForCurrentClient(phone: phone, userId: userId)
        .where((o) =>
            o.vendorName == storeName && ReorderService.isReorderable(o))
        .toList();

    if (past.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: 40),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.refresh_rounded, size: 64, color: Color(0xFFBDBDBD)),
              SizedBox(height: 16),
              Text(
                'Ainda sem pedidos nesta loja',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: AppColors.textPrimary,
                ),
              ),
              SizedBox(height: 8),
              Text(
                'Os teus pedidos anteriores nesta loja vão aparecer aqui para reordenar com um toque.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 14,
                  color: AppColors.textSecondary,
                  height: 1.5,
                ),
              ),
            ],
          ),
        ),
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: past.length,
      separatorBuilder: (_, __) => const SizedBox(height: 12),
      itemBuilder: (_, i) => _ReorderCard(
        order: past[i],
        onReorder: () => _reorder(context, past[i]),
      ),
    );
  }

  void _reorder(BuildContext context, OrderModel order) {
    final cart = context.read<CartStore>();
    final partnerStore = context.read<PartnerProductStore>();
    final restaurantStore = context.read<RestaurantStore>();
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);

    // Reconstrói o carrinho a partir do pedido (preço atual). Devolve os nomes
    // dos itens cujo preço/disponibilidade mudou (parceiros).
    final changed = ReorderService.applyTo(
      cart: cart,
      order: order,
      partnerStore: isPartnerStore ? partnerStore : null,
      restaurantStore: isPartnerStore ? restaurantStore : null,
    );

    navigator.push(MaterialPageRoute(builder: (_) => const CartScreen()));

    if (changed.isNotEmpty) {
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            'Alguns preços foram atualizados: ${changed.join(', ')}.',
          ),
          duration: const Duration(seconds: 5),
        ),
      );
    }
  }
}

class _ReorderCard extends StatelessWidget {
  const _ReorderCard({required this.order, required this.onReorder});

  final OrderModel order;
  final VoidCallback onReorder;

  String _formatDate(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';

  @override
  Widget build(BuildContext context) {
    final total = order.finalTotal ?? order.total;
    final itemNames = order.items.map((i) => i.name).join(', ');

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.07),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                _formatDate(order.createdAt),
                style: TextStyle(
                  fontSize: 13,
                  color: Colors.grey.shade600,
                ),
              ),
              const Spacer(),
              Text(
                '€${total.toStringAsFixed(2)}',
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.bold,
                  color: Colors.black87,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            '${order.items.length} ${order.items.length == 1 ? 'item' : 'itens'}'
            '${itemNames.isEmpty ? '' : ' · $itemNames'}',
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 13, color: Colors.grey.shade800),
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: onReorder,
              icon: const Icon(Icons.refresh_rounded, size: 18),
              label: const Text('Pedir de novo'),
              style: OutlinedButton.styleFrom(
                foregroundColor: AppColors.primary,
                side: const BorderSide(color: AppColors.primary),
                padding: const EdgeInsets.symmetric(vertical: 10),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
