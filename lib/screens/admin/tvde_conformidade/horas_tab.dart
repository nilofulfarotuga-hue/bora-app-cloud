// Separador 6 — Horas de trabalho dos motoristas TVDE (a lei limita as horas
// seguidas/diárias). RPC: admin_tvde_horas(p_driver, p_dias). Export CSV.
import 'package:flutter/material.dart';

import '../../../config/app_colors.dart';
import '_comum.dart';

const Map<String, String> kTvdeFecho = {
  'offline': 'Ficou offline',
  'sem_sinal': 'Perdeu o sinal',
  'admin': 'Fechado pelo admin',
};

class TvdeHorasTab extends StatefulWidget {
  const TvdeHorasTab({super.key, this.rpc, this.guardarCsv});

  final TvdeRpc? rpc;
  final TvdeGuardarCsv? guardarCsv;

  @override
  State<TvdeHorasTab> createState() => _TvdeHorasTabState();
}

class _TvdeHorasTabState extends State<TvdeHorasTab> {
  bool _carregando = true;
  String? _erro;
  List<Map<String, dynamic>> _linhas = [];
  String? _motorista; // user_id; null = todos
  int _dias = 7;

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
      // Sempre todos, e o filtro por motorista faz-se aqui: assim a lista de
      // escolha não encolhe quando se filtra.
      final l = tvdeLista(await _rpc('admin_tvde_horas', {'p_driver': null, 'p_dias': _dias}));
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

  List<Map<String, dynamic>> get _filtradas => _motorista == null
      ? _linhas
      : _linhas.where((l) => '${l['driver_user_id']}' == _motorista).toList();

  Future<void> _exportar() async {
    try {
      await (widget.guardarCsv ?? tvdeGuardarCsvPadrao)(
        'tvde_horas_${_dias}d_${tvdeHoje()}.csv',
        tvdeCsv(['motorista', 'driver_user_id', 'inicio', 'fim', 'horas', 'fecho'], [
          for (final l in _filtradas)
            [
              l['nome'],
              l['driver_user_id'],
              tvdeDataHora(l['inicio']),
              l['fim'] == null ? 'em curso' : tvdeDataHora(l['fim']),
              '${l['horas'] ?? ''}'.replaceAll('.', ','),
              kTvdeFecho[l['fecho']] ?? l['fecho'] ?? '',
            ],
        ]),
      );
    } catch (e) {
      if (mounted) tvdeAvisar(context, tvdeErro(e), erro: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    return tvdeCorpo(
      carregando: _carregando,
      erro: _erro,
      tentar: _carregar,
      conteudo: () {
        final nomes = <String, String>{};
        for (final l in _linhas) {
          nomes['${l['driver_user_id']}'] = tvdeTexto(l['nome']);
        }
        final f = _filtradas;
        final total = f.fold<double>(0, (s, l) => s + (tvdeNum(l['horas']) ?? 0));
        return RefreshIndicator(
          onRefresh: _carregar,
          child: ListView(padding: const EdgeInsets.all(12), children: [
            Wrap(spacing: 8, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
              DropdownButton<String?>(
                value: nomes.containsKey(_motorista) ? _motorista : null,
                hint: const Text('Todos os motoristas'),
                items: [
                  const DropdownMenuItem<String?>(value: null, child: Text('Todos os motoristas')),
                  for (final e in nomes.entries)
                    DropdownMenuItem<String?>(value: e.key, child: Text(e.value)),
                ],
                onChanged: (v) => setState(() => _motorista = v),
              ),
              DropdownButton<int>(
                value: _dias,
                items: const [
                  DropdownMenuItem(value: 1, child: Text('Últimas 24h')),
                  DropdownMenuItem(value: 7, child: Text('7 dias')),
                  DropdownMenuItem(value: 30, child: Text('30 dias')),
                ],
                onChanged: (v) {
                  if (v == null) return;
                  setState(() => _dias = v);
                  _carregar();
                },
              ),
              OutlinedButton.icon(
                  onPressed: f.isEmpty ? null : _exportar,
                  icon: const Icon(Icons.download),
                  label: const Text('Exportar CSV')),
            ]),
            const SizedBox(height: 8),
            Text('${f.length} turno(s) · ${tvdeHoras(total)} no total',
                style: const TextStyle(fontWeight: FontWeight.w700)),
            const SizedBox(height: 8),
            if (f.isEmpty) tvdeVazio('Sem turnos registados neste período.'),
            if (f.isNotEmpty)
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: DataTable(
                  columns: const [
                    DataColumn(label: Text('Motorista')),
                    DataColumn(label: Text('Início')),
                    DataColumn(label: Text('Fim')),
                    DataColumn(label: Text('Horas'), numeric: true),
                    DataColumn(label: Text('Como fechou')),
                  ],
                  rows: [
                    for (final l in f)
                      DataRow(cells: [
                        DataCell(Text(tvdeTexto(l['nome']))),
                        DataCell(Text(tvdeDataHora(l['inicio']))),
                        DataCell(l['fim'] == null
                            ? tvdeChip('Em curso', AppColors.info)
                            : Text(tvdeDataHora(l['fim']))),
                        DataCell(Text(tvdeHoras(l['horas']))),
                        DataCell(Text(kTvdeFecho[l['fecho']] ?? tvdeTexto(l['fecho']))),
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
