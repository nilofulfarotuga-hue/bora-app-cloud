import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../config/app_colors.dart';
import '../../config/app_spacing.dart';
import '../../models/tvde_ride.dart';
import '../../stores/tvde_store.dart';

/// [Fase B] Preço do pacote ida-e-volta (€8) do lado do MOTORISTA.
///
/// Memo de sessão: o badge de cobrança e o aviso são widgets diferentes mas
/// TÊM de mostrar o mesmo número — se um dissesse €8 e o outro €9 (porque o
/// Danilo mudou `tvde_roundtrip_price_cents` a meio), o motorista recolheria o
/// valor errado em mão. Uma leitura por sessão, partilhada pelos dois.
class TvdeRoundtripPrice {
  TvdeRoundtripPrice._();

  /// Mesmo fallback que o cliente usa em `tvde_request_ride_screen`.
  static const int fallbackCents = 800;

  static int _cached = fallbackCents;
  static Future<int>? _inflight;

  /// Último valor conhecido (fallback até a primeira leitura chegar).
  static int get cents => _cached;

  static Future<int> load(TvdeStore store) {
    final pending = _inflight;
    if (pending != null) return pending;
    final f = store
        .getSettingInt('tvde_roundtrip_price_cents', fallbackCents)
        .then((v) {
      _cached = v;
      return v;
    });
    _inflight = f;
    return f;
  }
}

/// [Fase B] Aviso ao MOTORISTA numa perna do pacote €8 (ida ou volta).
///
/// Existe por uma razão só: o motorista não pode confundir **o que ganha** com
/// **o que o cliente paga**. Os €8 são o preço das duas pernas e são da Bora —
/// na ida em dinheiro ele recolhe-os em mão por conta dela, e a Bora acerta as
/// contas no fim da semana. Sem este aviso, um motorista que ganha €4 e recebe
/// €8 em mão assume que os €8 são dele.
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
      return 'Recebes €$earn desta corrida. A volta já está paga — não cobres '
          'nada ao cliente.';
    }
    if (ride.isPaidOnline) {
      return 'Recebes €$earn desta corrida. O cliente já pagou os €$pack '
          'online — não cobres nada ao cliente.';
    }
    return 'Recebes €$earn desta corrida. Os €$pack que o cliente paga NÃO são '
        'teus — recolhes em mão por conta da Bora, que acerta contigo no fim '
        'da semana.';
  }

  @override
  State<TvdeRoundtripDriverNotice> createState() =>
      _TvdeRoundtripDriverNoticeState();
}

class _TvdeRoundtripDriverNoticeState extends State<TvdeRoundtripDriverNotice> {
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
