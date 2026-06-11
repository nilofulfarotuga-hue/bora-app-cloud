import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../auth/auth_store.dart';
import '../config/app_colors.dart';
import '../models/order_model.dart';
import '../models/restaurant_model.dart';
import 'partner_call_driver_screen.dart';
import 'partner_products_screen.dart';
import '../widgets/address_text.dart';
import '../widgets/bora_support_fab.dart';
import 'register_partner_screen.dart';
import '../stores/order_store.dart';
import '../stores/restaurant_store.dart';
import '../stores/session_store.dart';

class RestaurantDashboardScreen extends StatelessWidget {
  const RestaurantDashboardScreen({super.key, this.partnerRestaurant});

  final RestaurantModel? partnerRestaurant;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final switchModeColor =
        theme.appBarTheme.foregroundColor ?? theme.colorScheme.onPrimary;
    final restaurantStore = context.watch<RestaurantStore>();
    final authStore = context.watch<AuthStore>();
    final sessionRole = context.watch<SessionStore>().role;
    final isPartnerSession =
        sessionRole == UserRole.partner || authStore.role == AuthRole.partner;
    final isPartnerContext = partnerRestaurant != null || isPartnerSession;

    final restaurants = () {
      if (partnerRestaurant != null) {
        final refreshed =
            restaurantStore.restaurantByEmail(partnerRestaurant!.email);
        if (refreshed != null) {
          return <RestaurantModel>[refreshed];
        }
        return <RestaurantModel>[partnerRestaurant!];
      }

      if (isPartnerSession) {
        final partner = authStore.currentPartner;
        if (partner == null) return <RestaurantModel>[];
        final restaurant = restaurantStore.restaurantByEmail(partner.email);
        if (restaurant == null) {
          return <RestaurantModel>[];
        }
        return <RestaurantModel>[restaurant];
      }

      return restaurantStore.restaurants;
    }();

