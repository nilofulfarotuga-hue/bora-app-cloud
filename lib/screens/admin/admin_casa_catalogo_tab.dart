/// CASA — aba "Catálogo e preços" do hub (painel admin, PT-BR): ofícios
/// (ligar/desligar) e serviços (nome, modo, preço, unidade, quantidades,
/// duração, perguntas, ligar/desligar). Mudar preço volta a pôr os valores
/// como PROPOSTA até o Danilo dizer "autorizo" — quem decide é o servidor
/// (`admin_casa_guardar_servico`); o painel só avisa antes.
library;

import 'dart:convert';

import 'package:flutter/material.dart';

import '../../config/app_colors.dart';
import '../../config/app_spacing.dart';
import 'admin_casa_comum.dart';

/// Lê o JSON das perguntas escrito no painel. Vazio = sem perguntas.
({List<Map<String, dynamic>>? lista, String? erro}) casaLerPerguntas(
    String texto) {
  final t = texto.trim();
  if (t.isEmpty) return (lista: <Map<String, dynamic>>[], erro: null);
  Object? v;
  try {
    v = jsonDecode(t);
  } catch (_) {
    return (lista: null, erro: 'JSON inválido (confira aspas e vírgulas).');
  }
  if (v is! List) {
    return (lista: null, erro: 'Tem de ser uma lista: [ {...}, {...} ].');
  }
  final out = <Map<String, dynamic>>[];
  final ids = <String>{};
  for (final e in v) {
    if (e is! Map) {
      return (
        lista: null,
        erro: 'Cada pergunta é um objeto {"id", "texto", "tipo"}.'
      );
    }
    final m = Map<String, dynamic>.from(e);
    final id = '${m['id'] ?? ''}'.trim();
    final pergunta = '${m['texto'] ?? ''}'.trim();
    final tipo = '${m['tipo'] ?? 'texto'}'.trim();
    if (id.isEmpty || pergunta.isEmpty) {
      return (lista: null, erro: 'Cada pergunta precisa de "id" e "texto".');
    }
    if (!ids.add(id)) return (lista: null, erro: 'id repetido: "$id".');
    if (tipo != 'texto' && tipo != 'escolha') {
      return (
        lista: null,
        erro: '"tipo" tem de ser "texto" ou "escolha" (em "$id").'
      );
    }
    final opcoes = m['opcoes'];
    if (tipo == 'escolha' && (opcoes is! List || opcoes.isEmpty)) {
      return (lista: null, erro: '"escolha" precisa de "opcoes" (em "$id").');
    }
    out.add({
      'id': id,
      'texto': pergunta,
      'tipo': tipo,
      if (tipo == 'escolha' && opcoes is List)
        'opcoes': [for (final o in opcoes) '$o'],
    });
  }
  return (lista: out, erro: null);
}

/// Regras do serviço antes de mandar ao servidor. `null` = está bem.
String? casaValidarServico(Map<String, dynamic> d) {
  if ('${d['nome'] ?? ''}'.trim().isEmpty) return 'Falta o nome.';
  if ('${d['oficio'] ?? ''}'.trim().isEmpty) return 'Falta o ofício.';
  final modo = d['modo'];
  if (modo != 'fixo' && modo != 'hora' && modo != 'orcamento') {
    return 'Modo inválido.';
  }
  if (modo == 'orcamento' && d['preco_cents'] != null) {
    return 'Orçamento não tem preço fixo.';
  }
  if (modo != 'orcamento' && (d['preco_cents'] == null || casaInt(d['preco_cents']) <= 0)) {
    return 'Falta o preço (em euros).';
  }
  final min = casaDouble(d['min_quantidade']);
  final max = casaDouble(d['max_quantidade']);
  if (min <= 0) return 'A quantidade mínima tem de ser maior que 0.';
  if (max < min) return 'A quantidade máxima não pode ser menor que a mínima.';
  if (casaInt(d['duracao_min']) <= 0) return 'A duração tem de ser maior que 0.';
  return null;
}

