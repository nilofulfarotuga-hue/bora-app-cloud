import 'package:flutter/material.dart';

import '../../config/app_colors.dart';
import '../../models/tvde_ride.dart';

/// PART2 (2026-07-07) — badge de pagamento do lado do MOTORISTA no TVDE.
/// Espelha o padrão do estafeta do delivery ("COBRAR EM DINHEIRO: €X"):
/// hoje todas as corridas são em dinheiro, por isso o motorista tem de saber
/// QUANTO cobrar ao passageiro. Corrida coberta pelo plano → não cobra nada.
///
/// Antes do finish usa o valor ESTIMADO (`est_fare_cents`, mostrado com "~");
/// depois do finish usa o valor FINAL real (`final_fare_cents`).
class TvdePayBadge extends StatelessWidget {
  const TvdePayBadge({super.key, required this.ride, this.dense = false});

  final TvdeRide ride;

  /// Versão compacta (ex.: cartão de oferta), sem fundo, só a linha.
  final bool dense;

  @override
  Widget build(BuildContext context) {
    // 3 estados (precedência: plano → pago online → dinheiro):
    // - coberta pelo plano  → verde, "NÃO cobrar"
    // - card/mbway (online) → verde, "💳 Pago no app — NÃO cobrar" [PART C]
    // - dinheiro            → laranja, "cobrar €X ao passageiro"
    final covered = ride.usedSubscriptionRide;
    final paidOnline = !covered && ride.isPaidOnline;
    final noCollect = covered || paidOnline;

    final String emoji;
    final String text;
    if (covered) {
      emoji = '💚';
      text = 'Coberta pelo plano — NÃO cobrar o passageiro';
    } else if (paidOnline) {
      emoji = '💳';
      text = 'Pago no app — NÃO cobrar o passageiro';
    } else {
      final grossCents = ride.finalFareCents ?? ride.estFareCents;
      final approx = ride.finalFareCents == null; // antes do finish = estimado
      final gross = (grossCents / 100).toStringAsFixed(2);
      emoji = '💵';
      text = 'Dinheiro · cobrar ${approx ? '~' : ''}€$gross ao passageiro';
    }
    final color = noCollect ? AppColors.primary : Colors.orange.shade900;

    final row = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(emoji, style: const TextStyle(fontSize: 14)),
        const SizedBox(width: 6),
        Flexible(
          child: Text(
            text,
            style: TextStyle(
                color: color, fontSize: 13, fontWeight: FontWeight.w700),
          ),
        ),
      ],
    );

    if (dense) return row;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(
        color: noCollect
            ? AppColors.primary.withValues(alpha: 0.10)
            : Colors.orange.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(8),
      ),
      child: row,
    );
  }
}
