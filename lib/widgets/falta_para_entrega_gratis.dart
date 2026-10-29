import 'package:flutter/material.dart';

import '../config/app_colors.dart';
import '../config/app_spacing.dart';
import '../l10n/tr.dart';

/// "Faltam 4,50 € para a entrega grátis" — a linha que a Glovo e a Uber põem
/// no carrinho e que faz o cliente juntar mais um item. Aparece no carrinho e
/// no ecrã de pagamento (28/10/2026: também nas lojas parceiras).
class FaltaParaEntregaGratis extends StatelessWidget {
  const FaltaParaEntregaGratis({super.key, required this.falta});

  /// Quanto falta, em euros (já maior que zero).
  final double falta;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: Spacing.xs),
      child: Row(
        children: [
          const Icon(Icons.add_shopping_cart,
              size: 16, color: AppColors.primary),
          const SizedBox(width: Spacing.xs),
          Expanded(
            child: Text(
              'Faltam {0} € para a entrega grátis'
                  .trArgs([falta.toStringAsFixed(2).replaceAll('.', ',')]),
              style: const TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
                color: AppColors.primary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
