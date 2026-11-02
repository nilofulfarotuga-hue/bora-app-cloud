import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../config/app_colors.dart';
import '../../config/app_spacing.dart';
import '../../services/auth_admin_service.dart';
import '../../utils/hora_lisboa.dart';
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
  // 01/11/2026 (missão chaves-varredura, B2): rascunhos pagos sem pedido + histórico do vigia
  // (deep-link /admin/orphans dos alertas "PAGOU E NÃO TEM PEDIDO").
  late Future<List<Map<String, dynamic>>> _futurePagos;
  final Set<String> _aCriar = {};

  @override
  void initState() {
    super.initState();
    _future = _load();
    _futurePagos = _loadPagos();
  }

  Future<List<Map<String, dynamic>>> _load() async {
    final res = await Supabase.instance.client.rpc('admin_list_orphans');
    if (res is List) return res.map((e) => Map<String, dynamic>.from(e as Map)).toList();
    return const [];
  }

  Future<List<Map<String, dynamic>>> _loadPagos() async {
    final res = await Supabase.instance.client.rpc('admin_pagos_sem_pedido');
    if (res is List) return res.map((e) => Map<String, dynamic>.from(e as Map)).toList();
    return const [];
  }

  Future<void> _refresh() async {
    setState(() {
      _future = _load();
      _futurePagos = _loadPagos();
    });
    await Future.wait([_future, _futurePagos]);
  }

  /// Chama a finalize-order-from-intent com a sessão do admin (aceita admin desde a v15). Ela
  /// confirma na Stripe que o pagamento foi mesmo concluído antes de criar o pedido, e não cria
  /// dois pedidos para o mesmo rascunho.
  Future<void> _criarPedido(Map<String, dynamic> row) async {
    final pi = row['payment_intent_id'] as String?;
    final draftId = row['draft_id'] as String?;
    if (pi == null || draftId == null || _aCriar.contains(draftId)) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Criar o pedido agora?'),
        content: Text(
            'O pagamento de ${row['cliente_nome'] ?? 'cliente'} '
            '(€${((row['valor'] as num?) ?? 0).toStringAsFixed(2)}) vai virar pedido, '
            'igual ao que devia ter acontecido sozinho. O servidor confirma primeiro '
            'na Stripe (processadora de pagamentos) que o dinheiro entrou.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Criar pedido')),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    setState(() => _aCriar.add(draftId));
    String msg;
    try {
      final r = await Supabase.instance.client.functions
          .invoke('finalize-order-from-intent', body: {'payment_intent_id': pi});
      final dados = r.data is Map ? Map<String, dynamic>.from(r.data as Map) : <String, dynamic>{};
      final pedido = dados['order_id']?.toString();
      msg = dados['idempotent'] == true
          ? 'Este pagamento já tinha pedido${pedido != null ? ': $pedido' : ''}.'
          : 'Pedido criado${pedido != null ? ': $pedido' : ''}.';
      try {
        await Supabase.instance.client.rpc('log_admin_action', params: {
          'p_action': 'pedido_criado_de_rascunho_pago',
          'p_entity_type': 'payment_draft',
          'p_entity_id': draftId,
          'p_details': {'payment_intent_id': pi, 'order_id': pedido, 'resposta': dados},
        });
      } catch (e) {
        debugPrint('[AdminOrphanPayments] auditoria: $e');
      }
    } on FunctionException catch (e) {
      final det = e.details is Map ? Map<String, dynamic>.from(e.details as Map) : <String, dynamic>{};
      msg = switch (det['error']) {
        'pi_not_succeeded' =>
          'A Stripe diz que este pagamento NÃO foi concluído (estado: ${det['status'] ?? '?'}). Nada foi criado.',
        'draft_not_found' => 'O rascunho já não existe. Nada foi criado.',
        _ => 'O servidor recusou (HTTP ${e.status}): ${det['error'] ?? e.details}',
      };
    } catch (e) {
      msg = 'Erro ao criar o pedido: $e';
    }
    if (!mounted) return;
    setState(() => _aCriar.remove(draftId));
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
    await _refresh();
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
      body: RefreshIndicator(
        onRefresh: _refresh,
        child: ListView(
          padding: const EdgeInsets.all(12),
          children: [
            const _Titulo('Pagos sem pedido',
                'Rascunhos de pagamento (cartão / MB Way) ainda sem pedido. "Pago" = a Stripe confirmou.'),
            FutureBuilder<List<Map<String, dynamic>>>(
              future: _futurePagos,
              builder: (context, snap) {
                if (snap.connectionState == ConnectionState.waiting) {
                  return const Padding(
                      padding: EdgeInsets.all(16), child: Center(child: CircularProgressIndicator()));
                }
                if (snap.hasError) {
                  return Text('Erro a carregar (admin_pagos_sem_pedido): ${snap.error}');
                }
                final todos = snap.data ?? const [];
                final pendentes = todos.where((r) => r['estado'] != 'com_pedido').toList();
                final historico = todos.where((r) => r['tentativa_em'] != null).toList();
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (pendentes.isEmpty)
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 12),
                        child: Text('Nenhum pagamento à espera de pedido.'),
                      ),
                    for (final r in pendentes) ...[
                      _PagoCard(
                        row: r,
                        aCriar: _aCriar.contains(r['draft_id']),
                        onCriar: () => _criarPedido(r),
                      ),
                      const SizedBox(height: 8),
                    ],
                    const SizedBox(height: 8),
                    const _Titulo('Histórico do vigia',
                        'O que o vigia "pago sem pedido" apanhou (payment_drafts_alertados): quando tentou curar e quando avisou.'),
                    if (historico.isEmpty)
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 12),
                        child: Text('O vigia ainda não apanhou nenhum caso.'),
                      ),
                    for (final r in historico) _HistoricoLinha(row: r),
                  ],
                );
              },
            ),
            const SizedBox(height: 16),
            const _Titulo('Outros órfãos', 'Rascunhos por usar e pedidos sem cobrança (admin_list_orphans).'),
            FutureBuilder<List<Map<String, dynamic>>>(
              future: _future,
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Padding(
                      padding: EdgeInsets.all(16), child: Center(child: CircularProgressIndicator()));
                }
                if (snapshot.hasError) {
                  return Text(
                    'Erro a carregar: ${snapshot.error}\n\n'
                    'Verifica que admin_list_orphans existe e tens role=admin.',
                  );
                }
                final rows = snapshot.data ?? const [];
                if (rows.isEmpty) {
                  return const Padding(
                    padding: EdgeInsets.symmetric(vertical: 24),
                    child: Column(children: [
                      Icon(Icons.check_circle_outline, size: 48, color: Colors.green),
                      SizedBox(height: 8),
                      Text('Sem órfãos. Tudo limpo.', style: TextStyle(fontSize: 16)),
                    ]),
                  );
                }
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (final r in rows) ...[
                      _OrphanCard(row: r, onDelete: _deleteDraft),
                      const SizedBox(height: 8),
                    ],
                  ],
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _Titulo extends StatelessWidget {
  const _Titulo(this.titulo, this.explicacao);
  final String titulo;
  final String explicacao;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(titulo, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
          Text(explicacao, style: const TextStyle(fontSize: 12, color: AppColors.textSecondary)),
        ]),
      );
}

