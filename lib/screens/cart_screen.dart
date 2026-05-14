import 'dart:async' show unawaited;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../config/app_colors.dart';
import '../config/app_spacing.dart';
import '../models/order_service_type.dart';
import '../services/wallet_service.dart';
import '../stores/cart_store.dart';
import '../stores/restaurant_store.dart';
import '../widgets/bora/bora.dart';
import '../widgets/takeaway/curbside_inputs.dart';
import '../widgets/tip_selector.dart';
import 'orders_screen.dart';
import 'payment_method_screen.dart';

class CartScreen extends StatelessWidget {
  const CartScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final cartStore = context.watch<CartStore>();
    final pricing = cartStore.pricingBreakdown;

    final apartmentEnabled = cartStore.apartmentDelivery;
    double baseDeliveryFee = pricing.deliveryFee - pricing.apartmentSurcharge;
    if (baseDeliveryFee < 0) {
      baseDeliveryFee = 0;
    }
    // Takeaway (BR §14.9) — client skips delivery fee entirely.
    // Gorjeta (BR §4.5) — somada ao total final (split 80/20 a jusante).
    final totalToPay = (cartStore.isTakeaway
            ? (pricing.customerTotal - pricing.deliveryFee)
            : pricing.customerTotal) +
        cartStore.tipEur;

    return Scaffold(
      backgroundColor: AppColors.surface,
      appBar: AppBar(
        title: const Text('Carrinho'),
        backgroundColor: Colors.transparent,
        foregroundColor: Colors.white,
        elevation: 0,
        flexibleSpace: const DecoratedBox(
          decoration: BoxDecoration(gradient: AppColors.headerGradient),
        ),
      ),
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
                    itemCount: cartStore.items.length,
                    separatorBuilder: (_, __) =>
                        const SizedBox(height: Spacing.sm),
                    itemBuilder: (context, index) {
                      final item = cartStore.items[index];
                      return _CartItemTile(
                        name: item.name,
                        price: item.price,
                        quantity: item.quantity,
                        onDecrease: () => cartStore.decreaseQuantity(item),
                        onIncrease: () => cartStore.increaseQuantity(item),
                        onRemove: () => cartStore.removeItem(item),
                      );
                    },
                  ),
          ),
          _CheckoutPanel(
            cartStore: cartStore,
            pricing: pricing,
            apartmentEnabled: apartmentEnabled,
            baseDeliveryFee: baseDeliveryFee,
            totalToPay: totalToPay,
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
          const Text(
            'O carrinho está vazio.',
            style: TextStyle(
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
    required this.onDecrease,
    required this.onIncrease,
    required this.onRemove,
  });

  final String name;
  final double price;
  final int quantity;
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
        borderRadius: BorderRadius.circular(Radii.md),
        border: Border.all(color: AppColors.divider),
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
    required this.apartmentEnabled,
    required this.baseDeliveryFee,
    required this.totalToPay,
  });

  final CartStore cartStore;
  final dynamic pricing;
  final bool apartmentEnabled;
  final double baseDeliveryFee;
  final double totalToPay;

  @override
  State<_CheckoutPanel> createState() => _CheckoutPanelState();
}

class _CheckoutPanelState extends State<_CheckoutPanel> {
  WalletBalance? _wallet;
  bool _useWalletBalance = false;

