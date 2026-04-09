import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../data/fake_data.dart';
import '../models/cart_item.dart';
import '../stores/cart_store.dart';
import 'cart_screen.dart';

class StoreProductsScreen extends StatefulWidget {
  final RetailStore store;

  const StoreProductsScreen({super.key, required this.store});

  @override
  State<StoreProductsScreen> createState() => _StoreProductsScreenState();
}

class _StoreProductsScreenState extends State<StoreProductsScreen> {
  String _selectedCategory = 'Tudo';

  /// Extracts unique categories from product names (first word).
  /// When the data model gains a real `category` field, replace this.
  List<String> _buildCategories(List<MarketProduct> products) {
    if (products.isEmpty) return ['Tudo'];
    final cats = products
        .map((p) => p.name.split(' ').first)
        .toSet()
        .toList()
      ..sort();
    return ['Tudo', ...cats];
  }

  List<MarketProduct> _filteredProducts(List<MarketProduct> products) {
    if (_selectedCategory == 'Tudo') return products;
    return products
        .where((p) => p.name.startsWith(_selectedCategory))
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    final cartStore = context.watch<CartStore>();
    final products = widget.store.products;
    final categories = _buildCategories(products);
    final filtered = _filteredProducts(products);

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.store.name),
        actions: [
          _CartBadge(cartStore: cartStore),
        ],
      ),
      body: Column(
        children: [
          // ── Horizontal category chips ──────────────────────────────────────
          SizedBox(
            height: 52,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              itemCount: categories.length,
              separatorBuilder: (_, __) => const SizedBox(width: 8),
              itemBuilder: (_, i) {
                final cat = categories[i];
                final isSelected = cat == _selectedCategory;
                return ChoiceChip(
                  label: Text(cat),
                  selected: isSelected,
                  onSelected: (_) =>
                      setState(() => _selectedCategory = cat),
                  selectedColor: Theme.of(context).colorScheme.primary,
                  labelStyle: TextStyle(
                    color: isSelected ? Colors.white : null,
                    fontWeight: FontWeight.w500,
                  ),
                );
              },
            ),
          ),
          const Divider(height: 1),

          // ── Product grid ───────────────────────────────────────────────────
          Expanded(
            child: filtered.isEmpty
                ? const Center(
                    child: Text('Nenhum produto disponível no momento.'),
                  )
                : GridView.builder(
                    padding: const EdgeInsets.all(16),
                    gridDelegate:
                        const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 2,
                      mainAxisSpacing: 12,
                      crossAxisSpacing: 12,
                      childAspectRatio: 0.72,
                    ),
                    itemCount: filtered.length,
                    itemBuilder: (context, index) =>
                        _ProductCard(product: filtered[index]),
                  ),
          ),

          // ── Fixed "Ver carrinho" button ────────────────────────────────────
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
}

// ─── Product card (2-col grid) ─────────────────────────────────────────────────

class _ProductCard extends StatelessWidget {
  const _ProductCard({required this.product});

  final MarketProduct product;

  @override
  Widget build(BuildContext context) {
    final cartStore = context.watch<CartStore>();
    final qty = cartStore.items
        .where((i) => i.name == product.name)
        .fold<int>(0, (sum, i) => sum + i.quantity);

    return Card(
      elevation: 2,
      shape:
          RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Product image placeholder
            Expanded(
              child: Container(
                width: double.infinity,
                decoration: BoxDecoration(
                  color: Colors.grey.shade100,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.shopping_bag_outlined,
                    size: 40, color: Colors.grey),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              product.name,
              style: const TextStyle(
                  fontWeight: FontWeight.w600, fontSize: 13),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 4),
            Text(
              '€${product.price.toStringAsFixed(2)}',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 15,
                color: Theme.of(context).colorScheme.primary,
              ),
            ),
            const SizedBox(height: 8),

            // Add button ↔ quantity stepper
            qty == 0
                ? SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: () => context.read<CartStore>().addItem(
                            CartItem(
                                name: product.name,
                                price: product.price),
                          ),
                      style: ElevatedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 6),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8)),
                      ),
                      child: const Icon(Icons.add, size: 20),
                    ),
                  )
                : Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      _QtyButton(
                        icon: Icons.remove,
                        onTap: () {
                          try {
                            final item = cartStore.items.firstWhere(
                                (i) => i.name == product.name);
                            cartStore.decreaseQuantity(item);
                          } catch (_) {}
                        },
                      ),
                      Text(
                        '$qty',
                        style: const TextStyle(
                            fontWeight: FontWeight.bold, fontSize: 16),
                      ),
                      _QtyButton(
                        icon: Icons.add,
                        onTap: () => context.read<CartStore>().addItem(
                              CartItem(
                                  name: product.name,
                                  price: product.price),
                            ),
                      ),
                    ],
                  ),
          ],
        ),
      ),
    );
  }
}

// ─── Quantity stepper button ───────────────────────────────────────────────────

class _QtyButton extends StatelessWidget {
  const _QtyButton({required this.icon, required this.onTap});

  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme.primary;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.all(4),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Icon(icon, size: 20, color: color),
      ),
    );
  }
}

// ─── Cart icon with badge ──────────────────────────────────────────────────────

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
