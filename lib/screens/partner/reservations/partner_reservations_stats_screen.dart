import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../config/app_theme.dart';
import '../../../stores/partner_reservas_store.dart';

/// Reservas PRO F4 — analytics partner.
///
/// KPIs essenciais (SevenRooms-inspired):
///   - Total reservas, aprovadas %, rejeitadas %, no-shows %
///   - Walk-ins, cobertos servidos
///   - Conversion rate + no-show rate (com cor semáforo)
/// Bar chart fl_chart para distribuição de status.
class PartnerReservationsStatsScreen extends StatefulWidget {
  const PartnerReservationsStatsScreen({
    super.key,
    required this.restaurantId,
  });

  final String restaurantId;

  @override
  State<PartnerReservationsStatsScreen> createState() =>
      _PartnerReservationsStatsScreenState();
}

class _PartnerReservationsStatsScreenState
    extends State<PartnerReservationsStatsScreen> {
  int _days = 30;
  late Future<Map<String, dynamic>> _future;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  void _refresh() {
    setState(() {
      _future = context.read<PartnerReservasStore>().fetchStats(
            restaurantId: widget.restaurantId,
            days: _days,
          );
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Estatísticas')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                const Text(
                  'Período: ',
                  style: TextStyle(fontWeight: FontWeight.w600),
                ),
                DropdownButton<int>(
                  value: _days,
                  items: const [
                    DropdownMenuItem(value: 7, child: Text('Últimos 7 dias')),
                    DropdownMenuItem(value: 30, child: Text('Últimos 30 dias')),
                    DropdownMenuItem(value: 90, child: Text('Últimos 90 dias')),
                  ],
                  onChanged: (v) {
                    if (v == null) return;
                    setState(() => _days = v);
                    _refresh();
                  },
                ),
              ],
            ),
          ),
          Expanded(
            child: FutureBuilder<Map<String, dynamic>>(
              future: _future,
              builder: (context, snap) {
                if (snap.connectionState != ConnectionState.done) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (snap.hasError) {
                  return Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.error_outline,
                              size: 48, color: Colors.red),
                          const SizedBox(height: 12),
                          Text(
                            snap.error
                                .toString()
                                .replaceFirst('Exception: ', ''),
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: 12),
                          ElevatedButton(
                            onPressed: _refresh,
                            child: const Text('Tentar de novo'),
                          ),
                        ],
                      ),
                    ),
                  );
                }
                final data = snap.data ?? {};
                return RefreshIndicator(
                  onRefresh: () async => _refresh(),
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                    children: _buildContent(data),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  List<Widget> _buildContent(Map<String, dynamic> data) {
    final total = (data['total'] as int?) ?? 0;
    final approved = (data['approved'] as int?) ?? 0;
    final rejected = (data['rejected'] as int?) ?? 0;
    final noShows = (data['no_shows'] as int?) ?? 0;
    final seated = (data['seated'] as int?) ?? 0;
    final walkIns = (data['walk_ins'] as int?) ?? 0;
    final totalCovers = (data['total_covers'] as int?) ?? 0;

    final approvalRate = total > 0 ? (approved / total * 100) : 0.0;
    final noShowRate = total > 0 ? (noShows / total * 100) : 0.0;

    Color noShowColor;
    if (noShowRate < 5) {
      noShowColor = AppTheme.primary;
    } else if (noShowRate < 10) {
      noShowColor = AppTheme.secondary;
    } else {
      noShowColor = Colors.red;
    }

    return [
      GridView.count(
        crossAxisCount: 2,
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        mainAxisSpacing: 12,
        crossAxisSpacing: 12,
        childAspectRatio: 1.6,
        children: [
          _kpiCard('Total reservas', '$total', Icons.event_note,
              AppTheme.primary),
          _kpiCard('Cobertos servidos', '$totalCovers',
              Icons.restaurant, AppTheme.primary),
          _kpiCard('Aprovação',
              '${approvalRate.toStringAsFixed(0)}%', Icons.check_circle,
              AppTheme.primary),
          _kpiCard('No-shows',
              '${noShowRate.toStringAsFixed(1)}%',
              Icons.person_off, noShowColor),
          _kpiCard('Walk-ins', '$walkIns', Icons.directions_walk,
              AppTheme.secondary),
          _kpiCard('Sentados', '$seated', Icons.event_seat,
              AppTheme.primary),
        ],
      ),
      const SizedBox(height: 24),
      const Text(
        'Distribuição',
        style: TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.w800,
          color: AppTheme.textPrimary,
        ),
      ),
      const SizedBox(height: 12),
      if (total == 0)
        const Padding(
          padding: EdgeInsets.symmetric(vertical: 32),
          child: Center(
            child: Text(
              'Sem dados no período seleccionado.',
              style: TextStyle(color: AppTheme.textSecondary),
            ),
          ),
        )
      else
        SizedBox(
          height: 220,
          child: BarChart(
            _buildBarChart(approved, rejected, noShows, walkIns),
          ),
        ),
      const SizedBox(height: 16),
      _legend(),
    ];
  }

  Widget _kpiCard(String label, String value, IconData icon, Color color) {
    return Card(
      elevation: 1,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, size: 20, color: color),
            const SizedBox(height: 6),
            Text(
              value,
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w800,
                color: color,
              ),
            ),
            Text(
              label,
              style: const TextStyle(
                fontSize: 12,
                color: AppTheme.textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }

  BarChartData _buildBarChart(
      int approved, int rejected, int noShows, int walkIns) {
    final values = <int>[approved, rejected, noShows, walkIns];
    final labels = <String>['Aprov', 'Rejeit', 'No-show', 'Walk-in'];
    final colors = <Color>[
      AppTheme.primary,
      Colors.red,
      Colors.orange,
      AppTheme.secondary,
    ];
    final maxY = (values.fold<int>(0, (a, b) => a > b ? a : b)).toDouble();
    return BarChartData(
      maxY: maxY == 0 ? 1 : maxY * 1.2,
      gridData: const FlGridData(show: false),
      borderData: FlBorderData(show: false),
      titlesData: FlTitlesData(
        leftTitles: const AxisTitles(
          sideTitles: SideTitles(showTitles: true, reservedSize: 28),
        ),
        topTitles: const AxisTitles(
          sideTitles: SideTitles(showTitles: false),
        ),
        rightTitles: const AxisTitles(
          sideTitles: SideTitles(showTitles: false),
        ),
        bottomTitles: AxisTitles(
          sideTitles: SideTitles(
            showTitles: true,
            reservedSize: 28,
            getTitlesWidget: (value, meta) {
              final i = value.toInt();
              if (i < 0 || i >= labels.length) return const SizedBox.shrink();
              return Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  labels[i],
                  style: const TextStyle(fontSize: 11),
                ),
              );
            },
          ),
        ),
      ),
      barGroups: [
        for (var i = 0; i < values.length; i++)
          BarChartGroupData(
            x: i,
            barRods: [
              BarChartRodData(
                toY: values[i].toDouble(),
                color: colors[i],
                width: 24,
                borderRadius: BorderRadius.circular(4),
              ),
            ],
          ),
      ],
    );
  }

  Widget _legend() {
    return const Wrap(
      spacing: 12,
      runSpacing: 8,
      children: [
        _LegendDot(color: AppTheme.primary, label: 'Aprovadas'),
        _LegendDot(color: Colors.red, label: 'Rejeitadas'),
        _LegendDot(color: Colors.orange, label: 'No-shows'),
        _LegendDot(color: AppTheme.secondary, label: 'Walk-ins'),
      ],
    );
  }
}

class _LegendDot extends StatelessWidget {
  const _LegendDot({required this.color, required this.label});
  final Color color;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(
            color: color,
            shape: BoxShape.circle,
          ),
        ),
        const SizedBox(width: 6),
        Text(label, style: const TextStyle(fontSize: 12)),
      ],
    );
  }
}
