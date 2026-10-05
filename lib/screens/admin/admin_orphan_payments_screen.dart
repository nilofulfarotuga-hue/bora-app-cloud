import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../config/app_colors.dart';
import '../../config/app_spacing.dart';
import '../../services/auth_admin_service.dart';
import '../../widgets/bora/bora_screen_app_bar.dart';

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

  Future<void> _deleteDraft(Map<String, dynamic> row) async {
    final draftId = row['id'] as String?;
    if (draftId == null) return;
    // [ronda 04/10] Apagar um rascunho não se desfaz, e sem ele um pagamento
    // que ainda entre não vira pedido (`finalize-order-from-intent` devolve
    // draft_not_found): confirma-se antes e fica na auditoria.
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Excluir este rascunho de pagamento?'),
        content: const Text(
            'Não dá para desfazer. O rascunho guarda o carrinho de um '
            'pagamento por cartão que ainda não virou pedido: se o cliente '
            'ainda pagar, o pedido não é criado sozinho.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancelar')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Excluir')),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    try {
      final sb = Supabase.instance.client;
      // Sem permissão a base apaga ZERO linhas e não dá erro (hoje a tabela só
      // deixa ler): pede-se de volta o que saiu e só então se diz "apagado" e
      // se regista — nunca uma exclusão que não aconteceu.
      final apagados = await sb
          .from('payment_drafts')
          .delete()
          .eq('id', draftId)
          .select('id');
      if (apagados.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
                content: Text(
                    'O servidor não deixou excluir este rascunho. Ele some '
                    'sozinho depois de expirar.')),
          );
        }
        return;
      }
      // A auditoria falhar não desfaz o que já foi apagado: diz-se a verdade.
      var registado = true;
      try {
        await sb.rpc('log_admin_action', params: {
          'p_action': 'rascunho_pagamento_excluido',
          'p_entity_type': 'payment_draft',
          'p_entity_id': draftId,
          'p_details': {
            'payment_intent_id': row['payment_intent_id'],
            'valor': row['amount'],
            'idade_minutos': row['age_minutes'],
            'estado': row['notes'],
          },
        });
      } catch (e) {
        registado = false;
        debugPrint('[AdminOrphanPayments] auditoria: $e');
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text(registado
                  ? 'Draft apagado.'
                  : 'Draft apagado, mas não ficou registrado na auditoria.')),
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
      return const Scaffold(
        backgroundColor: AppColors.background,
        appBar: BoraScreenAppBar(title: 'Órfãos de pagamento'),
        body: Center(child: Text('Acesso negado.')),
      );
    }

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: BoraScreenAppBar(
        title: 'Órfãos de pagamento',
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
  final Future<void> Function(Map<String, dynamic> row) onDelete;

  @override
  Widget build(BuildContext context) {
    final kind = row['kind'] as String? ?? '?';
    final id = row['id'] as String? ?? '?';
    final pi = row['payment_intent_id'] as String? ?? 'n/a';
    final amount = (row['amount'] as num?)?.toDouble() ?? 0.0;
    final ageMin = (row['age_minutes'] as num?)?.toDouble() ?? 0.0;
    final notes = row['notes'] as String? ?? '';

    final isDraft = kind == 'payment_draft';
    final color = isDraft ? AppColors.warning : AppColors.error;

    return Container(
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(Radii.lg),
        border: Border.all(color: color, width: 1),
        boxShadow: AppColors.shadowCard,
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
                  onPressed: () => onDelete(row),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
