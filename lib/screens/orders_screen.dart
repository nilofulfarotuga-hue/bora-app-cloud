import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../auth/auth_store.dart';
import '../config/app_colors.dart';
import '../config/app_spacing.dart';
import '../models/order_model.dart';
import 'errand_form_screen.dart';
import '../services/wallet_service.dart';
import '../stores/order_store.dart';
import '../widgets/bora/bora_screen_app_bar.dart';
import '../widgets/bora_support_fab.dart';
import 'order_details_screen.dart';
import 'restaurants_screen.dart';
import 'wallet_history_screen.dart';

import '../l10n/tr.dart';

class OrdersScreen extends StatefulWidget {
  const OrdersScreen({super.key});

  @override
  State<OrdersScreen> createState() => _OrdersScreenState();
}

class _OrdersScreenState extends State<OrdersScreen> {
  StreamSubscription<AuthState>? _authSub;
  // Sessão 3B: ids de pedidos com ajustes wallet (debit/settlement) para
  // mostrar ícone "carteira" no card.
  Map<String, List<WalletTx>> _walletByOrder = const {};

  @override
  void initState() {
    super.initState();
    _authSub = Supabase.instance.client.auth.onAuthStateChange.listen((data) {
      if (data.event == AuthChangeEvent.signedIn && mounted) {
        context.read<OrderStore>().loadOrders();
        _loadWallet();
      }
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        context.read<OrderStore>().loadOrders();
        _loadWallet();
      }
    });
  }

  Future<void> _loadWallet() async {
    try {
      final b = await WalletService.instance.getBalance();
      final map = <String, List<WalletTx>>{};
      for (final tx in b.lastTransactions) {
        if (tx.relatedOrderId == null) continue;
        if (tx.kind != 'debit' && tx.kind != 'settlement') continue;
        map.putIfAbsent(tx.relatedOrderId!, () => []).add(tx);
      }
      if (mounted) setState(() => _walletByOrder = map);
    } catch (_) {/* offline / sem wallet */}
  }

  @override
  void dispose() {
    _authSub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final store = context.watch<OrderStore>();
    final authStore = context.watch<AuthStore>();
    final phone = authStore.currentClient?.phone ?? '';
    final userId = authStore.userId;

    final orders = store.ordersForCurrentClient(phone: phone, userId: userId);
    // Loader só quando há fetch activo E ainda nada a mostrar — combinado
    // com o anti-wipe guard em OrderStore evita o "loading infinito".
    final showInitialLoader = store.isLoading && orders.isEmpty;

    return Scaffold(
      backgroundColor: AppColors.background,
      floatingActionButton: const BoraSupportFab(),
      appBar: BoraScreenAppBar(title: 'Pedidos'.tr),
      body: showInitialLoader
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: () => store.loadOrders(),
              color: AppColors.primary,
              child: orders.isEmpty
                  ? LayoutBuilder(
                      builder: (context, constraints) => SingleChildScrollView(
                        physics: const AlwaysScrollableScrollPhysics(),
                        child: ConstrainedBox(
                          constraints: BoxConstraints(
                            minHeight: constraints.maxHeight,
                          ),
                          child: const _EmptyOrders(),
                        ),
                      ),
                    )
                  : ListView.separated(
                      physics: const AlwaysScrollableScrollPhysics(),
                      padding: const EdgeInsets.fromLTRB(
                          Spacing.lg, Spacing.md, Spacing.lg, Spacing.xxl),
                      itemCount: orders.length,
                      separatorBuilder: (_, __) =>
                          const SizedBox(height: Spacing.sm),
                      itemBuilder: (context, index) {
                        final order = orders[index];
                        final card = _OrderCard(
                          order: order,
                          walletTxs: _walletByOrder[order.id] ?? const [],
                          onTap: () => Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) =>
                                  OrderDetailsScreen(order: order),
                            ),
                          ),
                        );
                        // N3 — "Pedir de novo" para favores: pré-preenche o
                        // wizard a partir dos campos errand_* do pedido.
                        if (order.serviceType != OrderServiceType.errand) {
                          return card;
                        }
                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            card,
                            const SizedBox(height: 6),
                            OutlinedButton.icon(
                              onPressed: () => Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => ErrandFormScreen(
                                    prefill: ErrandPrefill(
                                      description: order.errandDescription ?? '',
                                      location: order.errandLocation ?? '',
                                      hasPurchase: order.errandHasPurchase,
                                      estimatedCents:
                                          order.errandEstimatedPurchaseCents,
                                      speed: order.errandSpeed ?? 'normal',
                                      homeStop: order.errandHomeStop,
                                      homeStopReason: order.errandHomeStopReason,
                                    ),
                                  ),
                                ),
                              ),
                              icon: const Icon(Icons.refresh, size: 18),
                              label: Text('Pedir de novo'.tr),
                            ),
                          ],
                        );
                      },
                    ),
            ),
    );
  }
}

