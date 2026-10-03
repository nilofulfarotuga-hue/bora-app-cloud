// Separador 4 — Motoristas TVDE e o estado de conformidade de cada um.
// RPCs: admin_tvde_motoristas_conformidade (reavalia todos ao abrir),
//       admin_tvde_motorista_bloqueio(p_driver, p_bloquear, p_motivo),
//       admin_tvde_motorista_dados(p_driver, p), admin_tvde_operadores.
import 'package:flutter/material.dart';

import '../../../config/app_colors.dart';
import '_comum.dart';

/// Um motivo/aviso do servidor ({codigo, rotulo, ...} ou texto) → texto.
String tvdeRotuloMotivo(dynamic m) {
  if (m is Map) {
    return '${m['rotulo'] ?? m['texto'] ?? m['motivo'] ?? m['codigo'] ?? m}';
  }
  return '$m';
}

class TvdeMotoristasTab extends StatefulWidget {
  const TvdeMotoristasTab({super.key, this.rpc});

  final TvdeRpc? rpc;

  @override
  State<TvdeMotoristasTab> createState() => _TvdeMotoristasTabState();
}

class _TvdeMotoristasTabState extends State<TvdeMotoristasTab> with TvdeAGravar {
  bool _carregando = true;
  String? _erro;
  List<Map<String, dynamic>> _mot = [];
  List<(String, String)> _operadores = [];
  String _busca = '';
  bool _soImpedidos = false;

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
      final m = tvdeLista(await _rpc('admin_tvde_motoristas_conformidade'));
      final o = tvdeLista(await _rpc('admin_tvde_operadores'));
      if (!mounted) return;
      setState(() {
        _mot = m;
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

  Future<void> _bloqueio(Map<String, dynamic> m, bool bloquear) async {
    final motivo = await tvdePedirTexto(context,
        titulo: bloquear
            ? 'Bloquear ${tvdeTexto(m['nome'])}?'
            : 'Tirar o bloqueio manual de ${tvdeTexto(m['nome'])}?',
        explicacao: bloquear
            ? 'Bloqueio manual: o motorista deixa de poder ficar online no TVDE '
                'até ser desbloqueado. Fica registado na auditoria.'
            : 'Só tira o bloqueio manual. Se faltarem documentos, continua impedido.');
    if (motivo == null) return;
    final ok = await correr('bloq-${m['user_id']}',
        () => _rpc('admin_tvde_motorista_bloqueio',
            {'p_driver': m['user_id'], 'p_bloquear': bloquear, 'p_motivo': motivo}),
        ok: bloquear ? 'Motorista bloqueado.' : 'Bloqueio manual retirado.');
    if (ok) _carregar();
  }

  Future<void> _dados(Map<String, dynamic> m) async {
    final r = await tvdeFormulario(context,
        titulo: 'Dados TVDE de ${tvdeTexto(m['nome'])}',
        nota: 'A lei (Lei 45/2018, revista pela Lei 59/2026) pede: operador '
            'licenciado, carta B há mais de 3 anos, falar português e o curso '
            'de atualização em dia.',
        campos: [
          TvdeCampo('operador_id', 'Operador TVDE',
              tipo: TvdeCampoTipo.escolha, opcoes: _operadores),
          const TvdeCampo('carta_b_emitida_em', 'Carta B emitida em',
              tipo: TvdeCampoTipo.data),
          const TvdeCampo('fala_portugues', 'Fala português', tipo: TvdeCampoTipo.sim),
          const TvdeCampo('curso_atualizacao_em', 'Curso de atualização TVDE feito em',
              tipo: TvdeCampoTipo.data),
        ],
        inicial: m);
    if (r == null) return;
    final ok = await correr('dados-${m['user_id']}',
        () => _rpc('admin_tvde_motorista_dados', {'p_driver': m['user_id'], 'p': r}),
        ok: 'Dados gravados.');
    if (ok) _carregar();
  }

  Widget _cartao(Map<String, dynamic> m) {
    final uid = m['user_id'];
    final bloqueado = tvdeBool(m['bloqueado']) == true;
    final manual = tvdeBool(m['bloqueio_manual']) == true;
    final motivos = (m['motivos'] is List ? m['motivos'] as List : const []);
    final avisos = (m['avisos'] is List ? m['avisos'] as List : const []);
    return Card(
      key: Key('tvde-motorista-$uid'),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Expanded(
              child: Text(tvdeTexto(m['nome']),
                  style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
            ),
            if (tvdeBool(m['online']) == true) ...[
              tvdeChip('Online', AppColors.info),
              const SizedBox(width: 6),
            ],
            bloqueado
                ? tvdeChip('Impedido', AppColors.error)
                : tvdeChip('Pode trabalhar', AppColors.success),
          ]),
          const SizedBox(height: 4),
          Text('${tvdeTexto(m['telefone'])} · Operador: ${tvdeTexto(m['operador'])} · '
              'Veículo: ${tvdeTexto(m['veiculo'])}',
              style: const TextStyle(fontSize: 12)),
          Text('Horas nas últimas 24h: ${tvdeHoras(m['horas_bora_24h'])} na Bora · '
              '${tvdeHoras(m['horas_total_24h'])} no total',
              style: const TextStyle(fontSize: 12)),
          Text('Carta B desde ${tvdeData(m['carta_b_emitida_em'])} · '
              'Fala português: ${tvdeBool(m['fala_portugues']) == true ? 'sim' : 'não'} · '
              'Curso: ${tvdeData(m['curso_atualizacao_em'])} · '
              'Verificado ${tvdeDataHora(m['verificado_em'])}',
              style: const TextStyle(fontSize: 12, color: AppColors.textSecondary)),
          if (motivos.isNotEmpty) ...[
            const SizedBox(height: 6),
            const Text('Impedimentos:',
                style: TextStyle(fontWeight: FontWeight.w600, color: AppColors.error)),
            for (final x in motivos)
              Text('• ${tvdeRotuloMotivo(x)}',
                  style: const TextStyle(fontSize: 12, color: AppColors.error)),
          ],
          if (avisos.isNotEmpty) ...[
            const SizedBox(height: 6),
            const Text('Avisos:',
                style: TextStyle(fontWeight: FontWeight.w600, color: AppColors.warning)),
            for (final x in avisos)
              Text('• ${tvdeRotuloMotivo(x)}', style: const TextStyle(fontSize: 12)),
          ],
          if (manual)
            Text('Bloqueio manual: ${tvdeTexto(m['bloqueio_manual_motivo'])}',
                style: const TextStyle(fontSize: 12, color: AppColors.error)),
          const SizedBox(height: 8),
          Wrap(spacing: 8, runSpacing: 8, children: [
            manual
                ? tvdeBotao(
                    rotulo: 'Desbloquear',
                    icone: Icons.lock_open,
                    cor: AppColors.success,
                    aGravar: aGravar.contains('bloq-$uid'),
                    onPressed: () => _bloqueio(m, false))
                : tvdeBotao(
                    rotulo: 'Bloquear',
                    icone: Icons.lock,
                    cor: AppColors.error,
                    aGravar: aGravar.contains('bloq-$uid'),
                    onPressed: () => _bloqueio(m, true)),
            tvdeBotao(
                rotulo: 'Editar dados',
                icone: Icons.edit,
                aGravar: aGravar.contains('dados-$uid'),
                onPressed: () => _dados(m)),
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
        final lista = _mot
            .where((m) => !_soImpedidos || tvdeBool(m['bloqueado']) == true)
            .where((m) =>
                q.isEmpty ||
                '${m['nome']} ${m['telefone']} ${m['operador']} ${m['veiculo']}'
                    .toLowerCase()
                    .contains(q))
            .toList();
        final impedidos = _mot.where((m) => tvdeBool(m['bloqueado']) == true).length;
        return RefreshIndicator(
          onRefresh: _carregar,
          child: ListView(padding: const EdgeInsets.all(12), children: [
            Text('${_mot.length} motorista(s) TVDE · $impedidos com impedimentos',
                style: const TextStyle(fontWeight: FontWeight.w700)),
            const SizedBox(height: 8),
            Wrap(spacing: 8, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
              SizedBox(
                width: 260,
                child: TextField(
                  decoration: const InputDecoration(
                      isDense: true,
                      prefixIcon: Icon(Icons.search),
                      hintText: 'Procurar nome, telefone, matrícula'),
                  onChanged: (t) => setState(() => _busca = t.trim()),
                ),
              ),
              FilterChip(
                label: const Text('Só impedidos'),
                selected: _soImpedidos,
                onSelected: (v) => setState(() => _soImpedidos = v),
              ),
            ]),
            const SizedBox(height: 8),
            if (lista.isEmpty) tvdeVazio('Nenhum motorista.'),
            for (final m in lista) _cartao(m),
          ]),
        );
      },
    );
  }
}
