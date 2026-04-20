import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/business_view_models.dart';
import '../models/order_service_type.dart';
import '../models/restaurant_model.dart';
import '../stores/cart_store.dart';
import '../stores/restaurant_store.dart';
import '../utils/business_mapper.dart';
import '../widgets/bora/bora_screen_app_bar.dart';
import 'store_categories_screen.dart';
import 'store_products_screen.dart';

class StoresScreen extends StatelessWidget {
  const StoresScreen({super.key, this.initialCategory});

  final BusinessCategory? initialCategory;

  String get _title {
    switch (initialCategory) {
      case BusinessCategory.supermarket:
        return 'Supermercados';
      case BusinessCategory.store:
        return 'Lojas';
      case BusinessCategory.pharmacy:
        return 'Farmácias';
      default:
        return 'Lojas e Farmácias';
    }
  }

  @override
  Widget build(BuildContext context) {
    final restaurantStore = context.watch<RestaurantStore>();
    final relevantBusinesses = restaurantStore.restaurants
        .where(
          (business) =>
              business.category == BusinessCategory.supermarket ||
              business.category == BusinessCategory.store ||
              business.category == BusinessCategory.pharmacy,
        )
        .toList();

    final supermarketEntries = _buildEntriesForCategory(
      restaurantStore: restaurantStore,
      businesses: relevantBusinesses,
      category: BusinessCategory.supermarket,
    );
    final storeEntries = _buildEntriesForCategory(
      restaurantStore: restaurantStore,
      businesses: relevantBusinesses,
      category: BusinessCategory.store,
    );
    final pharmacyEntries = _buildEntriesForCategory(
      restaurantStore: restaurantStore,
      businesses: relevantBusinesses,
      category: BusinessCategory.pharmacy,
    );

    final showSupermarkets = initialCategory == null ||
        initialCategory == BusinessCategory.supermarket;
    final showStores =
        initialCategory == null || initialCategory == BusinessCategory.store;
    final showPharmacies =
        initialCategory == null || initialCategory == BusinessCategory.pharmacy;

    final sections = <Widget>[];
    if (showSupermarkets) {
      sections.addAll(
        _buildSection(
          context: context,
          title: 'Supermercados',
          entries: supermarketEntries,
        ),
      );
    }
    if (showStores) {
      sections.addAll(
        _buildSection(
          context: context,
          title: 'Lojas',
          entries: storeEntries,
        ),
      );
    }
    if (showPharmacies) {
      sections.addAll(
        _buildSection(
          context: context,
          title: 'Farmácias',
          entries: pharmacyEntries,
        ),
      );
    }

    if (sections.isEmpty) {
      sections.add(
        const Padding(
          padding: EdgeInsets.all(24),
          child: Center(
            child: Text('Nenhuma loja disponível no momento.'),
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: const Color(0xFFF5F5F5),
      appBar: BoraScreenAppBar(title: _title),
      body: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
        children: sections,
      ),
    );
  }

  List<Widget> _buildSection({
    required BuildContext context,
    required String title,
    required List<_StoreEntry> entries,
  }) {
    if (entries.isEmpty) {
      if (initialCategory != null) {
        return [
          Padding(
            padding: const EdgeInsets.only(top: 8, bottom: 4),
            child: Text(
              title,
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 8),
            child: Text('Nenhuma loja disponível nesta categoria.'),
          ),
        ];
      }
      return [];
    }

    return [
      Padding(
        padding: const EdgeInsets.only(top: 8, bottom: 12),
        child: Text(
          title,
          style: const TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.bold,
            color: Colors.black87,
          ),
        ),
      ),
      ...entries.map(
        (entry) => Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: _StoreTile(
            entry: entry,
            onTap: () => _openStore(context, entry),
          ),
        ),
      ),
      const SizedBox(height: 12),
    ];
  }

  List<_StoreEntry> _buildEntriesForCategory({
    required RestaurantStore restaurantStore,
    required List<RestaurantModel> businesses,
    required BusinessCategory category,
  }) {
    final entries = <_StoreEntry>[];
    for (final business in businesses) {
      if (business.category != category) continue;
      final retailStore = BusinessMapper.buildRetailStore(
        restaurantStore: restaurantStore,
        business: business,
      );
      // null means the business is a restaurant (wrong category) — skip it.
      // Empty-product stores still appear; StoreProductsScreen shows a message.
      if (retailStore == null) continue;
      entries.add(_StoreEntry(business: business, store: retailStore));
    }
    return entries;
  }

  void _openStore(BuildContext context, _StoreEntry entry) {
    // Prefer the store's real coordinates (now present in DB for non-partners
    // too) so distance_km reflects the actual pickup→dropoff route. Fallback
    // to the client's delivery location if missing.
    final pickupLocation =
        entry.business.location ?? context.read<CartStore>().deliveryLocation;

    context.read<CartStore>().configureSession(
          serviceType: OrderServiceType.storeShopping,
          isPartnerStore: entry.business.isPartner,
          vendorName: entry.store.name,
          pickupLocation: pickupLocation,
          pickupStreet: entry.business.address,
          pickupCity: null,
          pickupPostalCode: null,
        );

    final isLargeStore =
        entry.business.category == BusinessCategory.supermarket ||
            entry.business.category == BusinessCategory.store;

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => isLargeStore
            ? StoreCategoriesScreen(
                restaurantId: entry.business.id,
                storeName: entry.store.name,
              )
            : StoreProductsScreen(
                restaurantId: entry.business.id,
                storeName: entry.store.name,
              ),
      ),
    );
  }
}

