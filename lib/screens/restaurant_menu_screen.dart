import 'package:cached_network_image/cached_network_image.dart';
import 'dart:async';

import 'package:flutter/foundation.dart' show listEquals;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../config/app_colors.dart';
import '../config/app_spacing.dart';
import '../models/business_view_models.dart';
import '../models/cart_item.dart';
import '../models/order_service_type.dart';
import '../models/partner_product.dart';
import '../models/restaurant_model.dart';
import '../services/order_eta_service.dart';
import '../services/pricing_service.dart';
import '../stores/cart_store.dart';
import '../stores/favorite_store.dart';
import '../stores/restaurant_store.dart';
import '../utils/cart_feedback.dart';
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
    // M9 (paridade Glovo): os produtos chegam ordenados por sort_order
    // (sequência da fonte — ex. "Sanduíches e McMenus" primeiro no McDonald's).
    // Preservar a ordem de inserção das categorias em vez de ordenar
    // alfabeticamente, que punha "Acompanhamentos" antes dos menus.
    final grouped = <String, List<PartnerProduct>>{};
    for (final p in products) {
      final cat = p.category.isNotEmpty ? p.category : 'Outros';
      grouped.putIfAbsent(cat, () => []).add(p);
    }
    return grouped;
  }

}

// ─── State ──────────────────────────────────────────────────────────────────────

