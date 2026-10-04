// P1-S11-001 (2026-05-17) — Histórico de push broadcasts admin.
// Chama admin_list_broadcasts (RPC SECURITY DEFINER) e mostra status,
// destinatários (sent_count/failed_count), scheduled_at, completed_at.
//
// 04/10/2026: lê admin_list_broadcasts_v2 (com a nota do porquê) e permite
// cancelar um agendado que ainda não saiu (admin_cancel_broadcast, com
// confirmação). A fila (cron execute-broadcast-queue, a cada 2 min) chama a
// Edge Function execute-broadcast, que marca 'sent'/'failed' com nota.

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../config/app_colors.dart';
import '../../utils/hora_lisboa.dart';
import '../../widgets/bora/bora_screen_app_bar.dart';

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
        'admin_list_broadcasts_v2',
        params: {'p_limit': _limit},
      );
      if (!mounted) return;
      setState(() {
        _rows = ((res as List?) ?? const [])
            .map((e) => Map<String, dynamic>.from(e as Map))
            .toList();
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        debugPrint('[AdminBroadcastsHistory] $e');
        _error = 'Não consegui carregar o histórico.';
        _loading = false;
      });
    }
  }

  Color _statusColor(String status) {
    switch (status) {
      case 'sent':
        return AppColors.success;
      case 'failed':
        return AppColors.error;
      case 'sending':
        return AppColors.warning;
      case 'pending':
      default:
        return AppColors.textSecondary;
    }
  }

  String _fmt(DateTime? dt) =>
      dt == null ? '—' : dataHoraLisboa(dt.toUtc().toIso8601String());

  Future<void> _cancelar(Map<String, dynamic> r) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Cancelar notificação?'),
        content: Text('"${r['title'] ?? ''}" não vai sair. Isto não se desfaz.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Voltar')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Cancelar envio')),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    try {
      final res = await Supabase.instance.client
          .rpc('admin_cancel_broadcast', params: {'p_id': r['id']});
      if (!mounted) return;
      final m = (res is Map) ? res : const {};
      messenger.showSnackBar(SnackBar(
          content: Text(m['ok'] == true
              ? 'Cancelada.'
              : (m['erro']?.toString() ?? 'Não consegui cancelar.'))));
      _load();
    } catch (e) {
      debugPrint('[AdminBroadcastsHistory] cancelar: $e');
      if (!mounted) return;
      messenger.showSnackBar(
          const SnackBar(content: Text('Não consegui cancelar.')));
    }
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
      backgroundColor: AppColors.background,
      appBar: BoraScreenAppBar(
        title: 'Histórico de broadcasts',
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
                      style: const TextStyle(color: AppColors.error),
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
                        separatorBuilder: (_, __) =>
                            const Divider(height: 1, color: AppColors.divider),
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
                          final nota = (r['status_note'] as String?) ?? '';
                          final pessoas = r['pessoas_alvo'];

                          return ListTile(
                            isThreeLine: true,
                            leading: CircleAvatar(
                              backgroundColor: _statusColor(status),
                              child: const Icon(Icons.campaign,
                                  color: Colors.white, size: 20),
                            ),
                            trailing: status == 'pending'
                                ? IconButton(
                                    tooltip: 'Cancelar este envio',
                                    icon: const Icon(Icons.cancel_outlined,
                                        color: AppColors.error),
                                    onPressed: () => _cancelar(r),
                                  )
                                : null,
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
                                            color: AppColors.textSecondary),
                                      ),
                                    Text(
                                      'Agendado: ${_fmt(scheduledAt)}',
                                      style: const TextStyle(
                                          fontSize: 11,
                                          color: AppColors.textSecondary),
                                    ),
                                    if (completedAt != null)
                                      Text(
                                        'Concluído: ${_fmt(completedAt)}',
                                        style: const TextStyle(
                                            fontSize: 11,
                                            color: AppColors.textSecondary),
                                      ),
                                    if (pessoas != null)
                                      Text(
                                        'Pessoas: $pessoas',
                                        style: const TextStyle(
                                            fontSize: 11,
                                            color: AppColors.textSecondary),
                                      ),
                                  ],
                                ),
                                if (nota.isNotEmpty)
                                  Text(
                                    nota,
                                    style: const TextStyle(
                                        fontSize: 11,
                                        fontStyle: FontStyle.italic,
                                        color: AppColors.textSecondary),
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
