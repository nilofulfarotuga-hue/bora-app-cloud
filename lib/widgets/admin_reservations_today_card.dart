import 'dart:async';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../screens/admin/admin_reservations_screen.dart';

/// T2.G — Card "Reservas Hoje" no admin_dashboard.
class AdminReservationsTodayCard extends StatefulWidget {
  const AdminReservationsTodayCard({super.key});
  @override
  State<AdminReservationsTodayCard> createState() =>
      _AdminReservationsTodayCardState();
}

class _AdminReservationsTodayCardState
    extends State<AdminReservationsTodayCard> {
  Timer? _timer;
  Map<String, dynamic>? _data;

  @override
  void initState() {
    super.initState();
    _refresh();
    _timer =
        Timer.periodic(const Duration(seconds: 60), (_) => _refresh());
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _refresh() async {
    try {
      final res = await Supabase.instance.client
          .rpc('admin_reservations_today');
      if (!mounted) return;
      setState(() => _data = (res as Map).cast<String, dynamic>());
    } catch (e) {
      debugPrint('[AdminReservationsTodayCard] $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final d = _data;
    if (d == null) return const SizedBox.shrink();
    final pending = (d['pending'] as num?)?.toInt() ?? 0;
    final approved = (d['approved'] as num?)?.toInt() ?? 0;
    final next = (d['next'] as List?) ?? const [];
    if (pending == 0 && approved == 0 && next.isEmpty) {
      return const SizedBox.shrink();
    }
    return Card(
      margin: const EdgeInsets.all(8),
      color: Colors.deepPurple.shade50,
      child: InkWell(
        onTap: () => Navigator.push(
            context,
            MaterialPageRoute(
                builder: (_) => const AdminReservationsScreen())),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                children: [
                  const Icon(Icons.event_seat,
                      color: Colors.deepPurple, size: 20),
                  const SizedBox(width: 8),
                  const Text('Reservas hoje',
                      style: TextStyle(
                          fontWeight: FontWeight.bold, fontSize: 14)),
                  const Spacer(),
                  _badge('Pending', pending, Colors.orange),
                  const SizedBox(width: 6),
                  _badge('Approved', approved, Colors.green),
                ],
              ),
            ),
            ...next.take(5).map((e) {
              final r = (e as Map).cast<String, dynamic>();
              final t = DateTime.tryParse(r['reserved_for'] as String);
              return ListTile(
                dense: true,
                leading: Icon(Icons.access_time,
                    size: 16,
                    color: r['status'] == 'pending'
                        ? Colors.orange
                        : Colors.green),
                title: Text(
                    '${t != null ? "${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}" : '—'} · ${r['people']} pax · ${r['client_name'] ?? '?'}'),
                subtitle: Text('${r['restaurant_id']} · ${r['status']}',
                    style: const TextStyle(fontSize: 11)),
              );
            }),
          ],
        ),
      ),
    );
  }

  Widget _badge(String label, int n, Color c) {
    if (n == 0) return const SizedBox.shrink();
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: c.withValues(alpha: 0.18),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text('$n $label',
          style: TextStyle(fontSize: 11, color: c, fontWeight: FontWeight.w600)),
    );
  }
}
