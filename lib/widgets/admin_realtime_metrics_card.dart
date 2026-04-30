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
      final supa = Supabase.instance.client;
      final results = await Future.wait([
        supa.from('orders').count(CountOption.exact)
            .inFilter('status', ['created', 'preparing', 'callingDriver']),
        supa.from('orders').count(CountOption.exact)
            .inFilter('status', ['driverAccepted', 'pickedUp', 'onTheWay']),
        supa.from('drivers').count(CountOption.exact).eq('is_online', true),
        supa.from('orders')
            .select('created_at, delivered_at')
            .eq('status', 'delivered')
            .gte('delivered_at', DateTime.now().subtract(const Duration(hours: 24)).toIso8601String())
            .limit(500),
        supa.from('orders')
            .select('id')
            .eq('status', 'callingDriver')
            .lt('created_at', DateTime.now().subtract(const Duration(minutes: 30)).toIso8601String())
            .limit(1),
      ]);
      final pending = results[0] as int;
      final active = results[1] as int;
      final drivers = results[2] as int;
      final delivered = (results[3] as List).cast<Map<String, dynamic>>();
      final stale = (results[4] as List).isNotEmpty;

      double? avg;
      if (delivered.isNotEmpty) {
        var sum = 0.0;
        var count = 0;
        for (final o in delivered) {
          final c = DateTime.tryParse((o['created_at'] ?? '') as String);
          final d = DateTime.tryParse((o['delivered_at'] ?? '') as String);
          if (c != null && d != null) {
            sum += d.difference(c).inSeconds / 60.0;
            count++;
          }
        }
        if (count > 0) avg = sum / count;
      }

      if (mounted) {
        setState(() {
          _pending = pending;
          _active = active;
          _driversOnline = drivers;
          _avgDeliveryMin = avg;
          _hasStaleOrder = stale;
          _loading = false;
        });
      }
    } catch (_) {
      // silencioso — auto-retry no próximo tick
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