class _RestaurantMenuScreenState extends State<RestaurantMenuScreen>
    with TickerProviderStateMixin {
  // ── Search state (2026-06-05 — RPC fuzzy igual ao padrão StoreProductsScreen)
  String _searchQuery = '';
  final TextEditingController _searchController = TextEditingController();
  Timer? _rpcDebounce;
  List<Map<String, dynamic>> _rpcRows = const [];
  bool _rpcLoading = false;

  // ── M-C (2026-06-10) — página Glovo: tabs sticky sincronizadas com scroll ──
  static const double _kSectionTabsHeight = 48;

  final ScrollController _menuScroll = ScrollController();
  TabController? _sectionTabs;
  List<GlobalKey> _sectionKeys = const [];
  int _activeSection = 0;
  bool _tabTapScrolling = false;

  @override
  void initState() {
    super.initState();
    _menuScroll.addListener(_onMenuScroll);
  }

  @override
  void dispose() {
    _rpcDebounce?.cancel();
    _searchController.dispose();
    _menuScroll.dispose();
    _sectionTabs?.dispose();
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

  // ── M-C helpers (página Glovo) ─────────────────────────────────────────────

  void _syncSectionTabs(int count) {
    if (_sectionKeys.length == count) return;
    _sectionKeys = List.generate(count, (_) => GlobalKey());
    _sectionTabs?.dispose();
    _sectionTabs =
        count > 0 ? TabController(length: count, vsync: this) : null;
    if (_activeSection >= count) _activeSection = 0;
  }

  double? _revealOffsetOf(int index) {
    final ctx = _sectionKeys[index].currentContext;
    final render = ctx?.findRenderObject();
    if (render == null) return null;
    return RenderAbstractViewport.of(render)
        .getOffsetToReveal(render, 0)
        .offset;
  }

  void _scrollToSection(int index) {
    final reveal = _revealOffsetOf(index);
    if (reveal == null || !_menuScroll.hasClients) return;
    final target = (reveal - _kSectionTabsHeight)
        .clamp(0.0, _menuScroll.position.maxScrollExtent);
    setState(() => _activeSection = index);
    _tabTapScrolling = true;
    _menuScroll
        .animateTo(
          target,
          duration: const Duration(milliseconds: 350),
          curve: Curves.easeOutCubic,
        )
        .whenComplete(() => _tabTapScrolling = false);
  }

  void _onMenuScroll() {
    if (_tabTapScrolling || _sectionKeys.isEmpty || !_menuScroll.hasClients) {
      return;
    }
    final pixels = _menuScroll.position.pixels;
    var active = 0;
    for (var i = 0; i < _sectionKeys.length; i++) {
      final reveal = _revealOffsetOf(i);
      if (reveal == null) continue;
      if (pixels >= reveal - _kSectionTabsHeight - 12) active = i;
    }
    if (active != _activeSection) {
      setState(() => _activeSection = active);
      _sectionTabs?.animateTo(active);
    }
  }

  /// Mesma regra de preço do resto do ecrã: parceiro = preço puro;
  /// não-parceiro = markup runtime. B1 (2026-06-11): unificado em
  /// PricingService.applyMarkup SEM arredondar por unidade (o servidor
  /// arredonda a soma no fim — round unitário divergia ±1 cêntimo com
  /// quantidade > 1). basePrice = puro (product_lines.unit_price).
  void _addToCart(PartnerProduct product) {
    context.read<CartStore>().addItem(CartItem(
          productId: product.id,
          name: product.name,
          price: PricingService.applyMarkup(
              product.price, widget.restaurant.isPartner),
          basePrice: product.price,
        ));
    showAddedToCartSnack(context, '${product.name} no carrinho');
  }

  Widget _buildGlovoMenu(
    Map<String, List<PartnerProduct>> grouped,
    RestaurantStore restaurantStore,
  ) {
    final sections = grouped.entries.toList();
    _syncSectionTabs(sections.length);
    final model = restaurantStore.restaurantById(widget.restaurantId);

    return CustomScrollView(
      controller: _menuScroll,
      slivers: [
        SliverToBoxAdapter(
          child: _StoreHeader(
            model: model,
            fallbackName: widget.restaurant.name,
            isPartner: widget.restaurant.isPartner,
          ),
        ),
        SliverPersistentHeader(
          pinned: true,
          delegate: _SectionTabsDelegate(
            height: _kSectionTabsHeight,
            controller: _sectionTabs!,
            labels: [
              for (final e in sections)
                '${RestaurantMenuScreen._emojiFor(e.key)} ${e.key}',
            ],
            onTap: _scrollToSection,
          ),
        ),
        SliverToBoxAdapter(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (var i = 0; i < sections.length; i++)
                _MenuSection(
                  key: _sectionKeys[i],
                  title:
                      '${RestaurantMenuScreen._emojiFor(sections[i].key)} ${sections[i].key}',
                  products: sections[i].value,
                  isPartnerStore: widget.restaurant.isPartner,
                  onAdd: _addToCart,
                  onSeeAll: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => _SectionProductsScreen(
                        restaurant: widget.restaurant,
                        categoryLabel:
                            '${RestaurantMenuScreen._emojiFor(sections[i].key)} ${sections[i].key}',
                        products: sections[i].value,
                      ),
                    ),
                  ),
                ),
              const SizedBox(height: 96),
            ],
          ),
        ),
      ],
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
        backgroundColor: AppColors.primary,
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
          // "Em breve": banner fixo por baixo do cabeçalho. O cardápio
          // continua todo visível e navegável — só não aceita pedidos.
          if (cart.vendorComingSoon)
            ComingSoonBanner(text: cart.vendorComingSoonText),
          // Festas: aviso prévio das encomendas, sempre visível na loja.
          if (cart.vendorIsFestas)
            Container(
              width: double.infinity,
              color: const Color(0xFFFDF2F8),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Text(
                'Encomendas com $kFestasAvisoDias dia de antecedência · '
                'itens "Na hora" saem já',
                style: const TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF9D174D),
                ),
              ),
            ),
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
                                  // B1: exibido = cobrado (markup runtime).
                                  '€${PricingService.applyMarkup(p.price, widget.restaurant.isPartner).toStringAsFixed(2)}',
                                  style: const TextStyle(fontSize: 13)),
                              onTap: () => Navigator.push(
                                context,
                                MaterialPageRoute(
                                    builder: (_) => ProductDetailScreen(
                                          product: p,
                                          isPartnerStore:
                                              widget.restaurant.isPartner,
                                        )),
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
                                // B1: exibido = cobrado também no fallback.
                                displayPrice: PricingService.applyMarkup(
                                    item.price, widget.restaurant.isPartner),
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
                                  // B1 (2026-06-11): caminho legacy não
                                  // aplicava markup não-parceiro (BusinessMapper
                                  // passa products.price puro) — display e
                                  // carrinho ficavam abaixo do cobrado.
                                  context
                                      .read<CartStore>()
                                      .addItem(CartItem(
                                          productId: productId,
                                          name: item.name,
                                          price: PricingService.applyMarkup(
                                              item.price,
                                              widget.restaurant.isPartner),
                                          basePrice: item.price));
                                  showAddedToCartSnack(
                                      context, '${item.name} no carrinho');
                                },
                              ),
                            );
                          },
                        )
                      // ── Página Glovo (M-C 2026-06-10): header de loja
                      // + tabs sticky + secções com carrosséis horizontais.
                      : _buildGlovoMenu(grouped, restaurantStore),
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

// ─── Store header (M-C 2026-06-10 — padrão Glovo: capa + logo + métricas) ────

