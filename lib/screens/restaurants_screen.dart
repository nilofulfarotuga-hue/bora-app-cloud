import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../config/app_colors.dart';
import '../config/app_spacing.dart';
import '../models/order_service_type.dart';
import '../models/restaurant_model.dart';
import '../services/order_eta_service.dart';
import '../services/pricing_service.dart';
import '../stores/cart_store.dart';
import '../stores/favorite_store.dart';
import '../stores/restaurant_store.dart';
import '../utils/business_mapper.dart';
import '../widgets/bora/bora_screen_app_bar.dart';
import '../widgets/bora_support_fab.dart';
import 'reservation_flow_screen.dart';
import 'restaurant_menu_screen.dart';
import 'restaurant_options_screen.dart';

class RestaurantsScreen extends StatelessWidget {
  const RestaurantsScreen({super.key, this.reservationsOnly = false});

  final bool reservationsOnly;

  @override
  Widget build(BuildContext context) {
    final restaurantStore = context.watch<RestaurantStore>();
    final restaurants = restaurantStore.restaurants
        .where((business) =>
            business.category == BusinessCategory.restaurant &&
            (!reservationsOnly ||
                (business.isPartner && business.reservationsEnabled)))
        .toList()
      ..sort((a, b) {
        // Open ones first, then alphabetical.
        final aOpen = a.isOpenNow();
        final bOpen = b.isOpenNow();
        if (aOpen != bOpen) return aOpen ? -1 : 1;
        return a.name.compareTo(b.name);
      });

    return Scaffold(
      backgroundColor: AppColors.surface,
      floatingActionButton: const BoraSupportFab(),
      appBar: BoraScreenAppBar(
        title: reservationsOnly ? 'Reservar Mesa' : 'Restaurantes',
      ),
      body: restaurants.isEmpty
          ? const _EmptyState()
          : ListView.builder(
              padding: const EdgeInsets.fromLTRB(
                Spacing.lg, Spacing.md, Spacing.lg, Spacing.xxl),
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

  Future<void> _openRestaurant(
    BuildContext context,
    RestaurantStore restaurantStore,
    RestaurantModel business,
  ) async {
    // Closed restaurants cannot receive orders.
    if (!business.isOpenNow() && !reservationsOnly) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(business.statusLabel()),
          duration: const Duration(seconds: 3),
        ),
      );
      return;
    }

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

    // BUG #6 (2026-05-13) — se há carrinho activo de OUTRA loja, pedir
    // confirmação antes de descartar.  configureSession() ainda tem o
    // silent-clear como defesa em profundidade.
    final cart = context.read<CartStore>();
    final differentVendor = cart.items.isNotEmpty &&
        cart.vendorName != null &&
        cart.vendorName != business.name;
    if (differentVendor) {
      final confirm = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Carrinho activo'),
          content: Text(
            'Tens itens no carrinho de ${cart.vendorName}. '
            'Queres cancelar e começar novo pedido em ${business.name}?',
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

    // Prefer the restaurant's real coordinates (now present in DB for
    // non-partners too) so distance_km reflects the actual pickup→dropoff
    // route. Fallback to the client's delivery location if missing.
    final pickupLocation = business.location ?? cart.deliveryLocation;

    cart.configureSession(
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

    // BUG 3 (2026-05-15) — se cliente veio do fluxo "Reservar Mesa", saltar
    // o ecrã de opções e ir directamente à reserva.
    // ReservationFlowScreen espera RestaurantModel (business), não o adaptador
    // de menu Restaurant (variable `restaurant` acima).
    if (reservationsOnly &&
        business.isPartner &&
        business.reservationsEnabled) {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => ReservationFlowScreen(restaurant: business),
        ),
      );
      return;
    }

    // BUG #9+10 (2026-05-13) + D1/D2 (2026-05-14) — mostra ecrã de opções
    // se houver pelo menos uma opção além do menu directo. Cartões são
    // condicionais individualmente em RestaurantOptionsScreen. Sem reservas
    // e sem takeaway → directo ao menu (menos cliques).
    final showOptions = business.isPartner &&
        (business.reservationsEnabled || business.takeawayEnabled);

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => showOptions
            ? RestaurantOptionsScreen(
                business: business,
                restaurant: restaurant,
                restaurantId: business.id,
              )
            : RestaurantMenuScreen(
                restaurant: restaurant,
                restaurantId: business.id,
              ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: Spacing.xxxl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.restaurant_outlined,
              size: 72,
              color: AppColors.textSecondary.withValues(alpha: 0.4),
            ),
            const SizedBox(height: Spacing.lg),
            const Text(
              'Nenhum restaurante disponível',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: AppColors.textPrimary,
              ),
            ),
            const SizedBox(height: Spacing.sm),
            const Text(
              'Volta mais tarde para ver os restaurantes da tua área.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 13,
                color: AppColors.textSecondary,
              ),
            ),
          ],
        ),
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
      padding: const EdgeInsets.only(bottom: Spacing.sm),
      child: Material(
        color: Colors.white,
        borderRadius: BorderRadius.circular(Radii.lg),
        child: InkWell(
          borderRadius: BorderRadius.circular(Radii.lg),
          onTap: onTap,
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(Radii.lg),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.05),
                  blurRadius: 6,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            padding: const EdgeInsets.symmetric(
                horizontal: Spacing.lg, vertical: Spacing.md),
            child: Row(
              children: [
                _RestaurantLogo(
                  photoUrl: business.photoUrl,
                  name: business.name,
                  isPartner: isPartner,
                ),
                const SizedBox(width: Spacing.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        business.name,
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          color: AppColors.textPrimary,
                        ),
                      ),
                      const SizedBox(height: Spacing.xs),
                      Row(
                        children: [
                          _OpenStatusBadge(business: business),
                        ],
                      ),
                      const SizedBox(height: 6),
                      _MetaRow(business: business),
                    ],
                  ),
                ),
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
                      color: isFav
                          ? Colors.redAccent
                          : AppColors.textSecondary.withValues(alpha: 0.5),
                    ),
                  ),
                ),
                const SizedBox(width: Spacing.sm),
                Icon(
                  Icons.arrow_forward_ios,
                  size: 14,
                  color: AppColors.textSecondary.withValues(alpha: 0.5),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _RestaurantLogo extends StatelessWidget {
  const _RestaurantLogo({
    required this.photoUrl,
    required this.name,
    required this.isPartner,
  });

  final String photoUrl;
  final String name;
  final bool isPartner;

  @override
  Widget build(BuildContext context) {
    final bgColor = isPartner
        ? AppColors.primary.withValues(alpha: 0.10)
        : AppColors.accent.withValues(alpha: 0.10);
    final textColor = isPartner ? AppColors.primary : AppColors.accent;
    final initial = name.isNotEmpty ? name[0].toUpperCase() : '?';

    if (photoUrl.isNotEmpty) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(Radii.md),
        child: SizedBox(
          width: 48,
          height: 48,
          child: CachedNetworkImage(
            imageUrl: photoUrl,
            fit: BoxFit.cover,
            fadeInDuration: const Duration(milliseconds: 120),
            placeholder: (_, __) => _InitialBox(
              initial: initial,
              bgColor: bgColor,
              textColor: textColor,
            ),
            errorWidget: (_, __, ___) => _InitialBox(
              initial: initial,
              bgColor: bgColor,
              textColor: textColor,
            ),
          ),
        ),
      );
    }

    return _InitialBox(
      initial: initial,
      bgColor: bgColor,
      textColor: textColor,
    );
  }
}

