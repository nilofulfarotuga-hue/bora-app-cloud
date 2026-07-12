import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/cart_item.dart';
import '../models/partner_product.dart';
import '../models/product_variant.dart';
import '../services/pricing_service.dart';
import '../stores/cart_store.dart';
import '../stores/favorite_store.dart';
import '../stores/restaurant_store.dart';
import '../utils/cart_feedback.dart';
import '../widgets/bora/bora_product_card.dart';
import '../widgets/bora/bora_screen_app_bar.dart';
import '../widgets/bora_support_fab.dart';
import 'cart_screen.dart';
import 'product_detail_screen.dart';

class StoreProductsScreen extends StatefulWidget {
  final String restaurantId;
  final String storeName;
  final String? initialCategory;
  final bool isPartnerStore;

  const StoreProductsScreen({
    super.key,
    required this.restaurantId,
    required this.storeName,
    required this.isPartnerStore,
    this.initialCategory,
  });

  @override
  State<StoreProductsScreen> createState() => _StoreProductsScreenState();
}

class _StoreProductsScreenState extends State<StoreProductsScreen> {
  late String _selectedCategory;
  String _searchQuery = '';
  final TextEditingController _searchController = TextEditingController();
  // RPC-backed search (robust to accents/case via server-side normalization).
  Timer? _rpcDebounce;
  List<Map<String, dynamic>> _rpcRows = const [];
  bool _rpcLoading = false;

  // ── Normalise: remove accents + lowercase ──────────────────────────────────
  String _normalize(String text) {
    const accents = 'àáâãäåèéêëìíîïòóôõöùúûüýñçÀÁÂÃÄÅÈÉÊËÌÍÎÏÒÓÔÕÖÙÚÛÜÝÑÇ';
    const normal = 'aaaaaaeeeeiiiioooooouuuuyncaaaaaaeeeeiiiioooooouuuuync';
    String result = text.toLowerCase();
    for (int i = 0; i < accents.length; i++) {
      result = result.replaceAll(accents[i], normal[i]);
    }
    return result;
  }