    if (restaurants.isEmpty) {
      return Scaffold(
        backgroundColor: AppColors.surface,
        floatingActionButton: const BoraSupportFab(),
        appBar: AppBar(
          backgroundColor: AppColors.primary,
          foregroundColor: Colors.white,
          elevation: 0,
          flexibleSpace: const DecoratedBox(
            decoration: BoxDecoration(gradient: AppColors.headerGradient),
          ),
          leading: IconButton(
            icon: const Icon(Icons.arrow_back_ios_new_rounded),
            onPressed: () {
              Navigator.of(context)
                  .pushNamedAndRemoveUntil('/', (route) => false);
            },
            tooltip: 'Voltar',
          ),
          title: const Text(
            'Painel do Parceiro',
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
        ),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.store_mall_directory_outlined,
                    size: 64, color: Colors.grey),
                const SizedBox(height: 16),
                Text(
                  isPartnerContext
                      ? 'Complete o registo do seu restaurante para aceder ao painel.'
                      : 'Nenhum restaurante disponível no momento.\nAdicione parceiros através da consola interna.',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodyLarge?.copyWith(
                    color: Colors.grey.shade700,
                  ),
                ),
                if (isPartnerContext) ...[
                  const SizedBox(height: 24),
                  ElevatedButton.icon(
                    onPressed: () {
                      Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => const RegisterPartnerScreen(),
                        ),
                      );
                    },
                    icon: const Icon(Icons.store_mall_directory_outlined),
                    label: const Text('Registar restaurante'),
                  ),
                ],
              ],
            ),
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: AppColors.background,
      floatingActionButton: const BoraSupportFab(),
      appBar: AppBar(
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        elevation: 0,
        flexibleSpace: const DecoratedBox(
          decoration: BoxDecoration(gradient: AppColors.headerGradient),
        ),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded),
          onPressed: () {
            Navigator.of(context)
                .pushNamedAndRemoveUntil('/', (route) => false);
          },
          tooltip: 'Voltar',
        ),
        title: const Text(
          'Painel do Parceiro',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        actions: [
          TextButton.icon(
            onPressed: () async {
              final navigator = Navigator.of(context);
              final authStore = context.read<AuthStore>();
              final sessionStore = context.read<SessionStore>();
              authStore.logout();
              await sessionStore.clearRole();
              if (!navigator.mounted) return;
              navigator.pushNamedAndRemoveUntil('/', (route) => false);
            },
            style: TextButton.styleFrom(
              foregroundColor: switchModeColor,
              padding: const EdgeInsets.symmetric(horizontal: 12),
            ),
            icon: Icon(Icons.swap_horiz, color: switchModeColor),
            label: const Text('Mudar modo'),
          ),
        ],
      ),
      body: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: restaurants.length,
        itemBuilder: (context, index) {
          final restaurant = restaurants[index];
          final orders = restaurantStore.ordersForRestaurant(restaurant.id);
          return Card(
            margin: const EdgeInsets.only(bottom: 16),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (restaurant.photoUrl.isNotEmpty)
                    ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: Image.network(
                        restaurant.photoUrl,
                        height: 140,
                        width: double.infinity,
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => const SizedBox.shrink(),
                      ),
                    ),
                  if (restaurant.photoUrl.isNotEmpty)
                    const SizedBox(height: 12),
                  Text(
                    restaurant.name,
                    style: theme.textTheme.titleLarge,
                  ),
                  const SizedBox(height: 4),
                  Text(restaurant.address),
                  const SizedBox(height: 4),
                  Text('Categoria: ${restaurant.category.label}'),
                  const SizedBox(height: 4),
                  Text('Telefone: ${restaurant.phone}'),
                  Text('Email: ${restaurant.email}'),
                  Text('Cozinha: ${restaurant.cuisineType}'),
                  const SizedBox(height: 12),
                  if (isPartnerContext)
                    Wrap(
                      spacing: 12,
                      runSpacing: 8,
                      alignment: WrapAlignment.end,
                      children: [
                        ElevatedButton.icon(
                          onPressed: () async {
                            final created = await Navigator.push<bool>(
                              context,
                              MaterialPageRoute(
                                builder: (_) => PartnerCallDriverScreen(
                                    restaurant: restaurant),
                              ),
                            );
                            if (!context.mounted || created != true) return;
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text(
                                    'Pedido de entrega enviado. Estafetas notificados.'),
                              ),
                            );
                          },
                          icon: const Icon(Icons.local_shipping_outlined),
                          label: const Text('Chamar estafeta'),
                        ),
                        OutlinedButton.icon(
                          onPressed: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => PartnerProductsScreen(
                                    restaurant: restaurant),
                              ),
                            );
                          },
                          icon: const Icon(Icons.store_mall_directory_outlined),
                          label: const Text('Gerir produtos'),
                        ),
                      ],
                    ),
                  if (isPartnerContext) const SizedBox(height: 12),
                  if (orders.isEmpty) const Text('Nenhum pedido pendente.'),
                  if (orders.isNotEmpty)
                    ...orders.map((order) => _OrderTile(order: order)),
                  if (isPartnerContext && orders.isNotEmpty) ...[
                    const SizedBox(height: 16),
                    _PartnerEarningsSection(restaurant: restaurant),
                  ],
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

class _OrderTile extends StatefulWidget {
  const _OrderTile({required this.order});

  final OrderModel order;

  @override
  State<_OrderTile> createState() => _OrderTileState();
}

class _OrderTileState extends State<_OrderTile> {
  bool _isProcessing = false;

