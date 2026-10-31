/// CASA — aba "Pedidos" do hub e a ficha completa de cada pedido (painel
/// admin, PT-BR). Lista por estado; a ficha mostra fotos (balde privado
/// casa-fotos, URL assinada), orçamentos, extras, conversa, histórico de
/// estados e registro de ofertas. Ações (todas com confirmação): reatribuir,
/// cancelar, marcar/desmarcar teste, forçar conclusão e resolver disputa.
/// Nenhum valor é calculado aqui: o painel só mostra o que o servidor dá.
library;

import 'dart:convert';

import 'package:flutter/material.dart';

import '../../config/app_colors.dart';
import '../../config/app_spacing.dart';
import 'admin_casa_comum.dart';
import 'admin_casa_profissionais_tab.dart' show AdminCasaProfissionalScreen;

/// Ações do pedido que aparecem em cada estado.
Set<String> casaAcoesPedido(String? estado) {
  const reatribuir = {
    'procura',
    'orcamentos',
    'aceite',
    'a_caminho',
    'chegou',
    'disputa',
    'expirado',
  };
  const forcar = {'aceite', 'a_caminho', 'chegou', 'em_curso', 'concluido', 'disputa'};
  return {
    if (reatribuir.contains(estado)) 'reatribuir',
    if (estado != 'confirmado' && estado != 'cancelado') 'cancelar',
    if (forcar.contains(estado)) 'forcar_conclusao',
    if (estado == 'disputa') 'resolver_disputa',
    'teste',
  };
}

/// Tipos de foto, pela ordem em que aparecem.
const Map<String, String> kCasaTiposFoto = {
  'problema': 'Problema (enviadas pelo cliente)',
  'antes': 'Antes (profissional)',
  'depois': 'Depois (profissional)',
  'extra': 'Extra (profissional)',
};

// ═══════════════════════════════════════════════════════════════════════════
// Lista
// ═══════════════════════════════════════════════════════════════════════════

class AdminCasaPedidosTab extends StatefulWidget {
  const AdminCasaPedidosTab({super.key, this.rpc, this.estadoInicial});
  final ChamarRpcPainel? rpc;
  final String? estadoInicial;

  @override
  State<AdminCasaPedidosTab> createState() => _AdminCasaPedidosTabState();
}

class _AdminCasaPedidosTabState extends State<AdminCasaPedidosTab> {
  late String? _estado = widget.estadoInicial;
  late Future<List<Map<String, dynamic>>> _future = _load();

  ChamarRpcPainel get _rpc => casaRpc(widget.rpc);

  Future<List<Map<String, dynamic>>> _load() async =>
      casaLista(casaVerOk(await _rpc('admin_casa_pedidos', {
        'p_estado': _estado,
        'p_limite': 200,
      })));

  Future<void> _refresh() async {
    setState(() {
      _future = _load();
    });
    await _future;
  }

  Future<void> _abrir(Map<String, dynamic> p) async {
    await Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => AdminCasaPedidoScreen(id: '${p['id']}', rpc: widget.rpc),
    ));
    if (mounted) await _refresh();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        CasaFiltros(
          opcoes: kCasaEstados,
          valor: _estado,
          rotulo: casaEstadoPtBr,
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
              return RefreshIndicator(
                onRefresh: _refresh,
                child: lista.isEmpty
                    ? ListView(children: const [
                        CasaVazio('Nenhum pedido neste estado.'),
                      ])
                    : ListView.builder(
                        padding: const EdgeInsets.only(bottom: Spacing.huge),
                        itemCount: lista.length,
                        itemBuilder: (_, i) => _CartaoPedido(
                            p: lista[i], onTap: () => _abrir(lista[i])),
                      ),
              );
            },
          ),
        ),
      ],
    );
  }
}

