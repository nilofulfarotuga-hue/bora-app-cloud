import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../config/app_colors.dart';
import '../../config/app_spacing.dart';
import '../../widgets/bora/bora_screen_app_bar.dart';

/// Admin — Métricas de marcações (vertical Serviços / Barbearias).
///
/// KPIs via RPC `admin_appointments_metrics(p_provider_id, p_from, p_to)`
/// que devolve {total, confirmed, completed, no_show, cancelled, walk_ins,
/// no_show_rate_pct, bora_revenue_cents, service_revenue_app_cents}.
/// Dropdown de período (hoje / 7 / 30 / 90 dias). Estilo de
/// `admin_reservations_metrics_screen.dart`. PT-BR.
class AdminAppointmentsMetricsScreen extends StatefulWidget {
  const AdminAppointmentsMetricsScreen({super.key});

  @override
  State<AdminAppointmentsMetricsScreen> createState() =>
      _AdminAppointmentsMetricsScreenState();
}

class _AdminAppointmentsMetricsScreenState
    extends State<AdminAppointmentsMetricsScreen> {
  late Future<Map<String, dynamic>> _future;
  int _days = 30; // 0 = hoje; senão últimos N dias

  static const _periods = <(int, String)>[
    (0, 'Hoje'),
    (7, 'Últimos 7 dias'),
    (30, 'Últimos 30 dias'),
    (90, 'Últimos 90 dias'),
  ];

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<Map<String, dynamic>> _load() async {
    final now = DateTime.now();
    final DateTime from;
    if (_days == 0) {
      from = DateTime(now.year, now.month, now.day); // início de hoje
    } else {
      from = now.subtract(Duration(days: _days));
    }
    final res = await Supabase.instance.client.rpc(
      'admin_appointments_metrics',
      params: {
        'p_provider_id': null,
        'p_from': from.toUtc().toIso8601String(),
        'p_to': now.toUtc().toIso8601String(),
      },
    );
    return Map<String, dynamic>.from(res as Map);
  }

  String _euros(int cents) => '€${(cents / 100.0).toStringAsFixed(2)}';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: BoraScreenAppBar(
        title: 'Métricas Barbearias',
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () => setState(() => _future = _load()),
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(
                Spacing.md, Spacing.sm, Spacing.md, Spacing.xs),
            child: Row(
              children: [
                const Text('Período:'),
                const SizedBox(width: Spacing.sm),
                DropdownButton<int>(
                  value: _days,
                  items: _periods
                      .map((p) => DropdownMenuItem<int>(
                            value: p.$1,
                            child: Text(p.$2),
                          ))
                      .toList(),
                  onChanged: (v) {
                    if (v == null) return;
                    setState(() {
                      _days = v;
                      _future = _load();
                    });
                  },
                ),
              ],
            ),
          ),
          Expanded(
            child: RefreshIndicator(
              onRefresh: () async {
                setState(() => _future = _load());
                await _future;
              },
              child: FutureBuilder<Map<String, dynamic>>(
                future: _future,
                builder: (_, snap) => _buildStatsView(snap),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatsView(AsyncSnapshot<Map<String, dynamic>> snap) {
    if (snap.connectionState != ConnectionState.done) {
      return const Center(child: CircularProgressIndicator());
    }
    if (snap.hasError) {
      return ListView(
        children: [
          Padding(
            padding: const EdgeInsets.all(Spacing.xxl),
            child: Text(
              'Erro: ${snap.error}',
              style: const TextStyle(color: AppColors.error),
              textAlign: TextAlign.center,
            ),
          ),
        ],
      );
    }
    final data = snap.data ?? const <String, dynamic>{};
    int asInt(String key) => ((data[key] as num?) ?? 0).toInt();

    final total = asInt('total');
    final confirmed = asInt('confirmed');
    final completed = asInt('completed');
    final noShow = asInt('no_show');
    final cancelled = asInt('cancelled');
    final walkIns = asInt('walk_ins');
    final noShowPct = ((data['no_show_rate_pct'] as num?) ?? 0).toDouble();
    final boraRevenue = asInt('bora_revenue_cents');
    final serviceRevenue = asInt('service_revenue_app_cents');

    Color noShowColor;
    if (noShowPct < 5) {
      noShowColor = AppColors.success;
    } else if (noShowPct < 10) {
      noShowColor = AppColors.warning;
    } else {
      noShowColor = AppColors.error;
    }

    return ListView(
      padding: const EdgeInsets.all(Spacing.lg),
      children: [
        GridView.count(
          crossAxisCount: 2,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          crossAxisSpacing: Spacing.md,
          mainAxisSpacing: Spacing.md,
          childAspectRatio: 1.6,
          children: [
            _kpi('Total', '$total', AppColors.info),
            _kpi('Confirmadas', '$confirmed', AppColors.success),
            _kpi('Concluídas', '$completed', AppColors.primary),
            _kpi('No-shows', '$noShow (${noShowPct.toStringAsFixed(1)}%)',
                noShowColor),
            _kpi('Canceladas', '$cancelled', AppColors.warning),
            _kpi('Walk-ins', '$walkIns', Colors.purple),
            _kpi('Receita Bora', _euros(boraRevenue), AppColors.primary),
            _kpi('Serviços (app)', _euros(serviceRevenue), Colors.teal),
          ],
        ),
        const SizedBox(height: Spacing.xxl),
        if (total > 0) ...[
          const Text(
            'Distribuição por estado',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: Spacing.md),
          SizedBox(
            height: 220,
            child: BarChart(
              BarChartData(
                alignment: BarChartAlignment.spaceAround,
                barGroups: [
                  _bar(0, confirmed, AppColors.success),
                  _bar(1, completed, AppColors.primary),
                  _bar(2, noShow, AppColors.error),
                  _bar(3, cancelled, AppColors.warning),
                  _bar(4, walkIns, Colors.purple),
                ],
                titlesData: FlTitlesData(
                  show: true,
                  bottomTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 30,
                      getTitlesWidget: (v, _) {
                        const labels = [
                          'Conf.',
                          'Concl.',
                          'No-show',
                          'Cancel.',
                          'Walk'
                        ];
                        final i = v.toInt();
                        return Padding(
                          padding: const EdgeInsets.only(top: Spacing.xs),
                          child: Text(
                            i >= 0 && i < labels.length ? labels[i] : '',
                            style: const TextStyle(fontSize: 11),
                          ),
                        );
                      },
                    ),
                  ),
                  leftTitles: const AxisTitles(
                    sideTitles: SideTitles(showTitles: true, reservedSize: 30),
                  ),
                  rightTitles: const AxisTitles(
                    sideTitles: SideTitles(showTitles: false),
                  ),
                  topTitles: const AxisTitles(
                    sideTitles: SideTitles(showTitles: false),
                  ),
                ),
                gridData: const FlGridData(show: true),
                borderData: FlBorderData(show: false),
              ),
            ),
          ),
        ] else
          const Padding(
            padding: EdgeInsets.symmetric(vertical: Spacing.xxxl),
            child: Center(
              child: Text(
                'Sem dados no período seleccionado.',
                style: TextStyle(color: AppColors.textSecondary),
              ),
            ),
          ),
      ],
    );
  }

  BarChartGroupData _bar(int x, int v, Color c) => BarChartGroupData(
        x: x,
        barRods: [
          BarChartRodData(toY: v.toDouble(), color: c, width: 24),
        ],
      );

  Widget _kpi(String label, String value, Color color) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(Radii.lg),
        boxShadow: AppColors.shadowCard,
      ),
      child: Padding(
        padding: const EdgeInsets.all(Spacing.md),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: const TextStyle(
                  fontSize: 13, color: AppColors.textSecondary),
            ),
            const SizedBox(height: Spacing.xs),
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(
                value,
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                  color: color,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
