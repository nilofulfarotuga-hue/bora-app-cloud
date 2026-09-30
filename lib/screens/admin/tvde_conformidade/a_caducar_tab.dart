// Separador 5 — Documentos a caducar nos próximos 30 dias (motoristas,
// veículos e operadores), ordenados pela data. RPC: admin_tvde_a_caducar(30).
import 'package:flutter/material.dart';

import '../../../config/app_colors.dart';
import '_comum.dart';

class TvdeACaducarTab extends StatefulWidget {
  const TvdeACaducarTab({super.key, this.rpc, this.guardarCsv, this.dias = 30});

  final TvdeRpc? rpc;
  final TvdeGuardarCsv? guardarCsv;
  final int dias;

  @override
  State<TvdeACaducarTab> createState() => _TvdeACaducarTabState();
}

class _TvdeACaducarTabState extends State<TvdeACaducarTab> {
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
      final l = tvdeLista(await _rpc('admin_tvde_a_caducar', {'p_dias': widget.dias}));
      l.sort((a, b) => '${a['validade']}'.compareTo('${b['validade']}'));
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

  Future<void> _exportar() async {
    try {
      await (widget.guardarCsv ?? tvdeGuardarCsvPadrao)(
        'tvde_a_caducar_${tvdeHoje()}.csv',
        tvdeCsv(['tipo', 'quem', 'documento', 'validade', 'dias'], [
          for (final l in _linhas)
            [l['tipo'], l['quem'], l['documento'], l['validade'], l['dias']],
        ]),
      );
    } catch (e) {
      if (mounted) tvdeAvisar(context, tvdeErro(e), erro: true);
    }
  }

  Color _cor(int dias) => dias < 0
      ? AppColors.error
      : dias <= 7
          ? AppColors.error
          : AppColors.warning;

  @override
  Widget build(BuildContext context) {
    return tvdeCorpo(
      carregando: _carregando,
      erro: _erro,
      tentar: _carregar,
      conteudo: () => RefreshIndicator(
        onRefresh: _carregar,
        child: ListView(padding: const EdgeInsets.all(12), children: [
          Row(children: [
            Expanded(
              child: Text(
                  '${_linhas.length} documento(s) vencido(s) ou a vencer em ${widget.dias} dias',
                  style: const TextStyle(fontWeight: FontWeight.w700)),
            ),
            OutlinedButton.icon(
                onPressed: _linhas.isEmpty ? null : _exportar,
                icon: const Icon(Icons.download),
                label: const Text('CSV')),
          ]),
          const SizedBox(height: 8),
          if (_linhas.isEmpty) tvdeVazio('Nada a caducar nos próximos ${widget.dias} dias.'),
          if (_linhas.isNotEmpty)
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: DataTable(
                columns: const [
                  DataColumn(label: Text('Validade')),
                  DataColumn(label: Text('Dias'), numeric: true),
                  DataColumn(label: Text('Tipo')),
                  DataColumn(label: Text('Quem')),
                  DataColumn(label: Text('Documento')),
                ],
                rows: [
                  for (final l in _linhas)
                    DataRow(cells: [
                      DataCell(Text(tvdeData(l['validade']))),
                      DataCell(Text(
                          tvdeInt(l['dias']) < 0 ? 'vencido há ${-tvdeInt(l['dias'])}' : '${tvdeInt(l['dias'])}',
                          style: TextStyle(
                              color: _cor(tvdeInt(l['dias'])),
                              fontWeight: FontWeight.w700))),
                      DataCell(Text(switch (l['tipo']) {
                        'motorista' => 'Motorista',
                        'veiculo' => 'Veículo',
                        'operador' => 'Operador',
                        final t => tvdeTexto(t),
                      })),
                      DataCell(Text(tvdeTexto(l['quem']))),
                      DataCell(Text(tvdeTexto(l['documento']))),
                    ]),
                ],
              ),
            ),
        ]),
      ),
    );
  }
}
