import 'dart:async' show Timer, unawaited;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../config/app_colors.dart';
import '../config/app_spacing.dart';
import '../models/order_service_type.dart';
import '../models/restaurant_model.dart' show kFestasPrateleiraEncomenda;
import '../models/order_model.dart' show PaymentMethod;
import '../services/tip_service.dart';
import '../services/wallet_service.dart';
import '../services/weight_portions.dart';
import '../stores/cart_store.dart';
import '../stores/order_store.dart';
import '../stores/restaurant_store.dart';
import '../widgets/bora/bora.dart';
import '../widgets/bora/maior_18.dart';
import '../widgets/takeaway/curbside_inputs.dart';
import '../widgets/tip_selector.dart';
import '../widgets/valor_com_risco.dart';
import 'complete_profile_screen.dart' show garantirContactoDoCliente;
import 'festas_quando_screen.dart';
import 'orders_screen.dart';
import 'payment_method_screen.dart';

import '../l10n/tr.dart';

class CartScreen extends StatelessWidget {
  const CartScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final cartStore = context.watch<CartStore>();
    final pricing = cartStore.pricingBreakdown;
    // UM SÓ TOTAL (05/10/2026): as parcelas e o total são os do
    // `CartStore.resumo` — os do servidor assim que o quote chega, o cálculo
    // local até lá. É a mesma fonte do ecrã de pagamento.
    final resumo = cartStore.resumo;

    final apartmentEnabled = cartStore.apartmentDelivery;
    // A gorjeta fica FORA do total: é cobrada à parte, depois do pedido, e o
    // ecrã de pagamento nunca a somou — os dois totais diferiam e o saldo
    // Bora era calculado sobre um valor com gorjeta.
    final totalToPay = resumo.total;

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: BoraScreenAppBar(title: 'Carrinho'.tr),
      body: Column(
        children: [
          Expanded(
            child: cartStore.items.isEmpty
                ? const _EmptyCart()
                : ListView.separated(
                    padding: const EdgeInsets.fromLTRB(
                      Spacing.lg,
                      Spacing.md,
                      Spacing.lg,
                      Spacing.lg,
                    ),
                    // Missão maiores-18: aviso persistente no topo da lista
                    // quando há tabaco/álcool — o estafeta pede documento.
                    itemCount: cartStore.items.length +
                        (cartStore.hasAgeRestricted ? 1 : 0),
                    separatorBuilder: (_, __) =>
                        const SizedBox(height: Spacing.sm),
                    itemBuilder: (context, index) {
                      if (cartStore.hasAgeRestricted) {
                        if (index == 0) return const Maior18Aviso();
                        index -= 1;
                      }
                      final item = cartStore.items[index];
                      return _CartItemTile(
                        // Ao peso: "Abóbora Cabotiá — 500 g (meio quilo)".
                        name: WeightPortions.displayName(item),
                        price: item.price,
                        quantity: item.quantity,
                        // T1 (2026-06-11): cliente vê as opções escolhidas
                        // (toppings) — o preço da linha já as inclui.
                        options: WeightPortions.optionsWithoutWeight(item)
                            .map((o) => '${o.group}: ${o.items.join(', ')}')
                            .toList(),
                        onDecrease: () => cartStore.decreaseQuantity(item),
                        onIncrease: () => cartStore.increaseQuantity(item),
                        onRemove: () => cartStore.removeItem(item),
                      );
                    },
                  ),
          ),
          // Painel de checkout limitado a ~62% do ecrã: a lista de itens
          // (Expanded, acima) mantém sempre espaço para rolar, e dentro do
          // painel o resumo de preços rola enquanto o botão fica pinado.
          ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.of(context).size.height * 0.62,
            ),
            child: _CheckoutPanel(
              cartStore: cartStore,
              pricing: pricing,
              resumo: resumo,
              apartmentEnabled: apartmentEnabled,
              totalToPay: totalToPay,
            ),
          ),
        ],
      ),
    );
  }
}

class _EmptyCart extends StatelessWidget {
  const _EmptyCart();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.shopping_cart_outlined,
            size: 64,
            color: AppColors.textSecondary.withValues(alpha: 0.5),
          ),
          const SizedBox(height: Spacing.md),
          Text(
            'O carrinho está vazio.'.tr,
            style: const TextStyle(
              fontSize: 16,
              color: AppColors.textSecondary,
            ),
          ),
        ],
      ),
    );
  }
}

