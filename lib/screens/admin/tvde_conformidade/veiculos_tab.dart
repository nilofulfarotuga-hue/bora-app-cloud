// Separador 3 — Veículos TVDE. Lista (estado, operador, motoristas), cria e
// edita todos os campos, aprova/suspende/rejeita com motivo e associa ou
// desassocia motoristas.
// RPCs: admin_tvde_veiculos, admin_tvde_veiculo_guardar(p),
//       admin_tvde_veiculo_estado(p_id, p_estado, p_motivo),
//       admin_tvde_associar_veiculo(p_driver, p_vehicle, p_ativo),
//       admin_tvde_operadores (escolha do operador),
//       admin_tvde_motoristas_conformidade (escolha do motorista).
import 'package:flutter/material.dart';

import '../../../config/app_colors.dart';
import '_comum.dart';

List<TvdeCampo> tvdeCamposVeiculo(
        {required bool novo, required List<(String, String)> operadores}) =>
    [
      if (novo)
        TvdeCampo('matricula', 'Matrícula',
            obrigatorio: true,
            ajuda: 'Ex.: AA-00-BB (a matrícula não se muda depois de criada)',
            validar: (v) => v.replaceAll(RegExp(r'[^A-Za-z0-9]'), '').length >= 4
                ? null
                : 'Matrícula inválida.'),
      TvdeCampo('operator_id', 'Operador TVDE',
          tipo: TvdeCampoTipo.escolha, opcoes: operadores),
      const TvdeCampo('marca', 'Marca'),
      const TvdeCampo('modelo', 'Modelo'),
      const TvdeCampo('cor', 'Cor'),
      TvdeCampo('ano_fabrico', 'Ano de fabrico',
          tipo: TvdeCampoTipo.numero,
          validar: (v) {
            final n = int.tryParse(v) ?? 0;
            return n >= 1980 && n <= 2100 ? null : 'Entre 1980 e 2100.';
          }),
      const TvdeCampo('primeira_matricula_em', 'Data da 1.ª matrícula',
          tipo: TvdeCampoTipo.data,
          ajuda: 'AAAA-MM-DD — a lei limita a idade do carro'),
      TvdeCampo('lugares', 'Lugares (máx. 9, com o motorista)',
          tipo: TvdeCampoTipo.numero,
          validar: (v) {
            final n = int.tryParse(v) ?? 0;
            return n >= 1 && n <= 9 ? null : 'Entre 1 e 9.';
          }),
      const TvdeCampo('eletrico', 'Elétrico', tipo: TvdeCampoTipo.sim),
      const TvdeCampo('registo_imt_numero', 'Registo IMT n.º (veículo TVDE)'),
      const TvdeCampo('registo_imt_validade', 'Validade do registo IMT',
          tipo: TvdeCampoTipo.data),
      const TvdeCampo('seguro_seguradora', 'Seguradora'),
      const TvdeCampo('seguro_apolice', 'Apólice n.º'),
      const TvdeCampo('seguro_validade', 'Validade do seguro',
          tipo: TvdeCampoTipo.data),
      const TvdeCampo('seguro_acidentes_pessoais',
          'Seguro de acidentes pessoais (passageiros)',
          tipo: TvdeCampoTipo.sim),
      const TvdeCampo('inspecao_proxima', 'Próxima inspeção',
          tipo: TvdeCampoTipo.data),
      const TvdeCampo('distico_id', 'Dístico TVDE (identificação no vidro)'),
      const TvdeCampo('adaptado_mobilidade_reduzida',
          'Adaptado a mobilidade reduzida',
          tipo: TvdeCampoTipo.sim),
    ];

class TvdeVeiculosTab extends StatefulWidget {
  const TvdeVeiculosTab({super.key, this.rpc});

  final TvdeRpc? rpc;

  @override
  State<TvdeVeiculosTab> createState() => _TvdeVeiculosTabState();
}

