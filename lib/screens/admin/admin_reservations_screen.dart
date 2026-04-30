import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../config/app_colors.dart';
import '../../models/reservation_model.dart';

/// Admin view: all table reservations across restaurants (BR §16.2).
class AdminReservationsScreen extends StatefulWidget {
  const AdminReservationsScreen({super.key});

  @override
  State<AdminReservationsScreen> createState() =>
      _AdminReservationsScreenState();
}

class _AdminReservationsScreenState extends State<AdminReservationsScreen> {
  late Future<List<ReservationModel>> _future;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<List<ReservationModel>> _load() async {
    final rows = await Supabase.instance.client
        .from('reservations')
        .select()
        .order('reserved_for', ascending: false)
        .limit(200);
    return (rows as List)
        .cast<Map<String, dynamic>>()
        .map(ReservationModel.fromSupabase)
        .toList();
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
          'Reservas (admin)',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
      ),
      body: Column(
        children: [
          // T2.G: métricas 30d (no-show%, cancel%, receita Bora, créditos)
          const _MetricsHeader(),
          Expanded(
            child: FutureBuilder<List<ReservationModel>>(
              future: _future,
              builder: (context, snap) {
                if (snap.connectionState != ConnectionState.done) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (snap.hasError) {
                  return Center(child: Text('Erro: ${snap.error}'));
                }
                final list = snap.data ?? const <ReservationModel>[];
                if (list.isEmpty) {
                  return const Center(child: Text('Sem reservas.'));
                }
                return RefreshIndicator(
                  onRefresh: () async => setState(() => _future = _load()),
                  child: ListView.separated(
                    padding: const EdgeInsets.all(12),
                    itemCount: list.length,
                    separatorBuilder: (_, __) => const Divider(height: 1),
                    itemBuilder: (context, i) {
                      final r = list[i];
                      final d = r.reservedFor.toLocal();
                      return ListTile(
                        title: Text(
                          '${r.clientName} · ${r.people} pessoas · ${r.restaurantId}',
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                        subtitle: Text(
                          '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')} '
                          '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')} · '
                          '${r.status.dbName}',
                        ),
                      );
                    },
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _MetricsHeader extends StatefulWidget {
  const _MetricsHeader();
  @override
  State<_MetricsHeader> createState() => _MetricsHeaderState();
}

class _MetricsHeaderState extends State<_MetricsHeader> {
  Map<String, dynamic>? _data;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final res = await Supabase.instance.client
          .rpc('admin_reservations_metrics', params: {'p_days': 30});
      if (mounted) setState(() => _data = (res as Map).cast<String, dynamic>());
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final d = _data;
    if (d == null) return const SizedBox(height: 4);
    return Container(
      width: double.infinity,
      color: Colors.deepPurple.shade50,
      padding: const EdgeInsets.all(12),
      child: Wrap(
        spacing: 16,
        runSpacing: 8,
        children: [
          _stat('Total 30d', '${d['total']}'),
          _stat('No-show', '${d['no_show_rate_pct']}%', highlight: true),
          _stat('Cancel', '${d['cancellation_rate_pct']}%'),
          _stat('Receita',
              '€${(((d['bora_revenue_cents'] as num?) ?? 0) / 100).toStringAsFixed(2)}',
              highlight: true),
          _stat('Créditos',
              '€${(((d['credits_given_cents'] as num?) ?? 0) / 100).toStringAsFixed(2)}'),
        ],
      ),
    );
  }

  Widget _stat(String label, String v, {bool highlight = false}) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label,
              style: const TextStyle(fontSize: 10, color: Colors.black54)),
          Text(v,
              style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: highlight ? Colors.deepPurple : Colors.black87)),
        ],
      );
}
