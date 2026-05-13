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

  // BUG #1 frontend (§54 / 2026-05-12) — dívida wallet a cobrar neste checkout
  int _debtSettleCents = 0;

  @override
  void initState() {
    super.initState();
    _loadTokens();
    _loadDebt();
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

  /// BUG #1 frontend (§54 / 2026-05-12) — busca debt_settle_cents do quote authoritative.
  /// Server-side: quote_order_pricing com include_debt:true lê client_wallets.free_balance_cents.
  Future<void> _loadDebt() async {
    try {
      final cartStore = context.read<CartStore>();
      final quote = await cartStore.quoteOrderPricing(
        walletAppliedCents: cartStore.walletAppliedCents,
      );
      if (mounted && quote != null) {
        final debt = (quote['debt_settle_cents'] as num?)?.toInt() ?? 0;
        setState(() => _debtSettleCents = debt);
      }
    } catch (e) {
      debugPrint('[PaymentMethodScreen] _loadDebt error: $e');
    }
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
          _availableTokens = (response as num?)?.toInt() ?? 0;
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
    // BUG 2 (Fase 4 / 2026-04-30): subtrair wallet ao totalToPay.
    // Antes: pricing.customerTotal era mostrado integralmente. Cliente via
    // €148.69 mesmo após aplicar saldo no cart_screen — desalinhado com
    // "Total a pagar (após saldo)" do cart bottom sheet. Stripe cobrava
    // o full total porque payment_method_screen não desconta wallet aqui.
    // Fix: descontar walletApplied a totalToPay para que tokens e Stripe
    // operem sobre o valor REAL após saldo.
    final double walletAppliedEur = cartStore.walletAppliedCents / 100.0;
    final double totalAfterWallet =
        (pricing.customerTotal - walletAppliedEur).clamp(0.0, double.infinity);
    final totalToPay = totalAfterWallet;
    final hasApartmentDelivery = cartStore.apartmentDelivery;
    double baseDeliveryFee = pricing.deliveryFee - pricing.apartmentSurcharge;
    if (baseDeliveryFee < 0) {
      baseDeliveryFee = 0;
    }

    // ── Token discount calculation ─────────────────────────────────────────
    // BR: TOKEN_MAX_DISCOUNT_RATIO = 0.50, TOKEN_VALUE_EUR = 0.005
    // (100 tokens = €0.50 → 1 token = €0.005)
    // BUG 2: maxDiscountEuro calculado sobre totalToPay já SEM wallet.
    final double maxDiscountEuro =
        totalToPay * BRTokens.TOKEN_MAX_DISCOUNT_RATIO;
    final int maxTokensUsable =
        (maxDiscountEuro / BRTokens.TOKEN_VALUE_EUR).floor();
    final int tokensToUse = min(_availableTokens, maxTokensUsable);
    final double tokenDiscount =
        _useTokens ? (tokensToUse * BRTokens.TOKEN_VALUE_EUR) : 0.0;
    final double debtEur = _debtSettleCents / 100.0;
    final double finalPrice =
        (totalToPay - tokenDiscount + debtEur).clamp(0.0, double.infinity);

    // BUG #1 frontend (§54) — CASH disabled se total_pedido + dívida > €40 (limite hardcoded)
    final double totalCashWithDebt = finalPrice; // já inclui dívida + após desconto tokens
    final bool cashBlockedByLimit = totalCashWithDebt > 40.0;

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

                        // BUG 2 fix: linha do saldo aplicado, alinhada com cart_screen.
                        if (walletAppliedEur > 0)
                          _SummaryRow(
                            label: 'Saldo Bora aplicado',
                            value: -walletAppliedEur,
                            isDiscount: true,
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

                        // BUG #1 frontend (§54) — linha dívida anterior (vermelho)
                        if (_debtSettleCents > 0)
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 4),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text('Dívida anterior',
                                    style: TextStyle(color: Colors.red.shade700)),
                                Text('+€${debtEur.toStringAsFixed(2)}',
                                    style: TextStyle(
                                        color: Colors.red.shade700,
                                        fontWeight: FontWeight.w600)),
                              ],
                            ),
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
                Column(
                  children: paymentOptions.map((option) {
                    final bool disabled = option.method == PaymentMethod.cash &&
                        cashBlockedByLimit;
                    return _PaymentOptionTile(
                      option: option,
                      groupValue: _selectedMethod,
                      disabled: disabled,
                      disabledTooltip: disabled
                          ? 'Limite dinheiro €40 excedido. Tens €${debtEur.toStringAsFixed(2)} de dívida + €${(finalPrice - debtEur).toStringAsFixed(2)} deste pedido = €${finalPrice.toStringAsFixed(2)}. Escolhe Cartão ou MBWay.'
                          : null,
                      onChanged: (value) {
                        if (value != null) {
                          setState(() => _selectedMethod = value);
                        }
                      },
                    );
                  }).toList(),
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

    // ── Card: PAYMENT-FIRST flow (BUG 1 / Fase 2, 2026-04-30) ────────────────
    // Order is NOT created until Stripe charge confirms via webhook.
    // No more orphan orders if user closes Stripe sheet / kills app.
    //
    // Steps:
    //   1. cartStore.startCardPaymentDraft → create-payment-intent (NEW mode)
    //      → payment_drafts row + Stripe PI (no order yet).
    //   2. Stripe.presentPaymentSheet(clientSecret) → user pays.
    //   3. Webhook payment_intent.succeeded → finalize-order-from-intent
    //      → create_order(payment_already_confirmed=true) → dispatch.
    //   4. Flutter polls payment_drafts for used_at → fetches order_id.
    if (_selectedMethod == PaymentMethod.card) {
      // Wallet-only path: no Stripe charge needed — fall back to legacy flow.
      final cartTotalAfterWallet =
          cartStore.pricingBreakdown.customerTotal -
              (cartStore.walletAppliedCents / 100.0);
      if (cartTotalAfterWallet <= 0) {
        debugPrint('[Checkout] wallet covers full order — using legacy path');
        // Use old finishOrder flow (cash-like) since no card charge needed.
        final ordered = await cartStore.finishOrder(
          orderStore,
          paymentMethod: PaymentMethod.card,
          paymentStatus: PaymentStatus.paid, // RPC will mark paid (charge_total<=0)
          clientPhone: authStore.currentClient?.phone,
          customerName: authStore.currentClient?.name,
          tokensUsed: tokensUsed,
        );
        if (!mounted) return;
        if (!ordered) {
          setState(() => _isProcessing = false);
          messenger.showSnackBar(SnackBar(
            content: Text(
              '❌ Não foi possível criar o pedido.\n\n'
              'DIAG: ${cartStore.lastFinishOrderDiag}',
            ),
            duration: const Duration(seconds: 15),
            backgroundColor: Colors.red.shade800,
          ));
          return;
        }
        await _consumeTokensAndNavigate(tokensUsed);
        return;
      }

      // Step 1: create draft + Stripe PI (no order yet)
      final draft = await cartStore.startCardPaymentDraft(
        orderStore,
        clientPhone: authStore.currentClient?.phone,
        customerName: authStore.currentClient?.name,
      );
      if (!mounted) return;
      if (draft == null) {
        setState(() => _isProcessing = false);
        messenger.showSnackBar(SnackBar(
          content: Text(
            '❌ Não foi possível iniciar o pagamento.\n\n'
            'DIAG: ${cartStore.lastCardPaymentDiag}',
          ),
          duration: const Duration(seconds: 15),
          backgroundColor: Colors.red.shade800,
        ));
        return;
      }

      final clientSecret = draft['clientSecret'] as String;
      final draftId = draft['draftId'] as String;

      // Step 2: present Stripe sheet
      try {
        await paymentService.processPayment(clientSecret);
      } on StripeException catch (e) {
        if (!mounted) return;
        setState(() => _isProcessing = false);
        debugPrint(
            '[Checkout] card cancelled/declined: ${e.error.localizedMessage}');
        // BUG 1 fix: NO order to clean up — webhook deletes draft on
        // payment_intent.canceled / payment_failed. App-side: just dismiss.
        messenger.showSnackBar(
          const SnackBar(content: Text('Pagamento cancelado. Sem cobrança.')),
        );
        return;
      } catch (e) {
        if (!mounted) return;
        setState(() => _isProcessing = false);
        debugPrint('[Checkout] card payment error: $e');
        messenger.showSnackBar(
          const SnackBar(
            content:
                Text('Pagamento por cartão indisponível. Tente MBWay ou dinheiro.'),
            duration: Duration(seconds: 5),
          ),
        );
        return;
      }

      // Step 3: wait for webhook to create order via finalize-order-from-intent
      messenger.showSnackBar(
        const SnackBar(
          content: Text('Pagamento confirmado. A criar pedido...'),
          duration: Duration(seconds: 4),
        ),
      );
      // Capture navigator BEFORE await to avoid use_build_context_synchronously.
      final navigator = Navigator.of(context);
      final orderId = await orderStore.waitForOrderFromDraft(draftId);
      if (!mounted) return;
      if (orderId == null) {
        setState(() => _isProcessing = false);
        messenger.showSnackBar(const SnackBar(
          content: Text(
              'Pagamento confirmado mas a criação do pedido demorou. Verifica o histórico em alguns segundos.'),
          duration: Duration(seconds: 6),
        ));
        // Clear cart anyway — order will appear via realtime when webhook completes.
        cartStore.clearCart();
        navigator.popUntil((route) => route.isFirst);
        return;
      }

      // Step 4: success — clear cart + consume tokens + navigate
      cartStore.clearCart();
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
          messenger.showSnackBar(SnackBar(
            content: Text(
              '❌ Não foi possível criar o pedido.\n\n'
              'DIAG: ${cartStore.lastFinishOrderDiag}',
            ),
            duration: const Duration(seconds: 15),
            backgroundColor: Colors.red.shade800,
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
          messenger.showSnackBar(SnackBar(
            content: const Text(
              '❌ Não foi possível iniciar o pagamento MBWay.\n\n'
              'DIAG: paymentService.initiateMbwayPayment retornou null',
            ),
            duration: const Duration(seconds: 15),
            backgroundColor: Colors.red.shade800,
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
      messenger.showSnackBar(SnackBar(
        content: Text(
          '❌ Não foi possível criar o pedido.\n\n'
          'DIAG: ${cartStore.lastFinishOrderDiag}',
        ),
        duration: const Duration(seconds: 15),
        backgroundColor: Colors.red.shade800,
      ));
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
    required this.onChanged,
    this.disabled = false,
    this.disabledTooltip,
  });

  final _PaymentOption option;
  final PaymentMethod groupValue;
  final ValueChanged<PaymentMethod?> onChanged;
  final bool disabled;
  final String? disabledTooltip;

  @override
  Widget build(BuildContext context) {
    final isSelected = option.method == groupValue;
    final card = Opacity(
      opacity: disabled ? 0.4 : 1.0,
      child: Card(
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
          onChanged: disabled ? null : onChanged,
          title: Text(option.title),
          subtitle: Text(option.subtitle),
          secondary: Icon(option.icon),
        ),
      ),
    );
    if (disabled && disabledTooltip != null) {
      return Tooltip(
        message: disabledTooltip!,
        triggerMode: TooltipTriggerMode.tap,
        showDuration: const Duration(seconds: 6),
        child: card,
      );
    }
    return card;
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
