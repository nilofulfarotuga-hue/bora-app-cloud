import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../data/fake_data.dart';
import '../stores/cart_store.dart';
import '../models/cart_item.dart';
import 'cart_screen.dart';

class RestaurantMenuScreen extends StatelessWidget {

  final Restaurant restaurant;

  const RestaurantMenuScreen({
    super.key,
    required this.restaurant,
  });

  @override
  Widget build(BuildContext context) {

    final cart = context.watch<CartStore>();

    return Scaffold(

      appBar: AppBar(
        title: Text(restaurant.name),
      ),

      body: Column(

        children: [

          if (!cart.isPartnerStore)
            Container(
              width: double.infinity,
              color: Colors.orange.shade50,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              child: Row(
                children: [
                  Icon(Icons.info_outline, color: Colors.orange.shade700, size: 20),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Um estafeta irá comprar estes itens por você. Os preços já incluem a taxa de compra (15%).',
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
            child: ListView.builder(

              itemCount: restaurant.menu.length,

              itemBuilder: (context, index) {

                final item = restaurant.menu[index];

                return Card(
                  margin: const EdgeInsets.all(12),

                  child: ListTile(

                    title: Text(
                      item.name,
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                      ),
                    ),

                    subtitle: Text(
                      "€${item.price.toStringAsFixed(2)}",
                    ),

                    trailing: ElevatedButton(

                      onPressed: () {

                        final cartItem = CartItem(
                          name: item.name,
                          price: item.price,
                        );

                        context.read<CartStore>().addItem(cartItem);

                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text("${item.name} adicionado ao carrinho"),
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

          if (cart.items.isNotEmpty)

            Container(

              padding: const EdgeInsets.all(16),
              width: double.infinity,

              child: ElevatedButton(

                onPressed: () {

                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => const CartScreen(),
                    ),
                  );

                },

                child: Text(
                  "Ver Carrinho (€${cart.total.toStringAsFixed(2)})",
                ),

              ),

            )

        ],

      ),

    );
  }
}