  Future<void> _accept() async {
    if (_isProcessing) return;
    setState(() => _isProcessing = true);
    final orderStore = context.read<OrderStore>();
    // restaurantAcceptOrder returns Future<bool>
    final success = await orderStore.restaurantAcceptOrder(widget.order);
    if (!mounted) return;
    setState(() => _isProcessing = false);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          success
              ? 'Pedido aceite. Preparação iniciada.'
              : 'Não foi possível atualizar o pedido.',
        ),
      ),
    );
  }

  Future<void> _reject() async {
    if (_isProcessing) return;
    final messenger = ScaffoldMessenger.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Rejeitar pedido?'),
          content:
              Text('Tem a certeza que pretende rejeitar o pedido ${widget.order.id}?'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('Cancelar'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: const Text('Rejeitar pedido'),
            ),
          ],
        );
      },
    );

    if (confirmed != true || !mounted) return;
    setState(() => _isProcessing = true);
    final orderStore = context.read<OrderStore>();
    final success = await orderStore.restaurantRejectOrder(widget.order);
    if (!mounted) return;
    setState(() => _isProcessing = false);
    messenger.showSnackBar(
      SnackBar(
        content: Text(
          success ? 'Pedido rejeitado.' : 'Não foi possível rejeitar o pedido.',
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final order = widget.order;
    final isCreated = order.status == OrderStatus.created;
    final isPreparing = order.status == OrderStatus.preparing;

    return Container(
      margin: const EdgeInsets.only(top: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.surface2,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Pedido ${order.id}',
              style: const TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 4),
          Text('Total: €${order.total.toStringAsFixed(2)}'),
          if (order.customerName != null && order.customerName!.isNotEmpty)
            Text('Cliente: ${order.customerName!}'),
          if (order.clientPhone != null && order.clientPhone!.isNotEmpty)
            Text('Telefone: ${order.clientPhone!}'),
          if (order.dropoffAddress != null || order.destination != null)
            AddressText(
                rawAddress: order.dropoffAddress,
                coords: order.destination,
                prefix: 'Entrega: '),
          if (order.customerNotes != null && order.customerNotes!.isNotEmpty)
            Text('Nota: ${order.customerNotes!}'),
          const SizedBox(height: 8),
          Row(
            children: [
              Chip(label: Text(order.status.label)),
              if (isCreated) ...[
                const Spacer(),
                if (_isProcessing)
                  const SizedBox(
                    height: 24,
                    width: 24,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                else ...[
                  ElevatedButton(
                    onPressed: _accept,
                    child: const Text('Aceitar pedido'),
                  ),
                  const SizedBox(width: 8),
                  OutlinedButton(
                    onPressed: _reject,
                    child: const Text('Rejeitar pedido'),
                  ),
                ],
              ],
            ],
          ),
          if (isPreparing) ...[
            const SizedBox(height: 12),
            const _OrderStatusNote(
              icon: Icons.timer,
              message:
                  'Preparação em andamento. Um estafeta será chamado automaticamente em até 5 minutos.',
              color: Colors.orange,
            ),
          ],
          if (order.status == OrderStatus.callingDriver) ...[
            const SizedBox(height: 12),
            const _OrderStatusNote(
              icon: Icons.delivery_dining,
              message: 'Estamos a procurar o melhor estafeta disponível.',
              color: Colors.blue,
            ),
          ],
        ],
      ),
    );
  }
}

class _OrderStatusNote extends StatelessWidget {
  const _OrderStatusNote({
    required this.icon,
    required this.message,
    required this.color,
  });

  final IconData icon;
  final String message;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          Icon(icon, color: color),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              message,
              style: theme.textTheme.bodyMedium,
            ),
          ),
        ],
      ),
    );
  }
}

class _PartnerEarningsSection extends StatelessWidget {
  const _PartnerEarningsSection({required this.restaurant});

  final RestaurantModel restaurant;

  static bool _isSameDay(DateTime a, DateTime b) {
    final localA = a.toLocal();
    final localB = b.toLocal();
    return localA.year == localB.year &&
        localA.month == localB.month &&
        localA.day == localB.day;
  }

  static DateTime _startOfDay(DateTime date) {
    final local = date.toLocal();
    return DateTime(local.year, local.month, local.day);
  }

  String _formatCurrency(double value) => '€${value.toStringAsFixed(2)}';

  String _formatDateTime(DateTime dateTime) {
    final local = dateTime.toLocal();
    final day = local.day.toString().padLeft(2, '0');
    final month = local.month.toString().padLeft(2, '0');
    final hour = local.hour.toString().padLeft(2, '0');
    final minute = local.minute.toString().padLeft(2, '0');
    return '$day/$month/${local.year} • $hour:$minute';
  }