class _CartItemTile extends StatelessWidget {
  const _CartItemTile({
    required this.name,
    required this.price,
    required this.quantity,
    this.options = const [],
    required this.onDecrease,
    required this.onIncrease,
    required this.onRemove,
  });

  final String name;
  final double price;
  final int quantity;
  final List<String> options;
  final VoidCallback onDecrease;
  final VoidCallback onIncrease;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(
          Spacing.md, Spacing.sm, Spacing.xs, Spacing.sm),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(Radii.lg),
        boxShadow: AppColors.shadowSm,
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textPrimary,
                  ),
                ),
                if (options.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    options.join('\n'),
                    style: const TextStyle(
                      fontSize: 12,
                      height: 1.3,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ],
                const SizedBox(height: 2),
                Text(
                  '€${price.toStringAsFixed(2)}',
                  style: const TextStyle(
                    fontSize: 14,
                    color: AppColors.textSecondary,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.remove_circle_outline),
            color: AppColors.textSecondary,
            onPressed: onDecrease,
          ),
          Text(
            '$quantity',
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: AppColors.textPrimary,
            ),
          ),
          IconButton(
            icon: const Icon(Icons.add_circle_outline),
            color: AppColors.primary,
            onPressed: onIncrease,
          ),
          IconButton(
            icon: const Icon(Icons.delete_outline),
            color: AppColors.error,
            onPressed: onRemove,
          ),
        ],
      ),
    );
  }
}

class _CheckoutPanel extends StatefulWidget {
  const _CheckoutPanel({
    required this.cartStore,
    required this.pricing,
    required this.resumo,
    required this.apartmentEnabled,
    required this.totalToPay,
  });

  final CartStore cartStore;
  final dynamic pricing;
  final ResumoDoCarrinho resumo;
  final bool apartmentEnabled;
  final double totalToPay;

  @override
  State<_CheckoutPanel> createState() => _CheckoutPanelState();
}

class _CheckoutPanelState extends State<_CheckoutPanel> {
  WalletBalance? _wallet;
  bool _useWalletBalance = false;

  /// [Pedido duplicado · 04/10] Trava PRÓPRIA do "Finalizar pedido": do 1.º
  /// toque até o ecrã de pagamento fechar. Antes, dois toques rápidos abriam
  /// dois ecrãs de pagamento (há um await de contacto antes do push).
  bool _aAbrirPagamento = false;

  Future<void> _comTravaPagamento(Future<void> Function() accao) async {
    if (_aAbrirPagamento) return;
    setState(() => _aAbrirPagamento = true);
    try {
      await accao();
    } finally {
      if (mounted) setState(() => _aAbrirPagamento = false);
    }
  }

  /// UM SÓ TOTAL (05/10/2026): o painel pede ao servidor o quote DESTE
  /// carrinho ao abrir e sempre que ele muda — com uma pausa, para não sair
  /// uma chamada por cada toque no "+". O [CartStore] avisa quando chega.
  late final CartStore _cart = context.read<CartStore>();
  Timer? _quoteTimer;

  void _pedirQuoteComPausa() {
    _quoteTimer?.cancel();
    _quoteTimer = Timer(const Duration(milliseconds: 600), () {
      if (mounted) unawaited(_cart.quoteOrderPricing());
    });
  }

  @override
  void dispose() {
    _cart.removeListener(_pedirQuoteComPausa);
    _quoteTimer?.cancel();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    // M-E (2026-06-10): total do painel com distância de ROTA (= cobrança).
    _cart.refreshRouteDistance();
    _cart.addListener(_pedirQuoteComPausa);
    unawaited(_cart.quoteOrderPricing());
    _loadWallet();
    TipService.ligada().then((v) {
      if (!mounted) return;
      // Desligada: nenhuma gorjeta escondida fica a somar no total.
      if (!v) context.read<CartStore>().setTipCents(0);
      setState(() => _gorjetaLigada = v);
    });
  }

  /// Gorjeta ligada no servidor (`tips_enabled`)? Até sabermos, não se mostra.
  bool _gorjetaLigada = false;

