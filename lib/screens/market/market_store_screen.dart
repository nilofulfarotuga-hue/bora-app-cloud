import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../config/app_colors.dart';
import '../../stores/cart_store.dart';
import '../../widgets/bora/bora_screen_app_bar.dart';
import '../../stores/restaurant_store.dart';
import '../../widgets/market/market_bottom_nav.dart';
import '../../widgets/market/market_categories_tab.dart';
import '../../widgets/market/market_reorder_tab.dart';
import '../../widgets/market/market_store_tab.dart';
import '../cart_screen.dart';

/// Host do interior do mercado — 3 tabs estilo Glovo:
///   0 → Loja (hero + stats + search + grid categorias + secções horizontais)
///   1 → Categorias (lista vertical)
///   2 → Pedir de novo (placeholder pós-launch)
///
/// Callers existentes (stores_screen.dart) não precisam de alterações —
/// StoreCategoriesScreen é agora um wrapper fino que delega para este widget.
class MarketStoreScreen extends StatefulWidget {
  const MarketStoreScreen({
    super.key,
    required this.restaurantId,
    required this.storeName,
    required this.isPartnerStore,
    this.initialTab = 0,
  });

  final String restaurantId;
  final String storeName;
  final bool isPartnerStore;

  /// 0 = Loja, 1 = Categorias, 2 = Pedir de novo.
  final int initialTab;

  @override
  State<MarketStoreScreen> createState() => _MarketStoreScreenState();
}

class _MarketStoreScreenState extends State<MarketStoreScreen> {
  late int _selectedTab;

  @override
  void initState() {
    super.initState();
    _selectedTab = widget.initialTab;
    // Hotfix (2026-06-12): carrega a loja INTEIRA ao abrir (full-load
    // on-demand, 1000/página). Os carrosséis por categoria e a tab Categorias
    // precisam de todas as categorias — preenchem progressivamente à medida
    // que as páginas chegam. Arranque continua sem carregar os 45k.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      context
          .read<RestaurantStore>()
          .loadFullStoreProducts(widget.restaurantId);
    });
  }

  @override
  Widget build(BuildContext context) {
    final restaurantStore = context.watch<RestaurantStore>();
    final cartStore = context.watch<CartStore>();

    // Localizar o RestaurantModel pelo ID.
    // Se não encontrado ainda (ex: loading), mostrar loader.
    final idx = restaurantStore.restaurants
        .indexWhere((r) => r.id == widget.restaurantId);
    final restaurant = idx != -1 ? restaurantStore.restaurants[idx] : null;

    if (restaurant == null) {
      return Scaffold(
        appBar: BoraScreenAppBar(title: widget.storeName),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      backgroundColor: const Color(0xFFF5F5F5),
      body: IndexedStack(
        index: _selectedTab,
        children: [
          MarketStoreTab(
            restaurant: restaurant,
            storeName: widget.storeName,
            isPartnerStore: widget.isPartnerStore,
          ),
          MarketCategoriesTab(
            restaurantId: widget.restaurantId,
            storeName: widget.storeName,
            isPartnerStore: widget.isPartnerStore,
          ),
          MarketReorderTab(
            storeName: widget.storeName,
            isPartnerStore: widget.isPartnerStore,
          ),
        ],
      ),
      bottomNavigationBar: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Botão flutuante "Ver carrinho" acima do bottom nav
          if (cartStore.items.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
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
                        fontWeight: FontWeight.w600, fontSize: 15),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 13),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14)),
                  ),
                ),
              ),
            ),
          MarketBottomNav(
            selectedIndex: _selectedTab,
            onTap: (i) => setState(() => _selectedTab = i),
          ),
        ],
      ),
    );
  }
}
