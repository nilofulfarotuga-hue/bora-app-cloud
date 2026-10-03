// Separador 11 — Checklist "Pronto para licenciamento": cada requisito legal
// com bolinha verde/amarela/vermelha, base legal, o que falta e o interruptor
// associado. Tocar → mudar o estado com nota.
// RPCs: admin_tvde_requisitos(), admin_tvde_requisito_estado(p_codigo, p_estado, p_o_que_falta).
import 'package:flutter/material.dart';

import '../../../config/app_colors.dart';
import '_comum.dart';

const List<(String, String)> kTvdeEstadosRequisito = [
  ('verde', 'Verde — cumprido'),
  ('amarelo', 'Amarelo — em curso / parcial'),
  ('vermelho', 'Vermelho — falta'),
];

Color tvdeCorRequisito(String? e) => switch (e) {
      'verde' => AppColors.success,
      'amarelo' => AppColors.warning,
      'vermelho' => AppColors.error,
      _ => AppColors.textSecondary,
    };

/// Agrupa por `area`, mantendo a ordem de chegada (o servidor ordena por `ordem`).
Map<String, List<Map<String, dynamic>>> tvdeAgruparPorArea(
    List<Map<String, dynamic>> reqs) {
  final out = <String, List<Map<String, dynamic>>>{};
  for (final r in reqs) {
    out.putIfAbsent(tvdeTexto(r['area']), () => []).add(r);
  }
  return out;
}

class TvdeChecklistTab extends StatefulWidget {
  const TvdeChecklistTab({super.key, this.rpc});

  final TvdeRpc? rpc;

  @override
  State<TvdeChecklistTab> createState() => _TvdeChecklistTabState();
}

class _TvdeChecklistTabState extends State<TvdeChecklistTab> with TvdeAGravar {
  bool _carregando = true;
  String? _erro;
  List<Map<String, dynamic>> _reqs = [];

  TvdeRpc get _rpc => widget.rpc ?? tvdeRpcPadrao;

  @override
  void initState() {
    super.initState();
    _carregar();
  }

  Future<void> _carregar() async {
    setState(() {
      _carregando = true;
      _erro = null;
    });
    try {
      final l = tvdeLista(await _rpc('admin_tvde_requisitos'));
      l.sort((a, b) => tvdeInt(a['ordem']).compareTo(tvdeInt(b['ordem'])));
      if (!mounted) return;
      setState(() {
        _reqs = l;
        _carregando = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _erro = tvdeErro(e);
        _carregando = false;
      });
    }
  }

  Future<void> _mudar(Map<String, dynamic> r) async {
    final res = await showDialog<(String, String)>(
      context: context,
      builder: (_) => _EstadoDialog(requisito: r),
    );
    if (res == null) return;
    final codigo = '${r['codigo']}';
    final ok = await correr('req-$codigo',
        () => _rpc('admin_tvde_requisito_estado',
            {'p_codigo': codigo, 'p_estado': res.$1, 'p_o_que_falta': res.$2}),
        ok: 'Requisito atualizado.');
    if (ok) _carregar();
  }

