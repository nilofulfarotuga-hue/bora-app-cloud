import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../config/app_colors.dart';
import '../config/app_spacing.dart';
import '../stores/cart_store.dart';
import '../widgets/bora/bora.dart';
import '../widgets/tip_selector.dart';
import 'orders_screen.dart';
import 'payment_method_screen.dart';

class CartScreen extends StatelessWidget {
  const CartScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final cartStore = context.watch<CartStore>();
    final pricing = cartStore.pricingBreakdown;

    final apartmentEnabled = cartStore.apartmentDelivery;
    double baseDeliveryFee = pricing.deliveryFee - pricing.apartmentSurcharge;
    if (baseDeliveryFee < 0) {
      baseDeliveryFee = 0;
    }
    // Takeaway (BR §14.9) — client skips delivery fee entirely.
    // Gorjeta (BR §4.5) — somada ao total final (split 80/20 a jusante).
    final totalToPay = (cartStore.isTakeaway
            ? (pricing.customerTotal - pricing.deliveryFee)
            : pricing.customerTotal) +
        cartStore.tipEur;

    return Scaffold(
      backgroundColor: AppColors.surface,
      appBar: AppBar(
        title: const Text('Carrinho'),
        backgroundColor: Colors.transparent,
        foregroundColor: Colors.white,
        elevation: 0,
        flexibleSpace: const DecoratedBox(
          decoration: BoxDecoration(gradient: AppColors.headerGradient),
        ),
      ),
      body: Column(
        children: [
          Expanded(
            child: cartStore.items.isEmpty
                ? const _EmptyCart()
                : ListView.separated(
                    padding: const EdgeInsets.fromLTRB(
                      Spacing.lg,
                      Spacing.md,
                      Spacing.lg,
                      Spacing.lg,
                    ),
                    itemCount: cartStore.items.length,
                    separatorBuilder: (_, __) =>
                        const SizedBox(height: Spacing.sm),
                    itemBuilder: (context, index) {
                      final item = cartStore.items[index];
                      return _CartItemTile(
                        name: item.name,
                        price: item.price,
                        quantity: item.quantity,
                        onDecrease: () => cartStore.decreaseQuantity(item),
                        onIncrease: () => cartStore.increaseQuantity(item),
                        onRemove: () => cartStore.removeItem(item),
                      );
                    },
                  ),
          ),
          _CheckoutPanel(
            cartStore: cartStore,
            pricing: pricing,
            apartmentEnabled: apartmentEnabled,
            baseDeliveryFee: baseDeliveryFee,
            totalToPay: totalToPay,
          ),
        ],
      ),
    );
  }
}

class _EmptyCart extends StatelessWidget {
  const _EmptyCart();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.shopping_cart_outlined,
            size: 64,
            color: AppColors.textSecondary.withValues(alpha: 0.5),
          ),
          const SizedBox(height: Spacing.md),
          const Text(
            'O carrinho está vazio.',
            style: TextStyle(
              fontSize: 16,
              color: AppColors.textSecondary,
            ),
          ),
        ],
      ),
    );
  }
}

class _CartItemTile extends StatelessWidget {
  const _CartItemTile({
    required this.name,
    required this.price,
    required this.quantity,
    required this.onDecrease,
    required this.onIncrease,
    required this.onRemove,
  });

  final String name;
  final double price;
  final int quantity;
  final VoidCallback onDecrease;
  final VoidCallback onIncrease;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(
          Spacing.md, Spacing.sm, Spacing.xs, Spacing.sm),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(Radii.md),
        border: Border.all(color: AppColors.divider),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '€${price.toStringAsFixed(2)}',
                  style: const TextStyle(
                    fontSize: 14,
                    color: AppColors.textSecondary,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.remove_circle_outline),
            color: AppColors.textSecondary,
            onPressed: onDecrease,
          ),
          Text(
            '$quantity',
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: AppColors.textPrimary,
            ),
          ),
          IconButton(
            icon: const Icon(Icons.add_circle_outline),
            color: AppColors.primary,
            onPressed: onIncrease,
          ),
          IconButton(
            icon: const Icon(Icons.delete_outline),
            color: AppColors.error,
            onPressed: onRemove,
          ),
        ],
      ),
    );
  }
}

class _CheckoutPanel extends StatelessWidget {
  const _CheckoutPanel({
    required this.cartStore,
    required this.pricing,
    required this.apartmentEnabled,
    required this.baseDeliveryFee,
    required this.totalToPay,
  });

