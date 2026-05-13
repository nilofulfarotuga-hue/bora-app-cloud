import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:vibration/vibration.dart';

import '../auth/auth_store.dart';
import '../config/app_colors.dart';
import '../widgets/bora_support_fab.dart';
import '../models/chat_message.dart';
import '../models/order_model.dart';
import '../models/restaurant_model.dart';
import 'chat_screen.dart';
import '../stores/order_store.dart';
import '../stores/partner_product_store.dart';
import '../stores/restaurant_store.dart';
import '../services/sound_service.dart';
import '../stores/session_store.dart';
import '../widgets/address_text.dart';
import 'partner/reservations/partner_reservations_home_screen.dart';
import 'partner_call_driver_screen.dart';
import 'partner_earnings_screen.dart';
import 'partner_hours_screen.dart';
import 'partner_products_screen.dart';

class PartnerDashboardScreen extends StatefulWidget {
  const PartnerDashboardScreen({super.key, required this.restaurant});

  final RestaurantModel restaurant;

  @override
  State<PartnerDashboardScreen> createState() => _PartnerDashboardScreenState();
}

class _PartnerDashboardScreenState extends State<PartnerDashboardScreen> {
  final Set<String> _knownCreatedOrderIds = <String>{};
  final SoundService _soundService = SoundService();
  Timer? _vibrationTimer;
  int _pendingReservationsCount = 0;
  final Set<String> _seenPendingReservationIds = <String>{};
  RealtimeChannel? _reservationsChannel;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      context.read<PartnerProductStore>().selectRestaurant(widget.restaurant);
      context.read<OrderStore>().loadOrders();
      unawaited(_loadPendingReservationsCount());
      _subscribeReservationsRealtime();
    });
  }

  Future<void> _loadPendingReservationsCount() async {
    try {
      final rows = await Supabase.instance.client
          .from('reservations')
          .select('id')
          .eq('restaurant_id', widget.restaurant.id)
          .eq('status', 'pending');
      if (!mounted) return;
      final list = (rows as List).cast<Map<String, dynamic>>();
      _seenPendingReservationIds
        ..clear()
        ..addAll(list.map((r) => r['id'].toString()));
      final count = list.length;
      if (count != _pendingReservationsCount) {
        setState(() => _pendingReservationsCount = count);
      }
    } catch (e) {
      debugPrint(
          '[PartnerDashboard] _loadPendingReservationsCount error: $e');
    }
  }

  void _subscribeReservationsRealtime() {
    if (_reservationsChannel != null) return;
    final channelName = 'partner_reservations_${widget.restaurant.id}';
    _reservationsChannel = Supabase.instance.client
        .channel(channelName)
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'reservations',
          callback: (payload) {
            if (!mounted) return;
            final rec = payload.newRecord;
            if (rec.isEmpty) return;
            if (rec['restaurant_id'] != widget.restaurant.id) return;
            if (rec['status'] != 'pending') return;
            final id = rec['id']?.toString();
            if (id == null || _seenPendingReservationIds.contains(id)) return;
            _seenPendingReservationIds.add(id);
            setState(() => _pendingReservationsCount += 1);
            final clientName =
                (rec['client_name'] as String?)?.trim().isNotEmpty == true
                    ? rec['client_name'] as String
                    : 'cliente';
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('Nova reserva de $clientName'),
                backgroundColor: AppColors.warning,
                duration: const Duration(seconds: 4),
              ),
            );
            debugPrint(
                '[PartnerDashboard] realtime new pending reservation $id');
          },
        )
        .onPostgresChanges(
          // BUG A — escutar UPDATE para decrementar quando status sai de
          // 'pending' (aceitar/rejeitar/sentar/etc) e re-incrementar se
          // voltar para pending.
          event: PostgresChangeEvent.update,
          schema: 'public',
          table: 'reservations',
          callback: (payload) {
            if (!mounted) return;
            final rec = payload.newRecord;
            if (rec.isEmpty) return;
            if (rec['restaurant_id'] != widget.restaurant.id) return;
            final id = rec['id']?.toString();
            if (id == null) return;
            final newStatus = rec['status'];
            final wasInSet = _seenPendingReservationIds.contains(id);
            if (newStatus != 'pending' && wasInSet) {
              _seenPendingReservationIds.remove(id);
              if (_pendingReservationsCount > 0) {
                setState(() => _pendingReservationsCount -= 1);
              }
              debugPrint(
                  '[PartnerDashboard] realtime pending→$newStatus reservation $id');
            } else if (newStatus == 'pending' && !wasInSet) {
              _seenPendingReservationIds.add(id);
              setState(() => _pendingReservationsCount += 1);
              debugPrint(
                  '[PartnerDashboard] realtime →pending reservation $id');
            }
          },
        )
      ..subscribe();
  }

  @override
  void dispose() {
    _reservationsChannel?.unsubscribe();
    _reservationsChannel = null;
    _vibrationTimer?.cancel();
    _soundService.dispose();
    super.dispose();
  }

  Future<void> _startVibrationLoop() async {
    if (_vibrationTimer != null) return;
    if (!(await Vibration.hasVibrator())) return;
    Vibration.vibrate(duration: 400);
    _vibrationTimer =
        Timer.periodic(const Duration(milliseconds: 2500), (_) {
      Vibration.vibrate(duration: 400);
    });
  }

  void _stopVibrationLoop() {
    _vibrationTimer?.cancel();
    _vibrationTimer = null;
  }

  Future<void> _handleTestMode() async {
    final authStore = context.read<AuthStore>();
    final sessionStore = context.read<SessionStore>();
    authStore.logout();
    await sessionStore.clearRole();
    if (!mounted) return;
    Navigator.of(context).popUntil((route) => route.isFirst);
  }

  void _handleNewOrders(List<OrderModel> orders) async {
    final createdIds = orders
        .where((order) => order.status == OrderStatus.created)
        .map((order) => order.id)
        .toSet();

    if (createdIds.isNotEmpty) {
      unawaited(_soundService.playLoop());
      unawaited(_startVibrationLoop());
    } else {
      unawaited(_soundService.stop());
      _stopVibrationLoop();
    }

    _knownCreatedOrderIds
      ..clear()
      ..addAll(createdIds);
  }

  String _ordersLabel(int count) {
    return count == 1 ? '1 pedido' : '$count pedidos';
  }

  double _sumEarningsSince(List<OrderModel> orders, DateTime threshold) {
    var total = 0.0;
    for (final order in orders) {
      if (order.createdAt.isBefore(threshold)) continue;
      total += _partnerRevenue(order);
    }
    return total;
  }

  double _partnerRevenue(OrderModel order) {
    final commission = order.platformCommissionAmount;
    final itemsValue = order.subtotal > 0
        ? order.subtotal
        : (order.total - order.deliveryFee - order.serviceFee);
    final revenue = itemsValue - commission;
    return revenue > 0 ? revenue : 0;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final partnerStore = context.watch<PartnerProductStore>();
    final orderStore = context.watch<OrderStore>();
    final restaurantStore = context.watch<RestaurantStore>();
    final currentRestaurant = restaurantStore.restaurants.firstWhere(
      (r) => r.id == widget.restaurant.id,
      orElse: () => widget.restaurant,
    );
    final products = partnerStore.productsForRestaurant(widget.restaurant.id);
    final availableProducts =
        products.where((product) => product.isAvailable).length;

    final partnerOrders =
        orderStore.partnerOrdersForRestaurant(widget.restaurant.name);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _handleNewOrders(partnerOrders);
    });

    final now = DateTime.now();
    final startOfToday = DateTime(now.year, now.month, now.day);
    final startOfWeek = startOfToday.subtract(const Duration(days: 6));
    final todayCount = partnerOrders
        .where((order) => !order.createdAt.isBefore(startOfToday))
        .length;
    final weekCount = partnerOrders
        .where((order) => !order.createdAt.isBefore(startOfWeek))
        .length;
    final totalCount = partnerOrders.length;

    final todayEarnings = _sumEarningsSince(partnerOrders, startOfToday);
    final weekEarnings = _sumEarningsSince(partnerOrders, startOfWeek);
    final totalEarnings = _sumEarningsSince(
      partnerOrders,
      DateTime.fromMillisecondsSinceEpoch(0),
    );

    final appBarForeground =
        theme.appBarTheme.foregroundColor ?? theme.colorScheme.onPrimary;
    final subtitleColor = appBarForeground.withValues(alpha: 0.7);

    return Scaffold(
      backgroundColor: AppColors.surface,
      floatingActionButton: const BoraSupportFab(),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        foregroundColor: Colors.white,
        elevation: 0,
        flexibleSpace: const DecoratedBox(
          decoration: BoxDecoration(gradient: AppColors.headerGradient),
        ),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              widget.restaurant.name,
              overflow: TextOverflow.ellipsis,
            ),
            Text(
              widget.restaurant.cuisineType,
              style: theme.textTheme.bodySmall?.copyWith(
                color: subtitleColor,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
        actions: [
          TextButton.icon(
            onPressed: () => restaurantStore.toggleRestaurantOnline(
                widget.restaurant.id, !currentRestaurant.isOnline),
            style: TextButton.styleFrom(
              foregroundColor: currentRestaurant.isOnline
                  ? Colors.greenAccent
                  : Colors.redAccent,
            ),
            icon: Icon(currentRestaurant.isOnline
                ? Icons.circle
                : Icons.circle_outlined),
            label: Text(currentRestaurant.isOnline ? 'ONLINE' : 'OFFLINE'),
          ),
          TextButton.icon(
            onPressed: _handleTestMode,
            style: TextButton.styleFrom(foregroundColor: appBarForeground),
            icon: const Icon(Icons.bug_report_outlined),
            label: const Text('Teste'),
          ),
        ],
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (currentRestaurant.reservationsEnabled &&
                    _pendingReservationsCount > 0) ...[
                  _PendingReservationsBadge(
                    count: _pendingReservationsCount,
                    onTap: () => Navigator.of(context)
                        .push(
                          MaterialPageRoute(
                            builder: (_) => PartnerReservationsHomeScreen(
                              restaurantId: currentRestaurant.id,
                              restaurantName: currentRestaurant.name,
                            ),
                          ),
                        )
                        // BUG A — refresh ao voltar de Reservas Pro.
                        .then((_) {
                      if (mounted) _loadPendingReservationsCount();
                    }),
                  ),
                  const SizedBox(height: 16),
                ],
                _EarningsSummary(
                  todayAmount: todayEarnings,
                  weekAmount: weekEarnings,
                  totalAmount: totalEarnings,
                  todayLabel: _ordersLabel(todayCount),
                  weekLabel: _ordersLabel(weekCount),
                  totalLabel: _ordersLabel(totalCount),
                ),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: () => Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => PartnerEarningsScreen(
                          restaurant: widget.restaurant,
                        ),
                      ),
                    ),
                    icon: const Icon(Icons.bar_chart),
                    label: const Text('Ver detalhe de ganhos'),
                  ),
                ),
                const SizedBox(height: 8),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: () => Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => PartnerHoursScreen(
                          restaurant: currentRestaurant,
                        ),
                      ),
                    ),
                    icon: const Icon(Icons.schedule),
                    label: const Text('Horários de funcionamento'),
                  ),
                ),
                const SizedBox(height: 24),
                _OverviewCard(
                  totalProducts: products.length,
                  availableProducts: availableProducts,
                ),
                const SizedBox(height: 16),
                _ReservationsToggleCard(
                  enabled: currentRestaurant.reservationsEnabled,
                  onChanged: (value) => restaurantStore
                      .toggleReservationsEnabled(currentRestaurant.id, value),
                ),
                if (currentRestaurant.reservationsEnabled) ...[
                  const SizedBox(height: 8),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: () => Navigator.of(context)
                          .push(
                            MaterialPageRoute(
                              builder: (_) => PartnerReservationsHomeScreen(
                                restaurantId: currentRestaurant.id,
                                restaurantName: currentRestaurant.name,
                              ),
                            ),
                          )
                          // BUG A — refresh ao voltar de Reservas Pro.
                          .then((_) {
                        if (mounted) _loadPendingReservationsCount();
                      }),
                      icon: const Icon(Icons.event_seat),
                      label: const Text('Reservas Pro'),
                    ),
                  ),
                ],
                const SizedBox(height: 24),
                _OrdersSection(
                  orders: partnerOrders,
                  onAccept: (order) async {
                    final accepted =
                        await orderStore.restaurantAcceptOrder(order);
                    if (!context.mounted) return;
                    // BUG F (2026-05-13) — incluir ultimos 4 chars do order id
                    // para o parceiro identificar QUAL pedido em situacoes
                    // com varios pedidos simultaneos.
                    final shortId = order.id.length >= 4
                        ? order.id.substring(order.id.length - 4).toUpperCase()
                        : order.id.toUpperCase();
                    final message = accepted
                        ? 'Pedido aceite — #$shortId. Prepare os itens.'
                        : 'Não foi possível aceitar o pedido — #$shortId.';
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text(message)),
                    );
                  },
                  onReject: (order) async {
                    final rejected =
                        await orderStore.restaurantRejectOrder(order);
                    if (!context.mounted) return;
                    final shortId = order.id.length >= 4
                        ? order.id.substring(order.id.length - 4).toUpperCase()
                        : order.id.toUpperCase();
                    final message = rejected
                        ? 'Pedido rejeitado — #$shortId.'
                        : 'Não foi possível rejeitar o pedido — #$shortId.';
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text(message)),
                    );
                  },
                  onCallDriver: (order) async {
                    final ready = await orderStore.restaurantMarkReady(order);
                    if (!context.mounted) return;
                    final shortId = order.id.length >= 4
                        ? order.id.substring(order.id.length - 4).toUpperCase()
                        : order.id.toUpperCase();
                    final message = ready
                        ? 'Estafeta a caminho — #$shortId'
                        : 'Não foi possível chamar o estafeta — #$shortId.';
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text(message)),
                    );
                  },
                ),
                const SizedBox(height: 24),
                Text(
                  'Ações rápidas',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 12),
                _ActionButton(
                  icon: Icons.inventory_2_outlined,
                  label: 'Gerir produtos',
                  description:
                      'Atualize o catálogo, ajuste disponibilidade e mantenha os itens organizados.',
                  onPressed: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => PartnerProductsScreen(
                          restaurant: widget.restaurant,
                        ),
                      ),
                    );
                  },
                ),
                const SizedBox(height: 12),
                _ActionButton(
                  icon: Icons.local_shipping_outlined,
                  label: 'Chamar estafeta',
                  description:
                      'Criar um pedido de entrega com os produtos disponíveis para envio imediato.',
                  onPressed: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => PartnerCallDriverScreen(
                          restaurant: widget.restaurant,
                        ),
                      ),
                    );
                  },
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _OrdersSection extends StatelessWidget {
  const _OrdersSection({
    required this.orders,
    required this.onAccept,
    required this.onReject,
    required this.onCallDriver,
  });

  final List<OrderModel> orders;
  final Future<void> Function(OrderModel) onAccept;
  final Future<void> Function(OrderModel) onReject;
  final Future<void> Function(OrderModel) onCallDriver;

  @override
  Widget build(BuildContext context) {
    if (orders.isEmpty) {
      return Card(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Row(
            children: [
              Icon(Icons.event_available,
                  color: Theme.of(context).colorScheme.primary),
              const SizedBox(width: 12),
              const Expanded(
                child: Text(
                  'Nenhum pedido pendente no momento.',
                  style: TextStyle(fontWeight: FontWeight.w500),
                ),
              ),
            ],
          ),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: orders
          .map(
            (order) => Padding(
              padding: const EdgeInsets.only(bottom: 16),
              child: _PartnerOrderCard(
                order: order,
                onAccept: onAccept,
                onReject: onReject,
                onCallDriver: onCallDriver,
              ),
            ),
          )
          .toList(),
    );
  }
}

class _PartnerOrderCard extends StatefulWidget {
  const _PartnerOrderCard({
    required this.order,
    required this.onAccept,
    required this.onReject,
    required this.onCallDriver,
  });

  final OrderModel order;
  final Future<void> Function(OrderModel) onAccept;
  final Future<void> Function(OrderModel) onReject;
  final Future<void> Function(OrderModel) onCallDriver;

  @override
  State<_PartnerOrderCard> createState() => _PartnerOrderCardState();
}

class _PartnerOrderCardState extends State<_PartnerOrderCard>
    with SingleTickerProviderStateMixin {
  late final AnimationController _flashController;

  /// Anti double-tap durante a chamada `restaurantMarkReady`. Map por orderId
  /// para coexistir com o pattern usado no resto do dashboard parceiro.
  final Map<String, bool> _chamandobusy = {};

  bool get _isNew => widget.order.status == OrderStatus.created;

  @override
  void initState() {
    super.initState();
    _flashController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    );
    _updateFlashing();
  }

  @override
  void didUpdateWidget(covariant _PartnerOrderCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.order.status != widget.order.status) {
      _updateFlashing();
    }
  }

  void _updateFlashing() {
    if (_isNew) {
      _flashController.repeat(reverse: true);
    } else {
      _flashController.stop();
      _flashController.value = 0;
    }
  }

  @override
  void dispose() {
    _flashController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AnimatedBuilder(
      animation: _flashController,
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: _buildContent(theme),
      ),
      builder: (context, child) {
        final highlight = theme.colorScheme.secondary.withValues(alpha: 0.22);
        final background = _isNew
            ? Color.lerp(Colors.white, highlight, _flashController.value)!
            : Colors.white;
        final elevation = _isNew ? 2.0 + (_flashController.value * 4) : 1.0;
        final borderSide = _isNew
            ? BorderSide(
                color: theme.colorScheme.secondary.withValues(alpha: 0.7),
                width: 1.2,
              )
            : BorderSide.none;
        return Card(
          color: background,
          elevation: elevation,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
            side: borderSide,
          ),
          child: child,
        );
      },
    );
  }

  Widget _buildContent(ThemeData theme) {
    final order = widget.order;
    final isNew = _isNew;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              isNew ? 'Novo pedido' : order.status.label,
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w700,
                color: isNew ? theme.colorScheme.primary : null,
              ),
            ),
            Text(
              '€${order.total.toStringAsFixed(2)}',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        // ── Cliente ──────────────────────────────────────────────────────
        Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Cliente',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: Colors.grey.shade600,
                    ),
                  ),
                  Text(
                    order.customerName ?? 'Cliente BORA',
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                ],
              ),
            ),
            if ((order.clientPhone ?? '').isNotEmpty) ...[
              IconButton(
                icon: const Icon(Icons.phone, size: 20),
                tooltip: 'Ligar cliente',
                onPressed: () async {
                  final uri = Uri(scheme: 'tel', path: order.clientPhone!);
                  if (await canLaunchUrl(uri)) {
                    await launchUrl(uri, mode: LaunchMode.externalApplication);
                  }
                },
              ),
              IconButton(
                icon: const Icon(Icons.chat_bubble_outline, size: 20),
                tooltip: 'Chat cliente',
                onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => ChatScreen(
                      order: order,
                      senderType: ChatSenderType.client,
                    ),
                  ),
                ),
              ),
            ],
          ],
        ),
        // ── Estafeta (aparece após aceitação) ────────────────────────────
        if (order.assignedDriverId != null) ...[
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Estafeta',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: Colors.grey.shade600,
                      ),
                    ),
                    Text(
                      (order.driverPhone ?? '').isNotEmpty
                          ? order.driverPhone!
                          : 'Em trânsito',
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                  ],
                ),
              ),
              if ((order.driverPhone ?? '').isNotEmpty) ...[
                IconButton(
                  icon: const Icon(Icons.phone, size: 20),
                  tooltip: 'Ligar estafeta',
                  onPressed: () async {
                    final uri = Uri(scheme: 'tel', path: order.driverPhone!);
                    if (await canLaunchUrl(uri)) {
                      await launchUrl(uri,
                          mode: LaunchMode.externalApplication);
                    }
                  },
                ),
                IconButton(
                  icon: const Icon(Icons.chat_bubble_outline, size: 20),
                  tooltip: 'Chat estafeta',
                  onPressed: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => ChatScreen(
                        order: order,
                        senderType: ChatSenderType.driver,
                      ),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ],
        if ((order.dropoffAddress ?? '').isNotEmpty ||
            order.destination != null)
          _InfoRow(
            label: 'Entrega',
            value: '',
            valueWidget: AddressText(
              rawAddress: order.dropoffAddress,
              coords: order.destination,
            ),
          ),
        const SizedBox(height: 12),
        Text(
          'Itens',
          style:
              theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 8),
        if (order.items.isEmpty)
          Text(
            order.customerNotes?.isNotEmpty == true
                ? order.customerNotes!
                : 'Detalhes indisponíveis.',
          )
        else
          ...order.items.map(
            (item) => Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: Text(
                '• ${item.quantity} × ${item.name} — €${(item.price * item.quantity).toStringAsFixed(2)}',
              ),
            ),
          ),
        const SizedBox(height: 16),
        Row(
          children: [
            if (order.status == OrderStatus.created) ...[
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: () {
                    widget.onAccept(order);
                  },
                  icon: const Icon(Icons.check),
                  label: const Text('Aceitar pedido'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () {
                    widget.onReject(order);
                  },
                  icon: const Icon(Icons.close),
                  label: const Text('Rejeitar'),
                ),
              ),
            ] else ...[
              Expanded(child: _buildBotaoEstafeta(order)),
            ],
          ],
        ),
      ],
    );
  }

  Future<void> _chamarEstafeta(OrderModel order) async {
    final orderId = order.id;
    if (_chamandobusy[orderId] == true) return;

    setState(() => _chamandobusy[orderId] = true);
    try {
      await widget.onCallDriver(order);
    } finally {
      if (mounted) {
        setState(() => _chamandobusy.remove(orderId));
      }
    }
  }

  Widget _buildBotaoEstafeta(OrderModel order) {
    final busy = _chamandobusy[order.id] == true;

    switch (order.status) {
      case OrderStatus.preparing:
        return SizedBox(
          width: double.infinity,
          child: ElevatedButton.icon(
            onPressed: busy ? null : () => _chamarEstafeta(order),
            icon: busy
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : const Icon(Icons.delivery_dining),
            label: Text(busy ? 'A chamar...' : 'Chamar estafeta'),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFE65100),
              foregroundColor: Colors.white,
              minimumSize: const Size(double.infinity, 48),
            ),
          ),
        );

      case OrderStatus.callingDriver:
        return SizedBox(
          width: double.infinity,
          child: ElevatedButton.icon(
            onPressed: null,
            icon: const SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: Colors.white70,
              ),
            ),
            label: const Text('Aguardando estafeta...'),
            style: ElevatedButton.styleFrom(
              disabledBackgroundColor: Colors.grey.shade400,
              disabledForegroundColor: Colors.white,
              minimumSize: const Size(double.infinity, 48),
            ),
          ),
        );

      case OrderStatus.driverAccepted:
      case OrderStatus.pickedUp:
      case OrderStatus.onTheWay:
        return SizedBox(
          width: double.infinity,
          child: ElevatedButton.icon(
            onPressed: null,
            icon: const Icon(Icons.directions_bike),
            label: const Text('Estafeta a caminho'),
            style: ElevatedButton.styleFrom(
              disabledBackgroundColor: Colors.grey.shade400,
              disabledForegroundColor: Colors.white,
              minimumSize: const Size(double.infinity, 48),
            ),
          ),
        );

      case OrderStatus.delivered:
        return SizedBox(
          width: double.infinity,
          child: ElevatedButton.icon(
            onPressed: null,
            icon: const Icon(Icons.check_circle),
            label: const Text('Entregue ✓'),
            style: ElevatedButton.styleFrom(
              disabledBackgroundColor: const Color(0xFF1B5E20),
              disabledForegroundColor: Colors.white,
              minimumSize: const Size(double.infinity, 48),
            ),
          ),
        );

      case OrderStatus.rejected:
      case OrderStatus.cancelled:
        return SizedBox(
          width: double.infinity,
          child: OutlinedButton.icon(
            onPressed: null,
            icon: const Icon(Icons.cancel_outlined),
            label: Text(order.status.label),
            style: OutlinedButton.styleFrom(
              minimumSize: const Size(double.infinity, 48),
              foregroundColor: Colors.grey,
            ),
          ),
        );

      case OrderStatus.created:
        return const SizedBox.shrink();
    }
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({required this.label, required this.value, this.valueWidget});

  final String label;
  final String value;
  final Widget? valueWidget;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '$label: ',
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
          Expanded(
            child: valueWidget ?? Text(value.isEmpty ? '-' : value),
          ),
        ],
      ),
    );
  }
}

