// Separador 8 — Fiscalização (art. 20.º-A da Lei 45/2018, revista pela Lei
// 59/2026): acesso temporário das entidades fiscalizadoras (IMT, AMT, PSP,
// GNR, ACT...) aos dados estritamente necessários, e exportação imediata.
// RPCs: admin_tvde_fiscal_criar, admin_tvde_fiscal_lista,
//       admin_tvde_fiscal_revogar, admin_tvde_fiscal_exportar.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../config/app_colors.dart';
import '_comum.dart';

const String kTvdeTextoRegisto =
    'Cada acesso e cada exportação ficam registados (art. 20.º-A).';

String _eurosSemSimbolo(dynamic c) => tvdeEuros(c).replaceAll(' €', '');

/// Um CSV com secções (uma por bloco), separador ';'.
String tvdeFiscalCsv(Map<String, dynamic> d) {
  final b = StringBuffer();
  void secao(String titulo, List<String> cab, List<List<dynamic>> linhas) {
    b.writeln('# $titulo (${linhas.length})');
    b.write(tvdeCsv(cab, linhas));
    b.writeln();
    b.writeln();
  }

  final periodo = tvdeMapa(d['periodo']);
  final plataforma = tvdeMapa(d['plataforma']);
  secao('PLATAFORMA E PERÍODO', ['campo', 'valor'], [
    ['periodo_de', tvdeDataHora(periodo['de'])],
    ['periodo_ate', tvdeDataHora(periodo['ate'])],
    ['gerado_em', tvdeDataHora(d['gerado_em'])],
    for (final e in plataforma.entries) [e.key, '${e.value ?? ''}'],
  ]);
  secao('VIAGENS', [
    'codigo', 'pedida_em', 'inicio', 'fim', 'estado', 'origem', 'destino',
    'distancia_km', 'valor_eur', 'intermediacao_eur', 'pagamento', 'motorista', 'matricula'
  ], [
    for (final v in tvdeLista(d['viagens']))
      [
        v['codigo'], tvdeDataHora(v['pedida_em']), tvdeDataHora(v['inicio']),
        tvdeDataHora(v['fim']), v['estado'], v['origem'], v['destino'],
        '${v['distancia_km'] ?? ''}'.replaceAll('.', ','),
        _eurosSemSimbolo(v['valor_cents']), _eurosSemSimbolo(v['intermediacao_cents']),
        v['pagamento'], v['motorista'], v['matricula'],
      ],
  ]);
  secao('TEMPOS DE TRABALHO', ['motorista', 'inicio', 'fim', 'horas', 'fecho'], [
    for (final t in tvdeLista(d['tempos_trabalho']))
      [
        t['motorista'], tvdeDataHora(t['inicio']),
        t['fim'] == null ? 'em curso' : tvdeDataHora(t['fim']),
        '${t['horas'] ?? ''}'.replaceAll('.', ','), t['fecho'],
      ],
  ]);
  secao('DOCUMENTOS', [
    'motorista', 'cmtvde_numero', 'cmtvde_validade', 'carta_validade', 'carta_b_desde',
    'operador', 'operador_nipc', 'operador_licenca', 'operador_licenca_validade', 'veiculos'
  ], [
    for (final x in tvdeLista(d['documentos']))
      () {
        final o = tvdeMapa(x['operador']);
        return [
          x['motorista'], x['cmtvde_numero'], tvdeData(x['cmtvde_validade']),
          tvdeData(x['carta_validade']), tvdeData(x['carta_b_desde']),
          o['denominacao'], o['nipc'], o['licenca'], tvdeData(o['licenca_validade']),
          tvdeLista(x['veiculos'])
              .map((v) => '${v['matricula']} ${v['marca'] ?? ''} ${v['modelo'] ?? ''} '
                  '[registo ${v['registo_imt'] ?? '—'} até ${tvdeData(v['registo_validade'])}, '
                  'seguro até ${tvdeData(v['seguro_validade'])}, inspeção ${tvdeData(v['inspecao'])}, '
                  'dístico ${v['distico'] ?? '—'}, ${v['estado'] ?? ''}]')
              .join(' | '),
        ];
      }(),
  ]);
  secao('QUEIXAS', [
    'numero', 'data', 'canal', 'categoria', 'descricao', 'estado', 'diligencias',
    'resolucao', 'resolvida_em', 'motorista'
  ], [
    for (final q in tvdeLista(d['queixas']))
      [
        q['numero'], tvdeDataHora(q['data']), q['canal'], q['categoria'], q['descricao'],
        q['estado'],
        tvdeLista(q['diligencias'])
            .map((x) => '${tvdeDataHora(x['em'])}: ${x['texto']}')
            .join(' | '),
        q['resolucao'], tvdeDataHora(q['resolvida_em']), q['motorista'],
      ],
  ]);
  secao('BLOQUEIOS', ['data', 'tipo', 'motivo', 'ator', 'motorista'], [
    for (final e in tvdeLista(d['bloqueios']))
      [tvdeDataHora(e['data']), e['tipo'], e['motivo'], e['ator'], e['motorista']],
  ]);
  return b.toString();
}

