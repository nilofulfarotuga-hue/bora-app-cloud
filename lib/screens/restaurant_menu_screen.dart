import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/business_view_models.dart';
import '../models/cart_item.dart';
import '../stores/cart_store.dart';
import '../stores/favorite_store.dart';
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
    final favorites = context.watch<FavoriteStore>();
    final primaryColor = Theme.of(context).colorScheme.primary;

    return Scaffold(
      backgroundColor: const Color(0xFFF5F5F5),
      appBar: AppBar(
        title: Text(
          restaurant.name,
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        backgroundColor: Colors.white,
        foregroundColor: Colors.black87,
        elevation: 0,
        actions: [
          // ── Favorite toggle ──────────────────────────────────────────────
          IconButton(
            onPressed: () => favorites.toggle('restaurant_${restaurant.name}'),
            icon: AnimatedSwitcher(
              duration: const Duration(milliseconds: 200),
              transitionBuilder: (child, anim) =>
                  ScaleTransition(scale: anim, child: child),
              child: Icon(
                favorites.isFavorite('restaurant_${restaurant.name}')
                    ? Icons.favorite
                    : Icons.favorite_border,
                key: ValueKey(
                    favorites.isFavorite('restaurant_${restaurant.name}')),
                color: favorites.isFavorite('restaurant_${restaurant.name}')
                    ? Colors.red
                    : null,
              ),
            ),
          ),
          // ── Cart badge ───────────────────────────────────────────────────
          Stack(
            alignment: Alignment.center,
            children: [
              IconButton(
                icon: const Icon(Icons.shopping_cart_outlined),
                onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const CartScreen()),
                ),
              ),
              if (cart.totalItems > 0)
                Positioned(
                  top: 8,
                  right: 8,
                  child: IgnorePointer(
                    child: CircleAvatar(
                      radius: 8,
                      backgroundColor: Colors.red,
                      child: Text(
                        '${cart.totalItems}',
                        style:
                            const TextStyle(fontSize: 10, color: Colors.white),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ],
      ),
      body: Column(
        children: [
          // ── Non-partner notice ───────────────────────────────────────────
          if (!cart.isPartnerStore)
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

          // ── Menu items ───────────────────────────────────────────────────
          Expanded(
            child: restaurant.menu.isEmpty
                ? _EmptyMenu()
                : ListView.builder(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
                    itemCount: restaurant.menu.length,
                    itemBuilder: (context, index) {
                      final item = restaurant.menu[index];
                      final favKey = 'menu_${restaurant.name}_${item.name}';
                      final isFav = favorites.isFavorite(favKey);

                      return Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: _MenuItemCard(
                          item: item,
                          isFavorite: isFav,
                          primaryColor: primaryColor,
                          onFavorite: () => favorites.toggle(favKey),
                          onAdd: () {
                            context.read<CartStore>().addItem(CartItem(
                                  name: item.name,
                                  price: item.price,
                                ));
                            ScaffoldMessenger.of(context)
                              ..hideCurrentSnackBar()
                              ..showSnackBar(
                                SnackBar(
                                  content:
                                      Text('${item.name} adicionado ao carrinho'),
                                  duration: const Duration(seconds: 2),
                                  behavior: SnackBarBehavior.floating,
                                  shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(10)),
                                  action: SnackBarAction(
                                    label: 'Ver',
                                    onPressed: () => Navigator.push(
                                      context,
                                      MaterialPageRoute(
                                          builder: (_) => const CartScreen()),
                                    ),
                                  ),
                                ),
                              );
                          },
                        ),
                      );
                    },
                  ),
          ),

          // ── Ver carrinho button ──────────────────────────────────────────
          if (cart.items.isNotEmpty)
            SafeArea(
              top: false,
              minimum: const EdgeInsets.fromLTRB(16, 8, 16, 16),
              child: SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: () => Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const CartScreen()),
                  ),
                  icon: const Icon(Icons.shopping_cart),
                  label: Text(
                    'Ver carrinho · €${cart.total.toStringAsFixed(2)}',
                    style: const TextStyle(
                        fontWeight: FontWeight.w600, fontSize: 16),
                  ),
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14)),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

// ─── Menu item card ────────────────────────────────────────────────────────────

class _MenuItemCard extends StatelessWidget {
  const _MenuItemCard({
    required this.item,
    required this.isFavorite,
    required this.primaryColor,
    required this.onFavorite,
    required this.onAdd,
  });

  final MenuItem item;
  final bool isFavorite;
  final Color primaryColor;
  final VoidCallback onFavorite;
  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onAdd,
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.05),
                blurRadius: 6,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            child: Row(
              children: [
                // ── Info ────────────────────────────────────────────────────
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        item.name,
                        style: const TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 15,
                          color: Colors.black87,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '€${item.price.toStringAsFixed(2)}',
                        style: TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 14,
                          color: primaryColor,
                        ),
                      ),
                    ],
                  ),
                ),

                // ── Favorite ─────────────────────────────────────────────
                GestureDetector(
                  onTap: onFavorite,
                  child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 200),
                    transitionBuilder: (child, anim) =>
                        ScaleTransition(scale: anim, child: child),
                    child: Icon(
                      isFavorite ? Icons.favorite : Icons.favorite_border,
                      key: ValueKey(isFavorite),
                      size: 20,
                      color: isFavorite ? Colors.red : Colors.grey.shade400,
                    ),
                  ),
                ),
                const SizedBox(width: 12),

                // ── Add button ───────────────────────────────────────────
                Container(
                  decoration: BoxDecoration(
                    color: primaryColor,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Material(
                    color: Colors.transparent,
                    child: InkWell(
                      borderRadius: BorderRadius.circular(10),
                      onTap: onAdd,
                      child: const Padding(
                        padding: EdgeInsets.all(8),
                        child: Icon(Icons.add, size: 20, color: Colors.white),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ─── Empty menu state ──────────────────────────────────────────────────────────

class _EmptyMenu extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.restaurant_menu_outlined,
                size: 72, color: Colors.grey.shade300),
            const SizedBox(height: 16),
            Text(
              'Menu indisponível',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: Colors.grey.shade600,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Este restaurante ainda não adicionou itens ao menu.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13, color: Colors.grey.shade400),
            ),
          ],
        ),
      ),
    );
  }
}