class _StoreHeader extends StatelessWidget {
  const _StoreHeader({
    required this.model,
    required this.fallbackName,
    required this.isPartner,
  });

  final RestaurantModel? model;
  final String fallbackName;
  final bool isPartner;

  @override
  Widget build(BuildContext context) {
    final cart = context.watch<CartStore>();
    final store = context.watch<RestaurantStore>();

    final name = model?.name ?? fallbackName;
    final hero = model?.heroImageUrl ?? '';
    final logo = model?.photoUrl ?? '';

    final client = cart.deliveryLocation;
    final pickup = model?.location;
    final distanceKm = OrderEtaService.distanceKmBetween(client, pickup);
    final window = OrderEtaService.deliveryWindowMinutes(
      clientLocation: client,
      restaurantLocation: pickup,
    );
    final fee = distanceKm == null
        ? null
        : PricingService.estimatedDeliveryFee(
            distanceKm: distanceKm,
            isPartner: isPartner,
          );
    // `model` é campo (não promove com o null-check) — bang seguro sob o guard.
    final rating = model == null ? null : store.avgRatingFor(model!.id);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Stack(
          clipBehavior: Clip.none,
          children: [
            SizedBox(
              height: 150,
              width: double.infinity,
              child: hero.isNotEmpty
                  ? CachedNetworkImage(
                      imageUrl: hero,
                      fit: BoxFit.cover,
                      fadeInDuration: const Duration(milliseconds: 120),
                      placeholder: (_, __) => const _HeaderFallback(),
                      errorWidget: (_, __, ___) => const _HeaderFallback(),
                    )
                  : const _HeaderFallback(),
            ),
            Positioned(
              left: 16,
              bottom: -28,
              child: Container(
                padding: const EdgeInsets.all(3),
                decoration: BoxDecoration(
                  color: Colors.white,
                  shape: BoxShape.circle,
                  boxShadow: AppColors.shadowCard,
                ),
                child: ClipOval(
                  child: SizedBox(
                    width: 56,
                    height: 56,
                    child: logo.isNotEmpty
                        ? CachedNetworkImage(
                            imageUrl: logo,
                            fit: BoxFit.cover,
                            errorWidget: (_, __, ___) =>
                                _LogoFallback(name: name),
                          )
                        : _LogoFallback(name: name),
                  ),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 36),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Text(
            name,
            style: const TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w800,
              color: Colors.black87,
            ),
          ),
        ),
        const SizedBox(height: 6),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Wrap(
            spacing: 12,
            runSpacing: 4,
            children: [
              if (rating != null)
                _HeaderChip(
                  icon: Icons.star_rounded,
                  label: rating.toStringAsFixed(1),
                  iconColor: Colors.amber.shade700,
                ),
              if (window != null)
                _HeaderChip(
                  icon: Icons.schedule,
                  label: '${window.$1}-${window.$2} min',
                ),
              if (fee != null)
                _HeaderChip(
                  icon: Icons.delivery_dining,
                  label: '€${fee.toStringAsFixed(2)}',
                ),
            ],
          ),
        ),
        const SizedBox(height: 10),
      ],
    );
  }
}

class _HeaderChip extends StatelessWidget {
  const _HeaderChip({required this.icon, required this.label, this.iconColor});

  final IconData icon;
  final String label;
  final Color? iconColor;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 14, color: iconColor ?? AppColors.textSecondary),
        const SizedBox(width: 3),
        Text(
          label,
          style: const TextStyle(
            fontSize: 12.5,
            fontWeight: FontWeight.w600,
            color: AppColors.textPrimary,
          ),
        ),
      ],
    );
  }
}

class _HeaderFallback extends StatelessWidget {
  const _HeaderFallback();

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(gradient: AppColors.headerGradient),
      alignment: Alignment.center,
      child: const Icon(
        Icons.storefront_outlined,
        size: 42,
        color: Colors.white70,
      ),
    );
  }
}

class _LogoFallback extends StatelessWidget {
  const _LogoFallback({required this.name});

  final String name;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: AppColors.primaryWash,
      alignment: Alignment.center,
      child: Text(
        name.isEmpty ? '?' : name.substring(0, 1).toUpperCase(),
        style: const TextStyle(
          fontSize: 22,
          fontWeight: FontWeight.w800,
          color: AppColors.primary,
        ),
      ),
    );
  }
}

// ─── Sticky section tabs (M-C) ───────────────────────────────────────────────

class _SectionTabsDelegate extends SliverPersistentHeaderDelegate {
  const _SectionTabsDelegate({
    required this.height,
    required this.controller,
    required this.labels,
    required this.onTap,
  });

