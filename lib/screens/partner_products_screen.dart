import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../config/app_colors.dart';
import '../models/partner_product.dart';
import '../models/restaurant_model.dart';
import '../stores/partner_product_store.dart';
import 'add_product_screen.dart';

class PartnerProductsScreen extends StatefulWidget {
  const PartnerProductsScreen({super.key, required this.restaurant});

  final RestaurantModel restaurant;

  @override
  State<PartnerProductsScreen> createState() => _PartnerProductsScreenState();
}

class _PartnerProductsScreenState extends State<PartnerProductsScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      context.read<PartnerProductStore>().selectRestaurant(widget.restaurant);
    });
  }

  Future<void> _openAddProduct() async {
    final created = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => AddProductScreen(restaurant: widget.restaurant),
      ),
    );
    if (!mounted) return;
    if (created == true) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Produto adicionado com sucesso.')),
      );
    }
  }

  Future<void> _toggleAvailability(
      PartnerProduct product, bool isAvailable) async {
    final store = context.read<PartnerProductStore>();
    // Store handles optimistic UI update + rollback on failure — no local
    // loading state needed here. Just await and show error if DB rejects.
    final success = await store.toggleAvailability(
      restaurantId: widget.restaurant.id,
      productId: product.id,
      isAvailable: isAvailable,
    );
    if (!success && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Não foi possível atualizar a disponibilidade.'),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final productStore = context.watch<PartnerProductStore>();
    final products = productStore.productsForRestaurant(widget.restaurant.id);

    return Scaffold(
      backgroundColor: AppColors.surface,
      appBar: AppBar(
        title: Text(
          'Produtos de ${widget.restaurant.name}',
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        backgroundColor: Colors.transparent,
        foregroundColor: Colors.white,
        elevation: 0,
        flexibleSpace: const DecoratedBox(
          decoration: BoxDecoration(gradient: AppColors.headerGradient),
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _openAddProduct(),
        icon: const Icon(Icons.add),
        label: const Text('Adicionar produto'),
      ),
      body: SafeArea(
        child: products.isEmpty
            ? _EmptyProducts(restaurantName: widget.restaurant.name)
            : ListView.separated(
                padding: const EdgeInsets.all(16),
                itemCount: products.length,
                separatorBuilder: (_, __) => const SizedBox(height: 12),
                itemBuilder: (context, index) {
                  final product = products[index];
                  return _ProductTile(
                    product: product,
                    onToggleAvailability: (value) =>
                        _toggleAvailability(product, value),
                  );
                },
              ),
      ),
    );
  }
}

class _ProductTile extends StatelessWidget {
  const _ProductTile({
    required this.product,
    required this.onToggleAvailability,
  });

  final PartnerProduct product;
  final ValueChanged<bool> onToggleAvailability;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _ProductPhoto(photoUrl: product.photoUrl, name: product.name),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        product.name,
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        product.description,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: theme.textTheme.bodySmall?.color,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Text(
                  '€${product.price.toStringAsFixed(2)}',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const Spacer(),
                Row(
                  children: [
                    Text(
                      product.isAvailable ? 'Disponível' : 'Indisponível',
                      style: theme.textTheme.bodyMedium,
                    ),
                    const SizedBox(width: 8),
                    Switch(
                      value: product.isAvailable,
                      onChanged: onToggleAvailability,
                    ),
                  ],
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _ProductPhoto extends StatelessWidget {
  const _ProductPhoto({required this.photoUrl, required this.name});

  final String photoUrl;
  final String name;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: Image.network(
        photoUrl,
        width: 72,
        height: 72,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) {
          return Container(
            width: 72,
            height: 72,
            color: Colors.grey.shade200,
            alignment: Alignment.center,
            child: Text(
              _fallbackInitial(name),
              style: Theme.of(context).textTheme.titleLarge,
            ),
          );
        },
      ),
    );
  }
}

String _fallbackInitial(String name) {
  final trimmed = name.trim();
  if (trimmed.isEmpty) {
    return '?';
  }
  final codePoint = trimmed.runes.isNotEmpty ? trimmed.runes.first : null;
  if (codePoint == null) {
    return '?';
  }
  return String.fromCharCode(codePoint).toUpperCase();
}

class _EmptyProducts extends StatelessWidget {
  const _EmptyProducts({required this.restaurantName});

  final String restaurantName;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.inventory_2_outlined,
              size: 64,
              color: theme.colorScheme.primary,
            ),
            const SizedBox(height: 16),
            Text(
              'Ainda não existem produtos registados',
              style: theme.textTheme.titleMedium,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              'Comece por adicionar o primeiro produto para $restaurantName.',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.textTheme.bodySmall?.color,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}
