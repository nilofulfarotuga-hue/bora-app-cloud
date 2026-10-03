// Separador 9 — Relatório AMT (Autoridade da Mobilidade e dos Transportes):
// contribuição de regulação de 5% sobre a intermediação, por mês.
// RPCs: admin_tvde_amt(), admin_tvde_amt_gerar(p_mes date). Export CSV.
import 'package:flutter/material.dart';

import '../../../config/app_colors.dart';
import '_comum.dart';

const String kTvdeNotaAmt = 'Valores sem IVA — empresa por constituir.';

String tvdeMesRotulo(dynamic mes) {
  final d = DateTime.tryParse('$mes');
  if (d == null) return tvdeTexto(mes);
  return '${d.month.toString().padLeft(2, '0')}/${d.year}';
}

class TvdeAmtTab extends StatefulWidget {
  const TvdeAmtTab({super.key, this.rpc, this.guardarCsv});

  final TvdeRpc? rpc;
  final TvdeGuardarCsv? guardarCsv;

  @override
  State<TvdeAmtTab> createState() => _TvdeAmtTabState();
}

class _TvdeAmtTabState extends State<TvdeAmtTab> with TvdeAGravar {
  bool _carregando = true;
  String? _erro;
  List<Map<String, dynamic>> _linhas = [];

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
      final l = tvdeLista(await _rpc('admin_tvde_amt'));
      if (!mounted) return;
      setState(() {
        _linhas = l;
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

  Future<void> _gerar() async {
    final agora = DateTime.now();
    // Por defeito o mês anterior (o último fechado).
    var ano = agora.month == 1 ? agora.year - 1 : agora.year;
    var mes = agora.month == 1 ? 12 : agora.month - 1;
    final escolhido = await showDialog<DateTime>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, mudar) => AlertDialog(
          title: const Text('Gerar relatório AMT do mês'),
          content: Row(children: [
            DropdownButton<int>(
              value: mes,
              items: [
                for (var m = 1; m <= 12; m++)
                  DropdownMenuItem(value: m, child: Text(m.toString().padLeft(2, '0'))),
              ],
              onChanged: (v) => mudar(() => mes = v ?? mes),
            ),
            const SizedBox(width: 12),
            DropdownButton<int>(
              value: ano,
              items: [
                for (var a = agora.year - 2; a <= agora.year; a++)
                  DropdownMenuItem(value: a, child: Text('$a')),
              ],
              onChanged: (v) => mudar(() => ano = v ?? ano),
            ),
          ]),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancelar')),
            FilledButton(
                onPressed: () => Navigator.pop(ctx, DateTime(ano, mes, 1)),
                child: const Text('Gerar')),
          ],
        ),
      ),
    );
    if (escolhido == null) return;
    final iso =
        '${escolhido.year}-${escolhido.month.toString().padLeft(2, '0')}-01';
    final ok = await correr('gerar',
        () => _rpc('admin_tvde_amt_gerar', {'p_mes': iso}),
        ok: 'Relatório de ${tvdeMesRotulo(iso)} gerado.');
    if (ok) _carregar();
  }

  Future<void> _exportar() async {
    String e(dynamic c) => tvdeEuros(c).replaceAll(' €', '');
    try {
      await (widget.guardarCsv ?? tvdeGuardarCsvPadrao)(
        'tvde_amt_${tvdeHoje()}.csv',
        tvdeCsv([
          'mes', 'viagens', 'faturado_eur', 'intermediacao_eur', 'contribuicao_pct',
          'contribuicao_eur', 'viagens_acima_teto', 'gerado_em', 'nota'
        ], [
          for (final l in _linhas)
            [
              tvdeMesRotulo(l['mes']), l['viagens'], e(l['faturado_cents']),
              e(l['intermediacao_cents']), '${l['contribuicao_pct'] ?? ''}'.replaceAll('.', ','),
              e(l['contribuicao_cents']), l['viagens_acima_teto'],
              tvdeDataHora(l['gerado_em']), kTvdeNotaAmt,
            ],
        ]),
      );
    } catch (err) {
      if (mounted) tvdeAvisar(context, tvdeErro(err), erro: true);
    }
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
          tvdeNota('Contribuição de regulação à AMT: 5% sobre o valor de '
              'intermediação da plataforma. $kTvdeNotaAmt',
              cor: AppColors.warning),
          Wrap(spacing: 8, runSpacing: 8, children: [
            tvdeBotao(
                key: const Key('tvde-amt-gerar'),
                rotulo: 'Gerar mês',
                icone: Icons.calculate,
                aGravar: aGravar.contains('gerar'),
                onPressed: _gerar),
            OutlinedButton.icon(
                onPressed: _linhas.isEmpty ? null : _exportar,
                icon: const Icon(Icons.download),
                label: const Text('Exportar CSV')),
          ]),
          const SizedBox(height: 8),
          if (_linhas.isEmpty) tvdeVazio('Nenhum mês gerado ainda.'),
          if (_linhas.isNotEmpty)
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: DataTable(
                columns: const [
                  DataColumn(label: Text('Mês')),
                  DataColumn(label: Text('Viagens'), numeric: true),
                  DataColumn(label: Text('Faturado'), numeric: true),
                  DataColumn(label: Text('Intermediação'), numeric: true),
                  DataColumn(label: Text('Contribuição'), numeric: true),
                  DataColumn(label: Text('Acima do teto'), numeric: true),
                  DataColumn(label: Text('Gerado em')),
                ],
                rows: [
                  for (final l in _linhas)
                    DataRow(cells: [
                      DataCell(Text(tvdeMesRotulo(l['mes']))),
                      DataCell(Text('${tvdeInt(l['viagens'])}')),
                      DataCell(Text(tvdeEuros(l['faturado_cents']))),
                      DataCell(Text(tvdeEuros(l['intermediacao_cents']))),
                      DataCell(Text(
                          '${tvdeEuros(l['contribuicao_cents'])} (${tvdeTexto(l['contribuicao_pct'])}%)')),
                      DataCell(Text('${tvdeInt(l['viagens_acima_teto'])}',
                          style: TextStyle(
                              color: tvdeInt(l['viagens_acima_teto']) > 0
                                  ? AppColors.error
                                  : null))),
                      DataCell(Text(tvdeDataHora(l['gerado_em']))),
                    ]),
                ],
              ),
            ),
        ]),
      ),
    );
  }
}
