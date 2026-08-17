import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../config/app_colors.dart';
import '../../models/partner_product.dart';
import '../../models/restaurant_model.dart';
import '../../screens/store_products_screen.dart';
import '../../services/pricing_service.dart';
import '../../stores/cart_store.dart';
import '../../stores/favorite_store.dart';
import '../../stores/restaurant_store.dart';
import 'market_category_chip_large.dart';
import 'market_product_card.dart';

/// Tab "Loja" do interior do mercado — padrão Glovo.
///
/// Estrutura (CustomScrollView slivers):
///   1. SliverAppBar com hero expansível (3 fallbacks)
///   2. Identidade: nome + tag "Frescura garantida"
///   3. Stats row: rating (condicional) + ETA + taxa entrega
///   4. Search bar → StoreProductsScreen
///   5. Grid "Comprar por categoria" (4 cols, TODAS as categorias por sort_order)
///   6. Secção horizontal "Em promoção" (só se ≥3 produtos)
///   7. Secção horizontal "Mais vendidos" (só se ≥3 produtos)
///   8. Carrosséis por categoria — TODAS empilhadas por sort_order (SliverList lazy)
class MarketStoreTab extends StatelessWidget {
  const MarketStoreTab({
    super.key,
    required this.restaurant,
    required this.storeName,
    required this.isPartnerStore,
  });

  final RestaurantModel restaurant;
  final String storeName;
  final bool isPartnerStore;

  // TODO: ETA hardcoded 2.5min/km — mover para platform_settings ou RPC dedicado em sessão futura.
  static const double _etaMinPerKm = 2.5;
  // Gate só para "Em promoção" / "Mais vendidos" (rails de destaque no topo).
  static const int _minSectionProducts = 3;
  // Produtos mostrados em cada carrossel de categoria (paridade Glovo: ~10-12).
  static const int _maxCarouselProducts = 12;

  // ─── Helpers de dados ─────────────────────────────────────────────────────

  String _categoryOf(PartnerProduct p) {
    if (p.categoryRoot.isNotEmpty) return _capitalize(p.categoryRoot);
    if (p.category.isNotEmpty) return _capitalize(p.category);
    return _capitalize(p.name.split(' ').first);
  }

  String _capitalize(String s) =>
      s.isEmpty ? s : s[0].toUpperCase() + s.substring(1).toLowerCase();

  /// Todas as categorias na ordem de sort_order. O RestaurantStore devolve os
  /// produtos já ordenados por sort_order (sequência da fonte, ex. Glovo) — por
  /// isso a ordem de 1ª aparição de cada categoria === ordem de sort_order.
  /// Map literal Dart = LinkedHashMap → preserva ordem de inserção.
  List<MapEntry<String, List<PartnerProduct>>> _orderedCategories(
      List<PartnerProduct> products) {
    final map = <String, List<PartnerProduct>>{};
    for (final p in products) {
      map.putIfAbsent(_categoryOf(p), () => []).add(p);
    }
    return map.entries.toList();
  }

  /// Foto do 1º produto popular da categoria, ou 1º produto com foto.
  String? _photoForCategory(List<PartnerProduct> products) {
    final popular = products.where((p) => p.isPopular && p.photoUrl.isNotEmpty);
    if (popular.isNotEmpty) return popular.first.photoUrl;
    final withPhoto = products.where((p) => p.photoUrl.isNotEmpty);
    return withPhoto.isNotEmpty ? withPhoto.first.photoUrl : null;
  }

  String _etaText(double distanceKm) {
    if (distanceKm <= 0) return '30-45 min';
    final base = (distanceKm * _etaMinPerKm).floor();
    final lo = base < 5 ? 5 : base;
    return '$lo-${lo + 15} min';
  }

  // ─── Build ────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final restaurantStore = context.watch<RestaurantStore>();
    final cartStore = context.watch<CartStore>();
    final favoriteStore = context.watch<FavoriteStore>();

