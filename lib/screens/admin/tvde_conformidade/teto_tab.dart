// Separador 10 — Teto de 25% da intermediação (a parte da plataforma não pode
// passar de 25% do valor da viagem). RPC: admin_tvde_intermediacao(200).
import 'package:flutter/material.dart';

import '../../../config/app_colors.dart';
import '_comum.dart';

class TvdeTetoTab extends StatefulWidget {
  const TvdeTetoTab({super.key, this.rpc});

  final TvdeRpc? rpc;

  @override
  State<TvdeTetoTab> createState() => _TvdeTetoTabState();
}

class _TvdeTetoTabState extends State<TvdeTetoTab> {
  bool _carregando = true;
  String? _erro;
  Map<String, dynamic> _resumo = {};
  List<Map<String, dynamic>> _linhas = [];
  bool _soAcima = false;

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
      final r = tvdeMapa(await _rpc('admin_tvde_intermediacao', {'p_limite': 200}));
      if (!mounted) return;
      setState(() {
        _resumo = tvdeMapa(r['resumo']);
        _linhas = tvdeLista(r['linhas']);
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

  String _pct(dynamic v) {
    final n = tvdeNum(v);
    return n == null ? '—' : '${n.toStringAsFixed(2).replaceAll('.', ',')}%';
  }

  Widget _num(String rot, String val, {bool alerta = false}) => Container(
        width: 150,
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: alerta ? AppColors.error : AppColors.divider),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(val,
              style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                  color: alerta ? AppColors.error : AppColors.textPrimary)),
          Text(rot, style: const TextStyle(fontSize: 12)),
        ]),
      );

  @override
  Widget build(BuildContext context) {
    return tvdeCorpo(
      carregando: _carregando,
      erro: _erro,
      tentar: _carregar,
      conteudo: () {
        final lista = _soAcima
            ? _linhas.where((l) => tvdeBool(l['cumpre']) == false).toList()
            : _linhas;
        final acima = tvdeInt(_resumo['acima_teto']);
        return RefreshIndicator(
          onRefresh: _carregar,
          child: ListView(padding: const EdgeInsets.all(12), children: [
            tvdeNota('A intermediação (parte da Bora) não pode passar de 25% do '
                'valor da viagem. Cada corrida acabada é verificada.'),
            Wrap(spacing: 8, runSpacing: 8, children: [
              _num('Verificadas', '${tvdeInt(_resumo['verificadas'])}'),
              _num('Acima do teto', '$acima', alerta: acima > 0),
              _num('% média', _pct(_resumo['pct_medio'])),
              _num('% máxima', _pct(_resumo['pct_max']),
                  alerta: (tvdeNum(_resumo['pct_max']) ?? 0) > 25),
            ]),
            const SizedBox(height: 8),
            FilterChip(
              label: const Text('Só acima do teto'),
              selected: _soAcima,
              onSelected: (v) => setState(() => _soAcima = v),
            ),
            const SizedBox(height: 8),
            if (lista.isEmpty) tvdeVazio('Nenhuma corrida verificada.'),
            if (lista.isNotEmpty)
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: DataTable(
                  columns: const [
                    DataColumn(label: Text('Viagem')),
                    DataColumn(label: Text('Valor'), numeric: true),
                    DataColumn(label: Text('Intermediação'), numeric: true),
                    DataColumn(label: Text('%'), numeric: true),
                    DataColumn(label: Text('Teto'), numeric: true),
                    DataColumn(label: Text('Cumpre')),
                    DataColumn(label: Text('Verificado em')),
                  ],
                  rows: [
                    for (final l in lista)
                      DataRow(cells: [
                        DataCell(Text(tvdeTexto(l['viagem']))),
                        DataCell(Text(tvdeEuros(l['valor_viagem_cents']))),
                        DataCell(Text(tvdeEuros(l['intermediacao_cents']))),
                        DataCell(Text(_pct(l['pct']))),
                        DataCell(Text(_pct(l['teto_pct']))),
                        DataCell(tvdeBool(l['cumpre']) == true
                            ? tvdeChip('Sim', AppColors.success)
                            : tvdeChip('Não', AppColors.error)),
                        DataCell(Text(tvdeDataHora(l['verificado_em']))),
                      ]),
                  ],
                ),
              ),
          ]),
        );
      },
    );
  }
}
