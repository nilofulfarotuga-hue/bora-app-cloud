import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../stores/cart_store.dart';
import 'orders_screen.dart';
import 'payment_method_screen.dart';



class CartScreen extends StatelessWidget {
  const CartScreen({super.key});

  @override
  Widget build(BuildContext context) {

                        final cartStore = context.watch<CartStore>();
    final pricing = cartStore.pricingBreakdown;

    final totalToPay = pricing.customerTotal;
    final apartmentEnabled = cartStore.apartmentDelivery;
    double baseDeliveryFee = pricing.deliveryFee - pricing.apartmentSurcharge;
    if (baseDeliveryFee < 0) {
      baseDeliveryFee = 0;
    }


    return Scaffold(
      appBar: AppBar(
        title: const Text("Carrinho"),
      ),
      body: Column(
        children: [
          Expanded(
            child: cartStore.items.isEmpty
                ? const Center(child: Text("O carrinho está vazio."))
                : ListView.builder(
                    itemCount: cartStore.items.length,
                    itemBuilder: (context, index) {
                      final item = cartStore.items[index];
                      return ListTile(
                        title: Text(item.name),
                        subtitle: Text("€${item.price.toStringAsFixed(2)}"),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              icon: const Icon(Icons.remove_circle_outline),
                              onPressed: () =>
                                  cartStore.decreaseQuantity(item),
                            ),
                            Text("${item.quantity}",
                                style: const TextStyle(fontSize: 16)),
                            IconButton(
                              icon: const Icon(Icons.add_circle_outline),
                              onPressed: () =>
                                  cartStore.increaseQuantity(item),
                            ),
                            IconButton(
                              icon: const Icon(Icons.delete_outline,
                                  color: Colors.red),
                              onPressed: () => cartStore.removeItem(item),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
          ),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.grey.shade100,
              borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
            ),
                        child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SwitchListTile.adaptive(
                  value: apartmentEnabled,
                  onChanged: cartStore.items.isEmpty
                      ? null
                      : (value) => cartStore.setApartmentDelivery(value),
                  contentPadding: EdgeInsets.zero,
                  title: const Text("Entregar no apartamento (+€1.50)"),
                  subtitle: const Text("Inclui bônus de €1 para o estafeta."),
                ),
                const SizedBox(height: 8),
                _SummaryRow(

                  label: "Subtotal",
                  value: cartStore.total,
                ),
                if (!cartStore.isPartnerStore)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Row(
                      children: [
                        Icon(Icons.shopping_bag_outlined,
                            size: 14, color: Colors.orange.shade700),
                        const SizedBox(width: 6),
                        Text(
                          'Taxa de compra incluída nos preços',
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.orange.shade800,
                          ),
                        ),
                      ],
                    ),
                  ),
                if (pricing.serviceFee > 0)
                  _SummaryRow(
                    label: "Taxa de serviço",
                    value: pricing.serviceFee,
                  ),
                                _SummaryRow(
                  label: "Entrega",
                  value: baseDeliveryFee,
                ),
                if (pricing.apartmentSurcharge > 0)
                  _SummaryRow(
                    label: "Entrega em apartamento",
                    value: pricing.apartmentSurcharge,
                  ),

                const Divider(height: 24),
                _SummaryRow(
                  label: "Total a pagar",
                  value: totalToPay,
                  isStrong: true,
                ),
                const SizedBox(height: 16),
                                ElevatedButton(
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
                  child: const Text("Finalizar pedido"),
                ),

              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SummaryRow extends StatelessWidget {
  final String label;
  final double value;
  final bool isStrong;

  const _SummaryRow({
    required this.label,
    required this.value,
    this.isStrong = false,
  });

  @override
  Widget build(BuildContext context) {
    final textStyle = Theme.of(context).textTheme.bodyMedium?.copyWith(
          fontWeight: isStrong ? FontWeight.bold : FontWeight.normal,
        );

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: textStyle),
          Text("€${value.toStringAsFixed(2)}", style: textStyle),
        ],
      ),
    );
  }
}