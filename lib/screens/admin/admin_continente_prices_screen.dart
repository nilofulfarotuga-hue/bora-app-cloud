import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../config/app_colors.dart';
import '../../widgets/bora/bora_screen_app_bar.dart';

/// Painel admin — revisão dos preços PVPR do Continente (staging).
/// Idioma PT-BR (decisão Danilo). Lê/escreve via RPCs admin_continente_*.
/// NUNCA aplica preços automaticamente — só pelo botão "Aplicar aprovados".
class AdminContinentePricesScreen extends StatefulWidget {
  const AdminContinentePricesScreen({super.key});

  @override
  State<AdminContinentePricesScreen> createState() =>
      _AdminContinentePricesScreenState();
}

class _AdminContinentePricesScreenState
    extends State<AdminContinentePricesScreen> {
  bool _loading = true;
  bool _busy = false;
  String? _error;
  Map<String, dynamic> _summary = {};
  List<Map<String, dynamic>> _rows = [];
  String _filter = 'big_div';

  // filtros (chave RPC -> rótulo PT-BR)
  static const _filters = <MapEntry<String, String>>[
    MapEntry('big_div', 'Divergência ≥25%'),
    MapEntry('pending', 'Pendentes'),
    MapEntry('promo', 'Em promoção'),
    MapEntry('needs_review', 'Precisa revisão'),
    MapEntry('no_price', 'Sem preço'),
    MapEntry('approved', 'Aprovados'),
    MapEntry('applied', 'Aplicados'),
    MapEntry('all', 'Todos'),
  ];

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
      final res = await Future.wait([
        sb.rpc('admin_continente_price_summary'),
        sb.rpc('admin_continente_price_list',
            params: {'p_filter': _filter, 'p_limit': 500, 'p_offset': 0}),
      ]);
      if (!mounted) return;
      setState(() {
        _summary = Map<String, dynamic>.from(res[0] as Map);
        _rows = (res[1] as List)
            .map((e) => Map<String, dynamic>.from(e as Map))
            .toList();
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

  Future<void> _review(List<String> ids, String action) async {
    if (ids.isEmpty || _busy) return;
    setState(() => _busy = true);
    try {
      await Supabase.instance.client.rpc('admin_continente_price_review',
          params: {'p_ids': ids, 'p_action': action});
      await _load();
      _snack(action == 'approved'
          ? '${ids.length} aprovado(s).'
          : '${ids.length} rejeitado(s).');
    } catch (e) {
      _snack('Erro: $e', error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _applyApproved() async {
    final approved = (_summary['approved'] ?? 0) as int;
    if (approved == 0) {
      _snack('Não há linhas aprovadas para aplicar.');
      return;
    }
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Aplicar preços aprovados?'),
        content: Text(
            'Vai gravar $approved preço(s) aprovado(s) na tabela de produtos '
            '(campo preço). Esta ação fica registrada no log de auditoria. '
            'Continuar?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancelar')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Aplicar')),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    setState(() => _busy = true);
    try {
      final r = await Supabase.instance.client
          .rpc('admin_continente_apply_prices') as Map;
      await _load();
      _snack('Aplicados ${r['applied']} preço(s) aos produtos.');
    } catch (e) {
      _snack('Erro ao aplicar: $e', error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _snack(String msg, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg),
      backgroundColor: error ? Colors.red.shade700 : null,
    ));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: const BoraScreenAppBar(title: 'Preços Continente (PVPR)'),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(
                  child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Text('Erro: $_error',
                      style: const TextStyle(color: AppColors.error)),
                ))
              : Column(
                  children: [
                    _summaryPanel(),
                    _filterBar(),
                    const Divider(height: 1),
                    Expanded(child: _list()),
                  ],
                ),
    );
  }

  Widget _summaryPanel() {
    int n(String k) => (_summary[k] ?? 0) as int;
    final items = <List<dynamic>>[
      ['Total', n('total'), Colors.blueGrey],
      ['Atualizáveis', n('ok'), Colors.green],
      ['Promoção', n('promo'), Colors.indigo],
      ['≥25%', n('big_div'), Colors.orange],
      ['Revisão', n('needs_review'), Colors.amber.shade800],
      ['Sem preço', n('no_price'), Colors.grey],
      ['Aprovados', n('approved'), Colors.teal],
      ['Aplicados', n('applied'), Colors.purple],
    ];
    return Container(
      width: double.infinity,
      color: AppColors.surface,
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: items
                .map((it) => _statChip(
                    it[0] as String, it[1] as int, it[2] as Color))
                .toList(),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              FilledButton.icon(
                onPressed: _busy ? null : _applyApproved,
                icon: const Icon(Icons.save),
                label: Text('Aplicar aprovados (${n('approved')})'),
              ),
              const SizedBox(width: 8),
              OutlinedButton.icon(
                onPressed: _busy ? null : _load,
                icon: const Icon(Icons.refresh),
                label: const Text('Atualizar'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _statChip(String label, int value, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Text('$label: $value',
          style: TextStyle(
              color: color, fontWeight: FontWeight.w600, fontSize: 12.5)),
    );
  }

  Widget _filterBar() {
    return SizedBox(
      height: 48,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 8),
        children: _filters.map((f) {
          final sel = f.key == _filter;
          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
            child: ChoiceChip(
              label: Text(f.value),
              selected: sel,
              onSelected: _busy
                  ? null
                  : (_) {
                      setState(() => _filter = f.key);
                      _load();
                    },
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _list() {
    if (_rows.isEmpty) {
      return const Center(child: Text('Sem linhas neste filtro.'));
    }
    final visibleIds = _rows
        .where((r) => r['applied'] != true)
        .map((r) => r['id'] as String)
        .toList();
    return Column(
      children: [
        if (visibleIds.isNotEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            child: Row(
              children: [
                Text(
                    '${_rows.length} linha(s)${_rows.length >= 500 ? ' (máx. 500)' : ''}'),
                const Spacer(),
                TextButton(
                  onPressed:
                      _busy ? null : () => _review(visibleIds, 'approved'),
                  child: const Text('Aprovar todos os visíveis'),
                ),
              ],
            ),
          ),
        Expanded(
          child: ListView.builder(
            itemCount: _rows.length,
            itemBuilder: (_, i) => _rowCard(_rows[i]),
          ),
        ),
      ],
    );
  }

  Widget _rowCard(Map<String, dynamic> r) {
    final old = (r['old_price'] as num?)?.toDouble();
    final neu = (r['new_price'] as num?)?.toDouble();
    final div = (r['divergence_pct'] as num?)?.toDouble();
    final promo = r['had_promo'] == true;
    final status = r['status'] as String? ?? '';
    final action = r['reviewer_action'] as String?;
    final applied = r['applied'] == true;
    final id = r['id'] as String;

    Color divColor = Colors.green;
    if (div != null && div.abs() >= 0.5) {
      divColor = Colors.red;
    } else if (div != null && div.abs() >= 0.25) {
      divColor = Colors.orange;
    }

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(r['name'] as String? ?? '(sem nome)',
                style: const TextStyle(
                    fontWeight: FontWeight.w600,
                    color: AppColors.textPrimary)),
            const SizedBox(height: 6),
            Row(
              children: [
                if (old != null)
                  Text('${old.toStringAsFixed(2)}€',
                      style: const TextStyle(
                          decoration: TextDecoration.lineThrough,
                          color: AppColors.textSecondary)),
                if (old != null && neu != null)
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 6),
                    child: Icon(Icons.arrow_forward, size: 14),
                  ),
                if (neu != null)
                  Text('${neu.toStringAsFixed(2)}€',
                      style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          color: AppColors.textPrimary))
                else
                  Text('— sem preço ($status)',
                      style: const TextStyle(color: Colors.grey)),
                const Spacer(),
                if (div != null)
                  Text('${(div * 100).toStringAsFixed(0)}%',
                      style: TextStyle(
                          color: divColor, fontWeight: FontWeight.bold)),
              ],
            ),
            const SizedBox(height: 6),
            Wrap(
              spacing: 6,
              runSpacing: 4,
              children: [
                if (promo) _tag('promo→PVPR', Colors.indigo),
                if (r['needs_review'] == true) _tag('revisão', Colors.amber.shade800),
                if (applied) _tag('aplicado', Colors.purple),
                if (action == 'approved' && !applied)
                  _tag('aprovado', Colors.teal),
                if (action == 'rejected') _tag('rejeitado', Colors.red),
              ],
            ),
            if (!applied) ...[
              const SizedBox(height: 4),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: _busy ? null : () => _review([id], 'rejected'),
                    child: const Text('Rejeitar'),
                  ),
                  const SizedBox(width: 4),
                  FilledButton(
                    onPressed: (_busy || neu == null)
                        ? null
                        : () => _review([id], 'approved'),
                    child: const Text('Aprovar'),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _tag(String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(label,
          style: TextStyle(
              color: color, fontSize: 11.5, fontWeight: FontWeight.w600)),
    );
  }
}