  final double height;
  final TabController controller;
  final List<String> labels;
  final ValueChanged<int> onTap;

  @override
  double get minExtent => height;

  @override
  double get maxExtent => height;

  @override
  Widget build(
      BuildContext context, double shrinkOffset, bool overlapsContent) {
    return Material(
      color: Colors.white,
      elevation: overlapsContent ? 2 : 0,
      child: TabBar(
        controller: controller,
        isScrollable: true,
        tabAlignment: TabAlignment.start,
        onTap: onTap,
        labelColor: AppColors.primary,
        unselectedLabelColor: AppColors.textSecondary,
        indicatorColor: AppColors.primary,
        indicatorWeight: 3,
        dividerColor: Colors.transparent,
        labelStyle:
            const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700),
        unselectedLabelStyle:
            const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600),
        tabs: [for (final l in labels) Tab(text: l)],
      ),
    );
  }

  @override
  bool shouldRebuild(_SectionTabsDelegate oldDelegate) =>
      oldDelegate.controller != controller ||
      oldDelegate.height != height ||
      !listEquals(oldDelegate.labels, labels);
}

// ─── Secção com carrossel horizontal (M-C — padrão Glovo) ────────────────────

class _MenuSection extends StatelessWidget {
  const _MenuSection({
    super.key,
    required this.title,
    required this.products,
    required this.isPartnerStore,
    required this.onAdd,
    required this.onSeeAll,
  });

  final String title;
  final List<PartnerProduct> products;
  final bool isPartnerStore;
  final void Function(PartnerProduct) onAdd;
  final VoidCallback onSeeAll;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 18, 8, 4),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 16.5,
                    fontWeight: FontWeight.w800,
                    color: Colors.black87,
                  ),
                ),
              ),
              TextButton(
                onPressed: onSeeAll,
                child: const Text(
                  'Ver todos',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: AppColors.primary,
                  ),
                ),
              ),
            ],
          ),
        ),
        SizedBox(
          height: 210,
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            itemCount: products.length,
            itemBuilder: (context, i) => Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: _GlovoProductCard(
                product: products[i],
                isPartnerStore: isPartnerStore,
                onAdd: () => onAdd(products[i]),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

// ─── Product card vertical do carrossel (M-C) ────────────────────────────────

class _GlovoProductCard extends StatelessWidget {
  const _GlovoProductCard({
    required this.product,
    required this.isPartnerStore,
    required this.onAdd,
  });

  final PartnerProduct product;
  final bool isPartnerStore;
  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    // Mesma regra de display do _SectionProductCard: exibido = cobrado
    // (B1: fonte única PricingService.applyMarkup).
    final displayPrice =
        PricingService.applyMarkup(product.price, isPartnerStore);
    final comingSoon = context.watch<CartStore>().vendorBlocksAddToCart;
    // Loja fora de horario: o botao fica desativado e diz que esta fechada,
    // em vez de convidar a pedir.
    final fechada = context.watch<CartStore>().lojaFechada;
    final avisoFechada = context.watch<CartStore>().avisoLojaFechada;

    void openDetail() => Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => ProductDetailScreen(
              product: product,
              isPartnerStore: isPartnerStore,
            ),
          ),
        );

    return SizedBox(
      width: 142,
      child: Material(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: openDetail,
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              boxShadow: AppColors.shadowCard,
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  SizedBox(
                    height: 104,
                    child: product.photoUrl.isNotEmpty
                        ? CachedNetworkImage(
                            imageUrl: product.photoUrl,
                            fit: BoxFit.cover,
                            fadeInDuration: const Duration(milliseconds: 120),
                            placeholder: (_, __) => const _CardImageFallback(),
                            errorWidget: (_, __, ___) =>
                                const _CardImageFallback(),
                          )
                        : const _CardImageFallback(),
                  ),
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            product.name,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 12.5,
                              fontWeight: FontWeight.w600,
                              color: Colors.black87,
                            ),
                          ),
                          const Spacer(),
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  product.price > 0
                                      ? '€${displayPrice.toStringAsFixed(2)}'
                                      : 'Sem preço',
                                  style: TextStyle(
                                    fontSize: 13.5,
                                    fontWeight: FontWeight.w700,
                                    color: product.price > 0
                                        ? AppColors.primary
                                        : Colors.grey,
                                  ),
                                ),
                              ),
                              InkWell(
                                borderRadius: BorderRadius.circular(8),
                                // Com opções obrigatórias o "+" abre o
                                // detalhe (escolher menu/extras); sem opções
                                // adiciona direto — regra _SectionProductCard.
                                onTap: fechada
                                    ? () => showLojaFechadaSnackBar(
                                        context, avisoFechada)
                                    : comingSoon
                                    ? () =>
                                        showComingSoonBlockedSnackBar(context)
                                    : (product.hasRequiredOptions
                                        ? openDetail
                                        : onAdd),
                                child: Container(
                                  width: 28,
                                  height: 28,
                                  decoration: BoxDecoration(
                                    color: (comingSoon || fechada)
                                        ? Colors.grey.shade400
                                        : AppColors.primary,
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: const Icon(
                                    Icons.add,
                                    size: 16,
                                    color: Colors.white,
                                  ),
                                ),
                              ),
                            ],
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
      ),
    );
  }
}

