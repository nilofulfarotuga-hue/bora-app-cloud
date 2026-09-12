import 'package:flutter/material.dart';

import '../config/app_colors.dart';

/// Valor com o preço antigo RISCADO ao lado — o gesto que a Uber e a Glovo
/// usam quando uma taxa desce (ordem do Danilo, 2026-09-08).
///
/// Fica assim: ~~€2.50~~ **€0.99** — o antigo a cinzento, riscado e mais
/// pequeno; o actual em verde Bora (#16A34A) e a negrito.
///
/// Sem [riscado] (ou com um risco que não seja maior que o valor actual),
/// desenha-se apenas o valor normal, com o estilo que o ecrã já usava — ou
/// seja, cair para o comportamento antigo não custa nada e é o estado seguro.
/// Nada de selos, percentagens ou contagens decrescentes: só o antes e o
/// depois.
class ValorComRisco extends StatelessWidget {
  const ValorComRisco({
    super.key,
    required this.valor,
    this.riscado,
    this.style,
  });

  /// O que o cliente paga hoje, em euros.
  final double valor;

  /// O que pagava antes, em euros. `null` (ou <= [valor]) = sem risco.
  final double? riscado;

  /// Estilo do ecrã que chama, para o valor normal continuar igual ao resto
  /// da coluna de preços.
  final TextStyle? style;

  static String _eur(double v) => '€${v.toStringAsFixed(2)}';

  @override
  Widget build(BuildContext context) {
    final antigo = riscado;
    if (antigo == null || antigo <= valor) {
      return Text(_eur(valor), style: style);
    }

    final base = style ?? const TextStyle(fontSize: 14);
    final tamanhoRiscado = ((base.fontSize ?? 14) - 2).clamp(9.0, 24.0);

    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.baseline,
      textBaseline: TextBaseline.alphabetic,
      children: [
        Text(
          _eur(antigo),
          style: base.copyWith(
            fontSize: tamanhoRiscado,
            fontWeight: FontWeight.w500,
            color: AppColors.textSecondary,
            decoration: TextDecoration.lineThrough,
            decorationColor: AppColors.textSecondary,
          ),
        ),
        const SizedBox(width: 6),
        Text(
          _eur(valor),
          style: base.copyWith(
            fontWeight: FontWeight.w800,
            color: AppColors.success, // verde Bora #16A34A
          ),
        ),
      ],
    );
  }
}