  @override
  void initState() {
    super.initState();
    _selectedCategory = widget.initialCategory ?? 'Todos';
    // Hotfix (2026-06-12): carrega a loja INTEIRA ao abrir (full-load
    // on-demand). Necessário para o filtro/secções por categoria verem todas
    // as categorias. Idempotente (não recarrega se já carregada).
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      context
          .read<RestaurantStore>()
          .loadFullStoreProducts(widget.restaurantId);
    });
  }

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
                rows.whereType<Map<String, dynamic>>(),
              )
            : const [];
        _rpcLoading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _rpcRows = const [];
        _rpcLoading = false;
      });
    }
  }

  String _categoryOf(PartnerProduct p) {
    // Prefer category_root (grouped mother category, e.g. "Mercearia")
    // over the fragmented leaf category ("mercearia/bolacha/...").
    if (p.categoryRoot.isNotEmpty) return _capitalize(p.categoryRoot);
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
      final q = _normalize(_searchQuery);
      result = result
          .where((p) =>
              _normalize(p.name).contains(q) ||
              _normalize(p.description).contains(q))
          .toList();
    }
    if (_selectedCategory != 'Todos') {
      result =
          result.where((p) => _categoryOf(p) == _selectedCategory).toList();
    }
    return result;
  }

  List<PartnerProduct> _getSuggestions(List<PartnerProduct> products) {
    if (_searchQuery.isEmpty) return [];
    final q = _normalize(_searchQuery);
    return products
        .where((p) => _normalize(p.name).contains(q))
        .take(10)
        .toList();
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
    final suggestions =
        _searchQuery.trim().length >= 2 ? _getSuggestions(products) : <PartnerProduct>[];
    final isFruit = _isFruitCategory(_selectedCategory);
    final grouped = _showSections ? _groupByCategory(filtered) : null;

    return Scaffold(
      backgroundColor: const Color(0xFFF5F5F5),
      floatingActionButton: const BoraSupportFab(),
      appBar: BoraScreenAppBar(
        title: widget.storeName,
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
              onChanged: (v) {
                setState(() => _searchQuery = v);
                _scheduleRpcSearch(v);
              },
              onSubmitted: (_) {},
              decoration: InputDecoration(
                hintText: 'Buscar produtos...',
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

          // ── Search mode: RPC results fill screen / Browse mode: chips + grid ─
          // 2026-06-05: antes os resultados RPC só apareciam num painel 360px
          // que desaparecia ao pressionar Enter. A lista principal usava apenas
          // filtro local (contains), falhando em queries fuzzy (ex: "aguas" →
          // "Água"). Agora quando há query ≥ 2 chars, o painel RPC ocupa o
          // Expanded completo — funciona para TODAS as lojas, mesmo sem produtos
          // em memória (RPC sintetiza PartnerProduct do row DB directamente).
          if (_searchQuery.trim().length >= 2) ...[
            Expanded(
              child: _SuggestionsPanel(
                rpcRows: _rpcRows,
                rpcLoading: _rpcLoading,
                localFallback: suggestions,
                loadedProducts: products,
                isPartnerStore: widget.isPartnerStore,
                onPickSection: (categoryRoot) {
                  _searchController.clear();
                  setState(() {
                    _searchQuery = '';
                    _rpcRows = const [];
                    _rpcLoading = false;
                    _selectedCategory = _capitalize(categoryRoot);
                  });
                },
                onPickProduct: (p) {
                  _searchController.clear();
                  setState(() {
                    _searchQuery = '';
                    _rpcRows = const [];
                    _rpcLoading = false;
                  });
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                        builder: (_) => ProductDetailScreen(
                              product: p,
                              isPartnerStore: widget.isPartnerStore,
                            )),
                  );
                },
              ),
            ),
          ] else ...[
            // ── Browse mode: category chips + sectioned/flat grid ───────────
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
            Expanded(
              // Hotfix (2026-06-12): a loja é carregada inteira ao abrir
              // (loadFullStoreProducts). Enquanto carrega e ainda não há
              // produtos da categoria → spinner; vazio real → _EmptyState.
              child: filtered.isEmpty
                  ? (restaurantStore.storeProductsLoading(widget.restaurantId)
                      ? const Center(child: CircularProgressIndicator())
                      : _EmptyState(
                          hasSearch: _searchQuery.isNotEmpty,
                          searchQuery: _searchQuery,
                          onRefresh: () => setState(() {}),
                        ))
                  : _showSections
                      ? _SectionedView(
                          grouped: grouped!,
                          isFruitCategory: _isFruitCategory,
                          isPartnerStore: widget.isPartnerStore,
                        )
                      : _FlatGridView(
                          products: filtered,
                          showPerKg: isFruit,
                          isPartnerStore: widget.isPartnerStore,
                        ),
            ),
          ],

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

// ─── Category style lookup ─────────────────────────────────────────────────────

({Color color, String emoji}) _categoryStyle(String category) {
  final cat = category.toLowerCase();
  if (cat.contains('animal') || cat.contains('pet') || cat.contains('mascot')) {
    return (color: const Color(0xFFFF8C42), emoji: '🐾');
  }
  if (cat.contains('bebida') || cat.contains('drink') || cat.contains('sumo')) {
    return (color: const Color(0xFF4FC3F7), emoji: '🥤');
  }
  if (cat.contains('bebé') || cat.contains('bebe') || cat.contains('baby')) {
    return (color: const Color(0xFFF48FB1), emoji: '👶');
  }
  if (cat.contains('bio') || cat.contains('orgân') || cat.contains('natural')) {
    return (color: const Color(0xFF66BB6A), emoji: '🌿');
  }
  if (cat.contains('casa') || cat.contains('lar') || cat.contains('home')) {
    return (color: const Color(0xFFFFD54F), emoji: '🏠');
  }
  if (cat.contains('chocol') || cat.contains('doce') || cat.contains('sweet')) {
    return (color: const Color(0xFFA1887F), emoji: '🍫');
  }
  if (cat.contains('congelad') ||
      cat.contains('frozen') ||
      cat.contains('gelad')) {
    return (color: const Color(0xFF80DEEA), emoji: '❄️');
  }
  if (cat.contains('fitness') ||
      cat.contains('proteína') ||
      cat.contains('protein')) {
    return (color: const Color(0xFF9CCC65), emoji: '💪');
  }
  if (cat.contains('carne') || cat.contains('meat') || cat.contains('talh')) {
    return (color: const Color(0xFFEF9A9A), emoji: '🥩');
  }
  if (cat.contains('peixe') ||
      cat.contains('fish') ||
      cat.contains('marisco')) {
    return (color: const Color(0xFF4DB6AC), emoji: '🐟');
  }
  if (cat.contains('frut') || cat.contains('fruit')) {
    return (color: const Color(0xFFFFB74D), emoji: '🍎');
  }
  if (cat.contains('legum') ||
      cat.contains('vegeta') ||
      cat.contains('hortal')) {
    return (color: const Color(0xFF81C784), emoji: '🥬');
  }
  if (cat.contains('latic') ||
      cat.contains('leite') ||
      cat.contains('queijo') ||
      cat.contains('dairy')) {
    return (color: const Color(0xFFFFF9C4), emoji: '🥛');
  }
  if (cat.contains('mercearia') || cat.contains('grocer')) {
    return (color: const Color(0xFFBCAAA4), emoji: '🛒');
  }
  if (cat.contains('padaria') ||
      cat.contains('pão') ||
      cat.contains('bakery')) {
    return (color: const Color(0xFFFFCC80), emoji: '🍞');
  }
  if (cat.contains('higiene') ||
      cat.contains('beleza') ||
      cat.contains('beauty')) {
    return (color: const Color(0xFF90CAF9), emoji: '🧴');
  }
  if (cat.contains('limpeza') || cat.contains('clean')) {
    return (color: const Color(0xFF80CBC4), emoji: '🧹');
  }
  if (cat.contains('charcut') ||
      cat.contains('enchid') ||
      cat.contains('frios')) {
    return (color: const Color(0xFFF8BBD0), emoji: '🧀');
  }
  if (cat.contains('snack') ||
      cat.contains('salgado') ||
      cat.contains('bolach')) {
    return (color: const Color(0xFFFFF176), emoji: '🍿');
  }
  return (color: const Color(0xFFCFD8DC), emoji: '🛍️');
}

// ─── Sectioned view (supermarket style — grid 2 colunas por secção) ───────────

class _SectionedView extends StatelessWidget {
  const _SectionedView({
    required this.grouped,
    required this.isFruitCategory,
    required this.isPartnerStore,
  });

  final Map<String, List<PartnerProduct>> grouped;
  final bool Function(String) isFruitCategory;
  final bool isPartnerStore;

  @override
  Widget build(BuildContext context) {
    final restaurantStore = context.watch<RestaurantStore>();
    final sections = grouped.entries.toList();
    final slivers = <Widget>[];

    for (var index = 0; index < sections.length; index++) {
      final category = sections[index].key;
      final items = sections[index].value;
      final showPerKg = isFruitCategory(category);
      final style = _categoryStyle(category);
      final heroPhoto = items
          .firstWhere(
            (p) => p.photoUrl.isNotEmpty,
            orElse: () => items.first,
          )
          .photoUrl;

      final noVariants = <PartnerProduct>[];
      final withVariants = <PartnerProduct>[];
      for (final p in items) {
        if (restaurantStore.variantsForProduct(p.id).isNotEmpty) {
          withVariants.add(p);
        } else {
          noVariants.add(p);
        }
      }

      slivers.add(
        SliverToBoxAdapter(
          child: _SectionHeader(
            category: category,
            count: items.length,
            style: style,
            heroPhoto: heroPhoto,
          ),
        ),
      );

      if (noVariants.isNotEmpty) {
        slivers.add(
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            sliver: SliverGrid(
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 2,
                mainAxisSpacing: 12,
                crossAxisSpacing: 12,
                childAspectRatio: 3 / 4,
              ),
              delegate: SliverChildBuilderDelegate(
                (context, i) => _BoraProductCardTile(
                  product: noVariants[i],
                  isPartnerStore: isPartnerStore,
                ),
                childCount: noVariants.length,
              ),
            ),
          ),
        );
      }

      if (withVariants.isNotEmpty) {
        slivers.add(
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            sliver: SliverList(
              delegate: SliverChildBuilderDelegate(
                (context, i) => Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: _ProductCard(
                    product: withVariants[i],
                    showPerKg: showPerKg,
                    isPartnerStore: isPartnerStore,
                  ),
                ),
                childCount: withVariants.length,
              ),
            ),
          ),
        );
      }

      if (index < sections.length - 1) {
        slivers.add(
          const SliverToBoxAdapter(
            child: Padding(
              padding: EdgeInsets.symmetric(vertical: 8),
              child: Divider(height: 1, thickness: 1, indent: 16, endIndent: 16),
            ),
          ),
        );
      }
    }

    slivers.add(const SliverToBoxAdapter(child: SizedBox(height: 16)));

    return CustomScrollView(
      physics: const BouncingScrollPhysics(),
      slivers: slivers,
    );
  }
}

