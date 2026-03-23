import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../data/fake_data.dart';
import '../models/cart_item.dart';
import '../stores/cart_store.dart';
import 'cart_screen.dart';

class StoreProductsScreen extends StatelessWidget {
  final RetailStore store;

  const StoreProductsScreen({super.key, required this.store});

  @override
  Widget build(BuildContext context) {
    final products = store.products;
    final cartStore = context.watch<CartStore>();
    final isPartner = cartStore.isPartnerStore;

    return Scaffold(
      appBar: AppBar(
        title: Text(store.name),
        actions: [
          IconButton(
            icon: const Icon(Icons.shopping_cart),
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => const CartScreen(),
                ),
              );
            },
          ),
        ],
      ),
      body: Column(
        children: [
          if (!isPartner)
            Container(
              width: double.infinity,
              color: Colors.orange.shade50,
              padding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              child: Row(
                children: [
                  Icon(Icons.info_outline,
                      color: Colors.orange.shade700, size: 20),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Adicione itens livremente — um estafeta irá comprar por você. Os preços incluem a taxa de compra (15%).',
                      style: TextStyle(
                        color: Colors.orange.shade800,
                        fontSize: 13,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          Expanded(
            child: products.isEmpty
                ? const Center(
                    child: Text("Nenhum produto disponível no momento."),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 12),
                    itemCount: products.length,
                    itemBuilder: (context, index) {
                      final product = products[index];

                      return Card(
                        margin: const EdgeInsets.symmetric(vertical: 8),
                        child: ListTile(
                          title: Text(product.name),
                          subtitle:
                              Text("€${product.price.toStringAsFixed(2)}"),
                          trailing: ElevatedButton(
                            onPressed: () {
                              context.read<CartStore>().addItem(
                                    CartItem(
                                      name: product.name,
                                      price: product.price,
                                    ),
                                  );

                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text(
                                    "${product.name} adicionado ao carrinho",
                                  ),
                                ),
                              );
                            },
                            child: const Text("Adicionar"),
                          ),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}