  Widget _buildSummaryRow(
    BuildContext context,
    String label,
    String value, {
    bool emphasize = false,
  }) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          Expanded(
            child: Text(label, style: theme.textTheme.bodyMedium),
          ),
          Text(
            value,
            style: theme.textTheme.bodyMedium?.copyWith(
              fontWeight: emphasize ? FontWeight.w600 : FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final orderStore = context.watch<OrderStore>();
    final theme = Theme.of(context);
    final orders = orderStore.partnerOrdersForRestaurant(restaurant.name);

    if (orders.isEmpty) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Ganhos', style: theme.textTheme.titleMedium),
          const SizedBox(height: 8),
          const Text(
              'Ainda não há pedidos. Os ganhos aparecem assim que houver pedidos.'),
        ],
      );
    }

    final nonRejectedOrders =
        orders.where((order) => order.status != OrderStatus.rejected).toList();

    final today = DateTime.now();
    final todayStart = _startOfDay(today);
    final weekStart = todayStart.subtract(const Duration(days: 6));

    double totalFor(Iterable<OrderModel> items) =>
        items.fold<double>(0, (sum, order) => sum + order.total);
    double commissionFor(Iterable<OrderModel> items) => items.fold<double>(
        0, (sum, order) => sum + order.platformCommissionAmount);
    double restaurantFor(Iterable<OrderModel> items) => items.fold<double>(
        0, (sum, order) => sum + order.restaurantEarningsAmount);

    final dailyOrders = nonRejectedOrders
        .where((order) => _isSameDay(order.createdAt, todayStart))
        .toList();
    final dailyCount = dailyOrders.length;
    final dailyTotal = totalFor(dailyOrders);
    final dailyCommission = commissionFor(dailyOrders);
    final dailyRestaurant = restaurantFor(dailyOrders);

    final weeklyOrders = nonRejectedOrders.where((order) {
      final day = _startOfDay(order.createdAt);
      return !day.isBefore(weekStart) && !day.isAfter(todayStart);
    }).toList();
    final weeklyTotal = totalFor(weeklyOrders);
    final weeklyCommission = commissionFor(weeklyOrders);
    final weeklyRestaurant = restaurantFor(weeklyOrders);

    final latestOrders = orders.take(10).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Ganhos', style: theme.textTheme.titleMedium),
        const SizedBox(height: 8),
        Card(
          elevation: 0,
          color: Colors.grey.shade50,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Por pedido',
                  style: theme.textTheme.titleSmall
                      ?.copyWith(fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 12),
                for (var i = 0; i < latestOrders.length; i++) ...[
                  _buildOrderEntry(context, latestOrders[i]),
                  if (i < latestOrders.length - 1) const Divider(height: 24),
                ],
                if (orders.length > latestOrders.length)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(
                      'A mostrar os últimos ${latestOrders.length} de ${orders.length} pedidos.',
                      style: theme.textTheme.bodySmall
                          ?.copyWith(color: Colors.grey.shade600),
                    ),
                  ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        Card(
          elevation: 0,
          color: Colors.grey.shade50,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Resumo diário (hoje)',
                  style: theme.textTheme.titleSmall
                      ?.copyWith(fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 12),
                _buildSummaryRow(context, 'Pedidos', '$dailyCount',
                    emphasize: true),
                _buildSummaryRow(
                    context, 'Total vendido', _formatCurrency(dailyTotal)),
                _buildSummaryRow(
                  context,
                  'Comissão da plataforma (10%)',
                  _formatCurrency(dailyCommission),
                ),
                _buildSummaryRow(
                  context,
                  'Ganhos do restaurante (90%)',
                  _formatCurrency(dailyRestaurant),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        Card(
          elevation: 0,
          color: Colors.grey.shade50,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Resumo semanal (últimos 7 dias)',
                  style: theme.textTheme.titleSmall
                      ?.copyWith(fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 12),
                _buildSummaryRow(
                    context, 'Total vendido', _formatCurrency(weeklyTotal)),
                _buildSummaryRow(
                  context,
                  'Comissão da plataforma',
                  _formatCurrency(weeklyCommission),
                ),
                _buildSummaryRow(
                  context,
                  'Valor a receber',
                  _formatCurrency(weeklyRestaurant),
                  emphasize: true,
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 8),
        _LedgerRestaurantCard(restaurantId: restaurant.id),
        const SizedBox(height: 8),
        Text(
          'Apenas pedidos parceiros não rejeitados contam para os ganhos.',
          style:
              theme.textTheme.bodySmall?.copyWith(color: Colors.grey.shade600),
        ),
      ],
    );
  }

  Widget _buildOrderEntry(BuildContext context, OrderModel order) {
    final theme = Theme.of(context);
    final isRejected = order.status == OrderStatus.rejected;
    final commission = isRejected ? 0.0 : order.platformCommissionAmount;
    final restaurantShare = isRejected ? 0.0 : order.restaurantEarningsAmount;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Pedido ${order.id}',
          style:
              theme.textTheme.bodyLarge?.copyWith(fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 4),
        Text(
          _formatDateTime(order.createdAt),
          style:
              theme.textTheme.bodySmall?.copyWith(color: Colors.grey.shade600),
        ),
        const SizedBox(height: 8),
        _buildSummaryRow(context, 'Estado', order.status.label),
        if (order.customerName != null && order.customerName!.isNotEmpty)
          _buildSummaryRow(context, 'Cliente', order.customerName!),
        if (order.clientPhone != null && order.clientPhone!.isNotEmpty)
          _buildSummaryRow(context, 'Telefone', order.clientPhone!),
        if (order.dropoffAddress != null || order.destination != null)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 2),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                    child: Text('Entrega', style: theme.textTheme.bodyMedium)),
                Flexible(
                  child: AddressText(
                    rawAddress: order.dropoffAddress,
                    coords: order.destination,
                    style: theme.textTheme.bodyMedium
                        ?.copyWith(fontWeight: FontWeight.w500),
                  ),
                ),
              ],
            ),
          ),
        _buildSummaryRow(context, 'Total do pedido', _formatCurrency(order.total),
            emphasize: true),
        _buildSummaryRow(
          context,
          'Comissão da plataforma (10%)',
          _formatCurrency(commission),
        ),
        _buildSummaryRow(
          context,
          'Ganhos do restaurante (90%)',
          _formatCurrency(restaurantShare),
          emphasize: true,
        ),
        if (isRejected)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              'Pedidos rejeitados não geram pagamento.',
              style:
                  theme.textTheme.bodySmall?.copyWith(color: Colors.redAccent),
            ),
          ),
      ],
    );
  }
}

