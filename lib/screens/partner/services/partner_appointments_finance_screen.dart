import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../config/app_colors.dart';
import '../../../config/app_spacing.dart';
import '../../../stores/partner_appointments_store.dart';
import '../../../widgets/bora/bora_screen_app_bar.dart';

/// Financeiro do prestador (vertical Serviços). Resumo da semana actual
/// (preview RPC) + BarChart das últimas 4 semanas (receita das liquidações)
/// + histórico de liquidações (appointment_payouts).
class PartnerAppointmentsFinanceScreen extends StatefulWidget {
  const PartnerAppointmentsFinanceScreen({super.key});

  @override
  State<PartnerAppointmentsFinanceScreen> createState() =>
      _PartnerAppointmentsFinanceScreenState();
}

class _PartnerAppointmentsFinanceScreenState
    extends State<PartnerAppointmentsFinanceScreen> {
  late Future<_FinanceData> _future;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<_FinanceData> _load() async {
    final store = context.read<PartnerAppointmentsStore>();
    final preview = await store.weeklyPreview();
    final payouts = await store.fetchPayouts();
    return _FinanceData(preview: preview, payouts: payouts);
  }

  void _refresh() => setState(() => _future = _load());

  String _eur(num cents) => '€${(cents / 100).toStringAsFixed(2)}';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: BoraScreenAppBar(
        title: 'Financeiro',
        actions: [
          IconButton(icon: const Icon(Icons.refresh), onPressed: _refresh),
        ],
      ),
      body: FutureBuilder<_FinanceData>(
        future: _future,
        builder: (context, snap) {
          if (snap.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snap.hasError) {
            return _error(snap.error.toString());
          }
          final data = snap.data!;
          return RefreshIndicator(
            onRefresh: () async => _refresh(),
            child: ListView(
              padding: const EdgeInsets.all(Spacing.lg),
              children: _content(data),
            ),
          );
        },
      ),
    );
  }

  List<Widget> _content(_FinanceData data) {
    final p = data.preview;
    final netCents = (p['net_payout_cents'] as num?) ?? 0;
    final totalAppointments = (p['total_appointments'] as num?)?.toInt() ?? 0;
    // FIM DO SINAL (2026-08-03) — chaves novas de compute_provider_weekly_payout:
    // recebido − taxa Bora (€0,50/marcação) = a repassar. O retido de faltas
    // fica 100% na Bora e por isso não entra no repasse.
    final recebido = (p['revenue_recebida_cents'] as num?) ?? 0;
    final taxaBora = (p['taxa_bora_cents'] as num?) ?? 0;
    final retido = (p['retido_no_show_cents'] as num?) ?? 0;

    return [
      const _SectionTitle('Esta semana'),
      const SizedBox(height: Spacing.md),
      GridView.count(
        crossAxisCount: 2,
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        mainAxisSpacing: Spacing.md,
        crossAxisSpacing: Spacing.md,
        childAspectRatio: 1.5,
        children: [
          _kpiCard('Marcações', '$totalAppointments', Icons.event_available,
              AppColors.primary),
          _kpiCard('Recebido', _eur(recebido), Icons.content_cut,
              AppColors.primary),
          _kpiCard('Retido (faltas)', _eur(retido), Icons.person_off_outlined,
              AppColors.primary),
          _kpiCard('Taxa Bora', _eur(taxaBora), Icons.percent,
              AppColors.accent),
        ],
      ),
      const SizedBox(height: Spacing.md),
      _netCard(netCents),
      const SizedBox(height: Spacing.xl),
      const _SectionTitle('Receita — últimas 4 semanas'),
      const SizedBox(height: Spacing.md),
      _revenueChart(data.payouts),
      const SizedBox(height: Spacing.xl),
      const _SectionTitle('Liquidações'),
      const SizedBox(height: Spacing.md),
      if (data.payouts.isEmpty)
        _emptyCard('Ainda não há liquidações.')
      else
        ...data.payouts.map(_payoutTile),
      const SizedBox(height: Spacing.xl),
    ];
  }

  Widget _netCard(num netCents) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.primary.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(Radii.lg),
      ),
      padding: const EdgeInsets.all(Spacing.lg),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'A repassar (estimado)',
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    color: AppColors.textPrimary,
                  ),
                ),
                SizedBox(height: 2),
                Text(
                  'A Bora transfere no acerto semanal.',
                  style: TextStyle(
                      fontSize: 11.5, color: AppColors.textSecondary),
                ),
              ],
            ),
          ),
          Text(
            _eur(netCents),
            style: const TextStyle(
              fontWeight: FontWeight.w800,
              fontSize: 20,
              color: AppColors.primary,
            ),
          ),
        ],
      ),
    );
  }

  Widget _kpiCard(String label, String value, IconData icon, Color color) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(Radii.lg),
        boxShadow: AppColors.shadowCard,
      ),
      padding: const EdgeInsets.all(Spacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 20, color: color),
          const SizedBox(height: 6),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              value,
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w800,
                color: color,
              ),
            ),
          ),
          Text(
            label,
            style: const TextStyle(
              fontSize: 12,
              color: AppColors.textSecondary,
            ),
          ),
        ],
      ),
    );
  }

  /// BarChart das últimas 4 semanas (mais antigas → recentes). Usa
  /// net_payout_cents de cada liquidação.
  Widget _revenueChart(List<Map<String, dynamic>> payouts) {
    // payouts vem desc; pega as 4 mais recentes e inverte para ordem temporal.
    final recent = payouts.take(4).toList().reversed.toList();
    if (recent.isEmpty) {
      return _emptyCard('Sem dados para o gráfico.');
    }
    final values = recent
        .map((r) => ((r['net_payout_cents'] as num?) ?? 0).toDouble() / 100)
        .toList();
    final labels = recent.map((r) => _weekLabel(r['week_start_at'])).toList();
    final maxY = values.fold<double>(0, (a, b) => a > b ? a : b);

    return Container(
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(Radii.lg),
        boxShadow: AppColors.shadowCard,
      ),
      padding: const EdgeInsets.all(Spacing.lg),
      child: SizedBox(
        height: 200,
        child: BarChart(
          BarChartData(
            maxY: maxY == 0 ? 1 : maxY * 1.2,
            gridData: const FlGridData(show: false),
            borderData: FlBorderData(show: false),
            titlesData: FlTitlesData(
              leftTitles: const AxisTitles(
                sideTitles: SideTitles(showTitles: true, reservedSize: 36),
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
                    if (i < 0 || i >= labels.length) {
                      return const SizedBox.shrink();
                    }
                    return Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text(labels[i],
                          style: const TextStyle(fontSize: 11)),
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
                      toY: values[i],
                      color: AppColors.primary,
                      width: 28,
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ],
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _payoutTile(Map<String, dynamic> r) {
    final n = (r['total_appointments'] as num?)?.toInt() ?? 0;
    final net = (r['net_payout_cents'] as num?) ?? 0;
    final status = (r['status'] as String?) ?? 'pending';
    final isPaid = status == 'paid';
    final statusColor = isPaid ? AppColors.success : AppColors.warning;

    return Container(
      margin: const EdgeInsets.only(bottom: Spacing.md),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(Radii.lg),
        boxShadow: AppColors.shadowCard,
      ),
      child: Padding(
        padding: const EdgeInsets.all(Spacing.lg),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _weekRange(r['week_start_at'], r['week_end_at']),
                    style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '$n ${n == 1 ? 'marcação' : 'marcações'}',
                    style: const TextStyle(
                      fontSize: 13,
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
                  _eur(net),
                  style: const TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 15,
                    color: AppColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 4),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: statusColor.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(Radii.sm),
                  ),
                  child: Text(
                    isPaid ? 'Pago' : 'Pendente',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: statusColor,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _emptyCard(String msg) => Container(
        decoration: BoxDecoration(
          color: AppColors.card,
          borderRadius: BorderRadius.circular(Radii.lg),
          boxShadow: AppColors.shadowCard,
        ),
        padding: const EdgeInsets.all(Spacing.lg),
        child: Text(msg,
            style: const TextStyle(color: AppColors.textSecondary)),
      );

  Widget _error(String e) => Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline,
                  size: 48, color: AppColors.error),
              const SizedBox(height: 12),
              Text(e.replaceFirst('Exception: ', ''),
                  textAlign: TextAlign.center),
              const SizedBox(height: 12),
              ElevatedButton(
                onPressed: _refresh,
                child: const Text('Tentar de novo'),
              ),
            ],
          ),
        ),
      );

  String _two(int v) => v.toString().padLeft(2, '0');

  String _weekLabel(Object? iso) {
    final dt = _parse(iso);
    if (dt == null) return '—';
    return '${_two(dt.day)}/${_two(dt.month)}';
  }

  String _weekRange(Object? start, Object? end) {
    final s = _parse(start);
    final e = _parse(end);
    if (s == null) return 'Semana';
    final sLabel = '${_two(s.day)}/${_two(s.month)}';
    if (e == null) return 'Semana de $sLabel';
    return '$sLabel – ${_two(e.day)}/${_two(e.month)}';
  }

  DateTime? _parse(Object? v) =>
      v is String ? DateTime.tryParse(v)?.toLocal() : null;
}

class _FinanceData {
  _FinanceData({required this.preview, required this.payouts});
  final Map<String, dynamic> preview;
  final List<Map<String, dynamic>> payouts;
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: const TextStyle(
        fontSize: 16,
        fontWeight: FontWeight.w800,
        color: AppColors.textPrimary,
      ),
    );
  }
}
