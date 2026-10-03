// Separador 2 — Operadores TVDE (empresas licenciadas pelo IMT que contratam
// os motoristas). Lista, cria/edita e aprova/suspende/rejeita com motivo.
// RPCs: admin_tvde_operadores, admin_tvde_operador_guardar(p),
//       admin_tvde_operador_estado(p_id, p_estado, p_motivo).
import 'package:flutter/material.dart';

import '../../../config/app_colors.dart';
import '_comum.dart';

final List<TvdeCampo> kTvdeCamposOperador = [
  const TvdeCampo('denominacao', 'Denominação (nome da empresa)', obrigatorio: true),
  TvdeCampo('nipc', 'NIPC (NIF da empresa, 9 dígitos)',
      obrigatorio: true,
      validar: (v) => RegExp(r'^\d{9}$').hasMatch(v.replaceAll(' ', ''))
          ? null
          : 'O NIPC tem 9 dígitos.'),
  const TvdeCampo('licenca_imt_numero', 'Licença IMT n.º (licença de operador TVDE)'),
  const TvdeCampo('licenca_imt_validade', 'Validade da licença IMT',
      tipo: TvdeCampoTipo.data),
  TvdeCampo('email', 'Email',
      validar: (v) => v.contains('@') ? null : 'Email inválido.'),
  const TvdeCampo('telefone', 'Telefone'),
  const TvdeCampo('sede', 'Sede (morada)'),
  const TvdeCampo('contrato_assinado_em', 'Data do contrato com a Bora',
      tipo: TvdeCampoTipo.data),
  const TvdeCampo('notas', 'Notas', tipo: TvdeCampoTipo.longo),
];

class TvdeOperadoresTab extends StatefulWidget {
  const TvdeOperadoresTab({super.key, this.rpc});

  final TvdeRpc? rpc;

  @override
  State<TvdeOperadoresTab> createState() => _TvdeOperadoresTabState();
}

class _TvdeOperadoresTabState extends State<TvdeOperadoresTab> with TvdeAGravar {
  bool _carregando = true;
  String? _erro;
  List<Map<String, dynamic>> _ops = [];

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
      final l = tvdeLista(await _rpc('admin_tvde_operadores'));
      if (!mounted) return;
      setState(() {
        _ops = l;
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

  Future<void> _editar([Map<String, dynamic>? op]) async {
    final r = await tvdeFormulario(context,
        titulo: op == null ? 'Novo operador TVDE' : 'Editar ${op['denominacao']}',
        campos: kTvdeCamposOperador,
        inicial: op ?? const {});
    if (r == null) return;
    r['nipc'] = (r['nipc'] as String).replaceAll(' ', '');
    if (op != null) r['id'] = op['id'];
    final ok = await correr('guardar-${op?['id'] ?? 'novo'}',
        () => _rpc('admin_tvde_operador_guardar', {'p': r}),
        ok: 'Operador gravado.');
    if (ok) _carregar();
  }

  Future<void> _estado(Map<String, dynamic> op, String estado, String verbo) async {
    final motivo = await tvdePedirTexto(context,
        titulo: '$verbo ${op['denominacao']}?',
        explicacao: 'Fica registado na auditoria. Os motoristas deste operador '
            'são reavaliados na hora.');
    if (motivo == null) return;
    final ok = await correr('estado-${op['id']}',
        () => _rpc('admin_tvde_operador_estado',
            {'p_id': op['id'], 'p_estado': estado, 'p_motivo': motivo}),
        ok: 'Operador: $estado.');
    if (ok) _carregar();
  }

  Widget _cartao(Map<String, dynamic> op) {
    final (rot, cor) = tvdeEstado(op['estado'] as String?);
    final id = op['id'];
    final ocupado = aGravar.contains('estado-$id') || aGravar.contains('guardar-$id');
    return Card(
      key: Key('tvde-operador-$id'),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Expanded(
              child: Text(tvdeTexto(op['denominacao']),
                  style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
            ),
            tvdeChip(rot, cor),
          ]),
          const SizedBox(height: 4),
          Text('NIPC ${tvdeTexto(op['nipc'])} · Licença IMT ${tvdeTexto(op['licenca_imt_numero'])} '
              '(válida até ${tvdeData(op['licenca_imt_validade'])})'),
          Text('${tvdeTexto(op['email'])} · ${tvdeTexto(op['telefone'])}',
              style: const TextStyle(fontSize: 12)),
          Text('Sede: ${tvdeTexto(op['sede'])} · Contrato: ${tvdeData(op['contrato_assinado_em'])}',
              style: const TextStyle(fontSize: 12)),
          Text('${tvdeInt(op['motoristas'])} motorista(s) · ${tvdeInt(op['veiculos'])} veículo(s)',
              style: const TextStyle(fontSize: 12, color: AppColors.textSecondary)),
          if (op['estado_motivo'] != null)
            Text('Motivo: ${op['estado_motivo']}',
                style: TextStyle(fontSize: 12, color: cor)),
          if (op['notas'] != null)
            Text('Notas: ${op['notas']}', style: const TextStyle(fontSize: 12)),
          const SizedBox(height: 8),
          Wrap(spacing: 8, runSpacing: 8, children: [
            tvdeBotao(
                rotulo: 'Editar',
                icone: Icons.edit,
                aGravar: aGravar.contains('guardar-$id'),
                onPressed: () => _editar(op)),
            if (op['estado'] != 'aprovado')
              tvdeBotao(
                  rotulo: 'Aprovar',
                  icone: Icons.check,
                  cor: AppColors.success,
                  aGravar: ocupado,
                  onPressed: () => _estado(op, 'aprovado', 'Aprovar')),
            if (op['estado'] != 'suspenso')
              tvdeBotao(
                  rotulo: 'Suspender',
                  icone: Icons.pause_circle_outline,
                  cor: AppColors.warning,
                  aGravar: ocupado,
                  onPressed: () => _estado(op, 'suspenso', 'Suspender')),
            if (op['estado'] != 'rejeitado')
              tvdeBotao(
                  rotulo: 'Rejeitar',
                  icone: Icons.block,
                  cor: AppColors.error,
                  aGravar: ocupado,
                  onPressed: () => _estado(op, 'rejeitado', 'Rejeitar')),
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
      conteudo: () => RefreshIndicator(
        onRefresh: _carregar,
        child: ListView(padding: const EdgeInsets.all(12), children: [
          tvdeNota('Operador TVDE = empresa com licença do IMT (Instituto da '
              'Mobilidade e dos Transportes) que contrata os motoristas. Sem '
              'operador aprovado, o motorista fica impedido quando o mestre estiver ligado.'),
          Align(
            alignment: Alignment.centerLeft,
            child: tvdeBotao(
                key: const Key('tvde-operador-novo'),
                rotulo: 'Novo operador',
                icone: Icons.add_business,
                aGravar: aGravar.contains('guardar-novo'),
                onPressed: () => _editar()),
          ),
          const SizedBox(height: 8),
          if (_ops.isEmpty) tvdeVazio('Nenhum operador registado.'),
          for (final o in _ops) _cartao(o),
        ]),
      ),
    );
  }
}
