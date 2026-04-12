import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/order_service_type.dart';
import '../models/restaurant_model.dart';
import '../stores/cart_store.dart';
import '../stores/favorite_store.dart';
import '../stores/restaurant_store.dart';
import '../utils/business_mapper.dart';
import 'restaurant_menu_screen.dart';

class RestaurantsScreen extends StatelessWidget {
  const RestaurantsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final restaurantStore = context.watch<RestaurantStore>();
    final restaurants = restaurantStore.restaurants
        .where((business) =>
            business.category == BusinessCategory.restaurant &&
            business.isOnline)
        .toList()
      ..sort((a, b) => a.name.compareTo(b.name));

    return Scaffold(
      backgroundColor: const Color(0xFFF5F5F5),
      appBar: AppBar(
        title: const Text(
          'Restaurantes',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        backgroundColor: Colors.white,
        foregroundColor: Colors.black87,
        elevation: 0,
      ),
      body: restaurants.isEmpty
          ? Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 32),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.restaurant_outlined,
                        size: 72, color: Colors.grey.shade300),
                    const SizedBox(height: 16),
                    Text(
                      'Nenhum restaurante disponível',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: Colors.grey.shade600,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Volte mais tarde para ver os restaurantes da sua área.',
                      textAlign: TextAlign.center,
                      style:
                          TextStyle(fontSize: 13, color: Colors.grey.shade400),
                    ),
                  ],
                ),
              ),
            )
          : ListView.builder(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
              itemCount: restaurants.length,
              itemBuilder: (context, index) {
                final business = restaurants[index];
                return _RestaurantTile(
                  business: business,
                  onTap: () =>
                      _openRestaurant(context, restaurantStore, business),
                );
              },
            ),
    );
  }

  void _openRestaurant(
    BuildContext context,
    RestaurantStore restaurantStore,
    RestaurantModel business,
  ) {
    // Partner restaurants must have a registered location in the DB.
    if (business.isPartner && business.location == null) {
      debugPrint(
        'RestaurantsScreen: BLOCKED — "${business.name}" has no coordinates.',
      );
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Restaurante sem localização definida. Contacte o suporte.',
          ),
          duration: Duration(seconds: 4),
        ),
      );
      return;
    }

    // Non-partner: driver shops near the client — use the delivery location
    // as pickup so distance is always realistic regardless of DB data.
    final pickupLocation = business.isPartner
        ? business.location
        : context.read<CartStore>().deliveryLocation;

    context.read<CartStore>().configureSession(
          serviceType: OrderServiceType.restaurant,
          isPartnerStore: business.isPartner,
          vendorName: business.name,
          pickupLocation: pickupLocation,
          pickupStreet: business.address,
          pickupCity: null,
          pickupPostalCode: null,
        );

    final restaurant = BusinessMapper.buildRestaurantMenu(
      restaurantStore: restaurantStore,
      business: business,
    );

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => RestaurantMenuScreen(restaurant: restaurant),
      ),
    );
  }
}

class _RestaurantTile extends StatelessWidget {
  const _RestaurantTile({required this.business, required this.onTap});

  final RestaurantModel business;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final isPartner = business.isPartner;
    final favorites = context.watch<FavoriteStore>();
    final favKey = 'restaurant_${business.name}';
    final isFav = favorites.isFavorite(favKey);

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Material(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: onTap,
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.05),
                  blurRadius: 6,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            child: Row(
              children: [
                // ── Icon ──────────────────────────────────────────────────
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: isPartner
                        ? Colors.green.shade50
                        : Colors.orange.shade50,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(
                    Icons.restaurant,
                    color: isPartner
                        ? Colors.green.shade600
                        : Colors.orange.shade600,
                  ),
                ),
                const SizedBox(width: 14),

                // ── Info ─────────────────────────────────────────────────
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        business.name,
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          color: Colors.black87,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          _PartnerBadge(isPartner: isPartner),
                        ],
                      ),
                    ],
                  ),
                ),

                // ── Favorite ─────────────────────────────────────────────
                GestureDetector(
                  onTap: () => favorites.toggle(favKey),
                  child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 200),
                    transitionBuilder: (child, anim) =>
                        ScaleTransition(scale: anim, child: child),
                    child: Icon(
                      isFav ? Icons.favorite : Icons.favorite_border,
                      key: ValueKey(isFav),
                      size: 22,
                      color: isFav ? Colors.red : Colors.grey.shade400,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Icon(Icons.arrow_forward_ios,
                    size: 14, color: Colors.grey.shade400),
              ],
            ),
          ),
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

