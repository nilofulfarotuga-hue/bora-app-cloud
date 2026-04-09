import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Temporary in-app admin dashboard.
///
/// Reads aggregated metrics from `admin_dashboard_metrics()` (server-side
/// SECURITY DEFINER RPC). The function only ever returns aggregates — never
/// row-level data — so even if this screen is reached by a non-admin the
/// blast radius is limited to four totals.
///
/// Access gating is intentionally temporary: an email allowlist below.
/// Replace with a real admin role + JWT claim before production.
class AdminDashboardScreen extends StatefulWidget {
  const AdminDashboardScreen({super.key});

  /// Temporary admin allowlist. Add the operator email(s) here.
  /// When empty, the gate is permissive (dev mode).
  static const Set<String> adminEmails = <String>{
    // 'you@boraapp.com',
  };

  @override
  State<AdminDashboardScreen> createState() => _AdminDashboardScreenState();
}

class _AdminDashboardScreenState extends State<AdminDashboardScreen> {
  late Future<Map<String, dynamic>> _metricsFuture;

  @override
  void initState() {
    super.initState();
    _metricsFuture = _loadMetrics();
  }

  Future<Map<String, dynamic>> _loadMetrics() async {
    final response = await Supabase.instance.client.rpc('admin_dashboard_metrics');
    if (response is Map<String, dynamic>) return response;
    if (response is Map) return Map<String, dynamic>.from(response);
    throw StateError('Unexpected RPC response type: ${response.runtimeType}');
  }

  Future<void> _refresh() async {
    setState(() {
      _metricsFuture = _loadMetrics();
    });
    await _metricsFuture;
  }

  bool get _isAuthorized {
    final allow = AdminDashboardScreen.adminEmails;
    if (allow.isEmpty) return true; // dev mode — open
    final email = Supabase.instance.client.auth.currentUser?.email;
    return email != null && allow.contains(email);
  }