  final CartStore cartStore;
  final dynamic pricing;
  final bool apartmentEnabled;
  final double baseDeliveryFee;
  final double totalToPay;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      minimum: const EdgeInsets.only(bottom: Spacing.lg),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.fromLTRB(
          Spacing.xl,
          Spacing.xl,
          Spacing.xl,
          Spacing.lg,
        ),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius:
              const BorderRadius.vertical(top: Radius.circular(Radii.xl)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.08),
              blurRadius: 12,
              offset: const Offset(0, -4),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (cartStore.isPartnerStore)
              SwitchListTile.adaptive(
                value: cartStore.isTakeaway,
                onChanged: cartStore.items.isEmpty
                    ? null
                    : (value) => cartStore.setTakeaway(value),
                contentPadding: EdgeInsets.zero,
                activeColor: AppColors.primary,
                title: const Text(
                  'Ir buscar (takeaway, sem entrega)',
                  style: TextStyle(fontWeight: FontWeight.w600),
                ),
                subtitle: const Text(
                  'Sem taxa de entrega. Recebes aviso quando estiver pronto. (BR §14.9)',
                  style: TextStyle(fontSize: 12),
                ),
              ),
            SwitchListTile.adaptive(
              value: apartmentEnabled,
              onChanged: cartStore.items.isEmpty || cartStore.isTakeaway
                  ? null
                  : (value) => cartStore.setApartmentDelivery(value),
              contentPadding: EdgeInsets.zero,
              activeColor: AppColors.primary,
              title: const Text(
                'Entregar no apartamento (+€1.50)',
                style: TextStyle(fontWeight: FontWeight.w600),
              ),
            ),
            const SizedBox(height: Spacing.sm),
            _SummaryRow(label: 'Subtotal', value: cartStore.total),
            if (pricing.serviceFee > 0)
              _SummaryRow(
                  label: 'Taxa de serviço', value: pricing.serviceFee),
            _SummaryRow(
              label: cartStore.isTakeaway ? 'Entrega (takeaway)' : 'Entrega',
              value: cartStore.isTakeaway ? 0.0 : baseDeliveryFee,
            ),
            if (pricing.apartmentSurcharge > 0)
              _SummaryRow(
                label: 'Entrega em apartamento',
                value: pricing.apartmentSurcharge,
              ),
            if (pricing.bagFee > 0)
              _SummaryRow(
                  label: 'Saco para viagem', value: pricing.bagFee),
            const SizedBox(height: Spacing.md),
            TipSelector(
              initialCents: cartStore.tipCents,
              enabled: cartStore.items.isNotEmpty,
              onChanged: (cents) => cartStore.setTipCents(cents),
            ),
            if (cartStore.tipCents > 0)
              _SummaryRow(
                  label: 'Gorjeta', value: cartStore.tipEur, accent: true),
            const Divider(height: Spacing.xxl),
            _SummaryRow(
              label: 'Total a pagar',
              value: totalToPay,
              isStrong: true,
            ),
            const SizedBox(height: Spacing.lg),
            BoraPrimaryButton(
              label: 'Finalizar pedido',
              icon: Icons.shopping_bag_outlined,
              onPressed: cartStore.items.isEmpty
                  ? null
                  : () async {
                      final confirmed = await Navigator.push<bool>(
                        context,
                        MaterialPageRoute(
                          builder: (_) => const PaymentMethodScreen(),
                        ),
                      );
                      if (confirmed == true && context.mounted) {
                        Navigator.of(context)
                            .popUntil((route) => route.isFirst);
                        Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => const OrdersScreen(),
                          ),
                        );
                      }
                    },
            ),
          ],
        ),
      ),
    );
  }
}

class _SummaryRow extends StatelessWidget {
  const _SummaryRow({
    required this.label,
    required this.value,
    this.isStrong = false,
    this.accent = false,
  });

  final String label;
  final double value;
  final bool isStrong;
  final bool accent;

  @override
  Widget build(BuildContext context) {
    final color = accent
        ? AppColors.accent
        : (isStrong ? AppColors.textPrimary : AppColors.textSecondary);
    final style = TextStyle(
      fontSize: isStrong ? 16 : 14,
      fontWeight: isStrong ? FontWeight.w800 : FontWeight.w500,
      color: color,
    );

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: Spacing.xs),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: style),
          Text('€${value.toStringAsFixed(2)}', style: style),
        ],
      ),
    );
  }
}