/// A mudança mexe nos valores (preço, modo ou unidade)? Serviço novo com
/// preço também conta.
bool casaMudaValores(Map<String, dynamic>? original, Map<String, dynamic> novo) {
  if (original == null) return novo['preco_cents'] != null;
  return casaInt(original['preco_cents']) != casaInt(novo['preco_cents']) ||
      '${original['modo']}' != '${novo['modo']}' ||
      '${original['unidade']}' != '${novo['unidade']}';
}

class AdminCasaCatalogoTab extends StatefulWidget {
  const AdminCasaCatalogoTab({super.key, this.rpc});
  final ChamarRpcPainel? rpc;

  @override
  State<AdminCasaCatalogoTab> createState() => _AdminCasaCatalogoTabState();
}

class _AdminCasaCatalogoTabState extends State<AdminCasaCatalogoTab> {
  late Future<Map<String, dynamic>> _future = _load();
  bool _busy = false;

  ChamarRpcPainel get _rpc => casaRpc(widget.rpc);

  Future<Map<String, dynamic>> _load() async =>
      casaMapa(casaVerOk(await _rpc('admin_casa_catalogo', {})));

  Future<void> _refresh() async {
    setState(() {
      _future = _load();
    });
    await _future;
  }

  Future<void> _correr(
      String fn, Map<String, dynamic> params, String sucesso) async {
    if (_busy) return;
    setState(() => _busy = true);
    final ok = await casaExecutar(context, () => _rpc(fn, params), sucesso);
    if (!mounted) return;
    setState(() => _busy = false);
    if (ok) await _refresh();
  }

  Future<void> _ligarOficio(Map<String, dynamic> o, bool ligar) async {
    final nome = casaTexto(o['nome'] ?? o['codigo']);
    final fase2 = casaInt(o['fase'] ?? 1) >= 2;
    final ok = await casaConfirmar(
      context,
      titulo: ligar ? 'Ligar o ofício "$nome"?' : 'Desligar o ofício "$nome"?',
      texto: ligar
          ? (fase2
              ? 'Fase 2: os clientes passam a ver este ofício, mas só '
                  'profissionais com o documento DGEG/IMPIC APROVADO recebem '
                  'pedidos.'
              : 'Os clientes passam a ver os serviços deste ofício.')
          : 'Os clientes deixam de ver os serviços deste ofício. Pedidos já '
              'feitos continuam.',
      botao: ligar ? 'Ligar' : 'Desligar',
      perigo: !ligar,
    );
    if (ok == null) return;
    await _correr('admin_casa_guardar_oficio',
        {'p_codigo': o['codigo'], 'p_ativo': ligar},
        ligar ? 'Ofício ligado.' : 'Ofício desligado.');
  }