class _EarningsSummary extends StatelessWidget {
  const _EarningsSummary({
    required this.todayAmount,
    required this.weekAmount,
    required this.totalAmount,
    required this.todayLabel,
    required this.weekLabel,
    required this.totalLabel,
  });

  final double todayAmount;
  final double weekAmount;
  final double totalAmount;
  final String todayLabel;
  final String weekLabel;
  final String totalLabel;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final isCompact = constraints.maxWidth < 600;
        final cards = <Widget>[
          _EarningCard(
            title: 'Ganhos hoje',
            subtitle: todayLabel,
            amount: todayAmount,
            icon: Icons.today_outlined,
          ),
          _EarningCard(
            title: 'Ganhos semana',
            subtitle: weekLabel,
            amount: weekAmount,
            icon: Icons.date_range_outlined,
          ),
          _EarningCard(
            title: 'Ganhos totais',
            subtitle: totalLabel,
            amount: totalAmount,
            icon: Icons.savings_outlined,
          ),
        ];

        if (isCompact) {
          return Column(
            children: [
              for (var i = 0; i < cards.length; i++) ...[
                cards[i],
                if (i < cards.length - 1) const SizedBox(height: 12),
              ],
            ],
          );
        }

        return Row(
          children: [
            Expanded(child: cards[0]),
            const SizedBox(width: 12),
            Expanded(child: cards[1]),
            const SizedBox(width: 12),
            Expanded(child: cards[2]),
          ],
        );
      },
    );
  }
}

