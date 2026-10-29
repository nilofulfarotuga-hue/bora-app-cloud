import 'package:flutter/material.dart';

import '../config/app_colors.dart';
import '../l10n/tr.dart';
import '../services/small_order_fee.dart';
import '../utils/euros.dart';

/// "Entrega grátis a partir de 30 €" na ficha da loja (28/10/2026).
///
/// Só aparece quando a loja tem o mínimo (`restaurants.free_delivery_min_cents`),
/// seja parceira (só sai a taxa base) ou não (sai a entrega toda). O número vem
/// da leitura que o carrinho já faz ao abrir a loja ([SmallOrderFeeService]);
/// quem desenha esta linha vive dentro de um ecrã que já observa o carrinho,
/// por isso reaparece sozinha quando a leitura chega.
class EntregaGratisDaLoja extends StatelessWidget {
  const EntregaGratisDaLoja({
    super.key,
    required this.restaurantId,
    this.padding = EdgeInsets.zero,
    this.fundo,
  });

  final String? restaurantId;
  final EdgeInsetsGeometry padding;
  final Color? fundo;

  /// "30 €" quando é redondo, "29,50 €" quando não.
  static String valorCurto(int cents) =>
      cents % 100 == 0 ? '${cents ~/ 100} €' : eur(cents / 100);

  @override
  Widget build(BuildContext context) {
    final cents = SmallOrderFeeService.entregaGratisMinCents(restaurantId);
    if (cents == null || cents <= 0) return const SizedBox.shrink();
    return Container(
      key: const Key('entrega_gratis_da_loja'),
      width: double.infinity,
      color: fundo,
      padding: padding,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.delivery_dining, size: 16, color: AppColors.primary),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              'Entrega grátis a partir de {0}'.trArgs([valorCurto(cents)]),
              style: const TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w700,
                color: AppColors.primary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
