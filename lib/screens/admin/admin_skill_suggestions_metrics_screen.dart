// Sessão 5G B6 — Métricas detalhadas das propostas IA.
// 4 gráficos: por tipo, por zona, top categorias, por mês.
// Cores Bora: verde #1B5E20, laranja #E65100, cinza #757575, vermelho #C62828.

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../config/app_colors.dart';

class AdminSkillSuggestionsMetricsScreen extends StatefulWidget {
  const AdminSkillSuggestionsMetricsScreen({super.key});

  @override
  State<AdminSkillSuggestionsMetricsScreen> createState() =>
      _AdminSkillSuggestionsMetricsScreenState();
}

class _AdminSkillSuggestionsMetricsScreenState
    extends State<AdminSkillSuggestionsMetricsScreen> {
  static const _boraGreen = AppColors.primary;
  static const _boraOrange = AppColors.accent;
  static const _grey = Color(0xFF757575);
  static const _critical = Color(0xFFC62828);

  Map<String, dynamic>? _metrics;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final result = await Supabase.instance.client
          .rpc('admin_skill_suggestions_metrics');
      if (!mounted) return;
      setState(() {
        _metrics =
            result is Map ? Map<String, dynamic>.from(result) : <String, dynamic>{};
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: _boraGreen,
        foregroundColor: Colors.white,
        title: const Text('Métricas detalhadas'),
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.error_outline, color: Colors.red, size: 48),
              const SizedBox(height: 12),
              const Text('Erro ao carregar métricas.',
                  style: TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              Text(_error!,
                  style:
                      const TextStyle(fontSize: 12, color: Colors.black54),
                  textAlign: TextAlign.center),
              const SizedBox(height: 16),
              TextButton.icon(
                icon: const Icon(Icons.refresh),
                label: const Text('Tentar de novo'),
                onPressed: _load,
              ),
            ],
          ),
        ),
      );
    }
    final m = _metrics ?? const {};
    final avgHours = (m['avg_review_hours'] as num?)?.toDouble() ?? 0.0;
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _summaryCard(avgHours),
          const SizedBox(height: 16),
          _byTypeCard(m['by_type']),
          const SizedBox(height: 16),
          _byZoneCard(m['by_zone']),
          const SizedBox(height: 16),
          _topCategoriesCard(m['top_categories']),
          const SizedBox(height: 16),
          _byMonthCard(m['by_month']),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  Widget _summaryCard(double avgHours) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Resumo geral',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
            const SizedBox(height: 8),
            Row(
              children: [
                const Icon(Icons.access_time, size: 18, color: _grey),
                const SizedBox(width: 6),
                Text(
                  'Tempo médio de revisão: ${avgHours.toStringAsFixed(1)} horas',
                  style: const TextStyle(fontSize: 13),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _byTypeCard(dynamic raw) {
    final entries = _mapEntries(raw);
    if (entries.isEmpty) return _emptyChartCard('Por tipo');
    final colors = <String, Color>{
      'new_skill': _boraGreen,
      'playbook_update': _boraOrange,
      'settings_update': _grey,
    };
    final labels = <String, String>{
      'new_skill': 'Skill nova',
      'playbook_update': 'Playbook',
      'settings_update': 'Configuração',
    };
    return _pieCard('Por tipo', entries, colors, labels);
  }

  Widget _byZoneCard(dynamic raw) {
    final entries = _mapEntries(raw);
    if (entries.isEmpty) return _emptyChartCard('Por zona');
    final colors = <String, Color>{
      'safe': _boraGreen,
      'critical': _critical,
    };
    final labels = <String, String>{
      'safe': 'Segura',
      'critical': 'Crítica',
    };
    return _pieCard('Por zona', entries, colors, labels);
  }

  Widget _topCategoriesCard(dynamic raw) {
    final list = (raw is List) ? raw : const [];
    if (list.isEmpty) return _emptyChartCard('Top categorias');
    final bars = <_BarItem>[];
    for (var i = 0; i < list.length && i < 10; i++) {
      final item = list[i];
      if (item is! Map) continue;
      final cat = (item['category'] ?? '').toString();
      final count = (item['count'] as num?)?.toInt() ?? 0;
      if (cat.isEmpty) continue;
      bars.add(_BarItem(label: cat, value: count.toDouble()));
    }
    if (bars.isEmpty) return _emptyChartCard('Top categorias');
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Top categorias',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
            const SizedBox(height: 16),
            SizedBox(
              height: 220,
              child: BarChart(
                BarChartData(
                  alignment: BarChartAlignment.spaceAround,
                  maxY: bars.map((b) => b.value).reduce((a, b) => a > b ? a : b) * 1.2,
                  titlesData: FlTitlesData(
                    leftTitles: const AxisTitles(
                        sideTitles: SideTitles(
                            showTitles: true, reservedSize: 28)),
                    rightTitles: const AxisTitles(
                        sideTitles: SideTitles(showTitles: false)),
                    topTitles: const AxisTitles(
                        sideTitles: SideTitles(showTitles: false)),
                    bottomTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        reservedSize: 50,
                        getTitlesWidget: (value, meta) {
                          final i = value.toInt();
                          if (i < 0 || i >= bars.length) {
                            return const SizedBox();
                          }
                          final label = bars[i].label;
                          final short = label.length > 8
                              ? '${label.substring(0, 8)}…'
                              : label;
                          return Padding(
                            padding: const EdgeInsets.only(top: 6),
                            child: Transform.rotate(
                              angle: -0.5,
                              child: Text(short,
                                  style: const TextStyle(fontSize: 9)),
                            ),
                          );
                        },
                      ),
                    ),
                  ),
                  gridData: const FlGridData(show: false),
                  borderData: FlBorderData(show: false),
                  barGroups: List.generate(
                    bars.length,
                    (i) => BarChartGroupData(
                      x: i,
                      barRods: [
                        BarChartRodData(
                          toY: bars[i].value,
                          color: _boraGreen,
                          width: 14,
                          borderRadius:
                              const BorderRadius.vertical(top: Radius.circular(4)),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _byMonthCard(dynamic raw) {
    final list = (raw is List) ? raw : const [];
    if (list.isEmpty) return _emptyChartCard('Por mês (últimos 6 meses)');
    final spots = <FlSpot>[];
    final labels = <String>[];
    for (var i = 0; i < list.length; i++) {
      final item = list[i];
      if (item is! Map) continue;
      final month = (item['month'] ?? '').toString();
      final count = (item['count'] as num?)?.toInt() ?? 0;
      spots.add(FlSpot(i.toDouble(), count.toDouble()));
      labels.add(month.length >= 7 ? month.substring(5, 7) : month);
    }
    if (spots.isEmpty) return _emptyChartCard('Por mês (últimos 6 meses)');
    final maxY = spots.map((s) => s.y).reduce((a, b) => a > b ? a : b);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Por mês (últimos 6 meses)',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
            const SizedBox(height: 16),
            SizedBox(
              height: 200,
              child: LineChart(
                LineChartData(
                  minY: 0,
                  maxY: maxY == 0 ? 1 : maxY * 1.2,
                  gridData: const FlGridData(show: false),
                  borderData: FlBorderData(show: false),
                  titlesData: FlTitlesData(
                    leftTitles: const AxisTitles(
                        sideTitles: SideTitles(
                            showTitles: true, reservedSize: 28)),
                    rightTitles: const AxisTitles(
                        sideTitles: SideTitles(showTitles: false)),
                    topTitles: const AxisTitles(
                        sideTitles: SideTitles(showTitles: false)),
                    bottomTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        reservedSize: 22,
                        getTitlesWidget: (value, meta) {
                          final i = value.toInt();
                          if (i < 0 || i >= labels.length) {
                            return const SizedBox();
                          }
                          return Text(labels[i],
                              style: const TextStyle(fontSize: 10));
                        },
                      ),
                    ),
                  ),
                  lineBarsData: [
                    LineChartBarData(
                      spots: spots,
                      isCurved: true,
                      curveSmoothness: 0.3,
                      preventCurveOverShooting: true,
                      color: _boraOrange,
                      barWidth: 2.5,
                      dotData: const FlDotData(show: true),
                      belowBarData: BarAreaData(
                        show: true,
                        color: _boraOrange.withValues(alpha: 0.12),
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

  Widget _pieCard(
    String title,
    List<MapEntry<String, int>> entries,
    Map<String, Color> colors,
    Map<String, String> labels,
  ) {
    final total = entries.fold<int>(0, (a, b) => a + b.value);
    if (total == 0) return _emptyChartCard(title);
    final sections = <PieChartSectionData>[];
    for (final e in entries) {
      final color = colors[e.key] ?? _grey;
      final pct = (e.value / total) * 100;
      sections.add(PieChartSectionData(
        color: color,
        value: e.value.toDouble(),
        title: '${pct.toStringAsFixed(0)}%',
        radius: 60,
        titleStyle: const TextStyle(
            color: Colors.white, fontWeight: FontWeight.bold, fontSize: 11),
      ));
    }
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title,
                style: const TextStyle(
                    fontWeight: FontWeight.bold, fontSize: 14)),
            const SizedBox(height: 12),
            SizedBox(
              height: 180,
              child: PieChart(
                PieChartData(
                  sections: sections,
                  centerSpaceRadius: 24,
                  sectionsSpace: 2,
                ),
              ),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 12,
              runSpacing: 6,
              children: entries.map((e) {
                final color = colors[e.key] ?? _grey;
                final label = labels[e.key] ?? e.key;
                return Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 12,
                      height: 12,
                      decoration: BoxDecoration(
                        color: color,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                    const SizedBox(width: 4),
                    Text('$label (${e.value})',
                        style: const TextStyle(fontSize: 12)),
                  ],
                );
              }).toList(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _emptyChartCard(String title) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          children: [
            Text(title,
                style: const TextStyle(
                    fontWeight: FontWeight.bold, fontSize: 14)),
            const SizedBox(height: 12),
            Text('Sem dados ainda',
                style: TextStyle(color: Colors.grey.shade600)),
          ],
        ),
      ),
    );
  }

  List<MapEntry<String, int>> _mapEntries(dynamic raw) {
    if (raw is! Map) return const [];
    return raw.entries
        .map((e) => MapEntry(
              e.key.toString(),
              (e.value as num?)?.toInt() ?? 0,
            ))
        .where((e) => e.value > 0)
        .toList();
  }
}

class _BarItem {
  const _BarItem({required this.label, required this.value});
  final String label;
  final double value;
}
