import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../config/app_colors.dart';

/// Reservas Pro F4 admin — métricas dedicadas (B4-light).
///
/// Padrão visual igual ao admin existente: AppColors.surface + headerGradient.
/// Sem AdminStore — chama RPC directo (consistente com pattern admin projecto).
class AdminReservationsMetricsScreen extends StatefulWidget {
  const AdminReservationsMetricsScreen({super.key});

  @override
  State<AdminReservationsMetricsScreen> createState() =>
      _AdminReservationsMetricsScreenState();
}

class _AdminReservationsMetricsScreenState
    extends State<AdminReservationsMetricsScreen> {
  late Future<Map<String, dynamic>> _future;
  int _days = 30;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<Map<String, dynamic>> _load() async {
    final res = await Supabase.instance.client.rpc(
      'admin_reservations_metrics',
      params: {'p_days': _days},
    );
    return Map<String, dynamic>.from(res as Map);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.surface,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        foregroundColor: Colors.white,
        elevation: 0,
        flexibleSpace: const DecoratedBox(
          decoration: BoxDecoration(gradient: AppColors.headerGradient),
        ),
        title: const Text(
          'Métricas Reservas Pro',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        actions: [
          DropdownButton<int>(
            value: _days,
            dropdownColor: AppColors.primary,
            iconEnabledColor: Colors.white,
            underline: const SizedBox.shrink(),
            items: const [
              DropdownMenuItem(
                value: 7,
                child: Text('7 dias', style: TextStyle(color: Colors.white)),
              ),
              DropdownMenuItem(
                value: 30,
                child: Text('30 dias', style: TextStyle(color: Colors.white)),
              ),
              DropdownMenuItem(
                value: 90,
                child: Text('90 dias', style: TextStyle(color: Colors.white)),
              ),
            ],
            onChanged: (v) {
              if (v == null) return;
              setState(() {
                _days = v;
                _future = _load();
              });
            },
          ),
          const SizedBox(width: 16),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () async {
          setState(() => _future = _load());
          await _future;
        },
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
                  child: Text(
                    'Erro: ${snap.error}',
                    style: const TextStyle(color: Colors.red),
                    textAlign: TextAlign.center,
                  ),
                ),
              );
            }
            final data = snap.data ?? const {};
            final stats =
                data['stats'] is Map ? data['stats'] as Map : data;

            int asInt(String key) =>
                ((stats[key] as num?) ?? 0).toInt();

            final total = asInt('total');
            final approved = asInt('approved');
            final cancelled = asInt('cancelled');
            final noShow = asInt('no_show');
            final walkIns = asInt('walk_ins');
            final seated = asInt('seated');
            final covers = asInt('total_covers');

            final noShowPct = total == 0 ? 0.0 : (noShow / total * 100);
            Color noShowColor;
            if (noShowPct < 5) {
              noShowColor = Colors.green;
            } else if (noShowPct < 10) {
              noShowColor = Colors.orange;
            } else {
              noShowColor = Colors.red;
            }

            return ListView(
              padding: const EdgeInsets.all(16),
              children: [
                GridView.count(
                  crossAxisCount: 2,
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  crossAxisSpacing: 12,
                  mainAxisSpacing: 12,
                  childAspectRatio: 1.6,
                  children: [
                    _kpi('Total', '$total', Colors.blue),
                    _kpi('Aprovadas', '$approved', Colors.green),
                    _kpi('Canceladas', '$cancelled', Colors.orange),
                    _kpi(
                      'No-shows',
                      '$noShow (${noShowPct.toStringAsFixed(1)}%)',
                      noShowColor,
                    ),
                    _kpi('Walk-ins', '$walkIns', Colors.purple),
                    _kpi('Cobertos', '$covers', Colors.teal),
                  ],
                ),
                const SizedBox(height: 24),
                if (total > 0) ...[
                  const Text(
                    'Distribuição por status',
                    style: TextStyle(
                        fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    height: 220,
                    child: BarChart(
                      BarChartData(
                        alignment: BarChartAlignment.spaceAround,
                        barGroups: [
                          BarChartGroupData(x: 0, barRods: [
                            BarChartRodData(
                              toY: approved.toDouble(),
                              color: Colors.green,
                              width: 24,
                            ),
                          ]),
                          BarChartGroupData(x: 1, barRods: [
                            BarChartRodData(
                              toY: cancelled.toDouble(),
                              color: Colors.orange,
                              width: 24,
                            ),
                          ]),
                          BarChartGroupData(x: 2, barRods: [
                            BarChartRodData(
                              toY: noShow.toDouble(),
                              color: Colors.red,
                              width: 24,
                            ),
                          ]),
                          BarChartGroupData(x: 3, barRods: [
                            BarChartRodData(
                              toY: walkIns.toDouble(),
                              color: Colors.purple,
                              width: 24,
                            ),
                          ]),
                          BarChartGroupData(x: 4, barRods: [
                            BarChartRodData(
                              toY: seated.toDouble(),
                              color: Colors.teal,
                              width: 24,
                            ),
                          ]),
                        ],
                        titlesData: FlTitlesData(
                          show: true,
                          bottomTitles: AxisTitles(
                            sideTitles: SideTitles(
                              showTitles: true,
                              reservedSize: 30,
                              getTitlesWidget: (v, _) {
                                const labels = [
                                  'Aprov.',
                                  'Cancel.',
                                  'No-show',
                                  'Walk',
                                  'Sent.'
                                ];
                                final i = v.toInt();
                                return Padding(
                                  padding: const EdgeInsets.only(top: 4),
                                  child: Text(
                                    i >= 0 && i < labels.length
                                        ? labels[i]
                                        : '',
                                    style: const TextStyle(fontSize: 11),
                                  ),
                                );
                              },
                            ),
                          ),
                          leftTitles: const AxisTitles(
                            sideTitles: SideTitles(
                              showTitles: true,
                              reservedSize: 30,
                            ),
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
                    padding: EdgeInsets.symmetric(vertical: 32),
                    child: Center(
                      child: Text(
                        'Sem dados no período seleccionado.',
                        style: TextStyle(color: Colors.black54),
                      ),
                    ),
                  ),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _kpi(String label, String value, Color color) {
    return Card(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: TextStyle(fontSize: 13, color: Colors.grey[700]),
            ),
            const SizedBox(height: 4),
            Text(
              value,
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.bold,
                color: color,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
