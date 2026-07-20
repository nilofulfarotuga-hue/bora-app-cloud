import 'package:flutter/material.dart';

import '../../config/app_colors.dart';
import '../../config/app_spacing.dart';

/// Selector de pagamento do pedido TVDE. **Dinheiro** está SEMPRE visível e é
/// o default. **Cartão** e **MB Way** só aparecem com [cardEnabled] = true
/// (kill switch `tvde_card_payments_enabled`). Com o switch off mostra apenas
/// "Pagamento: Dinheiro" — resolve o "ia direto sem pedir pagamento".
///
/// Com MB Way selecionado mostra o campo do **número de telemóvel** — sem ele a
/// Edge Function recebe `phone` vazio, monta o E.164 como `+351` e a Stripe
/// recusa o PaymentIntent. Mesmo contrato do `ReservationPaymentMethodSheet`
/// (9 dígitos PT); o controller é do pai, que valida antes de confirmar.
class TvdePaymentSelector extends StatelessWidget {
  const TvdePaymentSelector({
    super.key,
    required this.current,
    required this.cardEnabled,
    required this.onChanged,
    this.phoneController,
    this.phoneError,
  });

  /// 'cash' | 'card' | 'mbway'
  final String current;
  final bool cardEnabled;
  final ValueChanged<String> onChanged;

  /// Controller do número MB Way (só usado quando [current] == 'mbway').
  final TextEditingController? phoneController;

  /// Mensagem de erro do número, quando a validação do pai falha.
  final String? phoneError;

  Widget _chip(String value, String label, IconData icon, Key key) {
    final selected = current == value;
    return ChoiceChip(
      key: key,
      avatar: Icon(icon,
          size: 18, color: selected ? Colors.white : AppColors.textSecondary),
      label: Text(label),
      selected: selected,
      selectedColor: AppColors.primary,
      labelStyle: TextStyle(
          color: selected ? Colors.white : AppColors.textPrimary,
          fontWeight: FontWeight.w600),
      onSelected: (_) => onChanged(value),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Pagamento',
            style: TextStyle(
                fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
        const SizedBox(height: Spacing.xs),
        Wrap(
          spacing: Spacing.sm,
          children: [
            _chip('cash', 'Dinheiro', Icons.payments_outlined,
                const Key('tvde_pay_cash')),
            if (cardEnabled) ...[
              _chip('card', 'Cartão', Icons.credit_card,
                  const Key('tvde_pay_card')),
              _chip('mbway', 'MB Way', Icons.smartphone,
                  const Key('tvde_pay_mbway')),
            ],
          ],
        ),
        if (cardEnabled && current == 'mbway' && phoneController != null) ...[
          const SizedBox(height: Spacing.sm),
          TextField(
            key: const Key('tvde_pay_mbway_phone'),
            controller: phoneController,
            keyboardType: TextInputType.phone,
            decoration: InputDecoration(
              labelText: 'Número MBWay',
              hintText: '9XXXXXXXX',
              prefixText: '+351 ',
              errorText: phoneError,
              border: const OutlineInputBorder(),
              isDense: true,
            ),
          ),
          const SizedBox(height: Spacing.xs),
          const Text(
            'Vais receber o pedido de pagamento na app MBWay.',
            style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
          ),
        ],
      ],
    );
  }
}