class _CardImageFallback extends StatelessWidget {
  const _CardImageFallback();

  @override
  Widget build(BuildContext context) {
    return Container(
      color: AppColors.surface2,
      alignment: Alignment.center,
      child: Icon(
        Icons.fastfood_rounded,
        size: 30,
        color: Colors.grey.shade400,
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
      // B1 (2026-06-11): fonte única applyMarkup (sem round unitário) +
      // basePrice puro para product_lines.unit_price.
      context.read<CartStore>().addItem(CartItem(
            productId: product.id,
            name: product.name,
            price: PricingService.applyMarkup(
                product.price, restaurant.isPartner),
            basePrice: product.price,
          ));
      showAddedToCartSnack(context, '${product.name} no carrinho');
    }

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: Text(
          categoryLabel,
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        backgroundColor: AppColors.primary,
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
                        builder: (_) => ProductDetailScreen(
                          product: product,
                          isPartnerStore: restaurant.isPartner,
                        ),
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
    final comingSoon = context.watch<CartStore>().vendorBlocksAddToCart;
    // Loja fora de horario: o botao fica desativado e diz que esta fechada,
    // em vez de convidar a pedir.
    final fechada = context.watch<CartStore>().lojaFechada;
    final avisoFechada = context.watch<CartStore>().avisoLojaFechada;
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
                            // B1: fonte única applyMarkup (exibido = cobrado).
                            ? '€${PricingService.applyMarkup(product.price, isPartnerStore).toStringAsFixed(2)}'
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
                    color: (comingSoon || fechada)
                        ? Colors.grey.shade400
                        : primaryColor,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Material(
                    color: Colors.transparent,
                    child: InkWell(
                      borderRadius: BorderRadius.circular(10),
                      // Se o produto tem grupos de opção obrigatórios (bebida,
                      // tamanho, acompanhamento...), o "+" abre o detalhe para
                      // o cliente escolher — não adiciona direto. Produtos sem
                      // opções obrigatórias (mercados, bebidas avulsas) seguem
                      // a adicionar direto.
                      onTap: fechada
                          ? () => showLojaFechadaSnackBar(context, avisoFechada)
                          : comingSoon
                          ? () => showComingSoonBlockedSnackBar(context)
                          : (product.hasRequiredOptions ? onTap : onAdd),
                      child: const Padding(
                        padding: EdgeInsets.all(7),
                        child: Icon(Icons.add,
                            size: 18,
                            color: Colors.white,
                            semanticLabel: 'Adicionar'),
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
    required this.displayPrice,
    required this.isFavorite,
    required this.primaryColor,
    required this.onFavorite,
    required this.onAdd,
  });

  final MenuItem item;

  /// Preço exibido = preço cobrado (markup runtime em não-parceiro — B1).
  final double displayPrice;
  final bool isFavorite;
  final Color primaryColor;
  final VoidCallback onFavorite;
  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    final comingSoon = context.watch<CartStore>().vendorBlocksAddToCart;
    // Loja fora de horario: o botao fica desativado e diz que esta fechada,
    // em vez de convidar a pedir.
    final fechada = context.watch<CartStore>().lojaFechada;
    final avisoFechada = context.watch<CartStore>().avisoLojaFechada;
    void tapAdd() => fechada
        ? showLojaFechadaSnackBar(context, avisoFechada)
        : comingSoon
            ? showComingSoonBlockedSnackBar(context)
            : onAdd();
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: tapAdd,
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
                        '€${displayPrice.toStringAsFixed(2)}',
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
                    color: (comingSoon || fechada)
                        ? Colors.grey.shade400
                        : primaryColor,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Material(
                    color: Colors.transparent,
                    child: InkWell(
                      borderRadius: BorderRadius.circular(10),
                      onTap: tapAdd,
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
