// Separador 7 — Queixas TVDE (livro de reclamações da plataforma). Filtro por
// estado; abrir uma queixa → diligência, resposta (vai por notificação ao
// cliente), resolução e novo estado. Mostra o prazo de retenção.
// RPCs: admin_tvde_queixas(p_estado),
//       admin_tvde_queixa_atualizar(p_id, p_estado, p_diligencia, p_resposta, p_resolucao).
import 'package:flutter/material.dart';

import '../../../config/app_colors.dart';
import '_comum.dart';

const List<(String, String)> kTvdeEstadosQueixa = [
  ('recebida', 'Recebida'),
  ('em_analise', 'Em análise'),
  ('respondida', 'Respondida'),
  ('resolvida', 'Resolvida'),
  ('arquivada', 'Arquivada'),
];

const Map<String, String> kTvdeCategoriaQueixa = {
  'preco': 'Preço',
  'comportamento': 'Comportamento',
  'seguranca': 'Segurança',
  'veiculo': 'Veículo',
  'percurso': 'Percurso',
  'pagamento': 'Pagamento',
  'acessibilidade': 'Acessibilidade',
  'dados_pessoais': 'Dados pessoais',
  'outro': 'Outro',
};

String tvdeRotuloEstadoQueixa(String? e) {
  for (final x in kTvdeEstadosQueixa) {
    if (x.$1 == e) return x.$2;
  }
  return e ?? '—';
}

Color tvdeCorEstadoQueixa(String? e) => switch (e) {
      'recebida' => AppColors.error,
      'em_analise' => AppColors.warning,
      'respondida' => AppColors.info,
      'resolvida' => AppColors.success,
      _ => AppColors.textSecondary,
    };

class TvdeQueixasTab extends StatefulWidget {
  const TvdeQueixasTab({super.key, this.rpc});

  final TvdeRpc? rpc;

  @override
  State<TvdeQueixasTab> createState() => _TvdeQueixasTabState();
}

class _TvdeQueixasTabState extends State<TvdeQueixasTab> with TvdeAGravar {
  bool _carregando = true;
  String? _erro;
  List<Map<String, dynamic>> _queixas = [];
  String? _filtro; // null = todas

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
      final l = tvdeLista(await _rpc('admin_tvde_queixas', {'p_estado': _filtro}));
      if (!mounted) return;
      setState(() {
        _queixas = l;
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

  Future<void> _abrir(Map<String, dynamic> q) async {
    final r = await showDialog<Map<String, String>>(
      context: context,
      builder: (_) => _QueixaDialog(queixa: q),
    );
    if (r == null) return;
    final ok = await correr('q-${q['id']}',
        () => _rpc('admin_tvde_queixa_atualizar', {
              'p_id': q['id'],
              'p_estado': r['estado'],
              'p_diligencia': r['diligencia'],
              'p_resposta': r['resposta'],
              'p_resolucao': r['resolucao'],
            }),
        ok: (r['resposta'] ?? '').isNotEmpty
            ? 'Queixa atualizada; a resposta foi enviada ao cliente por notificação.'
            : 'Queixa atualizada.');
    if (ok) _carregar();
  }

  Widget _cartao(Map<String, dynamic> q) {
    final estado = q['estado'] as String?;
    return Card(
      key: Key('tvde-queixa-${q['id']}'),
      child: ListTile(
        onTap: aGravar.contains('q-${q['id']}') ? null : () => _abrir(q),
        title: Row(children: [
          Expanded(
            child: Text(
                'N.º ${tvdeTexto(q['numero'])} · ${kTvdeCategoriaQueixa[q['categoria']] ?? tvdeTexto(q['categoria'])}',
                style: const TextStyle(fontWeight: FontWeight.w700)),
          ),
          tvdeChip(tvdeRotuloEstadoQueixa(estado), tvdeCorEstadoQueixa(estado)),
        ]),
        subtitle: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(tvdeTexto(q['descricao']), maxLines: 2, overflow: TextOverflow.ellipsis),
          Text('${tvdeDataHora(q['created_at'])} · canal ${tvdeTexto(q['canal'])} · '
              'autor ${tvdeTexto(q['autor'])} · motorista ${tvdeTexto(q['motorista'])} · '
              'viagem ${tvdeTexto(q['viagem'])}',
              style: const TextStyle(fontSize: 12)),
          Text('Guardar até ${tvdeData(q['prazo_retencao'])} (prazo de retenção)',
              style: const TextStyle(fontSize: 12, color: AppColors.textSecondary)),
        ]),
        trailing: aGravar.contains('q-${q['id']}')
            ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
            : const Icon(Icons.chevron_right),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(children: [
      SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
        child: Row(children: [
          ChoiceChip(
            label: const Text('Todas'),
            selected: _filtro == null,
            onSelected: (_) {
              setState(() => _filtro = null);
              _carregar();
            },
          ),
          for (final e in kTvdeEstadosQueixa)
            Padding(
              padding: const EdgeInsets.only(left: 6),
              child: ChoiceChip(
                label: Text(e.$2),
                selected: _filtro == e.$1,
                onSelected: (_) {
                  setState(() => _filtro = e.$1);
                  _carregar();
                },
              ),
            ),
        ]),
      ),
      Expanded(
        child: tvdeCorpo(
          carregando: _carregando,
          erro: _erro,
          tentar: _carregar,
          conteudo: () => RefreshIndicator(
            onRefresh: _carregar,
            child: ListView(padding: const EdgeInsets.all(12), children: [
              if (_queixas.isEmpty) tvdeVazio('Nenhuma queixa neste estado.'),
              for (final q in _queixas) _cartao(q),
            ]),
          ),
        ),
      ),
    ]);
  }
}

class _QueixaDialog extends StatefulWidget {
  const _QueixaDialog({required this.queixa});

