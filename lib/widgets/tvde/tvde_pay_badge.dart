import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/tvde_fare_view.dart';
import '../../models/tvde_ride.dart';
import '../../stores/tvde_store.dart';
import '../payments/collect_badge.dart';
import 'tvde_roundtrip_driver_notice.dart';

/// Adapter TVDE do badge de cobrança do motorista. Mapeia a corrida para o
/// [CollectBadge] partilhado (mesmo widget do delivery e da limpeza):
/// coberta pelo plano → não cobrar; card/mbway → já pago; senão → cobrar €X.
/// Antes do finish usa o estimado (`~`), depois usa o valor final real.
///
/// [Fase B] Perna do pacote manda em tudo o resto: a corrida é PREPAGA, por
/// isso a tarifa nunca se cobra. Na ida em dinheiro o que se recolhe é o
/// **pacote** (preço dinâmico, as duas pernas), não a tarifa desta corrida.
class TvdePayBadge extends StatefulWidget {
  const TvdePayBadge({super.key, required this.ride, this.dense = false});

  final TvdeRide ride;
  final bool dense;

  @override
  State<TvdePayBadge> createState() => _TvdePayBadgeState();
}

class _TvdePayBadgeState extends State<TvdePayBadge> {
  int _packageCents = TvdeRoundtripPrice.fallbackCents;

  @override
  void initState() {
    super.initState();
    if (!widget.ride.isRoundtripLeg) return;
    TvdeRoundtripPrice.loadForRide(context.read<TvdeStore>(), widget.ride)
        .then((v) {
      if (mounted) setState(() => _packageCents = v);
    });
  }

  @override
  Widget build(BuildContext context) {
    final ride = widget.ride;
    final dense = widget.dense;

    // Fonte única partilhada com o ecrã do cliente — os dois nunca discordam.
    final fare = TvdeFareView.of(ride, packageCents: _packageCents);

    if (fare.driverCollectCents <= 0) {
      return CollectBadge(
        state: fare.coveredByPlan
            ? CollectState.coveredByPlan
            : CollectState.paidOnline,
        dense: dense,
      );
    }
    return CollectBadge(
      state: CollectState.collectCash,
      amountCents: fare.driverCollectCents,
      approx: fare.approx,
      dense: dense,
    );
  }
}
