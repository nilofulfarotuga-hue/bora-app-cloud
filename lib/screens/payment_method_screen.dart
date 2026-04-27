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

  // MBWay phone input (Portuguese mobile, 9 digits — E.164 prefix added before send).
  final TextEditingController _mbwayPhoneController = TextEditingController();

  // ── Token discount state ───────────────────────────────────────────────────
  int _availableTokens = 0;
  bool _useTokens = false;
  bool _tokensLoaded = false;

  @override
  void initState() {
    super.initState();
    _loadTokens();
    // Pre-fill with profile phone (digits-only) if available — user can override.
    final profilePhone = context.read<AuthStore>().currentClient?.phone;
    if (profilePhone != null && profilePhone.isNotEmpty) {
      final digits = profilePhone.replaceAll(RegExp(r'\D'), '');
      _mbwayPhoneController.text =
          digits.startsWith('351') ? digits.substring(3) : digits;
    }
  }

  @override
  void dispose() {
    _mbwayPhoneController.dispose();
    super.dispose();
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
                if (_selectedMethod == PaymentMethod.mbway) ...[
                  const SizedBox(height: 12),
                  Card(
                    elevation: 1,
                    margin: EdgeInsets.zero,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Número MBWay',
                            style: Theme.of(context)
                                .textTheme
                                .titleSmall
                                ?.copyWith(fontWeight: FontWeight.w600),
                          ),
                          const SizedBox(height: 8),
                          TextField(
                            controller: _mbwayPhoneController,
                            keyboardType: TextInputType.phone,
                            maxLength: 9,
                            decoration: const InputDecoration(
                              prefixText: '+351 ',
                              hintText: '912345678',
                              border: OutlineInputBorder(),
                              counterText: '',
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Telemóvel português associado à tua conta MBWay (9 dígitos).',
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.grey.shade600,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
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

  /// Forces exit from payment screen to home root after a post-createOrder
  /// failure. If [orderId] is provided, also calls `client-cancel-order` Edge
  /// Function to mark the orphan order as cancelled in DB (avoids stuck
  /// status='preparing' / payment_status='pending' rows).
  Future<void> _bailOutAndCancel(String? orderId) async {
    if (orderId != null) {
      try {
        await Supabase.instance.client.functions.invoke(
          'client-cancel-order',
          body: {'order_id': orderId, 'reason': 'payment_failed'},
        );
      } catch (e) {
        debugPrint('[Checkout] _bailOutAndCancel error (non-fatal): $e');
      }
    }
    if (!mounted) return;
    Navigator.of(context).popUntil((route) => route.isFirst);
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

    // Pre-flight: MBWay requires a 9-digit Portuguese mobile number.
    if (_selectedMethod == PaymentMethod.mbway) {
      final digits =
          _mbwayPhoneController.text.replaceAll(RegExp(r'\D'), '');
      if (digits.length != 9 ||
          !(digits.startsWith('9') || digits.startsWith('2'))) {
        messenger.showSnackBar(
          const SnackBar(
            content: Text(
                'Introduz um número de telemóvel português válido (9 dígitos).'),
            backgroundColor: Colors.red,
          ),
        );
        return;
      }
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
      // Send `total` (DB column `price`) — the customer-facing price.
      // The Edge Function does ZERO-TOLERANCE validation on this field
      // and applies the 15% pre-auth buffer server-side before charging Stripe.
      // Sending paymentBufferTotal here would fail the equality check.
      final createdOrder = orderStore.orders.first;
      final orderId = createdOrder.id;
      final stripeAmount = createdOrder.total;
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
        await _bailOutAndCancel(orderId);
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
        await _bailOutAndCancel(orderId);
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
        // Real MBWay flow mirrors card: order created first (pending),
        // then Stripe sends push to user's MBWay app, then stripe-webhook
        // resolves payment_status=paid server-side.
        final mbwayOrdered = await cartStore.finishOrder(
          orderStore,
          paymentMethod: PaymentMethod.mbway,
          paymentStatus: PaymentStatus.pending,
          clientPhone: authStore.currentClient?.phone,
          customerName: authStore.currentClient?.name,
          tokensUsed: tokensUsed,
        );
        if (!mounted) return;
        if (!mbwayOrdered) {
          setState(() => _isProcessing = false);
          messenger.showSnackBar(const SnackBar(
            content: Text('Não foi possível criar o pedido. Tente novamente.'),
          ));
          return;
        }
        final mbwayOrder = orderStore.orders.first;
        // Use the user-entered MBWay number (validated as 9 digits in pre-flight).
        // Edge Function handles E.164 conversion (prepends +351).
        final clientPhone =
            _mbwayPhoneController.text.replaceAll(RegExp(r'\D'), '');
        setState(() => _isProcessing = false);
        final piId = await paymentService.initiateMbwayPayment(
          orderId: mbwayOrder.id,
          phone: clientPhone,
        );
        if (!mounted) return;
        if (piId == null) {
          messenger.showSnackBar(const SnackBar(
            content: Text('Não foi possível iniciar o pagamento MBWay.'),
          ));
          await _bailOutAndCancel(mbwayOrder.id);
          return;
        }
        final mbwayPaid = await _showMBWayWaitingDialog(mbwayOrder.id, amount);
        if (!mounted) return;
        if (!mbwayPaid) {
          messenger.showSnackBar(const SnackBar(
            content: Text('Pagamento MBWay não confirmado ou expirou.'),
          ));
          await _bailOutAndCancel(mbwayOrder.id);
          return;
        }
        await _consumeTokensAndNavigate(tokensUsed);
        return;
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

  Future<bool> _showMBWayWaitingDialog(String orderId, double amount) async {
    return await showDialog<bool>(
          context: context,
          barrierDismissible: false,
          builder: (_) =>
              _MBWayWaitingDialog(orderId: orderId, amount: amount),
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

class _MBWayWaitingDialog extends StatefulWidget {
  const _MBWayWaitingDialog({required this.orderId, required this.amount});
  final String orderId;
  final double amount;

  @override
  State<_MBWayWaitingDialog> createState() => _MBWayWaitingDialogState();
}

class _MBWayWaitingDialogState extends State<_MBWayWaitingDialog> {
  static const _timeoutSeconds = 120;
  int _secondsLeft = _timeoutSeconds;
  bool _done = false;

  @override
  void initState() {
    super.initState();
    _countdown();
    _poll();
  }

  void _countdown() async {
    while (_secondsLeft > 0 && mounted && !_done) {
      await Future.delayed(const Duration(seconds: 1));
      if (mounted && !_done) setState(() => _secondsLeft--);
    }
    if (mounted && !_done) Navigator.of(context).pop(false);
  }

  void _poll() async {
    while (mounted && !_done) {
      await Future.delayed(const Duration(seconds: 3));
      if (!mounted || _done) break;
      try {
        final row = await Supabase.instance.client
            .from('orders')
            .select('payment_status')
            .eq('id', widget.orderId)
            .maybeSingle();
        if (row?['payment_status'] == 'paid' && mounted && !_done) {
          _done = true;
          Navigator.of(context).pop(true);
        }
      } catch (_) {}
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
          const Text('Aguarda confirmação MBWay'),
        ],
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(height: 4),
          Text(
            'Enviámos um pedido de €${widget.amount.toStringAsFixed(2)} '
            'para o teu telemóvel.\nAbre o MBWay e confirma.',
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 16),
          const CircularProgressIndicator(),
          const SizedBox(height: 12),
          Text(
            'A aguardar confirmação... $_secondsLeft s',
            style: TextStyle(color: Colors.grey.shade600, fontSize: 13),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () {
            _done = true;
            Navigator.of(context).pop(false);
          },
          child: const Text('Cancelar'),
        ),
      ],
    );
  }
}