  @override
  Widget build(BuildContext context) {
    if (!_isAuthorized) {
      return Scaffold(
        appBar: AppBar(title: const Text('Painel Admin')),
        body: const Center(
          child: Padding(
            padding: EdgeInsets.all(24),
            child: Text(
              'Acesso negado.\nO seu email não está na lista de admins.',
              textAlign: TextAlign.center,
            ),
          ),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Painel Admin'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _refresh,
            tooltip: 'Atualizar',
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _refresh,
        child: FutureBuilder<Map<String, dynamic>>(
          future: _metricsFuture,
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }
            if (snapshot.hasError) {
              return ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  const SizedBox(height: 80),
                  const Icon(Icons.error_outline, size: 48, color: Colors.red),
                  const SizedBox(height: 12),
                  Text(
                    'Erro ao carregar métricas:\n${snapshot.error}',
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 16),
                  Center(
                    child: ElevatedButton.icon(
                      onPressed: _refresh,
                      icon: const Icon(Icons.refresh),
                      label: const Text('Tentar de novo'),
                    ),
                  ),
                ],
              );
            }

            final m = snapshot.data ?? const <String, dynamic>{};
            final platformRevenue = _toDouble(m['platform_revenue']);
            final ordersToday = _toInt(m['orders_today']);
            final driversPayable = _toDouble(m['drivers_payable']);
            final restaurantsPayable = _toDouble(m['restaurants_payable']);
            final generatedAt = m['generated_at']?.toString() ?? '—';
            final dailyOrders = _parseDailyOrders(m['daily_orders']);

            return ListView(
              padding: const EdgeInsets.all(16),
              children: [
                _buildChart(dailyOrders),
                _MetricCard(
                  icon: Icons.account_balance_wallet,
                  iconColor: Colors.green,
                  title: 'Faturamento total (plataforma)',
                  value: '€${platformRevenue.toStringAsFixed(2)}',
                ),
                _MetricCard(
                  icon: Icons.receipt_long,
                  iconColor: Colors.blue,
                  title: 'Pedidos hoje',
                  value: ordersToday.toString(),
                ),
                _MetricCard(
                  icon: Icons.local_shipping,
                  iconColor: Colors.orange,
                  title: 'A pagar — drivers',
                  value: '€${driversPayable.toStringAsFixed(2)}',
                ),
                _MetricCard(
                  icon: Icons.restaurant,
                  iconColor: Colors.purple,
                  title: 'A pagar — restaurantes',
                  value: '€${restaurantsPayable.toStringAsFixed(2)}',
                ),
                const SizedBox(height: 12),
                Center(
                  child: Text(
                    'Atualizado: $generatedAt',
                    style: Theme.of(context)
                        .textTheme
                        .bodySmall
                        ?.copyWith(color: Colors.grey),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  static List<_DayCount> _parseDailyOrders(dynamic raw) {
    if (raw is! List) return const [];
    final result = <_DayCount>[];
    for (final item in raw) {
      if (item is! Map) continue;
      final date = item['date']?.toString() ?? '';
      final count = _toInt(item['count']);
      if (date.isNotEmpty) result.add(_DayCount(date, count));
    }
    result.sort((a, b) => a.date.compareTo(b.date));
    return result;
  }

  Widget _buildChart(List<_DayCount> data) {
    if (data.isEmpty) return const SizedBox();
    final maxY = data.map((d) => d.count).reduce((a, b) => a > b ? a : b).toDouble();
    final spots = List.generate(
      data.length,
      (i) => FlSpot(i.toDouble(), data[i].count.toDouble()),
    );
    return Card(
      elevation: 2,
      margin: const EdgeInsets.only(bottom: 16),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 8, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Pedidos por dia',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
            ),
            const SizedBox(height: 12),
            SizedBox(
              height: 130,
              child: LineChart(
                LineChartData(
                  minY: 0,
                  maxY: maxY == 0 ? 1 : maxY * 1.2,
                  gridData: const FlGridData(show: false),
                  borderData: FlBorderData(show: false),
                  lineTouchData: LineTouchData(
                    touchTooltipData: LineTouchTooltipData(
                      getTooltipItems: (spots) => spots
                          .map((s) => LineTooltipItem(
                                '${s.y.toInt()} pedidos',
                                const TextStyle(color: Colors.white, fontSize: 11),
                              ))
                          .toList(),
                    ),
                  ),
                  titlesData: FlTitlesData(
                    leftTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                    rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                    topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                    bottomTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        reservedSize: 22,
                        getTitlesWidget: (value, meta) {
                          final i = value.toInt();
                          if (i < 0 || i >= data.length) return const SizedBox();
                          final d = data[i].date;
                          // Format: dd/MM from yyyy-MM-dd
                          String label;
                          if (d.length >= 10) {
                            label = '${d.substring(8, 10)}/${d.substring(5, 7)}';
                          } else {
                            label = d;
                          }
                          return Text(label, style: const TextStyle(fontSize: 9, color: Colors.grey));
                        },
                      ),
                    ),
                  ),
                  lineBarsData: [
                    LineChartBarData(
                      spots: spots,
                      isCurved: true,
                      curveSmoothness: 0.4,
                      preventCurveOverShooting: true,
                      color: const Color(0xFF2196F3),
                      barWidth: 2.5,
                      dotData: const FlDotData(show: true),
                      belowBarData: BarAreaData(
                        show: true,
                        color: const Color(0xFF2196F3).withValues(alpha: 0.12),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  static double _toDouble(dynamic v) {
    if (v == null) return 0;
    if (v is num) return v.toDouble();
    return double.tryParse(v.toString()) ?? 0;
  }

  static int _toInt(dynamic v) {
    if (v == null) return 0;
    if (v is int) return v;
    if (v is num) return v.toInt();
    return int.tryParse(v.toString()) ?? 0;
  }
}

class _MetricCard extends StatelessWidget {
  const _MetricCard({
    required this.icon,
    required this.iconColor,
    required this.title,
    required this.value,
  });

  final IconData icon;
  final Color iconColor;
  final String title;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 2,
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            CircleAvatar(
              radius: 24,
              backgroundColor: iconColor.withValues(alpha: 0.15),
              child: Icon(icon, color: iconColor, size: 28),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: Colors.grey.shade700,
                        ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    value,
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
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

class _DayCount {
  const _DayCount(this.date, this.count);
  final String date;
  final int count;
}