class _InitialBox extends StatelessWidget {
  const _InitialBox({
    required this.initial,
    required this.bgColor,
    required this.textColor,
  });

  final String initial;
  final Color bgColor;
  final Color textColor;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 48,
      height: 48,
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(Radii.md),
      ),
      alignment: Alignment.center,
      child: Text(
        initial,
        style: TextStyle(
          fontSize: 22,
          fontWeight: FontWeight.w800,
          color: textColor,
        ),
      ),
    );
  }
}


class _OpenStatusBadge extends StatelessWidget {
  const _OpenStatusBadge({required this.business});

  final RestaurantModel business;

  @override
  Widget build(BuildContext context) {
    final open = business.isOpenNow();
    final color = open ? Colors.green.shade700 : Colors.red.shade600;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(Radii.md),
        border: Border.all(color: color.withValues(alpha: 0.4), width: 1),
      ),
      child: Text(
        business.statusLabel(),
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          color: color,
        ),
      ),
    );
  }
}

class _MetaRow extends StatelessWidget {
  const _MetaRow({required this.business});

  final RestaurantModel business;

  @override
  Widget build(BuildContext context) {
    final cart = context.watch<CartStore>();
    final store = context.watch<RestaurantStore>();
    final client = cart.deliveryLocation;
    final pickup = business.location;
    final distanceKm =
        OrderEtaService.distanceKmBetween(client, pickup);
    final window = OrderEtaService.deliveryWindowMinutes(
      clientLocation: client,
      restaurantLocation: pickup,
    );
    final fee = distanceKm == null
        ? null
        : PricingService.estimatedDeliveryFee(
            distanceKm: distanceKm,
            isPartner: business.isPartner,
          );
    final rating = store.avgRatingFor(business.id);

    final chips = <Widget>[];
    if (window != null) {
      chips.add(_metaChip(
        icon: Icons.schedule,
        label: '${window.$1}-${window.$2} min',
      ));
    }
    if (distanceKm != null) {
      chips.add(_metaChip(
        icon: Icons.place_outlined,
        label: '${distanceKm.toStringAsFixed(1)} km',
      ));
    }
    if (fee != null) {
      chips.add(_metaChip(
        icon: Icons.delivery_dining,
        label: '€${fee.toStringAsFixed(2)}',
      ));
    }
    if (rating != null) {
      chips.add(_metaChip(
        icon: Icons.star_rounded,
        label: rating.toStringAsFixed(1),
        iconColor: Colors.amber.shade700,
      ));
    }

    if (chips.isEmpty) return const SizedBox.shrink();

    return Wrap(
      spacing: 10,
      runSpacing: 4,
      children: chips,
    );
  }

  Widget _metaChip({
    required IconData icon,
    required String label,
    Color? iconColor,
  }) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 13, color: iconColor ?? AppColors.textSecondary),
        const SizedBox(width: 3),
        Text(
          label,
          style: const TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: AppColors.textPrimary,
          ),
        ),
      ],
    );
  }
}
