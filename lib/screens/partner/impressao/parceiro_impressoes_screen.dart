// Painel do parceiro — pedidos de impressão e de personalizados (missão a3-guarda-16-11, parte 2).
// - ImpressaoPedidosCartao: cartão no topo do separador Pedidos (só lojas com o serviço ligado),
//   com o número à espera e o TOQUE PERSISTENTE enquanto houver algum por responder
//   (o mesmo das receitas das farmácias, PADRAO_BORA 1.6).
// - ParceiroImpressoesScreen: lista em tempo real + separador "Preços" (tabela da loja).
// - ParceiroImpressaoDetalheScreen: abrir/descarregar os ficheiros (link assinado) e
//   "Aceitar" / "Pronto" / "Entregue" / "Não posso fazer"; nos personalizados, mandar o preço.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../config/app_colors.dart';
import '../../../models/pedido_impressao.dart';
import '../../../models/restaurant_model.dart';
import '../../../services/impressao_service.dart';
import '../../../services/incoming_job_alert.dart';
import '../../../services/sound_service.dart';
import '../../../widgets/bora/bora_bottom_action_bar.dart';

String _hora(DateTime d) =>
    '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')} ${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';

bool _aEsperaDaLoja(PedidoImpressao p) => p.estado == ImpressaoEstado.enviado;

String _rotuloLoja(PedidoImpressao p) {
  switch (p.estado) {
    case ImpressaoEstado.enviado:
      return p.personalizado ? 'Mande o preço ao cliente' : 'À espera que aceite';
    case ImpressaoEstado.orcamentado:
      return 'Preço enviado — à espera do cliente';
    case ImpressaoEstado.aceite:
      return 'Aceite — a preparar';
    case ImpressaoEstado.pronto:
      return p.entrega ? 'Pronto — a aguardar estafeta' : 'Pronto — à espera do cliente';
    default:
      return impressaoEstadoTexto(p.estado, personalizado: p.personalizado);
  }
}

/// Lê "12,34" / "12.34" / "12" → cêntimos. Null se não for válido. [permiteZero] para tabelas.
int? centsDeTexto(String s, {bool permiteZero = false}) {
  final t = s.trim().replaceAll('€', '').replaceAll(' ', '').replaceAll(',', '.');
  if (t.isEmpty) return null;
  final v = double.tryParse(t);
  if (v == null || v < 0 || (!permiteZero && v == 0) || v > 5000) return null;
  return (v * 100).round();
}

// ───────────────────────────────────────────────────────────────── cartão + alarme

class ImpressaoPedidosCartao extends StatefulWidget {
  const ImpressaoPedidosCartao({super.key, required this.restaurant});
  final RestaurantModel restaurant;

  @override
  State<ImpressaoPedidosCartao> createState() => _ImpressaoPedidosCartaoState();
}

class _ImpressaoPedidosCartaoState extends State<ImpressaoPedidosCartao> {
  final _svc = ImpressaoService();
  final _som = SoundService();
  StreamSubscription<List<PedidoImpressao>>? _sub;
  List<PedidoImpressao> _lista = const [];
  final Set<String> _avisados = {};
  bool _ligado = false;
  bool _aTocar = false;

  @override
  void initState() {
    super.initState();
    _arrancar();
  }

  Future<void> _arrancar() async {
    final l = await _svc.loja(widget.restaurant.id);
    if (!mounted || l == null || !l.ligado) return;
    setState(() => _ligado = true);
    _sub = _svc.daLoja(widget.restaurant.id).listen(_aoMudar, onError: (_) {});
  }

  void _aoMudar(List<PedidoImpressao> l) {
    if (!mounted) return;
    setState(() => _lista = l);
    final aEspera = l.where(_aEsperaDaLoja).toList();
    if (aEspera.isNotEmpty && !_aTocar) {
      _aTocar = true;
      unawaited(_som.playLoop());
      HapticFeedback.heavyImpact();
    } else if (aEspera.isEmpty && _aTocar) {
      _aTocar = false;
      unawaited(_som.stop());
    }
    for (final p in aEspera) {
      if (_avisados.add(p.id)) {
        unawaited(IncomingJobAlert.show(
          id: p.id,
          type: p.personalizado ? 'personalizado_novo' : 'impressao_nova',
          title: p.personalizado ? 'Pedido de personalizado' : 'Novo pedido de impressão',
          body: p.personalizado ? 'Toque para ver e mandar o preço.' : '${p.resumo} — toque para aceitar.',
          extraPayload: {'orderId': p.id},
        ));
      }
    }
  }

  @override
  void dispose() {
    _sub?.cancel();
    if (_aTocar) unawaited(_som.stop());
    super.dispose();
  }

  Future<void> _abrir() async {
    if (_aTocar) {
      _aTocar = false;
      unawaited(_som.stop());
    }
    await Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => ParceiroImpressoesScreen(restaurantId: widget.restaurant.id, lojaNome: widget.restaurant.name),
    ));
  }

  @override
  Widget build(BuildContext context) {
    if (!_ligado) return const SizedBox.shrink();
    final n = _lista.where(_aEsperaDaLoja).length;
    final destaque = n > 0;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Material(
        color: destaque ? AppColors.primary : Colors.white,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          key: const ValueKey('impressao_pedidos_cartao'),
          borderRadius: BorderRadius.circular(16),
          onTap: _abrir,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(children: [
              Icon(Icons.print, size: 30, color: destaque ? Colors.white : AppColors.primary),
              const SizedBox(width: 12),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('Impressões e personalizados',
                      style: TextStyle(
                          fontSize: 17, fontWeight: FontWeight.w800, color: destaque ? Colors.white : AppColors.textPrimary)),
                  const SizedBox(height: 2),
                  Text(
                    destaque ? '$n à espera de resposta — toque para responder' : 'Sem pedidos à espera · preços',
                    style: TextStyle(color: destaque ? Colors.white : AppColors.textSecondary),
                  ),
                ]),
              ),
              Icon(Icons.chevron_right, color: destaque ? Colors.white : AppColors.textSecondary),
            ]),
          ),
        ),
      ),
    );
  }
}

