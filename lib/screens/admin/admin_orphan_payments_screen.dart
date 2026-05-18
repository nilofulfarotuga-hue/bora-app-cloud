import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../config/app_colors.dart';
import '../../services/auth_admin_service.dart';

/// Painel admin para órfãos de pagamento (BUG 1 / Fase 2 — 2026-04-30).
///
/// Mostra:
///   • payment_drafts (pending/expired) — Stripe PI sem order ainda
///   • orders.payment_status = 'cancelled_no_charge' — orders cuja PI nunca
///     teve charge real (BUG 3)
///
/// Fonte: RPC `admin_list_orphans()` (SECURITY DEFINER, service_role only).
/// O cleanup automático de drafts é feito pelo pg_cron `cleanup_payment_drafts`
/// a cada 5 min — esta UI é para inspecção e replay manual.
class AdminOrphanPaymentsScreen extends StatefulWidget {
  const AdminOrphanPaymentsScreen({super.key});

  @override
  State<AdminOrphanPaymentsScreen> createState() => _AdminOrphanPaymentsScreenState();
}

class _AdminOrphanPaymentsScreenState extends State<AdminOrphanPaymentsScreen> {
  late Future<List<Map<String, dynamic>>> _future;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<List<Map<String, dynamic>>> _load() async {
    final res = await Supabase.instance.client.rpc('admin_list_orphans');
    if (res is List) return res.map((e) => Map<String, dynamic>.from(e as Map)).toList();
    return const [];
  }

  Future<void> _refresh() async {
    setState(() => _future = _load());
    await _future;
  }

  Future<void> _deleteDraft(String draftId) async {
    try {
      await Supabase.instance.client.from('payment_drafts').delete().eq('id', draftId);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Draft apagado.')),
        );
      }
      await _refresh();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erro ao excluir draft: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!AuthAdminService.isAdmin()) {
      return Scaffold(
        appBar: AppBar(title: const Text('Órfãos de pagamento')),
        body: const Center(child: Text('Acesso negado.')),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Órfãos de pagamento'),
        actions: [
          IconButton(icon: const Icon(Icons.refresh), onPressed: _refresh),
        ],
      ),
      body: FutureBuilder<List<Map<String, dynamic>>>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  'Erro a carregar: ${snapshot.error}\n\n'
                  'Verifica que admin_list_orphans existe e tens role=admin.',
                  textAlign: TextAlign.center,
                ),
              ),
            );
          }
          final rows = snapshot.data ?? const [];
          if (rows.isEmpty) {
            return RefreshIndicator(
              onRefresh: _refresh,
              child: ListView(
                children: const [
                  SizedBox(height: 80),
                  Center(child: Icon(Icons.check_circle_outline, size: 64, color: Colors.green)),
                  SizedBox(height: 16),
                  Center(child: Text('Sem órfãos. Tudo limpo.', style: TextStyle(fontSize: 16))),
                ],
              ),
            );
          }

          return RefreshIndicator(
            onRefresh: _refresh,
            child: ListView.separated(
              padding: const EdgeInsets.all(12),
              itemCount: rows.length,
              separatorBuilder: (_, __) => const SizedBox(height: 8),
              itemBuilder: (_, i) => _OrphanCard(row: rows[i], onDelete: _deleteDraft),
            ),
          );
        },
      ),
    );
  }
}

class _OrphanCard extends StatelessWidget {
  const _OrphanCard({required this.row, required this.onDelete});

  final Map<String, dynamic> row;
  final Future<void> Function(String draftId) onDelete;

  @override
  Widget build(BuildContext context) {
    final kind = row['kind'] as String? ?? '?';
    final id = row['id'] as String? ?? '?';
    final pi = row['payment_intent_id'] as String? ?? 'n/a';
    final amount = (row['amount'] as num?)?.toDouble() ?? 0.0;
    final ageMin = (row['age_minutes'] as num?)?.toDouble() ?? 0.0;
    final notes = row['notes'] as String? ?? '';

    final isDraft = kind == 'payment_draft';
    final color = isDraft ? AppColors.warning : Colors.red.shade700;

    return Card(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: color, width: 1),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(isDraft ? Icons.hourglass_top : Icons.error_outline, color: color),
                const SizedBox(width: 8),
                Text(isDraft ? 'Payment Draft' : 'Order sem charge',
                    style: TextStyle(fontWeight: FontWeight.bold, color: color)),
                const Spacer(),
                Text('${ageMin.toStringAsFixed(0)} min', style: const TextStyle(fontSize: 12)),
              ],
            ),
            const SizedBox(height: 8),
            Text('ID: $id', style: const TextStyle(fontFamily: 'monospace', fontSize: 12)),
            Text('PI: $pi', style: const TextStyle(fontFamily: 'monospace', fontSize: 12)),
            Text('Valor: €${amount.toStringAsFixed(2)}'),
            Text('Estado: $notes'),
            if (isDraft) ...[
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton.icon(
                  icon: const Icon(Icons.delete, size: 16),
                  label: const Text('Excluir draft'),
                  onPressed: () => onDelete(id),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
