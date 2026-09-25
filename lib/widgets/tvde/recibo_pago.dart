import 'package:flutter/material.dart';

import '../../config/app_colors.dart';
import '../../l10n/tr.dart';
import '../../models/saved_card.dart';
import '../../models/tvde_ride.dart';
import '../../services/card_wallet_service.dart';

/// "Pago 5,00 € · cartão •••• 4242" — a prova de que o dinheiro saiu.
///
/// ## A cicatriz (22/09/2026)
///
/// O Danilo pagou 5,00 € numa corrida e ficou convencido de que tinha corrido
/// de graça: não houve folha antes (ver `FolhaConfirmarCartao`) **e** não houve
/// recibo depois. A app cobrou e nunca mais falou do assunto.
///
/// Aparece só quando o servidor já confirmou o pagamento. Enquanto está a
/// pagar, ou se o pagamento não passou, não se mostra nada — dizer "pago"
/// antes de o ser seria pior do que calar.
class ReciboPago extends StatefulWidget {
  const ReciboPago({super.key, required this.ride, this.compacto = false});

  final TvdeRide ride;

  /// Versão de uma linha, para as listas do histórico.
  final bool compacto;

  /// A corrida foi mesmo paga online e há valor para mostrar?
  static bool vale(TvdeRide ride) =>
      ride.isPaidOnline &&
      ride.paymentStatus == 'succeeded' &&
      ride.estFareCents > 0;

  @override
  State<ReciboPago> createState() => _ReciboPagoState();
}

class _ReciboPagoState extends State<ReciboPago> {
  SavedCard? _cartao;

  @override
  void initState() {
    super.initState();
    _carregarCartao();
  }

  /// O `tvde_rides` não guarda os 4 últimos dígitos (e não deve guardar). Os
  /// que se mostram são os do cartão padrão da carteira — que é exactamente o
  /// que a Carteira Única cobrou. Sem cartão guardado (cartão novo) mostra-se
  /// só "cartão", sem inventar dígitos.
  Future<void> _carregarCartao() async {
    if (widget.ride.paymentMethod != 'card') return;
    try {
      final c = await CardWalletService.instance.defaultCard();
      if (mounted) setState(() => _cartao = c);
    } catch (_) {/* sem carteira → fica só "cartão" */}
  }

  String get _valor =>
      '${(widget.ride.estFareCents / 100).toStringAsFixed(2).replaceAll('.', ',')} €';

  String get _meio {
    if (widget.ride.paymentMethod == 'mbway') return 'MB Way';
    final c = _cartao;
    if (c == null) return 'cartão'.tr;
    return '${'cartão'.tr} •••• ${c.last4}';
  }

  @override
  Widget build(BuildContext context) {
    if (!ReciboPago.vale(widget.ride)) return const SizedBox.shrink();

    final texto = '${'Pago'.tr} $_valor · $_meio';

    if (widget.compacto) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.check_circle,
              size: 14, color: AppColors.primary),
          const SizedBox(width: 4),
          Text(texto,
              style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: AppColors.primary)),
        ],
      );
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.primary.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          const Icon(Icons.check_circle, size: 18, color: AppColors.primary),
          const SizedBox(width: 8),
          Expanded(
            child: Text(texto,
                style: const TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w600,
                    color: AppColors.primary)),
          ),
        ],
      ),
    );
  }
}
