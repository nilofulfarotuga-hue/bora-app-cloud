import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../auth/auth_store.dart';
import '../../../config/app_colors.dart';
import '../../../models/saved_card.dart';
import '../../../services/card_wallet_service.dart';
import '../../../widgets/card_mandate_notice.dart';

import '../../../l10n/tr.dart';

/// Métodos de pagamento aceites para pré-pagamento de reserva.
/// CASH é deliberadamente excluído — reserva exige pré-pagamento online.
enum ReservationPaymentMethod { card, mbway }

/// Legenda da opção "Cartão" (Carteira Única, 2026-07-21).
///
/// Com cartão guardado diz qual é, para o cliente saber o que vai ser cobrado
/// antes de confirmar. Só marca + últimos 4 dígitos — nunca o número completo.
/// Função pura de propósito: o sheet exige um AuthStore com Supabase
/// inicializado, o que impede um teste de widget; assim o texto fica testável.
String cardOptionSubtitle(SavedCard? defaultCard) => defaultCard == null
    ? 'Pague com cartão de crédito ou débito.'
    : '${defaultCard.prettyBrand} •••• ${defaultCard.last4} · pagas num toque';

class ReservationPaymentChoice {
  const ReservationPaymentChoice({
    required this.method,
    this.mbwayPhone,
  });

  final ReservationPaymentMethod method;
  final String? mbwayPhone;
}

/// Bottom sheet de escolha de método de pagamento para reserva (€3 prepagamento).
///
/// Padrão visual alinhado com `payment_method_screen.dart` (pedidos normais),
/// mas restrito a Cartão + MBWay. Para MBWay recolhe número PT (9 dígitos).
///
/// Uso:
/// ```dart
/// final choice = await showModalBottomSheet<ReservationPaymentChoice>(
///   context: context,
///   isScrollControlled: true,
///   builder: (_) => const ReservationPaymentMethodSheet(amountEur: 3.0),
/// );
/// if (choice == null) return; // user cancelou
/// ```
class ReservationPaymentMethodSheet extends StatefulWidget {
  const ReservationPaymentMethodSheet({
    super.key,
    required this.amountEur,
    this.title = 'Reserva',
  });

  final double amountEur;

  /// Título do sheet — default mantém o texto das reservas; o fluxo de
  /// marcações (M7) passa 'Sinal da marcação'.
  final String title;

  @override
  State<ReservationPaymentMethodSheet> createState() =>
      _ReservationPaymentMethodSheetState();
}

