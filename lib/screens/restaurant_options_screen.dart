import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../config/app_colors.dart';
import '../config/app_spacing.dart';
import '../models/business_view_models.dart';
import '../models/restaurant_model.dart';
import '../stores/cart_store.dart';
import '../widgets/bora/bora_screen_app_bar.dart';
import '../widgets/bora/bora_tile_card.dart';
import 'client/reservation/reservation_availability_screen.dart';
import 'restaurant_menu_screen.dart';

/// BUG #9+10 (2026-05-13) — ecrã intermédio com 3 opções antes do cardápio
/// para restaurantes parceiros com reservas activas.
///
/// Apresentado entre a lista de restaurantes e o `RestaurantMenuScreen`:
/// só para `isPartner == true && reservationsEnabled == true`. Para outros
/// parceiros e não-parceiros, `restaurants_screen.dart` continua a navegar
/// directamente ao menu.
///
/// Cartões (`BoraTileCard`):
///   1. Entrega          → setTakeaway(false) + RestaurantMenuScreen
///   2. Ir buscar        → setTakeaway(true)  + RestaurantMenuScreen
///   3. Reservar mesa    → ReservationAvailabilityScreen
///
/// O switch "Ir buscar" em `cart_screen.dart` continua activo e permite
/// override pelo cliente (Q14, confirmado pelo Danilo).
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

  void _openMenu(BuildContext context, {required bool takeaway}) {
    context.read<CartStore>().setTakeaway(takeaway);
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
          BoraTileCard(
            label: 'Entrega',
            gradient: AppColors.tileRestaurants,
            iconData: Icons.delivery_dining,
            onTap: () => _openMenu(context, takeaway: false),
          ),
          const SizedBox(height: Spacing.md),
          BoraTileCard(
            label: 'Ir buscar',
            gradient: AppColors.tileCarryGroceries,
            iconData: Icons.shopping_bag_outlined,
            onTap: () => _openMenu(context, takeaway: true),
          ),
          const SizedBox(height: Spacing.md),
          BoraTileCard(
            label: 'Reservar mesa',
            gradient: AppColors.tileReserveTable,
            iconData: Icons.event_seat_outlined,
            onTap: () => _openReservation(context),
          ),
        ],
      ),
    );
  }
}