class _EmptyOrders extends StatelessWidget {
  const _EmptyOrders();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: Spacing.xxl),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.receipt_long_outlined,
            size: 72,
            color: AppColors.textSecondary.withValues(alpha: 0.4),
          ),
          const SizedBox(height: Spacing.lg),
          Text(
            'Ainda não fizeste pedidos'.tr,
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w800,
              color: AppColors.textPrimary,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: Spacing.sm),
          Text(
            'Explora os restaurantes e lojas disponíveis na tua área.'.tr,
            style: const TextStyle(fontSize: 14, color: AppColors.textSecondary),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: Spacing.xl),
          OutlinedButton.icon(
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const RestaurantsScreen()),
            ),
            icon: const Icon(Icons.restaurant_menu),
            label: Text('Ver restaurantes'.tr),
            style: OutlinedButton.styleFrom(
              foregroundColor: AppColors.primary,
              side: const BorderSide(color: AppColors.primary, width: 1.5),
              padding: const EdgeInsets.symmetric(
                  horizontal: Spacing.xl, vertical: Spacing.md),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(Radii.md),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _OrderCard extends StatelessWidget {
  const _OrderCard({
    required this.order,
    required this.onTap,
    this.walletTxs = const [],
  });

  final OrderModel order;
  final VoidCallback onTap;
  /// Sessão 3B: transactions wallet (debit/settlement) deste pedido.
  final List<WalletTx> walletTxs;

  @override
  Widget build(BuildContext context) {
    final totalLabel = order.isPurchaseFinalized && order.finalTotal != null
        ? '€${order.finalTotal!.toStringAsFixed(2)}'
        : '€${order.total.toStringAsFixed(2)}';
    final hasWalletAdjust = walletTxs.isNotEmpty;

    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(Radii.lg),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(Radii.lg),
        child: Container(
          padding: const EdgeInsets.symmetric(
              horizontal: Spacing.lg, vertical: Spacing.md),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(Radii.lg),
            boxShadow: AppColors.shadowCard,
          ),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          order.orderCode,
                          style: const TextStyle(
                            fontSize: 13,
                            color: AppColors.textSecondary,
                            fontWeight: FontWeight.w600,
                            letterSpacing: 0.5,
                          ),
                        ),
                        const Spacer(),
                        Text(
                          totalLabel,
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w800,
                            color: AppColors.textPrimary,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: Spacing.xs),
                    if (order.vendorName != null &&
                        order.vendorName!.isNotEmpty)
                      Text(
                        order.vendorName!,
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          color: AppColors.textPrimary,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    const SizedBox(height: Spacing.sm),
                    Row(
                      children: [
                        _StatusChip(status: order.status),
                        if (hasWalletAdjust) ...[
                          const SizedBox(width: 8),
                          GestureDetector(
                            onTap: () => _showWalletAdjustModal(context, walletTxs),
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 8, vertical: 4),
                              decoration: BoxDecoration(
                                color: Colors.deepPurple.shade50,
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(
                                    color: Colors.deepPurple.shade200),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(Icons.account_balance_wallet,
                                      size: 12,
                                      color: Colors.deepPurple.shade700),
                                  const SizedBox(width: 4),
                                  Text('Carteira'.tr,
                                      style: TextStyle(
                                          fontSize: 11,
                                          color: Colors.deepPurple.shade700,
                                          fontWeight: FontWeight.w600)),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: Spacing.sm),
              Icon(
                Icons.chevron_right,
                color: AppColors.textSecondary.withValues(alpha: 0.5),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Modal Sessão 3B: detalhes dos ajustes wallet ligados a um pedido.
void _showWalletAdjustModal(BuildContext context, List<WalletTx> txs) {
  showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    builder: (ctx) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Icon(Icons.account_balance_wallet,
                  color: Colors.deepPurple.shade700),
              const SizedBox(width: 8),
              Text('Ajustes na carteira'.tr,
                  style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
            ]),
            const SizedBox(height: 4),
            Text(
              'Movimentos relacionados com este pedido.'.tr,
              style: const TextStyle(fontSize: 12, color: Colors.black54),
            ),
            const SizedBox(height: 12),
            ...txs.map((tx) {
              final amount = (tx.amountCents.abs() / 100).toStringAsFixed(2);
              final sign = tx.isCredit ? '+' : '−';
              return ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Icon(
                  tx.kind == 'settlement'
                      ? Icons.swap_horiz
                      : Icons.shopping_basket,
                  color: tx.kind == 'settlement'
                      ? Colors.deepPurple
                      : Colors.red.shade700,
                ),
                title: Text(tx.kindLabel),
                subtitle: Text(tx.reason),
                trailing: Text(
                  '$sign€$amount',
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    color: tx.isCredit ? Colors.green : Colors.red,
                  ),
                ),
              );
            }),
            const SizedBox(height: 8),
            Center(
              child: TextButton.icon(
                icon: const Icon(Icons.history),
                label: Text('Ver histórico completo'.tr),
                onPressed: () {
                  Navigator.pop(ctx);
                  Navigator.push(
                      context,
                      MaterialPageRoute(
                          builder: (_) => const WalletHistoryScreen()));
                },
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.status});

  final OrderStatus status;

  Color _color() {
    switch (status) {
      case OrderStatus.delivered:
        return AppColors.success;
      case OrderStatus.readyForPickup:
        return AppColors.success; // takeaway pronto = positivo
      case OrderStatus.rejected:
      case OrderStatus.cancelled:
        return AppColors.error;
      case OrderStatus.driverAccepted:
        return AppColors.info;
      case OrderStatus.pickedUp:
      case OrderStatus.onTheWay:
        return AppColors.accent;
      case OrderStatus.preparing:
      case OrderStatus.callingDriver:
        return AppColors.warning;
      case OrderStatus.created:
        return AppColors.textSecondary;
    }
  }

  @override
  Widget build(BuildContext context) {
    final color = _color();
    return Container(
      padding: const EdgeInsets.symmetric(
          horizontal: Spacing.sm, vertical: Spacing.xs),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(Radii.pill),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 6),
          Text(
            status.label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}