  /// Gorjeta do checkout (missão 03/10 · bloco 3): até 04/10 só existia no
  /// ecrã — a `create_order` nunca a recebia e nunca foi cobrada. Agora, com o
  /// pedido já criado e pago, cobra-se à parte (cartão/MB Way) ou fica
  /// registada para entregar em mão (dinheiro). 100% para o estafeta.
  Future<void> _tratarGorjetaDoCheckout(int tipCents) async {
    if (tipCents <= 0 || !_gorjetaLigada) return;
    final orderStore = context.read<OrderStore>();
    final messenger = ScaffoldMessenger.of(context);
    final orderId = orderStore.lastCreatedOrderId;
    if (orderId == null) return;
    final order = orderStore.orders.where((o) => o.id == orderId).firstOrNull;
    final r = order?.paymentMethod == PaymentMethod.cash
        ? await TipService.registarDinheiro(orderId, tipCents)
        : await TipService.cobrar(
            target: 'order', id: orderId, cents: tipCents, moment: 'checkout');
    messenger.showSnackBar(SnackBar(content: Text(r.mensagem)));
  }

  Future<void> _loadWallet() async {
    try {
      final b = await WalletService.instance.getBalance();
      if (mounted) setState(() => _wallet = b);
    } catch (_) {/* offline / no balance */}
  }

  /// Cents do saldo livre que cobrem o pedido (até ao máximo do total).
  int _walletAppliedCents() {
    if (!_useWalletBalance || _wallet == null) return 0;
    if (_wallet!.freeCents <= 0) return 0;
    final totalCents = (widget.totalToPay * 100).round();
    return _wallet!.freeCents < totalCents ? _wallet!.freeCents : totalCents;
  }

  /// Sessão 3B: cents devidos do saldo negativo anterior (sempre positivo).
  /// Vai ser liquidado server-side em create_order; UI só mostra a linha.
  int _settlementCents() => _wallet?.debtCents ?? 0;