class _TvdeVeiculosTabState extends State<TvdeVeiculosTab> with TvdeAGravar {
  bool _carregando = true;
  String? _erro;
  List<Map<String, dynamic>> _veiculos = [];
  List<(String, String)> _operadores = [];
  String _busca = '';

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
      final v = tvdeLista(await _rpc('admin_tvde_veiculos'));
      final o = tvdeLista(await _rpc('admin_tvde_operadores'));
      if (!mounted) return;
      setState(() {
        _veiculos = v;
        _operadores = [
          for (final x in o)
            ('${x['id']}', '${x['denominacao']} (${tvdeEstado(x['estado'] as String?).$1})'),
        ];
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

  Future<void> _editar([Map<String, dynamic>? v]) async {
    final r = await tvdeFormulario(context,
        titulo: v == null ? 'Novo veículo TVDE' : 'Editar ${v['matricula']}',
        campos: tvdeCamposVeiculo(novo: v == null, operadores: _operadores),
        inicial: v ?? const {});
    if (r == null) return;
    if (v != null) r['id'] = v['id'];
    final ok = await correr('guardar-${v?['id'] ?? 'novo'}',
        () => _rpc('admin_tvde_veiculo_guardar', {'p': r}),
        ok: 'Veículo gravado.');
    if (ok) _carregar();
  }

  Future<void> _estado(Map<String, dynamic> v, String estado, String verbo) async {
    final motivo = await tvdePedirTexto(context,
        titulo: '$verbo o veículo ${v['matricula']}?',
        explicacao: 'Fica registado na auditoria. Os motoristas associados '
            'são reavaliados na hora.');
    if (motivo == null) return;
    final ok = await correr('estado-${v['id']}',
        () => _rpc('admin_tvde_veiculo_estado',
            {'p_id': v['id'], 'p_estado': estado, 'p_motivo': motivo}),
        ok: 'Veículo: $estado.');
    if (ok) _carregar();
  }

  Future<void> _associar(Map<String, dynamic> v) async {
    List<Map<String, dynamic>> motoristas;
    try {
      motoristas = tvdeLista(await _rpc('admin_tvde_motoristas_conformidade'));
    } catch (e) {
      if (mounted) tvdeAvisar(context, tvdeErro(e), erro: true);
      return;
    }
    if (!mounted) return;
    final escolhido = await showDialog<String>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: Text('Associar motorista a ${v['matricula']}'),
        children: [
          if (motoristas.isEmpty)
            const Padding(
                padding: EdgeInsets.all(16),
                child: Text('Nenhum motorista TVDE encontrado.')),
          for (final m in motoristas)
            SimpleDialogOption(
              onPressed: () => Navigator.pop(ctx, '${m['user_id']}'),
              child: Text('${tvdeTexto(m['nome'])} · ${tvdeTexto(m['telefone'])}'),
            ),
        ],
      ),
    );
    if (escolhido == null) return;
    final ok = await correr('assoc-${v['id']}',
        () => _rpc('admin_tvde_associar_veiculo',
            {'p_driver': escolhido, 'p_vehicle': v['id'], 'p_ativo': true}),
        ok: 'Motorista associado.');
    if (ok) _carregar();
  }

  Future<void> _desassociar(Map<String, dynamic> v, Map<String, dynamic> m) async {
    final sim = await tvdeConfirmar(context,
        titulo: 'Desassociar?',
        texto: 'Tirar ${tvdeTexto(m['nome'])} do veículo ${v['matricula']}? '
            'Sem veículo aprovado ativo, o motorista fica impedido quando o mestre estiver ligado.');
    if (!sim) return;
    final ok = await correr('assoc-${v['id']}-${m['user_id']}',
        () => _rpc('admin_tvde_associar_veiculo',
            {'p_driver': m['user_id'], 'p_vehicle': v['id'], 'p_ativo': false}),
        ok: 'Motorista desassociado.');
    if (ok) _carregar();
  }

