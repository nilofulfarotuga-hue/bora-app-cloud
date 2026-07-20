import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/tvde_ride.dart';
import '../../stores/tvde_store.dart';
import '../payments/collect_badge.dart';
import 'tvde_roundtrip_driver_notice.dart';

/// Adapter TVDE do badge de cobrança do motorista. Mapeia a corrida para o
/// [CollectBadge] partilhado (mesmo widget do delivery e da limpeza):
/// coberta pelo plano → não cobrar; card/mbway → já pago; senão → cobrar €X.
/// Antes do finish usa o estimado (`~`), depois usa o valor final real.
///
/// [Fase B] Perna do pacote €8 manda em tudo o resto: a corrida é PREPAGA, por
/// isso a tarifa nunca se cobra. Na ida em dinheiro o que se recolhe é o
/// **pacote** (€8, as duas pernas), não a tarifa desta corrida — sem esta
/// exceção o badge mandava cobrar os €5 da ida por cima dos €8 (o "€13").
class TvdePayBadge extends StatefulWidget {
  const TvdePayBadge({super.key, required this.ride, this.dense = false});

  final TvdeRide ride;
  final bool dense;

  @override
  State<TvdePayBadge> createState() => _TvdePayBadgeState();
}

class _TvdePayBadgeState extends State<TvdePayBadge> {
  int _packageCents = TvdeRoundtripPrice.cents;

  @override
  void initState() {
    super.initState();
    if (!widget.ride.isRoundtripLeg) return;
    TvdeRoundtripPrice.load(context.read<TvdeStore>()).then((v) {
      if (mounted) setState(() => _packageCents = v);
    });
  }

  @override
  Widget build(BuildContext context) {
    final ride = widget.ride;
    final dense = widget.dense;

    if (ride.isRoundtripLeg) {
      // Volta (sempre grátis para o cliente) ou pacote já pago online.
      if (ride.isReturnLeg || ride.isPaidOnline) {
        return CollectBadge(state: CollectState.paidOnline, dense: dense);
      }
      // Ida do pacote em dinheiro: recolhe os €8 do pacote, uma vez só.
      return CollectBadge(
        state: CollectState.collectCash,
        amountCents: _packageCents,
        dense: dense,
      );
    }

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
