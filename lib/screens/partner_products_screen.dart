import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../config/app_colors.dart';
import '../models/partner_product.dart';
import '../models/restaurant_model.dart';
import '../services/partner_price_rules.dart';
import '../stores/partner_product_store.dart';
import '../widgets/bora/bora_screen_app_bar.dart';
import '../widgets/bora_support_fab.dart';
import 'add_product_screen.dart';
import 'product_options_manage_screen.dart';

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

  /// 2026-09-14 (missão parceiro-edita-preco): edição completa — nome,
  /// descrição, preço que recebes, categoria e foto — no mesmo ecrã de criar.
  /// Substitui o diálogo solto de categoria (BUG 1, 2026-07-17), que era o
  /// único "Editar" que existia e não deixava mudar o preço.
  Future<void> _openEditProduct(PartnerProduct product) async {
    final updated = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => AddProductScreen(
          restaurant: widget.restaurant,
          product: product,
        ),
      ),
    );
    if (!mounted) return;
    if (updated == true) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Produto atualizado.')),
      );
    }
  }

  /// Apagar com confirmação. O Danilo já disse ao dono da Sabores de Casa que
  /// ia poder limpar o que não vende — tem de haver botão.
  Future<void> _deleteProduct(PartnerProduct product) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Apagar ${product.name}?'),
        content: const Text('Esta ação não pode ser desfeita.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.error),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Apagar'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    final store = context.read<PartnerProductStore>();
    final success = await store.deleteProduct(
      restaurantId: widget.restaurant.id,
      productId: product.id,
    );
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(success
            ? 'Produto apagado.'
            : 'Não foi possível apagar o produto.'),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final productStore = context.watch<PartnerProductStore>();
    final products = productStore.productsForRestaurant(widget.restaurant.id);

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: BoraScreenAppBar(
          title: 'Produtos de ${widget.restaurant.name}'),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _openAddProduct(),
        icon: const Icon(Icons.add),
        label: const Text('Adicionar produto'),
      ),
      body: Stack(
        children: [
          SafeArea(
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
                        isPartnerStore: widget.restaurant.isPartner,
                        onToggleAvailability: (value) =>
                            _toggleAvailability(product, value),
                        onEdit: () => _openEditProduct(product),
                        onDelete: () => _deleteProduct(product),
                      );
                    },
                  ),
          ),
          const Positioned(
            top: 16,
            right: 16,
            child: SafeArea(
              child: BoraSupportFab(
                position: FabPosition.topRight,
                heroTag: 'bora_support_fab_partner_products',
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ProductTile extends StatelessWidget {
  const _ProductTile({
    required this.product,
    required this.isPartnerStore,
    required this.onToggleAvailability,
    required this.onEdit,
    required this.onDelete,
  });

  final PartnerProduct product;
  final bool isPartnerStore;
  final ValueChanged<bool> onToggleAvailability;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final shelf = product.partnerShelfPrice;
    // Loja parceira com balcão gravado: mostra o que ele recebe e o que o
    // cliente vê. Sem balcão (produto antigo) mostra só o preço do cliente —
    // o balcão fica gravado na primeira edição.
    final showBothPrices = isPartnerStore && shelf != null;
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
                Expanded(
                  child: showBothPrices
                      ? Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Recebes ${formatEurPt(shelf)}',
                              style: theme.textTheme.titleMedium?.copyWith(
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            Text(
                              'O cliente vê ${formatEurPt(product.price)}',
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: theme.textTheme.bodySmall?.color,
                              ),
                            ),
                          ],
                        )
                      : Text(
                          formatEurPt(product.price),
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                ),
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
            const SizedBox(height: 4),
            Text(
              product.category.trim().isEmpty
                  ? 'Sem categoria'
                  : 'Categoria: ${product.category}',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.textTheme.bodySmall?.color,
                fontStyle: product.category.trim().isEmpty
                    ? FontStyle.italic
                    : FontStyle.normal,
              ),
            ),
            const SizedBox(height: 4),
            Wrap(
              spacing: 4,
              children: [
                TextButton.icon(
                  onPressed: onEdit,
                  icon: const Icon(Icons.edit_outlined, size: 18),
                  label: const Text('Editar produto'),
                ),
                TextButton.icon(
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) =>
                          ProductOptionsManageScreen(product: product),
                    ),
                  ),
                  icon: const Icon(Icons.tune, size: 18),
                  label: const Text('Gerir opções'),
                ),
                TextButton.icon(
                  onPressed: onDelete,
                  style: TextButton.styleFrom(foregroundColor: AppColors.error),
                  icon: const Icon(Icons.delete_outline, size: 18),
                  label: const Text('Apagar'),
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
