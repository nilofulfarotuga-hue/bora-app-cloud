import 'package:cached_network_image/cached_network_image.dart';
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../config/app_colors.dart';
import '../config/app_spacing.dart';
import '../models/business_view_models.dart';
import '../models/cart_item.dart';
import '../models/order_service_type.dart';
import '../models/partner_product.dart';
import '../stores/cart_store.dart';
import '../stores/favorite_store.dart';
import '../stores/restaurant_store.dart';
import '../widgets/bora/bora.dart';
import '../widgets/bora_support_fab.dart';
import 'cart_screen.dart';
import 'client/reservation/reservation_availability_screen.dart';
import 'product_detail_screen.dart';

class RestaurantMenuScreen extends StatefulWidget {
  final Restaurant restaurant;

  /// Used to load products with categories and images from [RestaurantStore].
  final String restaurantId;

  const RestaurantMenuScreen({
    super.key,
    required this.restaurant,
    required this.restaurantId,
  });

  @override
  State<RestaurantMenuScreen> createState() => _RestaurantMenuScreenState();

  static const Map<String, String> _categoryEmoji = {
    'burgers': '🍔',
    'hambúrgueres': '🍔',
    'hamburgers': '🍔',
    'chicken': '🍗',
    'frango': '🍗',
    'aves': '🍗',
    'wraps': '🌯',
    'twister': '🌯',
    'pizzas': '🍕',
    'pizza': '🍕',
    'pastas': '🍝',
    'pasta': '🍝',
    'acompanhamentos': '🍟',
    'sides': '🍟',
    'bebidas': '🥤',
    'drinks': '🥤',
    'sobremesas': '🍦',
    'desserts': '🍦',
    'saladas': '🥗',
    'salads': '🥗',
    'happy meal': '🎁',
    'kids': '👶',
    'menus': '🍱',
    'snacks': '🧆',
    'entradas': '🧆',
    'plant-based': '🌱',
    'vegan': '🌱',
    'pequeno-almoço': '☕',
    'breakfast': '☕',
    'mcmenus': '🍱',
    'europoupança': '💶',
    'sopas': '🍲',
    'buckets': '🍗',
    'whopper': '🍔',
    'complementos': '🍞',
    'rodízio': '🍕',
    'ofertas': '🎁',
  };

  static String _emojiFor(String category) =>
      _categoryEmoji[category.toLowerCase()] ?? '🍽️';

  static Map<String, List<PartnerProduct>> _groupByCategory(
      List<PartnerProduct> products) {
    final grouped = <String, List<PartnerProduct>>{};
    for (final p in products) {
      final cat = p.category.isNotEmpty ? p.category : 'Outros';
      grouped.putIfAbsent(cat, () => []).add(p);
    }
    return Map.fromEntries(
      grouped.entries.toList()..sort((a, b) => a.key.compareTo(b.key)),
    );
  }

}

// ─── State ──────────────────────────────────────────────────────────────────────

class _RestaurantMenuScreenState extends State<RestaurantMenuScreen> {
  // ── Search state (2026-06-05 — RPC fuzzy igual ao padrão StoreProductsScreen)
  String _searchQuery = '';
  final TextEditingController _searchController = TextEditingController();
  Timer? _rpcDebounce;
  List<Map<String, dynamic>> _rpcRows = const [];
  bool _rpcLoading = false;

