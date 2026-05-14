import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../config/app_colors.dart';
import '../config/app_spacing.dart';
import '../models/business_view_models.dart';
import '../models/order_service_type.dart';
import '../models/restaurant_model.dart';
import '../stores/cart_store.dart';
import '../widgets/bora/bora_screen_app_bar.dart';
import '../widgets/bora/bora_tile_card.dart';
import 'client/reservation/reservation_availability_screen.dart';
import 'restaurant_menu_screen.dart';

/// BUG #9+10 (2026-05-13) + D1 (2026-05-14) — ecrã intermédio com 1-3 cartões
/// antes do cardápio.
///
/// Apresentado entre a lista de restaurantes e o `RestaurantMenuScreen`:
/// só para `isPartner==true && (reservationsEnabled || takeawayEnabled)`.
///
/// Cartões (condicionais individualmente):
///   1. Entrega         → serviceType=restaurant + RestaurantMenuScreen (sempre visível)
///   2. Ir buscar       → serviceType=takeaway  + RestaurantMenuScreen (se takeawayEnabled)
///   3. Reservar mesa   → ReservationAvailabilityScreen (se reservationsEnabled)
///
/// R5 (2026-05-14): Ao chegar via este ecrã, `cameFromOptions=true` é
/// propagado ao menu/cart para esconder o switch "Ir buscar" no cart_screen
/// (evita UX ambíguo — para trocar modo, cliente volta atrás).
class RestaurantOptionsScreen extends StatelessWidget {
  const RestaurantOptionsScreen({
    super.key,
    required this.business,
    required this.restaurant,
    required this.restaurantId,
  });

  final RestaurantModel business;
  final Restaurant restaurant;
  final String restaurantId;

  void _openMenu(BuildContext context, OrderServiceType type) {
    context.read<CartStore>().setServiceTypeFromOption(type);
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => RestaurantMenuScreen(
          restaurant: restaurant,
          restaurantId: restaurantId,
        ),
      ),
    );
  }

  void _openReservation(BuildContext context) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ReservationAvailabilityScreen(
          restaurantId: restaurantId,
          restaurantName: business.name,
          restaurantPhotoUrl: business.photoUrl,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: BoraScreenAppBar(title: business.name),
      body: ListView(
        padding: const EdgeInsets.all(Spacing.lg),
        children: [
          Text(
            'Como queres fazer o pedido?',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: Colors.grey.shade800,
            ),
          ),
          const SizedBox(height: Spacing.lg),
          // Cartão "Entrega" — sempre presente (todos os parceiros aceitam
          // delivery enquanto isPartner=true).
          BoraTileCard(
            label: 'Entrega',
            gradient: AppColors.tileRestaurants,
            iconData: Icons.delivery_dining,
            onTap: () => _openMenu(context, OrderServiceType.restaurant),
          ),
          // D1 — "Ir buscar" só se restaurante aceita takeaway.
          if (business.takeawayEnabled) ...[
            const SizedBox(height: Spacing.md),
            BoraTileCard(
              label: 'Ir buscar',
              gradient: AppColors.tileCarryGroceries,
              iconData: Icons.shopping_bag_outlined,
              onTap: () => _openMenu(context, OrderServiceType.takeaway),
            ),
          ],
          // D1 — "Reservar mesa" só se restaurante aceita reservas.
          if (business.reservationsEnabled) ...[
            const SizedBox(height: Spacing.md),
            BoraTileCard(
              label: 'Reservar mesa',
              gradient: AppColors.tileReserveTable,
              iconData: Icons.event_seat_outlined,
              onTap: () => _openReservation(context),
            ),
          ],
        ],
      ),
    );
  }
}