// ─── Flat grid view (uma categoria seleccionada) ──────────────────────────────

class _FlatGridView extends StatelessWidget {
  const _FlatGridView({
    required this.products,
    required this.showPerKg,
    required this.isPartnerStore,
  });

  final List<PartnerProduct> products;
  final bool showPerKg;
  final bool isPartnerStore;

  @override
  Widget build(BuildContext context) {
    final restaurantStore = context.watch<RestaurantStore>();
    final noVariants = <PartnerProduct>[];
    final withVariants = <PartnerProduct>[];
    for (final p in products) {
      if (restaurantStore.variantsForProduct(p.id).isNotEmpty) {
        withVariants.add(p);
      } else {
        noVariants.add(p);
      }
    }

    return CustomScrollView(
      physics: const BouncingScrollPhysics(),
      slivers: [
        if (noVariants.isNotEmpty)
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            sliver: SliverGrid(
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 2,
                mainAxisSpacing: 12,
                crossAxisSpacing: 12,
                childAspectRatio: 3 / 4,
              ),
              delegate: SliverChildBuilderDelegate(
                (context, i) => _BoraProductCardTile(
                  product: noVariants[i],
                  isPartnerStore: isPartnerStore,
                ),
                childCount: noVariants.length,
              ),
            ),
          ),
        if (withVariants.isNotEmpty)
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
            sliver: SliverList(
              delegate: SliverChildBuilderDelegate(
                (context, i) => Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: _ProductCard(
                    product: withVariants[i],
                    showPerKg: showPerKg,
                    isPartnerStore: isPartnerStore,
                  ),
                ),
                childCount: withVariants.length,
              ),
            ),
          ),
      ],
    );
  }
}

