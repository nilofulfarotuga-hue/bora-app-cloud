// P1-S11-001 (2026-05-17) — Histórico de push broadcasts admin.
// Chama admin_list_broadcasts (RPC SECURITY DEFINER) e mostra status,
// destinatários (sent_count/failed_count), scheduled_at, completed_at.
//
// admin_create_broadcast persiste rows aqui com status='pending'. Edge Fn
// broadcast-push (não implementada ainda — bloqueada por Firebase setup #1)
// consome status='pending' e marca 'sent'/'failed'.

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class AdminBroadcastsHistoryScreen extends StatefulWidget {
  const AdminBroadcastsHistoryScreen({super.key});

  @override
  State<AdminBroadcastsHistoryScreen> createState() =>
      _AdminBroadcastsHistoryScreenState();
}

class _AdminBroadcastsHistoryScreenState
    extends State<AdminBroadcastsHistoryScreen> {
  List<Map<String, dynamic>> _rows = const [];
  bool _loading = true;
  String? _error;
  int _limit = 50;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final res = await Supabase.instance.client.rpc(
        'admin_list_broadcasts',
        params: {'p_limit': _limit},
      );
      if (!mounted) return;
      setState(() {
        _rows = (res as List).cast<Map<String, dynamic>>();
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  Color _statusColor(String status) {
    switch (status) {
      case 'sent':
        return Colors.green.shade700;
      case 'failed':
        return Colors.red.shade700;
      case 'sending':
        return Colors.amber.shade700;
      case 'pending':
      default:
        return Colors.blueGrey;
    }
  }

  String _fmt(DateTime? dt) {
    if (dt == null) return '—';
    final d = dt.toLocal();
    return '${d.day.toString().padLeft(2, '0')}/'
        '${d.month.toString().padLeft(2, '0')}/'
        '${d.year} '
        '${d.hour.toString().padLeft(2, '0')}:'
        '${d.minute.toString().padLeft(2, '0')}';
  }

  String _segmentLabel(String s) {
    switch (s) {
      case 'all':
        return 'Todos';
      case 'clients':
        return 'Clientes';
      case 'drivers':
        return 'Drivers';
      case 'partners':
        return 'Parceiros';
      default:
        return s;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Histórico de broadcasts'),
        actions: [
          PopupMenuButton<int>(
            tooltip: 'Limite',
            initialValue: _limit,
            onSelected: (v) {
              setState(() => _limit = v);
              _load();
            },
            itemBuilder: (_) => const [
              PopupMenuItem(value: 20, child: Text('20')),
              PopupMenuItem(value: 50, child: Text('50')),
              PopupMenuItem(value: 100, child: Text('100')),
              PopupMenuItem(value: 200, child: Text('200')),
            ],
            icon: const Icon(Icons.format_list_numbered),
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loading ? null : _load,
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Text(
                      'Erro a carregar: $_error',
                      style: const TextStyle(color: Colors.red),
                    ),
                  ),
                )
              : _rows.isEmpty
                  ? const Center(child: Text('Sem broadcasts registados.'))
                  : RefreshIndicator(
                      onRefresh: _load,
                      child: ListView.separated(
                        padding: const EdgeInsets.all(12),
                        itemCount: _rows.length,
                        separatorBuilder: (_, __) => const Divider(height: 1),
                        itemBuilder: (context, i) {
                          final r = _rows[i];
                          final status = (r['status'] as String?) ?? 'pending';
                          final segment = (r['segment'] as String?) ?? '?';
                          final title = (r['title'] as String?) ?? '';
                          final body = (r['body'] as String?) ?? '';
                          final sentCount = (r['sent_count'] as int?) ?? 0;
                          final failedCount = (r['failed_count'] as int?) ?? 0;
                          final scheduledAt =
                              DateTime.tryParse(r['scheduled_at'] as String? ?? '');
                          final completedAt =
                              DateTime.tryParse(r['completed_at'] as String? ?? '');

                          return ListTile(
                            isThreeLine: true,
                            leading: CircleAvatar(
                              backgroundColor: _statusColor(status),
                              child: const Icon(Icons.campaign,
                                  color: Colors.white, size: 20),
                            ),
                            title: Text(
                              title,
                              style:
                                  const TextStyle(fontWeight: FontWeight.bold),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            subtitle: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  body,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(fontSize: 12),
                                ),
                                const SizedBox(height: 2),
                                Wrap(
                                  spacing: 8,
                                  runSpacing: 2,
                                  children: [
                                    Chip(
                                      label: Text(
                                        _segmentLabel(segment),
                                        style: const TextStyle(fontSize: 11),
                                      ),
                                      visualDensity: VisualDensity.compact,
                                      padding: EdgeInsets.zero,
                                    ),
                                    Chip(
                                      label: Text(
                                        status.toUpperCase(),
                                        style: TextStyle(
                                            fontSize: 11,
                                            color: _statusColor(status)),
                                      ),
                                      backgroundColor:
                                          _statusColor(status).withValues(alpha: 0.1),
                                      visualDensity: VisualDensity.compact,
                                      padding: EdgeInsets.zero,
                                    ),
                                    if (status == 'sent' || status == 'failed')
                                      Text(
                                        '✓ $sentCount · ✗ $failedCount',
                                        style: const TextStyle(
                                            fontSize: 11,
                                            color: Colors.black54),
                                      ),
                                    Text(
                                      'Agendado: ${_fmt(scheduledAt)}',
                                      style: const TextStyle(
                                          fontSize: 11, color: Colors.black54),
                                    ),
                                    if (completedAt != null)
                                      Text(
                                        'Concluído: ${_fmt(completedAt)}',
                                        style: const TextStyle(
                                            fontSize: 11,
                                            color: Colors.black54),
                                      ),
                                  ],
                                ),
                              ],
                            ),
                          );
                        },
                      ),
                    ),
    );
  }
}
