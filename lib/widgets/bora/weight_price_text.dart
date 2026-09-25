import 'package:flutter/material.dart';

import '../../l10n/tr.dart';
import '../../services/weight_portions.dart';

/// Preço de um produto no cartão/lista. Produto normal: "€1,14". Produto ao
/// peso: "desde €1,14" (a porção de 200 g) e, por baixo, em pequeno, o preço
/// ao cliente por quilo ("€5,70/kg") — o que ele paga mesmo, não o balcão.
///
/// [displayPrice] é o preço já exibido/cobrado (com markup runtime quando a
/// loja não é parceira), para a regra "exibido = cobrado" continuar a valer.
class WeightPriceText extends StatelessWidget {
  const WeightPriceText({
    super.key,
    required this.displayPrice,
    required this.soldByWeight,
    this.style,
    this.perKgStyle,
    this.unavailableLabel,
  });

  final double displayPrice;
  final bool soldByWeight;
  final TextStyle? style;
  final TextStyle? perKgStyle;

  /// Texto quando não há preço (null = "€0,00" como antes).
  final String? unavailableLabel;

  static String priceLabel(double displayPrice, bool soldByWeight) {
    final base = '€${displayPrice.toStringAsFixed(2)}';
    return soldByWeight ? 'desde {0}'.trArgs([base]) : base;
  }

  static String perKgLabel(double displayPrice) =>
      '€${WeightPortions.clientPerKgFromBase(displayPrice).toStringAsFixed(2)}/kg';

  @override
  Widget build(BuildContext context) {
    if (displayPrice <= 0 && unavailableLabel != null) {
      return Text(unavailableLabel!, style: style);
    }
    if (!soldByWeight) {
      return Text(priceLabel(displayPrice, false), style: style);
    }
    final small = perKgStyle ??
        TextStyle(
          fontSize: (style?.fontSize ?? 13) - 2,
          fontWeight: FontWeight.w400,
          color: Colors.grey.shade600,
        );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(priceLabel(displayPrice, true), style: style),
        Text(perKgLabel(displayPrice), style: small),
      ],
    );
  }
}
