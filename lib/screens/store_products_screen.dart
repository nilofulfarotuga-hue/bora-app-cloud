import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/cart_item.dart';
import '../models/partner_product.dart';
import '../models/product_variant.dart';
import '../stores/cart_store.dart';
import '../stores/favorite_store.dart';
import '../stores/restaurant_store.dart';
import 'cart_screen.dart';
import 'product_detail_screen.dart';

class StoreProductsScreen extends StatefulWidget {
  final String restaurantId;
  final String storeName;
  final String? initialCategory;

  const StoreProductsScreen({
    super.key,
    required this.restaurantId,
    required this.storeName,
    this.initialCategory,
  });

  @override
  State<StoreProductsScreen> createState() => _StoreProductsScreenState();
}

class _StoreProductsScreenState extends State<StoreProductsScreen> {
  late String _selectedCategory;
  String _searchQuery = '';
  final TextEditingController _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _selectedCategory = widget.initialCategory ?? 'Todos';
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  String _categoryOf(PartnerProduct p) {
    if (p.category.isNotEmpty) return _capitalize(p.category);
    // Fallback: derive from product name
    return _capitalize(p.name.split(' ').first);
  }

  String _capitalize(String s) =>
      s.isEmpty ? s : s[0].toUpperCase() + s.substring(1).toLowerCase();

  List<String> _buildCategories(List<PartnerProduct> products) {
    if (products.isEmpty) return ['Todos'];
    final cats = products.map(_categoryOf).toSet().toList()..sort();
    return ['Todos', ...cats];
  }

  List<PartnerProduct> _applyFilters(List<PartnerProduct> products) {
    var result = products;
    if (_searchQuery.isNotEmpty) {
      final q = _searchQuery.toLowerCase();
      result = result
          .where((p) =>
              p.name.toLowerCase().contains(q) ||
              p.description.toLowerCase().contains(q))
          .toList();
    }
    if (_selectedCategory != 'Todos') {
      result =
          result.where((p) => _categoryOf(p) == _selectedCategory).toList();
    }
    return result;
  }

  bool _isFruitCategory(String category) =>
      category.toLowerCase().contains('frut') ||
      category.toLowerCase().contains('fruit') ||
      category.toLowerCase().contains('legum');

  Map<String, List<PartnerProduct>> _groupByCategory(
      List<PartnerProduct> products) {
    final grouped = <String, List<PartnerProduct>>{};
    for (final p in products) {
      final cat = _categoryOf(p);
      grouped.putIfAbsent(cat, () => []).add(p);
    }
    return Map.fromEntries(
      grouped.entries.toList()..sort((a, b) => a.key.compareTo(b.key)),
    );
  }

  bool get _showSections => _selectedCategory == 'Todos';

