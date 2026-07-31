import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../config/app_colors.dart';
import '../models/business_view_models.dart';
import '../models/order_service_type.dart';
import '../models/restaurant_model.dart';
import '../stores/cart_store.dart';
import '../stores/restaurant_store.dart';
import '../utils/business_mapper.dart';
import '../utils/business_opener.dart';
import '../widgets/bora/bora_screen_app_bar.dart';
import '../widgets/bora/coming_soon.dart';
import '../widgets/bora_support_fab.dart';
import 'store_categories_screen.dart';
import 'store_products_screen.dart';

enum _StoreSort { name, rating }

class StoresScreen extends StatefulWidget {
  const StoresScreen({super.key, this.initialCategory});

  final BusinessCategory? initialCategory;

  @override
  State<StoresScreen> createState() => _StoresScreenState();
}

class _StoresScreenState extends State<StoresScreen> {
  final TextEditingController _searchCtrl = TextEditingController();
  String _query = '';
  _StoreSort _sort = _StoreSort.name;

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  String get _title {
    switch (widget.initialCategory) {
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

  Widget _buildSearchSortBar(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextField(
          controller: _searchCtrl,
          onChanged: (v) => setState(() => _query = v),
          textInputAction: TextInputAction.search,
          decoration: InputDecoration(
            hintText: 'Pesquisar loja...',
            prefixIcon: const Icon(Icons.search),
            suffixIcon: _query.isEmpty
                ? null
                : IconButton(
                    icon: const Icon(Icons.clear),
                    onPressed: () {
                      _searchCtrl.clear();
                      setState(() => _query = '');
                    },
                  ),
            filled: true,
            fillColor: Colors.white,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide.none,
            ),
            contentPadding: const EdgeInsets.symmetric(horizontal: 16),
          ),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            const Text('Ordenar:', style: TextStyle(color: Colors.black54)),
            const SizedBox(width: 8),
            ChoiceChip(
              label: const Text('Nome'),
              selected: _sort == _StoreSort.name,
              onSelected: (_) => setState(() => _sort = _StoreSort.name),
            ),
            const SizedBox(width: 8),
            ChoiceChip(
              label: const Text('Avaliação'),
              selected: _sort == _StoreSort.rating,
              onSelected: (_) => setState(() => _sort = _StoreSort.rating),
            ),
          ],
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final restaurantStore = context.watch<RestaurantStore>();
    final relevantBusinesses = restaurantStore.restaurants
        .where(
          // belongsTo = categoria principal OU `extra_categories` — a mesma
          // loja pode ser listada em mais do que uma secção.
          (business) =>
              business.belongsTo(BusinessCategory.supermarket) ||
              business.belongsTo(BusinessCategory.store) ||
              business.belongsTo(BusinessCategory.pharmacy),
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

    final showSupermarkets = widget.initialCategory == null ||
        widget.initialCategory == BusinessCategory.supermarket;
    final showStores = widget.initialCategory == null ||
        widget.initialCategory == BusinessCategory.store;
    final showPharmacies = widget.initialCategory == null ||
        widget.initialCategory == BusinessCategory.pharmacy;

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
      floatingActionButton: const BoraSupportFab(),
      appBar: BoraScreenAppBar(title: _title),
      body: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
        children: [
          _buildSearchSortBar(context),
          const SizedBox(height: 16),
          ...sections,
        ],
      ),
    );
  }

