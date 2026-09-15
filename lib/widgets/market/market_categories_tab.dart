import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../config/app_colors.dart';
import '../../models/partner_product.dart';
import '../../screens/store_products_screen.dart';
import '../../stores/restaurant_store.dart';

import '../../l10n/tr.dart';

/// Tab "Categorias" do interior do mercado — lista vertical estilo Glovo.
/// Thumbnail + nome + sub-categorias resumo + chevron.
/// Toque → StoreProductsScreen(initialCategory: cat).
class MarketCategoriesTab extends StatelessWidget {
  const MarketCategoriesTab({
    super.key,
    required this.restaurantId,
    required this.storeName,
    required this.isPartnerStore,
  });

  final String restaurantId;
  final String storeName;
  final bool isPartnerStore;

  String _categoryOf(PartnerProduct p) {
    if (p.categoryRoot.isNotEmpty) return _cap(p.categoryRoot);
    if (p.category.isNotEmpty) return _cap(p.category);
    return _cap(p.name.split(' ').first);
  }

  String _cap(String s) =>
      s.isEmpty ? s : s[0].toUpperCase() + s.substring(1).toLowerCase();

  /// Foto do 1º produto popular da categoria, ou 1º produto com foto.
  String? _photoFor(List<PartnerProduct> products) {
    final popular =
        products.where((p) => p.isPopular && p.photoUrl.isNotEmpty);
    if (popular.isNotEmpty) return popular.first.photoUrl;
    final withPhoto = products.where((p) => p.photoUrl.isNotEmpty);
    return withPhoto.isNotEmpty ? withPhoto.first.photoUrl : null;
  }

  /// Primeiras 3 sub-categorias distintas (p.category) dentro da cat-root.
  String _subCatsLabel(List<PartnerProduct> products, String catRoot) {
    final subs = products
        .where((p) => _categoryOf(p) == catRoot)
        .map((p) => p.category.isNotEmpty ? _cap(p.category) : '')
        .where((s) => s.isNotEmpty && s != catRoot)
        .toSet()
        .take(3)
        .toList();

    if (subs.isEmpty) {
      // Fallback: primeiros 3 nomes de produtos
      final names = products
          .where((p) => _categoryOf(p) == catRoot)
          .map((p) => p.name.split(' ').first)
          .take(3)
          .toList();
      return names.join(', ');
    }
    return subs.join(', ');
  }

  @override
  Widget build(BuildContext context) {
    final restaurantStore = context.watch<RestaurantStore>();
    final products = restaurantStore.partnerProductsForRestaurant(
      restaurantId,
      onlyAvailable: true,
    );

    // Agrupa por categoria, ordena por contagem desc
    final counts = <String, List<PartnerProduct>>{};
    for (final p in products) {
      counts.putIfAbsent(_categoryOf(p), () => []).add(p);
    }
    final categories = counts.entries.toList()
      ..sort((a, b) => b.value.length.compareTo(a.value.length));

    if (categories.isEmpty) {
      // Hotfix (2026-06-12): durante o full-load da loja, mostrar spinner em
      // vez do falso "Sem categorias" (que piscava enquanto carregava).
      if (restaurantStore.storeProductsLoading(restaurantId)) {
        return const Center(child: CircularProgressIndicator());
      }
      return Center(
        child: Text(
          'Sem categorias disponíveis.'.tr,
          style: const TextStyle(color: AppColors.textSecondary),
        ),
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.only(top: 8, bottom: 24),
      itemCount: categories.length,
      separatorBuilder: (_, __) =>
          const Divider(height: 1, color: AppColors.divider),
      itemBuilder: (context, i) {
        final entry = categories[i];
        final catName = entry.key;
        final catProducts = entry.value;
        final photo = _photoFor(catProducts);
        final subLabel = _subCatsLabel(catProducts, catName);

        return _CategoryListTile(
          categoryName: catName,
          productCount: catProducts.length,
          photoUrl: photo,
          subCatsLabel: subLabel,
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => StoreProductsScreen(
                restaurantId: restaurantId,
                storeName: storeName,
                initialCategory: catName,
                isPartnerStore: isPartnerStore,
              ),
            ),
          ),
        );
      },
    );
  }
}

class _CategoryListTile extends StatelessWidget {
  const _CategoryListTile({
    required this.categoryName,
    required this.productCount,
    required this.photoUrl,
    required this.subCatsLabel,
    required this.onTap,
  });

  final String categoryName;
  final int productCount;
  final String? photoUrl;
  final String subCatsLabel;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            // Thumbnail 60×60
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: SizedBox(
                width: 60,
                height: 60,
                child: _Thumbnail(photoUrl: photoUrl),
              ),
            ),
            const SizedBox(width: 14),
            // Texto
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    categoryName,
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  if (subCatsLabel.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(
                      subCatsLabel,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 12,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ],
                  const SizedBox(height: 2),
                  Text(
                    '{0} produto{1}'.trArgs([productCount, productCount != 1 ? 's' : '']),
                    style: const TextStyle(
                      fontSize: 11,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
            const Icon(Icons.chevron_right,
                color: AppColors.textSecondary, size: 22),
          ],
        ),
      ),
    );
  }
}

class _Thumbnail extends StatelessWidget {
  const _Thumbnail({required this.photoUrl});
  final String? photoUrl;

  @override
  Widget build(BuildContext context) {
    final url = photoUrl;
    if (url != null && url.isNotEmpty) {
      return CachedNetworkImage(
        imageUrl: url,
        fit: BoxFit.cover,
        errorWidget: (_, __, ___) => const _Placeholder(),
      );
    }
    return const _Placeholder();
  }
}

class _Placeholder extends StatelessWidget {
  const _Placeholder();
  @override
  Widget build(BuildContext context) => Container(
        color: const Color(0xFFE8F5E9),
        child: const Center(
          child: Icon(Icons.category_outlined,
              size: 24, color: AppColors.primary),
        ),
      );
}