  Widget _cartao(Map<String, dynamic> v) {
    final (rot, cor) = tvdeEstado(v['estado'] as String?);
    final id = v['id'];
    final ocupado = aGravar.contains('estado-$id');
    final motoristas = tvdeLista(v['motoristas']);
    return Card(
      key: Key('tvde-veiculo-$id'),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Expanded(
              child: Text(
                  '${tvdeTexto(v['matricula'])} · ${tvdeTexto(v['marca'])} ${v['modelo'] ?? ''}',
                  style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
            ),
            tvdeChip(rot, cor),
          ]),
          const SizedBox(height: 4),
          Text('Operador: ${tvdeTexto(v['operador'])} · Cor ${tvdeTexto(v['cor'])} · '
              'Ano ${tvdeTexto(v['ano_fabrico'])} · 1.ª matrícula ${tvdeData(v['primeira_matricula_em'])}',
              style: const TextStyle(fontSize: 12)),
          Text('${tvdeTexto(v['lugares'])} lugares'
              '${tvdeBool(v['eletrico']) == true ? ' · elétrico' : ''}'
              '${tvdeBool(v['adaptado_mobilidade_reduzida']) == true ? ' · adaptado a mobilidade reduzida' : ''}'
              ' · Dístico ${tvdeTexto(v['distico_id'])}',
              style: const TextStyle(fontSize: 12)),
          Text('Registo IMT ${tvdeTexto(v['registo_imt_numero'])} até ${tvdeData(v['registo_imt_validade'])} · '
              'Seguro ${tvdeTexto(v['seguro_seguradora'])} até ${tvdeData(v['seguro_validade'])}'
              '${tvdeBool(v['seguro_acidentes_pessoais']) == true ? ' (c/ acidentes pessoais)' : ''} · '
              'Inspeção ${tvdeData(v['inspecao_proxima'])}',
              style: const TextStyle(fontSize: 12)),
          if (v['estado_motivo'] != null)
            Text('Motivo: ${v['estado_motivo']}', style: TextStyle(fontSize: 12, color: cor)),
          const SizedBox(height: 6),
          Wrap(spacing: 6, runSpacing: 6, children: [
            if (motoristas.isEmpty)
              const Text('Sem motoristas associados.',
                  style: TextStyle(fontSize: 12, color: AppColors.textSecondary)),
            for (final m in motoristas)
              InputChip(
                label: Text(
                    '${tvdeTexto(m['nome'])}${tvdeBool(m['ativo']) == true ? '' : ' (inativo)'}'),
                onDeleted: tvdeBool(m['ativo']) == true &&
                        !aGravar.contains('assoc-$id-${m['user_id']}')
                    ? () => _desassociar(v, m)
                    : null,
                deleteButtonTooltipMessage: 'Desassociar',
              ),
          ]),
          const SizedBox(height: 8),
          Wrap(spacing: 8, runSpacing: 8, children: [
            tvdeBotao(
                rotulo: 'Editar',
                icone: Icons.edit,
                aGravar: aGravar.contains('guardar-$id'),
                onPressed: () => _editar(v)),
            tvdeBotao(
                rotulo: 'Associar motorista',
                icone: Icons.person_add_alt,
                aGravar: aGravar.contains('assoc-$id'),
                onPressed: () => _associar(v)),
            if (v['estado'] != 'aprovado')
              tvdeBotao(
                  rotulo: 'Aprovar',
                  icone: Icons.check,
                  cor: AppColors.success,
                  aGravar: ocupado,
                  onPressed: () => _estado(v, 'aprovado', 'Aprovar')),
            if (v['estado'] != 'suspenso')
              tvdeBotao(
                  rotulo: 'Suspender',
                  icone: Icons.pause_circle_outline,
                  cor: AppColors.warning,
                  aGravar: ocupado,
                  onPressed: () => _estado(v, 'suspenso', 'Suspender')),
            if (v['estado'] != 'rejeitado')
              tvdeBotao(
                  rotulo: 'Rejeitar',
                  icone: Icons.block,
                  cor: AppColors.error,
                  aGravar: ocupado,
                  onPressed: () => _estado(v, 'rejeitado', 'Rejeitar')),
          ]),
        ]),
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
        final q = _busca.toLowerCase();
        final lista = _veiculos
            .where((v) =>
                q.isEmpty ||
                '${v['matricula']} ${v['marca']} ${v['modelo']} ${v['operador']}'
                    .toLowerCase()
                    .contains(q))
            .toList();
        return RefreshIndicator(
          onRefresh: _carregar,
          child: ListView(padding: const EdgeInsets.all(12), children: [
            Wrap(spacing: 8, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
              tvdeBotao(
                  key: const Key('tvde-veiculo-novo'),
                  rotulo: 'Novo veículo',
                  icone: Icons.directions_car,
                  aGravar: aGravar.contains('guardar-novo'),
                  onPressed: () => _editar()),
              SizedBox(
                width: 260,
                child: TextField(
                  decoration: const InputDecoration(
                      isDense: true,
                      prefixIcon: Icon(Icons.search),
                      hintText: 'Procurar matrícula, marca, operador'),
                  onChanged: (t) => setState(() => _busca = t.trim()),
                ),
              ),
            ]),
            const SizedBox(height: 8),
            if (lista.isEmpty) tvdeVazio('Nenhum veículo.'),
            for (final v in lista) _cartao(v),
          ]),
        );
      },
    );
  }
}