  final Map<String, dynamic> queixa;

  @override
  State<_QueixaDialog> createState() => _QueixaDialogState();
}

class _QueixaDialogState extends State<_QueixaDialog> {
  late String _estado;
  final _dil = TextEditingController();
  late final TextEditingController _resp;
  late final TextEditingController _resol;

  @override
  void initState() {
    super.initState();
    final e = widget.queixa['estado'] as String?;
    _estado = kTvdeEstadosQueixa.any((x) => x.$1 == e) ? e! : 'em_analise';
    _resp = TextEditingController();
    _resol = TextEditingController(text: widget.queixa['resolucao'] as String? ?? '');
  }

  @override
  void dispose() {
    _dil.dispose();
    _resp.dispose();
    _resol.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final q = widget.queixa;
    final dils = q['diligencias'] is List ? q['diligencias'] as List : const [];
    return AlertDialog(
      title: Text('Queixa n.º ${tvdeTexto(q['numero'])}'),
      content: SizedBox(
        width: 560,
        child: SingleChildScrollView(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
            Text(tvdeTexto(q['descricao'])),
            const SizedBox(height: 6),
            Text('Categoria: ${kTvdeCategoriaQueixa[q['categoria']] ?? tvdeTexto(q['categoria'])} · '
                'Canal: ${tvdeTexto(q['canal'])} · Contacto: ${tvdeTexto(q['contacto'])}',
                style: const TextStyle(fontSize: 12)),
            Text('Recebida ${tvdeDataHora(q['created_at'])} · '
                'Respondida ${tvdeDataHora(q['respondida_em'])} · Resolvida ${tvdeDataHora(q['resolvida_em'])}',
                style: const TextStyle(fontSize: 12)),
            Text('Prazo de retenção: guardar até ${tvdeData(q['prazo_retencao'])}',
                style: const TextStyle(fontSize: 12, color: AppColors.textSecondary)),
            if (q['resposta'] != null) ...[
              const SizedBox(height: 6),
              Text('Resposta já enviada: ${q['resposta']}', style: const TextStyle(fontSize: 12)),
            ],
            const SizedBox(height: 8),
            const Text('Diligências (o que já se fez):', style: TextStyle(fontWeight: FontWeight.w600)),
            if (dils.isEmpty) const Text('— nenhuma ainda —', style: TextStyle(fontSize: 12)),
            for (final d in dils)
              Text('• ${d is Map ? '${tvdeDataHora(d['em'])}: ${d['texto']}' : '$d'}',
                  style: const TextStyle(fontSize: 12)),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              initialValue: _estado,
              decoration: const InputDecoration(labelText: 'Estado'),
              items: [
                for (final e in kTvdeEstadosQueixa)
                  DropdownMenuItem(value: e.$1, child: Text(e.$2)),
              ],
              onChanged: (v) => setState(() => _estado = v ?? _estado),
            ),
            TextField(
              key: const Key('tvde-queixa-diligencia'),
              controller: _dil,
              maxLines: 3,
              minLines: 1,
              decoration: const InputDecoration(labelText: 'Nova diligência (fica no histórico)'),
            ),
            TextField(
              key: const Key('tvde-queixa-resposta'),
              controller: _resp,
              maxLines: 4,
              minLines: 1,
              decoration: const InputDecoration(
                  labelText: 'Resposta ao cliente',
                  helperText: 'Vai por notificação ao cliente (primeiros 180 caracteres).'),
            ),
            TextField(
              key: const Key('tvde-queixa-resolucao'),
              controller: _resol,
              maxLines: 3,
              minLines: 1,
              decoration: const InputDecoration(labelText: 'Resolução'),
            ),
          ]),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancelar')),
        FilledButton(
          onPressed: () => Navigator.pop(context, {
            'estado': _estado,
            'diligencia': _dil.text.trim(),
            'resposta': _resp.text.trim(),
            'resolucao': _resol.text.trim(),
          }),
          child: const Text('Gravar'),
        ),
      ],
    );
  }
}
