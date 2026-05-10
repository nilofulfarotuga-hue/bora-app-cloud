import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../config/app_colors.dart';
import '../config/app_spacing.dart';
import '../models/order_model.dart';
import '../models/restaurant_model.dart';
import '../stores/order_store.dart';
import '../widgets/bora_support_fab.dart';

enum _Period { today, week, month }

class PartnerEarningsScreen extends StatefulWidget {
  const PartnerEarningsScreen({super.key, required this.restaurant});

  final RestaurantModel restaurant;

  @override
  State<PartnerEarningsScreen> createState() => _PartnerEarningsScreenState();
}

class _PartnerEarningsScreenState extends State<PartnerEarningsScreen> {
  _Period _period = _Period.week;

  // Reservas — créditos €2 do `restaurant_menu_credits`.
  int _reservationUsedCount = 0;
  int _reservationUsedCents = 0;
  int _reservationPendingCount = 0;
  int _reservationPendingCents = 0;
  bool _reservationsLoading = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _loadReservationCredits();
    });
  }

  void _onPeriodChanged(_Period p) {
    setState(() => _period = p);
    _loadReservationCredits();
  }

  Future<void> _loadReservationCredits() async {
    if (!mounted) return;
    setState(() => _reservationsLoading = true);
    try {
      final start = _startOfPeriod(DateTime.now());
      final supabase = Supabase.instance.client;

      final usedRows = await supabase
          .from('restaurant_menu_credits')
          .select('amount_cents')
          .eq('restaurant_id', widget.restaurant.id)
          .gte('used_at', start.toIso8601String());

      final pendingRows = await supabase
          .from('restaurant_menu_credits')
          .select('amount_cents')
          .eq('restaurant_id', widget.restaurant.id)
          .filter('used_at', 'is', null);

      if (!mounted) return;
      final used = (usedRows as List).cast<Map<String, dynamic>>();
      final pending = (pendingRows as List).cast<Map<String, dynamic>>();
      setState(() {
        _reservationUsedCount = used.length;
        _reservationUsedCents = used.fold<int>(
            0, (s, r) => s + ((r['amount_cents'] as num?)?.toInt() ?? 0));
        _reservationPendingCount = pending.length;
        _reservationPendingCents = pending.fold<int>(
            0, (s, r) => s + ((r['amount_cents'] as num?)?.toInt() ?? 0));
        _reservationsLoading = false;
      });
    } catch (e) {
      debugPrint('[PartnerEarnings] _loadReservationCredits error: $e');
      if (mounted) setState(() => _reservationsLoading = false);
    }
  }

  double _partnerRevenue(OrderModel order) {
    final commission = order.platformCommissionAmount;
    final itemsValue = order.subtotal > 0
        ? order.subtotal
        : (order.total - order.deliveryFee - order.serviceFee);
    final revenue = itemsValue - commission;
    return revenue > 0 ? revenue : 0;
  }

  DateTime _startOfPeriod(DateTime now) {
    switch (_period) {
      case _Period.today:
        return DateTime(now.year, now.month, now.day);
      case _Period.week:
        return DateTime(now.year, now.month, now.day)
            .subtract(const Duration(days: 6));
      case _Period.month:
        return DateTime(now.year, now.month, now.day)
            .subtract(const Duration(days: 29));
    }
  }

  int _bucketCount() {
    switch (_period) {
      case _Period.today:
        return 1;
      case _Period.week:
        return 7;
      case _Period.month:
        return 30;
    }
  }

  @override
  Widget build(BuildContext context) {
    final orderStore = context.watch<OrderStore>();
    final now = DateTime.now();
    final start = _startOfPeriod(now);

    final allOrders = orderStore
        .partnerOrdersForRestaurant(widget.restaurant.name)
        .where((o) => o.status == OrderStatus.delivered)
        .toList();

    final periodOrders = allOrders
        .where((o) => !o.createdAt.isBefore(start))
        .toList()
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));

    final totalEarnings = periodOrders.fold<double>(
      0,
      (sum, o) => sum + _partnerRevenue(o),
    );
    final totalCommission = periodOrders.fold<double>(
      0,
      (sum, o) => sum + o.platformCommissionAmount,
    );
    final avgTicket =
        periodOrders.isEmpty ? 0.0 : totalEarnings / periodOrders.length;

    return Scaffold(
      backgroundColor: AppColors.surface,
      floatingActionButton: const BoraSupportFab(),
      appBar: AppBar(
        title: const Text(
          'Ganhos',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        backgroundColor: Colors.transparent,
        foregroundColor: Colors.white,
        elevation: 0,
        flexibleSpace: const DecoratedBox(
          decoration: BoxDecoration(gradient: AppColors.headerGradient),
        ),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(Spacing.lg),
          children: [
            _PeriodSelector(
              value: _period,
              onChanged: _onPeriodChanged,
            ),
            const SizedBox(height: Spacing.lg),
            _HeroCard(
              amount: totalEarnings + _reservationUsedCents / 100.0,
              periodLabel: _periodLabel(_period),
            ),
            const SizedBox(height: Spacing.lg),
            _KpiRow(
              ordersCount: periodOrders.length,
              avgTicket: avgTicket,
              commission: totalCommission,
            ),
            const SizedBox(height: Spacing.lg),
            _ReservationsSection(
              loading: _reservationsLoading,
              usedCount: _reservationUsedCount,
              usedCents: _reservationUsedCents,
              pendingCount: _reservationPendingCount,
              pendingCents: _reservationPendingCents,
              periodLabel: _periodLabel(_period),
            ),
            const SizedBox(height: Spacing.xl),
            if (_period != _Period.today) ...[
              _EarningsChart(
                orders: periodOrders,
                buckets: _bucketCount(),
                startDate: start,
                revenue: _partnerRevenue,
              ),
              const SizedBox(height: Spacing.xl),
            ],
            Row(
              children: [
                const Icon(Icons.receipt_long_outlined,
                    size: 20, color: AppColors.textPrimary),
                const SizedBox(width: 8),
                Text(
                  'Pedidos entregues (${periodOrders.length})',
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textPrimary,
                  ),
                ),
              ],
            ),
            const SizedBox(height: Spacing.sm),
            if (periodOrders.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 32),
                child: Center(
                  child: Text(
                    'Ainda não há pedidos entregues neste período.',
                    style: TextStyle(color: AppColors.textSecondary),
                  ),
                ),
              )
            else
              ...periodOrders.map(
                (o) => _OrderTile(
                  order: o,
                  revenue: _partnerRevenue(o),
                ),
              ),
          ],
        ),
      ),
    );
  }

  String _periodLabel(_Period p) {
    switch (p) {
      case _Period.today:
        return 'Hoje';
      case _Period.week:
        return 'Últimos 7 dias';
      case _Period.month:
        return 'Últimos 30 dias';
    }
  }
}

