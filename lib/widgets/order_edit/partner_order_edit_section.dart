import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../config/app_colors.dart';
import '../../models/order_edit.dart';
import '../../models/order_model.dart';
import '../../models/product_option.dart';
import '../../services/order_edit_service.dart';
import '../../utils/search_text.dart';

/// Loja PARCEIRA mexe num pedido já feito (PT-PT):
///   • "Acrescentar produto" — o cliente pediu mais; fica à espera dele aceitar.
///   • "Marcar em falta" — não há; sai do pedido e o cliente recebe a diferença.
/// Só aparece com o interruptor `order_edit_enabled` ligado e enquanto o pedido
/// ainda não saiu da loja. Os números vêm sempre do servidor (orçamento).
class PartnerOrderEditSection extends StatefulWidget {
  const PartnerOrderEditSection({super.key, required this.order});

  final OrderModel order;

  /// Estados em que a loja ainda tem o pedido na mão (igual ao servidor).
  static bool podeEditar(OrderModel o) =>
      o.isPartnerStore &&
      o.takeawayPickedUpAt == null &&
      const {
        OrderStatus.created,
        OrderStatus.preparing,
        OrderStatus.readyForPickup,
        OrderStatus.callingDriver,
        OrderStatus.driverAccepted,
      }.contains(o.status);

  @override
  State<PartnerOrderEditSection> createState() => _PartnerOrderEditSectionState();
}

class _PartnerOrderEditSectionState extends State<PartnerOrderEditSection> {
  late final Future<bool> _ativo = OrderEditService.instance.ativo();
  Stream<List<OrderEditGrupo>>? _grupos;

  @override
  void initState() {
    super.initState();
    _grupos = OrderEditService.instance.gruposDoPedido(widget.order.id);
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<bool>(
      future: _ativo,
      builder: (context, snap) {
        if (snap.data != true) return const SizedBox.shrink();
        return StreamBuilder<List<OrderEditGrupo>>(
          stream: _grupos,
          builder: (context, gsnap) {
            final grupos = gsnap.data ?? const <OrderEditGrupo>[];
            final editavel = PartnerOrderEditSection.podeEditar(widget.order);
            final temPendente = grupos.any((g) =>
                g.estado == OrderEditEstado.pendenteCliente || g.aguardaPagamento);
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (final g in grupos) _EstadoGrupo(grupo: g),
                if (editavel) ...[
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          key: const Key('btn_acrescentar_produto'),
                          onPressed: temPendente
                              ? null
                              : () => _abrirAcrescentar(context),
                          icon: const Icon(Icons.add_shopping_cart_outlined, size: 18),
                          label: const Text('Acrescentar produto'),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: OutlinedButton.icon(
                          key: const Key('btn_marcar_em_falta'),
                          onPressed: widget.order.items.isEmpty
                              ? null
                              : () => _abrirEmFalta(context),
                          icon: const Icon(Icons.remove_shopping_cart_outlined, size: 18),
                          label: const Text('Marcar em falta'),
                        ),
                      ),
                    ],
                  ),
                  if (temPendente)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text(
                        'Há uma proposta à espera do cliente.',
                        style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                      ),
                    ),
                ],
              ],
            );
          },
        );
      },
    );
  }

  Future<void> _abrirEmFalta(BuildContext context) async {
    final rascunho = await showModalBottomSheet<OrderEditRascunho>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _EmFaltaSheet(order: widget.order),
    );
    if (rascunho == null || rascunho.vazio || !context.mounted) return;
    await _confirmarEEnviar(context, rascunho, tirar: true);
  }

  Future<void> _abrirAcrescentar(BuildContext context) async {
    final rascunho = await showModalBottomSheet<OrderEditRascunho>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _AcrescentarSheet(order: widget.order),
    );
    if (rascunho == null || rascunho.vazio || !context.mounted) return;
    await _confirmarEEnviar(context, rascunho, tirar: false);
  }

  Future<void> _confirmarEEnviar(BuildContext context, OrderEditRascunho r,
      {required bool tirar}) async {
    final svc = OrderEditService.instance;
    final messenger = ScaffoldMessenger.of(context);
    Map<String, dynamic> orc;
    try {
      orc = await svc.orcamento(widget.order.id, r.alteracoes);
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(mensagemErroEdicao(e))));
      return;
    }
    if (!context.mounted) return;
    final antes = (orc['total_antes'] as num?)?.toDouble() ?? 0;
    final depois = (orc['total_depois'] as num?)?.toDouble() ?? 0;
    final dif = (orc['diferenca'] as num?)?.toDouble() ?? (depois - antes);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => _ResumoDialog(
        tirar: tirar,
        totalAntes: antes,
        totalDepois: depois,
        diferenca: dif,
        linhas: ((orc['linhas'] as List?) ?? const [])
            .whereType<Map>()
            .map((l) => '${l['quantidade']}× ${l['nome']}')
            .toList(),
        pagamento: widget.order.paymentMethod,
      ),
    );
    if (ok != true || !context.mounted) return;
    try {
      await svc.propor(widget.order.id, r.alteracoes);
      messenger.showSnackBar(SnackBar(
        content: Text(tirar
            ? 'Feito. O cliente foi avisado e recebe a diferença.'
            : 'Enviado. À espera que o cliente aceite.'),
      ));
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(mensagemErroEdicao(e))));
    }
  }
}