// ─── Section header (used by _SectionedView) ──────────────────────────────────

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({
    required this.category,
    required this.count,
    required this.style,
    required this.heroPhoto,
  });

  final String category;
  final int count;
  final ({Color color, String emoji}) style;
  final String heroPhoto;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: Stack(
          children: [
            Container(
              width: double.infinity,
              height: 56,
              color: style.color.withValues(alpha: 0.35),
            ),
            if (heroPhoto.isNotEmpty)
              Positioned.fill(
                child: Image.network(
                  heroPhoto,
                  fit: BoxFit.cover,
                  opacity: const AlwaysStoppedAnimation(0.12),
                  errorBuilder: (_, __, ___) => const SizedBox.shrink(),
                ),
              ),
            SizedBox(
              height: 56,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 14),
                child: Row(
                  children: [
                    Text(style.emoji,
                        style: const TextStyle(fontSize: 22)),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        category,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: Colors.black87,
                        ),
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        '$count ${count == 1 ? 'produto' : 'produtos'}',
                        style: const TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: Colors.black54),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Tile wrapper que liga BoraProductCard a CartStore + FavoriteStore ────────

class _BoraProductCardTile extends StatelessWidget {
  const _BoraProductCardTile({
    required this.product,
    required this.isPartnerStore,
  });

  final PartnerProduct product;
  final bool isPartnerStore;

  @override
  Widget build(BuildContext context) {
    final favoriteStore = context.watch<FavoriteStore>();
    final isFav = favoriteStore.isFavorite(product.id);

    return BoraProductCard(
      product: product,
      // B1 (2026-06-11): preço exibido = preço cobrado. A DB tem o preço BASE
      // do site oficial (a nota de 2026-05-21 estava errada — provado pelo
      // pedido 80ba3a2e); o markup não-parceiro aplica-se em runtime.
      displayPrice: PricingService.applyMarkup(product.price, isPartnerStore),
      isFavorite: isFav,
      onFavoriteToggle: () => favoriteStore.toggle(product.id),
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => ProductDetailScreen(
            product: product,
            isPartnerStore: isPartnerStore,
          ),
        ),
      ),
      onAdd: () {
        if (product.price <= 0) return;
        context.read<CartStore>().addItem(CartItem(
              productId: product.id,
              name: product.name,
              price: PricingService.applyMarkup(product.price, isPartnerStore),
              basePrice: product.price,
            ));
        showAddedToCartSnack(context, '${product.name} no carrinho');
      },
    );
  }
}