class _ReservationPaymentMethodSheetState
    extends State<ReservationPaymentMethodSheet> {
  ReservationPaymentMethod _selected = ReservationPaymentMethod.card;
  final TextEditingController _phoneCtrl = TextEditingController();
  String? _phoneError;

  /// Carteira Unica (2026-07-21) — cartao guardado que vai ser cobrado, para o
  /// cliente ver ANTES de confirmar qual o cartao em causa. `null` = ainda a
  /// carregar ou nao ha cartao guardado (cai no PaymentSheet, como sempre).
  SavedCard? _defaultCard;

  @override
  void initState() {
    super.initState();
    final profilePhone = context.read<AuthStore>().currentClient?.phone;
    if (profilePhone != null && profilePhone.isNotEmpty) {
      final digits = profilePhone.replaceAll(RegExp(r'\D'), '');
      _phoneCtrl.text = digits.startsWith('351') ? digits.substring(3) : digits;
    }
    _loadDefaultCard();
  }

  Future<void> _loadDefaultCard() async {
    final card = await CardWalletService.instance.defaultCard();
    if (!mounted) return;
    setState(() => _defaultCard = card);
  }

  @override
  void dispose() {
    _phoneCtrl.dispose();
    super.dispose();
  }

  void _onConfirm() {
    if (_selected == ReservationPaymentMethod.mbway) {
      final digits = _phoneCtrl.text.replaceAll(RegExp(r'\D'), '');
      if (digits.length != 9) {
        setState(() {
          _phoneError = 'Número MBWay inválido (9 dígitos).'.tr;
        });
        return;
      }
      Navigator.of(context).pop(
        ReservationPaymentChoice(
          method: ReservationPaymentMethod.mbway,
          mbwayPhone: digits,
        ),
      );
      return;
    }
    Navigator.of(context).pop(
      const ReservationPaymentChoice(method: ReservationPaymentMethod.card),
    );
  }

  @override
  Widget build(BuildContext context) {
    final viewInsets = MediaQuery.of(context).viewInsets;
    return Padding(
      padding: EdgeInsets.only(bottom: viewInsets.bottom),
      child: SafeArea(
        top: false,
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 14),
                  decoration: BoxDecoration(
                    color: Colors.grey.shade300,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              Text(
                '${widget.title.tr} — €${widget.amountEur.toStringAsFixed(2)}',
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textPrimary,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'Escolhe o método de pré-pagamento.'.tr,
                style: const TextStyle(
                  fontSize: 13,
                  color: AppColors.textSecondary,
                ),
              ),
              const SizedBox(height: 12),
              _OptionTile(
                title: 'Cartão (Stripe)'.tr,
                subtitle: cardOptionSubtitle(_defaultCard),
                icon: Icons.credit_card,
                value: ReservationPaymentMethod.card,
                groupValue: _selected,
                onChanged: (v) => setState(() => _selected = v!),
              ),
              _OptionTile(
                title: 'MBWay'.tr,
                subtitle: 'Receba uma notificação e confirme no MBWay.'.tr,
                icon: Icons.phone_iphone,
                value: ReservationPaymentMethod.mbway,
                groupValue: _selected,
                onChanged: (v) => setState(() => _selected = v!),
              ),
              // Mandato PSD2 — só no cartão e só até o 1.º ficar guardado.
              if (_selected == ReservationPaymentMethod.card)
                const CardMandateNotice(),
              if (_selected == ReservationPaymentMethod.mbway) ...[
                const SizedBox(height: 8),
                TextField(
                  controller: _phoneCtrl,
                  keyboardType: TextInputType.phone,
                  maxLength: 9,
                  decoration: InputDecoration(
                    labelText: 'Número MBWay'.tr,
                    hintText: '912345678',
                    prefixText: '+351 ',
                    border: const OutlineInputBorder(),
                    errorText: _phoneError,
                  ),
                  onChanged: (_) {
                    if (_phoneError != null) {
                      setState(() => _phoneError = null);
                    }
                  },
                ),
                const SizedBox(height: 4),
                Text(
                  'Telemóvel português associado à tua conta MBWay (9 dígitos).'.tr,
                  style: const TextStyle(
                    fontSize: 12,
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: _onConfirm,
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                  icon: const Icon(Icons.lock),
                  label: Text(
                    'Pagar €{0}'.trArgs([widget.amountEur.toStringAsFixed(2)]),
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _OptionTile extends StatelessWidget {
  const _OptionTile({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.value,
    required this.groupValue,
    required this.onChanged,
  });

  final String title;
  final String subtitle;
  final IconData icon;
  final ReservationPaymentMethod value;
  final ReservationPaymentMethod groupValue;
  final ValueChanged<ReservationPaymentMethod?> onChanged;

  @override
  Widget build(BuildContext context) {
    final isSelected = value == groupValue;
    return Card(
      elevation: isSelected ? 3 : 1,
      margin: const EdgeInsets.symmetric(vertical: 6),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(
          color: isSelected
              ? Theme.of(context).colorScheme.primary
              : Colors.grey.shade300,
          width: 1.2,
        ),
      ),
      child: RadioListTile<ReservationPaymentMethod>(
        value: value,
        groupValue: groupValue,
        onChanged: onChanged,
        title: Text(title),
        subtitle: Text(subtitle),
        secondary: Icon(icon),
      ),
    );
  }
}
