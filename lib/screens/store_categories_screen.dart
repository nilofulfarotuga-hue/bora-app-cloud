import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/partner_product.dart';
import '../stores/cart_store.dart';
import '../stores/restaurant_store.dart';
import 'cart_screen.dart';
import 'store_products_screen.dart';

class StoreCategoriesScreen extends StatelessWidget {
  const StoreCategoriesScreen({
    super.key,
    required this.restaurantId,
    required this.storeName,
  });

  final String restaurantId;
  final String storeName;

  static const _categoryIcons = <String, IconData>{
    'frutas': Icons.eco_rounded,
    'legumes': Icons.eco_rounded,
    'verduras': Icons.eco_rounded,
    'bebidas': Icons.local_drink_rounded,
    'águas': Icons.water_drop_rounded,
    'aguas': Icons.water_drop_rounded,
    'carnes': Icons.set_meal_rounded,
    'peixe': Icons.set_meal_rounded,
    'peixaria': Icons.set_meal_rounded,
    'padaria': Icons.bakery_dining_rounded,
    'pão': Icons.bakery_dining_rounded,
    'laticínios': Icons.egg_alt_rounded,
    'laticinios': Icons.egg_alt_rounded,
    'higiene': Icons.clean_hands_rounded,
    'limpeza': Icons.cleaning_services_rounded,
    'congelados': Icons.ac_unit_rounded,
    'snacks': Icons.fastfood_rounded,
    'bolachas': Icons.cookie_rounded,
    'cereais': Icons.breakfast_dining_rounded,
    'conservas': Icons.inventory_2_rounded,
    'mercearia': Icons.store_rounded,
    'animais': Icons.pets_rounded,
    'pet': Icons.pets_rounded,
    'farmácia': Icons.local_pharmacy_rounded,
    'farmacia': Icons.local_pharmacy_rounded,
    'flores': Icons.local_florist_rounded,
  };

  static const _categoryColors = <String, Color>{
    'frutas': Color(0xFF4CAF50),
    'legumes': Color(0xFF66BB6A),
    'verduras': Color(0xFF43A047),
    'bebidas': Color(0xFF1E88E5),
    'águas': Color(0xFF29B6F6),
    'aguas': Color(0xFF29B6F6),
    'carnes': Color(0xFFE53935),
    'peixe': Color(0xFF00ACC1),
    'peixaria': Color(0xFF00ACC1),
    'padaria': Color(0xFFF4511E),
    'laticínios': Color(0xFFFFA726),
    'laticinios': Color(0xFFFFA726),
    'higiene': Color(0xFF7E57C2),
    'limpeza': Color(0xFF26C6DA),
    'congelados': Color(0xFF5C6BC0),
    'snacks': Color(0xFFFF7043),
    'bolachas': Color(0xFFBF8A30),
    'mercearia': Color(0xFF546E7A),
    'animais': Color(0xFF8D6E63),
    'pet': Color(0xFF8D6E63),
  };

  IconData _iconFor(String category) {
    final key = category.toLowerCase();
    for (final entry in _categoryIcons.entries) {
      if (key.contains(entry.key)) return entry.value;
    }
    return Icons.category_rounded;
  }

  Color _colorFor(String category) {
    final key = category.toLowerCase();
    for (final entry in _categoryColors.entries) {
      if (key.contains(entry.key)) return entry.value;
    }
    return const Color(0xFF455A64);
  }

  String _categoryOf(PartnerProduct p) {
    if (p.category.isNotEmpty) {
      final c = p.category.trim();
      return c[0].toUpperCase() + c.substring(1).toLowerCase();
    }
    final first = p.name.split(' ').first;
    return first[0].toUpperCase() + first.substring(1).toLowerCase();
  }

