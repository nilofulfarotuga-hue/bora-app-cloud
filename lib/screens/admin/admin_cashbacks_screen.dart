import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../config/app_colors.dart';
import '../../config/app_spacing.dart';
import '../../widgets/bora/bora_screen_app_bar.dart';
import '../../services/admin_export_service.dart';
import 'admin_platform_settings_screen.dart';

/// T5.2 — Admin cashbacks: lista pagamentos cashback + total período.
class AdminCashbacksScreen extends StatefulWidget {
  const AdminCashbacksScreen({super.key});
  @override
  State<AdminCashbacksScreen> createState() => _AdminCashbacksScreenState();
}

class _AdminCashbacksScreenState extends State<AdminCashbacksScreen> {
  bool _loading = true;
  Map<String, dynamic>? _data;
  int _periodDays = 30;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final from = DateTime.now()
          .subtract(Duration(days: _periodDays))
          .toUtc()
          .toIso8601String();
      final to = DateTime.now().toUtc().toIso8601String();
      final res = await Supabase.instance.client
          .rpc('admin_list_cashbacks', params: {
        'p_from': from,
        'p_to': to,
        'p_limit': 500,
      });
      if (!mounted) return;
      setState(() {
        _data = (res as Map).cast<String, dynamic>();
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Erro: $e')));
    }
  }

  Future<void> _exportCsv() async {
    final txs = (_data?['transactions'] as List?) ?? const [];
    if (txs.isEmpty) return;
    final headers = ['tx_id', 'created_at', 'user_email', 'amount_cents',
                     'order_id', 'reason'];
    final rows = txs.map((e) {
      final t = (e as Map).cast<String, dynamic>();
      return [
        t['tx_id'] ?? '', t['created_at'] ?? '', t['user_email'] ?? '',
        t['amount_cents'] ?? '', t['order_id'] ?? '', t['reason'] ?? '',
      ];
    }).toList();
    final stamp = DateTime.now().toIso8601String().substring(0, 10);
    await AdminExportService.instance.exportCsv(
      filename: 'bora_cashbacks_$stamp.csv',
      headers: headers,
      rows: rows,
      subject: 'Bora — Cashbacks $stamp',
    );
  }

  @override
  Widget build(BuildContext context) {
    final txs = (_data?['transactions'] as List?) ?? const [];
    final totalCents = (_data?['total_cents'] as num?)?.toInt() ?? 0;
    final count = (_data?['count'] as num?)?.toInt() ?? 0;

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: BoraScreenAppBar(
        title: 'Cashbacks',
        actions: [
          IconButton(
              icon: const Icon(Icons.tune),
              tooltip: 'Editar % cashback',
              onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                      builder: (_) =>
                          const AdminPlatformSettingsScreen()))),
          IconButton(
              icon: const Icon(Icons.download),
              tooltip: 'CSV',
              onPressed: _exportCsv),
          IconButton(icon: const Icon(Icons.refresh), onPressed: _load),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.all(16),
                children: [
                  SegmentedButton<int>(
                    segments: const [
                      ButtonSegment(value: 7, label: Text('7d')),
                      ButtonSegment(value: 30, label: Text('30d')),
                      ButtonSegment(value: 90, label: Text('90d')),
                    ],
                    selected: {_periodDays},
                    onSelectionChanged: (s) {
                      setState(() => _periodDays = s.first);
                      _load();
                    },
                  ),
                  const SizedBox(height: 16),
                  Card(
                    color: AppColors.primaryWash,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(Radii.lg),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('Resumo',
                              style: TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.bold)),
                          const SizedBox(height: 8),
                          Text(
                              'Total cashback pago: €${(totalCents / 100).toStringAsFixed(2)}',
                              style: const TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold)),
                          Text('$count transactions'),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  if (txs.isEmpty)
                    const Padding(
                      padding: EdgeInsets.all(24),
                      child: Center(
                          child: Text('Sem cashbacks no período.',
                              style: TextStyle(color: AppColors.textSecondary))),
                    ),
                  ...txs.map((e) {
                    final t = (e as Map).cast<String, dynamic>();
                    final cents = (t['amount_cents'] as num?)?.toInt() ?? 0;
                    return Card(
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(Radii.lg),
                      ),
                      child: ListTile(
                        leading: const Icon(Icons.celebration,
                            color: AppColors.success),
                        title: Text(t['user_email'] as String? ?? '—'),
                        subtitle: Text(
                            '${t['created_at']?.toString().substring(0, 10) ?? ''} · order ${(t['order_id'] as String? ?? '').isNotEmpty ? (t['order_id'] as String).substring(0, 8) : '—'}'),
                        trailing: Text(
                            '€${(cents / 100).toStringAsFixed(2)}',
                            style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                color: AppColors.success)),
                      ),
                    );
                  }),
                ],
              ),
            ),
    );
  }
}
