/// CASA — aba "Orçamentos" do hub (painel admin, PT-BR): todos os
/// orçamentos, quem ganhou, tempo de resposta e os expirados.
library;

import 'package:flutter/material.dart';

import '../../config/app_colors.dart';
import '../../config/app_spacing.dart';
import 'admin_casa_comum.dart';
import 'admin_casa_pedidos_tab.dart' show AdminCasaPedidoScreen;

/// Resumo da lista (só contagens do que veio do servidor; nada de dinheiro).
({int total, int ganhos, int expirados, int abertos, double? mediaMin})
    casaResumoOrcamentos(List<Map<String, dynamic>> lista) {
  final tempos = [
    for (final o in lista)
      if (o['tempo_resposta_min'] != null) casaDouble(o['tempo_resposta_min']),
  ];
  return (
    total: lista.length,
    ganhos: lista.where((o) => o['ganhou'] == true).length,
    expirados: lista.where((o) => o['estado'] == 'expirado').length,
    abertos: lista.where((o) => o['estado'] == 'enviado').length,
    mediaMin: tempos.isEmpty
        ? null
        : tempos.reduce((a, b) => a + b) / tempos.length,
  );
}

/// "45 min" / "2 h 05 min".
String casaMinutosPtBr(Object? min) {
  if (min == null) return '—';
  final m = casaDouble(min).round();
  if (m < 60) return '$m min';
  return '${m ~/ 60} h ${(m % 60).toString().padLeft(2, '0')} min';
}

class AdminCasaOrcamentosTab extends StatefulWidget {
  const AdminCasaOrcamentosTab({super.key, this.rpc});
  final ChamarRpcPainel? rpc;

  @override
  State<AdminCasaOrcamentosTab> createState() => _AdminCasaOrcamentosTabState();
}

class _AdminCasaOrcamentosTabState extends State<AdminCasaOrcamentosTab> {
  String? _estado;
  late Future<List<Map<String, dynamic>>> _future = _load();

  ChamarRpcPainel get _rpc => casaRpc(widget.rpc);

  Future<List<Map<String, dynamic>>> _load() async => casaLista(
      casaVerOk(await _rpc('admin_casa_orcamentos', {'p_estado': _estado})));

  Future<void> _refresh() async {
    setState(() {
      _future = _load();
    });
    await _future;
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        CasaFiltros(
          opcoes: kCasaOrcamentoEstados,
          valor: _estado,
          rotulo: casaOrcamentoEstadoPtBr,
          onMudar: (v) {
            _estado = v;
            _refresh();
          },
        ),
        Expanded(
          child: FutureBuilder<List<Map<String, dynamic>>>(
            future: _future,
            builder: (context, snap) {
              if (snap.connectionState != ConnectionState.done) {
                return const Center(child: CircularProgressIndicator());
              }
              if (snap.hasError) {
                return CasaErroCarregar(erro: snap.error!, onTentar: _refresh);
              }
              final lista = snap.data ?? const <Map<String, dynamic>>[];
              final r = casaResumoOrcamentos(lista);
              return RefreshIndicator(
                onRefresh: _refresh,
                child: ListView(
                  padding: const EdgeInsets.only(bottom: Spacing.huge),
                  children: [
                    Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: Spacing.lg, vertical: Spacing.xs),
                      child: Text(
                        '${r.total} orçamentos · ${r.abertos} abertos · '
                        '${r.ganhos} ganharam · ${r.expirados} expirados · '
                        'resposta média ${r.mediaMin == null ? '—' : casaMinutosPtBr(r.mediaMin)}',
                        key: const ValueKey('casa-orcamentos-resumo'),
                        style: const TextStyle(
                            fontSize: 12, fontWeight: FontWeight.w600),
                      ),
                    ),
                    if (lista.isEmpty)
                      const CasaVazio('Nenhum orçamento neste filtro.'),
                    for (final o in lista)
                      Card(
                        margin: const EdgeInsets.symmetric(
                            horizontal: Spacing.md, vertical: Spacing.xs),
                        child: ListTile(
                          leading: Icon(
                            o['ganhou'] == true
                                ? Icons.emoji_events
                                : Icons.request_quote_outlined,
                            color: o['ganhou'] == true
                                ? AppColors.success
                                : AppColors.textSecondary,
                          ),
                          title: Text(
                              '${casaTexto(o['servico_nome'])} · ${casaEuroAdmin(o['preco_cents'])}'),
                          subtitle: Text(
                            '${casaTexto(o['profissional_nome'])} · '
                            '${casaOrcamentoEstadoPtBr(o['estado']?.toString())}\n'
                            'Enviado ${casaDataHora(o['created_at'])} · '
                            'respondeu em ${casaMinutosPtBr(o['tempo_resposta_min'])} · '
                            'expira ${casaDataHora(o['expira_em'])}',
                          ),
                          isThreeLine: true,
                          onTap: o['pedido_id'] == null
                              ? null
                              : () => Navigator.of(context)
                                      .push(MaterialPageRoute<void>(
                                    builder: (_) => AdminCasaPedidoScreen(
                                        id: '${o['pedido_id']}',
                                        rpc: widget.rpc),
                                  )),
                        ),
                      ),
                  ],
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}