class _EarningCard extends StatelessWidget {
  const _EarningCard({
    required this.title,
    required this.subtitle,
    required this.amount,
    required this.icon,
  });

  final String title;
  final String subtitle;
  final double amount;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final primary = theme.colorScheme.primary;
    final formattedAmount = '€${amount.toStringAsFixed(2)}';

    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            CircleAvatar(
              radius: 22,
              backgroundColor: primary.withValues(alpha: 0.1),
              child: Icon(icon, color: primary),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.textTheme.bodySmall?.color,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    formattedAmount,
                    style: theme.textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    subtitle,
                    style: theme.textTheme.bodySmall,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _OverviewCard extends StatelessWidget {
  const _OverviewCard({
    required this.totalProducts,
    required this.availableProducts,
  });

  final int totalProducts;
  final int availableProducts;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final unavailable = totalProducts - availableProducts;
    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Resumo do catálogo',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                _OverviewStat(
                  label: 'Total',
                  value: '$totalProducts',
                  icon: Icons.layers_outlined,
                  color: theme.colorScheme.primary,
                ),
                const SizedBox(width: 16),
                _OverviewStat(
                  label: 'Disponíveis',
                  value: '$availableProducts',
                  icon: Icons.check_circle_outline,
                  color: Colors.green.shade600,
                ),
                const SizedBox(width: 16),
                _OverviewStat(
                  label: 'Indisponíveis',
                  value: '$unavailable',
                  icon: Icons.pause_circle_outline,
                  color: Colors.orange.shade600,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _OverviewStat extends StatelessWidget {
  const _OverviewStat({
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
  });

  final String label;
  final String value;
  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Expanded(
      child: Container(
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(12),
        ),
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: color),
            const SizedBox(height: 8),
            Text(
              value,
              style: theme.textTheme.headlineSmall?.copyWith(
                color: color,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              label,
              style: theme.textTheme.bodyMedium,
            ),
          ],
        ),
      ),
    );
  }
}

