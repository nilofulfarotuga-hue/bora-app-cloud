// Separador 12 — Registo (auditoria) da conformidade TVDE: interruptores,
// aprovações, bloqueios, queixas, acessos e exportações de fiscalização.
// RPC: admin_tvde_eventos(p_tipo, p_limite).
import 'dart:convert';

import 'package:flutter/material.dart';

import '../../../config/app_colors.dart';
import '_comum.dart';

class TvdeRegistoTab extends StatefulWidget {
  const TvdeRegistoTab({super.key, this.rpc, this.guardarCsv});

  final TvdeRpc? rpc;
  final TvdeGuardarCsv? guardarCsv;

  @override
  State<TvdeRegistoTab> createState() => _TvdeRegistoTabState();
}

class _TvdeRegistoTabState extends State<TvdeRegistoTab> {
  bool _carregando = true;
  String? _erro;
  List<Map<String, dynamic>> _eventos = [];
  final Set<String> _tiposVistos = {};
  String? _tipo; // null = todos

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
      final l = tvdeLista(
          await _rpc('admin_tvde_eventos', {'p_tipo': _tipo, 'p_limite': 200}));
      if (!mounted) return;
      setState(() {
        _eventos = l;
        // Os tipos acumulam-se, para o filtro não encolher depois de filtrar.
        _tiposVistos.addAll(l.map((e) => '${e['tipo']}'));
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

  String _meta(dynamic m) {
    final mapa = tvdeMapa(m);
    if (mapa.isEmpty) return '';
    final s = jsonEncode(mapa);
    return s.length > 240 ? '${s.substring(0, 240)}…' : s;
  }

  Future<void> _exportar() async {
    try {
      await (widget.guardarCsv ?? tvdeGuardarCsvPadrao)(
        'tvde_registo_${tvdeHoje()}.csv',
        tvdeCsv(['quando', 'tipo', 'ator', 'motivo', 'motorista', 'detalhe'], [
          for (final e in _eventos)
            [
              tvdeDataHora(e['at']), e['tipo'], e['ator'], e['motivo'], e['motorista'],
              jsonEncode(tvdeMapa(e['meta'])),
            ],
        ]),
      );
    } catch (e) {
      if (mounted) tvdeAvisar(context, tvdeErro(e), erro: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final tipos = _tiposVistos.toList()..sort();
    return Column(children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
        child: Wrap(spacing: 8, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
          DropdownButton<String?>(
            value: _tipo,
            hint: const Text('Todos os tipos'),
            items: [
              const DropdownMenuItem<String?>(value: null, child: Text('Todos os tipos')),
              for (final t in tipos) DropdownMenuItem<String?>(value: t, child: Text(t)),
            ],
            onChanged: (v) {
              setState(() => _tipo = v);
              _carregar();
            },
          ),
          OutlinedButton.icon(
              onPressed: _eventos.isEmpty ? null : _exportar,
              icon: const Icon(Icons.download),
              label: const Text('CSV')),
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
              Text('${_eventos.length} evento(s) (máx. 200)',
                  style: const TextStyle(fontWeight: FontWeight.w700)),
              if (_eventos.isEmpty) tvdeVazio('Sem eventos.'),
              for (final e in _eventos)
                Card(
                  child: ListTile(
                    dense: true,
                    title: Text('${tvdeTexto(e['tipo'])} · ${tvdeTexto(e['ator'])}',
                        style: const TextStyle(fontWeight: FontWeight.w600)),
                    subtitle: Text([
                      tvdeDataHora(e['at']),
                      if (e['motorista'] != null) 'motorista ${e['motorista']}',
                      if (e['motivo'] != null) 'motivo: ${e['motivo']}',
                      if (_meta(e['meta']).isNotEmpty) _meta(e['meta']),
                    ].join('\n')),
                    leading: const Icon(Icons.history, color: AppColors.textSecondary),
                  ),
                ),
            ]),
          ),
        ),
      ),
    ]);
  }
}
