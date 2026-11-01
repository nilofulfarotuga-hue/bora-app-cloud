/// CASA — aba "Ofertas" do hub (painel admin, PT-BR): o registro da rotação
/// de TODOS os pedidos (`admin_casa_ofertas`, as 500 mais recentes). Mostra
/// quem foi chamado, se tinha aparelho registrado, se aceitou, recusou ou
/// deixou expirar, e em que ronda. Toque abre o pedido.
///
/// [01/11/2026 · C16 da revisão] A função existia no servidor sem chamador
/// (casca sem fio, PADRAO_BORA 1.5). A ficha do pedido continua a mostrar as
/// ofertas DAQUELE pedido; aqui vê-se a saúde da rotação inteira (ex.: muitos
/// "Sem aparelho registrado" = push que não chega).
library;

import 'package:flutter/material.dart';

import '../../config/app_colors.dart';
import '../../config/app_spacing.dart';
import 'admin_casa_comum.dart';
import 'admin_casa_pedidos_tab.dart' show AdminCasaPedidoScreen;

/// Filtro "sem resposta ainda" (no servidor a resposta vem nula).
const String kCasaOfertaAguardando = 'aguardando';

/// Filtros da aba, pela ordem dos chips (valores de `casa_ofertas.resposta`).
const List<String> kCasaOfertaRespostas = [
  kCasaOfertaAguardando,
  'aceite',
  'recusada',
  'expirada',
  'sem_aparelho',
  'orcamento_enviado',
];

/// Rótulo PT-BR de cada filtro.
String casaOfertaFiltroPtBr(String f) => f == kCasaOfertaAguardando
    ? 'Aguardando resposta'
    : casaOfertaRespostaPtBr(f);

/// A oferta cabe no filtro? (`null` = todas)
bool casaOfertaNoFiltro(Map<String, dynamic> o, String? filtro) {
  if (filtro == null) return true;
  final r = (o['resposta'] ?? '').toString();
  if (filtro == kCasaOfertaAguardando) return r.isEmpty;
  return r == filtro;
}

/// Contagens da lista (só o que veio do servidor; nada de dinheiro).
({
  int total,
  int aceitas,
  int recusadas,
  int expiradas,
  int semAparelho,
  int aguardando,
}) casaResumoOfertas(List<Map<String, dynamic>> lista) {
  int n(String r) => lista.where((o) => casaOfertaNoFiltro(o, r)).length;
  return (
    total: lista.length,
    aceitas: n('aceite'),
    recusadas: n('recusada'),
    expiradas: n('expirada'),
    semAparelho: lista.where((o) => o['tinha_aparelho'] == false).length,
    aguardando: n(kCasaOfertaAguardando),
  );
}

class AdminCasaOfertasTab extends StatefulWidget {
  const AdminCasaOfertasTab({super.key, this.rpc});
  final ChamarRpcPainel? rpc;

  @override
  State<AdminCasaOfertasTab> createState() => _AdminCasaOfertasTabState();
}

class _AdminCasaOfertasTabState extends State<AdminCasaOfertasTab> {
  String? _filtro;
  late Future<List<Map<String, dynamic>>> _future = _load();

  ChamarRpcPainel get _rpc => casaRpc(widget.rpc);

  Future<List<Map<String, dynamic>>> _load() async => casaLista(
      casaVerOk(await _rpc('admin_casa_ofertas', {'p_pedido_id': null})));

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
          opcoes: kCasaOfertaRespostas,
          valor: _filtro,
          rotulo: casaOfertaFiltroPtBr,
          // Filtra a lista já lida (a função do servidor não filtra resposta).
          onMudar: (v) => setState(() => _filtro = v),
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
              final todas = snap.data ?? const <Map<String, dynamic>>[];
              final r = casaResumoOfertas(todas);
              final lista = [
                for (final o in todas)
                  if (casaOfertaNoFiltro(o, _filtro)) o,
              ];
              return RefreshIndicator(
                onRefresh: _refresh,
                child: ListView(
                  padding: const EdgeInsets.only(bottom: Spacing.huge),
                  children: [
                    Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: Spacing.lg, vertical: Spacing.xs),
                      child: Text(
                        '${r.total} ofertas · ${r.aceitas} aceitas · '
                        '${r.recusadas} recusadas · ${r.expiradas} expiraram · '
                        '${r.semAparelho} sem aparelho · '
                        '${r.aguardando} aguardando',
                        key: const ValueKey('casa-ofertas-resumo'),
                        style: const TextStyle(
                            fontSize: 12, fontWeight: FontWeight.w600),
                      ),
                    ),
                    if (lista.isEmpty)
                      const CasaVazio('Nenhuma oferta neste filtro.'),
                    for (final o in lista) _linha(context, o),
                  ],
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _linha(BuildContext context, Map<String, dynamic> o) {
    final temAparelho = o['tinha_aparelho'] == true;
    final pedidoId = (o['pedido_id'] ?? '').toString();
    return Card(
      key: ValueKey('casa-oferta-${o['id']}'),
      margin: const EdgeInsets.symmetric(
          horizontal: Spacing.md, vertical: Spacing.xs),
      child: ListTile(
        leading: Icon(
          temAparelho ? Icons.phone_android : Icons.phonelink_erase,
          color: temAparelho ? AppColors.success : AppColors.error,
        ),
        title: Text('${casaTexto(o['profissional_nome'])} · '
            '${casaOfertaTipoPtBr(o['tipo']?.toString())} · '
            'ronda ${casaInt(o['ronda'])}'),
        subtitle: Text(
          'Enviada ${casaDataHora(o['enviada_em'])} · '
          'expira ${casaDataHora(o['expira_em'])}\n'
          '${casaOfertaRespostaPtBr(o['resposta']?.toString())}'
          '${o['respondida_em'] == null ? '' : ' em ${casaDataHora(o['respondida_em'])}'}',
        ),
        isThreeLine: true,
        trailing: pedidoId.isEmpty ? null : const Icon(Icons.chevron_right),
        onTap: pedidoId.isEmpty
            ? null
            : () => Navigator.of(context).push(MaterialPageRoute<void>(
                  builder: (_) =>
                      AdminCasaPedidoScreen(id: pedidoId, rpc: widget.rpc),
                )),
      ),
    );
  }
}