/// BR §14.10 — opt-in do parceiro para mostrar o botão "Reservar mesa" ao cliente.
class _ReservationsToggleCard extends StatelessWidget {
  const _ReservationsToggleCard({
    required this.enabled,
    required this.onChanged,
  });

  final bool enabled;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: Colors.grey.shade300),
      ),
      child: SwitchListTile.adaptive(
        value: enabled,
        onChanged: onChanged,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        title: const Text(
          'Aceitar reservas de mesa',
          style: TextStyle(fontWeight: FontWeight.w600),
        ),
        subtitle: Text(
          enabled
              ? 'O botão "Reservar mesa" aparece aos clientes.'
              : 'Desligado — reservas ocultas aos clientes. (BR §14.10)',
          style: const TextStyle(fontSize: 12),
        ),
        activeColor: const Color(0xFF1B5E20),
      ),
    );
  }
}

class _ActionButton extends StatelessWidget {
  const _ActionButton({
    required this.icon,
    required this.label,
    required this.description,
    required this.onPressed,
  });

  final IconData icon;
  final String label;
  final String description;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: onPressed,
      child: Ink(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          color: theme.colorScheme.surface,
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.06),
              blurRadius: 12,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        padding: const EdgeInsets.all(20),
        child: Row(
          children: [
            CircleAvatar(
              radius: 24,
              backgroundColor: theme.colorScheme.primary.withValues(alpha: 0.1),
              child: Icon(icon, color: theme.colorScheme.primary),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    description,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.textTheme.bodySmall?.color,
                    ),
                  ),
                ],
              ),
            ),
            const Icon(Icons.chevron_right),
          ],
        ),
      ),
    );
  }
}

class _PendingReservationsBadge extends StatelessWidget {
  const _PendingReservationsBadge({
    required this.count,
    required this.onTap,
  });

  final int count;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final label = count == 1
        ? '1 reserva pendente'
        : '$count reservas pendentes';
    return Material(
      color: AppColors.warning,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Row(
            children: [
              const Icon(Icons.event_seat, color: Colors.white, size: 22),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                        fontSize: 15,
                      ),
                    ),
                    const SizedBox(height: 2),
                    const Text(
                      'Toca para abrir Reservas Pro',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right, color: Colors.white),
            ],
          ),
        ),
      ),
    );
  }
}