  @override
  Widget build(BuildContext context) {
    final cartStore = context.watch<CartStore>();
    final restaurantStore = context.watch<RestaurantStore>();
    final products = restaurantStore.partnerProductsForRestaurant(
      restaurantId,
      onlyAvailable: true,
    );

    final categoryMap = <String, int>{};
    for (final p in products) {
      final cat = _categoryOf(p);
      categoryMap[cat] = (categoryMap[cat] ?? 0) + 1;
    }
    final categories = categoryMap.entries.toList()
      ..sort((a, b) => a.key.compareTo(b.key));

    return Scaffold(
      backgroundColor: const Color(0xFFF5F5F5),
      appBar: AppBar(
        title: Text(
          storeName,
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        backgroundColor: Colors.white,
        foregroundColor: Colors.black87,
        elevation: 0,
        actions: [_CartBadge(cartStore: cartStore)],
      ),
      body: Column(
        children: [
          Container(
            color: Colors.white,
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
            child: _AllProductsTile(
              total: products.length,
              onTap: () => _openProducts(context, null),
            ),
          ),
          const SizedBox(height: 4),
          Expanded(
            child: categories.isEmpty
                ? const Center(child: Text('Nenhuma categoria disponível.'))
                : GridView.builder(
                    padding: const EdgeInsets.all(16),
                    gridDelegate:
                        const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 2,
                      mainAxisSpacing: 12,
                      crossAxisSpacing: 12,
                      childAspectRatio: 1.4,
                    ),
                    itemCount: categories.length,
                    itemBuilder: (context, i) {
                      final cat = categories[i].key;
                      final count = categories[i].value;
                      return _CategoryCard(
                        name: cat,
                        count: count,
                        icon: _iconFor(cat),
                        color: _colorFor(cat),
                        onTap: () => _openProducts(context, cat),
                      );
                    },
                  ),
          ),
          if (cartStore.items.isNotEmpty)
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
                    'Ver carrinho · €${cartStore.total.toStringAsFixed(2)}',
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

  void _openProducts(BuildContext context, String? category) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => StoreProductsScreen(
          restaurantId: restaurantId,
          storeName: storeName,
          initialCategory: category,
        ),
      ),
    );
  }
}

// ─── All products tile ─────────────────────────────────────────────────────────

class _AllProductsTile extends StatelessWidget {
  const _AllProductsTile({required this.total, required this.onTap});

  final int total;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: primary.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: primary.withValues(alpha: 0.2)),
        ),
        child: Row(
          children: [
            Icon(Icons.grid_view_rounded, color: primary),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Ver todos os produtos',
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 15,
                      color: primary,
                    ),
                  ),
                  Text(
                    '$total ${total == 1 ? 'produto disponível' : 'produtos disponíveis'}',
                    style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                  ),
                ],
              ),
            ),
            Icon(Icons.arrow_forward_ios, size: 14, color: primary),
          ],
        ),
      ),
    );
  }
}

// ─── Category card ─────────────────────────────────────────────────────────────

class _CategoryCard extends StatelessWidget {
  const _CategoryCard({
    required this.name,
    required this.count,
    required this.icon,
    required this.color,
    required this.onTap,
  });

  final String name;
  final int count;
  final IconData icon;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.06),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, color: color, size: 24),
              ),
              const Spacer(),
              Text(
                name,
                style: const TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 14,
                  color: Colors.black87,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 2),
              Text(
                '$count ${count == 1 ? 'produto' : 'produtos'}',
                style: TextStyle(fontSize: 11, color: Colors.grey.shade500),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─── Cart badge ────────────────────────────────────────────────────────────────

class _CartBadge extends StatelessWidget {
  const _CartBadge({required this.cartStore});

  final CartStore cartStore;

  @override
  Widget build(BuildContext context) {
    return Stack(
      alignment: Alignment.center,
      children: [
        IconButton(
          icon: const Icon(Icons.shopping_cart_outlined),
          onPressed: () => Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const CartScreen()),
          ),
        ),
        if (cartStore.totalItems > 0)
          Positioned(
            top: 8,
            right: 8,
            child: IgnorePointer(
              child: CircleAvatar(
                radius: 8,
                backgroundColor: Colors.red,
                child: Text(
                  '${cartStore.totalItems}',
                  style: const TextStyle(fontSize: 10, color: Colors.white),
                ),
              ),
            ),
          ),
      ],
    );
  }
}