// ───────────────────────────────────────────────────────────────── lista + preços

class ParceiroImpressoesScreen extends StatelessWidget {
  const ParceiroImpressoesScreen({super.key, required this.restaurantId, required this.lojaNome});
  final String restaurantId;
  final String lojaNome;

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        backgroundColor: AppColors.background,
        appBar: AppBar(
          title: const Text('Impressões e personalizados'),
          bottom: const TabBar(tabs: [Tab(text: 'Pedidos'), Tab(text: 'Preços')]),
        ),
        body: TabBarView(children: [
          _ListaPedidos(restaurantId: restaurantId),
          ParceiroImpressaoPrecos(restaurantId: restaurantId),
        ]),
      ),
    );
  }
}

class _ListaPedidos extends StatelessWidget {
  const _ListaPedidos({required this.restaurantId});
  final String restaurantId;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<PedidoImpressao>>(
      stream: ImpressaoService().daLoja(restaurantId),
      builder: (context, snap) {
        if (snap.hasError) {
          return const Center(child: Padding(padding: EdgeInsets.all(24), child: Text('Não foi possível carregar os pedidos.')));
        }
        if (!snap.hasData) return const Center(child: CircularProgressIndicator());
        final l = snap.data!;
        if (l.isEmpty) {
          return const Center(
            child: Padding(
              padding: EdgeInsets.all(32),
              child: Text('Ainda não há pedidos de impressão.\nQuando chegar um, o telemóvel toca até responder.',
                  textAlign: TextAlign.center),
            ),
          );
        }
        return ListView.separated(
          padding: const EdgeInsets.all(16),
          itemCount: l.length,
          separatorBuilder: (_, __) => const SizedBox(height: 10),
          itemBuilder: (context, i) {
            final p = l[i];
            final espera = _aEsperaDaLoja(p);
            return Material(
              color: Colors.white,
              borderRadius: BorderRadius.circular(14),
              child: InkWell(
                borderRadius: BorderRadius.circular(14),
                onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => ParceiroImpressaoDetalheScreen(pedidoId: p.id))),
                child: Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: espera ? AppColors.primary : AppColors.divider, width: espera ? 2 : 1),
                  ),
                  child: Row(children: [
                    Icon(p.personalizado ? Icons.card_giftcard : Icons.print, color: AppColors.primary, size: 28),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(p.personalizado ? 'Personalizado' : p.resumo,
                            style: const TextStyle(fontWeight: FontWeight.w700), maxLines: 2, overflow: TextOverflow.ellipsis),
                        const SizedBox(height: 2),
                        Text('${_hora(p.createdAt)} · ${p.entrega ? 'entrega' : 'levantar na loja'}${p.isDemo ? ' · TESTE' : ''}',
                            style: const TextStyle(color: AppColors.textSecondary, fontSize: 13)),
                        const SizedBox(height: 4),
                        Text(_rotuloLoja(p),
                            style: TextStyle(color: espera ? AppColors.primaryDark : AppColors.textSecondary, fontWeight: FontWeight.w700)),
                      ]),
                    ),
                    if (p.artigoCents != null)
                      Text(euros(p.artigoCents), style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
                  ]),
                ),
              ),
            );
          },
        );
      },
    );
  }
}

