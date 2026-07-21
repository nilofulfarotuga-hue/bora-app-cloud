import 'package:flutter/material.dart';

import '../config/app_colors.dart';
import '../config/app_spacing.dart';
import '../models/saved_card.dart';
import '../services/card_wallet_service.dart';
import '../services/payment_biometric_gate.dart';
import 'bora/bora_primary_button.dart';

/// Botão de pagamento partilhado por todas as verticais que cobram cartão
/// (Carteira Única, Parte 2/6).
///
/// Faz três coisas, sempre pela mesma ordem:
///   1. mostra qual o cartão que vai ser cobrado (marca + últimos 4);
///   2. pede digital/rosto antes de cobrar, quando é cartão guardado;
///   3. chama [onPay] com o `saved_pm_id` a usar (`null` = cartão novo, o
///      ecrã deve cair no PaymentSheet).
///
/// Dois modos:
/// - **Ecrã com selector próprio** (delivery): passa [savedPmIdOverride] e
///   [showSavedCard] `false` — a escolha do ecrã manda, o botão só faz o gate.
/// - **Ecrã sem selector** (reserva, marcação, TVDE, limpeza): não passa nada;
///   o botão resolve o cartão padrão da carteira e mostra-o.
class UnifiedCheckoutButton extends StatefulWidget {
  const UnifiedCheckoutButton({
    super.key,
    required this.label,
    required this.onPay,
    this.amount,
    this.busy = false,
    this.enabled = true,
    this.showSavedCard = true,
    this.savedPmIdOverride,
    this.useOverride = false,
    this.wallet,
    this.gate,
  });

  /// Texto do botão, ex.: 'Confirmar pagamento'.
  final String label;

  /// Cobra. Recebe o `saved_pm_id` ou `null` (cartão novo → PaymentSheet).
  final Future<void> Function(String? savedPmId) onPay;

  /// Valor a cobrar — só para o texto do diálogo do sistema.
  final double? amount;

  final bool busy;
  final bool enabled;

  /// Mostra a linha "Visa •••• 4242". Desliga-se em ecrãs que já listam os
  /// cartões, para não dizer a mesma coisa duas vezes.
  final bool showSavedCard;

  /// Cartão escolhido pelo ecrã. Só é respeitado com [useOverride] `true` —
  /// senão não havia como distinguir "escolheu cartão novo" (`null`) de
  /// "o ecrã não opina".
  final String? savedPmIdOverride;
  final bool useOverride;

  /// Injectáveis para teste.
  final CardWalletService? wallet;
  final PaymentBiometricGate? gate;

  @override
  State<UnifiedCheckoutButton> createState() => _UnifiedCheckoutButtonState();
}

class _UnifiedCheckoutButtonState extends State<UnifiedCheckoutButton> {
  CardWalletService get _wallet => widget.wallet ?? CardWalletService.instance;
  PaymentBiometricGate get _gate => widget.gate ?? PaymentBiometricGate.instance;

  SavedCard? _defaultCard;
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    if (widget.showSavedCard || !widget.useOverride) _loadDefaultCard();
  }

  Future<void> _loadDefaultCard() async {
    final card = await _wallet.defaultCard();
    if (!mounted) return;
    setState(() => _defaultCard = card);
  }

  /// O cartão que vai ser cobrado: o do ecrã se ele opinar, senão o padrão.
  String? get _effectivePmId =>
      widget.useOverride ? widget.savedPmIdOverride : _defaultCard?.id;

  Future<void> _handlePress() async {
    if (_loading || widget.busy) return;
    final pmId = _effectivePmId;

    setState(() => _loading = true);
    try {
      final authorized = await _gate.ensureAuthorized(
        usingSavedCard: pmId != null,
        reason: widget.amount != null
            ? PaymentBiometricGate.reasonForAmount(widget.amount!)
            : 'Confirma o pagamento',
      );
      if (!mounted) return;
      if (!authorized) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Pagamento cancelado. Não foi cobrado nada.'),
          ),
        );
        return;
      }
      await widget.onPay(pmId);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final busy = widget.busy || _loading;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (widget.showSavedCard && _defaultCard != null) ...[
          _cardLine(_defaultCard!),
          const SizedBox(height: Spacing.md),
        ],
        BoraPrimaryButton(
          label: widget.label,
          loading: busy,
          onPressed: (busy || !widget.enabled) ? null : _handlePress,
        ),
      ],
    );
  }

  Widget _cardLine(SavedCard card) {
    return Container(
      padding: const EdgeInsets.symmetric(
          horizontal: Spacing.md, vertical: Spacing.sm),
      decoration: BoxDecoration(
        color: AppColors.surface2,
        borderRadius: BorderRadius.circular(Radii.md),
      ),
      child: Row(
        children: [
          const Icon(Icons.credit_card, size: 18, color: AppColors.primary),
          const SizedBox(width: Spacing.sm),
          Expanded(
            child: Text(
              '${card.prettyBrand} •••• ${card.last4}',
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: AppColors.textPrimary,
              ),
            ),
          ),
          const Icon(Icons.fingerprint, size: 18, color: AppColors.textSecondary),
        ],
      ),
    );
  }
}