  List<Widget> _buildSection({
    required BuildContext context,
    required String title,
    required List<_StoreEntry> entries,
  }) {
    if (entries.isEmpty) {
      if (widget.initialCategory != null) {
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
            onTap: () => openBusiness(
              context,
              context.read<RestaurantStore>(),
              entry.business,
            ),
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
      if (!business.belongsTo(category)) continue;
      final retailStore = BusinessMapper.buildRetailStore(
        restaurantStore: restaurantStore,
        business: business,
        sectionCategory: category,
      );
      // null means the section itself is `restaurant` (never here) — skip it.
      // Empty-product stores still appear; StoreProductsScreen shows a message.
      if (retailStore == null) continue;
      entries.add(_StoreEntry(
        business: business,
        store: retailStore,
        section: category,
      ));
    }

    // C2 — filtro de pesquisa por nome + ordenação (só sobre a lista já carregada).
    final q = _query.trim().toLowerCase();
    final filtered = q.isEmpty
        ? entries
        : entries
            .where((e) => e.store.name.toLowerCase().contains(q))
            .toList();
    filtered.sort((a, b) {
      switch (_sort) {
        case _StoreSort.rating:
          final ra = a.business.avgRating ?? -1;
          final rb = b.business.avgRating ?? -1;
          final byRating = rb.compareTo(ra); // maior avaliação primeiro
          return byRating != 0
              ? byRating
              : a.store.name
                  .toLowerCase()
                  .compareTo(b.store.name.toLowerCase());
        case _StoreSort.name:
          return a.store.name
              .toLowerCase()
              .compareTo(b.store.name.toLowerCase());
      }
    });
    return filtered;
  }
}

/// Abre o negócio com o layout de mercado/loja (categorias ou grelha de
/// produtos). Top-level para ser reutilizada pelo router `openBusiness`, que
/// atende também as secções onde a loja entra por `extra_categories`.
Future<void> openRetailBusiness(
  BuildContext context,
  RestaurantModel business,
  RetailStore store,
) async {
  // 2026-05-21 — fecho automático fora do horário.
  // Parceiros com business_hours configurado: bloqueia entrada.
  // Não-parceiros sem horário: isOpenNow() retorna true (default).
  if (!business.isOpenNow()) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(business.statusLabel()),
        duration: const Duration(seconds: 3),
      ),
    );
    return;
  }
  // BUG #6 (2026-05-13) — se há carrinho activo de OUTRA loja, pedir
  // confirmação antes de descartar.  configureSession() ainda tem o
  // silent-clear como defesa em profundidade.
  final cart = context.read<CartStore>();
  final differentVendor = cart.items.isNotEmpty &&
      cart.vendorName != null &&
      cart.vendorName != store.name;
  if (differentVendor) {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Carrinho activo'),
        content: Text(
          'Tens itens no carrinho de ${cart.vendorName}. '
          'Queres cancelar e começar novo pedido em ${store.name}?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Voltar'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Sim, novo pedido'),
          ),
        ],
      ),
    );
    if (confirm != true) return;
    if (!context.mounted) return;
    cart.clearCart();
  }

  // Prefer the store's real coordinates (now present in DB for non-partners
  // too) so distance_km reflects the actual pickup→dropoff route. Fallback
  // to the client's delivery location if missing.
  final pickupLocation = business.location ?? cart.deliveryLocation;

  cart.configureSession(
    serviceType: OrderServiceType.storeShopping,
    isPartnerStore: business.isPartner,
    vendorComingSoon: business.comingSoon,
    vendorComingSoonText: business.comingSoonLabel,
    vendorName: store.name,
    pickupLocation: pickupLocation,
    pickupStreet: business.address,
    pickupCity: null,
    pickupPostalCode: null,
  );

  final isLargeStore = business.category == BusinessCategory.supermarket ||
      business.category == BusinessCategory.store;

  Navigator.push(
    context,
    MaterialPageRoute(
      builder: (_) => isLargeStore
          ? StoreCategoriesScreen(
              restaurantId: business.id,
              storeName: store.name,
              isPartnerStore: business.isPartner,
            )
          : StoreProductsScreen(
              restaurantId: business.id,
              storeName: store.name,
              isPartnerStore: business.isPartner,
            ),
    ),
  );
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
        return AppColors.primaryMid;
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
    final cat = entry.section;
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
                    Icons.delivery_dining_rounded,
                    size: 15,
                    color: Colors.grey.shade600,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    'Estafeta entrega rápida',
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.grey.shade700,
                    ),
                  ),
                  const Spacer(),
                  if (entry.business.comingSoon) const ComingSoonChip(),
                ],
              ),
            ),
          ],
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
          child: CachedNetworkImage(
            imageUrl: photoUrl,
            fit: BoxFit.cover,
            fadeInDuration: const Duration(milliseconds: 120),
            placeholder: (_, __) =>
                _FallbackLogo(initial: initial, color: bannerColor),
            errorWidget: (_, __, ___) =>
                _FallbackLogo(initial: initial, color: bannerColor),
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
    required this.section,
  });

  final RestaurantModel business;
  final RetailStore store;

  /// Secção onde esta entrada está a ser mostrada (pode diferir da categoria
  /// principal do negócio quando vem de `extra_categories`).
  final BusinessCategory section;
}
