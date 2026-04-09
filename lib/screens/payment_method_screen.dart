import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../auth/auth_store.dart';
import '../config/business_rules.dart';
import '../models/order_model.dart';
import '../stores/cart_store.dart';
import '../stores/order_store.dart';
import '../services/payment_service.dart';

class PaymentMethodScreen extends StatefulWidget {
  const PaymentMethodScreen({super.key});

  @override
  State<PaymentMethodScreen> createState() => _PaymentMethodScreenState();
}

class _PaymentMethodScreenState extends State<PaymentMethodScreen> {
  PaymentMethod _selectedMethod = PaymentMethod.card;
  bool _isProcessing = false;

  // ── Token discount state ───────────────────────────────────────────────────
  int _availableTokens = 0;
  bool _useTokens = false;
  bool _tokensLoaded = false;

  @override
  void initState() {
    super.initState();
    _loadTokens();
  }

  Future<void> _loadTokens() async {
    final userId = Supabase.instance.client.auth.currentUser?.id;
    if (userId == null) {
      setState(() => _tokensLoaded = true);
      return;
    }
    try {
      final response = await Supabase.instance.client.rpc(
        'get_user_tokens',
        params: {'p_user_id': userId},
      );
      if (mounted) {
        setState(() {
          _availableTokens = (response as int?) ?? 0;
          _tokensLoaded = true;
        });
      }
    } catch (e) {
      debugPrint('[PaymentMethodScreen] _loadTokens error: $e');
      if (mounted) setState(() => _tokensLoaded = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cartStore = context.watch<CartStore>();
    final pricing = cartStore.pricingBreakdown;
    final totalToPay = pricing.customerTotal;
    final hasApartmentDelivery = cartStore.apartmentDelivery;
    double baseDeliveryFee = pricing.deliveryFee - pricing.apartmentSurcharge;
    if (baseDeliveryFee < 0) {
      baseDeliveryFee = 0;
    }

    // ── Token discount calculation ─────────────────────────────────────────
    // BR: TOKEN_MAX_DISCOUNT_RATIO = 0.50, TOKEN_VALUE_EUR = 0.005
    // (100 tokens = €0.50 → 1 token = €0.005)
    final double maxDiscountEuro =
        totalToPay * BRTokens.TOKEN_MAX_DISCOUNT_RATIO;
    final int maxTokensUsable =
        (maxDiscountEuro / BRTokens.TOKEN_VALUE_EUR).floor();
    final int tokensToUse = min(_availableTokens, maxTokensUsable);
    final double tokenDiscount =
        _useTokens ? (tokensToUse * BRTokens.TOKEN_VALUE_EUR) : 0.0;
    final double finalPrice = (totalToPay - tokenDiscount).clamp(0.0, double.infinity);

    // Cash is only allowed up to CASH_MAX_ORDER_VALUE_EUR. Above that we
    // hide the option entirely (the DB trigger `enforce_cash_payment_limit`
    // enforces the same rule server-side — UI is UX only).
    final bool cashAllowed = finalPrice <= BRBusiness.CASH_MAX_ORDER_VALUE_EUR;

    // If the user had cash selected and the total crossed the threshold,
    // force-reset to card to avoid a broken submit state.
    if (!cashAllowed && _selectedMethod == PaymentMethod.cash) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) setState(() => _selectedMethod = PaymentMethod.card);
      });
    }

    final paymentOptions = <_PaymentOption>[
      const _PaymentOption(
        method: PaymentMethod.card,
        title: 'Cartão (Stripe)',
        subtitle: 'Pague com cartão de crédito ou débito.',
        icon: Icons.credit_card,
      ),
      const _PaymentOption(
        method: PaymentMethod.mbway,
        title: 'MBWay',
        subtitle: 'Receba uma notificação e confirme no MBWay.',
        icon: Icons.phone_iphone,
      ),
      if (cashAllowed)
        const _PaymentOption(
          method: PaymentMethod.cash,
          title: 'Dinheiro',
          subtitle: 'Pague diretamente ao estafeta na entrega.',
          icon: Icons.payments,
        ),
    ];

    return Scaffold(
      appBar: AppBar(
        title: const Text('Pagamento'),
      ),
      body: Column(
        children: [
          Expanded(
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Card(
                  elevation: 2,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(
                          'Resumo do pedido',
                          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                                fontWeight: FontWeight.w600,
                              ),
                        ),
                        const SizedBox(height: 12),
                        _SummaryRow(label: 'Subtotal', value: pricing.subtotal),
                        if (pricing.serviceFee > 0)
                          _SummaryRow(label: 'Taxas', value: pricing.serviceFee),
                        _SummaryRow(label: 'Entrega', value: baseDeliveryFee),
                        if (pricing.apartmentSurcharge > 0)
                          _SummaryRow(
                            label: 'Entrega em apartamento',
                            value: pricing.apartmentSurcharge,
                          ),
                        if (hasApartmentDelivery)
                          Padding(
                            padding: const EdgeInsets.only(top: 8),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Icon(Icons.apartment, color: Colors.orange.shade600, size: 20),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    'Entrega em apartamento solicitada — bónus +€1 para o estafeta.',
                                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                          fontWeight: FontWeight.w600,
                                          color: Colors.orange.shade800,
                                        ),
                                  ),
                                ),
                              ],
                            ),
                          ),

                        // ── Token discount toggle ──────────────────────────
                        if (_tokensLoaded && _availableTokens > 0 && tokensToUse > 0) ...[
                          const SizedBox(height: 8),
                          Container(
                            decoration: BoxDecoration(
                              color: Colors.amber.shade50,
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: Colors.amber.shade200),
                            ),
                            child: SwitchListTile.adaptive(
                              contentPadding: const EdgeInsets.symmetric(
                                  horizontal: 12, vertical: 4),
                              secondary: const Icon(Icons.monetization_on,
                                  color: Colors.amber),
                              title: Text(
                                'Usar Bora Tokens',
                                style: const TextStyle(
                                    fontWeight: FontWeight.w600, fontSize: 14),
                              ),
                              subtitle: Text(
                                '$tokensToUse tokens → -€${tokenDiscount.toStringAsFixed(2)} '
                                '(máx. 50% do total)',
                                style: TextStyle(
                                    fontSize: 12, color: Colors.amber.shade800),
                              ),
                              value: _useTokens,
                              onChanged: (v) => setState(() => _useTokens = v),
                            ),
                          ),
                        ] else if (_tokensLoaded && _availableTokens == 0)
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 4),
                            child: Row(
                              children: [
                                Icon(Icons.monetization_on,
                                    size: 14, color: Colors.grey.shade400),
                                const SizedBox(width: 6),
                                Text(
                                  'Sem tokens disponíveis',
                                  style: TextStyle(
                                      fontSize: 12, color: Colors.grey.shade500),
                                ),
                              ],
                            ),
                          ),

                        const Divider(height: 24),

                        // Discount row (only when tokens active)
                        if (_useTokens && tokenDiscount > 0)
                          _SummaryRow(
                            label: 'Desconto (tokens)',
                            value: -tokenDiscount,
                            isDiscount: true,
                          ),

                        _SummaryRow(
                          label: 'Total a pagar',
                          value: finalPrice,
                          isStrong: true,
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 24),
                Text(
                  'Escolha o método de pagamento',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                ),
                const SizedBox(height: 12),
                ...paymentOptions.map(
                  (option) => _PaymentOptionTile(
                    option: option,
                    groupValue: _selectedMethod,
                    onChanged: (value) {
                      if (value != null) {
                        setState(() => _selectedMethod = value);
                      }
                    },
                  ),
                ),
              ],
            ),
          ),
          SafeArea(
            top: false,
            minimum: const EdgeInsets.all(16),
            child: SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _isProcessing
                    ? null
                    : () => _confirmPayment(
                          context,
                          finalPrice,
                          tokensUsed: _useTokens ? tokensToUse : 0,
                        ),
                child: _isProcessing
                    ? const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('Confirmar pagamento'),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _confirmPayment(
    BuildContext context,
    double amount, {
    int tokensUsed = 0,
  }) async {
    if (_isProcessing) return;

    if (kIsWeb && _selectedMethod == PaymentMethod.card) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Pagamentos por cartão disponíveis apenas em dispositivos móveis.'),
        ),
      );
      return;
    }

    setState(() => _isProcessing = true);

    final paymentService = PaymentService();
    bool success = true;
    String? paymentIntentId;
    PaymentStatus paymentStatus = PaymentStatus.pending;

    switch (_selectedMethod) {
      case PaymentMethod.card:
        // Card status becomes `paid` ONLY via Stripe webhook (server-side).
        // Client keeps it as `pending` after the sheet completes.
        paymentIntentId = await paymentService.payWithCard(amount);
        success = paymentIntentId != null;
        paymentStatus = PaymentStatus.pending;
        break;
      case PaymentMethod.mbway:
        // MBWay is server-trusted: client never marks it paid. The
        // confirm-mbway-payment Edge Function flips the DB row.
        success = await paymentService.payWithMBWay(amount);
        paymentStatus = PaymentStatus.pending;
        break;
      case PaymentMethod.cash:
        success = await paymentService.payWithCash(amount);
        if (success) paymentStatus = PaymentStatus.paid;
        break;
    }

    if (!mounted) return;

    if (!success) {
      setState(() => _isProcessing = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Pagamento não pôde ser concluído.')),
      );
      return;
    }

    final cartStore = context.read<CartStore>();
    final orderStore = context.read<OrderStore>();
    final authStore = context.read<AuthStore>();
    final ordered = await cartStore.finishOrder(
      orderStore,
      paymentMethod: _selectedMethod,
      paymentStatus: paymentStatus,
      paymentIntentId: paymentIntentId,
      clientPhone: authStore.currentClient?.phone,
      customerName: authStore.currentClient?.name,
      tokensUsed: tokensUsed,
    );

    if (!mounted) return;

    setState(() => _isProcessing = false);

    if (!ordered) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Não foi possível criar o pedido. Tente novamente.')),
      );
      return;
    }

    // ── Consume tokens (FIFO) after order is successfully created ────────────
    // Only runs when the user activated the token toggle and tokensUsed > 0.
    // Runs independently of the snackbar/navigation so a token failure does
    // not block the user from seeing the success message.
    if (tokensUsed > 0) {
      final userId = Supabase.instance.client.auth.currentUser?.id;
      if (userId != null) {
        try {
          final consumed = await Supabase.instance.client.rpc(
            'consume_tokens',
            params: {
              'p_user_id': userId,
              'p_amount':  tokensUsed,
            },
          ) as bool? ?? false;
          debugPrint('[Checkout] consume_tokens($tokensUsed) → $consumed');
        } catch (e) {
          // Consumption failure is non-fatal — order already created.
          // Log and continue; tokens remain available for manual reconciliation.
          debugPrint('[Checkout] consume_tokens error (non-fatal): $e');
        }
      }
    }

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Pagamento efetuado com sucesso.')),
    );
    Navigator.pop(context, true);
  }
}