  @override
  Widget build(BuildContext context) {
    final cartStore = context.watch<CartStore>();
    final restaurantStore = context.watch<RestaurantStore>();
    final products = restaurantStore.partnerProductsForRestaurant(
      widget.restaurantId,
      onlyAvailable: true,
    );

    final categories = _buildCategories(products);
    final filtered = _applyFilters(products);
    final isFruit = _isFruitCategory(_selectedCategory);
    final grouped = _showSections ? _groupByCategory(filtered) : null;

    return Scaffold(
      backgroundColor: const Color(0xFFF5F5F5),
      appBar: AppBar(
        title: Text(
          widget.storeName,
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        backgroundColor: Colors.white,
        foregroundColor: Colors.black87,
        elevation: 0,
        actions: [
          _CartBadge(cartStore: cartStore),
        ],
      ),
      body: Column(
        children: [
          // ── Search bar ─────────────────────────────────────────────────────
          Container(
            color: Colors.white,
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
            child: TextField(
              controller: _searchController,
              onChanged: (v) => setState(() => _searchQuery = v),
              decoration: InputDecoration(
                hintText: 'Buscar produtos...',
                hintStyle: TextStyle(color: Colors.grey.shade400),
                prefixIcon: Icon(Icons.search, color: Colors.grey.shade400),
                suffixIcon: _searchQuery.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear),
                        onPressed: () {
                          _searchController.clear();
                          setState(() => _searchQuery = '');
                        },
                      )
                    : null,
                filled: true,
                fillColor: const Color(0xFFF0F0F0),
                contentPadding: const EdgeInsets.symmetric(vertical: 0),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
          ),

          // ── Horizontal category chips ───────────────────────────────────────
          Container(
            color: Colors.white,
            height: 50,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
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
                  backgroundColor: const Color(0xFFF0F0F0),
                  labelStyle: TextStyle(
                    color: isSelected ? Colors.white : Colors.black87,
                    fontWeight: FontWeight.w600,
                    fontSize: 13,
                  ),
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(20)),
                );
              },
            ),
          ),
          const SizedBox(height: 4),

          // ── Content area ───────────────────────────────────────────────────
          Expanded(
            child: filtered.isEmpty
                ? _EmptyState(
                    hasSearch: _searchQuery.isNotEmpty,
                    searchQuery: _searchQuery,
                    onRefresh: () => setState(() {}),
                  )
                : _showSections
                    ? _SectionedView(
                        grouped: grouped!,
                        isFruitCategory: _isFruitCategory,
                      )
                    : ListView.builder(
                        padding: const EdgeInsets.all(16),
                        itemCount: filtered.length,
                        itemBuilder: (context, index) => Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: _ProductCard(
                            product: filtered[index],
                            showPerKg: isFruit,
                          ),
                        ),
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

// ─── Empty state ───────────────────────────────────────────────────────────────

class _EmptyState extends StatelessWidget {
  const _EmptyState({
    required this.hasSearch,
    required this.searchQuery,
    required this.onRefresh,
  });

  final bool hasSearch;
  final String searchQuery;
  final VoidCallback onRefresh;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              hasSearch ? Icons.search_off_rounded : Icons.inventory_2_outlined,
              size: 72,
              color: Colors.grey.shade300,
            ),
            const SizedBox(height: 16),
            Text(
              hasSearch
                  ? 'Sem resultados para "$searchQuery"'
                  : 'Nenhum produto disponível',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: Colors.grey.shade600,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              hasSearch
                  ? 'Tente outro termo de busca.'
                  : 'Este estabelecimento ainda não tem produtos cadastrados.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13, color: Colors.grey.shade400),
            ),
            if (!hasSearch) ...[
              const SizedBox(height: 24),
              OutlinedButton.icon(
                onPressed: onRefresh,
                icon: const Icon(Icons.refresh),
                label: const Text('Atualizar'),
                style: OutlinedButton.styleFrom(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

// ─── Loading skeleton ──────────────────────────────────────────────────────────

class _SkeletonLoader extends StatefulWidget {
  const _SkeletonLoader();

  @override
  State<_SkeletonLoader> createState() => _SkeletonLoaderState();
}

class _SkeletonLoaderState extends State<_SkeletonLoader>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _opacity;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..repeat(reverse: true);
    _opacity = Tween<double>(begin: 0.4, end: 1.0).animate(_controller);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _opacity,
      child: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: 5,
        itemBuilder: (_, __) => Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Container(
            height: 110,
            decoration: BoxDecoration(
              color: Colors.grey.shade200,
              borderRadius: BorderRadius.circular(16),
            ),
          ),
        ),
      ),
    );
  }
}

// ─── Sectioned view (supermarket style) ───────────────────────────────────────

class _SectionedView extends StatelessWidget {
  const _SectionedView({
    required this.grouped,
    required this.isFruitCategory,
  });

  final Map<String, List<PartnerProduct>> grouped;
  final bool Function(String) isFruitCategory;

  @override
  Widget build(BuildContext context) {
    final sections = grouped.entries.toList();

    return ListView.builder(
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.only(top: 8, bottom: 16),
      itemCount: sections.length,
      itemBuilder: (context, index) {
        final category = sections[index].key;
        final items = sections[index].value;
        final showPerKg = isFruitCategory(category);

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      category,
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: Colors.black87,
                      ),
                    ),
                  ),
                  Text(
                    '${items.length} ${items.length == 1 ? 'produto' : 'produtos'}',
                    style: TextStyle(fontSize: 12, color: Colors.grey.shade500),
                  ),
                ],
              ),
            ),
            SizedBox(
              height: _cardHeightFor(items),
              child: ListView.builder(
                scrollDirection: Axis.horizontal,
                physics: const BouncingScrollPhysics(),
                padding: const EdgeInsets.symmetric(horizontal: 16),
                itemCount: items.length,
                itemBuilder: (context, i) => Padding(
                  padding:
                      EdgeInsets.only(right: i < items.length - 1 ? 12 : 0),
                  child: SizedBox(
                    width: 272,
                    child: _ProductCard(
                      product: items[i],
                      showPerKg: showPerKg,
                    ),
                  ),
                ),
              ),
            ),
            if (index < sections.length - 1)
              const Padding(
                padding: EdgeInsets.only(top: 8),
                child: Divider(
                    height: 1, thickness: 1, indent: 16, endIndent: 16),
              ),
          ],
        );
      },
    );
  }

  double _cardHeightFor(List<PartnerProduct> items) {
    const base = 80.0;
    const variantHeight = 72.0;
    return base + variantHeight * 3;
  }
}