  Widget _linha(Map<String, dynamic> r) {
    final cor = tvdeCorRequisito(r['estado'] as String?);
    final codigo = '${r['codigo']}';
    return Card(
      key: Key('tvde-requisito-$codigo'),
      child: ListTile(
        onTap: aGravar.contains('req-$codigo') ? null : () => _mudar(r),
        leading: Container(
          key: Key('tvde-bolinha-$codigo-${r['estado']}'),
          width: 16,
          height: 16,
          margin: const EdgeInsets.only(top: 4),
          decoration: BoxDecoration(color: cor, shape: BoxShape.circle),
        ),
        title: Text(tvdeTexto(r['requisito']),
            style: const TextStyle(fontWeight: FontWeight.w600)),
        subtitle: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Base legal: ${tvdeTexto(r['base_legal'])}',
              style: const TextStyle(fontSize: 12)),
          if ((r['o_que_falta'] ?? '').toString().trim().isNotEmpty)
            Text('O que falta: ${r['o_que_falta']}',
                style: TextStyle(fontSize: 12, color: cor)),
          if (r['interruptor'] != null)
            Text('Interruptor: ${r['interruptor']}',
                style: const TextStyle(fontSize: 11, fontFamily: 'monospace')),
        ]),
        trailing: aGravar.contains('req-$codigo')
            ? const SizedBox(
                width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
            : const Icon(Icons.edit_outlined, size: 18),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return tvdeCorpo(
      carregando: _carregando,
      erro: _erro,
      tentar: _carregar,
      conteudo: () {
        final verdes = _reqs.where((r) => r['estado'] == 'verde').length;
        final amarelos = _reqs.where((r) => r['estado'] == 'amarelo').length;
        final vermelhos = _reqs.where((r) => r['estado'] == 'vermelho').length;
        final grupos = tvdeAgruparPorArea(_reqs);
        return RefreshIndicator(
          onRefresh: _carregar,
          child: ListView(
            key: const Key('tvde-checklist-lista'),
            padding: const EdgeInsets.all(12),
            children: [
              Text('$verdes verdes de ${_reqs.length}',
                  key: const Key('tvde-checklist-contagem'),
                  style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
              Text('$amarelos amarelos · $vermelhos vermelhos',
                  style: const TextStyle(color: AppColors.textSecondary)),
              const SizedBox(height: 4),
              const Text('Toque num requisito para mudar o estado e escrever o que falta.',
                  style: TextStyle(fontSize: 12)),
              const SizedBox(height: 8),
              if (_reqs.isEmpty) tvdeVazio('Nenhum requisito carregado.'),
              for (final g in grupos.entries) ...[
                Padding(
                  padding: const EdgeInsets.only(top: 12, bottom: 4),
                  child: Text(g.key,
                      style: const TextStyle(
                          fontWeight: FontWeight.w700, color: AppColors.primary)),
                ),
                for (final r in g.value) _linha(r),
              ],
            ],
          ),
        );
      },
    );
  }
}

class _EstadoDialog extends StatefulWidget {
  const _EstadoDialog({required this.requisito});

  final Map<String, dynamic> requisito;

  @override
  State<_EstadoDialog> createState() => _EstadoDialogState();
}

class _EstadoDialogState extends State<_EstadoDialog> {
  late String _estado;
  late final TextEditingController _nota;

  @override
  void initState() {
    super.initState();
    final e = widget.requisito['estado'] as String?;
    _estado = kTvdeEstadosRequisito.any((x) => x.$1 == e) ? e! : 'vermelho';
    _nota = TextEditingController(text: widget.requisito['o_que_falta'] as String? ?? '');
  }

  @override
  void dispose() {
    _nota.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(tvdeTexto(widget.requisito['requisito'])),
      content: SizedBox(
        width: 480,
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Wrap(spacing: 6, runSpacing: 6, children: [
            for (final e in kTvdeEstadosRequisito)
              ChoiceChip(
                key: Key('tvde-estado-${e.$1}'),
                avatar: CircleAvatar(radius: 7, backgroundColor: tvdeCorRequisito(e.$1)),
                label: Text(e.$2),
                selected: _estado == e.$1,
                onSelected: (_) => setState(() => _estado = e.$1),
              ),
          ]),
          TextField(
            key: const Key('tvde-requisito-nota'),
            controller: _nota,
            maxLines: 3,
            minLines: 1,
            decoration: const InputDecoration(labelText: 'O que falta (nota)'),
          ),
        ]),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancelar')),
        FilledButton(
          key: const Key('tvde-requisito-gravar'),
          onPressed: () => Navigator.pop(context, (_estado, _nota.text.trim())),
          child: const Text('Gravar'),
        ),
      ],
    );
  }
}
