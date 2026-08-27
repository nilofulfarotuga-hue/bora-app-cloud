import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../auth/auth_store.dart';
import '../config/app_colors.dart';
import '../config/app_spacing.dart';
import '../config/business_rules.dart' show BRTokens;
import '../models/order_model.dart';
import '../services/pricing_service.dart';
import '../stores/cart_store.dart';
import '../stores/order_store.dart';
import 'package:flutter_stripe/flutter_stripe.dart' show StripeException, FailureCode;

import '../models/saved_card.dart';
import '../services/card_wallet_service.dart';
import '../services/payment_service.dart';
import '../widgets/bora/bora_screen_app_bar.dart';
import '../widgets/card_mandate_notice.dart';
import '../widgets/customer_note_field.dart';
import '../widgets/unified_checkout_button.dart';

/// Mensagem única do bloqueio de "Em breve" no pagamento (PT-PT).
const String _kComingSoonPaymentMessage =
    'Esta loja ainda está a ser preparada. Em breve poderá finalizar o seu pedido.';

/// Substitui o botão de pagar quando a loja está em "Em breve".
///
/// O cliente já pôde escolher tudo; é aqui — e só aqui — que para.
class _ComingSoonPaymentNotice extends StatelessWidget {
  const _ComingSoonPaymentNotice({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: _kComingSoonPaymentMessage,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(Radii.lg),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(
              horizontal: Spacing.lg, vertical: Spacing.lg),
          decoration: BoxDecoration(
            color: AppColors.accent.withValues(alpha: 0.10),
            borderRadius: BorderRadius.circular(Radii.lg),
            border: Border.all(color: AppColors.accent),
          ),
          child: Row(
            children: [
              const Icon(Icons.schedule, color: AppColors.accent),
              const SizedBox(width: Spacing.md),
              const Expanded(
                child: Text(
                  _kComingSoonPaymentMessage,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    height: 1.35,
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

  // C1 (2026-05-31) — nota opcional do cliente para o estafeta (customerNotes).
  final TextEditingController _notesController = TextEditingController();

  // ── Token discount state ───────────────────────────────────────────────────
  int _availableTokens = 0;
  bool _tokensLoaded = false;

  /// Adendo2.3 (2026-08-16, pedido do Danilo): SLIDER — o cliente escolhe
  /// QUANTOS tokens usar (0..teto). O teto (token_payment_max_pct) é o fim
  /// físico do slider — intransponível por construção.
  int _tokensSelected = 0;

  /// Valor de 1 token em EUR — lido de token_value_cents_x100 (50 = €0,005).
  /// NUNCA cravado; fallback = constante das BR (espelho da DB).
  double _tokenValueEur = BRTokens.TOKEN_VALUE_EUR;

  // B3a (2026-06-12): pct máximo do pedido pagável em tokens — lido da DB
  // (platform_settings.token_payment_max_pct) com fallback 50 (BR §4.3).
  int _tokenMaxPct = 50;

  // BUG #1 frontend (§54 / 2026-05-12) — dívida wallet a cobrar neste checkout
  int _debtSettleCents = 0;

  // 2026-05-14 — cartoes guardados (Stripe Customer).
  List<SavedCard> _savedCards = const [];
  String? _selectedSavedPmId; // null = "pagar com novo cartao".
  bool _loadingCards = false;

  @override
  void initState() {
    super.initState();
    // M-E (2026-06-10): alinhar o "Total a pagar" com a cobrança real —
    // atualiza a distância para a ROTA Google (a mesma que o create_order
    // usa). O watch<CartStore> do build refaz o total quando chegar.
    context.read<CartStore>().refreshRouteDistance();
    _loadTokens();
    _loadDebt();
    _loadSavedCards();
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
    _notesController.dispose();
    super.dispose();
  }

  /// C1 — nota opcional do cliente para o estafeta (null se vazia).
  /// Festas: a data agendada entra SEMPRE à cabeça das observações — assim a
  /// loja vê a data mesmo que a gravação de scheduled_for falhe (o cartão
  /// cria a ordem no webhook, sem o cliente presente).
  String? get _orderNote {
    final t = _notesController.text.trim();
    final quando = context.read<CartStore>().festasQuando;
    if (quando != null) {
      final dia = '${quando.day.toString().padLeft(2, '0')}/'
          '${quando.month.toString().padLeft(2, '0')}';
      final hora = '${quando.hour.toString().padLeft(2, '0')}:00';
      final marca = 'Encomenda para $dia às $hora';
      return t.isEmpty ? marca : '$marca · $t';
    }
    return t.isEmpty ? null : t;
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

  /// 2026-05-14 — busca cartoes guardados via Edge Fn list-saved-cards.
  /// Pre-selecciona o cartao default (is_default=true) se existir.
  ///
  /// 2026-07-21 (Carteira Unica, Parte 2) — passa pela CardWalletService para
  /// respeitar o cartao que o cliente marcou como principal em "Meus Cartoes";
  /// so na ausencia dessa escolha e que vale o predefinido do Stripe.
  Future<void> _loadSavedCards() async {
    if (kIsWeb) return;
    setState(() => _loadingCards = true);
    try {
      final cards = await CardWalletService.instance.listCards();
      if (!mounted) return;
      setState(() {
        _savedCards = cards;
        _loadingCards = false;
        _selectedSavedPmId = cards
            .firstWhere(
              (c) => c.isDefault,
              orElse: () => cards.isNotEmpty
                  ? cards.first
                  : const SavedCard(id: '', brand: '', last4: ''),
            )
            .id;
        if (_selectedSavedPmId == '') _selectedSavedPmId = null;
      });
    } catch (e) {
      debugPrint('[PaymentMethodScreen] _loadSavedCards error: $e');
      if (mounted) setState(() => _loadingCards = false);
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
      // B3a (2026-06-12): pct do cap de tokens vem da DB (não hardcode).
      // get_setting devolve o jsonb cru (num) — fallback 50 se falhar.
      int pct = _tokenMaxPct;
      try {
        final pctRes = await Supabase.instance.client.rpc(
          'get_setting',
          params: {'p_key': 'token_payment_max_pct'},
        );
        if (pctRes is num) {
          pct = pctRes.toInt();
        } else if (pctRes is String) {
          pct = int.tryParse(pctRes) ?? pct;
        }
      } catch (e) {
        debugPrint('[PaymentMethodScreen] token_payment_max_pct fallback: $e');
      }
      // Adendo2.3: conversão lida das settings (token_value_cents_x100=50
      // ⇒ 1 token = €0,005), nunca cravada.
      double tokenValue = _tokenValueEur;
      try {
        final valRes = await Supabase.instance.client.rpc(
          'get_setting',
          params: {'p_key': 'token_value_cents_x100'},
        );
        final raw = valRes is num
            ? valRes.toDouble()
            : double.tryParse('${valRes ?? ''}'.replaceAll('"', ''));
        if (raw != null && raw > 0) tokenValue = raw / 100.0 / 100.0;
      } catch (e) {
        debugPrint('[PaymentMethodScreen] token_value fallback: $e');
      }
      if (mounted) {
        setState(() {
          _availableTokens = (response as num?)?.toInt() ?? 0;
          _tokenMaxPct = pct;
          _tokenValueEur = tokenValue;
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
    // FAVORES (errand) — total e breakdown vêm do quote do favor (base_fee/
    // home/km/compra), NÃO do pricingBreakdown genérico (entrega €2,50 + 15%).
    final bool isErrand = cartStore.serviceType == OrderServiceType.errand;
    final Map<String, dynamic>? errandQuote = cartStore.errandSession?.quote;
    double errVal(String k) => (errandQuote?[k] as num?)?.toDouble() ?? 0.0;
    final double errBase = errVal('base_fee');
    final double errHome = errVal('home_stop_fee');
    final double errKm = errVal('km_extra_fee');
    final double errPurchase = errVal('purchase_estimate');
    final double errandTotal =
        (errandQuote?['customer_total'] as num?)?.toDouble() ??
            pricing.customerTotal;
    // Taxa de pedido pequeno (2026-08-27): parcela propria somada ao total.
    // Nao se aplica a favores (errand), que tem quote proprio.
    final double smallOrderFee = isErrand ? 0.0 : cartStore.smallOrderFee;
    final double baseCustomerTotal =
        (isErrand ? errandTotal : pricing.customerTotal) + smallOrderFee;
    final double totalAfterWallet =
        (baseCustomerTotal - walletAppliedEur).clamp(0.0, double.infinity);
    final totalToPay = totalAfterWallet;
    final hasApartmentDelivery = cartStore.apartmentDelivery;
    double baseDeliveryFee = pricing.deliveryFee - pricing.apartmentSurcharge;
    if (baseDeliveryFee < 0) {
      baseDeliveryFee = 0;
    }

    // ── Token discount calculation ─────────────────────────────────────────
    // B3a (2026-06-12): pct lido da DB (token_payment_max_pct, fallback 50)
    // em vez do hardcode BRTokens.TOKEN_MAX_DISCOUNT_RATIO.
    // TOKEN_VALUE_EUR = 0.005 (100 tokens = €0.50 → 1 token = €0.005)
    // BUG 2: maxDiscountEuro calculado sobre totalToPay já SEM wallet.
    final double maxDiscountEuro = totalToPay * (_tokenMaxPct / 100.0);
    final int maxTokensUsable = (maxDiscountEuro / _tokenValueEur).floor();
    // FAVORES (§55.3) — cliente não usa/ganha tokens em favores → 0.
    final int tokensToUse =
        isErrand ? 0 : min(_availableTokens, maxTokensUsable);
    // Adendo2.3: o slider decide QUANTOS (0..tokensToUse) — teto físico.
    final int tokensChosen = _tokensSelected.clamp(0, tokensToUse);
    final double tokenDiscount = tokensChosen * _tokenValueEur;
    final double debtEur = _debtSettleCents / 100.0;
    final double finalPrice =
        (totalToPay - tokenDiscount + debtEur).clamp(0.0, double.infinity);

    // BUG #1 frontend (§54) — CASH disabled se total_pedido + dívida > €40 (limite hardcoded)
    // BUG fix pós-takeaway (2026-05-14): limite €40 NÃO se aplica a takeaway —
    // "Pagar na loja" é gerido pelo parceiro, sem estafeta a cobrar dinheiro.
    final double totalCashWithDebt = finalPrice; // já inclui dívida + após desconto tokens
    final bool cashBlockedByLimit =
        !cartStore.isTakeaway && totalCashWithDebt > 40.0;

    // BUG fix pós-takeaway (2026-05-14): em takeaway, "Dinheiro" passa a
    // "Pagar na loja" (parceiro recebe directamente). Valor enviado ao
    // servidor mantém-se 'cash' — só muda label/subtitle na UI.
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
      _PaymentOption(
        method: PaymentMethod.cash,
        title: cartStore.isTakeaway ? 'Pagar na loja' : 'Dinheiro',
        subtitle: cartStore.isTakeaway
            ? 'Pague diretamente ao parceiro ao levantar.'
            : 'Pague diretamente ao estafeta na entrega.',
        icon: Icons.payments,
      ),
    ];

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: const BoraScreenAppBar(title: 'Pagamento'),
      body: Column(
        children: [
          Expanded(
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Container(
                  decoration: BoxDecoration(
                    color: AppColors.card,
                    borderRadius: BorderRadius.circular(Radii.lg),
                    boxShadow: AppColors.shadowCard,
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
                        // FAVORES (errand) — breakdown do favor: SEM subtotal €0,
                        // SEM entrega €2,50, SEM taxa de serviço/15%.
                        if (isErrand) ...[
                          _SummaryRow(label: 'Favor', value: errBase),
                          if (errHome > 0)
                            _SummaryRow(
                                label: 'Paragem em casa', value: errHome),
                          if (errKm > 0)
                            _SummaryRow(
                                label: 'Distância extra', value: errKm),
                          if (errPurchase > 0)
                            _SummaryRow(
                                label: 'Compra estimada na loja',
                                value: errPurchase),
                        ],
                        if (!isErrand)
                          _SummaryRow(
                              label: 'Subtotal', value: pricing.subtotal),
                        if (!isErrand && pricing.serviceFee > 0)
                          _SummaryRow(
                              label: 'Taxas', value: pricing.serviceFee),
                        if (!isErrand)
                          _SummaryRow(
                          label: 'Entrega',
                          value: baseDeliveryFee,
                          subtitle: () {
                            // Taxa base e €/km derivadas do PricingService (fonte
                            // única de verdade) — não hardcodear 6/2.50/0.50.
                            final st = cartStore.serviceType;
                            final double baseFee =
                                PricingService.calculateBreakdown(
                              serviceType: st,
                              subtotal: 0,
                              distanceKm: 4,
                            ).deliveryFee;
                            final double perKm =
                                PricingService.calculateBreakdown(
                                      serviceType: st,
                                      subtotal: 0,
                                      distanceKm: 5,
                                    ).deliveryFee -
                                    baseFee;
                            final double d = pricing.distanceKm;
                            final double extra = d > 4.0 ? d - 4.0 : 0.0;
                            final bool isPackage =
                                st == OrderServiceType.sendPackage ||
                                    st == OrderServiceType.carryGroceries;
                            // Encomenda/Levar compras: mostra SEMPRE a composição
                            // para o cliente perceber o acréscimo acima de 4 km.
                            if (isPackage) {
                              final base =
                                  'Inclui €${baseFee.toStringAsFixed(2)} de taxa base (até 4 km)';
                              if (extra > 0) {
                                return '$base + €${perKm.toStringAsFixed(2)}/km acima de 4 km '
                                    '(€${(perKm * extra).toStringAsFixed(2)} por ${extra.toStringAsFixed(1)} km extra).';
                              }
                              return '$base + €${perKm.toStringAsFixed(2)}/km acima de 4 km.';
                            }
                            if (extra <= 0) return null;
                            return '€${baseFee.toStringAsFixed(2)} base + €${(perKm * extra).toStringAsFixed(2)} por ${extra.toStringAsFixed(1)}km extra';
                          }(),
                        ),
                        // B1 (2026-06-11): linha do saco visível também aqui
                        // (€0,30 restaurante / €0,10×saco mercado) — era
                        // cobrada pelo servidor mas ausente deste resumo.
                        if (pricing.bagFee > 0)
                          _SummaryRow(
                              label: 'Saco para viagem',
                              value: pricing.bagFee),
                        if (smallOrderFee > 0)
                          _SummaryRow(
                              label: 'Taxa de pedido pequeno',
                              value: smallOrderFee),
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
                                const Icon(Icons.apartment,
                                    color: AppColors.accent, size: 20),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    'Entrega em apartamento solicitada — bónus +€1 para o estafeta.',
                                    style: Theme.of(context)
                                        .textTheme
                                        .bodySmall
                                        ?.copyWith(
                                          fontWeight: FontWeight.w600,
                                          color: AppColors.accentDark,
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
                            // Adendo2.3 (2026-08-16): SLIDER — o cliente
                            // escolhe QUANTO usar; o teto ($_tokenMaxPct%) é o
                            // fim físico do trilho (intransponível) com marca
                            // escura no limite.
                            child: Padding(
                              padding:
                                  const EdgeInsets.fromLTRB(12, 10, 12, 2),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      const Icon(Icons.monetization_on,
                                          color: Colors.amber, size: 20),
                                      const SizedBox(width: 8),
                                      const Expanded(
                                        child: Text(
                                          'Bora Tokens',
                                          style: TextStyle(
                                              fontWeight: FontWeight.w600,
                                              fontSize: 14),
                                        ),
                                      ),
                                      Text(
                                        tokensChosen > 0
                                            ? '$tokensChosen tokens · -€${tokenDiscount.toStringAsFixed(2)}'
                                            : 'não usar',
                                        style: TextStyle(
                                            fontSize: 13,
                                            fontWeight: FontWeight.w700,
                                            color: Colors.amber.shade900),
                                      ),
                                    ],
                                  ),
                                  Text(
                                    'Tens €${(_availableTokens * _tokenValueEur).toStringAsFixed(2)} em tokens — '
                                    'podes usar até €${(tokensToUse * _tokenValueEur).toStringAsFixed(2)} '
                                    'neste pedido (máx. $_tokenMaxPct%).',
                                    style: TextStyle(
                                        fontSize: 12,
                                        color: Colors.amber.shade800),
                                  ),
                                  Row(
                                    children: [
                                      Expanded(
                                        child: SliderTheme(
                                          data: SliderTheme.of(context)
                                              .copyWith(
                                            activeTrackColor:
                                                Colors.amber.shade700,
                                            thumbColor: Colors.amber.shade800,
                                            inactiveTrackColor:
                                                Colors.amber.shade100,
                                          ),
                                          child: Slider(
                                            value: tokensChosen.toDouble(),
                                            max: tokensToUse.toDouble(),
                                            divisions:
                                                tokensToUse > 0 ? 20 : null,
                                            onChanged: tokensToUse > 0
                                                ? (v) => setState(() =>
                                                    _tokensSelected =
                                                        v.round())
                                                : null,
                                          ),
                                        ),
                                      ),
                                      // marca escura INTRANSPONÍVEL do teto
                                      Container(
                                        width: 4,
                                        height: 22,
                                        decoration: BoxDecoration(
                                          color: Colors.brown.shade800,
                                          borderRadius:
                                              BorderRadius.circular(2),
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ] else if (_tokensLoaded && _availableTokens == 0)
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 4),
                            child: Row(
                              children: [
                                const Icon(Icons.monetization_on,
                                    size: 14, color: AppColors.textSubtle),
                                const SizedBox(width: 6),
                                const Text(
                                  'Sem tokens disponíveis',
                                  style: TextStyle(
                                      fontSize: 12,
                                      color: AppColors.textSubtle),
                                ),
                              ],
                            ),
                          ),

                        const Divider(height: 24),

                        // Discount row (only when tokens active)
                        if (tokenDiscount > 0)
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
                                const Text('Dívida anterior',
                                    style: TextStyle(color: AppColors.error)),
                                Text('+€${debtEur.toStringAsFixed(2)}',
                                    style: const TextStyle(
                                        color: AppColors.error,
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
                // C1 — nota opcional para o estafeta (liga ao customerNotes).
                CustomerNoteField(controller: _notesController),
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
                // FAVORES (§55.4) — clareza cartão (garantia ×1,2) vs dinheiro.
                if (isErrand && errPurchase > 0) ...[
                  const SizedBox(height: 8),
                  _ErrandPaymentHint(
                    method: _selectedMethod,
                    estimate: errPurchase,
                  ),
                ],
                if (_selectedMethod == PaymentMethod.card &&
                    (_savedCards.isNotEmpty || _loadingCards)) ...[
                  const SizedBox(height: 12),
                  Container(
                    decoration: BoxDecoration(
                      color: AppColors.card,
                      borderRadius: BorderRadius.circular(Radii.lg),
                      boxShadow: AppColors.shadowCard,
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(8),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Padding(
                            padding: const EdgeInsets.fromLTRB(8, 8, 8, 4),
                            child: Text(
                              'Cartões guardados',
                              style: Theme.of(context)
                                  .textTheme
                                  .titleSmall
                                  ?.copyWith(fontWeight: FontWeight.w600),
                            ),
                          ),
                          if (_loadingCards)
                            const Padding(
                              padding: EdgeInsets.all(16),
                              child: Center(
                                child: SizedBox(
                                  height: 18,
                                  width: 18,
                                  child:
                                      CircularProgressIndicator(strokeWidth: 2),
                                ),
                              ),
                            )
                          else ...[
                            for (final card in _savedCards)
                              RadioListTile<String?>(
                                value: card.id,
                                groupValue: _selectedSavedPmId,
                                onChanged: (v) =>
                                    setState(() => _selectedSavedPmId = v),
                                title: Text(
                                  '${card.prettyBrand} •••• ${card.last4}',
                                ),
                                subtitle: Text(
                                  card.isDefault
                                      ? '${card.prettyExpiry}  ·  predefinido'
                                      : card.prettyExpiry,
                                ),
                                dense: true,
                              ),
                            RadioListTile<String?>(
                              value: null,
                              groupValue: _selectedSavedPmId,
                              onChanged: (v) =>
                                  setState(() => _selectedSavedPmId = v),
                              title: const Text('+ Pagar com novo cartão'),
                              dense: true,
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                ],
                // Mandato PSD2 — fora do bloco acima de proposito: esse so
                // aparece quando JA ha cartoes guardados, e a frase e para
                // quem ainda nao tem nenhum. O widget esconde-se sozinho.
                if (_selectedMethod == PaymentMethod.card)
                  const CardMandateNotice(),
                if (_selectedMethod == PaymentMethod.mbway) ...[
                  const SizedBox(height: 12),
                  Container(
                    decoration: BoxDecoration(
                      color: AppColors.card,
                      borderRadius: BorderRadius.circular(Radii.lg),
                      boxShadow: AppColors.shadowCard,
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
                          const Text(
                            'Telemóvel português associado à tua conta MBWay (9 dígitos).',
                            style: TextStyle(
                              fontSize: 12,
                              color: AppColors.textSecondary,
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
            // Carteira Unica, Parte 2 (2026-07-21): o botao passou a ser o
            // UnifiedCheckoutButton — pede digital/rosto antes de cobrar
            // quando o pagamento vai num cartao guardado (1 toque, sem
            // PaymentSheet pelo meio). showSavedCard=false porque este ecra ja
            // tem a lista de cartoes guardados acima; useOverride=true porque
            // a escolha feita nessa lista manda sobre o padrao da carteira.
            // Loja em "Em breve" (2026-08-05): o cliente percorre tudo — loja,
            // opcoes, carrinho, checkout — e so e travado AQUI. O servidor
            // rejeita na mesma (trigger `trg_payment_draft_coming_soon`), isto
            // e a camada de UI para ele perceber porque nao consegue avancar.
            child: context.watch<CartStore>().vendorComingSoon
                ? _ComingSoonPaymentNotice(
                    onTap: () => ScaffoldMessenger.of(context)
                      ..hideCurrentSnackBar()
                      ..showSnackBar(const SnackBar(
                        content: Text(_kComingSoonPaymentMessage),
                        duration: Duration(seconds: 4),
                      )),
                  )
                : UnifiedCheckoutButton(
                    label: 'Confirmar pagamento',
                    amount: finalPrice,
                    busy: _isProcessing,
                    showSavedCard: false,
                    useOverride: true,
                    savedPmIdOverride: _selectedMethod == PaymentMethod.card
                        ? _selectedSavedPmId
                        : null,
                    onPay: (_) => _confirmPayment(
                      context,
                      finalPrice,
                      tokensUsed: tokensChosen,
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  /// B1 (2026-06-12): traduz códigos de erro conhecidos da RPC create_order
  /// para PT-PT. Fallback = mensagem genérica existente.
  String _createOrderErrorMessage(OrderStore orderStore) {
    final err = orderStore.lastCreateOrderError ?? '';
    if (err.contains('delivery_distance_exceeded')) {
      final m = RegExp(r'>\s*(\d+(?:[.,]\d+)?)\s*km').firstMatch(err);
      final max = m?.group(1) ?? '15';
      return 'Entrega não disponível. Máximo $max km.';
    }
    // B3a (2026-06-12): cap server-side de tokens excedido.
    if (err.contains('token_cap_exceeded')) {
      return 'O desconto em Bora Tokens excede o máximo de '
          '$_tokenMaxPct% do pedido.';
    }
    return 'Não foi possível criar o pedido. Tente novamente.';
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

  /// Parte 3 (rodada 2) — grava a paragem em casa do favor (morada + coords +
  /// dinheiro a pegar + perna de volta) via RPC NÃO-financeira, SEM tocar no
  /// create_order (checkout que cobra). Best-effort — falha não quebra o checkout.
  Future<void> _persistErrandHomeStop(CartStore cart, String orderId) async {
    final es = cart.errandSession;
    final home = es?.home;
    if (es == null || home == null) return;
    try {
      await Supabase.instance.client.rpc('errand_set_home_stop', params: {
        'p_order_id': orderId,
        'p_address': es.homeStopAddress,
        'p_lat': home.latitude,
        'p_lng': home.longitude,
        'p_cash_cents': es.homeStopCashCents,
        'p_return_leg': es.returnLeg,
      });
    } catch (e) {
      debugPrint('[Checkout] errand_set_home_stop failed (non-fatal): $e');
    }
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
    // F4 (2026-08-16): era o ÚNICO await do funil do cartão fora de try/catch —
    // se lançasse (refresh de sessão falhado), o handler morria em silêncio com
    // _isProcessing preso e a Edge nunca era chamada (zero draft, zero PI).
    try {
      await authStore.ensureSessionForOrder();
    } catch (e) {
      debugPrint('[bora-pay] ensureSessionForOrder falhou: $e');
      if (!mounted) return;
      setState(() => _isProcessing = false);
      messenger.showSnackBar(const SnackBar(
          content: Text(
              'Erro de sessão. Verifica a ligação à internet e tenta de novo.'),
          backgroundColor: Colors.red));
      return;
    }

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
      // A taxa de pedido pequeno conta para saber se o saldo cobre TUDO —
      // senao um carrinho com taxa cairia no caminho legacy sem cobrar nada.
      final cartTotalAfterWallet =
          cartStore.pricingBreakdown.customerTotal +
              cartStore.smallOrderFee -
              (cartStore.walletAppliedCents / 100.0);
      if (cartTotalAfterWallet <= 0) {
        debugPrint('[Checkout] wallet covers full order — using legacy path');
        // Use old finishOrder flow (cash-like) since no card charge needed.
        final bool ordered;
        try {
          ordered = await cartStore.finishOrder(
            orderStore,
            paymentMethod: PaymentMethod.card,
            paymentStatus: PaymentStatus.paid, // RPC will mark paid (charge_total<=0)
            clientPhone: authStore.currentClient?.phone,
            customerName: authStore.currentClient?.name,
            notes: _orderNote,
            tokensUsed: tokensUsed,
          );
        } catch (e) {
          debugPrint('[bora-pay] wallet-only finishOrder error: $e');
          if (!mounted) return;
          setState(() => _isProcessing = false);
          messenger.showSnackBar(const SnackBar(
              content: Text('Erro ao criar o pedido. Verifica a ligação e tenta de novo.'),
              backgroundColor: Colors.red));
          return;
        }
        if (!mounted) return;
        if (!ordered) {
          setState(() => _isProcessing = false);
          messenger.showSnackBar(SnackBar(
              content: Text(_createOrderErrorMessage(orderStore))));
          return;
        }
        await _consumeTokensAndNavigate(tokensUsed);
        return;
      }

      // Step 1: create draft + Stripe PI (no order yet).
      // 2026-05-14 — passa _selectedSavedPmId; Edge Fn v28 cria PI com
      // confirm:true off_session quando saved_pm_id presente.
      // 2026-06-04 — wrapped em try/catch: se Edge Fn create-payment-intent
      // lançar (timeout/rede/JWT), _isProcessing ficava preso → spinner infinito.
      final Map<String, dynamic>? draft;
      try {
        draft = await cartStore.startCardPaymentDraft(
          orderStore,
          clientPhone: authStore.currentClient?.phone,
          customerName: authStore.currentClient?.name,
          savedPmId: _selectedSavedPmId,
        );
      } catch (e) {
        // F4 (2026-08-16): log SEMPRE (era só kDebugMode — invisível no build
        // release do telemóvel) + erro real truncado no ecrã p/ diagnóstico.
        debugPrint('[bora-pay] startCardPaymentDraft error: $e');
        if (!mounted) return;
        setState(() => _isProcessing = false);
        final detail = e.toString();
        messenger.showSnackBar(SnackBar(
            content: Text(
                'Erro ao iniciar pagamento. Verifica a ligação e tenta de novo.\n'
                '(${detail.length > 120 ? detail.substring(0, 120) : detail})'),
            backgroundColor: Colors.red));
        return;
      }
      if (!mounted) return;
      if (draft == null) {
        setState(() => _isProcessing = false);
        messenger.showSnackBar(const SnackBar(
            content:
                Text('Não foi possível iniciar o pagamento. Tente novamente.')));
        return;
      }

      final clientSecret = draft['clientSecret'] as String;
      final draftId = draft['draftId'] as String;
      final requiresAction = (draft['requiresAction'] as bool?) ?? false;

      // Step 2: confirm payment.
      // - Cartao guardado: PI ja foi confirm:true off_session server-side. So
      //   abrimos sheet se requiresAction=true (3DS challenge).
      // - Cartao novo: fluxo PaymentSheet normal (recolhe nome via
      //   billingDetailsCollectionConfiguration).
      try {
        if (_selectedSavedPmId != null) {
          final ok = await paymentService.confirmSavedCardPayment(
            clientSecret: clientSecret,
            requiresAction: requiresAction,
          );
          if (!ok) {
            if (!mounted) return;
            setState(() => _isProcessing = false);
            messenger.showSnackBar(const SnackBar(
                content: Text(
                    'Pagamento com cartão guardado não foi concluído. Tenta de novo ou usa um cartão diferente.')));
            return;
          }
        } else {
          await paymentService.processPayment(clientSecret);
        }
      } on StripeException catch (e) {
        if (!mounted) return;
        setState(() => _isProcessing = false);
        debugPrint(
            '[Checkout] card cancelled/declined: ${e.error.localizedMessage}');
        // BUG 1 fix: NO order to clean up — webhook deletes draft on
        // payment_intent.canceled / payment_failed. App-side: just dismiss.
        if (e.error.code == FailureCode.Canceled) {
          messenger.showSnackBar(
            const SnackBar(content: Text('Pagamento cancelado. Sem cobrança.')),
          );
        } else {
          messenger.showSnackBar(
            SnackBar(
              content: Text(
                  e.error.localizedMessage ?? 'Pagamento recusado. Tenta de novo.'),
              backgroundColor: Colors.red,
            ),
          );
        }
        return;
      } catch (e) {
        if (!mounted) return;
        setState(() => _isProcessing = false);
        // F4 (2026-08-16): tag estável p/ `adb logcat | grep bora-pay` + erro
        // real truncado no ecrã — o screenshot fecha o diagnóstico.
        debugPrint('[bora-pay] card payment error: $e');
        final detail = e.toString();
        messenger.showSnackBar(
          SnackBar(
            content: Text(
                'Pagamento por cartão indisponível. Tente MBWay ou dinheiro.\n'
                '(${detail.length > 120 ? detail.substring(0, 120) : detail})'),
            duration: const Duration(seconds: 6),
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
      // 8.1 — persistir a foto do favor (errand via cartão) antes de limpar.
      final reqPhoto = cartStore.errandRequestPhotoUrl;
      if (reqPhoto != null) {
        try {
          await Supabase.instance.client.rpc(
            'client_set_errand_request_photo',
            params: {'p_order_id': orderId, 'p_url': reqPhoto},
          );
        } catch (e) {
          debugPrint('[Checkout] set errand photo failed (non-fatal): $e');
        }
      }
      // Parte 3 (rodada 2) — persistir a paragem em casa (morada+coords+cash+volta)
      // ANTES de clearCart (que apaga a errandSession).
      await _persistErrandHomeStop(cartStore, orderId);
      // Festas (2026-08-25) — a ordem do cartão nasce no webhook sem a data;
      // gravá-la agora pela RPC dedicada (valida dono/categoria/dia seguinte).
      // Se falhar, a data já segue nas observações do pedido.
      final quandoFesta = cartStore.festasQuando;
      if (cartStore.vendorIsFestas && quandoFesta != null) {
        try {
          await Supabase.instance.client.rpc(
            'festas_set_schedule',
            params: {
              'p_order_id': orderId,
              'p_scheduled_for': quandoFesta.toUtc().toIso8601String(),
            },
          );
        } catch (e) {
          debugPrint('[Checkout] festas_set_schedule falhou (non-fatal): $e');
        }
      }
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
        // v21 (2026-05-15) — server-side confirmation flow:
        //   1. cartStore.finishOrder → pedido criado em DB (payment_status=pending)
        //   2. paymentService.initiateMbwayPayment → Edge Fn create-mbway-payment-intent
        //      confirma o PaymentIntent server-side com billing_details.phone.
        //      Stripe envia push à app MBWay IMEDIATAMENTE e devolve paymentIntentId.
        //   3. _showMBWayWaitingDialog → ecrã com countdown 120s + poll a cada 3s
        //      a orders.payment_status até detectar 'paid' (webhook resolveu).
        //   4. Se utilizador cancela ou expira → _bailOutAndCancel (reason=payment_failed
        //      → client-cancel-order v20 isenta de taxa de cancelamento).
        final mbwayOrdered = await cartStore.finishOrder(
          orderStore,
          paymentMethod: PaymentMethod.mbway,
          paymentStatus: PaymentStatus.pending,
          clientPhone: authStore.currentClient?.phone,
          customerName: authStore.currentClient?.name,
          notes: _orderNote,
          tokensUsed: tokensUsed,
        );
        if (!mounted) return;
        if (!mbwayOrdered) {
          setState(() => _isProcessing = false);
          messenger.showSnackBar(SnackBar(
            content: Text(_createOrderErrorMessage(orderStore)),
          ));
          return;
        }
        // FIX 4 (2026-05-15) — usa lastCreatedOrderId em vez de orders.first
        // (que pode ser reordenado por realtime entre createOrder e este acesso).
        final mbwayOrderId = orderStore.lastCreatedOrderId;
        if (mbwayOrderId == null) {
          setState(() => _isProcessing = false);
          messenger.showSnackBar(const SnackBar(
            content: Text('Erro interno: pedido criado mas ID não disponível.'),
          ));
          return;
        }
        // Use the user-entered MBWay number (validated as 9 digits in pre-flight).
        // Edge Function handles E.164 conversion (prepends +351).
        final clientPhone =
            _mbwayPhoneController.text.replaceAll(RegExp(r'\D'), '');
        setState(() => _isProcessing = false);
        final piId = await paymentService.initiateMbwayPayment(
          orderId: mbwayOrderId,
          phone: clientPhone,
        );
        if (!mounted) return;
        if (piId == null) {
          messenger.showSnackBar(const SnackBar(
            content: Text('Não foi possível iniciar o pagamento MBWay.'),
          ));
          await _bailOutAndCancel(mbwayOrderId);
          return;
        }
        final mbwayPaid = await _showMBWayWaitingDialog(mbwayOrderId, amount);
        if (!mounted) return;
        if (!mbwayPaid) {
          messenger.showSnackBar(const SnackBar(
            content: Text('Pagamento MBWay não confirmado ou expirou.'),
          ));
          await _bailOutAndCancel(mbwayOrderId);
          return;
        }
        await _persistErrandHomeStop(cartStore, mbwayOrderId);
        await _consumeTokensAndNavigate(tokensUsed);
        return;
      case PaymentMethod.cash:
        // 2026-06-04 — feedback visual imediato: cold-start RPC create_order +
        // dispatch leva 3-5s. Sem mensagem, utilizador só vê spinner vazio.
        messenger.showSnackBar(const SnackBar(
          content: Text('A preparar o seu pedido…'),
          duration: Duration(seconds: 3),
        ));
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
      notes: _orderNote,
      tokensUsed: tokensUsed,
    );

    if (!mounted) return;

    setState(() => _isProcessing = false);

    if (!ordered) {
      messenger.showSnackBar(
        SnackBar(content: Text(_createOrderErrorMessage(orderStore))),
      );
      return;
    }

    final cashOrderId = orderStore.lastCreatedOrderId;
    if (cashOrderId != null) {
      await _persistErrandHomeStop(cartStore, cashOrderId);
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
          content: Text('Pedido criado. A aguardar confirmação de pagamento.')),
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
                : AppColors.divider,
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
    this.subtitle,
  });

  final String label;
  final double value;
  final bool isStrong;
  final bool isDiscount;
  final String? subtitle;

  @override
  Widget build(BuildContext context) {
    final color = isDiscount ? AppColors.success : null;
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
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: textStyle),
                if (subtitle != null)
                  Text(
                    subtitle!,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: AppColors.textSecondary,
                        ),
                  ),
              ],
            ),
          ),
          Text(valueText, style: textStyle),
        ],
      ),
    );
  }
}

/// FAVORES (§55.4) — explica garantia (cartão ×1,2) ou dinheiro a levar.
class _ErrandPaymentHint extends StatelessWidget {
  const _ErrandPaymentHint({required this.method, required this.estimate});
  final PaymentMethod method;
  final double estimate;

  @override
  Widget build(BuildContext context) {
    final isCash = method == PaymentMethod.cash;
    final guarantee = estimate * 1.2;
    final text = isCash
        ? 'Leva ~€${estimate.toStringAsFixed(2)} em dinheiro para a compra. '
            'O estafeta confirma o valor exato no talão.'
        : 'Para a compra, o cartão pode segurar ~€${guarantee.toStringAsFixed(2)} '
            'como garantia (estimativa ×1,2). Pagas só o valor do talão — '
            'o resto é libertado.';
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.primaryWash,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.divider),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(isCash ? Icons.payments_outlined : Icons.credit_card,
              size: 18, color: AppColors.primary),
          const SizedBox(width: 8),
          Expanded(child: Text(text, style: const TextStyle(fontSize: 12.5))),
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
            style: const TextStyle(color: AppColors.textSecondary, fontSize: 13),
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