class _StoreTile extends StatelessWidget {
  const _StoreTile({required this.entry, required this.onTap});

  final _StoreEntry entry;
  final VoidCallback onTap;

  Color _bannerColor(BusinessCategory cat) {
    switch (cat) {
      case BusinessCategory.supermarket:
        return const Color(0xFF1A73E8);
      case BusinessCategory.pharmacy:
        return const Color(0xFF2E7D32);
      case BusinessCategory.store:
        return const Color(0xFF6A1B9A);
      default:
        return const Color(0xFF455A64);
    }
  }

  IconData _categoryIcon(BusinessCategory cat) {
    switch (cat) {
      case BusinessCategory.supermarket:
        return Icons.local_grocery_store_rounded;
      case BusinessCategory.pharmacy:
        return Icons.local_pharmacy_rounded;
      case BusinessCategory.store:
        return Icons.storefront_rounded;
      default:
        return Icons.store_rounded;
    }
  }

  String _categoryLabel(BusinessCategory cat) {
    switch (cat) {
      case BusinessCategory.supermarket:
        return 'Supermercado';
      case BusinessCategory.pharmacy:
        return 'Farmácia';
      case BusinessCategory.store:
        return 'Loja';
      default:
        return 'Loja';
    }
  }

  @override
  Widget build(BuildContext context) {
    final isPartner = entry.business.isPartner;
    final cat = entry.business.category;
    final bannerColor = _bannerColor(cat);

    return GestureDetector(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.07),
              blurRadius: 10,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Banner ───────────────────────────────────────────────────
            Container(
              height: 80,
              decoration: BoxDecoration(
                color: bannerColor.withValues(alpha: 0.12),
                borderRadius:
                    const BorderRadius.vertical(top: Radius.circular(16)),
              ),
              child: Row(
                children: [
                  const SizedBox(width: 16),
                  _StoreLogo(
                    photoUrl: entry.business.photoUrl,
                    name: entry.store.name,
                    bannerColor: bannerColor,
                    fallbackIcon: _categoryIcon(cat),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          entry.store.name,
                          style: const TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.bold,
                            color: Colors.black87,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 2),
                        Text(
                          _categoryLabel(cat),
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.grey.shade600,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const Icon(Icons.arrow_forward_ios,
                      size: 16, color: Colors.grey),
                  const SizedBox(width: 16),
                ],
              ),
            ),

            // ── Footer ───────────────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              child: Row(
                children: [
                  Icon(
                    isPartner
                        ? Icons.verified_rounded
                        : Icons.shopping_cart_rounded,
                    size: 15,
                    color: isPartner ? Colors.green : Colors.orange,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    isPartner
                        ? 'Parceiro BORA · entrega rápida'
                        : 'Estafeta compra por você',
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.grey.shade700,
                    ),
                  ),
                  const Spacer(),
                  _PartnerBadge(isPartner: isPartner),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PartnerBadge extends StatelessWidget {
  const _PartnerBadge({required this.isPartner});

  final bool isPartner;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: isPartner ? Colors.green.shade100 : Colors.orange.shade100,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isPartner ? Colors.green : Colors.orange,
          width: 1,
        ),
      ),
      child: Text(
        isPartner ? 'Parceiro' : 'Não parceiro',
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: isPartner ? Colors.green.shade800 : Colors.orange.shade800,
        ),
      ),
    );
  }
}

class _StoreLogo extends StatelessWidget {
  const _StoreLogo({
    required this.photoUrl,
    required this.name,
    required this.bannerColor,
    required this.fallbackIcon,
  });

  final String photoUrl;
  final String name;
  final Color bannerColor;
  final IconData fallbackIcon;

  @override
  Widget build(BuildContext context) {
    final initial = name.isNotEmpty ? name[0].toUpperCase() : '?';

    if (photoUrl.isNotEmpty) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(14),
        child: SizedBox(
          width: 56,
          height: 56,
          child: Image.network(
            photoUrl,
            fit: BoxFit.cover,
            errorBuilder: (_, __, ___) => _FallbackLogo(
              initial: initial,
              color: bannerColor,
            ),
          ),
        ),
      );
    }

    return _FallbackLogo(initial: initial, color: bannerColor);
  }
}

class _FallbackLogo extends StatelessWidget {
  const _FallbackLogo({required this.initial, required this.color});

  final String initial;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 56,
      height: 56,
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(14),
      ),
      alignment: Alignment.center,
      child: Text(
        initial,
        style: const TextStyle(
          fontSize: 24,
          fontWeight: FontWeight.bold,
          color: Colors.white,
        ),
      ),
    );
  }
}

class _StoreEntry {
  const _StoreEntry({
    required this.business,
    required this.store,
  });

  final RestaurantModel business;
  final RetailStore store;
}