  Future<void> _editarServico(Map<String, dynamic>? s,
      List<Map<String, dynamic>> oficios, String? oficioNovo) async {
    final dados = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (_) => _EditarServicoDialog(
          servico: s, oficios: oficios, oficioNovo: oficioNovo),
    );
    if (dados == null || !mounted) return;
    if (casaMudaValores(s, dados)) {
      final ok = await casaConfirmar(
        context,
        titulo: 'Isto mexe no preço',
        texto: '$kCasaAvisoMudarPreco\n\nO servidor recusa pedidos reais de '
            'preço fixo até lá. Continuar?',
        botao: 'Guardar como proposta',
        perigo: true,
      );
      if (ok == null) return;
    }
    await _correr('admin_casa_guardar_servico', {
      'p_id': s?['id'],
      'p_dados': dados,
    }, s == null ? 'Serviço criado.' : 'Serviço guardado.');
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Map<String, dynamic>>(
      future: _future,
      builder: (context, snap) {
        if (snap.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snap.hasError) {
          return CasaErroCarregar(erro: snap.error!, onTentar: _refresh);
        }
        final m = snap.data ?? const <String, dynamic>{};
        final oficios = casaLista(m['oficios']);
        final servicos = casaLista(m['servicos']);
        final valores = CasaValores.fromJson(m['valores_autorizados']);
        oficios.sort((a, b) => casaInt(a['ordem']).compareTo(casaInt(b['ordem'])));
        servicos.sort((a, b) => casaInt(a['ordem']).compareTo(casaInt(b['ordem'])));
        return RefreshIndicator(
          onRefresh: _refresh,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(
                Spacing.md, Spacing.md, Spacing.md, Spacing.huge),
            children: [
              Container(
                key: const ValueKey('casa-catalogo-aviso-preco'),
                width: double.infinity,
                padding: const EdgeInsets.all(Spacing.md),
                margin: const EdgeInsets.only(bottom: Spacing.sm),
                decoration: BoxDecoration(
                  color: AppColors.warning.withValues(alpha: 0.18),
                  border: Border.all(color: AppColors.warning, width: 2),
                  borderRadius: BorderRadius.circular(Radii.md),
                ),
                child: const Text(
                  'ATENÇÃO: $kCasaAvisoMudarPreco',
                  style: TextStyle(fontWeight: FontWeight.w800, fontSize: 14),
                ),
              ),
              CasaAvisoValores(valores: valores),
              for (final o in oficios) ...[
                const SizedBox(height: Spacing.md),
                _cabecalhoOficio(o, oficios),
                for (final s
                    in servicos.where((s) => s['oficio'] == o['codigo']))
                  _servico(s, oficios),
              ],
            ],
          ),
        );
      },
    );
  }

  Widget _cabecalhoOficio(
      Map<String, dynamic> o, List<Map<String, dynamic>> oficios) {
    final ativo = o['ativo'] == true;
    final fase = casaInt(o['fase'] ?? 1);
    return Card(
      color: AppColors.primaryWash,
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.symmetric(
            horizontal: Spacing.md, vertical: Spacing.sm),
        child: Row(children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(casaTexto(o['nome']),
                    style: const TextStyle(
                        fontWeight: FontWeight.w800, fontSize: 15)),
                Text(
                  'Fase $fase'
                  '${o['documento_exigido'] == null ? '' : ' · exige ${casaDocumentoTipoPtBr(o['documento_exigido']?.toString())}'}'
                  ' · ${ativo ? 'ligado' : 'desligado'}',
                  style: const TextStyle(
                      fontSize: 12, color: AppColors.textSecondary),
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: 'Novo serviço neste ofício',
            onPressed: _busy
                ? null
                : () => _editarServico(null, oficios, '${o['codigo']}'),
            icon: const Icon(Icons.add_circle_outline),
          ),
          Switch(
            key: ValueKey('casa-oficio-ativo-${o['codigo']}'),
            value: ativo,
            onChanged: _busy ? null : (v) => _ligarOficio(o, v),
          ),
        ]),
      ),
    );
  }

  Widget _servico(Map<String, dynamic> s, List<Map<String, dynamic>> oficios) {
    final modo = s['modo']?.toString();
    final perguntas = casaLista(s['perguntas']);
    final ativo = s['ativo'] != false;
    final preco = modo == 'orcamento'
        ? 'Orçamento (sem preço fixo)'
        : '${casaEuroAdmin(s['preco_cents'])} ${casaUnidadePtBr(s['unidade']?.toString())}';
    return Card(
      margin: const EdgeInsets.only(top: Spacing.xs),
      child: ListTile(
        title: Text(casaTexto(s['nome']),
            style: TextStyle(
                fontWeight: FontWeight.w700,
                color: ativo ? AppColors.textPrimary : AppColors.textSubtle)),
        subtitle: Text(
          '${casaModoPtBr(modo)} · $preco\n'
          'Quantidade ${_num(s['min_quantidade'])} a ${_num(s['max_quantidade'])} · '
          '${casaInt(s['duracao_min'])} min · ${perguntas.length} pergunta${perguntas.length == 1 ? '' : 's'}'
          '${ativo ? '' : ' · DESLIGADO'}',
        ),
        isThreeLine: true,
        trailing: const Icon(Icons.edit_outlined),
        onTap: _busy ? null : () => _editarServico(s, oficios, null),
      ),
    );
  }

  static String _num(Object? v) {
    final d = casaDouble(v);
    return d % 1 == 0 ? '${d.round()}' : d.toString().replaceAll('.', ',');
  }
}

