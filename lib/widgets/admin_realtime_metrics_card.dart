import 'dart:async';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Card "AGORA" para o admin_dashboard_screen.
/// 4 métricas: pending, active, drivers online, tempo médio entrega 24h.
/// Auto-refresh 10s. Padrão Uber Eats Restaurant Ops / Glovo Operations.
class AdminRealtimeMetricsCard extends StatefulWidget {
  const AdminRealtimeMetricsCard({super.key});
  @override
  State<AdminRealtimeMetricsCard> createState() => _AdminRealtimeMetricsCardState();
}

class _AdminRealtimeMetricsCardState extends State<AdminRealtimeMetricsCard> {
  Timer? _timer;
  int _pending = 0;
  int _active = 0;
  int _driversOnline = 0;
  double? _avgDeliveryMin;
  bool _hasStaleOrder = false;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _refresh();
    _timer = Timer.periodic(const Duration(seconds: 10), (_) => _refresh());
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _refresh() async {
    try {
      // Single round-trip via admin_realtime_metrics RPC (SECURITY DEFINER,
      // _admin_op_guard). Replaces 5 separate count/select queries — much
      // cheaper for a 10s polling card.
      final supa = Supabase.instance.client;
      final res = await supa.rpc('admin_realtime_metrics');
      final m = (res as Map).cast<String, dynamic>();

      if (mounted) {
        setState(() {
          _pending = (m['pending_orders'] as num?)?.toInt() ?? 0;
          _active = (m['active_orders'] as num?)?.toInt() ?? 0;
          _driversOnline = (m['drivers_online'] as num?)?.toInt() ?? 0;
          _avgDeliveryMin = (m['avg_delivery_min_24h'] as num?)?.toDouble();
          _hasStaleOrder = m['has_stale_order'] == true;
          _loading = false;
        });
      }
    } catch (e) {
      // Auto-retry no próximo tick — log para debug mas sem spamar UI.
      debugPrint('[AdminRealtimeMetricsCard] RPC error: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.all(8),
      child: Column(
        children: [
          if (_hasStaleOrder)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(8),
              color: Colors.red,
              child: const Text(
                '⚠️ Pedido pendente há mais de 30min sem driver',
                style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                textAlign: TextAlign.center,
              ),
            ),
          Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.bolt, color: Colors.green),
                    const SizedBox(width: 4),
                    const Text('AGORA', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                    const Spacer(),
                    if (_loading)
                      const SizedBox(width: 12, height: 12, child: CircularProgressIndicator(strokeWidth: 2)),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    _metric('Pending', '$_pending', _pending > 5 ? Colors.orange : Colors.black),
                    _metric('Active', '$_active', Colors.blue),
                    _metric('Drivers online', '$_driversOnline', Colors.green),
                    _metric(
                      'Tempo médio',
                      _avgDeliveryMin == null ? '—' : '${_avgDeliveryMin!.toStringAsFixed(0)}min',
                      Colors.purple,
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _metric(String label, String value, Color color) {
    return Column(
      children: [
        Text(value, style: TextStyle(color: color, fontSize: 20, fontWeight: FontWeight.bold)),
        Text(label, style: const TextStyle(fontSize: 10, color: Colors.black54)),
      ],
    );
  }
}
