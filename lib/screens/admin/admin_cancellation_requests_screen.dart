import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../config/app_colors.dart';
import '../../widgets/bora/bora_screen_app_bar.dart';

class AdminCancellationRequestsScreen extends StatefulWidget {
  const AdminCancellationRequestsScreen({super.key});
  @override
  State<AdminCancellationRequestsScreen> createState() => _S();
}

class _S extends State<AdminCancellationRequestsScreen> {
  String _status = 'pending';
  List<Map<String, dynamic>> _rows = const [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() { _loading = true; _error = null; });
    try {
      final res = await Supabase.instance.client.rpc(
        'admin_list_cancellation_requests',
        params: {'p_status': _status, 'p_limit': 200, 'p_offset': 0},
      );
      final list = ((res as List?) ?? [])
          .map((e) => (e as Map).cast<String, dynamic>()).toList();
      if (mounted) setState(() => _rows = list);
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _approve(Map<String, dynamic> r) async {
    String method = 'wallet';
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => StatefulBuilder(
        builder: (ctx, set) => AlertDialog(
          title: const Text('Aprovar cancelamento'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Order: ${r['order_id']}'),
              Text('Pedido por: ${r['requester_role']}'),
              const SizedBox(height: 8),
              const Text('Método de reembolso:'),
              RadioListTile(value: 'stripe', groupValue: method,
                  onChanged: (v) => set(() => method = v!),
                  title: const Text('Cartão (Stripe, 5-10 dias)')),
              RadioListTile(value: 'wallet', groupValue: method,
                  onChanged: (v) => set(() => method = v!),
                  title: const Text('Wallet (instantâneo)')),
              RadioListTile(value: 'none', groupValue: method,
                  onChanged: (v) => set(() => method = v!),
                  title: const Text('Sem reembolso')),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Aprovar')),
          ],
        ),
      ),
    );
    if (ok != true) return;
    try {
      // 1) Marca aprovação na DB (RPC + audit)
      await Supabase.instance.client.rpc('admin_approve_cancellation', params: {
        'p_request_id': r['id'], 'p_refund_method': method,
      });
      // 2) Executa o refund via Edge Function (Stripe ou wallet split)
      final exec = await Supabase.instance.client.functions.invoke(
        'execute-cancellation',
        body: {'request_id': r['id']},
      );
      if (exec.status >= 400) {
        throw Exception('execute-cancellation falhou: ${exec.data}');
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Aprovado e executado: ${exec.data}')),
        );
      }
      await _load();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erro: $e')));
    }
  }

  Future<void> _reject(Map<String, dynamic> r) async {
    final ctrl = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Rejeitar cancelamento'),
        content: TextField(controller: ctrl,
          decoration: const InputDecoration(labelText: 'Motivo (3+ chars)')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Voltar')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Rejeitar')),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await Supabase.instance.client.rpc('admin_reject_cancellation', params: {
        'p_request_id': r['id'], 'p_reason': ctrl.text.trim(),
      });
      if (mounted) await _load();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Erro: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: const BoraScreenAppBar(title: 'Pedidos de Cancelamento'),
      body: Column(
        children: [
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.all(8),
            child: Row(children: [
              for (final s in const ['pending','approved','rejected','withdrawn'])
                Padding(
                  padding: const EdgeInsets.only(right: 4),
                  child: ChoiceChip(label: Text(s), selected: _status==s,
                    onSelected: (_) { setState(() => _status = s); _load(); }),
                ),
            ]),
          ),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _error != null
                    ? Center(child: Text(_error!, style: const TextStyle(color: AppColors.error)))
                    : RefreshIndicator(
                        onRefresh: _load,
                        child: _rows.isEmpty
                            ? ListView(children: const [
                                SizedBox(height: 60),
                                Center(child: Text('Sem pedidos.')),
                              ])
                            : ListView.separated(
                                itemCount: _rows.length,
                                separatorBuilder: (_, __) =>
                                    const Divider(height: 1, color: AppColors.divider),
                                itemBuilder: (_, i) {
                                  final r = _rows[i];
                                  final created = DateTime.parse(r['created_at'] as String).toLocal();
                                  final pending = r['status'] == 'pending';
                                  final stale = pending &&
                                      DateTime.now().difference(created).inMinutes > 30;
                                  return ListTile(
                                    leading: CircleAvatar(
                                      backgroundColor: stale ? AppColors.warning : Colors.grey.shade300,
                                      child: Icon(
                                        pending ? Icons.access_time : Icons.check,
                                        color: stale ? Colors.white : Colors.black54,
                                      ),
                                    ),
                                    title: Text('${r['requester_role']} → ${r['order_id']}'),
                                    subtitle: Text(
                                      '${r['reason']}\n${created.toIso8601String()}',
                                    ),
                                    isThreeLine: true,
                                    trailing: pending
                                        ? Wrap(spacing: 4, children: [
                                            IconButton(
                                              icon: const Icon(Icons.check, color: AppColors.success),
                                              onPressed: () => _approve(r),
                                            ),
                                            IconButton(
                                              icon: const Icon(Icons.close, color: AppColors.error),
                                              onPressed: () => _reject(r),
                                            ),
                                          ])
                                        : Text(r['status']!),
                                  );
                                },
                              ),
                      ),
          ),
        ],
      ),
    );
  }
}
