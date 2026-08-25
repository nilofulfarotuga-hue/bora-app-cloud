// Painel admin (PT-BR) — auditoria da ida ao mercado de um pedido.
//
// Nasceu do caso real de 2026-08-25 (entrega do Continente): o app do
// entregador gravou a MESMA lista de 6 linhas duas vezes (18:03:12 e
// 18:03:38) e a cliente viu tudo repetido. O app já foi corrigido, mas o
// admin não tinha onde OLHAR: não dava para ver as linhas gravadas, nem o
// estado do reconhecimento do talão, nem apagar uma linha repetida.
//
// Esta aba mostra, por pedido:
//   • cada linha de `order_purchase_items_v2` com o seu estado
//     (pendente / comprado / em falta / substituído / adicionado);
//   • linhas REPETIDAS destacadas, com botão para apagar a repetida;
//   • o estado do reconhecimento automático do talão
//     (`order_receipts_v2`): rodou? leu o total? divergiu do digitado?
//   • botão "Marcar como revisado" (baixa o sinalizador de revisão e deixa
//     a nota de quem revisou e quando).
//
// Não toca em nenhuma coluna de dinheiro: valores de reembolso, status de
// reembolso e totais do pedido são apenas LIDOS.

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../config/app_colors.dart';
import '../../config/app_spacing.dart';
import '../../widgets/private_bucket_image.dart';

class AdminOrderPurchaseTab extends StatefulWidget {
  const AdminOrderPurchaseTab({super.key, required this.orderId});

  final String orderId;

  @override
  State<AdminOrderPurchaseTab> createState() => _AdminOrderPurchaseTabState();
}