// ─── Product card ──────────────────────────────────────────────────────────────

class _ProductCard extends StatefulWidget {
  const _ProductCard({
    required this.product,
    required this.showPerKg,
    required this.isPartnerStore,
  });

  final PartnerProduct product;
  final bool showPerKg;
  final bool isPartnerStore;

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
          builder: (_) => ProductDetailScreen(
            product: widget.product,
            isPartnerStore: widget.isPartnerStore,
          ),
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
                // ── Product image + name + favorite ───────────────────────
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _ProductThumbnail(
                      photoUrl: widget.product.photoUrl,
                      category: widget.product.category,
                    ),
                    const SizedBox(width: 10),
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
                              label: 'Mais vendido', color: Colors.orange),
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
                    style: TextStyle(fontSize: 12, color: Colors.grey.shade500),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
                // ── Base price (no variants) ───────────────────────────────
                if (variants.isEmpty) ...[
                  const SizedBox(height: 8),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        widget.product.price > 0
                            // B1: exibido = cobrado (markup runtime não-parceiro).
                            ? '€${PricingService.applyMarkup(widget.product.price, widget.isPartnerStore).toStringAsFixed(2)}'
                            : 'Preço indisponível',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 15,
                          color: widget.product.price > 0
                              ? primaryColor
                              : Colors.grey.shade500,
                        ),
                      ),
                      _QtyButton(
                        icon: Icons.add,
                        color: primaryColor,
                        semanticId: 'btn_add_carrinho',
                        onTap: () {
                          if (widget.product.price <= 0) return;
                          context.read<CartStore>().addItem(CartItem(
                                productId: widget.product.id,
                                name: widget.product.name,
                                price: PricingService.applyMarkup(
                                    widget.product.price,
                                    widget.isPartnerStore),
                                basePrice: widget.product.price,
                              ));
                          showAddedToCartSnack(
                              context, '${widget.product.name} no carrinho');
                        },
                      ),
                    ],
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
                        productPhotoUrl: widget.product.photoUrl,
                        showPerKg: widget.showPerKg,
                        cartStore: cartStore,
                        primaryColor: primaryColor,
                        showCheapestBadge: showCheapest,
                        showPremiumBadge: showPremium,
                        isPartnerStore: widget.isPartnerStore,
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
    required this.productPhotoUrl,
    required this.showPerKg,
    required this.cartStore,
    required this.primaryColor,
    required this.showCheapestBadge,
    required this.showPremiumBadge,
    required this.isPartnerStore,
  });

  final ProductVariant variant;
  final String productName;
  final String productPhotoUrl;
  final bool showPerKg;
  final CartStore cartStore;
  final Color primaryColor;
  final bool showCheapestBadge;
  final bool showPremiumBadge;
  final bool isPartnerStore;

  // Sessão 4C: ProductVariant.id é UUID válido — usar directamente.
  // Embeber o nome do produto criava productId que falhava lookup na RPC.
  String get _variantKey => variant.id;

  void _addToCart(BuildContext context) {
    // B1 (2026-06-11): variantes podem não existir em `products` — o servidor
    // usa unit_price (basePrice) como fallback e aplica o markup à soma.
    context.read<CartStore>().addItem(CartItem(
          productId: _variantKey,
          name: '$productName (${variant.brandName})',
          price: PricingService.applyMarkup(variant.price, isPartnerStore),
          basePrice: variant.price,
        ));
    showAddedToCartSnack(
      context,
      '${variant.brandName} no carrinho',
      onView: () => Navigator.push(
          context, MaterialPageRoute(builder: (_) => const CartScreen())),
    );
  }

  @override
  Widget build(BuildContext context) {
    final qty = cartStore.items
        .where((i) => i.productId == _variantKey)
        .fold<int>(0, (sum, i) => sum + i.quantity);
    // B1 (2026-06-11): exibido = cobrado. A DB tem preço BASE (a nota de
    // 2026-05-21 estava errada); markup não-parceiro aplicado em runtime.
    final markedPrice =
        PricingService.applyMarkup(variant.price, isPartnerStore);
    final priceLabel = showPerKg
        ? '€${markedPrice.toStringAsFixed(2)}/kg'
        : '€${markedPrice.toStringAsFixed(2)}';

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
                  child: productPhotoUrl.isNotEmpty
                      ? Image.network(
                          productPhotoUrl,
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) => _PlaceholderImage(),
                        )
                      : _PlaceholderImage(),
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
                  semanticId: 'btn_add_carrinho',
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