class _CartaoPedido extends StatelessWidget {
  const _CartaoPedido({required this.p, required this.onTap});
  final Map<String, dynamic> p;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final estado = p['estado']?.toString();
    final morada = casaMapa(p['morada']);
    return Card(
      margin: const EdgeInsets.symmetric(
          horizontal: Spacing.md, vertical: Spacing.xs),
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(Spacing.md),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [
                Expanded(
                  child: Text(casaTexto(p['servico_nome'] ?? p['oficio_nome']),
                      style: const TextStyle(
                          fontWeight: FontWeight.w700, fontSize: 15)),
                ),
                Text(casaEuroAdmin(p['total_cents']),
                    style: const TextStyle(fontWeight: FontWeight.w800)),
              ]),
              const SizedBox(height: Spacing.xs),
              Wrap(spacing: 6, runSpacing: 4, children: [
                CasaEtiqueta(casaEstadoPtBr(estado),
                    cor: casaEstadoCor(estado)),
                CasaEtiqueta(casaModoPtBr(p['modo']?.toString()),
                    cor: AppColors.textSecondary),
                CasaEtiqueta(casaPagamentoPtBr(p['payment_method']?.toString()),
                    cor: AppColors.textSecondary),
                if (p['is_test'] == true)
                  const CasaEtiqueta('TESTE', cor: AppColors.info),
              ]),
              const SizedBox(height: Spacing.xs),
              Text(
                'Cliente: ${casaTexto(p['cliente_nome'])} · '
                'Profissional: ${casaTexto(p['profissional_nome'])}',
                style: const TextStyle(fontSize: 12),
              ),
              Text(
                'Marcado para ${casaDataHora(p['scheduled_at'])} · '
                '${casaTexto(morada['city'])} · criado ${casaDataHora(p['created_at'])}',
                style: const TextStyle(
                    fontSize: 11, color: AppColors.textSubtle),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// Ficha
// ═══════════════════════════════════════════════════════════════════════════

class AdminCasaPedidoScreen extends StatefulWidget {
  const AdminCasaPedidoScreen({super.key, required this.id, this.rpc});
  final String id;
  final ChamarRpcPainel? rpc;

  @override
  State<AdminCasaPedidoScreen> createState() => _AdminCasaPedidoScreenState();
}

class _AdminCasaPedidoScreenState extends State<AdminCasaPedidoScreen> {
  late Future<Map<String, dynamic>> _future = _load();
  bool _busy = false;

  ChamarRpcPainel get _rpc => casaRpc(widget.rpc);

  Future<Map<String, dynamic>> _load() async => casaMapa(
      casaVerOk(await _rpc('admin_casa_pedido', {'p_id': widget.id})));

  Future<void> _refresh() async {
    setState(() {
      _future = _load();
    });
    await _future;
  }

  Future<void> _correr(
      String fn, Map<String, dynamic> params, String sucesso) async {
    if (_busy) return;
    setState(() => _busy = true);
    final ok = await casaExecutar(context, () => _rpc(fn, params), sucesso);
    if (!mounted) return;
    setState(() => _busy = false);
    if (ok) await _refresh();
  }

  // ── Ações ───────────────────────────────────────────────────────────────

  Future<void> _reatribuir(Map<String, dynamic> p) async {
    final oficio = p['oficio']?.toString();
    List<Map<String, dynamic>> pros;
    try {
      pros = casaLista(casaVerOk(await _rpc(
          'admin_casa_profissionais', {'p_estado': 'approved'})));
    } catch (e) {
      if (mounted) casaMsg(context, casaErroPtBr(e));
      return;
    }
    // Só quem tem ESTE ofício aprovado (quando o servidor manda os ofícios).
    final comOficio = pros.where((x) {
      final ofs = casaLista(x['oficios']);
      if (ofs.isEmpty) return true;
      return ofs.any((o) => o['codigo'] == oficio && o['estado'] == 'approved');
    }).toList();
    if (!mounted) return;
    final escolhido = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Reatribuir a quem?'),
        content: SizedBox(
          width: 420,
          child: comOficio.isEmpty
              ? const Text(
                  'Nenhum profissional aprovado com este ofício aprovado.')
              : ListView(
                  shrinkWrap: true,
                  children: [
                    for (final x in comOficio)
                      ListTile(
                        title: Text(casaTexto(x['name'])),
                        subtitle: Text(
                            '${casaTexto(x['phone'])} · ${casaInt(x['jobs_done'])} trabalhos'
                            '${x['is_active'] == false ? ' · pausado' : ''}'),
                        onTap: () => Navigator.pop(ctx, x),
                      ),
                  ],
                ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancelar')),
        ],
      ),
    );
    if (escolhido == null || !mounted) return;
    final nome = casaTexto(escolhido['name']);
    final ok = await casaConfirmar(
      context,
      titulo: 'Reatribuir para $nome?',
      texto: 'O pedido passa para $nome. O profissional anterior (se houver) '
          'deixa de o ver. Fica no histórico do pedido.',
      botao: 'Reatribuir',
    );
    if (ok == null) return;
    await _correr('admin_casa_reatribuir', {
      'p_pedido_id': widget.id,
      'p_profissional_id': escolhido['id'],
    }, 'Pedido reatribuído para $nome.');
  }

  Future<void> _cancelar() async {
    final motivo = await casaConfirmar(
      context,
      titulo: 'Cancelar este pedido?',
      texto: 'O cliente e o profissional são avisados. O dinheiro (se houver) '
          'segue as regras do servidor; nada é estornado por este botão.',
      botao: 'Cancelar pedido',
      perigo: true,
      pedirTexto: true,
      textoObrigatorio: true,
    );
    if (motivo == null) return;
    await _correr('admin_casa_cancelar',
        {'p_pedido_id': widget.id, 'p_motivo': motivo}, 'Pedido cancelado.');
  }

  Future<void> _marcarTeste(bool atual) async {
    final ok = await casaConfirmar(
      context,
      titulo: atual ? 'Desmarcar como teste?' : 'Marcar como teste?',
      texto: atual
          ? 'O pedido volta a contar nos números e nos acertos.'
          : 'Pedido de teste não entra nos números do painel nem nos acertos.',
      botao: atual ? 'Desmarcar' : 'Marcar teste',
    );
    if (ok == null) return;
    await _correr('admin_casa_marcar_teste',
        {'p_pedido_id': widget.id, 'p_is_test': !atual},
        atual ? 'Pedido desmarcado como teste.' : 'Pedido marcado como teste.');
  }

  Future<void> _forcarConclusao() async {
    final motivo = await casaConfirmar(
      context,
      titulo: 'Forçar a conclusão?',
      texto: 'O pedido fica como confirmado sem esperar pelo cliente. Use só '
          'quando o trabalho foi feito e o cliente não responde.',
      botao: 'Forçar conclusão',
      perigo: true,
      pedirTexto: true,
      textoObrigatorio: true,
    );
    if (motivo == null) return;
    await _correr('admin_casa_forcar_conclusao',
        {'p_pedido_id': widget.id, 'p_motivo': motivo}, 'Pedido concluído.');
  }

  Future<void> _resolverDisputa() async {
    final resolucao = await showDialog<String>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: const Text('Como fica a disputa?'),
        children: [
          for (final e in kCasaResolucoes.entries)
            SimpleDialogOption(
              onPressed: () => Navigator.pop(ctx, e.key),
              child: Text(e.value),
            ),
        ],
      ),
    );
    if (resolucao == null || !mounted) return;
    final nota = await casaConfirmar(
      context,
      titulo: kCasaResolucoes[resolucao] ?? resolucao,
      texto: resolucao == 'reembolso_pendente'
          ? 'Fica marcado "reembolso pendente". O reembolso em si NÃO é feito '
              'por aqui: é decisão de dinheiro do Danilo.'
          : 'A disputa fica resolvida e o cliente é avisado.',
      botao: 'Resolver',
      pedirTexto: true,
      textoObrigatorio: true,
      rotuloTexto: 'Nota (o que aconteceu)',
      linhas: 2,
    );
    if (nota == null) return;
    await _correr('admin_casa_resolver_disputa', {
      'p_pedido_id': widget.id,
      'p_resolucao': resolucao,
      'p_nota': nota,
    }, 'Disputa resolvida.');
  }

  // ── Desenho ─────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Pedido da Casa'),
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
              onPressed: _busy ? null : _refresh,
              icon: const Icon(Icons.refresh),
              tooltip: 'Atualizar'),
        ],
      ),
      body: FutureBuilder<Map<String, dynamic>>(
        future: _future,
        builder: (context, snap) {
          if (snap.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snap.hasError) {
            return CasaErroCarregar(erro: snap.error!, onTentar: _refresh);
          }
          return _corpo(snap.data ?? const <String, dynamic>{});
        },
      ),
    );
  }

  Widget _corpo(Map<String, dynamic> p) {
    final estado = p['estado']?.toString();
    final acoes = casaAcoesPedido(estado);
    final isTest = p['is_test'] == true;
    final morada = casaMapa(p['morada']);
    final cliente = casaMapa(p['cliente']);
    final pro = casaMapa(p['profissional']);
    final fotos = casaLista(p['fotos']);
    final orcamentos = casaLista(p['orcamentos']);
    final extras = casaLista(p['extras']);
    final mensagens = casaLista(p['mensagens']);
    final eventos = casaLista(p['eventos']);
    final ofertas = casaLista(p['ofertas']);
    final respostas = casaMapa(p['respostas']);

    return RefreshIndicator(
      onRefresh: _refresh,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(
            Spacing.lg, Spacing.md, Spacing.lg, Spacing.huge),
        children: [
          Text(casaTexto(p['servico_nome']),
              style:
                  const TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
          Text(casaTexto(p['oficio_nome'] ?? p['oficio']),
              style: const TextStyle(color: AppColors.textSecondary)),
          const SizedBox(height: Spacing.sm),
          Wrap(spacing: 6, runSpacing: 4, children: [
            CasaEtiqueta(casaEstadoPtBr(estado), cor: casaEstadoCor(estado)),
            CasaEtiqueta(casaModoPtBr(p['modo']?.toString()),
                cor: AppColors.textSecondary),
            if (isTest) const CasaEtiqueta('TESTE', cor: AppColors.info),
          ]),
          const SizedBox(height: Spacing.md),
          Wrap(spacing: Spacing.sm, runSpacing: Spacing.sm, children: [
            if (acoes.contains('reatribuir'))
              FilledButton.icon(
                key: const ValueKey('casa-pedido-reatribuir'),
                onPressed: _busy ? null : () => _reatribuir(p),
                icon: const Icon(Icons.swap_horiz, size: 18),
                label: const Text('Reatribuir'),
              ),
            if (acoes.contains('forcar_conclusao'))
              OutlinedButton(
                key: const ValueKey('casa-pedido-forcar'),
                onPressed: _busy ? null : _forcarConclusao,
                child: const Text('Forçar conclusão'),
              ),
            if (acoes.contains('resolver_disputa'))
              FilledButton(
                key: const ValueKey('casa-pedido-disputa'),
                style:
                    FilledButton.styleFrom(backgroundColor: AppColors.warning),
                onPressed: _busy ? null : _resolverDisputa,
                child: const Text('Resolver disputa'),
              ),
            OutlinedButton(
              key: const ValueKey('casa-pedido-teste'),
              onPressed: _busy ? null : () => _marcarTeste(isTest),
              child: Text(isTest ? 'Desmarcar teste' : 'Marcar como teste'),
            ),
            if (acoes.contains('cancelar'))
              OutlinedButton(
                key: const ValueKey('casa-pedido-cancelar'),
                style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.error),
                onPressed: _busy ? null : _cancelar,
                child: const Text('Cancelar pedido'),
              ),
          ]),

          const CasaSeccao('Pedido'),
          CasaLinha('Quantidade', casaDouble(p['quantidade']) % 1 == 0
              ? casaDouble(p['quantidade']).round()
              : casaDouble(p['quantidade'])),
          CasaLinha('Descrição', p['descricao']),
          for (final r in respostas.entries)
            CasaLinha('Resposta ${r.key}', r.value),
          CasaLinha('Endereço',
              '${casaTexto(morada['street'])}, ${casaTexto(morada['postal'])} ${casaTexto(morada['city'])}'),
          CasaLinha('Marcado para', casaDataHora(p['scheduled_at'])),
          CasaLinha('Duração prevista', '${casaInt(p['duracao_min'])} min'),
          CasaLinha('Criado', casaDataHora(p['created_at'])),

          const CasaSeccao('Dinheiro (do servidor)'),
          CasaLinha('Pagamento', casaPagamentoPtBr(p['payment_method']?.toString())),
          CasaLinha('Estado do pagamento',
              casaPagamentoStatusPtBr(p['payment_status']?.toString())),
          CasaLinha('Preço', casaEuroAdmin(p['preco_cents'])),
          CasaLinha('Extras', casaEuroAdmin(p['extras_cents'])),
          CasaLinha('Total do cliente', casaEuroAdmin(p['total_cents'])),
          CasaLinha('Ganho do profissional', casaEuroAdmin(p['ganho_cents'])),
          CasaLinha('Comissão Bora', casaEuroAdmin(p['comissao_cents'])),
          if (casaInt(p['cancel_fee_cents']) > 0)
            CasaLinha('Taxa de cancelamento', casaEuroAdmin(p['cancel_fee_cents'])),

          const CasaSeccao('Cliente'),
          CasaLinha('Nome', cliente['nome'] ?? p['cliente_nome']),
          CasaLinha('E-mail', cliente['email']),
          CasaLinha('Telefone', cliente['phone']),

          const CasaSeccao('Profissional'),
          if (pro.isEmpty)
            const CasaLinha('Profissional', 'Ainda sem profissional')
          else ...[
            CasaLinha('Nome', pro['name'] ?? pro['nome']),
            CasaLinha('Telefone', pro['phone']),
            CasaLinha(
                'Nota',
                '${casaDouble(pro['rating_avg']).toStringAsFixed(1).replaceAll('.', ',')} '
                    '(${casaInt(pro['ratings_count'])}) · ${casaInt(pro['jobs_done'])} trabalhos'),
            if ((pro['id'] ?? '').toString().isNotEmpty)
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton(
                  onPressed: () =>
                      Navigator.of(context).push(MaterialPageRoute<void>(
                    builder: (_) => AdminCasaProfissionalScreen(
                        id: '${pro['id']}', rpc: widget.rpc),
                  )),
                  child: const Text('Abrir ficha do profissional'),
                ),
              ),
          ],

          const CasaSeccao('Andamento'),
          CasaLinha('Aceito', casaDataHora(p['accepted_at'])),
          CasaLinha('A caminho', casaDataHora(p['on_the_way_at'])),
          CasaLinha('Chegou', casaDataHora(p['arrived_at'])),
          CasaLinha('Começou', casaDataHora(p['started_at'])),
          CasaLinha('Terminou', casaDataHora(p['done_at'])),
          CasaLinha('Cliente confirmou', casaDataHora(p['confirmed_at'])),
          if (p['cancelled_at'] != null) ...[
            CasaLinha('Cancelado', casaDataHora(p['cancelled_at']),
                cor: AppColors.error),
            CasaLinha('Cancelado por', casaPapelPtBr(p['cancelled_by']?.toString())),
            CasaLinha('Motivo', p['cancel_reason']),
          ],
          if (p['refazer_pedido_em'] != null)
            CasaLinha('Pediu para refazer', casaDataHora(p['refazer_pedido_em']),
                cor: AppColors.error),
          CasaLinha('Garantia até', casaDataHora(p['garantia_ate'])),
          CasaLinha('Nota do cliente',
              p['rating_cliente'] == null ? null : '${p['rating_cliente']} / 5'),
          CasaLinha('Comentário', p['comentario_cliente']),
          CasaLinha('Nota ao cliente',
              p['rating_profissional'] == null ? null : '${p['rating_profissional']} / 5'),

          const CasaSeccao('Fotos'),
          if (fotos.isEmpty) const CasaVazio('Sem fotos.'),
          for (final t in kCasaTiposFoto.entries)
            if (fotos.any((f) => f['tipo'] == t.key))
              _linhaFotos(t.value,
                  fotos.where((f) => f['tipo'] == t.key).toList()),

          CasaSeccao('Orçamentos (${orcamentos.length})'),
          if (orcamentos.isEmpty) const CasaVazio('Sem orçamentos.'),
          for (final o in orcamentos) _orcamento(o),

          CasaSeccao('Valores extra (${extras.length})'),
          if (extras.isEmpty) const CasaVazio('Sem pedidos de valor extra.'),
          for (final e in extras)
            ListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              title: Text('${casaEuroAdmin(e['valor_cents'])} — ${casaTexto(e['motivo'])}'),
              subtitle: Text('${casaExtraEstadoPtBr(e['estado']?.toString())} · '
                  '${casaDataHora(e['created_at'])}'),
            ),

          CasaSeccao('Conversa (${mensagens.length})'),
          if (mensagens.isEmpty) const CasaVazio('Sem mensagens.'),
          for (final m in mensagens)
            ListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              title: Text(casaTexto(m['message'])),
              subtitle: Text('${casaPapelPtBr(m['sender_role']?.toString())} · '
                  '${casaDataHora(m['created_at'])}'),
            ),

          CasaSeccao('Histórico de estados (${eventos.length})'),
          if (eventos.isEmpty) const CasaVazio('Sem histórico.'),
          for (final ev in eventos)
            ListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              title: Text('${casaEstadoPtBr(ev['estado_de']?.toString())} → '
                  '${casaEstadoPtBr(ev['estado_para']?.toString())}'),
              subtitle: Text('${casaPapelPtBr(ev['por_papel']?.toString())} · '
                  '${casaDataHora(ev['created_at'])}'
                  '${_detalhe(ev['detalhe'])}'),
            ),

          CasaSeccao('Registro de ofertas (${ofertas.length})'),
          if (ofertas.isEmpty) const CasaVazio('Ninguém foi chamado ainda.'),
          for (final o in ofertas)
            ListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              leading: Icon(
                o['tinha_aparelho'] == true
                    ? Icons.phone_android
                    : Icons.phonelink_erase,
                color: o['tinha_aparelho'] == true
                    ? AppColors.success
                    : AppColors.error,
              ),
              title: Text('${casaTexto(o['profissional_nome'])} · '
                  '${casaOfertaTipoPtBr(o['tipo']?.toString())} · ronda ${casaInt(o['ronda'])}'),
              subtitle: Text(
                  'Enviada ${casaDataHora(o['enviada_em'])} · expira ${casaDataHora(o['expira_em'])}\n'
                  '${casaOfertaRespostaPtBr(o['resposta']?.toString())}'
                  '${o['respondida_em'] == null ? '' : ' em ${casaDataHora(o['respondida_em'])}'}'),
              isThreeLine: true,
            ),
        ],
      ),
    );
  }

  String _detalhe(Object? d) {
    if (d == null) return '';
    if (d is Map && d.isEmpty) return '';
    if (d is String) return d.trim().isEmpty ? '' : '\n$d';
    try {
      return '\n${jsonEncode(d)}';
    } catch (_) {
      return '\n$d';
    }
  }

  Widget _linhaFotos(String titulo, List<Map<String, dynamic>> fotos) {
    final caminhos = [
      for (final f in fotos) (f['storage_path'] ?? '').toString(),
    ].where((c) => c.isNotEmpty).toList();
    return Padding(
      padding: const EdgeInsets.only(bottom: Spacing.xs),
      child: Row(children: [
        Expanded(child: Text('$titulo: ${fotos.length}')),
        TextButton.icon(
          onPressed: caminhos.isEmpty
              ? null
              : () => casaAbrirFotos(context,
                  balde: kBaldeCasaFotos, caminhos: caminhos, titulo: titulo),
          icon: const Icon(Icons.photo_library_outlined, size: 18),
          label: const Text('Ver'),
        ),
      ]),
    );
  }

  Widget _orcamento(Map<String, dynamic> o) {
    final pro = casaMapa(o['profissional']);
    final estado = o['estado']?.toString();
    return Card(
      margin: const EdgeInsets.only(bottom: Spacing.sm),
      child: Padding(
        padding: const EdgeInsets.all(Spacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Expanded(
                child: Text(
                    '${casaTexto(pro['name'] ?? pro['nome'])} · ${casaEuroAdmin(o['preco_cents'])}',
                    style: const TextStyle(fontWeight: FontWeight.w700)),
              ),
              CasaEtiqueta(casaOrcamentoEstadoPtBr(estado),
                  cor: estado == 'aceite'
                      ? AppColors.success
                      : estado == 'enviado'
                          ? AppColors.info
                          : AppColors.textSecondary),
            ]),
            CasaLinha('Inclui', o['inclui']),
            CasaLinha(
                'Materiais',
                '${casaTexto(o['materiais'])}'
                    '${o['materiais_incluidos'] == true ? ' (incluídos no preço)' : ' (por conta do cliente)'}'),
            CasaLinha('Prazo', o['prazo']),
            CasaLinha('Duração',
                o['duracao_min'] == null ? null : '${casaInt(o['duracao_min'])} min'),
            CasaLinha('Enviado', casaDataHora(o['created_at'])),
            CasaLinha('Expira', casaDataHora(o['expira_em'])),
          ],
        ),
      ),
    );
  }
}
