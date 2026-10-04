import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../config/app_colors.dart';
import '../../stores/restaurant_store.dart';

/// Banner da loja em pausa (04/10/2026): "Fechada temporariamente — volta às
/// HH:MM". Lê a loja ao vivo no [RestaurantStore] (o parceiro pode tirar a
/// pausa com o cliente já dentro da loja). Sem pausa, não ocupa espaço.
class BannerPausaLoja extends StatelessWidget {
  const BannerPausaLoja({super.key, required this.restaurantId});

  final String restaurantId;

  @override
  Widget build(BuildContext context) {
    final loja = context.watch<RestaurantStore>().restaurantById(restaurantId);
    if (loja == null || !loja.emPausa()) return const SizedBox.shrink();
    return Container(
      width: double.infinity,
      color: AppColors.error.withValues(alpha: 0.08),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(
        children: [
          const Icon(Icons.pause_circle_outline,
              size: 18, color: AppColors.error),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              loja.statusLabel(),
              style: const TextStyle(
                fontWeight: FontWeight.w700,
                color: AppColors.error,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
