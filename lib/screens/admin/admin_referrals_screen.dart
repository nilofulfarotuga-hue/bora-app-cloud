import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../services/admin_export_service.dart';

/// T5.1 — Admin referrals: invites + stats + manual code.
class AdminReferralsScreen extends StatefulWidget {
  const AdminReferralsScreen({super.key});
  @override
  State<AdminReferralsScreen> createState() => _AdminReferralsScreenState();
}

class _AdminReferralsScreenState extends State<AdminReferralsScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tab;
  bool _loading = true;
  Map<String, dynamic>? _stats;
  List<Map<String, dynamic>> _invites = const [];
  String _statusFilter = 'all';

  @override
  void initState() {
    super.initState();
    _tab = TabController(length: 2, vsync: this);
    _load();
  }

  @override
  void dispose() {
    _tab.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final s = await Supabase.instance.client
          .rpc('admin_referral_stats', params: {'p_days': 30});
      final inv = await Supabase.instance.client.rpc(
        'admin_list_referral_invites',
        params: {
          'p_status': _statusFilter == 'all' ? null : _statusFilter,
          'p_limit': 200,
          'p_offset': 0,
        },
      );
      if (!mounted) return;
      setState(() {
        _stats = (s as Map).cast<String, dynamic>();
        _invites = (inv as List).cast<Map<String, dynamic>>();
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
    if (_invites.isEmpty) return;
    final headers = ['invite_id', 'created_at', 'status', 'invited_email',
                     'referrer_email', 'code', 'first_order_at'];
    final rows = _invites
        .map((i) => [
              i['invite_id'] ?? '',
              i['created_at'] ?? '',
              i['status'] ?? '',
              i['invited_email'] ?? '',
              i['referrer_email'] ?? '',
              i['code'] ?? '',
              i['first_order_at'] ?? '',
            ])
        .toList();
    final stamp = DateTime.now().toIso8601String().substring(0, 10);
    await AdminExportService.instance.exportCsv(
      filename: 'bora_referrals_$stamp.csv',
      headers: headers,
      rows: rows,
      subject: 'Bora — Referrals $stamp',
    );
  }

  Future<void> _grantManualCode() async {
    final userIdCtrl = TextEditingController();
    final codeCtrl = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Atribuir código manual'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(
            controller: userIdCtrl,
            decoration: const InputDecoration(labelText: 'User ID (UUID)'),
          ),
          TextField(
            controller: codeCtrl,
            decoration: const InputDecoration(labelText: 'Código (≥3 chars)'),
          ),
        ]),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancelar')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Atribuir')),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await Supabase.instance.client.rpc('admin_grant_referral_code',
          params: {
            'p_user_id': userIdCtrl.text.trim(),
            'p_code': codeCtrl.text.trim(),
          });
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Código atribuído: ${codeCtrl.text}')));
      _load();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Erro: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Referrals'),
        bottom: TabBar(
          controller: _tab,
          tabs: const [
            Tab(text: 'Estatísticas'),
            Tab(text: 'Convites'),
          ],
        ),
        actions: [
          IconButton(
              icon: const Icon(Icons.add_card),
              tooltip: 'Atribuir código',
              onPressed: _grantManualCode),
          IconButton(
              icon: const Icon(Icons.download),
              tooltip: 'CSV',
              onPressed: _exportCsv),
          IconButton(icon: const Icon(Icons.refresh), onPressed: _load),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : TabBarView(controller: _tab, children: [
              _buildStats(),
              _buildInvites(),
            ]),
    );
  }

  Widget _buildStats() {
    final s = _stats;
    if (s == null) return const Center(child: Text('Sem stats.'));
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Últimos 30 dias',
                      style: TextStyle(
                          fontSize: 14, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 12),
                  _row('Total convites', '${s['total_invites']}'),
                  _row('Pendentes', '${s['pending']}'),
                  _row('Registaram', '${s['signed_up']}'),
                  _row('1º pedido feito', '${s['completed']}'),
                  const Divider(),
                  _row('Taxa conversão', '${s['conversion_pct']}%',
                      bold: true),
                  _row('Total pago em referrals',
                      '€${((s['total_paid_cents'] as num) / 100).toStringAsFixed(2)}',
                      bold: true),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          const Text('Top referrers',
              style:
                  TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          ...((s['top_referrers'] as List?) ?? const []).map((e) {
            final r = (e as Map).cast<String, dynamic>();
            return Card(
              child: ListTile(
                leading: const Icon(Icons.person),
                title: Text('Code: ${r['code'] ?? '—'}'),
                subtitle: Text(
                    '${r['invites_completed']} completos / ${r['invites_sent']} enviados'),
                trailing: Text(
                    '€${(((r['total_earned_cents'] as num?) ?? 0) / 100).toStringAsFixed(2)}'),
              ),
            );
          }),
        ],
      ),
    );
  }

  Widget _buildInvites() {
    return Column(children: [
      SizedBox(
        height: 50,
        child: ListView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          children: [
            'all',
            'pending',
            'signed_up',
            'first_order_done',
            'expired'
          ].map((s) {
            final isSel = _statusFilter == s;
            return Padding(
              padding: const EdgeInsets.only(right: 8),
              child: FilterChip(
                label: Text(s == 'all' ? 'Todos' : s),
                selected: isSel,
                onSelected: (_) {
                  setState(() => _statusFilter = s);
                  _load();
                },
              ),
            );
          }).toList(),
        ),
      ),
      const Divider(height: 1),
      Expanded(
        child: RefreshIndicator(
          onRefresh: _load,
          child: _invites.isEmpty
              ? ListView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  children: const [
                    SizedBox(height: 80),
                    Center(child: Text('Sem convites neste filtro.')),
                  ],
                )
              : ListView.builder(
                  physics: const AlwaysScrollableScrollPhysics(),
                  itemCount: _invites.length,
                  itemBuilder: (_, i) {
                    final inv = _invites[i];
                    final status = inv['status'] as String? ?? '';
                    return Card(
                      child: ListTile(
                        leading: _statusIcon(status),
                        title: Text(inv['invited_email'] as String? ?? '—'),
                        subtitle: Text(
                            'por ${inv['referrer_email'] ?? '?'} · ${inv['code'] ?? '?'}\n${inv['created_at']}'),
                        isThreeLine: true,
                        trailing: Text(status,
                            style: const TextStyle(fontSize: 11)),
                      ),
                    );
                  },
                ),
        ),
      ),
    ]);
  }

  Widget _statusIcon(String status) {
    switch (status) {
      case 'first_order_done':
        return const Icon(Icons.check_circle, color: Colors.green);
      case 'signed_up':
        return const Icon(Icons.person_add, color: Colors.orange);
      case 'expired':
        return const Icon(Icons.timer_off, color: Colors.grey);
      default:
        return const Icon(Icons.schedule, color: Colors.blue);
    }
  }

  Widget _row(String label, String value, {bool bold = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(label,
                style: TextStyle(
                    fontWeight: bold ? FontWeight.bold : FontWeight.normal)),
            Text(value,
                style: TextStyle(
                    fontWeight: bold ? FontWeight.bold : FontWeight.w600)),
          ]),
    );
  }
}