  @override
  void dispose() {
    _rpcDebounce?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  void _scheduleRpcSearch(String query) {
    _rpcDebounce?.cancel();
    final q = query.trim();
    if (q.length < 2) {
      if (_rpcRows.isNotEmpty || _rpcLoading) {
        setState(() {
          _rpcRows = const [];
          _rpcLoading = false;
        });
      }
      return;
    }
    _rpcDebounce = Timer(const Duration(milliseconds: 350), () {
      _runRpcSearch(q);
    });
  }

  Future<void> _runRpcSearch(String query) async {
    if (!mounted) return;
    setState(() => _rpcLoading = true);
    try {
      final rows = await Supabase.instance.client.rpc(
        'search_products',
        params: {
          'query_text': query,
          'p_restaurant_id': widget.restaurantId,
          'max_results': 50,
        },
      );
      if (!mounted) return;
      setState(() {
        _rpcRows = rows is List
            ? List<Map<String, dynamic>>.from(
                rows.whereType<Map<String, dynamic>>())
            : const [];
        _rpcLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _rpcRows = const [];
        _rpcLoading = false;
      });
    }
  }

  PartnerProduct _resolveProduct(Map<String, dynamic> row) {
    return PartnerProduct(
      id: (row['id'] ?? '').toString(),
      restaurantId: (row['restaurant_id'] ?? '').toString(),
      name: (row['name'] ?? '').toString(),
      description: (row['description'] ?? '').toString(),
      price: (row['price'] as num?)?.toDouble() ?? 0.0,
      photoUrl: (row['photo_url'] ?? '').toString(),
      isAvailable: true,
      category: (row['category'] ?? '').toString(),
      categoryRoot: (row['category_root'] ?? '').toString(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cart = context.watch<CartStore>();
    final favorites = context.watch<FavoriteStore>();
    final restaurantStore = context.watch<RestaurantStore>();

    final products = restaurantStore.partnerProductsForRestaurant(
      widget.restaurantId,
      onlyAvailable: true,
    );
    final grouped = RestaurantMenuScreen._groupByCategory(products);

    return Scaffold(
      backgroundColor: AppColors.background,
      floatingActionButton: const BoraSupportFab(),
      appBar: AppBar(
        title: Text(
          widget.restaurant.name,
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        backgroundColor: Colors.transparent,
        foregroundColor: Colors.white,
        elevation: 0,
        flexibleSpace: const DecoratedBox(
          decoration: BoxDecoration(gradient: AppColors.headerGradient),
        ),
        actions: [
          IconButton(
            onPressed: () =>
                favorites.toggle('restaurant_${widget.restaurant.name}'),
            icon: AnimatedSwitcher(
              duration: const Duration(milliseconds: 200),
              transitionBuilder: (child, anim) =>
                  ScaleTransition(scale: anim, child: child),
              child: Icon(
                favorites.isFavorite('restaurant_${widget.restaurant.name}')
                    ? Icons.favorite
                    : Icons.favorite_border,
                key: ValueKey(favorites
                    .isFavorite('restaurant_${widget.restaurant.name}')),
                color:
                    favorites.isFavorite('restaurant_${widget.restaurant.name}')
                        ? Colors.redAccent
                        : Colors.white,
              ),
            ),
          ),
          _CartBadgeAction(totalItems: cart.totalItems),
        ],
      ),
      body: Column(
        children: [
          // ── Search bar (2026-06-05) ─────────────────────────────────────
          Container(
            color: Colors.white,
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
            child: TextField(
              controller: _searchController,
              onChanged: (v) {
                setState(() => _searchQuery = v);
                _scheduleRpcSearch(v);
              },
              decoration: InputDecoration(
                hintText: 'Buscar no menu...',
                hintStyle: TextStyle(color: Colors.grey.shade400),
                prefixIcon: Icon(Icons.search, color: Colors.grey.shade400),
                suffixIcon: _searchQuery.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear),
                        onPressed: () {
                          _searchController.clear();
                          setState(() {
                            _searchQuery = '';
                            _rpcRows = const [];
                            _rpcLoading = false;
                          });
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

          if (_searchQuery.trim().length >= 2) ...[
            // ── Search mode: RPC results ────────────────────────────────
            Expanded(
              child: _rpcLoading && _rpcRows.isEmpty
                  ? const Center(
                      child: CircularProgressIndicator(strokeWidth: 2))
                  : _rpcRows
                          .where((r) => (r['result_type'] ?? '') == 'product')
                          .isEmpty
                      ? Center(
                          child: Text(
                            'Sem resultados para "$_searchQuery"',
                            style: TextStyle(color: Colors.grey.shade500),
                          ),
                        )
                      : ListView.builder(
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          itemCount: _rpcRows
                              .where(
                                  (r) => (r['result_type'] ?? '') == 'product')
                              .length,
                          itemBuilder: (context, index) {
                            final productRows = _rpcRows
                                .where(
                                    (r) => (r['result_type'] ?? '') == 'product')
                                .toList();
                            final p = _resolveProduct(productRows[index]);
                            return ListTile(
                              leading: ClipRRect(
                                borderRadius: BorderRadius.circular(8),
                                child: p.photoUrl.isNotEmpty
                                    ? Image.network(p.photoUrl,
                                        width: 48,
                                        height: 48,
                                        fit: BoxFit.cover)
                                    : Container(
                                        width: 48,
                                        height: 48,
                                        color: Colors.grey.shade200,
                                        child: const Icon(
                                            Icons.fastfood_outlined,
                                            size: 22,
                                            color: Colors.grey),
                                      ),
                              ),
                              title: Text(p.name,
                                  style: const TextStyle(
                                      fontWeight: FontWeight.w600,
                                      fontSize: 14)),
                              subtitle: Text(
                                  '€${p.price.toStringAsFixed(2)}',
                                  style: const TextStyle(fontSize: 13)),
                              onTap: () => Navigator.push(
                                context,
                                MaterialPageRoute(
                                    builder: (_) =>
                                        ProductDetailScreen(product: p)),
                              ),
                            );
                          },
                        ),
            ),
          ] else ...[
            // ── Browse mode: reservar mesa + normal menu ────────────────
            // BR §14.10 — botão "Reservar mesa" só aparece quando o parceiro
            // activa reservas no painel. Default: oculto.
            // BUG fix pós-takeaway (2026-05-14): se cliente veio pelo fluxo
            // takeaway (Ir buscar), esconder também.
            Builder(builder: (context) {
              final model =
                  restaurantStore.restaurantById(widget.restaurantId);
              if (model == null || !model.reservationsEnabled) {
                return const SizedBox.shrink();
              }
              if (cart.serviceType == OrderServiceType.takeaway) {
                return const SizedBox.shrink();
              }
              return Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                child: SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => ReservationAvailabilityScreen(
                          restaurantId: model.id,
                          restaurantName: model.name,
                          restaurantPhotoUrl: model.photoUrl,
                        ),
                      ),
                    ),
                    icon: const Icon(Icons.event_seat_outlined),
                    label: const Text('Reservar mesa'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppColors.primary,
                      side: const BorderSide(color: AppColors.primary),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                ),
              );
            }),
            Expanded(
              child: grouped.isEmpty && widget.restaurant.menu.isEmpty
                  ? _EmptyMenu()
                  : grouped.isEmpty
                      // Fallback: flat MenuItem list (no Supabase products yet)
                      ? ListView.builder(
                          padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
                          itemCount: widget.restaurant.menu.length,
                          itemBuilder: (context, index) {
                            final item = widget.restaurant.menu[index];
                            final favKey =
                                'menu_${widget.restaurant.name}_${item.name}';
                            return Padding(
                              padding: const EdgeInsets.only(bottom: 10),
                              child: _LegacyMenuItemCard(
                                item: item,
                                isFavorite: favorites.isFavorite(favKey),
                                primaryColor:
                                    Theme.of(context).colorScheme.primary,
                                onFavorite: () => favorites.toggle(favKey),
                                onAdd: () {
                                  // Sessão 4C: remover fallback `?? item.name`.
                                  // BusinessMapper sempre passa product.id real
                                  // (Bug-B fix 2026-04-30).
                                  final productId = item.productId;
                                  if (productId == null ||
                                      productId.isEmpty) {
                                    throw StateError(
                                        'MenuItem sem productId: ${item.name}');
                                  }
                                  context
                                      .read<CartStore>()
                                      .addItem(CartItem(
                                          productId: productId,
                                          name: item.name,
                                          price: item.price));
                                  ScaffoldMessenger.of(context)
                                    ..hideCurrentSnackBar()
                                    ..showSnackBar(SnackBar(
                                      content: Text(
                                          '${item.name} adicionado ao carrinho'),
                                      duration:
                                          const Duration(milliseconds: 1200),
                                      behavior: SnackBarBehavior.floating,
                                      margin: const EdgeInsets.only(
                                          bottom: 80, left: 16, right: 16),
                                      dismissDirection:
                                          DismissDirection.horizontal,
                                      shape: RoundedRectangleBorder(
                                          borderRadius:
                                              BorderRadius.circular(10)),
                                    ));
                                },
                              ),
                            );
                          },
                        )
                      // ── Section grid (Ecrã 1) ───────────────────────
                      : _SectionGrid(
                          grouped: grouped,
                          emojiFor: RestaurantMenuScreen._emojiFor,
                          restaurant: widget.restaurant,
                        ),
            ),
          ],

          // ── Ver carrinho button ────────────────────────────────────────
          if (cart.items.isNotEmpty)
            SafeArea(
              top: false,
              minimum: const EdgeInsets.fromLTRB(
                  Spacing.lg, Spacing.sm, Spacing.lg, Spacing.lg),
              child: BoraPrimaryButton(
                label: 'Ver carrinho · €${cart.total.toStringAsFixed(2)}',
                icon: Icons.shopping_cart,
                onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const CartScreen()),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

// Componente reutilizável: ícone do carrinho com badge numérico.
class _CartBadgeAction extends StatelessWidget {
  const _CartBadgeAction({required this.totalItems});

  final int totalItems;

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
        if (totalItems > 0)
          Positioned(
            top: 8,
            right: 8,
            child: IgnorePointer(
              child: CircleAvatar(
                radius: 8,
                backgroundColor: AppColors.accent,
                child: Text(
                  '$totalItems',
                  style: const TextStyle(
                    fontSize: 10,
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

// ─── Section grid (Ecrã 1) ────────────────────────────────────────────────────

class _SectionGrid extends StatelessWidget {
  const _SectionGrid({
    required this.grouped,
    required this.emojiFor,
    required this.restaurant,
  });

  final Map<String, List<PartnerProduct>> grouped;
  final String Function(String) emojiFor;
  final Restaurant restaurant;

  @override
  Widget build(BuildContext context) {
    final sections = grouped.entries.toList();

    return GridView.builder(
      padding: const EdgeInsets.all(16),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        mainAxisSpacing: 12,
        crossAxisSpacing: 12,
        childAspectRatio: 0.88,
      ),
      itemCount: sections.length,
      itemBuilder: (context, index) {
        final entry = sections[index];
        final firstWithImage = entry.value.firstWhere(
          (p) => p.photoUrl.isNotEmpty,
          orElse: () => entry.value.first,
        );
        return _SectionCard(
          categoryName: '${emojiFor(entry.key)} ${entry.key}',
          imageUrl: firstWithImage.photoUrl,
          productCount: entry.value.length,
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => _SectionProductsScreen(
                restaurant: restaurant,
                categoryLabel: '${emojiFor(entry.key)} ${entry.key}',
                products: entry.value,
              ),
            ),
          ),
        );
      },
    );
  }
}

// ─── Section card ─────────────────────────────────────────────────────────────

class _SectionCard extends StatelessWidget {
  const _SectionCard({
    required this.categoryName,
    required this.imageUrl,
    required this.productCount,
    required this.onTap,
  });

  final String categoryName;
  final String imageUrl;
  final int productCount;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            boxShadow: AppColors.shadowCard,
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // ── Section image (60% of card height) ─────────────────
                Expanded(
                  flex: 60,
                  child: imageUrl.isNotEmpty
                      ? CachedNetworkImage(
                          imageUrl: imageUrl,
                          fit: BoxFit.cover,
                          fadeInDuration: const Duration(milliseconds: 120),
                          placeholder: (_, __) => _SectionPlaceholder(),
                          errorWidget: (_, __, ___) => _SectionPlaceholder(),
                        )
                      : _SectionPlaceholder(),
                ),
                // ── Name + item count (40%) ─────────────────────────────
                Expanded(
                  flex: 40,
                  child: Container(
                    color: Colors.white,
                    padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          categoryName,
                          style: const TextStyle(
                            fontWeight: FontWeight.w700,
                            fontSize: 13,
                            color: Colors.black87,
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 2),
                        Text(
                          '$productCount ${productCount == 1 ? 'item' : 'itens'}',
                          style: TextStyle(
                            fontSize: 11,
                            color: Colors.grey.shade500,
                          ),
                        ),
                      ],
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

class _SectionPlaceholder extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      color: AppColors.surface2,
      child: Icon(
        Icons.restaurant_menu_outlined,
        size: 48,
        color: Colors.grey.shade300,
      ),
    );
  }
}

// ─── Section products screen (Ecrã 2) ────────────────────────────────────────

class _SectionProductsScreen extends StatelessWidget {
  const _SectionProductsScreen({
    required this.restaurant,
    required this.categoryLabel,
    required this.products,
  });

  final Restaurant restaurant;
  final String categoryLabel;
  final List<PartnerProduct> products;

  @override
  Widget build(BuildContext context) {
    final cart = context.watch<CartStore>();
    final primaryColor = Theme.of(context).colorScheme.primary;

    void addToCart(PartnerProduct product) {
      context.read<CartStore>().addItem(CartItem(
            productId: product.id,
            name: product.name,
            price: restaurant.isPartner
                ? product.price
                : double.parse((product.price * 1.15).toStringAsFixed(2)),
          ));
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: Text('${product.name} adicionado ao carrinho'),
            duration: const Duration(milliseconds: 1200),
            behavior: SnackBarBehavior.floating,
            margin: const EdgeInsets.only(bottom: 80, left: 16, right: 16),
            dismissDirection: DismissDirection.horizontal,
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            action: SnackBarAction(
              label: 'Ver',
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const CartScreen()),
              ),
            ),
          ),
        );
    }

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: Text(
          categoryLabel,
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        backgroundColor: Colors.transparent,
        foregroundColor: Colors.white,
        elevation: 0,
        flexibleSpace: const DecoratedBox(
          decoration: BoxDecoration(gradient: AppColors.headerGradient),
        ),
        actions: [
          _CartBadgeAction(totalItems: cart.totalItems),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
              itemCount: products.length,
              itemBuilder: (context, i) {
                final product = products[i];
                return Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: _SectionProductCard(
                    product: product,
                    primaryColor: primaryColor,
                    isPartnerStore: restaurant.isPartner,
                    onAdd: () => addToCart(product),
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => ProductDetailScreen(product: product),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
          if (cart.items.isNotEmpty)
            SafeArea(
              top: false,
              minimum: const EdgeInsets.fromLTRB(
                  Spacing.lg, Spacing.sm, Spacing.lg, Spacing.lg),
              child: BoraPrimaryButton(
                label: 'Ver carrinho · €${cart.total.toStringAsFixed(2)}',
                icon: Icons.shopping_cart,
                onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const CartScreen()),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

// ─── Section product card ─────────────────────────────────────────────────────

class _SectionProductCard extends StatelessWidget {
  const _SectionProductCard({
    required this.product,
    required this.primaryColor,
    required this.isPartnerStore,
    required this.onAdd,
    required this.onTap,
  });

  final PartnerProduct product;
  final Color primaryColor;
  final bool isPartnerStore;
  final VoidCallback onAdd;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            boxShadow: AppColors.shadowCard,
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            child: Row(
              children: [
                _ProductThumbnail(photoUrl: product.photoUrl),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        product.name,
                        style: const TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 14,
                          color: Colors.black87,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      if (product.description.isNotEmpty) ...[
                        const SizedBox(height: 2),
                        Text(
                          product.description,
                          style: TextStyle(
                              fontSize: 12, color: Colors.grey.shade500),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                      const SizedBox(height: 4),
                      Text(
                        product.price > 0
                            ? '€${(isPartnerStore ? product.price : product.price * 1.15).toStringAsFixed(2)}'
                            : 'Preço indisponível',
                        style: TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 14,
                          color: product.price > 0 ? primaryColor : Colors.grey,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 10),
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
                        padding: EdgeInsets.all(7),
                        child: Icon(Icons.add, size: 18, color: Colors.white),
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

// ─── Product image thumbnail ───────────────────────────────────────────────────

class _ProductThumbnail extends StatelessWidget {
  const _ProductThumbnail({required this.photoUrl});

  final String photoUrl;

  @override
  Widget build(BuildContext context) {
    if (photoUrl.isNotEmpty) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(10),
        child: SizedBox(
          width: 64,
          height: 64,
          child: CachedNetworkImage(
            imageUrl: photoUrl,
            fit: BoxFit.cover,
            fadeInDuration: const Duration(milliseconds: 120),
            placeholder: (_, __) => _FoodPlaceholder(),
            errorWidget: (_, __, ___) => _FoodPlaceholder(),
          ),
        ),
      );
    }
    return _FoodPlaceholder();
  }
}

class _FoodPlaceholder extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      width: 64,
      height: 64,
      decoration: BoxDecoration(
        color: Colors.grey.shade100,
        borderRadius: BorderRadius.circular(10),
      ),
      alignment: Alignment.center,
      child:
          Icon(Icons.fastfood_rounded, size: 28, color: Colors.grey.shade400),
    );
  }
}

// ─── Legacy menu item card (fallback, no image) ────────────────────────────────

class _LegacyMenuItemCard extends StatelessWidget {
  const _LegacyMenuItemCard({
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
            boxShadow: AppColors.shadowCard,
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            child: Row(
              children: [
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