/// Edita (ou cria) um serviço. Devolve o `p_dados` para o servidor.
class _EditarServicoDialog extends StatefulWidget {
  const _EditarServicoDialog(
      {required this.servico, required this.oficios, this.oficioNovo});
  final Map<String, dynamic>? servico;
  final List<Map<String, dynamic>> oficios;
  final String? oficioNovo;

  @override
  State<_EditarServicoDialog> createState() => _EditarServicoDialogState();
}

class _EditarServicoDialogState extends State<_EditarServicoDialog> {
  Map<String, dynamic> get _s => widget.servico ?? const <String, dynamic>{};

  late String _oficio = '${_s['oficio'] ?? widget.oficioNovo ?? ''}';
  late String _modo = '${_s['modo'] ?? 'fixo'}';
  late String _unidade = '${_s['unidade'] ?? 'tarefa'}';
  late bool _ativo = _s['ativo'] != false;
  late final _nome = TextEditingController(text: '${_s['nome'] ?? ''}');
  late final _descricao =
      TextEditingController(text: '${_s['descricao'] ?? ''}');
  late final _preco =
      TextEditingController(text: casaEuroCampo(_s['preco_cents']));
  late final _min =
      TextEditingController(text: '${_s['min_quantidade'] ?? 1}');
  late final _max =
      TextEditingController(text: '${_s['max_quantidade'] ?? 10}');
  late final _duracao =
      TextEditingController(text: '${_s['duracao_min'] ?? 60}');
  late final _ordem = TextEditingController(text: '${_s['ordem'] ?? 0}');
  late final _perguntas = TextEditingController(
      text: const JsonEncoder.withIndent('  ')
          .convert(_s['perguntas'] is List ? _s['perguntas'] : const []));
  String? _erro;