    final products = restaurantStore.partnerProductsForRestaurant(
      restaurant.id,
      onlyAvailable: true,
    );

    final promoProducts = products.where((p) => p.isOnSale).toList();
    final popularProducts = products.where((p) => p.isPopular).toList();
    // TODAS as categorias por sort_order — alimenta a grelha E os carrosséis.
    final orderedCats = _orderedCategories(products);

    final favKey = 'restaurant_$storeName';
    final isFav = favoriteStore.isFavorite(favKey);

    return CustomScrollView(
      slivers: [
        // ── 1. Hero SliverAppBar ──────────────────────────────────────────
        SliverAppBar(
          pinned: true,
          expandedHeight: 220,
          backgroundColor: AppColors.primary,
          leading: const _BackButton(),
          actions: [
            _FavoriteButton(
              isFav: isFav,
              onTap: () => favoriteStore.toggle(favKey),
            ),
            const SizedBox(width: 8),
          ],
          flexibleSpace: FlexibleSpaceBar(
            collapseMode: CollapseMode.parallax,
            background: _HeroBanner(
              heroImageUrl: restaurant.heroImageUrl,
              photoUrl: restaurant.photoUrl.isNotEmpty
                  ? restaurant.photoUrl
                  : null,
              storeName: storeName,
            ),
          ),
        ),

        // ── 2. Identidade ─────────────────────────────────────────────────
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  storeName,
                  style: const TextStyle(
                    fontSize: 26,
                    fontWeight: FontWeight.bold,
                    color: AppColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 6),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: AppColors.primary.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: const Text(
                    'Frescura garantida',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: AppColors.primary,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),

        // ── 3. Stats row ──────────────────────────────────────────────────
        // Taxa de entrega pela MESMA fonte da lista de restaurantes
        // (PricingService.estimatedDeliveryFee) — antes era '€2,50' fixo no
        // texto, que ficava errado acima de 4 km e se a setting mudasse.
        SliverToBoxAdapter(
          child: _StatsRow(
            avgRating: restaurant.avgRating,
            ratingsCount: restaurant.ratingsCount,
            etaText: _etaText(cartStore.distanceKm),
            feeText:
                '€${PricingService.estimatedDeliveryFee(distanceKm: cartStore.distanceKm, isPartner: isPartnerStore).toStringAsFixed(2)}',
          ),
        ),

        // ── 4. Search bar ─────────────────────────────────────────────────
        SliverToBoxAdapter(
          child: _SearchBar(
            storeName: storeName,
            restaurantId: restaurant.id,
            isPartnerStore: isPartnerStore,
          ),
        ),

        // ── 5. Grid "Comprar por categoria" (TODAS, por sort_order) ────────
        if (orderedCats.isNotEmpty)
          SliverToBoxAdapter(
            child: _CategoryGrid(
              categories: orderedCats
                  .map((e) => _CategoryEntry(
                        name: e.key,
                        photoUrl: _photoForCategory(e.value),
                      ))
                  .toList(),
              restaurantId: restaurant.id,
              storeName: storeName,
              isPartnerStore: isPartnerStore,
            ),
          ),

        // ── 6. Secção "Em promoção" ───────────────────────────────────────
        if (promoProducts.length >= _minSectionProducts)
          SliverToBoxAdapter(
            child: _HorizontalSection(
              title: 'Em promoção',
              products: promoProducts,
              restaurantId: restaurant.id,
              storeName: storeName,
              isPartnerStore: isPartnerStore,
              onSeeAll: () => _openProducts(context, null),
            ),
          ),

        // ── 7. Secção "Mais vendidos" ─────────────────────────────────────
        if (popularProducts.length >= _minSectionProducts)
          SliverToBoxAdapter(
            child: _HorizontalSection(
              title: 'Mais vendidos',
              products: popularProducts,
              restaurantId: restaurant.id,
              storeName: storeName,
              isPartnerStore: isPartnerStore,
              onSeeAll: () => _openProducts(context, null),
            ),
          ),

        // ── 8. Carrosséis por categoria — TODAS, por sort_order, lazy ──────
        // SliverList constrói só os carrosséis visíveis (perf: até 38
        // categorias no Continente). Cada carrossel mostra os 1ºs
        // _maxCarouselProducts produtos; a seta "→" abre a categoria completa.
        SliverList(
          delegate: SliverChildBuilderDelegate(
            (ctx, i) {
              final entry = orderedCats[i];
              final catProducts =
                  entry.value.take(_maxCarouselProducts).toList();
              return _HorizontalSection(
                title: entry.key,
                products: catProducts,
                restaurantId: restaurant.id,
                storeName: storeName,
                isPartnerStore: isPartnerStore,
                onSeeAll: () => _openProducts(ctx, entry.key),
              );
            },
            childCount: orderedCats.length,
          ),
        ),

        // ── Rodapé ────────────────────────────────────────────────────────
        SliverToBoxAdapter(
            child: _Footer(
                feeLabel:
                    '€${PricingService.estimatedDeliveryFee(distanceKm: cartStore.distanceKm, isPartner: isPartnerStore).toStringAsFixed(2)}')),
        const SliverToBoxAdapter(child: SizedBox(height: 24)),
      ],
    );
  }

  void _openProducts(BuildContext context, String? category) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => StoreProductsScreen(
          restaurantId: restaurant.id,
          storeName: storeName,
          initialCategory: category,
          isPartnerStore: isPartnerStore,
        ),
      ),
    );
  }
}