/// Linhas do PDF: uma tabela única com o bloco na 1.ª coluna.
List<List<String>> tvdeFiscalPdfLinhas(Map<String, dynamic> d) => [
      for (final v in tvdeLista(d['viagens']))
        [
          'Viagem',
          tvdeDataHora(v['pedida_em']),
          tvdeTexto(v['motorista']),
          '${v['codigo']} · ${tvdeTexto(v['origem'])} → ${tvdeTexto(v['destino'])} · '
              '${tvdeEuros(v['valor_cents'])} (intermediação ${tvdeEuros(v['intermediacao_cents'])}) · '
              '${tvdeTexto(v['estado'])} · ${tvdeTexto(v['matricula'])}',
        ],
      for (final t in tvdeLista(d['tempos_trabalho']))
        [
          'Tempo de trabalho',
          tvdeDataHora(t['inicio']),
          tvdeTexto(t['motorista']),
          'até ${t['fim'] == null ? 'em curso' : tvdeDataHora(t['fim'])} · ${tvdeHoras(t['horas'])}',
        ],
      for (final x in tvdeLista(d['documentos']))
        [
          'Documentos',
          '—',
          tvdeTexto(x['motorista']),
          'CMTVDE ${tvdeTexto(x['cmtvde_numero'])} até ${tvdeData(x['cmtvde_validade'])} · '
              'carta até ${tvdeData(x['carta_validade'])} · operador '
              '${tvdeTexto(tvdeMapa(x['operador'])['denominacao'])} · veículos '
              '${tvdeLista(x['veiculos']).map((v) => v['matricula']).join(', ')}',
        ],
      for (final q in tvdeLista(d['queixas']))
        [
          'Queixa',
          tvdeDataHora(q['data']),
          tvdeTexto(q['motorista']),
          'N.º ${q['numero']} · ${tvdeTexto(q['categoria'])} · ${tvdeTexto(q['estado'])} · '
              '${tvdeTexto(q['descricao'])}',
        ],
      for (final e in tvdeLista(d['bloqueios']))
        [
          'Bloqueio',
          tvdeDataHora(e['data']),
          tvdeTexto(e['motorista']),
          '${tvdeTexto(e['tipo'])} · ${tvdeTexto(e['motivo'])} (${tvdeTexto(e['ator'])})',
        ],
    ];

class TvdeFiscalizacaoTab extends StatefulWidget {
  const TvdeFiscalizacaoTab({super.key, this.rpc, this.guardarCsv, this.guardarPdf});

  final TvdeRpc? rpc;
  final TvdeGuardarCsv? guardarCsv;
  final TvdeGuardarPdf? guardarPdf;

  @override
  State<TvdeFiscalizacaoTab> createState() => _TvdeFiscalizacaoTabState();
}

class _TvdeFiscalizacaoTabState extends State<TvdeFiscalizacaoTab> with TvdeAGravar {
  bool _carregando = true;
  String? _erro;
  List<Map<String, dynamic>> _acessos = [];
  List<(String, String)> _motoristas = [];
  List<(String, String)> _veiculos = [];
  List<(String, String)> _operadores = [];

  final _entidade = TextEditingController();
  final _agente = TextEditingController();
  final _finalidade = TextEditingController();
  final _desde = TextEditingController();
  final _ate = TextEditingController();
  String _motorista = '';
  String _veiculo = '';
  String _operador = '';
  double _horas = 24;
  Map<String, dynamic>? _ultimoAcesso;