  @override
  void initState() {
    super.initState();
    _loadWallet();
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
    final apartmentEnabled = widget.apartmentEnabled;
    final baseDeliveryFee = widget.baseDeliveryFee;
    final totalToPay = widget.totalToPay;
    final walletAppliedCents = _walletAppliedCents();
    final walletAppliedEur = walletAppliedCents / 100;
    // Sessão 3B: settlement de saldo devedor anterior (server-side em create_order)
    final settlementCents = _settlementCents();
    final settlementEur = settlementCents / 100.0;
    final isWalletBlocked = _wallet?.isBlocked ?? false;
    final remainingToPay = (totalToPay - walletAppliedEur + settlementEur)
        .clamp(0.0, double.infinity);

    return SafeArea(
      top: false,
      minimum: const EdgeInsets.only(bottom: Spacing.lg),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.fromLTRB(
          Spacing.xl,
          Spacing.xl,
          Spacing.xl,
          Spacing.lg,
        ),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius:
              const BorderRadius.vertical(top: Radius.circular(Radii.xl)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.08),
              blurRadius: 12,
              offset: const Offset(0, -4),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // R5 — switch só aparece quando o cliente NÃO chegou via
            // RestaurantOptionsScreen. Vindo dessa tela, a modalidade está
            // bloqueada (cliente volta atrás para trocar). Evita UX ambíguo.
            if (cartStore.isPartnerStore && !cartStore.serviceTypeLockedByOptions)
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
                title: const Text(
                  'Ir buscar (takeaway, sem entrega)',
                  style: TextStyle(fontWeight: FontWeight.w600),
                ),
                subtitle: const Text(
                  'Sem taxa de entrega. Recebes aviso quando estiver pronto. (BR §14.9)',
                  style: TextStyle(fontSize: 12),
                ),
              ),
            // D6 — curbside inputs (visível apenas em takeaway, se o
            // restaurante actual tem curbside habilitado). Pré-paid no
            // cart_screen → sempre editável (isLocked=false).
            if (cartStore.isTakeaway) _CurbsideForCart(cartStore: cartStore),
            SwitchListTile.adaptive(
              value: apartmentEnabled,
              onChanged: cartStore.items.isEmpty || cartStore.isTakeaway
                  ? null
                  : (value) => cartStore.setApartmentDelivery(value),
              contentPadding: EdgeInsets.zero,
              activeColor: AppColors.primary,
              title: const Text(
                'Entregar no apartamento (+€1.50)',
                style: TextStyle(fontWeight: FontWeight.w600),
              ),
            ),
            const SizedBox(height: Spacing.sm),
            _SummaryRow(label: 'Subtotal', value: cartStore.total),
            if (pricing.serviceFee > 0)
              _SummaryRow(
                  label: 'Taxa de serviço', value: pricing.serviceFee),
            _SummaryRow(
              label: cartStore.isTakeaway ? 'Entrega (takeaway)' : 'Entrega',
              value: cartStore.isTakeaway ? 0.0 : baseDeliveryFee,
            ),
            if (pricing.apartmentSurcharge > 0)
              _SummaryRow(
                label: 'Entrega em apartamento',
                value: pricing.apartmentSurcharge,
              ),
            if (pricing.bagFee > 0)
              _SummaryRow(
                  label: 'Saco para viagem', value: pricing.bagFee),
            const SizedBox(height: Spacing.md),
            TipSelector(
              initialCents: cartStore.tipCents,
              enabled: cartStore.items.isNotEmpty,
              onChanged: (cents) => cartStore.setTipCents(cents),
            ),
            if (cartStore.tipCents > 0)
              _SummaryRow(
                  label: 'Gorjeta', value: cartStore.tipEur, accent: true),
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
                activeColor: Colors.green,
                secondary: const Icon(Icons.account_balance_wallet,
                    color: Colors.green),
                title: const Text(
                  'Usar saldo Bora',
                  style: TextStyle(fontWeight: FontWeight.w600),
                ),
                subtitle: Text(
                  'Disponível: €${(_wallet!.freeCents / 100).toStringAsFixed(2)}',
                  style: const TextStyle(fontSize: 12),
                ),
              ),
              if (_useWalletBalance && walletAppliedCents > 0)
                _SummaryRow(
                  label: 'Saldo Bora aplicado',
                  value: -walletAppliedEur,
                  accent: true,
                ),
            ],
            // ── Sessão 3B: saldo devedor anterior ──────────────────────────
            if (settlementCents > 0) ...[
              const Divider(height: Spacing.lg),
              _SummaryRow(
                label: 'Saldo devedor anterior',
                value: settlementEur,
                accent: true,
              ),
              Padding(
                padding: const EdgeInsets.only(top: 4, bottom: 4),
                child: Text(
                  'Liquidação automática da dívida em carteira.',
                  style: TextStyle(fontSize: 11, color: Colors.red.shade700),
                ),
              ),
            ],
            const Divider(height: Spacing.xxl),
            _SummaryRow(
              label: _useWalletBalance && walletAppliedCents > 0
                  ? 'Total a pagar (após saldo)'
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
                    Icon(Icons.block, color: Colors.red.shade700, size: 18),
                    const SizedBox(width: 8),
                    Expanded(
                      // BUG #1 (2026-05-13) — banner informativo, não bloqueia
                      // o avanço para PaymentMethodScreen. Cartão e MBWay
                      // liquidam dívida automaticamente; só CASH é gated em
                      // payment_method_screen.dart (BUG #1 §54).
                      child: Text(
                        'Carteira em dívida (saldo €${(_wallet!.freeCents / 100).toStringAsFixed(2)}). '
                        'Paga com Cartão ou MBWay para liquidar automaticamente.',
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
            const SizedBox(height: Spacing.lg),
            BoraPrimaryButton(
              // BUG #1 (2026-05-13) — `isWalletBlocked` deixa de bloquear o
              // botão e o label. Cartão/MBWay liquidam a dívida no checkout;
              // só CASH é disabled em payment_method_screen.dart (BUG #1 §54).
              label: remainingToPay <= 0
                  ? 'Pagar com saldo Bora'
                  : 'Finalizar pedido',
              icon: Icons.shopping_bag_outlined,
              onPressed: cartStore.items.isEmpty
                  ? null
                  : () async {
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

                      final confirmed = await Navigator.push<bool>(
                        context,
                        MaterialPageRoute(
                          builder: (_) => const PaymentMethodScreen(),
                        ),
                      );
                      if (confirmed == true && context.mounted) {
                        Navigator.of(context)
                            .popUntil((route) => route.isFirst);
                        Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => const OrdersScreen(),
                          ),
                        );
                      }
                    },
            ),
          ],
        ),
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

    final matches =
        restaurantStore.restaurants.where((r) => r.name == vendor);
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
  });

  final String label;
  final double value;
  final bool isStrong;
  final bool accent;

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
        children: [
          Text(label, style: style),
          Text('€${value.toStringAsFixed(2)}', style: style),
        ],
      ),
    );
  }
}