// ─── Hero Banner ─────────────────────────────────────────────────────────────

class _HeroBanner extends StatelessWidget {
  const _HeroBanner({
    required this.heroImageUrl,
    required this.photoUrl,
    required this.storeName,
  });

  final String? heroImageUrl;
  final String? photoUrl;
  final String storeName;

  @override
  Widget build(BuildContext context) {
    // Fallback chain:
    //   1. heroImageUrl (banner dedicado)
    //   2. photoUrl + gradient verde Bora overlay
    //   3. Cor sólida AppColors.primary + ícone storefront
    Widget background;
    if (heroImageUrl != null && heroImageUrl!.isNotEmpty) {
      background = CachedNetworkImage(
        imageUrl: heroImageUrl!,
        fit: BoxFit.cover,
        width: double.infinity,
        height: double.infinity,
        errorWidget: (_, __, ___) => _fallbackGradient(photoUrl),
      );
    } else if (photoUrl != null && photoUrl!.isNotEmpty) {
      background = _fallbackGradient(photoUrl);
    } else {
      background = _solidFallback();
    }

    return Stack(
      fit: StackFit.expand,
      children: [
        background,
        // Gradient escuro no fundo para legibilidade
        const Align(
          alignment: Alignment.bottomCenter,
          child: SizedBox(
            height: 80,
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.bottomCenter,
                  end: Alignment.topCenter,
                  colors: [Color(0xAA000000), Colors.transparent],
                ),
              ),
              child: SizedBox.expand(),
            ),
          ),
        ),
      ],
    );
  }

  Widget _fallbackGradient(String? url) {
    return Stack(
      fit: StackFit.expand,
      children: [
        if (url != null && url.isNotEmpty)
          CachedNetworkImage(
            imageUrl: url,
            fit: BoxFit.cover,
            errorWidget: (_, __, ___) => _solidFallback(),
          )
        else
          _solidFallback(),
        Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [
                AppColors.primary.withValues(alpha: 0.6),
                AppColors.primary.withValues(alpha: 0.1),
              ],
              begin: Alignment.bottomLeft,
              end: Alignment.topRight,
            ),
          ),
        ),
      ],
    );
  }

  Widget _solidFallback() => Container(
        color: AppColors.primary,
        child: const Center(
          child: Icon(Icons.storefront, size: 80, color: Colors.white54),
        ),
      );
}