class _PaymentOption {
  const _PaymentOption({
    required this.method,
    required this.title,
    required this.subtitle,
    required this.icon,
  });

  final PaymentMethod method;
  final String title;
  final String subtitle;
  final IconData icon;
}

class _PaymentOptionTile extends StatelessWidget {
  const _PaymentOptionTile({
    required this.option,
    required this.groupValue,
    required this.onChanged,
  });

  final _PaymentOption option;
  final PaymentMethod groupValue;
  final ValueChanged<PaymentMethod?> onChanged;

  @override
  Widget build(BuildContext context) {
    final isSelected = option.method == groupValue;
    return Card(
      elevation: isSelected ? 4 : 1,
      margin: const EdgeInsets.symmetric(vertical: 8),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
          color: isSelected
              ? Theme.of(context).colorScheme.primary
              : Colors.grey.shade300,
          width: 1.2,
        ),
      ),
      child: RadioListTile<PaymentMethod>(
        value: option.method,
        groupValue: groupValue,
        onChanged: onChanged,
        title: Text(option.title),
        subtitle: Text(option.subtitle),
        secondary: Icon(option.icon),
      ),
    );
  }
}

class _SummaryRow extends StatelessWidget {
  const _SummaryRow({
    required this.label,
    required this.value,
    this.isStrong = false,
    this.isDiscount = false,
  });

  final String label;
  final double value;
  final bool isStrong;
  final bool isDiscount;

  @override
  Widget build(BuildContext context) {
    final color = isDiscount ? Colors.green.shade700 : null;
    final textStyle = Theme.of(context).textTheme.bodyMedium?.copyWith(
          fontWeight: isStrong ? FontWeight.bold : FontWeight.normal,
          color: color,
        );

    // value is already negative for discounts — show it with explicit sign.
    final valueText = isDiscount
        ? '-€${value.abs().toStringAsFixed(2)}'
        : '€${value.toStringAsFixed(2)}';

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: textStyle),
          Text(valueText, style: textStyle),
        ],
      ),
    );
  }
}