  @override
  void dispose() {
    for (final c in [
      _nome,
      _descricao,
      _preco,
      _min,
      _max,
      _duracao,
      _ordem,
      _perguntas,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  double _dbl(TextEditingController c) =>
      double.tryParse(c.text.trim().replaceAll(',', '.')) ?? 0;

  void _guardar() {
    final perguntas = casaLerPerguntas(_perguntas.text);
    if (perguntas.erro != null) {
      setState(() => _erro = 'Perguntas: ${perguntas.erro}');
      return;
    }
    final dados = <String, dynamic>{
      'oficio': _oficio,
      'nome': _nome.text.trim(),
      'descricao': _descricao.text.trim(),
      'modo': _modo,
      'preco_cents': _modo == 'orcamento' ? null : casaCentimosDeTexto(_preco.text),
      'unidade': _unidade,
      'min_quantidade': _dbl(_min),
      'max_quantidade': _dbl(_max),
      'duracao_min': _dbl(_duracao).round(),
      'ordem': _dbl(_ordem).round(),
      'perguntas': perguntas.lista,
      'ativo': _ativo,
    };
    final erro = casaValidarServico(dados);
    if (erro != null) {
      setState(() => _erro = erro);
      return;
    }
    Navigator.pop(context, dados);
  }

  @override
  Widget build(BuildContext context) {
    final codigos = [for (final o in widget.oficios) '${o['codigo']}'];
    return AlertDialog(
      title: Text(widget.servico == null ? 'Novo serviço' : 'Editar serviço'),
      content: SizedBox(
        width: 520,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.all(Spacing.sm),
                decoration: BoxDecoration(
                  color: AppColors.warning.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(Radii.sm),
                ),
                child: const Text(kCasaAvisoMudarPreco,
                    style: TextStyle(fontWeight: FontWeight.w700)),
              ),
              const SizedBox(height: Spacing.sm),
              DropdownButtonFormField<String>(
                initialValue: codigos.contains(_oficio) ? _oficio : null,
                decoration: const InputDecoration(labelText: 'Ofício'),
                items: [
                  for (final o in widget.oficios)
                    DropdownMenuItem(
                        value: '${o['codigo']}',
                        child: Text(casaTexto(o['nome']))),
                ],
                onChanged: widget.servico == null
                    ? (v) => setState(() => _oficio = v ?? _oficio)
                    : null,
              ),
              TextField(
                controller: _nome,
                decoration: const InputDecoration(labelText: 'Nome'),
              ),
              TextField(
                controller: _descricao,
                minLines: 1,
                maxLines: 3,
                decoration: const InputDecoration(labelText: 'Descrição'),
              ),
              DropdownButtonFormField<String>(
                initialValue: _modo,
                decoration: const InputDecoration(labelText: 'Modo'),
                items: const [
                  DropdownMenuItem(value: 'fixo', child: Text('Preço fixo')),
                  DropdownMenuItem(value: 'hora', child: Text('Por hora')),
                  DropdownMenuItem(
                      value: 'orcamento', child: Text('Orçamento (com fotos)')),
                ],
                onChanged: (v) => setState(() => _modo = v ?? _modo),
              ),
              Row(children: [
                Expanded(
                  child: TextField(
                    controller: _preco,
                    enabled: _modo != 'orcamento',
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    decoration: const InputDecoration(
                        labelText: 'Preço (€)', suffixText: '€'),
                  ),
                ),
                const SizedBox(width: Spacing.sm),
                Expanded(
                  child: DropdownButtonFormField<String>(
                    initialValue: const ['tarefa', 'movel', 'hora']
                            .contains(_unidade)
                        ? _unidade
                        : 'tarefa',
                    decoration: const InputDecoration(labelText: 'Unidade'),
                    items: const [
                      DropdownMenuItem(
                          value: 'tarefa', child: Text('por tarefa')),
                      DropdownMenuItem(value: 'movel', child: Text('por móvel')),
                      DropdownMenuItem(value: 'hora', child: Text('por hora')),
                    ],
                    onChanged: (v) => setState(() => _unidade = v ?? _unidade),
                  ),
                ),
              ]),
              Row(children: [
                Expanded(
                  child: TextField(
                    controller: _min,
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    decoration:
                        const InputDecoration(labelText: 'Qtd. mínima'),
                  ),
                ),
                const SizedBox(width: Spacing.sm),
                Expanded(
                  child: TextField(
                    controller: _max,
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    decoration:
                        const InputDecoration(labelText: 'Qtd. máxima'),
                  ),
                ),
              ]),
              Row(children: [
                Expanded(
                  child: TextField(
                    controller: _duracao,
                    keyboardType: TextInputType.number,
                    decoration:
                        const InputDecoration(labelText: 'Duração (min)'),
                  ),
                ),
                const SizedBox(width: Spacing.sm),
                Expanded(
                  child: TextField(
                    controller: _ordem,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                        labelText: 'Ordem na lista'),
                  ),
                ),
              ]),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Ligado (os clientes veem)'),
                value: _ativo,
                onChanged: (v) => setState(() => _ativo = v),
              ),
              const SizedBox(height: Spacing.xs),
              const Text(
                'Perguntas ao cliente (JSON). Cada uma: {"id": "...", '
                '"texto": "...", "tipo": "texto"} ou "tipo": "escolha" com '
                '"opcoes": ["A", "B"].',
                style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
              ),
              const SizedBox(height: Spacing.xs),
              TextField(
                key: const ValueKey('casa-servico-perguntas'),
                controller: _perguntas,
                minLines: 4,
                maxLines: 12,
                style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
                decoration:
                    const InputDecoration(border: OutlineInputBorder()),
              ),
              if (_erro != null)
                Padding(
                  padding: const EdgeInsets.only(top: Spacing.sm),
                  child: Text(_erro!,
                      style: const TextStyle(
                          color: AppColors.error,
                          fontWeight: FontWeight.w700)),
                ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancelar')),
        FilledButton(onPressed: _guardar, child: const Text('Guardar')),
      ],
    );
  }
}