// ───────────────────────────────────────────────────────────────── detalhe

class ParceiroImpressaoDetalheScreen extends StatefulWidget {
  const ParceiroImpressaoDetalheScreen({super.key, required this.pedidoId, this.service});
  final String pedidoId;
  final ImpressaoService? service;

  @override
  State<ParceiroImpressaoDetalheScreen> createState() => _ParceiroImpressaoDetalheScreenState();
}

class _ParceiroImpressaoDetalheScreenState extends State<ParceiroImpressaoDetalheScreen> {
  ImpressaoService get _svc => widget.service ?? ImpressaoService();
  bool _ocupado = false;

  Future<void> _abrirFicheiro(String path) async {
    final url = await _svc.urlAssinado(path);
    if (url == null) {
      _msg('Não foi possível abrir o ficheiro.');
      return;
    }
    await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
  }

  void _msg(String m) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));
  }

  Future<void> _fazer(String acao, {int? valor, String? motivo, String? codigo}) async {
    setState(() => _ocupado = true);
    try {
      await _svc.lojaResponder(widget.pedidoId, acao, valorCents: valor, motivo: motivo, codigo: codigo);
    } on ImpressaoErro catch (e) {
      _msg(e.mensagem);
    } finally {
      if (mounted) setState(() => _ocupado = false);
    }
  }

  Future<String?> _pedirTexto(String titulo, String dica, {TextInputType tipo = TextInputType.text}) {
    final c = TextEditingController();
    return showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(titulo),
        content: TextField(controller: c, autofocus: true, keyboardType: tipo, decoration: InputDecoration(hintText: dica)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Voltar')),
          FilledButton(onPressed: () => Navigator.pop(ctx, c.text), child: const Text('Confirmar')),
        ],
      ),
    );
  }

  Future<void> _orcamentar() async {
    final t = await _pedirTexto('Preço do personalizado', 'Ex.: 12,50 (preço de balcão)',
        tipo: const TextInputType.numberWithOptions(decimal: true));
    if (t == null) return;
    final v = centsDeTexto(t);
    if (v == null) return _msg('Escreva um preço válido, por exemplo 12,50.');
    await _fazer('orcamentar', valor: v);
  }

  Future<void> _recusar() async {
    final t = await _pedirTexto('Não pode fazer?', 'Diga ao cliente porquê (opcional)');
    if (t == null) return;
    await _fazer('recusar', motivo: t);
  }

  Future<void> _entregue(PedidoImpressao p) async {
    String? codigo;
    if (!p.entrega) {
      codigo = await _pedirTexto('Código de levantamento', 'O cliente mostra um código de 6 letras/números');
      if (codigo == null) return;
    }
    await _fazer('entregue', codigo: codigo?.trim().toUpperCase());
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<PedidoImpressao?>(
      stream: _svc.acompanhar(widget.pedidoId),
      builder: (context, snap) {
        final p = snap.data;
        return Scaffold(
          backgroundColor: AppColors.background,
          appBar: AppBar(title: Text(p?.personalizado == true ? 'Personalizado' : 'Pedido de impressão')),
          body: p == null
              ? const Center(child: CircularProgressIndicator())
              : ListView(padding: const EdgeInsets.all(16), children: [
                  if (p.isDemo)
                    Container(
                      padding: const EdgeInsets.all(12),
                      margin: const EdgeInsets.only(bottom: 12),
                      decoration: BoxDecoration(color: AppColors.accent.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(12)),
                      child: const Text('Pedido de TESTE: nada foi cobrado ao cliente.', style: TextStyle(fontWeight: FontWeight.w700)),
                    ),
                  Text(_rotuloLoja(p), style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
                  const SizedBox(height: 4),
                  Text('Recebido ${_hora(p.createdAt)} · ${p.entrega ? 'entrega pelo Bora' : 'levantar na loja'}',
                      style: const TextStyle(color: AppColors.textSecondary)),
                  const SizedBox(height: 16),
                  if (!p.personalizado) ...[
                    const Text('O que imprimir', style: TextStyle(fontWeight: FontWeight.w800)),
                    const SizedBox(height: 6),
                    Text(p.resumo),
                    if (p.intervalo != null) Text('Páginas: ${p.intervalo}'),
                    const SizedBox(height: 12),
                    const Text('Ficheiros', style: TextStyle(fontWeight: FontWeight.w800)),
                    for (final f in p.ficheiros)
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: Icon(f.tipo == 'pdf' ? Icons.picture_as_pdf : Icons.image, color: AppColors.primary),
                        title: Text(f.nome, maxLines: 1, overflow: TextOverflow.ellipsis),
                        subtitle: Text('${f.paginas} pág.'),
                        trailing: const Icon(Icons.download),
                        onTap: () => _abrirFicheiro(f.path),
                      ),
                    if (p.ficheiros.isEmpty) const Text('Ficheiros já apagados (30 dias depois de concluído).'),
                  ] else ...[
                    const Text('Pedido do cliente', style: TextStyle(fontWeight: FontWeight.w800)),
                    const SizedBox(height: 6),
                    if (p.textoPersonalizado != null) Text('Texto: "${p.textoPersonalizado}"'),
                    Text('Quantidade: ${p.copias}'),
                    if (p.fotoPath != null)
                      TextButton.icon(
                        onPressed: () => _abrirFicheiro(p.fotoPath!),
                        icon: const Icon(Icons.image),
                        label: const Text('Abrir a foto do cliente'),
                      ),
                    const Text('Lembre-se: envie a prova ao cliente antes de produzir.',
                        style: TextStyle(color: AppColors.textSecondary)),
                  ],
                  if (p.nota != null) ...[const SizedBox(height: 10), Text('Nota do cliente: ${p.nota}')],
                  if (p.entrega && p.morada != null) ...[const SizedBox(height: 10), Text('Morada: ${p.morada}')],
                  const SizedBox(height: 16),
                  if (p.artigoCents != null)
                    Text('Valor da loja (balcão): ${euros(p.artigoCents)}',
                        style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
                ]),
          bottomNavigationBar: p == null ? null : _barra(p),
        );
      },
    );
  }

  Widget? _barra(PedidoImpressao p) {
    final botoes = <Widget>[];
    Widget principal(String t, VoidCallback f) => SizedBox(
          height: 52,
          child: FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.primary),
            onPressed: _ocupado ? null : f,
            child: Text(t, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
          ),
        );
    switch (p.estado) {
      case ImpressaoEstado.enviado:
        botoes.add(p.personalizado ? principal('Mandar o preço', _orcamentar) : principal('Aceitar', () => _fazer('aceitar')));
        botoes.add(TextButton(onPressed: _ocupado ? null : _recusar, child: const Text('Não posso fazer')));
        break;
      case ImpressaoEstado.aceite:
        botoes.add(principal('Pronto', () => _fazer('pronto')));
        break;
      case ImpressaoEstado.pronto:
        botoes.add(principal(p.entrega ? 'Entregue ao estafeta' : 'O cliente levantou', () => _entregue(p)));
        break;
      default:
        return null;
    }
    return BoraBottomActionBar(children: botoes);
  }
}

