import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../data/fake_data.dart';
import '../models/order_service_type.dart';
import '../models/restaurant_model.dart';
import '../stores/cart_store.dart';
import '../stores/restaurant_store.dart';
import '../utils/business_mapper.dart';
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

    final showSupermarkets =
        initialCategory == null || initialCategory == BusinessCategory.supermarket;
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
      appBar: AppBar(
        title: Text(_title),
      ),
      body: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
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
        padding: const EdgeInsets.only(top: 8, bottom: 4),
        child: Text(
          title,
          style: const TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
      const SizedBox(height: 8),
      ...entries.map(
        (entry) => _StoreTile(
          entry: entry,
          onTap: () => _openStore(context, entry),
        ),
      ),
      const SizedBox(height: 24),
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
    context.read<CartStore>().configureSession(
          serviceType: OrderServiceType.storeShopping,
          isPartnerStore: entry.business.isPartner,
          vendorName: entry.store.name,
          pickupLocation: entry.business.location,
          pickupStreet: entry.business.address,
          pickupCity: null,
          pickupPostalCode: null,
        );

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => StoreProductsScreen(store: entry.store),
      ),
    );
  }
}

class _StoreTile extends StatelessWidget {
  const _StoreTile({required this.entry, required this.onTap});

  final _StoreEntry entry;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final isPartner = entry.business.isPartner;
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 8),
      child: ListTile(
        title: Row(
          children: [
            Expanded(
              child: Text(
                entry.store.name,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            const SizedBox(width: 8),
            _PartnerBadge(isPartner: isPartner),
          ],
        ),
        subtitle: Text(
          isPartner ? 'Parceiro BORA' : 'Um estafeta irá comprar por você',
        ),
        trailing: const Icon(Icons.arrow_forward_ios),
        onTap: onTap,
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

class _StoreEntry {
  const _StoreEntry({
    required this.business,
    required this.store,
  });

  final RestaurantModel business;
  final RetailStore store;
}

