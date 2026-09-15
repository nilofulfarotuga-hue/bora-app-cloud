import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../config/app_colors.dart';
import '../../config/app_spacing.dart';

/// Reservas Pro F4 admin — métricas dedicadas (B4-light).
///
/// BLOCO F (2026-05-18) — 3 tabs:
///   • Geral — admin_reservations_metrics(p_days=7/30/90) (existente)
///   • Por restaurante — admin_get_reservations_stats(p_restaurant_id, ...)
///   • Período custom — admin_get_reservations_stats(p_start_date, p_end_date)
///
/// PT-BR (Regra 6).
class AdminReservationsMetricsScreen extends StatefulWidget {
  const AdminReservationsMetricsScreen({super.key});

  @override
  State<AdminReservationsMetricsScreen> createState() =>
      _AdminReservationsMetricsScreenState();
}

class _AdminReservationsMetricsScreenState
    extends State<AdminReservationsMetricsScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tab;

  // Tab 1 — geral rolling.
  late Future<Map<String, dynamic>> _generalFuture;
  int _days = 30;

  // Tab 2 — por restaurante.
  Future<Map<String, dynamic>>? _partnerFuture;
  List<Map<String, dynamic>> _partners = const [];
  String? _selectedPartnerId;
  String? _selectedPartnerName;

  // Tab 3 — período custom.
  Future<Map<String, dynamic>>? _customFuture;
  DateTime _customStart = DateTime.now().subtract(const Duration(days: 30));
  DateTime _customEnd = DateTime.now();

  @override
  void initState() {
    super.initState();
    _tab = TabController(length: 3, vsync: this);
    _generalFuture = _loadGeneral();
    _loadPartnersCache();
  }

  @override
  void dispose() {
    _tab.dispose();
    super.dispose();
  }

  // ─── Loaders ──────────────────────────────────────────────────────────────

  Future<Map<String, dynamic>> _loadGeneral() async {
    final res = await Supabase.instance.client.rpc(
      'admin_reservations_metrics',
      params: {'p_days': _days},
    );
    return Map<String, dynamic>.from(res as Map);
  }

  Future<void> _loadPartnersCache() async {
    try {
      final res = await Supabase.instance.client
          .rpc('admin_partners_with_counts');
      if (!mounted) return;
      setState(() {
        _partners = ((res as List?) ?? const [])
            .map((e) => Map<String, dynamic>.from(e as Map))
            .toList()
          ..sort((a, b) => (a['name'] as String? ?? '')
              .toLowerCase()
              .compareTo((b['name'] as String? ?? '').toLowerCase()));
      });
    } catch (_) {/* silent — tab usa fallback */}
  }

  Future<Map<String, dynamic>> _loadPartner(String partnerId) async {
    final res = await Supabase.instance.client.rpc(
      'admin_get_reservations_stats',
      params: {
        'p_restaurant_id': partnerId,
        'p_start_date': null,
        'p_end_date': null,
      },
    );
    return Map<String, dynamic>.from(res as Map);
  }

  Future<Map<String, dynamic>> _loadCustom() async {
    final res = await Supabase.instance.client.rpc(
      'admin_get_reservations_stats',
      params: {
        'p_restaurant_id': null,
        'p_start_date': _isoDate(_customStart),
        'p_end_date': _isoDate(_customEnd),
      },
    );
    return Map<String, dynamic>.from(res as Map);
  }

  String _isoDate(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  String _fmtDate(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';

  // ─── Build ────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        elevation: 0,
        flexibleSpace: const DecoratedBox(
          decoration: BoxDecoration(gradient: AppColors.headerGradient),
        ),
        title: const Text(
          'Métricas Reservas Pro',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        bottom: TabBar(
          controller: _tab,
          isScrollable: true,
          indicatorColor: Colors.white,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white70,
          tabs: const [
            Tab(icon: Icon(Icons.calendar_view_day), text: 'Geral'),
            Tab(icon: Icon(Icons.storefront), text: 'Por parceiro'),
            Tab(icon: Icon(Icons.date_range), text: 'Período'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tab,
        children: [
          _buildGeneralTab(),
          _buildPartnerTab(),
          _buildCustomTab(),
        ],
      ),
    );
  }

  // ─── Tab 1: Geral ────────────────────────────────────────────────────────

  Widget _buildGeneralTab() {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
          child: Row(
            children: [
              const Text('Período:'),
              const SizedBox(width: 8),
              DropdownButton<int>(
                value: _days,
                items: const [
                  DropdownMenuItem(value: 7, child: Text('Últimos 7 dias')),
                  DropdownMenuItem(value: 30, child: Text('Últimos 30 dias')),
                  DropdownMenuItem(value: 90, child: Text('Últimos 90 dias')),
                ],
                onChanged: (v) {
                  if (v == null) return;
                  setState(() {
                    _days = v;
                    _generalFuture = _loadGeneral();
                  });
                },
              ),
            ],
          ),
        ),
        Expanded(
          child: RefreshIndicator(
            onRefresh: () async {
              setState(() => _generalFuture = _loadGeneral());
              await _generalFuture;
            },
            child: FutureBuilder<Map<String, dynamic>>(
              future: _generalFuture,
              builder: (_, snap) => _buildStatsView(snap),
            ),
          ),
        ),
      ],
    );
  }

  // ─── Tab 2: Por parceiro ─────────────────────────────────────────────────

  Widget _buildPartnerTab() {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(12),
          child: DropdownButtonFormField<String>(
            initialValue: _selectedPartnerId,
            isExpanded: true,
            decoration: const InputDecoration(
              labelText: 'Selecione um parceiro',
              border: OutlineInputBorder(),
            ),
            items: _partners.isEmpty
                ? const [
                    DropdownMenuItem(
                      value: null,
                      child: Text('A carregar parceiros...'),
                    ),
                  ]
                : _partners.map((p) {
                    final id = p['id']?.toString() ?? '';
                    final name = (p['name'] as String?) ?? id;
                    return DropdownMenuItem<String>(
                      value: id,
                      child:
                          Text(name, overflow: TextOverflow.ellipsis),
                    );
                  }).toList(),
            onChanged: (v) {
              if (v == null) return;
              final p = _partners.firstWhere(
                (x) => x['id']?.toString() == v,
                orElse: () => const {},
              );
              setState(() {
                _selectedPartnerId = v;
                _selectedPartnerName = p['name'] as String?;
                _partnerFuture = _loadPartner(v);
              });
            },
          ),
        ),
        Expanded(
          child: _partnerFuture == null
              ? const Center(
                  child: Padding(
                    padding: EdgeInsets.all(24),
                    child: Text(
                      'Selecione um parceiro para ver as métricas.',
                      style: TextStyle(color: AppColors.textSecondary),
                    ),
                  ),
                )
              : RefreshIndicator(
                  onRefresh: () async {
                    if (_selectedPartnerId == null) return;
                    setState(() =>
                        _partnerFuture = _loadPartner(_selectedPartnerId!));
                    await _partnerFuture;
                  },
                  child: FutureBuilder<Map<String, dynamic>>(
                    future: _partnerFuture,
                    builder: (_, snap) => _buildStatsView(
                      snap,
                      title: _selectedPartnerName,
                    ),
                  ),
                ),
        ),
      ],
    );
  }

  // ─── Tab 3: Período custom ───────────────────────────────────────────────

  Widget _buildCustomTab() {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(12),
          child: OutlinedButton.icon(
            icon: const Icon(Icons.date_range),
            label: Text(
              '${_fmtDate(_customStart)} → ${_fmtDate(_customEnd)}',
              overflow: TextOverflow.ellipsis,
            ),
            onPressed: () async {
              final range = await showDateRangePicker(
                context: context,
                firstDate: DateTime.now().subtract(const Duration(days: 365)),
                lastDate: DateTime.now(),
                initialDateRange: DateTimeRange(
                  start: _customStart,
                  end: _customEnd,
                ),
                helpText: 'Período custom',
                saveText: 'OK',
                cancelText: 'Cancelar',
              );
              if (range == null || !mounted) return;
              setState(() {
                _customStart = range.start;
                _customEnd = range.end;
                _customFuture = _loadCustom();
              });
            },
          ),
        ),
        Expanded(
          child: _customFuture == null
              ? const Center(
                  child: Padding(
                    padding: EdgeInsets.all(24),
                    child: Text(
                      'Selecione um período para ver as métricas.',
                      style: TextStyle(color: AppColors.textSecondary),
                    ),
                  ),
                )
              : RefreshIndicator(
                  onRefresh: () async {
                    setState(() => _customFuture = _loadCustom());
                    await _customFuture;
                  },
                  child: FutureBuilder<Map<String, dynamic>>(
                    future: _customFuture,
                    builder: (_, snap) => _buildStatsView(snap),
                  ),
                ),
        ),
      ],
    );
  }

  // ─── View partilhada (Stats + cards + chart) ──────────────────────────────

  Widget _buildStatsView(AsyncSnapshot<Map<String, dynamic>> snap,
      {String? title}) {
    if (snap.connectionState != ConnectionState.done) {
      return const Center(child: CircularProgressIndicator());
    }
    if (snap.hasError) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            'Erro: ${snap.error}',
            style: const TextStyle(color: AppColors.error),
            textAlign: TextAlign.center,
          ),
        ),
      );
    }
    final data = snap.data ?? const <String, dynamic>{};
    final stats = data['stats'] is Map ? data['stats'] as Map : data;

    int asInt(String key) => ((stats[key] as num?) ?? 0).toInt();

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
        if (title != null) ...[
          Text(
            title,
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: 12),
        ],
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
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 12),
          SizedBox(
            height: 220,
            child: BarChart(
              BarChartData(
                alignment: BarChartAlignment.spaceAround,
                barGroups: [
                  _bar(0, approved, Colors.green),
                  _bar(1, cancelled, Colors.orange),
                  _bar(2, noShow, Colors.red),
                  _bar(3, walkIns, Colors.purple),
                  _bar(4, seated, Colors.teal),
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
        padding: const EdgeInsets.all(12),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: const TextStyle(
                  fontSize: 13, color: AppColors.textSecondary),
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