// ───────────────────────────────────────────────────────────────── tabela de preços

class ParceiroImpressaoPrecos extends StatefulWidget {
  const ParceiroImpressaoPrecos({super.key, required this.restaurantId, this.titulo});
  final String restaurantId;

  /// No admin aparece com outro título (PT-BR); na loja, null.
  final String? titulo;

  @override
  State<ParceiroImpressaoPrecos> createState() => _ParceiroImpressaoPrecosState();
}

class _ParceiroImpressaoPrecosState extends State<ParceiroImpressaoPrecos> {
  final _svc = ImpressaoService();
  final Map<String, TextEditingController> _c = {};
  bool _provisorio = false;
  bool _aCarregar = true;
  bool _aGravar = false;

  @override
  void initState() {
    super.initState();
    _carregar();
  }

  Future<void> _carregar() async {
    try {
      final p = await _svc.precos(widget.restaurantId);
      if (!mounted) return;
      setState(() {
        _provisorio = p.values.any((e) => e.provisorio);
        for (final k in ImpressaoService.chavesPreco.keys) {
          final v = p[k]?.valor;
          _c[k] = TextEditingController(
              text: v == null ? '' : (k == 'a3_fator_pct' ? '$v' : (v / 100).toStringAsFixed(2).replaceAll('.', ',')));
        }
        _aCarregar = false;
      });
    } catch (_) {
      if (mounted) setState(() => _aCarregar = false);
    }
  }