// ─── Product card ──────────────────────────────────────────────────────────────

class _ProductCard extends StatefulWidget {
  const _ProductCard({required this.product, required this.showPerKg});

  final PartnerProduct product;
  final bool showPerKg;

  @override
  State<_ProductCard> createState() => _ProductCardState();
}

class _ProductCardState extends State<_ProductCard>
    with SingleTickerProviderStateMixin {
  late AnimationController _scaleController;
  late Animation<double> _scaleAnimation;

  @override
  void initState() {
    super.initState();
    _scaleController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 120),
      lowerBound: 0.97,
      upperBound: 1.0,
      value: 1.0,
    );
    _scaleAnimation = _scaleController;
  }

  @override
  void dispose() {
    _scaleController.dispose();
    super.dispose();
  }

  void _onTapDown(_) => _scaleController.reverse();
  void _onTapUp(_) => _scaleController.forward();
  void _onTapCancel() => _scaleController.forward();

  @override
  Widget build(BuildContext context) {
    final cartStore = context.watch<CartStore>();
    final favoriteStore = context.watch<FavoriteStore>();
    final rawVariants =
        context.watch<RestaurantStore>().variantsForProduct(widget.product.id);
    final variants = [...rawVariants]
      ..sort((a, b) => a.price.compareTo(b.price));
    final primaryColor = Theme.of(context).colorScheme.primary;
    final total = variants.length;
    final isFav = favoriteStore.isFavorite(widget.product.id);

    return GestureDetector(
      onTapDown: _onTapDown,
      onTapUp: _onTapUp,
      onTapCancel: _onTapCancel,
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => ProductDetailScreen(product: widget.product),
        ),
      ),
      child: ScaleTransition(
        scale: _scaleAnimation,
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
                // ── Product name + favorite ────────────────────────────────
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Text(
                        widget.product.name,
                        style: const TextStyle(
                            fontWeight: FontWeight.w800, fontSize: 15),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    GestureDetector(
                      onTap: () => favoriteStore.toggle(widget.product.id),
                      child: AnimatedSwitcher(
                        duration: const Duration(milliseconds: 200),
                        transitionBuilder: (child, anim) => ScaleTransition(
                          scale: anim,
                          child: child,
                        ),
                        child: Icon(
                          isFav ? Icons.favorite : Icons.favorite_border,
                          key: ValueKey(isFav),
                          size: 20,
                          color: isFav ? Colors.red : Colors.grey.shade400,
                        ),
                      ),
                    ),
                  ],
                ),
                // ── Promo badges ───────────────────────────────────────────
                if (widget.product.isPopular || widget.product.isOnSale) ...[
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      if (widget.product.isPopular)
                        const Padding(
                          padding: EdgeInsets.only(right: 6),
                          child: _Badge(
                              label: 'Mais vendido',
                              color: Colors.orange),
                        ),
                      if (widget.product.isOnSale)
                        const _Badge(label: 'Promoção', color: Colors.red),
                    ],
                  ),
                ],
                if (widget.product.description.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    widget.product.description,
                    style:
                        TextStyle(fontSize: 12, color: Colors.grey.shade500),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
                if (variants.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  ...List.generate(variants.length, (i) {
                    final showCheapest = i == 0 && total > 1;
                    final showPremium = i == total - 1 && total > 1;
                    return Padding(
                      padding: EdgeInsets.only(bottom: i < total - 1 ? 8 : 0),
                      child: _VariantMiniCard(
                        variant: variants[i],
                        productName: widget.product.name,
                        showPerKg: widget.showPerKg,
                        cartStore: cartStore,
                        primaryColor: primaryColor,
                        showCheapestBadge: showCheapest,
                        showPremiumBadge: showPremium,
                      ),
                    );
                  }),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ─── Variant mini card ─────────────────────────────────────────────────────────

class _VariantMiniCard extends StatelessWidget {
  const _VariantMiniCard({
    required this.variant,
    required this.productName,
    required this.showPerKg,
    required this.cartStore,
    required this.primaryColor,
    required this.showCheapestBadge,
    required this.showPremiumBadge,
  });

  final ProductVariant variant;
  final String productName;
  final bool showPerKg;
  final CartStore cartStore;
  final Color primaryColor;
  final bool showCheapestBadge;
  final bool showPremiumBadge;

  String get _variantKey => '${productName}__${variant.id}';

  String get _imageUrl {
    final name = Uri.encodeComponent(variant.brandName.toLowerCase());
    return 'https://source.unsplash.com/400x400/?product,$name';
  }

  void _addToCart(BuildContext context) {
    context.read<CartStore>().addItem(CartItem(
          productId: _variantKey,
          name: '$productName (${variant.brandName})',
          price: variant.price,
        ));
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text('${variant.brandName} adicionado ao carrinho'),
          duration: const Duration(seconds: 2),
          behavior: SnackBarBehavior.floating,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          action: SnackBarAction(
            label: 'Ver',
            onPressed: () => Navigator.push(context,
                MaterialPageRoute(builder: (_) => const CartScreen())),
          ),
        ),
      );
  }

  @override
  Widget build(BuildContext context) {
    final qty = cartStore.items
        .where((i) => i.productId == _variantKey)
        .fold<int>(0, (sum, i) => sum + i.quantity);
    final priceLabel = showPerKg
        ? '€${variant.price.toStringAsFixed(2)}/kg'
        : '€${variant.price.toStringAsFixed(2)}';

    return Material(
      color: const Color(0xFFF7F7F7),
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: qty == 0 ? () => _addToCart(context) : null,
        child: Padding(
          padding: const EdgeInsets.all(8),
          child: Row(
            children: [
              // ── Variant image ────────────────────────────────────────────
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: SizedBox(
                  width: 52,
                  height: 52,
                  child: Image.network(
                    _imageUrl,
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => _PlaceholderImage(),
                  ),
                ),
              ),
              const SizedBox(width: 10),

              // ── Brand + badge ────────────────────────────────────────────
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      variant.brandName,
                      style: const TextStyle(
                          fontWeight: FontWeight.w600, fontSize: 13),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (showCheapestBadge) ...[
                      const SizedBox(height: 3),
                      const _Badge(label: 'Mais barato', color: Colors.green),
                    ] else if (showPremiumBadge) ...[
                      const SizedBox(height: 3),
                      const _Badge(label: 'Premium', color: Colors.blue),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 8),

              // ── Price ────────────────────────────────────────────────────
              Text(
                priceLabel,
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 14,
                  color: primaryColor,
                ),
              ),
              const SizedBox(width: 8),

              // ── Stepper ──────────────────────────────────────────────────
              if (qty == 0)
                _QtyButton(
                  icon: Icons.add,
                  color: primaryColor,
                  onTap: () => _addToCart(context),
                )
              else
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _QtyButton(
                      icon: Icons.remove,
                      color: primaryColor,
                      onTap: () {
                        try {
                          final item = cartStore.items
                              .firstWhere((i) => i.productId == _variantKey);
                          context.read<CartStore>().decreaseQuantity(item);
                        } catch (_) {}
                      },
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 6),
                      child: Text(
                        '$qty',
                        style: const TextStyle(
                            fontWeight: FontWeight.bold, fontSize: 14),
                      ),
                    ),
                    _QtyButton(
                      icon: Icons.add,
                      color: primaryColor,
                      onTap: () => _addToCart(context),
                    ),
                  ],
                ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─── Badge ─────────────────────────────────────────────────────────────────────

class _Badge extends StatelessWidget {
  const _Badge({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withValues(alpha: 0.3), width: 0.8),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w700,
          color: color,
          letterSpacing: 0.2,
        ),
      ),
    );
  }
}

// ─── Placeholder image ─────────────────────────────────────────────────────────

class _PlaceholderImage extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      color: const Color(0xFFF0F0F0),
      child: const Center(
        child: Icon(Icons.shopping_bag_outlined, size: 40, color: Colors.grey),
      ),
    );
  }
}

// ─── Quantity button ───────────────────────────────────────────────────────────

class _QtyButton extends StatelessWidget {
  const _QtyButton(
      {required this.icon, required this.color, required this.onTap});

  final IconData icon;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Icon(icon, size: 18, color: color),
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
