import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../config/app_colors.dart';
import '../../config/app_spacing.dart';
import '../../models/tvde_ride.dart';
import '../../stores/tvde_store.dart';

import '../../l10n/tr.dart';

/// [Fase B] Preço do pacote ida-e-volta do lado do MOTORISTA.
///
/// Memo de sessão: o badge de cobrança e o aviso são widgets diferentes mas
/// TÊM de mostrar o mesmo número. Ambos lêem `paid_cents` do vale
/// (`tvde_roundtrip_credits`) associado à corrida — fonte única por corrida.
class TvdeRoundtripPrice {
  TvdeRoundtripPrice._();

  static const int fallbackCents = 800;

  /// Lê o `paid_cents` do vale ligado a esta corrida.
  static Future<int> loadForRide(TvdeStore store, TvdeRide ride) async {
    final creditId = ride.roundtripCreditId;
    if (creditId == null) return fallbackCents;
    return store.getRoundtripPaidCents(creditId);
  }
}

/// [Fase B] Aviso ao MOTORISTA numa perna do pacote (ida ou volta).
///
/// Existe por uma razão só: o motorista não pode confundir **o que ganha** com
/// **o que o cliente paga**. O preço do pacote é da Bora — na ida em dinheiro
/// ele recolhe-os em mão por conta dela, e a Bora acerta as contas no fim da
/// semana. Sem este aviso, um motorista que ganha menos do que recolhe assume
/// que o valor é dele.
///
/// Não mostra nada fora do pacote (`ride.isRoundtripLeg == false`).
class TvdeRoundtripDriverNotice extends StatefulWidget {
  const TvdeRoundtripDriverNotice({super.key, required this.ride});

  final TvdeRide ride;

  /// Texto PT-PT do aviso. Público para o teste poder travar a redação sem
  /// montar o ecrã inteiro do motorista.
  static String messageFor(TvdeRide ride, int packageCents) {
    final earn = ((ride.driverEarnCents ?? 0) / 100).toStringAsFixed(2);
    final pack = (packageCents / 100).toStringAsFixed(2);
    if (ride.isReturnLeg) {
      return 'Recebes €{0} desta corrida. A volta já está paga — não cobres nada ao cliente.'.trArgs([earn]);
    }
    if (ride.isPaidOnline) {
      return 'Recebes €{0} desta corrida. O cliente já pagou os €{1} online — não cobres nada ao cliente.'.trArgs([earn, pack]);
    }
    return 'Recebes €{0} desta corrida. Os €{1} que o cliente paga NÃO são teus — recolhes em mão por conta da Bora, que acerta contigo no fim da semana.'.trArgs([earn, pack]);
  }

  @override
  State<TvdeRoundtripDriverNotice> createState() =>
      _TvdeRoundtripDriverNoticeState();
}

class _TvdeRoundtripDriverNoticeState extends State<TvdeRoundtripDriverNotice> {
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
    if (!ride.isRoundtripLeg) return const SizedBox.shrink();

    return Container(
      padding: const EdgeInsets.all(Spacing.sm),
      decoration: BoxDecoration(
        color: AppColors.primary.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.primary.withValues(alpha: 0.35)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.sync_alt, size: 18, color: AppColors.primary),
          const SizedBox(width: Spacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(ride.isReturnLeg ? 'Volta do pacote' : 'Ida do pacote',
                    style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: AppColors.primary)),
                const SizedBox(height: 2),
                Text(
                  TvdeRoundtripDriverNotice.messageFor(ride, _packageCents),
                  style: const TextStyle(
                      fontSize: 12.5, color: AppColors.textPrimary),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