class _PeriodSelector extends StatelessWidget {
  const _PeriodSelector({required this.value, required this.onChanged});

  final _Period value;
  final ValueChanged<_Period> onChanged;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        _chip(context, 'Hoje', _Period.today),
        const SizedBox(width: 8),
        _chip(context, 'Semana', _Period.week),
        const SizedBox(width: 8),
        _chip(context, 'Mês', _Period.month),
      ],
    );
  }

  Widget _chip(BuildContext context, String label, _Period p) {
    final selected = p == value;
    return Expanded(
      child: GestureDetector(
        onTap: () => onChanged(p),
        child: Container(
          height: 42,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: selected ? AppColors.primary : Colors.white,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: selected ? AppColors.primary : Colors.grey.shade300,
            ),
          ),
          child: Text(
            label,
            style: TextStyle(
              color: selected ? Colors.white : AppColors.textPrimary,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ),
    );
  }
}

class _HeroCard extends StatelessWidget {
  const _HeroCard({required this.amount, required this.periodLabel});

  final double amount;
  final String periodLabel;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(Spacing.xl),
      decoration: BoxDecoration(
        gradient: AppColors.headerGradient,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            periodLabel.toUpperCase(),
            style: const TextStyle(
              color: Colors.white70,
              fontSize: 12,
              fontWeight: FontWeight.w600,
              letterSpacing: 1.2,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            '€${amount.toStringAsFixed(2)}',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 42,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 4),
          const Text(
            'Ganho líquido (já descontada a comissão da plataforma)',
            style: TextStyle(color: Colors.white70, fontSize: 12),
          ),
        ],
      ),
    );
  }
}

class _KpiRow extends StatelessWidget {
  const _KpiRow({
    required this.ordersCount,
    required this.avgTicket,
    required this.commission,
  });