  @override
  void dispose() {
    for (final c in _c.values) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _gravar() async {
    final valores = <String, int>{};
    for (final e in _c.entries) {
      final int? v = e.key == 'a3_fator_pct' ? int.tryParse(e.value.text.trim()) : centsDeTexto(e.value.text, permiteZero: true);
      if (v == null || v < 0) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Valor inválido em "${ImpressaoService.chavesPreco[e.key]}".')));
        return;
      }
      valores[e.key] = v;
    }
    setState(() => _aGravar = true);
    try {
      await _svc.precosDefinir(widget.restaurantId, valores);
      if (!mounted) return;
      setState(() => _provisorio = false);
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Preços gravados.')));
    } on ImpressaoErro catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.mensagem)));
    } finally {
      if (mounted) setState(() => _aGravar = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_aCarregar) return const Center(child: CircularProgressIndicator());
    return ListView(padding: const EdgeInsets.all(16), children: [
      if (widget.titulo != null) Text(widget.titulo!, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
      if (_provisorio)
        Container(
          margin: const EdgeInsets.only(bottom: 12, top: 8),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(color: AppColors.accent.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(12)),
          child: const Text('Preços provisórios — mudem para os vossos e carreguem em Gravar.',
              style: TextStyle(fontWeight: FontWeight.w700)),
        ),
      const Text('Preço de balcão (o que cobram na loja). O cliente vê o preço com as taxas do Bora.',
          style: TextStyle(color: AppColors.textSecondary)),
      const SizedBox(height: 12),
      for (final e in ImpressaoService.chavesPreco.entries)
        Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: TextField(
            controller: _c[e.key],
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: InputDecoration(
              labelText: e.value,
              suffixText: e.key == 'a3_fator_pct' ? '%' : '€',
              border: const OutlineInputBorder(),
            ),
          ),
        ),
      const SizedBox(height: 8),
      SizedBox(
        height: 52,
        child: FilledButton(
          style: FilledButton.styleFrom(backgroundColor: AppColors.primary),
          onPressed: _aGravar ? null : _gravar,
          child: Text(_aGravar ? 'A gravar…' : 'Gravar preços', style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
        ),
      ),
    ]);
  }
}
