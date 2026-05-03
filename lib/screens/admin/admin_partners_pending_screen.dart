import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../config/app_colors.dart';

/// BUG 6d — Admin reviews partners awaiting approval and approves/rejects.
///
/// Lists partners filtered by `approval_status` (default 'pending'). Calls
/// `approve_partner` / `reject_partner` SECURITY DEFINER RPCs. New partners
/// stay invisible to clients until an admin approves them.
class AdminPartnersPendingScreen extends StatefulWidget {
  const AdminPartnersPendingScreen({super.key});

  @override
  State<AdminPartnersPendingScreen> createState() =>
      _AdminPartnersPendingScreenState();
}

class _AdminPartnersPendingScreenState
    extends State<AdminPartnersPendingScreen> {
  static const _statuses = {
    'pending': 'Pendentes',
    'approved': 'Aprovados',
    'rejected': 'Rejeitados',
    null: 'Todos',
  };

  String? _filter = 'pending';
  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _rows = const [];

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
      final r = await Supabase.instance.client.rpc(
        'list_partners_by_status',
        params: {'p_status': _filter},
      );
      if (!mounted) return;
      setState(() {
        _rows = List<Map<String, dynamic>>.from(r as List);
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = e.toString();
      });
    }
  }

  Future<void> _approve(Map<String, dynamic> r) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Aprovar parceiro'),
        content: Text(
            '${r['name']} ficará imediatamente visível aos clientes. Confirmar?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancelar')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.green),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Aprovar'),
          ),
        ],
      ),
    );
    if (confirm != true) return;
    try {
      await Supabase.instance.client.rpc(
        'approve_partner',
        params: {'p_restaurant_id': r['id']},
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${r['name']} aprovado.')),
      );
      _load();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Erro: $e')),
      );
    }
  }

  Future<void> _reject(Map<String, dynamic> r) async {
    final ctrl = TextEditingController();
    final reason = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Rejeitar ${r['name']}'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          maxLines: 3,
          decoration: const InputDecoration(
            labelText: 'Motivo (obrigatório)',
            hintText: 'Ex.: dados incompletos, foto inadequada…',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancelar')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () {
              final txt = ctrl.text.trim();
              if (txt.isEmpty) return;
              Navigator.pop(ctx, txt);
            },
            child: const Text('Rejeitar'),
          ),
        ],
      ),
    );
    if (reason == null || reason.isEmpty) return;
    try {
      await Supabase.instance.client.rpc(
        'reject_partner',
        params: {'p_restaurant_id': r['id'], 'p_reason': reason},
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${r['name']} rejeitado.')),
      );
      _load();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Erro: $e')),
      );
    }
  }

  Color _statusColor(String? s) => switch (s) {
        'approved' => Colors.green.shade700,
        'rejected' => Colors.red.shade700,
        'pending' => Colors.orange.shade700,
        _ => Colors.grey.shade700,
      };

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.surface,
      appBar: AppBar(
        title: const Text('Aprovação de parceiros',
            style: TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: Colors.transparent,
        foregroundColor: Colors.white,
        elevation: 0,
        flexibleSpace: const DecoratedBox(
          decoration: BoxDecoration(gradient: AppColors.headerGradient),
        ),
        actions: [
          IconButton(icon: const Icon(Icons.refresh), onPressed: _load),
        ],
      ),
      body: Column(
        children: [
          // Filter chips
          Padding(
            padding: const EdgeInsets.all(12),
            child: Wrap(
              spacing: 8,
              children: _statuses.entries.map((e) {
                final selected = _filter == e.key;
                return ChoiceChip(
                  label: Text(e.value),
                  selected: selected,
                  onSelected: (_) {
                    setState(() => _filter = e.key);
                    _load();
                  },
                );
              }).toList(),
            ),
          ),
          if (_loading)
            const Expanded(child: Center(child: CircularProgressIndicator()))
          else if (_error != null)
            Expanded(
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text('Erro: $_error',
                          textAlign: TextAlign.center,
                          style: const TextStyle(color: Colors.red)),
                      const SizedBox(height: 12),
                      ElevatedButton(
                          onPressed: _load,
                          child: const Text('Tentar de novo')),
                    ],
                  ),
                ),
              ),
            )
          else if (_rows.isEmpty)
            const Expanded(
              child: Center(
                child: Padding(
                  padding: EdgeInsets.all(32),
                  child: Text('Nenhum parceiro neste estado.'),
                ),
              ),
            )
          else
            Expanded(
              child: RefreshIndicator(
                onRefresh: _load,
                child: ListView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  itemCount: _rows.length,
                  itemBuilder: (ctx, i) => _buildRow(_rows[i]),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildRow(Map<String, dynamic> r) {
    final status = r['approval_status'] as String?;
    final isPending = status == 'pending';
    final reason = r['rejection_reason'] as String?;
    final createdAt =
        DateTime.tryParse(r['created_at'] as String? ?? '')?.toLocal();
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 6),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    r['name'] as String? ?? '(sem nome)',
                    style: const TextStyle(
                        fontWeight: FontWeight.w700, fontSize: 16),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: _statusColor(status).withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    (status ?? '').toUpperCase(),
                    style: TextStyle(
                        fontSize: 11,
                        color: _statusColor(status),
                        fontWeight: FontWeight.w700),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            if ((r['email'] as String?)?.isNotEmpty ?? false)
              Text('📧 ${r['email']}',
                  style: const TextStyle(fontSize: 12)),
            if ((r['phone'] as String?)?.isNotEmpty ?? false)
              Text('☎️ ${r['phone']}',
                  style: const TextStyle(fontSize: 12)),
            if ((r['address'] as String?)?.isNotEmpty ?? false)
              Text('📍 ${r['address']}',
                  style: const TextStyle(fontSize: 12)),
            if (createdAt != null)
              Text(
                'Criado: ${createdAt.day.toString().padLeft(2, '0')}/${createdAt.month.toString().padLeft(2, '0')}/${createdAt.year}',
                style: const TextStyle(
                    fontSize: 11, color: AppColors.textSecondary),
              ),
            if (reason != null && reason.isNotEmpty) ...[
              const SizedBox(height: 6),
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.red.shade50,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text('Motivo rejeição: $reason',
                    style: TextStyle(
                        fontSize: 12, color: Colors.red.shade900)),
              ),
            ],
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                if (status != 'approved')
                  OutlinedButton.icon(
                    icon: const Icon(Icons.check_circle, size: 18),
                    label: const Text('Aprovar'),
                    style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.green.shade700),
                    onPressed: () => _approve(r),
                  ),
                const SizedBox(width: 8),
                if (status != 'rejected')
                  OutlinedButton.icon(
                    icon: const Icon(Icons.cancel_outlined, size: 18),
                    label: Text(isPending ? 'Rejeitar' : 'Rejeitar'),
                    style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.red.shade700),
                    onPressed: () => _reject(r),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
