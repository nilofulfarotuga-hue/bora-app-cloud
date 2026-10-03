// T13 — Admin advanced KPIs (hot zones + avg ticket + conversion).

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../config/app_colors.dart';
import '../../widgets/bora/bora_screen_app_bar.dart';

class AdminAdvancedKpisScreen extends StatefulWidget {
  const AdminAdvancedKpisScreen({super.key});

  @override
  State<AdminAdvancedKpisScreen> createState() => _AdminAdvancedKpisScreenState();
}

class _AdminAdvancedKpisScreenState extends State<AdminAdvancedKpisScreen> {
  int _daysBack = 30;
  bool _loading = true;
  Map<String, dynamic>? _avgTicket;
  Map<String, dynamic>? _conversion;
  List<Map<String, dynamic>> _hotZones = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final results = await Future.wait([
        Supabase.instance.client.rpc('admin_kpi_avg_ticket', params: {'p_days_back': _daysBack}),
        Supabase.instance.client.rpc('admin_kpi_conversion', params: {'p_days_back': _daysBack}),
        Supabase.instance.client.rpc('admin_kpi_hot_zones', params: {'p_days_back': _daysBack, 'p_limit': 20}),
      ]);
      if (mounted) {
        setState(() {
          _avgTicket = Map<String, dynamic>.from(results[0] as Map);
          _conversion = Map<String, dynamic>.from(results[1] as Map);
          _hotZones = List<Map<String, dynamic>>.from(results[2] as List);
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _loading = false);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Erro: $e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: BoraScreenAppBar(
        title: 'KPIs Avançado',
        actions: [IconButton(icon: const Icon(Icons.refresh), onPressed: _load)],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.all(16),
              children: [
                Row(children: [
                  const Text('Período: '),
                  ...[7, 30, 90].map((d) => Padding(
                        padding: const EdgeInsets.only(right: 6),
                        child: ChoiceChip(
                          label: Text('${d}d'),
                          selected: _daysBack == d,
                          onSelected: (_) {
                            setState(() => _daysBack = d);
                            _load();
                          },
                        ),
                      )),
                ]),
                const SizedBox(height: 16),
                _buildAvgTicket(),
                const SizedBox(height: 16),
                _buildConversion(),
                const SizedBox(height: 16),
                _buildHotZones(),
              ],
            ),
          ),
    );
  }

  Widget _buildAvgTicket() {
    if (_avgTicket == null) return const SizedBox();
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('Ticket médio',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
          const SizedBox(height: 8),
          Text('${_avgTicket!['order_count'] ?? 0} pedidos'),
          const SizedBox(height: 4),
          _kpiRow('Total', '€${_avgTicket!['avg_ticket_total'] ?? 0}'),
          _kpiRow('Parceiro', '€${_avgTicket!['avg_ticket_partner'] ?? 0}'),
          _kpiRow('Mercado', '€${_avgTicket!['avg_ticket_market'] ?? 0}'),
        ]),
      ),
    );
  }

  Widget _buildConversion() {
    if (_conversion == null) return const SizedBox();
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('Funnel de conversão',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
          const SizedBox(height: 8),
          _kpiRow('Criados', '${_conversion!['orders_created'] ?? 0}'),
          _kpiRow('Entregues', '${_conversion!['orders_delivered'] ?? 0}'),
          _kpiRow('Cancelados', '${_conversion!['orders_cancelled'] ?? 0}'),
          _kpiRow('Rejeitados', '${_conversion!['orders_rejected'] ?? 0}'),
          const Divider(color: AppColors.divider),
          _kpiRow('Taxa conversão',
              '${_conversion!['conversion_rate'] ?? 0}%',
              highlight: true),
          _kpiRow('Taxa cancel.',
              '${_conversion!['cancel_rate'] ?? 0}%'),
        ]),
      ),
    );
  }

  Widget _buildHotZones() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('Zonas quentes (top 20)',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
          const SizedBox(height: 4),
          const Text('Bucketize por (lat,lng) ~1.1km',
              style: TextStyle(fontSize: 12, color: AppColors.textSubtle)),
          const SizedBox(height: 8),
          if (_hotZones.isEmpty)
            const Text('Sem dados.')
          else
            ..._hotZones.take(20).map((z) => ListTile(
                  dense: true,
                  leading: const Icon(Icons.location_on, color: AppColors.primary),
                  title: Text('(${z['cell_lat']}, ${z['cell_lng']})'),
                  subtitle: Text('${z['order_count']} pedidos · €${z['total_revenue']} · ${z['avg_distance']}km médio'),
                )),
        ]),
      ),
    );
  }

  Widget _kpiRow(String label, String value, {bool highlight = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(children: [
        Expanded(child: Text(label)),
        Text(value,
            style: TextStyle(
                fontWeight: highlight ? FontWeight.bold : FontWeight.normal,
                color: highlight ? AppColors.primary : null,
                fontSize: highlight ? 16 : 14)),
      ]),
    );
  }
}