String _eur(double v) => '${v.toStringAsFixed(2).replaceAll('.', ',')} €';

class _EstadoGrupo extends StatelessWidget {
  const _EstadoGrupo({required this.grupo});
  final OrderEditGrupo grupo;

  @override
  Widget build(BuildContext context) {
    final cor = switch (grupo.estado) {
      OrderEditEstado.pendenteCliente => AppColors.warning,
      OrderEditEstado.aceite || OrderEditEstado.aplicado => AppColors.primary,
      OrderEditEstado.recusado || OrderEditEstado.cancelado => Colors.grey.shade600,
    };
    final sinal = grupo.diferenca > 0 ? '+' : '';
    return Container(
      margin: const EdgeInsets.only(top: 6),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: cor.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: cor.withValues(alpha: 0.35)),
      ),
      child: Row(
        children: [
          Icon(grupo.eTirar ? Icons.remove_circle_outline : Icons.add_circle_outline,
              size: 18, color: cor),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              '${grupo.eTirar ? 'Em falta' : 'Acrescentar'}: ${grupo.resumo} '
              '($sinal${_eur(grupo.diferenca)})',
              style: const TextStyle(fontSize: 12.5),
            ),
          ),
          const SizedBox(width: 6),
          Text(orderEditEstadoTexto(grupo),
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: cor)),
        ],
      ),
    );
  }
}

class _ResumoDialog extends StatelessWidget {
  const _ResumoDialog({
    required this.tirar,
    required this.totalAntes,
    required this.totalDepois,
    required this.diferenca,
    required this.linhas,
    required this.pagamento,
  });

  final bool tirar;
  final double totalAntes;
  final double totalDepois;
  final double diferenca;
  final List<String> linhas;
  final PaymentMethod pagamento;

  @override
  Widget build(BuildContext context) {
    final devolucao = switch (pagamento) {
      PaymentMethod.cash => 'O cliente paga menos na entrega.',
      PaymentMethod.card => 'A diferença volta ao cartão do cliente.',
      _ => 'A diferença volta à carteira Bora do cliente.',
    };
    return AlertDialog(
      title: Text(tirar ? 'Marcar em falta' : 'Acrescentar ao pedido'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final l in linhas) Text('• $l'),
          const Divider(height: 20),
          _linha('Total antes', _eur(totalAntes)),
          _linha('Total novo', _eur(totalDepois), forte: true),
          _linha(tirar ? 'Devolvido ao cliente' : 'A mais para o cliente',
              _eur(diferenca.abs())),
          const SizedBox(height: 10),
          Text(
            tirar ? devolucao : 'O cliente recebe um aviso para aceitar ou recusar.',
            style: TextStyle(fontSize: 12.5, color: Colors.grey.shade700),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('Voltar'),
        ),
        FilledButton(
          key: const Key('btn_confirmar_edicao'),
          onPressed: () => Navigator.pop(context, true),
          child: Text(tirar ? 'Confirmar' : 'Enviar ao cliente'),
        ),
      ],
    );
  }

  Widget _linha(String a, String b, {bool forte = false}) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Row(
          children: [
            Expanded(child: Text(a)),
            Text(b,
                style: TextStyle(fontWeight: forte ? FontWeight.w800 : FontWeight.w500)),
          ],
        ),
      );
}

// ── Marcar em falta ──────────────────────────────────────────────────────────

class _EmFaltaSheet extends StatefulWidget {
  const _EmFaltaSheet({required this.order});
  final OrderModel order;

  @override
  State<_EmFaltaSheet> createState() => _EmFaltaSheetState();
}

class _EmFaltaSheetState extends State<_EmFaltaSheet> {
  late final List<int> _tirar = List.filled(widget.order.items.length, 0);