  final int ordersCount;
  final double avgTicket;
  final double commission;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: _kpi(
            icon: Icons.shopping_bag_outlined,
            label: 'Pedidos',
            value: '$ordersCount',
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _kpi(
            icon: Icons.trending_up,
            label: 'Ticket médio',
            value: '€${avgTicket.toStringAsFixed(2)}',
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _kpi(
            icon: Icons.percent,
            label: 'Comissão',
            value: '€${commission.toStringAsFixed(2)}',
          ),
        ),
      ],
    );
  }

  Widget _kpi(
      {required IconData icon, required String label, required String value}) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Column(
        children: [
          Icon(icon, size: 22, color: AppColors.primary),
          const SizedBox(height: 6),
          Text(
            value,
            style: const TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w800,
              color: AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: const TextStyle(
              fontSize: 11,
              color: AppColors.textSecondary,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}

class _EarningsChart extends StatelessWidget {
  const _EarningsChart({
    required this.orders,
    required this.buckets,
    required this.startDate,
    required this.revenue,
  });

  final List<OrderModel> orders;
  final int buckets;
  final DateTime startDate;
  final double Function(OrderModel) revenue;

  @override
  Widget build(BuildContext context) {
    final daily = List<double>.filled(buckets, 0);
    for (final o in orders) {
      final day = DateTime(o.createdAt.year, o.createdAt.month, o.createdAt.day);
      final idx = day.difference(startDate).inDays;
      if (idx >= 0 && idx < buckets) {
        daily[idx] += revenue(o);
      }
    }
    final maxVal = daily.fold<double>(0, (m, v) => v > m ? v : m);
    final chartMax = maxVal <= 0 ? 10.0 : maxVal * 1.2;

    return Container(
      height: 200,
      padding: const EdgeInsets.fromLTRB(12, 16, 12, 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: BarChart(
        BarChartData(
          maxY: chartMax,
          alignment: BarChartAlignment.spaceAround,
          gridData: const FlGridData(show: false),
          borderData: FlBorderData(show: false),
          titlesData: FlTitlesData(
            leftTitles: const AxisTitles(
                sideTitles: SideTitles(showTitles: false)),
            rightTitles: const AxisTitles(
                sideTitles: SideTitles(showTitles: false)),
            topTitles: const AxisTitles(
                sideTitles: SideTitles(showTitles: false)),
            bottomTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 22,
                interval: 1,
                getTitlesWidget: (value, meta) {
                  final i = value.toInt();
                  if (i < 0 || i >= buckets) return const SizedBox.shrink();
                  if (buckets == 7 || i % 5 == 0 || i == buckets - 1) {
                    final d = startDate.add(Duration(days: i));
                    return Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text(
                        '${d.day}/${d.month}',
                        style: const TextStyle(
                          fontSize: 10,
                          color: AppColors.textSecondary,
                        ),
                      ),
                    );
                  }
                  return const SizedBox.shrink();
                },
              ),
            ),
          ),
          barGroups: [
            for (var i = 0; i < buckets; i++)
              BarChartGroupData(
                x: i,
                barRods: [
                  BarChartRodData(
                    toY: daily[i],
                    color: AppColors.primary,
                    width: buckets == 7 ? 18 : 6,
                    borderRadius: const BorderRadius.vertical(
                        top: Radius.circular(4)),
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }
}

class _OrderTile extends StatelessWidget {
  const _OrderTile({required this.order, required this.revenue});

  final OrderModel order;
  final double revenue;

  @override
  Widget build(BuildContext context) {
    final when = order.createdAt;
    final hh = when.hour.toString().padLeft(2, '0');
    final mm = when.minute.toString().padLeft(2, '0');
    final customer = (order.customerName?.trim().isNotEmpty ?? false)
        ? order.customerName!
        : 'Cliente';
    final itemsCount = order.items.length;

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: AppColors.primary.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(Icons.receipt, color: AppColors.primary),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  customer,
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 14,
                    color: AppColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '${when.day}/${when.month} · $hh:$mm · $itemsCount ${itemsCount == 1 ? "item" : "itens"}',
                  style: const TextStyle(
                    fontSize: 12,
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                '+€${revenue.toStringAsFixed(2)}',
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w800,
                  color: AppColors.primary,
                ),
              ),
              Text(
                'Total €${order.total.toStringAsFixed(2)}',
                style: const TextStyle(
                  fontSize: 11,
                  color: AppColors.textSecondary,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ReservationsSection extends StatelessWidget {
  const _ReservationsSection({
    required this.loading,
    required this.usedCount,
    required this.usedCents,
    required this.pendingCount,
    required this.pendingCents,
    required this.periodLabel,
  });

  final bool loading;
  final int usedCount;
  final int usedCents;
  final int pendingCount;
  final int pendingCents;
  final String periodLabel;

  String _euros(int cents) => '€${(cents / 100.0).toStringAsFixed(2)}';

  String _label(int n, String singular, String plural) =>
      n == 1 ? '1 $singular' : '$n $plural';

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 0,
      color: AppColors.card,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(Spacing.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.event_seat,
                    size: 20, color: AppColors.primary),
                const SizedBox(width: 8),
                const Text(
                  'Reservas',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textPrimary,
                  ),
                ),
                const Spacer(),
                if (loading)
                  const SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            _Row(
              label:
                  'Créditos usados ($periodLabel)',
              detail: _label(usedCount, 'reserva', 'reservas'),
              amount: _euros(usedCents),
              amountColor: AppColors.primary,
              hint: 'A receber no acerto semanal',
            ),
            const SizedBox(height: 10),
            _Row(
              label: 'Créditos pendentes',
              detail: _label(pendingCount, 'reserva', 'reservas'),
              amount: _euros(pendingCents),
              amountColor: AppColors.textSecondary,
              hint: 'Cliente ainda não usou no restaurante',
            ),
          ],
        ),
      ),
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({
    required this.label,
    required this.detail,
    required this.amount,
    required this.amountColor,
    required this.hint,
  });

  final String label;
  final String detail;
  final String amount;
  final Color amountColor;
  final String hint;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                label,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textPrimary,
                ),
              ),
            ),
            Text(
              amount,
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w800,
                color: amountColor,
              ),
            ),
          ],
        ),
        const SizedBox(height: 2),
        Text(
          '$detail · $hint',
          style: const TextStyle(
            fontSize: 11,
            color: AppColors.textSecondary,
          ),
        ),
      ],
    );
  }
}
