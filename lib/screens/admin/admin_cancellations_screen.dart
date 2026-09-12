import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../config/app_colors.dart';
import '../../widgets/bora/bora_screen_app_bar.dart';

/// Bloco 4 — Histórico de cancelamentos (PT-BR). Lista cancellation_requests +
/// orders, com filtros (estágio/status/falhados) e reprocessamento idempotente
/// de reembolsos falhados via Edge Function reprocess-refund.
class AdminCancellationsScreen extends StatefulWidget {
  const AdminCancellationsScreen({super.key});
  @override
  State<AdminCancellationsScreen> createState() =>
      _AdminCancellationsScreenState();
}

class _AdminCancellationsScreenState extends State<AdminCancellationsScreen> {
  List<Map<String, dynamic>> _rows = [];
  bool _loading = true;
  String? _error;
  String? _stageFilter;
  String? _statusFilter;
  bool _failedOnly = false;
  final _busy = <String>{};

  static const _stageLabels = {
    'grace': 'E1 · Cortesia (grátis)',
    'before_dispatch': 'E2 · Antes do dispatch',
    'after_accept': 'E3 · Após estafeta aceitar',
    'after_pickup': 'E4 · Após pickup',
  };

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
      final res = await Supabase.instance.client
          .rpc('admin_list_cancellations', params: {
        'p_stage': _stageFilter,
        'p_status': _statusFilter,
        'p_failed_only': _failedOnly,
      });
      final list = ((res as List?) ?? const [])
          .map((e) => (e as Map).cast<String, dynamic>())
          .toList();
      if (mounted) setState(() => _rows = list);
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _reprocess(String orderId) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Reprocessar reembolso'),
        content: Text(
            'Reprocessar o reembolso do pedido $orderId?\n\n'
            'A operação é idempotente — não credita duas vezes.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Não')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Reprocessar')),
        ],
      ),
    );
    if (ok != true) return;
    setState(() => _busy.add(orderId));
    try {
      final res = await Supabase.instance.client.functions
          .invoke('reprocess-refund', body: {'order_id': orderId});
      final data = res.data;
      final msg = (data is Map && data['idempotent'] == true)
          ? 'Nada a reprocessar (já tratado).'
          : (data is Map && data['ok'] == true)
              ? 'Reembolso reprocessado: ${data['refund_status']}.'
              : 'Falha ao reprocessar.';
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(msg)));
      }
      await _load();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Erro: $e')));
      }
    } finally {
      if (mounted) setState(() => _busy.remove(orderId));
    }
  }

  String _euros(dynamic cents) {
    final c = (cents is num) ? cents : num.tryParse('$cents') ?? 0;
    return '€${(c / 100).toStringAsFixed(2)}';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: const BoraScreenAppBar(title: 'Cancelamentos'),
      body: Column(
        children: [
          _filtersBar(),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _error != null
                    ? Center(
                        child: Text(_error!,
                            style: const TextStyle(color: AppColors.error)))
                    : RefreshIndicator(
                        onRefresh: _load,
                        child: _rows.isEmpty
                            ? ListView(children: const [
                                SizedBox(height: 80),
                                Center(child: Text('Sem cancelamentos.')),
                              ])
                            : ListView.separated(
                                itemCount: _rows.length,
                                separatorBuilder: (_, __) =>
                                    const Divider(height: 1),
                                itemBuilder: (_, i) => _row(_rows[i]),
                              ),
                      ),
          ),
        ],
      ),
    );
  }

  Widget _filtersBar() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Wrap(
        spacing: 8,
        runSpacing: 4,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          DropdownButton<String?>(
            value: _stageFilter,
            hint: const Text('Estágio'),
            items: [
              const DropdownMenuItem(
                  value: null, child: Text('Todos os estágios')),
              ..._stageLabels.entries.map((e) =>
                  DropdownMenuItem(value: e.key, child: Text(e.value))),
            ],
            onChanged: (v) {
              setState(() => _stageFilter = v);
              _load();
            },
          ),
          DropdownButton<String?>(
            value: _statusFilter,
            hint: const Text('Status'),
            items: const [
              DropdownMenuItem(value: null, child: Text('Todos os status')),
              DropdownMenuItem(
                  value: 'approved', child: Text('Aprovado (automático)')),
              DropdownMenuItem(
                  value: 'pending', child: Text('Pendente (manual)')),
              DropdownMenuItem(value: 'rejected', child: Text('Rejeitado')),
            ],
            onChanged: (v) {
              setState(() => _statusFilter = v);
              _load();
            },
          ),
          FilterChip(
            label: const Text('Reembolsos falhados'),
            selected: _failedOnly,
            onSelected: (v) {
              setState(() => _failedOnly = v);
              _load();
            },
          ),
        ],
      ),
    );
  }

  Widget _row(Map<String, dynamic> r) {
    final orderId = '${r['order_id']}';
    final stage = r['cancel_stage'] as String?;
    final stageLabel = stage != null
        ? (_stageLabels[stage] ?? stage)
        : (r['auto_resolved'] == true ? 'Automático' : 'Manual');
    final refundStatus = r['order_refund_status'] as String?;
    final isFailed = refundStatus == 'failed';
    final auto = r['auto_resolved'] == true;
    final shortId = orderId.length > 8 ? orderId.substring(0, 8) : orderId;
    return ListTile(
      title: Text('#$shortId · $stageLabel'),
      subtitle: Text(
        'Taxa ${_euros(r['fee_cents'])} · Reembolso ${_euros(r['refund_cents'])} '
        '(${r['refund_method'] ?? '—'})\n'
        'Status: ${r['status']} · ${auto ? 'automático' : 'manual'}'
        '${refundStatus != null ? ' · reembolso: $refundStatus' : ''}\n'
        '${r['created_at'] ?? ''}',
      ),
      isThreeLine: true,
      trailing: isFailed
          ? (_busy.contains(orderId)
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2))
              : TextButton(
                  onPressed: () => _reprocess(orderId),
                  child: const Text('Reprocessar'),
                ))
          : null,
    );
  }
}