String _horaLisboa(dynamic iso) => dataHoraLisboa(iso);

class _PagoCard extends StatelessWidget {
  const _PagoCard({required this.row, required this.aCriar, required this.onCriar});
  final Map<String, dynamic> row;
  final bool aCriar;
  final VoidCallback onCriar;

  @override
  Widget build(BuildContext context) {
    final estado = row['estado'] as String? ?? '?';
    final pago = estado == 'pago_sem_pedido';
    final cor = pago ? AppColors.error : (estado == 'expirado' ? AppColors.textSecondary : AppColors.warning);
    final rotulo = switch (estado) {
      'pago_sem_pedido' => 'PAGOU E NÃO TEM PEDIDO',
      'a_espera_do_pagamento' => 'À espera do pagamento',
      'expirado' => 'Expirado sem pagamento',
      _ => estado,
    };
    final valor = ((row['valor'] as num?) ?? 0).toDouble();
    final minutos = ((row['minutos'] as num?) ?? 0).toInt();
    final metodo = switch (row['metodo']) { 'mbway' => 'MB Way', 'card' => 'cartão', final m => '${m ?? '?'}' };
    return Container(
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(Radii.lg),
        border: Border.all(color: cor, width: pago ? 2 : 1),
        boxShadow: AppColors.shadowCard,
      ),
      padding: const EdgeInsets.all(12),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(pago ? Icons.warning_amber_rounded : Icons.hourglass_top, color: cor),
          const SizedBox(width: 8),
          Expanded(child: Text(rotulo, style: TextStyle(fontWeight: FontWeight.bold, color: cor))),
          Text(minutos < 120 ? 'há $minutos min' : 'há ${(minutos / 60).round()} h',
              style: const TextStyle(fontSize: 12)),
        ]),
        const SizedBox(height: 8),
        Text('${row['cliente_nome'] ?? 'Cliente sem nome'} · ${row['cliente_telefone'] ?? 'sem telefone'}',
            style: const TextStyle(fontWeight: FontWeight.w600)),
        Text('Loja: ${row['loja'] ?? '?'} · €${valor.toStringAsFixed(2)} · $metodo'),
        Text('Criado ${_horaLisboa(row['criado_em'])} (hora de Lisboa)', style: const TextStyle(fontSize: 12)),
        Text('PI (pagamento na Stripe): ${row['payment_intent_id'] ?? '?'}',
            style: const TextStyle(fontFamily: 'monospace', fontSize: 11)),
        if (pago) ...[
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerRight,
            child: FilledButton.icon(
              icon: aCriar
                  ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.add_shopping_cart, size: 18),
              label: const Text('Criar o pedido agora'),
              onPressed: aCriar ? null : onCriar,
            ),
          ),
        ],
      ]),
    );
  }
}

class _HistoricoLinha extends StatelessWidget {
  const _HistoricoLinha({required this.row});
  final Map<String, dynamic> row;

  @override
  Widget build(BuildContext context) {
    final valor = ((row['valor'] as num?) ?? 0).toDouble();
    final comPedido = row['estado'] == 'com_pedido';
    return ListTile(
      dense: true,
      contentPadding: EdgeInsets.zero,
      leading: Icon(comPedido ? Icons.check_circle : Icons.error_outline,
          color: comPedido ? AppColors.success : AppColors.error),
      title: Text('${row['cliente_nome'] ?? 'Cliente'} · ${row['loja'] ?? '?'} · €${valor.toStringAsFixed(2)}'),
      subtitle: Text(
        'Tentou curar: ${_horaLisboa(row['tentativa_em'])} · '
        'Avisou: ${row['avisado_em'] == null ? 'não foi preciso' : _horaLisboa(row['avisado_em'])} · '
        '${comPedido ? 'pedido ${row['pedido_id'] ?? ''}' : 'ainda sem pedido'}',
        style: const TextStyle(fontSize: 12),
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
