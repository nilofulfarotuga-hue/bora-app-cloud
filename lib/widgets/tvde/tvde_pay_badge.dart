import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/tvde_fare_view.dart';
import '../../models/tvde_ride.dart';
import '../../stores/tvde_store.dart';
import '../../config/app_colors.dart';
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
    final badge = CollectBadge(
      state: CollectState.collectCash,
      amountCents: fare.driverCollectCents,
      approx: fare.approx,
      dense: dense,
    );
    // Contas claras (20/09/2026): numa corrida a dinheiro tem de ficar claro,
    // ANTES de terminar, que o valor em mão não é todo dele. O ganho vem do
    // servidor (agreed_driver_earn_cents / driver_earn_cents); o resto é a
    // diferença — o que entrega à Bora no acerto.
    final earn = ride.netDriverEarnCents;
    if (dense || earn <= 0 || earn > fare.driverCollectCents) return badge;
    final teu = (earn / 100).toStringAsFixed(2);
    final bora = ((fare.driverCollectCents - earn) / 100).toStringAsFixed(2);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        badge,
        const SizedBox(height: 4),
        Text(
          '${fare.approx ? '~' : ''}€$teu são teus · €$bora para a Bora',
          key: const Key('tvde_pay_badge_split'),
          textAlign: TextAlign.center,
          style: const TextStyle(
              fontSize: 12, fontWeight: FontWeight.w700, color: AppColors.success),
        ),
      ],
    );
  }
}
