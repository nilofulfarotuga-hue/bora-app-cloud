import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../auth/auth_store.dart';
import '../config/business_rules.dart' show BRTokens;
import '../models/order_model.dart';
import '../stores/cart_store.dart';
import '../stores/order_store.dart';
import 'package:flutter_stripe/flutter_stripe.dart' show StripeException;

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
    final double finalPrice =
        (totalToPay - tokenDiscount).clamp(0.0, double.infinity);

    const paymentOptions = <_PaymentOption>[
      _PaymentOption(
        method: PaymentMethod.card,
        title: 'Cartão (Stripe)',
        subtitle: 'Pague com cartão de crédito ou débito.',
        icon: Icons.credit_card,
      ),
      _PaymentOption(
        method: PaymentMethod.mbway,
        title: 'MBWay',
        subtitle: 'Receba uma notificação e confirme no MBWay.',
        icon: Icons.phone_iphone,
      ),
      _PaymentOption(
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
                          style:
                              Theme.of(context).textTheme.titleMedium?.copyWith(
                                    fontWeight: FontWeight.w600,
                                  ),
                        ),
                        const SizedBox(height: 12),
                        _SummaryRow(label: 'Subtotal', value: pricing.subtotal),
                        if (pricing.serviceFee > 0)
                          _SummaryRow(
                              label: 'Taxas', value: pricing.serviceFee),
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
                                Icon(Icons.apartment,
                                    color: Colors.orange.shade600, size: 20),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    'Entrega em apartamento solicitada — bónus +€1 para o estafeta.',
                                    style: Theme.of(context)
                                        .textTheme
                                        .bodySmall
                                        ?.copyWith(
                                          fontWeight: FontWeight.w600,
                                          color: Colors.orange.shade800,
                                        ),
                                  ),
                                ),
                              ],
                            ),
                          ),

                        // ── Token discount toggle ──────────────────────────
                        if (_tokensLoaded &&
                            _availableTokens > 0 &&
                            tokensToUse > 0) ...[
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
                              title: const Text(
                                'Usar Bora Tokens',
                                style: TextStyle(
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
                                      fontSize: 12,
                                      color: Colors.grey.shade500),
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
                RadioGroup<PaymentMethod>(
                  groupValue: _selectedMethod,
                  onChanged: (value) {
                    if (value != null) {
                      setState(() => _selectedMethod = value);
                    }
                  },
                  child: Column(
                    children: paymentOptions
                        .map((option) => _PaymentOptionTile(
                              option: option,
                              groupValue: _selectedMethod,
                            ))
                        .toList(),
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

    final messenger = ScaffoldMessenger.of(context);

    // Pre-flight: block payment if delivery address is not set.
    // This prevents charging the user and then failing at order creation.
    final cartStore = context.read<CartStore>();
    if (cartStore.deliveryLocation == null || cartStore.dropoffStreet.isEmpty) {
      messenger.showSnackBar(
        const SnackBar(
          content: Text(
              'Endereço de entrega não definido. Volte e selecione um endereço.'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    if (kIsWeb && _selectedMethod == PaymentMethod.card) {
      messenger.showSnackBar(
        const SnackBar(
          content: Text(
              'Pagamentos por cartão disponíveis apenas em dispositivos móveis.'),
        ),
      );
      return;
    }

    setState(() => _isProcessing = true);

    final paymentService = PaymentService();
    final orderStore = context.read<OrderStore>();
    final authStore = context.read<AuthStore>();
    // Ensure valid Supabase session before inserting order (re-signs as guest if expired).
    await authStore.ensureSessionForOrder();

    // ── Card: order must exist in DB before Stripe charges it ────────────────
    // The edge function validates payment_buffer_total from the DB,
    // so we create the order first (payment_status = pending), then charge.
    if (_selectedMethod == PaymentMethod.card) {
      // Step 1: create order in DB first
      final ordered = await cartStore.finishOrder(
        orderStore,
        paymentMethod: PaymentMethod.card,
        paymentStatus: PaymentStatus.pending,
        clientPhone: authStore.currentClient?.phone,
        customerName: authStore.currentClient?.name,
        tokensUsed: tokensUsed,
      );
      if (!mounted) return;
      if (!ordered) {
        setState(() => _isProcessing = false);
        messenger.showSnackBar(
          const SnackBar(
              content:
                  Text('Não foi possível criar o pedido. Tente novamente.')),
        );
        return;
      }

      // Step 2: charge against the real order ID.
      // Use paymentBufferTotal from the created order — it already includes the
      // 15% pre-auth buffer (non-partner) and token discount, matching exactly
      // what the edge function reads from the DB.
      final createdOrder = orderStore.orders.first;
      final orderId = createdOrder.id;
      final stripeAmount = createdOrder.paymentBufferTotal;
      try {
        final data = await paymentService.createPaymentIntent(
          orderId: orderId,
          amount: stripeAmount,
        );
        await paymentService.processPayment(data['clientSecret'] as String);
      } on StripeException catch (e) {
        if (!mounted) return;
        setState(() => _isProcessing = false);
        debugPrint(
            '[Checkout] card cancelled/declined: ${e.error.localizedMessage}');
        messenger.showSnackBar(
          const SnackBar(content: Text('Pagamento não pôde ser concluído.')),
        );
        return;
      } catch (e) {
        if (!mounted) return;
        setState(() => _isProcessing = false);
        debugPrint('[Checkout] card payment error: $e');
        messenger.showSnackBar(
          const SnackBar(
            content: Text(
                'Pagamento por cartão indisponível. Tente MBWay ou dinheiro.'),
            duration: Duration(seconds: 5),
          ),
        );
        return;
      }

      // Step 3: consume tokens + navigate.
      // Dispatch is triggered server-side by the stripe-webhook Edge Function
      // (payment_intent.succeeded → payment_status=paid → status=callingDriver
      //  → dispatch-engine invoked). Flutter never writes payment_status.
      await _consumeTokensAndNavigate(tokensUsed);
      return;
    }

    // ── MBWay / Cash: payment first, then order ───────────────────────────────
    bool success = true;
    String? paymentIntentId;
    PaymentStatus paymentStatus = PaymentStatus.pending;

    switch (_selectedMethod) {
      case PaymentMethod.card:
        break; // handled above
      case PaymentMethod.mbway:
        // Show confirmation dialog that simulates the MBWay push notification.
        // Order is only created after the user "confirms" on the dialog.
        setState(
            () => _isProcessing = false); // release button while dialog is open
        final mbwayConfirmed = await _showMBWayConfirmationDialog(amount);
        if (!mounted) return;
        setState(() => _isProcessing = true);
        success = mbwayConfirmed;
        break;
      case PaymentMethod.cash:
        success = await paymentService.payWithCash(amount);
        break;
    }

    if (!mounted) return;

    if (!success) {
      setState(() => _isProcessing = false);
      messenger.showSnackBar(
        const SnackBar(content: Text('Pagamento não pôde ser concluído.')),
      );
      return;
    }

    // Pagamento local confirmado (MBWay/Cash) — marcar como paid antes de criar order.
    paymentStatus = PaymentStatus.paid;

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
      messenger.showSnackBar(
        const SnackBar(
            content: Text('Não foi possível criar o pedido. Tente novamente.')),
      );
      return;
    }

    await _consumeTokensAndNavigate(tokensUsed);
  }

  /// Consumes loyalty tokens (non-fatal) and navigates back on success.
  Future<void> _consumeTokensAndNavigate(int tokensUsed) async {
    if (tokensUsed > 0) {
      final userId = Supabase.instance.client.auth.currentUser?.id;
      if (userId != null) {
        try {
          final consumed = await Supabase.instance.client.rpc(
                'consume_tokens',
                params: {
                  'p_user_id': userId,
                  'p_amount': tokensUsed,
                },
              ) as bool? ??
              false;
          debugPrint('[Checkout] consume_tokens($tokensUsed) → $consumed');
        } catch (e) {
          // Consumption failure is non-fatal — order already created.
          debugPrint('[Checkout] consume_tokens error (non-fatal): $e');
        }
      }
    }

    if (!mounted) return;
    setState(() => _isProcessing = false);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
          content: Text('Pedido criado. Aguardando confirmação de pagamento.')),
    );
    Navigator.pop(context, true);
  }

  Future<bool> _showMBWayConfirmationDialog(double amount) async {
    return await showDialog<bool>(
          context: context,
          barrierDismissible: false,
          builder: (_) => _MBWayConfirmationDialog(amount: amount),
        ) ??
        false;
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
  });

  final _PaymentOption option;
  final PaymentMethod groupValue;

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

class _MBWayConfirmationDialog extends StatefulWidget {
  const _MBWayConfirmationDialog({required this.amount});
  final double amount;

  @override
  State<_MBWayConfirmationDialog> createState() =>
      _MBWayConfirmationDialogState();
}

class _MBWayConfirmationDialogState extends State<_MBWayConfirmationDialog> {
  static const _timeoutSeconds = 120;
  int _secondsLeft = _timeoutSeconds;
  bool _confirmed = false;

  @override
  void initState() {
    super.initState();
    _startCountdown();
  }

  void _startCountdown() async {
    while (_secondsLeft > 0 && mounted && !_confirmed) {
      await Future.delayed(const Duration(seconds: 1));
      if (mounted && !_confirmed) setState(() => _secondsLeft--);
    }
    if (mounted && !_confirmed) {
      // Timeout — close with false
      Navigator.of(context).pop(false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: Row(
        children: [
          Icon(Icons.phone_iphone, color: Colors.red.shade700),
          const SizedBox(width: 8),
          const Text('Confirmação MBWay'),
        ],
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(height: 4),
          Text(
            'Foi enviado um pedido de pagamento de '
            '€${widget.amount.toStringAsFixed(2)} para o seu telemóvel.',
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 16),
          const CircularProgressIndicator(),
          const SizedBox(height: 12),
          Text(
            'Aguardando confirmação... $_secondsLeft s',
            style: TextStyle(color: Colors.grey.shade600, fontSize: 13),
          ),
          const SizedBox(height: 8),
          Text(
            '(Em desenvolvimento: use o botão abaixo para simular)',
            textAlign: TextAlign.center,
            style: TextStyle(
                fontSize: 11,
                color: Colors.grey.shade400,
                fontStyle: FontStyle.italic),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('Cancelar'),
        ),
        ElevatedButton.icon(
          onPressed: () {
            setState(() => _confirmed = true);
            Navigator.of(context).pop(true);
          },
          icon: const Icon(Icons.check_circle_outline),
          label: const Text('Confirmar no MBWay'),
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.red.shade700,
            foregroundColor: Colors.white,
          ),
        ),
      ],
    );
  }
}
