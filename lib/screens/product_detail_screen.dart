import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/cart_item.dart';
import '../models/partner_product.dart';
import '../models/product_variant.dart';
import '../stores/cart_store.dart';
import '../stores/restaurant_store.dart';
import 'cart_screen.dart';

class ProductDetailScreen extends StatefulWidget {
  const ProductDetailScreen({super.key, required this.product});

  final PartnerProduct product;

  @override
  State<ProductDetailScreen> createState() => _ProductDetailScreenState();
}

class _ProductDetailScreenState extends State<ProductDetailScreen> {
  ProductVariant? _selectedVariant;
  int _quantity = 1;

  String _imageUrl(ProductVariant v) {
    final name = Uri.encodeComponent(v.brandName.toLowerCase());
    return 'https://source.unsplash.com/800x800/?product,$name';
  }

  String _variantKey(ProductVariant v) =>
      '${widget.product.name}__${v.id}';

  void _addToCart(BuildContext context, ProductVariant v) {
    context.read<CartStore>().addItem(CartItem(
          productId: _variantKey(v),
          name: '${widget.product.name} (${v.brandName})',
          price: v.price,
          quantity: _quantity,
        ));
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text('${v.brandName} × $_quantity adicionado ao carrinho'),
          duration: const Duration(seconds: 2),
          behavior: SnackBarBehavior.floating,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        ),
      );
  }

  @override
  Widget build(BuildContext context) {
    final cartStore = context.watch<CartStore>();
    final rawVariants =
        context.watch<RestaurantStore>().variantsForProduct(widget.product.id);
    final variants = [...rawVariants]..sort((a, b) => a.price.compareTo(b.price));

    // Auto-select first variant if none selected yet
    if (_selectedVariant == null && variants.isNotEmpty) {
      _selectedVariant = variants.first;
    }

    final primaryColor = Theme.of(context).colorScheme.primary;
    final total = variants.length;

    return Scaffold(
      backgroundColor: const Color(0xFFF5F5F5),
      body: Column(
        children: [
          Expanded(
            child: CustomScrollView(
              physics: const BouncingScrollPhysics(),
              slivers: [
                // ── Hero image SliverAppBar ──────────────────────────────────
                SliverAppBar(
                  expandedHeight: MediaQuery.of(context).size.width,
                  pinned: true,
                  backgroundColor: Colors.white,
                  foregroundColor: Colors.black87,
                  actions: [
                    _CartBadge(cartStore: cartStore),
                  ],
                  flexibleSpace: FlexibleSpaceBar(
                    background: AnimatedSwitcher(
                      duration: const Duration(milliseconds: 300),
                      child: _selectedVariant != null
                          ? Image.network(
                              _imageUrl(_selectedVariant!),
                              key: ValueKey(_selectedVariant!.id),
                              fit: BoxFit.cover,
                              width: double.infinity,
                              errorBuilder: (_, __, ___) =>
                                  _PlaceholderImage(),
                            )
                          : _PlaceholderImage(),
                    ),
                  ),
                ),

                // ── Product name + description ───────────────────────────────
                SliverToBoxAdapter(
                  child: Container(
                    color: Colors.white,
                    padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          widget.product.name,
                          style: const TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.w800,
                            color: Colors.black87,
                          ),
                        ),
                        if (widget.product.description.isNotEmpty) ...[
                          const SizedBox(height: 8),
                          Text(
                            widget.product.description,
                            style: TextStyle(
                              fontSize: 14,
                              color: Colors.grey.shade600,
                              height: 1.4,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),

                const SliverToBoxAdapter(child: SizedBox(height: 8)),

                // ── Variants section header ──────────────────────────────────
                if (variants.isNotEmpty)
                  SliverToBoxAdapter(
                    child: Padding(
                      padding:
                          const EdgeInsets.fromLTRB(20, 0, 20, 12),
                      child: Text(
                        total == 1
                            ? '1 marca disponível'
                            : '$total marcas disponíveis',
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: Colors.grey,
                          letterSpacing: 0.3,
                        ),
                      ),
                    ),
                  ),

                // ── Variant cards (selection only) ───────────────────────────
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                  sliver: SliverList(
                    delegate: SliverChildBuilderDelegate(
                      (context, i) {
                        final v = variants[i];
                        final isCheapest = i == 0 && total > 1;
                        final isPremium = i == total - 1 && total > 1;
                        final isSelected = _selectedVariant?.id == v.id;

                        return Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: _VariantCard(
                            variant: v,
                            isSelected: isSelected,
                            isCheapest: isCheapest,
                            isPremium: isPremium,
                            primaryColor: primaryColor,
                            onSelect: () =>
                                setState(() => _selectedVariant = v),
                          ),
                        );
                      },
                      childCount: variants.length,
                    ),
                  ),
                ),

                // ── Global quantity selector ─────────────────────────────────
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        _StepButton(
                          icon: Icons.remove,
                          color: primaryColor,
                          onTap: _quantity > 1
                              ? () => setState(() => _quantity--)
                              : null,
                        ),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 24),
                          child: Text(
                            '$_quantity',
                            style: const TextStyle(
                              fontSize: 22,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                        _StepButton(
                          icon: Icons.add,
                          color: primaryColor,
                          onTap: () => setState(() => _quantity++),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),

          // ── Fixed bottom button ──────────────────────────────────────────
          if (_selectedVariant != null)
            SafeArea(
              top: false,
              minimum: const EdgeInsets.fromLTRB(16, 8, 16, 16),
              child: SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: () => _addToCart(context, _selectedVariant!),
                  icon: const Icon(Icons.add_shopping_cart),
                  label: Text(
                    'Adicionar ao carrinho · €${_selectedVariant!.price.toStringAsFixed(2)}',
                    style: const TextStyle(
                        fontWeight: FontWeight.w700, fontSize: 16),
                  ),
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 16),
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

// ─── Variant card (large) ──────────────────────────────────────────────────────

class _VariantCard extends StatelessWidget {
  const _VariantCard({
    required this.variant,
    required this.isSelected,
    required this.isCheapest,
    required this.isPremium,
    required this.primaryColor,
    required this.onSelect,
  });

  final ProductVariant variant;
  final bool isSelected;
  final bool isCheapest;
  final bool isPremium;
  final Color primaryColor;
  final VoidCallback onSelect;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onSelect,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOut,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isSelected
                ? primaryColor
                : Colors.transparent,
            width: 2,
          ),
          boxShadow: [
            BoxShadow(
              color: isSelected
                  ? primaryColor.withValues(alpha: 0.15)
                  : Colors.black.withValues(alpha: 0.06),
              blurRadius: isSelected ? 12 : 6,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            // ── Variant image ──────────────────────────────────────────────
            ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: SizedBox(
                width: 72,
                height: 72,
                child: Image.network(
                  _imageUrl,
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => _SmallPlaceholder(),
                ),
              ),
            ),
            const SizedBox(width: 14),

            // ── Brand name + badge ─────────────────────────────────────────
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    variant.brandName,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: Colors.black87,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 6),
                  if (isCheapest)
                    _Badge(
                        label: 'Mais barato', color: Colors.green.shade600)
                  else if (isPremium)
                    _Badge(label: 'Premium', color: Colors.blue.shade600),
                  const SizedBox(height: 6),
                  Text(
                    '€${variant.price.toStringAsFixed(2)}',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w800,
                      color: primaryColor,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),

            // ── Selection indicator ────────────────────────────────────────
            AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              width: 28,
              height: 28,
              decoration: BoxDecoration(
                color: isSelected ? primaryColor : Colors.transparent,
                shape: BoxShape.circle,
                border: Border.all(
                  color: isSelected ? primaryColor : Colors.grey.shade300,
                  width: 2,
                ),
              ),
              child: isSelected
                  ? const Icon(Icons.check, size: 16, color: Colors.white)
                  : null,
            ),
          ],
        ),
      ),
    );
  }

  String get _imageUrl {
    final name = Uri.encodeComponent(variant.brandName.toLowerCase());
    return 'https://source.unsplash.com/400x400/?product,$name';
  }
}

// ─── Helpers ───────────────────────────────────────────────────────────────────

class _Badge extends StatelessWidget {
  const _Badge({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.3), width: 0.8),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          color: color,
          letterSpacing: 0.2,
        ),
      ),
    );
  }
}

class _StepButton extends StatelessWidget {
  const _StepButton(
      {required this.icon, required this.color, required this.onTap});

  final IconData icon;
  final Color color;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final disabled = onTap == null;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: disabled
              ? Colors.grey.withValues(alpha: 0.08)
              : color.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Icon(icon, size: 20, color: disabled ? Colors.grey : color),
      ),
    );
  }
}

class _PlaceholderImage extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      color: const Color(0xFFEEEEEE),
      child: const Center(
        child: Icon(Icons.shopping_bag_outlined, size: 64, color: Colors.grey),
      ),
    );
  }
}

class _SmallPlaceholder extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      color: const Color(0xFFEEEEEE),
      child:
          const Center(child: Icon(Icons.image_outlined, color: Colors.grey)),
    );
  }
}

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