  TvdeRpc get _rpc => widget.rpc ?? tvdeRpcPadrao;

  @override
  void initState() {
    super.initState();
    _carregar();
    _carregarEscolhas();
  }

  @override
  void dispose() {
    for (final c in [_entidade, _agente, _finalidade, _desde, _ate]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _carregar() async {
    setState(() {
      _carregando = true;
      _erro = null;
    });
    try {
      final l = tvdeLista(await _rpc('admin_tvde_fiscal_lista'));
      if (!mounted) return;
      setState(() {
        _acessos = l;
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

  /// As listas de escolha do escopo; se falharem, o formulário continua a
  /// funcionar (escopo = tudo).
  Future<void> _carregarEscolhas() async {
    try {
      final o = tvdeLista(await _rpc('admin_tvde_operadores'));
      final v = tvdeLista(await _rpc('admin_tvde_veiculos'));
      final m = tvdeLista(await _rpc('admin_tvde_motoristas_conformidade'));
      if (!mounted) return;
      setState(() {
        _operadores = [for (final x in o) ('${x['id']}', '${x['denominacao']}')];
        _veiculos = [for (final x in v) ('${x['id']}', '${x['matricula']}')];
        _motoristas = [for (final x in m) ('${x['user_id']}', tvdeTexto(x['nome']))];
      });
    } catch (_) {/* escolhas opcionais */}
  }

  Map<String, dynamic> _escopo() => {
        if (_motorista.isNotEmpty) 'driver_user_id': _motorista,
        if (_veiculo.isNotEmpty) 'vehicle_id': _veiculo,
        if (_operador.isNotEmpty) 'operator_id': _operador,
        if (_desde.text.trim().isNotEmpty) 'desde': _desde.text.trim(),
        if (_ate.text.trim().isNotEmpty) 'ate': _ate.text.trim(),
      };

  bool _datasOk() {
    final re = RegExp(r'^\d{4}-\d{2}-\d{2}$');
    for (final c in [_desde, _ate]) {
      if (c.text.trim().isNotEmpty && !re.hasMatch(c.text.trim())) {
        tvdeAvisar(context, 'Datas em AAAA-MM-DD.', erro: true);
        return false;
      }
    }
    return true;
  }

  Future<void> _gerar() async {
    if (_entidade.text.trim().length < 2 || _finalidade.text.trim().length < 3) {
      tvdeAvisar(context, 'Preencha a entidade e a finalidade.', erro: true);
      return;
    }
    if (!_datasOk()) return;
    await correr('gerar', () async {
      final r = tvdeMapa(await _rpc('admin_tvde_fiscal_criar', {
        'p_entidade': _entidade.text.trim(),
        'p_agente': _agente.text.trim(),
        'p_finalidade': _finalidade.text.trim(),
        'p_escopo': _escopo(),
        'p_horas': _horas.round(),
      }));
      setState(() => _ultimoAcesso = r);
    }, ok: 'Acesso criado.');
    _carregar();
  }

  Future<void> _revogar(Map<String, dynamic> a) async {
    final sim = await tvdeConfirmar(context,
        titulo: 'Revogar acesso?',
        texto: 'O código de ${tvdeTexto(a['entidade'])} deixa de funcionar já.',
        perigo: true);
    if (!sim) return;
    final ok = await correr('rev-${a['id']}',
        () => _rpc('admin_tvde_fiscal_revogar', {'p_id': a['id']}),
        ok: 'Acesso revogado.');
    if (ok) _carregar();
  }

  Future<void> _exportar({required bool pdf}) async {
    if (!_datasOk()) return;
    await correr(pdf ? 'exp-pdf' : 'exp-csv', () async {
      final d = tvdeMapa(await _rpc('admin_tvde_fiscal_exportar', {'p_escopo': _escopo()}));
      final carimbo = tvdeHoje();
      if (pdf) {
        final periodo = tvdeMapa(d['periodo']);
        await (widget.guardarPdf ?? tvdeGuardarPdfPadrao)(
          'Bora TVDE — dados para fiscalização',
          ['Bloco', 'Data', 'Motorista', 'Detalhe'],
          tvdeFiscalPdfLinhas(d),
          'Período ${tvdeDataHora(periodo['de'])} a ${tvdeDataHora(periodo['ate'])} · '
              'gerado ${tvdeDataHora(d['gerado_em'])} · $kTvdeTextoRegisto',
        );
      } else {
        await (widget.guardarCsv ?? tvdeGuardarCsvPadrao)(
            'tvde_fiscalizacao_$carimbo.csv', tvdeFiscalCsv(d));
      }
    }, ok: 'Exportado (fica registado).');
  }

  void _copiar(String texto) {
    Clipboard.setData(ClipboardData(text: texto));
    tvdeAvisar(context, 'Copiado.');
  }

  Widget _escolha(String rotulo, String valor, List<(String, String)> opcoes,
          ValueChanged<String> mudar) =>
      SizedBox(
        width: 260,
        child: DropdownButtonFormField<String>(
          initialValue: opcoes.any((o) => o.$1 == valor) ? valor : '',
          isExpanded: true,
          decoration: InputDecoration(labelText: rotulo, isDense: true),
          items: [
            const DropdownMenuItem(value: '', child: Text('— todos —')),
            for (final o in opcoes)
              DropdownMenuItem(value: o.$1, child: Text(o.$2, overflow: TextOverflow.ellipsis)),
          ],
          onChanged: (v) => setState(() => mudar(v ?? '')),
        ),
      );

  Widget _campoData(String rotulo, TextEditingController c) => SizedBox(
        width: 170,
        child: TextField(
          controller: c,
          decoration: InputDecoration(
            labelText: rotulo,
            isDense: true,
            hintText: 'AAAA-MM-DD',
            suffixIcon: IconButton(
              icon: const Icon(Icons.calendar_month, size: 18),
              onPressed: () async {
                final d = await showDatePicker(
                    context: context,
                    initialDate: DateTime.tryParse(c.text) ?? DateTime.now(),
                    firstDate: DateTime(2020),
                    lastDate: DateTime(2100));
                if (d != null) {
                  c.text = '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
                }
              },
            ),
          ),
        ),
      );

  Widget _formulario() => Card(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('Gerar acesso temporário',
                style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
            const SizedBox(height: 8),
            TextField(
                key: const Key('tvde-fiscal-entidade'),
                controller: _entidade,
                decoration: const InputDecoration(
                    labelText: 'Entidade * (ex.: IMT, AMT, PSP, GNR, ACT)')),
            TextField(
                controller: _agente,
                decoration: const InputDecoration(labelText: 'Agente (nome / n.º de identificação)')),
            TextField(
                key: const Key('tvde-fiscal-finalidade'),
                controller: _finalidade,
                decoration: const InputDecoration(labelText: 'Finalidade * (porque precisa dos dados)')),
            const SizedBox(height: 8),
            const Text('Escopo (vazio = tudo; o período por defeito é os últimos 30 dias):',
                style: TextStyle(fontSize: 12)),
            const SizedBox(height: 4),
            Wrap(spacing: 8, runSpacing: 8, children: [
              _escolha('Motorista', _motorista, _motoristas, (v) => _motorista = v),
              _escolha('Veículo', _veiculo, _veiculos, (v) => _veiculo = v),
              _escolha('Operador', _operador, _operadores, (v) => _operador = v),
              _campoData('Desde', _desde),
              _campoData('Até', _ate),
            ]),
            const SizedBox(height: 8),
            Text('Validade do acesso: ${_horas.round()} hora(s)'),
            Slider(
              value: _horas,
              min: 1,
              max: 168,
              divisions: 167,
              label: '${_horas.round()} h',
              onChanged: (v) => setState(() => _horas = v),
            ),
            Wrap(spacing: 8, runSpacing: 8, children: [
              FilledButton.icon(
                key: const Key('tvde-fiscal-gerar'),
                onPressed: aGravar.contains('gerar') ? null : _gerar,
                icon: const Icon(Icons.key),
                label: const Text('Gerar acesso'),
              ),
              tvdeBotao(
                  rotulo: 'Exportar agora (CSV)',
                  icone: Icons.table_view,
                  aGravar: aGravar.contains('exp-csv'),
                  onPressed: () => _exportar(pdf: false)),
              tvdeBotao(
                  rotulo: 'Exportar agora (PDF)',
                  icone: Icons.picture_as_pdf,
                  aGravar: aGravar.contains('exp-pdf'),
                  onPressed: () => _exportar(pdf: true)),
            ]),
            if (_ultimoAcesso != null) ...[
              const SizedBox(height: 12),
              Container(
                key: const Key('tvde-fiscal-resultado'),
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                    color: AppColors.success.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: AppColors.success)),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('Expira ${tvdeDataHora(_ultimoAcesso!['expira_em'])}',
                      style: const TextStyle(fontWeight: FontWeight.w600)),
                  Row(children: [
                    Expanded(child: SelectableText('Código: ${_ultimoAcesso!['codigo']}')),
                    IconButton(
                        tooltip: 'Copiar código',
                        icon: const Icon(Icons.copy, size: 18),
                        onPressed: () => _copiar('${_ultimoAcesso!['codigo']}')),
                  ]),
                  Row(children: [
                    Expanded(child: SelectableText('${_ultimoAcesso!['url']}')),
                    IconButton(
                        tooltip: 'Copiar link',
                        icon: const Icon(Icons.copy, size: 18),
                        onPressed: () => _copiar('${_ultimoAcesso!['url']}')),
                  ]),
                ]),
              ),
            ],
          ]),
        ),
      );