  @override
  Widget build(BuildContext context) {
    final itens = widget.order.items;
    final total = _tirar.fold<int>(0, (a, b) => a + b);
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(
            left: 16, right: 16, top: 16,
            bottom: MediaQuery.of(context).viewInsets.bottom + 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text('O que não há?',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
            const SizedBox(height: 4),
            Text('Escolhe quantas unidades saem de cada linha.',
                style: TextStyle(color: Colors.grey.shade600)),
            const SizedBox(height: 12),
            Flexible(
              child: ListView.separated(
                shrinkWrap: true,
                itemCount: itens.length,
                separatorBuilder: (_, __) => const Divider(height: 1),
                itemBuilder: (_, i) {
                  final it = itens[i];
                  final opc = it.displayOptions
                      .map((o) => '${o.group}: ${o.items.join(', ')}')
                      .join(' · ');
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    child: Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('${it.quantity} × ${it.name}',
                                  style: const TextStyle(fontWeight: FontWeight.w600)),
                              if (opc.isNotEmpty)
                                Text(opc,
                                    style: TextStyle(
                                        fontSize: 12, color: Colors.grey.shade600)),
                              Text(_eur(it.price),
                                  style: TextStyle(
                                      fontSize: 12, color: Colors.grey.shade700)),
                            ],
                          ),
                        ),
                        _Stepper(
                          valor: _tirar[i],
                          max: it.quantity,
                          onChanged: (v) => setState(() => _tirar[i] = v),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
            const SizedBox(height: 12),
            FilledButton(
              onPressed: total == 0
                  ? null
                  : () {
                      final r = OrderEditRascunho();
                      for (var i = 0; i < itens.length; i++) {
                        r.tirar(
                          linhaIdx: i,
                          productId: itens[i].productId,
                          quantidade: _tirar[i],
                          preco: itens[i].price,
                        );
                      }
                      Navigator.pop(context, r);
                    },
              child: Text(total == 0 ? 'Escolhe o que falta' : 'Ver resumo ($total)'),
            ),
          ],
        ),
      ),
    );
  }
}

class _Stepper extends StatelessWidget {
  const _Stepper({required this.valor, required this.max, required this.onChanged, this.min = 0});
  final int valor;
  final int min;
  final int max;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton(
          visualDensity: VisualDensity.compact,
          onPressed: valor > min ? () => onChanged(valor - 1) : null,
          icon: const Icon(Icons.remove_circle_outline),
        ),
        SizedBox(
          width: 24,
          child: Text('$valor',
              textAlign: TextAlign.center,
              style: const TextStyle(fontWeight: FontWeight.w700)),
        ),
        IconButton(
          visualDensity: VisualDensity.compact,
          onPressed: valor < max ? () => onChanged(valor + 1) : null,
          icon: const Icon(Icons.add_circle_outline),
        ),
      ],
    );
  }
}

// ── Acrescentar produto ──────────────────────────────────────────────────────

class _ProdutoLoja {
  final String id;
  final String nome;
  final double preco;
  final String? foto;
  final String categoria;
  const _ProdutoLoja(this.id, this.nome, this.preco, this.foto, this.categoria);
}

class _Escolha {
  final _ProdutoLoja produto;
  final int quantidade;
  final List<SelectedOption> opcoes;
  final double precoUnitario;
  const _Escolha(this.produto, this.quantidade, this.opcoes, this.precoUnitario);
}

class _AcrescentarSheet extends StatefulWidget {
  const _AcrescentarSheet({required this.order});
  final OrderModel order;

  @override
  State<_AcrescentarSheet> createState() => _AcrescentarSheetState();
}

class _AcrescentarSheetState extends State<_AcrescentarSheet> {
  final _pesquisa = TextEditingController();
  List<_ProdutoLoja>? _produtos;
  String? _erro;
  final List<_Escolha> _escolhas = [];

  @override
  void initState() {
    super.initState();
    _carregar();
    _pesquisa.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _pesquisa.dispose();
    super.dispose();
  }