class _LedgerRestaurantCard extends StatefulWidget {
  const _LedgerRestaurantCard({required this.restaurantId});

  final String restaurantId;

  @override
  State<_LedgerRestaurantCard> createState() => _LedgerRestaurantCardState();
}

class _LedgerRestaurantCardState extends State<_LedgerRestaurantCard> {
  double? _settled;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final rows = await Supabase.instance.client
          .from('ledger_entries')
          .select('amount')
          .eq('user_id', widget.restaurantId)
          .eq('user_type', 'restaurant')
          .eq('type', 'earning');
      final total = (rows as List).fold<double>(
        0,
        (sum, r) => sum + ((r['amount'] as num?)?.toDouble() ?? 0),
      );
      setState(() {
        _settled = total;
        _loading = false;
      });
    } catch (_) {
      setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const LinearProgressIndicator(minHeight: 2);
    if (_settled == null) return const SizedBox.shrink();
    final theme = Theme.of(context);
    return Card(
      elevation: 0,
      color: Colors.green.shade50,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            const Icon(Icons.verified, color: Colors.green, size: 20),
            const SizedBox(width: 12),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Saldo liquidado',
                  style:
                      theme.textTheme.bodySmall?.copyWith(color: Colors.grey),
                ),
                Text(
                  '€${_settled!.toStringAsFixed(2)}',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: Colors.green.shade700,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
