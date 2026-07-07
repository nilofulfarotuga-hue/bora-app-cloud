import 'package:flutter/material.dart';

import '../../config/app_colors.dart';
import '../../config/app_spacing.dart';

/// Selector de pagamento do pedido TVDE. **Dinheiro** está SEMPRE visível e é
/// o default. **Cartão** e **MB Way** só aparecem com [cardEnabled] = true
/// (kill switch `tvde_card_payments_enabled`). Com o switch off mostra apenas
/// "Pagamento: Dinheiro" — resolve o "ia direto sem pedir pagamento".
class TvdePaymentSelector extends StatelessWidget {
  const TvdePaymentSelector({
    super.key,
    required this.current,
    required this.cardEnabled,
    required this.onChanged,
  });

  /// 'cash' | 'card' | 'mbway'
  final String current;
  final bool cardEnabled;
  final ValueChanged<String> onChanged;

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
      ],
    );
  }
}