  Future<void> _carregar() async {
    final rid = widget.order.restaurantId;
    if (rid == null) {
      setState(() => _erro = 'Loja desconhecida.');
      return;
    }
    try {
      final rows = await Supabase.instance.client
          .from('products')
          .select('id,name,price,photo_url,category,is_available')
          .eq('restaurant_id', rid)
          .eq('is_available', true)
          .order('name');
      final lista = (rows as List)
          .cast<Map<String, dynamic>>()
          .map((m) => _ProdutoLoja(
                m['id'] as String,
                (m['name'] as String?) ?? '',
                (m['price'] as num?)?.toDouble() ?? 0,
                m['photo_url'] as String?,
                (m['category'] as String?) ?? '',
              ))
          .toList();
      if (mounted) setState(() => _produtos = lista);
    } catch (e) {
      if (mounted) setState(() => _erro = 'Não foi possível carregar os produtos.');
    }
  }

  Future<void> _escolher(_ProdutoLoja p) async {
    final e = await showModalBottomSheet<_Escolha>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _OpcoesProdutoSheet(produto: p),
    );
    if (e != null) setState(() => _escolhas.add(e));
  }

  @override
  Widget build(BuildContext context) {
    final todos = _produtos ?? const <_ProdutoLoja>[];
    final q = _pesquisa.text;
    final filtrados = todos
        .where((p) => correspondePesquisa('${p.nome} ${p.categoria}', q))
        .toList();
    final altura = MediaQuery.of(context).size.height * 0.85;
    return SafeArea(
      child: SizedBox(
        height: altura,
        child: Padding(
          padding: EdgeInsets.only(
              left: 16, right: 16, top: 16,
              bottom: MediaQuery.of(context).viewInsets.bottom + 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text('Acrescentar produto',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
              const SizedBox(height: 10),
              TextField(
                key: const Key('pesquisa_produto_pedido'),
                controller: _pesquisa,
                autofocus: false,
                decoration: InputDecoration(
                  hintText: 'Pesquisar produto…',
                  prefixIcon: const Icon(Icons.search),
                  suffixIcon: q.isEmpty
                      ? null
                      : IconButton(
                          icon: const Icon(Icons.clear),
                          onPressed: _pesquisa.clear,
                        ),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                  isDense: true,
                ),
              ),
              const SizedBox(height: 8),
              if (_escolhas.isNotEmpty)
                Wrap(
                  spacing: 6,
                  runSpacing: 4,
                  children: [
                    for (var i = 0; i < _escolhas.length; i++)
                      InputChip(
                        label: Text(
                            '${_escolhas[i].quantidade}× ${_escolhas[i].produto.nome}'),
                        onDeleted: () => setState(() => _escolhas.removeAt(i)),
                      ),
                  ],
                ),
              Expanded(
                child: _erro != null
                    ? Center(child: Text(_erro!))
                    : _produtos == null
                        ? const Center(child: CircularProgressIndicator())
                        : filtrados.isEmpty
                            ? const Center(child: Text('Nenhum produto encontrado.'))
                            : ListView.separated(
                                itemCount: filtrados.length,
                                separatorBuilder: (_, __) => const Divider(height: 1),
                                itemBuilder: (_, i) {
                                  final p = filtrados[i];
                                  return ListTile(
                                    contentPadding: EdgeInsets.zero,
                                    leading: ClipRRect(
                                      borderRadius: BorderRadius.circular(8),
                                      child: SizedBox(
                                        width: 44,
                                        height: 44,
                                        child: (p.foto ?? '').isEmpty
                                            ? Container(
                                                color: Colors.grey.shade200,
                                                child: const Icon(Icons.fastfood_outlined,
                                                    size: 20),
                                              )
                                            : Image.network(p.foto!,
                                                fit: BoxFit.cover,
                                                errorBuilder: (_, __, ___) =>
                                                    Container(color: Colors.grey.shade200)),
                                      ),
                                    ),
                                    title: Text(p.nome),
                                    subtitle: Text(_eur(p.preco)),
                                    trailing: const Icon(Icons.add_circle_outline),
                                    onTap: () => _escolher(p),
                                  );
                                },
                              ),
              ),
              const SizedBox(height: 8),
              FilledButton(
                onPressed: _escolhas.isEmpty
                    ? null
                    : () {
                        final r = OrderEditRascunho();
                        for (final e in _escolhas) {
                          r.acrescentar(
                            productId: e.produto.id,
                            quantidade: e.quantidade,
                            precoUnitarioComExtras: e.precoUnitario,
                            opcoes: e.opcoes,
                          );
                        }
                        Navigator.pop(context, r);
                      },
                child: Text(_escolhas.isEmpty
                    ? 'Escolhe um produto'
                    : 'Ver resumo (${_escolhas.length})'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Opções/extras do produto, com as mesmas regras do carrinho do cliente
/// (mínimo/máximo por grupo; extras pagos somam ao preço).
class _OpcoesProdutoSheet extends StatefulWidget {
  const _OpcoesProdutoSheet({required this.produto});
  final _ProdutoLoja produto;

  @override
  State<_OpcoesProdutoSheet> createState() => _OpcoesProdutoSheetState();
}

class _OpcoesProdutoSheetState extends State<_OpcoesProdutoSheet> {
  List<ProductOptionGroup>? _grupos;
  final Map<String, Set<String>> _sel = {};
  int _qtd = 1;

  @override
  void initState() {
    super.initState();
    _carregar();
  }

  Future<void> _carregar() async {
    try {
      final res = await Supabase.instance.client
          .from('product_option_groups')
          .select(
              'id,product_id,name,description,is_required,min_choices,max_choices,sort_order,product_option_items(id,name,price_add,is_available,sort_order)')
          .eq('product_id', widget.produto.id)
          .order('sort_order');
      final lista = (res as List)
          .map((e) => ProductOptionGroup.fromMap(e as Map<String, dynamic>))
          .toList()
        ..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
      if (mounted) setState(() => _grupos = lista);
    } catch (_) {
      if (mounted) setState(() => _grupos = const []);
    }
  }

  int _conta(ProductOptionGroup g) => _sel[g.id]?.length ?? 0;
  bool get _ok => (_grupos ?? const []).every((g) => _conta(g) >= g.minChoices);

  double get _extras {
    var s = 0.0;
    for (final g in _grupos ?? const <ProductOptionGroup>[]) {
      final ids = _sel[g.id] ?? const <String>{};
      for (final it in g.items) {
        if (ids.contains(it.id)) s += it.priceAdd;
      }
    }
    return s;
  }

  void _toggle(ProductOptionGroup g, ProductOptionItem it) {
    if (!it.isAvailable) return;
    final set = _sel.putIfAbsent(g.id, () => <String>{});
    setState(() {
      if (g.maxChoices <= 1) {
        set
          ..clear()
          ..add(it.id);
      } else if (set.contains(it.id)) {
        set.remove(it.id);
      } else if (set.length < g.maxChoices) {
        set.add(it.id);
      }
    });
  }

  List<SelectedOption> get _opcoes => [
        for (final g in _grupos ?? const <ProductOptionGroup>[])
          if ((_sel[g.id] ?? const <String>{}).isNotEmpty)
            SelectedOption(
              group: g.name,
              items: g.items
                  .where((it) => _sel[g.id]!.contains(it.id))
                  .map((it) => it.name)
                  .toList(),
            ),
      ];

  @override
  Widget build(BuildContext context) {
    final unit = widget.produto.preco + _extras;
    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.85),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(widget.produto.nome,
                  style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
              Text(_eur(widget.produto.preco),
                  style: TextStyle(color: Colors.grey.shade700)),
              const SizedBox(height: 8),
              if (_grupos == null)
                const Padding(
                  padding: EdgeInsets.all(16),
                  child: Center(child: CircularProgressIndicator()),
                )
              else
                Flexible(
                  child: ListView(
                    shrinkWrap: true,
                    children: [
                      for (final g in _grupos!) ...[
                        Padding(
                          padding: const EdgeInsets.only(top: 10, bottom: 4),
                          child: Text(
                            '${g.name}'
                            '${g.minChoices > 0 ? ' (obrigatório)' : ''}'
                            ' · ${_conta(g)}/${g.maxChoices}',
                            style: const TextStyle(fontWeight: FontWeight.w700),
                          ),
                        ),
                        for (final it in g.items)
                          CheckboxListTile(
                            dense: true,
                            contentPadding: EdgeInsets.zero,
                            value: _sel[g.id]?.contains(it.id) ?? false,
                            onChanged: it.isAvailable ? (_) => _toggle(g, it) : null,
                            title: Text(it.name),
                            secondary: it.priceAdd > 0
                                ? Text('+${_eur(it.priceAdd)}')
                                : null,
                          ),
                      ],
                    ],
                  ),
                ),
              const SizedBox(height: 8),
              Row(
                children: [
                  const Text('Quantidade'),
                  const Spacer(),
                  _Stepper(
                    valor: _qtd,
                    min: 1,
                    max: 20,
                    onChanged: (v) => setState(() => _qtd = v),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              FilledButton(
                onPressed: _grupos == null || !_ok
                    ? null
                    : () => Navigator.pop(
                          context,
                          _Escolha(widget.produto, _qtd, _opcoes, unit),
                        ),
                child: Text('Juntar · ${_eur(unit * _qtd)}'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
