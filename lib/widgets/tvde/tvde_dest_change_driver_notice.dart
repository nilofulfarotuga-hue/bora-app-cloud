import 'package:flutter/material.dart';

import '../../config/app_colors.dart';
import '../../config/app_spacing.dart';
import '../../l10n/tr.dart';
import '../../models/tvde_ride.dart';

/// [Mudar destino 30/09] Aviso ao MOTORISTA de que o cliente mudou o destino.
///
/// Regra de ouro do lado do motorista: o número GRANDE é o que ELE ganha a
/// mais. O total do cliente só aparece em pequeno, como lembrete de quanto
/// cobrar — e só quando a corrida é em dinheiro.
///
/// Não mostra nada enquanto a corrida não tiver mudanças de destino.
class TvdeDestChangeDriverNotice extends StatelessWidget {
  const TvdeDestChangeDriverNotice({super.key, required this.ride});

  final TvdeRide ride;

  static String _eur(int cents) => '€${(cents / 100).toStringAsFixed(2)}';

  /// Texto do aviso rápido (snackbar) quando chega uma mudança nova.
  /// [ganhoCents] = o que esta mudança acrescenta ao ganho dele.
  static String snackFor(TvdeRide ride, int ganhoCents) {
    final destino = ride.destLabel ?? 'Destino';
    return ganhoCents > 0
        ? 'Novo destino: {0} · ganhas mais {1}'.trArgs([destino, _eur(ganhoCents)])
        : 'Novo destino: {0} · o teu ganho fica igual'.trArgs([destino]);
  }

  /// Lembrete de cobrança — só em dinheiro e só quando o cliente paga a mais.
  static String? collectFor(TvdeRide ride) {
    if (ride.isPaidOnline || ride.destChangeFeeCents <= 0) return null;
    if (ride.isRoundtripLeg || ride.usedSubscriptionRide) {
      return 'Cobras {0} da mudança de destino, em dinheiro, no fim.'
          .trArgs([_eur(ride.destChangeCashCents)]);
    }
    return 'Já está no total a cobrar: {0} de mudança de destino.'
        .trArgs([_eur(ride.destChangeFeeCents)]);
  }

  @override
  Widget build(BuildContext context) {
    if (!ride.hasDestChange) return const SizedBox.shrink();
    final ganho = ride.destChangeDriverCents;
    final cobrar = collectFor(ride);
    return Container(
      key: const Key('tvde_dest_change_driver_notice'),
      padding: const EdgeInsets.all(Spacing.sm),
      decoration: BoxDecoration(
        color: AppColors.primary.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.edit_location_alt, size: 18, color: AppColors.primary),
          const SizedBox(width: Spacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Novo destino: {0}'.trArgs([ride.destLabel ?? 'Destino']),
                    style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 13,
                        color: AppColors.textPrimary)),
                if (cobrar != null)
                  Text(cobrar,
                      key: const Key('tvde_dest_change_driver_collect'),
                      style: const TextStyle(
                          fontSize: 11.5, color: AppColors.textSecondary)),
              ],
            ),
          ),
          if (ganho > 0)
            Text('+${_eur(ganho)}',
                key: const Key('tvde_dest_change_driver_gain'),
                style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                    color: AppColors.primary)),
        ],
      ),
    );
  }
}