  @override
  Widget build(BuildContext context) {
    final cartStore = widget.cartStore;
    final pricing = widget.pricing;
    final resumo = widget.resumo;
    final apartmentEnabled = widget.apartmentEnabled;
    final baseDeliveryFee = resumo.entrega;
    final totalToPay = widget.totalToPay;
    final walletAppliedCents = _walletAppliedCents();
    final walletAppliedEur = walletAppliedCents / 100;
    // Sessão 3B: settlement de saldo devedor anterior (server-side em create_order)
    final settlementCents = _settlementCents();
    final settlementEur = settlementCents / 100.0;
    final isWalletBlocked = _wallet?.isBlocked ?? false;
    final remainingToPay = (totalToPay - walletAppliedEur + settlementEur)
        .clamp(0.0, double.infinity);

    // [botoes-navbar-eta 31/08] SafeArea(minimum:16) dava max(sistema, 16) e,
    // com o padding do MediaQuery consumido por um SafeArea acima, o
    // "Finalizar pedido" podia colar na navbar de 3 botões. Regra nova: 16 px
    // ALÉM do `viewPadding` do sistema, sempre (contrato BoraBottomActionBar).
    return Container(
        width: double.infinity,
        padding: EdgeInsets.fromLTRB(
          Spacing.xl,
          Spacing.xl,
          Spacing.xl,
          Spacing.lg + MediaQuery.of(context).viewPadding.bottom,
        ),
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(Radii.xl)),
          boxShadow: AppColors.shadowNav,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Resumo/opções rolam; o botão "Finalizar pedido" fica pinado
            // abaixo (padrão Uber Eats / Glovo) — sempre visível.
            Flexible(
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // R5 — switch só aparece quando o cliente NÃO chegou via
                    // RestaurantOptionsScreen. Vindo dessa tela, a modalidade está
                    // bloqueada (cliente volta atrás para trocar). Evita UX ambíguo.
                    if (cartStore.isPartnerStore &&
                        !cartStore.serviceTypeLockedByOptions)
                      SwitchListTile.adaptive(
                        value: cartStore.isTakeaway,
                        onChanged: cartStore.items.isEmpty
                            ? null
                            : (value) => cartStore.setServiceTypeFromOption(
                                  value
                                      ? OrderServiceType.takeaway
                                      : OrderServiceType.restaurant,
                                ),
                        contentPadding: EdgeInsets.zero,
                        activeColor: AppColors.primary,
                        title: Text(
                          'Ir buscar (takeaway, sem entrega)'.tr,
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                        subtitle: Text(
                          'Sem taxa de entrega. Recebes aviso quando estiver pronto.'.tr,
                          style: const TextStyle(fontSize: 12),
                        ),
                      ),
                    // D6 — curbside inputs (visível apenas em takeaway, se o
                    // restaurante actual tem curbside habilitado). Pré-paid no
                    // cart_screen → sempre editável (isLocked=false).
                    if (cartStore.isTakeaway)
                      _CurbsideForCart(cartStore: cartStore),
                    SwitchListTile.adaptive(
                      value: apartmentEnabled,
                      onChanged: cartStore.items.isEmpty || cartStore.isTakeaway
                          ? null
                          : (value) => cartStore.setApartmentDelivery(value),
                      contentPadding: EdgeInsets.zero,
                      activeColor: AppColors.primary,
                      title: Text(
                        'Entregar no apartamento (+€1.50)'.tr,
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                    ),
                    const SizedBox(height: Spacing.sm),
                    _SummaryRow(label: 'Subtotal'.tr, value: resumo.subtotal),
                    if (resumo.taxaServico > 0)
                      _SummaryRow(
                        label: 'Taxa de serviço'.tr,
                        value: resumo.taxaServico,
                        // Risco estilo Uber/Glovo: 2,50 € riscado ao lado do
                        // 0,99 €. Vem de platform_settings — pôr 0 na chave
                        // do risco faz desaparecer sem tocar em código.
                        riscado: cartStore.taxaServicoRiscada,
                      ),
                    _SummaryRow(
                      label: cartStore.isTakeaway
                          ? 'Entrega (takeaway)'.tr
                          : 'Entrega',
                      value: cartStore.isTakeaway ? 0.0 : baseDeliveryFee,
                      subtitle: () {
                        if (cartStore.isTakeaway) return null;
                        final d = pricing.distanceKm;
                        if (d <= 4.0) return null;
                        final extra = d - 4.0;
                        final extraCharge = baseDeliveryFee - 2.50;
                        return '€2.50 base + €{0} por {1}km extra'.trArgs([extraCharge.toStringAsFixed(2), extra.toStringAsFixed(1)]);
                      }(),
                    ),
                    if (resumo.apartamento > 0)
                      _SummaryRow(
                        label: 'Entrega em apartamento'.tr,
                        value: resumo.apartamento,
                      ),
                    if (resumo.saco > 0)
                      _SummaryRow(
                          label: 'Saco para viagem'.tr, value: resumo.saco),
                    if (cartStore.smallOrderFee > 0)
                      _SummaryRow(
                        label: 'Taxa de pedido pequeno'.tr,
                        value: cartStore.smallOrderFee,
                      ),
                    if (cartStore.faltaParaMinimo > 0)
                      _FaltaParaOMinimo(falta: cartStore.faltaParaMinimo),
                    const SizedBox(height: Spacing.md),
                    if (_gorjetaLigada) ...[
                      TipSelector(
                        initialCents: cartStore.tipCents,
                        enabled: cartStore.items.isNotEmpty,
                        onChanged: (cents) => cartStore.setTipCents(cents),
                      ),
                      Text(
                        'A gorjeta vai toda para o estafeta e é cobrada à parte.'
                            .tr,
                        style: const TextStyle(
                            fontSize: 12, color: AppColors.textSecondary),
                      ),
                    ],
                    if (_gorjetaLigada && cartStore.tipCents > 0)
                      _SummaryRow(
                          label: 'Gorjeta'.tr,
                          value: cartStore.tipEur,
                          accent: true),
                    // ── Wallet — saldo livre (Feature 1) ─────────────────────────────
                    if (_wallet != null && _wallet!.freeCents > 0) ...[
                      const Divider(height: Spacing.lg),
                      SwitchListTile.adaptive(
                        value: _useWalletBalance,
                        onChanged: cartStore.items.isEmpty
                            ? null
                            : (v) {
                                setState(() => _useWalletBalance = v);
                                cartStore.setWalletApplied(
                                    v ? _walletAppliedCents() : 0);
                              },
                        contentPadding: EdgeInsets.zero,
                        activeColor: AppColors.primary,
                        secondary: const Icon(Icons.account_balance_wallet,
                            color: AppColors.primary),
                        title: Text(
                          'Usar saldo Bora'.tr,
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                        subtitle: Text(
                          'Disponível: €{0}'.trArgs([(_wallet!.freeCents / 100).toStringAsFixed(2)]),
                          style: const TextStyle(fontSize: 12),
                        ),
                      ),
                      if (_useWalletBalance && walletAppliedCents > 0)
                        _SummaryRow(
                          label: 'Saldo Bora aplicado'.tr,
                          value: -walletAppliedEur,
                          accent: true,
                        ),
                    ],
                    // ── Sessão 3B: saldo devedor anterior ──────────────────────────
                    if (settlementCents > 0) ...[
                      const Divider(height: Spacing.lg),
                      _SummaryRow(
                        label: 'Saldo devedor anterior'.tr,
                        value: settlementEur,
                        accent: true,
                      ),
                      Padding(
                        padding: const EdgeInsets.only(top: 4, bottom: 4),
                        child: Text(
                          'Liquidação automática da dívida em carteira.'.tr,
                          style: TextStyle(
                              fontSize: 11, color: Colors.red.shade700),
                        ),
                      ),
                    ],
                    const Divider(height: Spacing.xxl),
                    _SummaryRow(
                      label: _useWalletBalance && walletAppliedCents > 0
                          ? 'Total a pagar (após saldo)'.tr
                          : 'Total a pagar',
                      value: remainingToPay,
                      isStrong: true,
                    ),
                    if (isWalletBlocked) ...[
                      const SizedBox(height: Spacing.md),
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: Colors.red.shade50,
                          border: Border.all(color: Colors.red.shade300),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Row(
                          children: [
                            Icon(Icons.block,
                                color: Colors.red.shade700, size: 18),
                            const SizedBox(width: 8),
                            Expanded(
                              // BUG #1 (2026-05-13) — banner informativo, não bloqueia
                              // o avanço para PaymentMethodScreen. Cartão e MBWay
                              // liquidam dívida automaticamente; só CASH é gated em
                              // payment_method_screen.dart (BUG #1 §54).
                              child: Text(
                                'Carteira em dívida (saldo {0}). Paga com Cartão ou MBWay para liquidar automaticamente.'.trArgs([_wallet!.freeFormatted]),
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Colors.red.shade900,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
            const SizedBox(height: Spacing.lg),
            // "Em breve": se por alguma via o item chegou ao carrinho, o
            // Finalizar fica bloqueado com a mesma mensagem. O servidor
            // rejeita na mesma (STORE_COMING_SOON).
            if (cartStore.vendorBlocksAddToCart) ...[
              Tooltip(
                message: kComingSoonBlockedMessage,
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => showComingSoonBlockedSnackBar(context),
                  child: AbsorbPointer(
                    child: BoraAccentButton(
                      label: 'Finalizar pedido'.tr,
                      icon: Icons.shopping_bag_outlined,
                      onPressed: null,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: Spacing.sm),
              Text(
                kComingSoonBlockedMessage,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: Colors.grey.shade700,
                ),
              ),
            ] else
            BoraAccentButton(
              // BUG #1 (2026-05-13) — `isWalletBlocked` deixa de bloquear o
              // botão e o label. Cartão/MBWay liquidam a dívida no checkout;
              // só CASH é disabled em payment_method_screen.dart (BUG #1 §54).
              // 4.1.D — CTA único laranja do ecrã (regra "1 elemento laranja
              // por ecrã"): substituído de BoraPrimaryButton para BoraAccentButton.
              label: remainingToPay <= 0
                  ? 'Pagar com saldo Bora'.tr
                  : 'Finalizar pedido',
              icon: Icons.shopping_bag_outlined,
              onPressed: cartStore.items.isEmpty || _aAbrirPagamento
                  ? null
                  : () => _comTravaPagamento(() async {
                      // BLOCO C.3 (2026-09-05) — porta única de contacto: sem
                      // nome/telemóvel válidos, o cliente é bloqueado aqui
                      // antes de seguir para pagamento (ver
                      // garantirContactoDoCliente em complete_profile_screen.dart).
                      final contactoOk =
                          await garantirContactoDoCliente(context);
                      if (!contactoOk || !context.mounted) return;

                      cartStore.setWalletApplied(
                          _useWalletBalance ? walletAppliedCents : 0);

                      // BUG #2 (sessão post-test 2026-05-12) — REMOVIDO
                      // AlertDialog 'Total ajustado'. Cliente já vê total no
                      // carrinho + PaymentMethodScreen. Server quote continua
                      // a correr (best-effort silencioso) — RPC create_order
                      // server-side recalcula authoritative total final.
                      // Cliente paga o que vê. Sem surpresa, sem dialog.
                      unawaited(cartStore.quoteOrderPricing(
                        walletAppliedCents:
                            _useWalletBalance ? walletAppliedCents : 0,
                      ));

                      // Festas: item de encomenda no carrinho → o cliente
                      // escolhe o dia e a hora (mínimo: dia seguinte).
                      // Carrinho misto agenda TUDO junto; só "Na hora" segue
                      // como delivery normal.
                      if (cartStore.vendorIsFestas) {
                        final restStore = context.read<RestaurantStore>();
                        final temEncomenda = cartStore.items.any((i) =>
                            restStore.productCategoryById(i.productId) ==
                            kFestasPrateleiraEncomenda);
                        if (temEncomenda) {
                          final quando = await Navigator.push<DateTime>(
                            context,
                            MaterialPageRoute(
                              builder: (_) => FestasQuandoScreen(
                                inicial: cartStore.festasQuando,
                              ),
                            ),
                          );
                          if (quando == null) return; // voltou atrás
                          cartStore.definirFestasQuando(quando);
                        } else {
                          cartStore.definirFestasQuando(null);
                        }
                        if (!context.mounted) return;
                      }

                      // O carrinho limpa-se ao criar o pedido: guarda-se já.
                      final tipCents = cartStore.tipCents;
                      final confirmed = await Navigator.push<bool>(
                        context,
                        MaterialPageRoute(
                          builder: (_) => const PaymentMethodScreen(),
                        ),
                      );
                      if (confirmed == true && context.mounted) {
                        await _tratarGorjetaDoCheckout(tipCents);
                        if (!context.mounted) return;
                        Navigator.of(context)
                            .popUntil((route) => route.isFirst);
                        Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => const OrdersScreen(),
                          ),
                        );
                      }
                    }),
            ),
          ],
        ),
    );
  }
}

/// D6 — Wrapper que faz lookup do RestaurantModel pelo vendorName e mostra
/// [CurbsideInputs] apenas se o restaurante tem `curbsideEnabled=true`.
/// Extraído como widget separado para evitar Builder inline complexo dentro
/// do checkout panel.
class _CurbsideForCart extends StatelessWidget {
  const _CurbsideForCart({required this.cartStore});

  final CartStore cartStore;

  @override
  Widget build(BuildContext context) {
    final restaurantStore = context.watch<RestaurantStore>();
    final vendor = cartStore.vendorName;
    if (vendor == null) return const SizedBox.shrink();

    final matches = restaurantStore.restaurants.where((r) => r.name == vendor);
    if (matches.isEmpty) return const SizedBox.shrink();
    final restaurant = matches.first;
    if (!restaurant.curbsideEnabled) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.only(top: Spacing.sm),
      child: CurbsideInputs(
        isCurbside: cartStore.isCurbside,
        curbsideInfo: cartStore.curbsideInfo,
        isLocked: false,
        onCurbsideChanged: cartStore.setCurbside,
        onInfoChanged: cartStore.setCurbsideInfo,
      ),
    );
  }
}

class _SummaryRow extends StatelessWidget {
  const _SummaryRow({
    required this.label,
    required this.value,
    this.isStrong = false,
    this.accent = false,
    this.subtitle,
    this.riscado,
  });

  final String label;
  final double value;
  final bool isStrong;
  final bool accent;
  final String? subtitle;

  /// Preço antigo a mostrar riscado ao lado (ver [ValorComRisco]).
  final double? riscado;

  @override
  Widget build(BuildContext context) {
    final color = accent
        ? AppColors.accent
        : (isStrong ? AppColors.textPrimary : AppColors.textSecondary);
    final style = TextStyle(
      fontSize: isStrong ? 16 : 14,
      fontWeight: isStrong ? FontWeight.w800 : FontWeight.w500,
      color: color,
    );

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: Spacing.xs),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: style),
                if (subtitle != null)
                  Text(
                    subtitle!,
                    style: const TextStyle(
                      fontSize: 11,
                      color: AppColors.textSecondary,
                    ),
                  ),
              ],
            ),
          ),
          ValorComRisco(valor: value, riscado: riscado, style: style),
        ],
      ),
    );
  }
}

/// Aviso do carrinho: quanto falta para deixar de pagar a taxa de pedido
/// pequeno. E o que a Uber e a Glovo fazem — e o que faz o cliente juntar mais
/// um item em vez de desistir do pedido.
class _FaltaParaOMinimo extends StatelessWidget {
  const _FaltaParaOMinimo({required this.falta});

  final double falta;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: Spacing.xs),
      child: Row(
        children: [
          const Icon(Icons.add_shopping_cart,
              size: 16, color: AppColors.primary),
          const SizedBox(width: Spacing.xs),
          Expanded(
            child: Text(
              'Faltam {0} € para evitar a taxa de pedido pequeno'.trArgs([falta.toStringAsFixed(2).replaceAll('.', ',')]),
              style: const TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
                color: AppColors.primary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