class _AdminOrderPurchaseTabState extends State<AdminOrderPurchaseTab> {
  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _items = const [];
  Map<String, dynamic>? _receipt;
  final Set<String> _apagando = <String>{};
  bool _salvandoRevisao = false;

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
      final sb = Supabase.instance.client;
      final items = await sb
          .from('order_purchase_items_v2')
          .select('id, original_item_id, original_name, original_price_cents, '
              'original_qty, status, actual_name, actual_price_cents, '
              'actual_qty, created_at')
          .eq('order_id', widget.orderId)
          .order('created_at');
      final receipt = await sb
          .from('order_receipts_v2')
          .select('id, photo_url, photo_taken_at, driver_typed_total_cents, '
              'ocr_extracted_total_cents, ocr_diff_cents, ocr_flagged, '
              'ocr_ran_at, receipt_parsed_total_cents, receipt_parsed_store, '
              'receipt_match, reimbursement_status, reimbursement_admin_notes')
          .eq('order_id', widget.orderId)
          .maybeSingle();
      if (!mounted) return;
      setState(() {
        _items = List<Map<String, dynamic>>.from(items as List);
        _receipt = receipt;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = 'Falha ao carregar a ida ao mercado: $e';
        _loading = false;
      });
    }
  }

  // ── Duplicadas ───────────────────────────────────────────────────────────

  /// Chave de identidade de uma linha. Duas linhas com a mesma chave são a
  /// mesma linha gravada duas vezes.
  String _chave(Map<String, dynamic> m) => [
        (m['original_name'] ?? '').toString().trim().toLowerCase(),
        (m['status'] ?? '').toString(),
        (m['original_qty'] ?? '').toString(),
        (m['original_price_cents'] ?? '').toString(),
      ].join('|');

  /// Ids das linhas que são repetição de uma anterior (a primeira fica).
  Set<String> get _idsRepetidos {
    final vistos = <String>{};
    final repetidos = <String>{};
    for (final m in _items) {
      final k = _chave(m);
      if (vistos.contains(k)) {
        repetidos.add(m['id'] as String);
      } else {
        vistos.add(k);
      }
    }
    return repetidos;
  }

  Future<void> _apagarLinha(Map<String, dynamic> m) async {
    final id = m['id'] as String;
    final nome = (m['original_name'] ?? 'linha').toString();
    final ok = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Apagar linha repetida?'),
            content: Text(
              'Vai apagar a linha "$nome" desta ida ao mercado.\n\n'
              'Use isso só quando a MESMA linha aparece duas vezes. '
              'A ação não mexe em nenhum valor cobrado nem em reembolso.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Cancelar'),
              ),
              FilledButton(
                style: FilledButton.styleFrom(
                    backgroundColor: AppColors.error),
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('Apagar'),
              ),
            ],
          ),
        ) ??
        false;
    if (!ok || !mounted) return;

    setState(() => _apagando.add(id));
    try {
      // `.select()` devolve as linhas realmente apagadas — com RLS, um DELETE
      // negado responde 200 com lista vazia. É a única forma de saber.
      final apagadas = await Supabase.instance.client
          .from('order_purchase_items_v2')
          .delete()
          .eq('id', id)
          .select('id');
      if (!mounted) return;
      if ((apagadas as List).isEmpty) {
        await _avisoSemPermissao();
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Linha repetida apagada.')),
      );
      await _load();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Não foi possível apagar: $e')),
      );
    } finally {
      if (mounted) setState(() => _apagando.remove(id));
    }
  }

  Future<void> _avisoSemPermissao() async {
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        icon: const Icon(Icons.lock_outline, color: AppColors.warning, size: 40),
        title: const Text('O banco recusou a exclusão'),
        content: const Text(
          'Nada foi alterado. A tabela order_purchase_items_v2 hoje só tem '
          'política de LEITURA para admin — falta a política de DELETE.\n\n'
          'É uma alteração de banco (RLS): precisa da sua autorização para '
          'ser aplicada. Está anotada no relatório desta correção.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Entendi'),
          ),
        ],
      ),
    );
  }

  // ── Revisão do talão ─────────────────────────────────────────────────────

  Future<void> _marcarRevisado() async {
    final receipt = _receipt;
    if (receipt == null) return;
    setState(() => _salvandoRevisao = true);
    try {
      final agora = DateTime.now();
      final quando = '${agora.day.toString().padLeft(2, '0')}/'
          '${agora.month.toString().padLeft(2, '0')}/${agora.year} '
          '${agora.hour.toString().padLeft(2, '0')}:'
          '${agora.minute.toString().padLeft(2, '0')}';
      final antigas =
          (receipt['reimbursement_admin_notes'] as String?)?.trim() ?? '';
      final nota = antigas.isEmpty
          ? 'Revisado no painel em $quando.'
          : '$antigas\nRevisado no painel em $quando.';

      final atualizadas = await Supabase.instance.client
          .from('order_receipts_v2')
          .update(<String, dynamic>{
            // Só o sinalizador de revisão e a nota. Nenhum valor de dinheiro,
            // nenhum status de reembolso.
            'ocr_flagged': false,
            'reimbursement_admin_notes': nota,
          })
          .eq('order_id', widget.orderId)
          .select('id');
      if (!mounted) return;
      if ((atualizadas as List).isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
                'O banco não aplicou a marcação (permissão de admin em falta).'),
          ),
        );
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Talão marcado como revisado.')),
      );
      await _load();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Não foi possível marcar como revisado: $e')),
      );
    } finally {
      if (mounted) setState(() => _salvandoRevisao = false);
    }
  }

  // ── Build ────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(Spacing.lg),
          child: Text(_error!,
              style: const TextStyle(color: AppColors.error),
              textAlign: TextAlign.center),
        ),
      );
    }

    final repetidos = _idsRepetidos;

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.all(Spacing.md),
        children: [
          _cardTalao(),
          const SizedBox(height: Spacing.md),
          if (repetidos.isNotEmpty) ...[
            _avisoRepetidas(repetidos.length),
            const SizedBox(height: Spacing.md),
          ],
          Text('Lista da ida ao mercado (${_items.length} linha'
              '${_items.length == 1 ? '' : 's'})',
              style: const TextStyle(fontWeight: FontWeight.w700)),
          const SizedBox(height: Spacing.sm),
          if (_items.isEmpty)
            const Card(
              child: Padding(
                padding: EdgeInsets.all(Spacing.md),
                child: Text(
                    'Nenhuma linha gravada. Este pedido não passou pelo fluxo '
                    'novo da ida ao mercado (storeShopping v2).'),
              ),
            )
          else
            ..._items.map((m) => _linha(m, repetidos.contains(m['id']))),
        ],
      ),
    );
  }

  Widget _avisoRepetidas(int n) => Card(
        color: AppColors.warning.withValues(alpha: 0.12),
        child: Padding(
          padding: const EdgeInsets.all(Spacing.md),
          child: Row(
            children: [
              const Icon(Icons.content_copy, color: AppColors.warning),
              const SizedBox(width: Spacing.sm),
              Expanded(
                child: Text(
                  '$n linha${n == 1 ? '' : 's'} repetida${n == 1 ? '' : 's'} '
                  'nesta lista. A primeira ocorrência fica; use o ícone da '
                  'lixeira para apagar a cópia.',
                  style: const TextStyle(fontSize: 13),
                ),
              ),
            ],
          ),
        ),
      );

  Widget _linha(Map<String, dynamic> m, bool repetida) {
    final status = (m['status'] ?? '').toString();
    final (rotulo, cor, icone) = _estadoLinha(status);
    final qtd = (m['original_qty'] as num?)?.toInt() ?? 1;
    final precoCents = (m['original_price_cents'] as num?)?.toInt() ?? 0;
    final realNome = m['actual_name'] as String?;
    final realCents = (m['actual_price_cents'] as num?)?.toInt();
    final realQtd = (m['actual_qty'] as num?)?.toInt();
    final criado = DateTime.tryParse((m['created_at'] ?? '').toString());
    final id = m['id'] as String;

    return Card(
      margin: const EdgeInsets.only(bottom: Spacing.sm),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: repetida
            ? const BorderSide(color: AppColors.warning, width: 1.4)
            : BorderSide(color: Colors.grey.shade200),
      ),
      child: Padding(
        padding: const EdgeInsets.all(Spacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icone, color: cor, size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    (m['original_name'] ?? '—').toString(),
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                ),
                Text('${qtd}x  €${(precoCents / 100).toStringAsFixed(2)}',
                    style: const TextStyle(fontWeight: FontWeight.w600)),
              ],
            ),
            const SizedBox(height: 6),
            Wrap(
              spacing: 8,
              runSpacing: 4,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                _chip(rotulo, cor),
                if (repetida) _chip('REPETIDA', AppColors.warning),
                if (criado != null)
                  Text(
                    'gravada ${criado.hour.toString().padLeft(2, '0')}:'
                    '${criado.minute.toString().padLeft(2, '0')}:'
                    '${criado.second.toString().padLeft(2, '0')}',
                    style: TextStyle(
                        fontSize: 11, color: Colors.grey.shade600),
                  ),
              ],
            ),
            if (realNome != null || realCents != null || realQtd != null) ...[
              const SizedBox(height: 6),
              Text(
                'Real: ${realNome ?? (m['original_name'] ?? '—')}'
                '${realQtd != null ? '  ·  ${realQtd}x' : ''}'
                '${realCents != null ? '  ·  €${(realCents / 100).toStringAsFixed(2)}' : ''}',
                style: TextStyle(fontSize: 12, color: Colors.grey.shade700),
              ),
            ],
            if (repetida)
              Align(
                alignment: Alignment.centerRight,
                child: _apagando.contains(id)
                    ? const Padding(
                        padding: EdgeInsets.only(top: 4),
                        child: SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                      )
                    : TextButton.icon(
                        onPressed: () => _apagarLinha(m),
                        icon: const Icon(Icons.delete_outline, size: 18),
                        label: const Text('Apagar repetida'),
                        style: TextButton.styleFrom(
                            foregroundColor: AppColors.error),
                      ),
              ),
          ],
        ),
      ),
    );
  }

  (String, Color, IconData) _estadoLinha(String status) {
    switch (status) {
      case 'purchased':
        return ('Comprado', AppColors.primary, Icons.check_circle);
      case 'unavailable':
        return ('Em falta', AppColors.error, Icons.cancel);
      case 'replaced':
        return ('Substituído', AppColors.warning, Icons.swap_horiz);
      case 'added':
        return ('Adicionado pelo entregador', AppColors.info, Icons.add_circle);
      case 'pending':
        return ('Pendente', Colors.grey, Icons.radio_button_unchecked);
      default:
        return (status.isEmpty ? '—' : status, Colors.grey, Icons.help_outline);
    }
  }

  Widget _chip(String texto, Color cor) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: cor.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: cor.withValues(alpha: 0.4)),
        ),
        child: Text(texto,
            style: TextStyle(
                fontSize: 11, color: cor, fontWeight: FontWeight.w700)),
      );

  // ── Card do talão + reconhecimento ───────────────────────────────────────

  Widget _cardTalao() {
    final r = _receipt;
    if (r == null) {
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(Spacing.md),
          child: Row(
            children: [
              Icon(Icons.receipt_long_outlined, color: Colors.grey.shade600),
              const SizedBox(width: Spacing.sm),
              const Expanded(
                child: Text('Sem talão registrado para este pedido.'),
              ),
            ],
          ),
        ),
      );
    }

    final digitado = (r['driver_typed_total_cents'] as num?)?.toInt();
    final lido = (r['receipt_parsed_total_cents'] as num?)?.toInt() ??
        (r['ocr_extracted_total_cents'] as num?)?.toInt();
    final diff = (r['ocr_diff_cents'] as num?)?.toInt();
    final flagged = r['ocr_flagged'] as bool? ?? false;
    final rodouEm = DateTime.tryParse((r['ocr_ran_at'] ?? '').toString());
    final loja = r['receipt_parsed_store'] as String?;
    final notas = (r['reimbursement_admin_notes'] as String?)?.trim();
    final foto = r['photo_url'] as String?;

    final (rotulo, cor, precisaRevisao) = _estadoReconhecimento(
      rodou: rodouEm != null,
      lido: lido,
      flagged: flagged,
    );

    return Card(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
            color: precisaRevisao ? AppColors.warning : Colors.grey.shade200,
            width: precisaRevisao ? 1.4 : 1),
      ),
      child: Padding(
        padding: const EdgeInsets.all(Spacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.receipt_long, color: AppColors.primary),
                const SizedBox(width: 8),
                const Expanded(
                  child: Text('Talão da compra',
                      style: TextStyle(fontWeight: FontWeight.w700)),
                ),
                _chip(rotulo, cor),
              ],
            ),
            const SizedBox(height: Spacing.sm),
            _kv('Valor digitado pelo entregador',
                digitado != null
                    ? '€${(digitado / 100).toStringAsFixed(2)}'
                    : '—'),
            _kv('Valor lido automaticamente',
                lido != null && lido > 0
                    ? '€${(lido / 100).toStringAsFixed(2)}'
                    : 'não foi lido'),
            if (diff != null)
              _kv('Diferença (digitado − lido)',
                  '€${(diff / 100).toStringAsFixed(2)}'),
            if (loja != null && loja.isNotEmpty) _kv('Loja no talão', loja),
            _kv(
                'Reconhecimento rodou',
                rodouEm != null
                    ? '${rodouEm.day.toString().padLeft(2, '0')}/'
                        '${rodouEm.month.toString().padLeft(2, '0')} '
                        '${rodouEm.hour.toString().padLeft(2, '0')}:'
                        '${rodouEm.minute.toString().padLeft(2, '0')}'
                    : 'ainda não'),
            if (precisaRevisao) ...[
              const SizedBox(height: Spacing.sm),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: AppColors.warning.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Text(
                  'Precisa de revisão. O valor que vale é o que o entregador '
                  'digitou — a leitura automática é só conferência, e quando '
                  'ela falha o app segue em frente de propósito, sem obrigar '
                  'a repetir a foto.',
                  style: TextStyle(fontSize: 12),
                ),
              ),
            ],
            if (notas != null && notas.isNotEmpty) ...[
              const SizedBox(height: Spacing.sm),
              Text('Notas do admin:\n$notas',
                  style: TextStyle(fontSize: 12, color: Colors.grey.shade700)),
            ],
            if (foto != null && foto.isNotEmpty) ...[
              const SizedBox(height: Spacing.sm),
              PrivateBucketImage(
                urlOrPath: foto,
                height: 180,
                borderRadius: BorderRadius.circular(8),
              ),
            ],
            const SizedBox(height: Spacing.sm),
            Align(
              alignment: Alignment.centerRight,
              child: _salvandoRevisao
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2))
                  : OutlinedButton.icon(
                      onPressed: flagged || precisaRevisao
                          ? _marcarRevisado
                          : null,
                      icon: const Icon(Icons.done_all, size: 18),
                      label: Text(flagged || precisaRevisao
                          ? 'Marcar como revisado'
                          : 'Nada a revisar'),
                    ),
            ),
          ],
        ),
      ),
    );
  }

  (String, Color, bool) _estadoReconhecimento({
    required bool rodou,
    required int? lido,
    required bool flagged,
  }) {
    if (!rodou) return ('não rodou ainda', Colors.grey, false);
    if (lido == null || lido == 0) {
      return ('total não lido', AppColors.warning, true);
    }
    if (flagged) return ('divergência sinalizada', AppColors.warning, true);
    return ('conferido', AppColors.primary, false);
  }

  Widget _kv(String label, String valor) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Text(label,
                  style: TextStyle(fontSize: 12, color: Colors.grey.shade700)),
            ),
            const SizedBox(width: 8),
            Text(valor,
                style: const TextStyle(
                    fontSize: 12, fontWeight: FontWeight.w700)),
          ],
        ),
      );
}
