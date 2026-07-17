// BLOCO A (2026-05-18) — Inbox de notificações admin.
//
// Lê da tabela admin_notifications (criada na migration
// 20260518000100_admin_notifications_infra.sql). Suporta:
//   • Filtro por severity (all/critical/high/medium/low)
//   • Filtro por event_type
//   • Marcar como lido (1-tap)
//   • Arquivar (swipe)
//   • Contador de não-lidos
//   • Pull-to-refresh
//   • Realtime para notificações novas
//
// PT-BR (Regra 6).

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../config/app_colors.dart';

class AdminNotificationsInboxScreen extends StatefulWidget {
  const AdminNotificationsInboxScreen({super.key});

  @override
  State<AdminNotificationsInboxScreen> createState() =>
      _AdminNotificationsInboxScreenState();
}

class _AdminNotificationsInboxScreenState
    extends State<AdminNotificationsInboxScreen> {
  final _supabase = Supabase.instance.client;
  List<Map<String, dynamic>> _rows = const [];
  bool _loading = true;
  String? _error;
  String _severityFilter = 'all'; // all/critical/high/medium/low
  bool _hideArchived = true;
  RealtimeChannel? _channel;

  static const _severityColors = {
    'critical': Colors.red,
    'high': Colors.orange,
    'medium': Colors.amber,
    'low': Colors.blueGrey,
  };

  @override
  void initState() {
    super.initState();
    _load();
    _subscribeRealtime();
  }

  @override
  void dispose() {
    if (_channel != null) _supabase.removeChannel(_channel!);
    super.dispose();
  }

  void _subscribeRealtime() {
    _channel = _supabase.channel('admin_notifications_inbox');
    _channel!
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'admin_notifications',
          callback: (_) {
            if (mounted) _load();
          },
        )
        .subscribe();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      var query = _supabase
          .from('admin_notifications')
          .select('id, created_at, event_type, severity, '
              'entity_type, entity_id, summary, payload, deep_link, '
              'read_at, archived_at');
      if (_severityFilter != 'all') {
        query = query.eq('severity', _severityFilter);
      }
      if (_hideArchived) {
        query = query.isFilter('archived_at', null);
      }
      final res = await query.order('created_at', ascending: false).limit(200);
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

  Future<void> _markRead(Map<String, dynamic> row) async {
    final id = row['id']?.toString();
    if (id == null || row['read_at'] != null) return;
    try {
      await _supabase.from('admin_notifications').update({
        'read_at': DateTime.now().toUtc().toIso8601String(),
      }).eq('id', id);
      if (mounted) _load();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Erro: $e'), backgroundColor: Colors.red),
      );
    }
  }

  /// PARTE A (2026-07-17) — tocar numa notificação marca-a lida E navega para
  /// o `deep_link` (ex.: /admin/drivers/approval). Antes o tap só marcava lida.
  Future<void> _openRow(Map<String, dynamic> row) async {
    await _markRead(row);
    if (!mounted) return;
    final link = row['deep_link']?.toString();
    if (link != null && link.startsWith('/admin')) {
      Navigator.of(context).pushNamed(link);
    }
  }

  Future<void> _archive(Map<String, dynamic> row) async {
    final id = row['id']?.toString();
    if (id == null) return;
    try {
      await _supabase.from('admin_notifications').update({
        'archived_at': DateTime.now().toUtc().toIso8601String(),
      }).eq('id', id);
      if (mounted) _load();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Erro: $e'), backgroundColor: Colors.red),
      );
    }
  }

  Future<void> _markAllRead() async {
    try {
      await _supabase
          .from('admin_notifications')
          .update({
            'read_at': DateTime.now().toUtc().toIso8601String(),
          })
          .isFilter('read_at', null);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('Todas marcadas como lidas.'),
            backgroundColor: AppColors.primary));
        _load();
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Erro: $e'), backgroundColor: Colors.red),
      );
    }
  }

  String _fmtDateTime(String? iso) {
    if (iso == null) return '—';
    final d = DateTime.tryParse(iso)?.toLocal();
    if (d == null) return iso;
    final now = DateTime.now();
    final diff = now.difference(d);
    if (diff.inMinutes < 1) return 'agora';
    if (diff.inHours < 1) return '${diff.inMinutes} min';
    if (diff.inDays < 1) return '${diff.inHours}h';
    if (diff.inDays < 7) return '${diff.inDays}d';
    return '${d.day.toString().padLeft(2, '0')}/'
        '${d.month.toString().padLeft(2, '0')}/${d.year}';
  }

  Color _colorFor(String severity) =>
      _severityColors[severity] ?? Colors.blueGrey;

  IconData _iconFor(String eventType) {
    switch (eventType) {
      case 'order_refund_high':
      case 'order_cancel_in_flight':
        return Icons.money_off;
      case 'wallet_debt_high':
        return Icons.warning_amber;
      case 'reservation_no_show':
        return Icons.event_busy;
      case 'skill_suggestion_critical':
        return Icons.psychology;
      case 'complaint_high':
        return Icons.report_problem;
      case 'order_orphan':
        return Icons.shopping_bag;
      case 'driver_phantom':
        return Icons.two_wheeler;
      case 'stripe_failures':
        return Icons.credit_card_off;
      default:
        return Icons.notifications;
    }
  }

  String _labelFor(String eventType) {
    switch (eventType) {
      case 'order_refund_high':
        return 'Reembolso alto';
      case 'dispatch_ttl_auto_cancel':
        return 'Cancelado por TTL de dispatch';
      case 'order_cancel_in_flight':
        return 'Cancelado em rota';
      case 'wallet_debt_high':
        return 'Dívida alta';
      case 'reservation_no_show':
        return 'No-show reserva';
      case 'skill_suggestion_critical':
        return 'Skill crítica';
      case 'complaint_high':
        return 'Reclamação grave';
      case 'order_orphan':
        return 'Pedido órfão';
      case 'driver_phantom':
        return 'Entregador fantasma';
      case 'stripe_failures':
        return '3+ falhas Stripe';
      default:
        return eventType;
    }
  }

  @override
  Widget build(BuildContext context) {
    final unreadCount = _rows.where((r) => r['read_at'] == null).length;
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        elevation: 0,
        flexibleSpace: const DecoratedBox(
          decoration: BoxDecoration(gradient: AppColors.headerGradient),
        ),
        title: Row(
          children: [
            const Text('Notificações',
                style: TextStyle(fontWeight: FontWeight.bold)),
            if (unreadCount > 0) ...[
              const SizedBox(width: 8),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.red,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text('$unreadCount',
                    style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 12)),
              ),
            ],
          ],
        ),
        actions: [
          PopupMenuButton<String>(
            tooltip: 'Filtrar severidade',
            initialValue: _severityFilter,
            onSelected: (v) {
              setState(() => _severityFilter = v);
              _load();
            },
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'all', child: Text('Todas')),
              PopupMenuItem(value: 'critical', child: Text('Crítica')),
              PopupMenuItem(value: 'high', child: Text('Alta')),
              PopupMenuItem(value: 'medium', child: Text('Média')),
              PopupMenuItem(value: 'low', child: Text('Baixa')),
            ],
            icon: const Icon(Icons.filter_list),
          ),
          IconButton(
            tooltip: 'Marcar todas como lidas',
            icon: const Icon(Icons.done_all),
            onPressed: unreadCount > 0 ? _markAllRead : null,
          ),
          IconButton(
            tooltip: _hideArchived ? 'Mostrar arquivadas' : 'Esconder arquivadas',
            icon: Icon(_hideArchived ? Icons.archive_outlined : Icons.archive),
            onPressed: () {
              setState(() => _hideArchived = !_hideArchived);
              _load();
            },
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loading ? null : _load,
          ),
        ],
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline, size: 48, color: AppColors.error),
              const SizedBox(height: 12),
              Text(_error!, textAlign: TextAlign.center),
              const SizedBox(height: 12),
              ElevatedButton(
                onPressed: _load,
                child: const Text('Tentar novamente'),
              ),
            ],
          ),
        ),
      );
    }
    if (_rows.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.notifications_none, size: 64, color: Colors.black26),
              SizedBox(height: 12),
              Text(
                'Nenhuma notificação no filtro atual.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.black54),
              ),
            ],
          ),
        ),
      );
    }
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.builder(
        padding: const EdgeInsets.symmetric(vertical: 4),
        itemCount: _rows.length,
        itemBuilder: (_, i) => _buildRow(_rows[i]),
      ),
    );
  }

  Widget _buildRow(Map<String, dynamic> r) {
    final severity = (r['severity'] as String?) ?? 'medium';
    final eventType = (r['event_type'] as String?) ?? 'unknown';
    final summary = (r['summary'] as String?) ?? '';
    final isRead = r['read_at'] != null;
    final isArchived = r['archived_at'] != null;
    final color = _colorFor(severity);

    return Dismissible(
      key: ValueKey(r['id']),
      direction: DismissDirection.endToStart,
      background: Container(
        color: Colors.grey.shade400,
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.symmetric(horizontal: 24),
        child: const Icon(Icons.archive, color: Colors.white),
      ),
      confirmDismiss: (_) async => !isArchived,
      onDismissed: (_) => _archive(r),
      child: Card(
        margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 3),
        color: isRead ? null : color.withValues(alpha: 0.05),
        child: ListTile(
          dense: true,
          leading: CircleAvatar(
            radius: 16,
            backgroundColor: color.withValues(alpha: 0.15),
            child: Icon(_iconFor(eventType), color: color, size: 18),
          ),
          title: Row(
            children: [
              Expanded(
                child: Text(
                  summary,
                  style: TextStyle(
                    fontWeight: isRead ? FontWeight.normal : FontWeight.bold,
                    fontSize: 13,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (!isRead)
                Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    color: color,
                    shape: BoxShape.circle,
                  ),
                ),
            ],
          ),
          subtitle: Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 6, vertical: 1),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(3),
                ),
                child: Text(
                  '${_labelFor(eventType)} · ${severity.toUpperCase()}',
                  style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                      color: color),
                ),
              ),
              const SizedBox(width: 6),
              Text(
                _fmtDateTime(r['created_at'] as String?),
                style: const TextStyle(fontSize: 11, color: Colors.black54),
              ),
              if (isArchived) ...[
                const SizedBox(width: 6),
                const Text('· arquivada',
                    style:
                        TextStyle(fontSize: 10, color: Colors.black38)),
              ],
            ],
          ),
          onTap: () => _openRow(r),
        ),
      ),
    );
  }
}