  String _escopoTexto(dynamic e) {
    final m = tvdeMapa(e);
    if (m.isEmpty) return 'tudo';
    String nome(List<(String, String)> l, dynamic id) {
      for (final x in l) {
        if (x.$1 == '$id') return x.$2;
      }
      return '$id'.length > 8 ? '${'$id'.substring(0, 8)}…' : '$id';
    }

    return [
      if (m['driver_user_id'] != null) 'motorista ${nome(_motoristas, m['driver_user_id'])}',
      if (m['vehicle_id'] != null) 'veículo ${nome(_veiculos, m['vehicle_id'])}',
      if (m['operator_id'] != null) 'operador ${nome(_operadores, m['operator_id'])}',
      if (m['desde'] != null) 'desde ${tvdeData(m['desde'])}',
      if (m['ate'] != null) 'até ${tvdeData(m['ate'])}',
    ].join(' · ');
  }

  Widget _acesso(Map<String, dynamic> a) {
    final ativo = tvdeBool(a['ativo']) == true;
    return Card(
      child: ListTile(
        title: Row(children: [
          Expanded(
              child: Text('${tvdeTexto(a['entidade'])} · ${tvdeTexto(a['agente'])}',
                  style: const TextStyle(fontWeight: FontWeight.w700))),
          ativo
              ? tvdeChip('Ativo', AppColors.success)
              : tvdeChip(a['revogado_em'] != null ? 'Revogado' : 'Expirado',
                  AppColors.textSecondary),
        ]),
        subtitle: Text('${tvdeTexto(a['finalidade'])}\nEscopo: ${_escopoTexto(a['escopo'])}\n'
            'Criado ${tvdeDataHora(a['criado_em'])} · expira ${tvdeDataHora(a['expira_em'])} · '
            '${tvdeInt(a['consultas'])} consulta(s)'
            '${a['ultima_consulta'] != null ? ' (última ${tvdeDataHora(a['ultima_consulta'])})' : ''}'),
        isThreeLine: true,
        trailing: ativo
            ? tvdeBotao(
                rotulo: 'Revogar',
                icone: Icons.block,
                cor: AppColors.error,
                aGravar: aGravar.contains('rev-${a['id']}'),
                onPressed: () => _revogar(a))
            : null,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      onRefresh: _carregar,
      child: ListView(padding: const EdgeInsets.all(12), children: [
        tvdeNota('$kTvdeTextoRegisto A entidade abre o link com o código, sem conta '
            'Bora, e só vê os dados necessários: viagens, tempos de trabalho, '
            'documentos, queixas e bloqueios — nunca nome, telefone ou email do passageiro.',
            icone: Icons.policy_outlined),
        _formulario(),
        const SizedBox(height: 12),
        const Text('Acessos criados', style: TextStyle(fontWeight: FontWeight.w700)),
        const SizedBox(height: 8),
        tvdeCorpo(
          carregando: _carregando,
          erro: _erro,
          tentar: _carregar,
          conteudo: () => Column(children: [
            if (_acessos.isEmpty) tvdeVazio('Nenhum acesso criado ainda.'),
            for (final a in _acessos) _acesso(a),
          ]),
        ),
      ]),
    );
  }
}
