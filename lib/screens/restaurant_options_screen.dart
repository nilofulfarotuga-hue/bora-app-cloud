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
import '../widgets/bora/coming_soon.dart';
import 'client/reservation/reservation_availability_screen.dart';
import 'restaurant_menu_screen.dart';

import '../l10n/tr.dart';

/// BUG #9+10 (2026-05-13) + D1 (2026-05-14) — ecrã intermédio com 3 cartões
/// antes do cardápio.
///
/// Apresentado entre a lista de restaurantes e o `RestaurantMenuScreen`:
/// sempre que `isPartner==true` (ver `restaurants_screen.dart`).
///
/// Cartões — SEMPRE OS 3 (BUG 2, 2026-07-17): os serviços desligados não
/// desaparecem, aparecem apagados (opacidade + toque bloqueado) com a
/// etiqueta "Não disponível", para o parceiro perceber que pode ativá-los.
///   1. Entrega         → serviceType=restaurant + RestaurantMenuScreen (sempre ativo)
///   2. Ir buscar       → serviceType=takeaway  + RestaurantMenuScreen (ativo se takeawayEnabled)
///   3. Reservar mesa   → ReservationAvailabilityScreen (ativo se reservationsEnabled)
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
    // "Em breve": a reserva cobra €3 de sinal — não entrar no fluxo.
    if (business.comingSoon) {
      showComingSoonBlockedSnackBar(context);
      return;
    }
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
      body: Column(
        children: [
          // "Em breve": banner fixo por baixo do cabeçalho. As opções e o
          // cardápio continuam navegáveis — só não fecham pedido.
          if (business.comingSoon)
            ComingSoonBanner(text: business.comingSoonLabel),
          Expanded(
            child: ListView(
        padding: const EdgeInsets.all(Spacing.lg),
        children: [
          Text(
            'Como queres fazer o pedido?'.tr,
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: Colors.grey.shade800,
            ),
          ),
          const SizedBox(height: Spacing.lg),
          // Cartão "Entrega" — sempre presente e ativo (todos os parceiros
          // aceitam delivery enquanto isPartner=true).
          BoraTileCard.image(
            label: 'Entrega'.tr,
            gradient: AppColors.tileRestaurants,
            imageAsset: 'assets/categories/btn_entrega.png',
            onTap: () => _openMenu(context, OrderServiceType.restaurant),
          ),
          const SizedBox(height: Spacing.md),
          // BUG 2 (2026-07-17): "Ir buscar" nunca desaparece — fica apagado
          // e sem toque quando o parceiro ainda não ativou takeaway.
          _buildOptionCard(
            label: 'Ir buscar'.tr,
            gradient: AppColors.tileCarryGroceries,
            imageAsset: 'assets/categories/btn_buscar.png',
            enabled: business.takeawayEnabled,
            onTap: () => _openMenu(context, OrderServiceType.takeaway),
          ),
          const SizedBox(height: Spacing.md),
          // BUG 2 (2026-07-17): idem para "Reservar mesa".
          _buildOptionCard(
            label: 'Reservar mesa'.tr,
            gradient: AppColors.tileReserveTable,
            imageAsset: 'assets/categories/btn_reservar.png',
            enabled: business.reservationsEnabled,
            onTap: () => _openReservation(context),
          ),
        ],
            ),
          ),
        ],
      ),
    );
  }

  /// Cartão sempre visível: quando `enabled=false`, fica apagado (opacidade
  /// 0.4) e bloqueado ao toque (`IgnorePointer`), com etiqueta "Não
  /// disponível" — nunca desaparece do ecrã (BUG 2, 2026-07-17).
  Widget _buildOptionCard({
    required String label,
    required Gradient gradient,
    required String imageAsset,
    required bool enabled,
    required VoidCallback onTap,
  }) {
    final card = BoraTileCard.image(
      label: label,
      gradient: gradient,
      imageAsset: imageAsset,
      onTap: onTap,
    );
    if (enabled) return card;
    return Stack(
      children: [
        Opacity(opacity: 0.4, child: IgnorePointer(child: card)),
        Positioned(
          top: 8,
          right: 8,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: Colors.black54,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              'Não disponível'.tr,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 11,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ),
      ],
    );
  }
}