// ─── Back Button ─────────────────────────────────────────────────────────────

class _BackButton extends StatelessWidget {
  const _BackButton();
  @override
  Widget build(BuildContext context) => IconButton(
        icon: Container(
          width: 32,
          height: 32,
          decoration: BoxDecoration(
            color: Colors.black45,
            shape: BoxShape.circle,
          ),
          child: const Icon(Icons.arrow_back, color: Colors.white, size: 18),
        ),
        onPressed: () => Navigator.of(context).pop(),
      );
}

// ─── Favorite Button ─────────────────────────────────────────────────────────

class _FavoriteButton extends StatelessWidget {
  const _FavoriteButton({required this.isFav, required this.onTap});
  final bool isFav;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => IconButton(
        icon: Container(
          width: 32,
          height: 32,
          decoration: const BoxDecoration(
            color: Colors.black45,
            shape: BoxShape.circle,
          ),
          child: Icon(
            isFav ? Icons.favorite : Icons.favorite_border,
            color: isFav ? Colors.red : Colors.white,
            size: 18,
          ),
        ),
        onPressed: onTap,
      );
}

// ─── Stats Row ────────────────────────────────────────────────────────────────

class _StatsRow extends StatelessWidget {
  const _StatsRow({
    required this.avgRating,
    required this.ratingsCount,
    required this.etaText,
    required this.feeText,
  });

  final double? avgRating;
  final int ratingsCount;
  final String etaText;

  /// Taxa de entrega calculada (fonte: PricingService) — nunca hardcoded.
  final String feeText;

  @override
  Widget build(BuildContext context) {
    final showRating = avgRating != null && ratingsCount >= 3;
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      padding: const EdgeInsets.symmetric(vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: const [
          BoxShadow(color: Color(0x0F000000), blurRadius: 4, offset: Offset(0, 2)),
        ],
      ),
      child: Row(
        children: [
          if (showRating) ...[
            Expanded(child: _StatCell(
              icon: Icons.star_rounded,
              iconColor: const Color(0xFFFFB300),
              label: avgRating!.toStringAsFixed(1),
              sublabel: '(${ratingsCount})',
            )),
            const _Divider(),
          ],
          Expanded(child: _StatCell(
            icon: Icons.access_time_rounded,
            iconColor: AppColors.primary,
            label: etaText,
            sublabel: 'ETA',
          )),
          const _Divider(),
          Expanded(child: _StatCell(
            icon: Icons.delivery_dining,
            iconColor: AppColors.primary,
            label: feeText,
            sublabel: 'Entrega',
          )),
        ],
      ),
    );
  }
}

class _StatCell extends StatelessWidget {
  const _StatCell({
    required this.icon,
    required this.iconColor,
    required this.label,
    required this.sublabel,
  });

  final IconData icon;
  final Color iconColor;
  final String label;
  final String sublabel;

  @override
  Widget build(BuildContext context) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: iconColor, size: 18),
          const SizedBox(height: 2),
          Text(label,
              style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 13,
                  color: AppColors.textPrimary)),
          Text(sublabel,
              style: const TextStyle(
                  fontSize: 10, color: AppColors.textSecondary)),
        ],
      );
}

class _Divider extends StatelessWidget {
  const _Divider();
  @override
  Widget build(BuildContext context) => Container(
        width: 1,
        height: 32,
        color: AppColors.divider,
      );
}

// ─── Search Bar ───────────────────────────────────────────────────────────────

class _SearchBar extends StatelessWidget {
  const _SearchBar({
    required this.storeName,
    required this.restaurantId,
    required this.isPartnerStore,
  });