// ─── Product thumbnail ─────────────────────────────────────────────────────────

class _ProductThumbnail extends StatelessWidget {
  const _ProductThumbnail({required this.photoUrl, required this.category});

  final String photoUrl;
  final String category;

  IconData get _fallbackIcon {
    final cat = category.toLowerCase();
    if (cat.contains('bebé') || cat.contains('bebe') || cat.contains('baby')) {
      return Icons.child_care;
    }
    if (cat.contains('frut') ||
        cat.contains('legum') ||
        cat.contains('vegeta')) {
      return Icons.eco;
    }
    if (cat.contains('carne') ||
        cat.contains('peixe') ||
        cat.contains('meat')) {
      return Icons.set_meal;
    }
    if (cat.contains('bebida') || cat.contains('drink')) {
      return Icons.local_drink;
    }
    if (cat.contains('limpeza') || cat.contains('higiene')) {
      return Icons.clean_hands;
    }
    if (cat.contains('farmácia') ||
        cat.contains('saúde') ||
        cat.contains('health')) {
      return Icons.medical_services_outlined;
    }
    return Icons.shopping_bag_outlined;
  }

  @override
  Widget build(BuildContext context) {
    if (photoUrl.isNotEmpty) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(10),
        child: SizedBox(
          width: 60,
          height: 60,
          child: Image.network(
            photoUrl,
            fit: BoxFit.cover,
            errorBuilder: (_, __, ___) => _iconBox(),
          ),
        ),
      );
    }
    return _iconBox();
  }

  Widget _iconBox() {
    return Container(
      width: 60,
      height: 60,
      decoration: BoxDecoration(
        color: const Color(0xFFF0F0F0),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Icon(_fallbackIcon, size: 30, color: Colors.grey.shade400),
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
      {required this.icon,
      required this.color,
      required this.onTap,
      this.semanticId});

  final IconData icon;
  final Color color;
  final VoidCallback onTap;
  // Identificador estável para o botão pequeno de "+" (adicionar ao carrinho).
  // O E2E toca-o por id (btn_add_carrinho) em vez de adivinhar a coordenada do
  // ícone sem texto no canto do card — ver flows/cliente/delivery-mercado-cash.yaml.
  final String? semanticId;

  @override
  Widget build(BuildContext context) {
    final button = InkWell(
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
    return semanticId == null
        ? button
        : Semantics(identifier: semanticId, button: true, child: button);
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

// ─── RPC-powered suggestions (sections + products) ─────────────────────────────

class _SuggestionsPanel extends StatelessWidget {
  const _SuggestionsPanel({
    required this.rpcRows,
    required this.rpcLoading,
    required this.localFallback,
    required this.loadedProducts,
    required this.onPickSection,
    required this.onPickProduct,
    required this.isPartnerStore,
  });

  final List<Map<String, dynamic>> rpcRows;
  final bool rpcLoading;
  final List<PartnerProduct> localFallback;
  final List<PartnerProduct> loadedProducts;
  final ValueChanged<String> onPickSection;
  final ValueChanged<PartnerProduct> onPickProduct;
  final bool isPartnerStore;

  PartnerProduct? _resolveProduct(Map<String, dynamic> row) {
    final id = (row['id'] ?? '').toString();
    if (id.isEmpty) return null;
    for (final p in loadedProducts) {
      if (p.id == id) return p;
    }
    // Synthesize a lightweight product if the RPC returned an id not in memory.
    return PartnerProduct(
      id: id,
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
    final sections = rpcRows
        .where((r) => (r['result_type'] ?? '') == 'section')
        .toList();
    final products = rpcRows
        .where((r) => (r['result_type'] ?? '') == 'product')
        .toList();

    final hasRpc = sections.isNotEmpty || products.isNotEmpty;

    if (rpcLoading && !hasRpc) {
      return Container(
        color: Colors.white,
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: const Center(
          child: SizedBox(
            width: 20,
            height: 20,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        ),
      );
    }

    if (!hasRpc && localFallback.isEmpty) {
      return const SizedBox.shrink();
    }

    return Container(
      color: Colors.white,
      child: ListView(
        padding: const EdgeInsets.symmetric(vertical: 4),
        children: [
          for (final s in sections)
            ListTile(
              dense: true,
              leading: const Icon(Icons.folder_outlined, size: 22),
              title: Text(
                (s['name'] ?? s['category_root'] ?? '').toString(),
                style:
                    const TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
              ),
              subtitle: const Text('Categoria',
                  style: TextStyle(fontSize: 11, color: Colors.grey)),
              onTap: () => onPickSection(
                  (s['category_root'] ?? s['name'] ?? '').toString()),
            ),
          if (sections.isNotEmpty && products.isNotEmpty)
            const Divider(height: 1),
          for (final r in products)
            Builder(builder: (_) {
              final p = _resolveProduct(r);
              if (p == null) return const SizedBox.shrink();
              return ListTile(
                dense: true,
                leading: ClipRRect(
                  borderRadius: BorderRadius.circular(6),
                  child: p.photoUrl.isNotEmpty
                      ? Image.network(p.photoUrl,
                          width: 36, height: 36, fit: BoxFit.cover)
                      : Container(
                          width: 36,
                          height: 36,
                          color: Colors.grey.shade200,
                          child: const Icon(
                              Icons.image_not_supported_outlined,
                              size: 18,
                              color: Colors.grey),
                        ),
                ),
                title: Text(p.name,
                    style: const TextStyle(
                        fontSize: 13, fontWeight: FontWeight.w600)),
                subtitle: Text(
                    // B1: exibido = cobrado (markup runtime não-parceiro).
                    '€${PricingService.applyMarkup(p.price, isPartnerStore).toStringAsFixed(2)}',
                    style: const TextStyle(fontSize: 12)),
                onTap: () => onPickProduct(p),
              );
            }),
          // Local fallback when RPC has no rows yet (e.g. first keystrokes).
          if (!hasRpc)
            for (final p in localFallback)
              ListTile(
                dense: true,
                leading: ClipRRect(
                  borderRadius: BorderRadius.circular(6),
                  child: p.photoUrl.isNotEmpty
                      ? Image.network(p.photoUrl,
                          width: 36, height: 36, fit: BoxFit.cover)
                      : Container(
                          width: 36,
                          height: 36,
                          color: Colors.grey.shade200,
                          child: const Icon(
                              Icons.image_not_supported_outlined,
                              size: 18,
                              color: Colors.grey),
                        ),
                ),
                title: Text(p.name,
                    style: const TextStyle(
                        fontSize: 13, fontWeight: FontWeight.w600)),
                subtitle: Text(
                    // B1: exibido = cobrado (markup runtime não-parceiro).
                    '€${PricingService.applyMarkup(p.price, isPartnerStore).toStringAsFixed(2)}',
                    style: const TextStyle(fontSize: 12)),
                onTap: () => onPickProduct(p),
              ),
        ],
      ),
    );
  }
}
