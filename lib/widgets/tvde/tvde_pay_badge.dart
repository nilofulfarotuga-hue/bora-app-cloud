import 'package:flutter/material.dart';

import '../../models/tvde_ride.dart';
import '../payments/collect_badge.dart';

/// Adapter TVDE do badge de cobrança do motorista. Mapeia a corrida para o
/// [CollectBadge] partilhado (mesmo widget do delivery e da limpeza):
/// coberta pelo plano → não cobrar; card/mbway → já pago; senão → cobrar €X.
/// Antes do finish usa o estimado (`~`), depois usa o valor final real.
class TvdePayBadge extends StatelessWidget {
  const TvdePayBadge({super.key, required this.ride, this.dense = false});

  final TvdeRide ride;
  final bool dense;

  @override
  Widget build(BuildContext context) {
    if (ride.usedSubscriptionRide) {
      return CollectBadge(state: CollectState.coveredByPlan, dense: dense);
    }
    if (ride.isPaidOnline) {
      return CollectBadge(state: CollectState.paidOnline, dense: dense);
    }
    return CollectBadge(
      state: CollectState.collectCash,
      amountCents: ride.finalFareCents ?? ride.estFareCents,
      approx: ride.finalFareCents == null,
      dense: dense,
    );
  }
}