  final String storeName;
  final String restaurantId;
  final bool isPartnerStore;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
      child: GestureDetector(
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => StoreProductsScreen(
              restaurantId: restaurantId,
              storeName: storeName,
              isPartnerStore: isPartnerStore,
            ),
          ),
        ),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: const Color(0xFFF5F5F5),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: const Color(0xFFE0E0E0)),
          ),
          child: Row(
            children: [
              const Icon(Icons.search, color: AppColors.textSecondary, size: 20),
              const SizedBox(width: 8),
              Text(
                'Procurar em $storeName...',
                style: const TextStyle(
                  color: AppColors.textSecondary,
                  fontSize: 14,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─── Category Grid ────────────────────────────────────────────────────────────

class _CategoryGrid extends StatelessWidget {
  const _CategoryGrid({
    required this.categories,
    required this.restaurantId,
    required this.storeName,
    required this.isPartnerStore,
  });

  final List<_CategoryEntry> categories;
  final String restaurantId;
  final String storeName;
  final bool isPartnerStore;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.only(bottom: 10),
            child: Text(
              'Comprar por categoria',
              style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.bold,
                color: AppColors.textPrimary,
              ),
            ),
          ),
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 4,
              crossAxisSpacing: 8,
              mainAxisSpacing: 8,
              childAspectRatio: 0.85,
            ),
            itemCount: categories.length,
            itemBuilder: (_, i) {
              final cat = categories[i];
              return MarketCategoryChipLarge(
                categoryName: cat.name,
                photoUrl: cat.photoUrl,
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => StoreProductsScreen(
                      restaurantId: restaurantId,
                      storeName: storeName,
                      initialCategory: cat.name,
                      isPartnerStore: isPartnerStore,
                    ),
                  ),
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}

// ─── Horizontal Section ───────────────────────────────────────────────────────

class _HorizontalSection extends StatelessWidget {
  const _HorizontalSection({
    required this.title,
    required this.products,
    required this.restaurantId,
    required this.storeName,
    required this.isPartnerStore,
    required this.onSeeAll,
  });

  final String title;
  final List<PartnerProduct> products;
  final String restaurantId;
  final String storeName;
  final bool isPartnerStore;
  final VoidCallback onSeeAll;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                title,
                style: const TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.bold,
                  color: AppColors.textPrimary,
                ),
              ),
              GestureDetector(
                onTap: onSeeAll,
                child: Container(
                  width: 28,
                  height: 28,
                  decoration: const BoxDecoration(
                    color: AppColors.textPrimary,
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.arrow_forward,
                      color: Colors.white, size: 16),
                ),
              ),
            ],
          ),
        ),
        SizedBox(
          height: 220,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            itemCount: products.length,
            separatorBuilder: (_, __) => const SizedBox(width: 10),
            itemBuilder: (_, i) => MarketProductCard(
              product: products[i],
              restaurantId: restaurantId,
              storeName: storeName,
              isPartnerStore: isPartnerStore,
            ),
          ),
        ),
      ],
    );
  }
}

// ─── Footer ───────────────────────────────────────────────────────────────────

class _Footer extends StatelessWidget {
  const _Footer({required this.feeLabel});

  /// Mesma taxa calculada da stats row (fonte: PricingService).
  final String feeLabel;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 24, 16, 8),
        child: GestureDetector(
          onTap: () => showDialog(
            context: context,
            builder: (_) => AlertDialog(
              title: const Text('Taxas e informações'),
              content: Text(
                'Taxa de entrega: $feeLabel\n'
                'Taxa de serviço: incluída no preço dos produtos\n'
                'Taxa de saco: €0,10/saco (cobrada após entrega)',
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Fechar'),
                ),
              ],
            ),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: const [
              Text(
                'Informações sobre as taxas ',
                style: TextStyle(
                    fontSize: 12, color: AppColors.textSecondary),
              ),
              Icon(Icons.info_outline,
                  size: 14, color: AppColors.textSecondary),
            ],
          ),
        ),
      );
}

// ─── Internal model ───────────────────────────────────────────────────────────

class _CategoryEntry {
  const _CategoryEntry({required this.name, required this.photoUrl});
  final String name;
  final String? photoUrl;
}
