import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../auth/auth_store.dart';
import '../stores/order_store.dart';
import '../models/order_model.dart';
import 'order_details_screen.dart';

class OrdersScreen extends StatefulWidget {
  const OrdersScreen({super.key});

  @override
  State<OrdersScreen> createState() => _OrdersScreenState();
}

class _OrdersScreenState extends State<OrdersScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) context.read<OrderStore>().loadOrders();
    });
  }

  @override
  Widget build(BuildContext context) {
    final store = context.watch<OrderStore>();
    final phone = context.watch<AuthStore>().currentClient?.phone ?? '';

    final orders = store.ordersForClient(phone);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Pedidos'),
      ),
      body: orders.isEmpty
          ? const Center(child: Text('Nenhum pedido'))
          : ListView.builder(
              itemCount: orders.length,
              itemBuilder: (context, index) {
                final order = orders[index];
                return ListTile(
                  title: Text('Pedido €${order.total.toStringAsFixed(2)}'),
                  subtitle: Text(
                    order.isPurchaseFinalized && order.finalTotal != null
                        ? '${order.status.label} · Comprado · €${order.finalTotal!.toStringAsFixed(2)}'
                        : order.status.label,
                  ),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => OrderDetailsScreen(order: order),
                      ),
                    );
                  },
                );
              },
            ),
    );
  }
}
