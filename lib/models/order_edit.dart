import 'product_option.dart';

/// Estado de uma alteração feita pela loja parceira a um pedido já feito.
/// Espelha `order_edits.estado` (CHECK no servidor).
enum OrderEditEstado { pendenteCliente, aceite, recusado, aplicado, cancelado }

OrderEditEstado orderEditEstadoFromDb(String? raw) {
  switch (raw) {
    case 'aceite':
      return OrderEditEstado.aceite;
    case 'recusado':
      return OrderEditEstado.recusado;
    case 'aplicado':
      return OrderEditEstado.aplicado;
    case 'cancelado':
      return OrderEditEstado.cancelado;
    case 'pendente_cliente':
    default:
      return OrderEditEstado.pendenteCliente;
  }
}

enum OrderEditTipo { add, remove, qty }

OrderEditTipo orderEditTipoFromDb(String? raw) {
  switch (raw) {
    case 'remove':
      return OrderEditTipo.remove;
    case 'qty':
      return OrderEditTipo.qty;
    case 'add':
    default:
      return OrderEditTipo.add;
  }
}

/// Uma linha de `order_edits` (um produto dentro de uma proposta).
class OrderEditLinha {
  final String id;
  final String grupoId;
  final String orderId;
  final String restaurantId;
  final String? editadoPor;
  final OrderEditTipo tipo;
  final int? linhaIdx;
  final String? productId;
  final String nome;
  final List<SelectedOption> opcoes;
  final int quantidade;
  final double precoUnitario;
  final double subtotalAntes;
  final double subtotalDepois;
  final double totalAntes;
  final double totalDepois;
  final OrderEditEstado estado;
  final String? motivo;
  final Map<String, dynamic> liquidacao;
  final DateTime? respondidoEm;
  final DateTime? aplicadoEm;
  final DateTime criadoEm;

  const OrderEditLinha({
    required this.id,
    required this.grupoId,
    required this.orderId,
    required this.restaurantId,
    required this.editadoPor,
    required this.tipo,
    required this.linhaIdx,
    required this.productId,
    required this.nome,
    required this.opcoes,
    required this.quantidade,
    required this.precoUnitario,
    required this.subtotalAntes,
    required this.subtotalDepois,
    required this.totalAntes,
    required this.totalDepois,
    required this.estado,
    required this.motivo,
    required this.liquidacao,
    required this.respondidoEm,
    required this.aplicadoEm,
    required this.criadoEm,
  });

  static double _d(dynamic v) => (v as num?)?.toDouble() ?? 0;

  factory OrderEditLinha.fromMap(Map<String, dynamic> m) => OrderEditLinha(
        id: m['id'] as String,
        grupoId: m['grupo_id'] as String,
        orderId: m['order_id'] as String,
        restaurantId: (m['restaurant_id'] as String?) ?? '',
        editadoPor: m['editado_por'] as String?,
        tipo: orderEditTipoFromDb(m['tipo'] as String?),
        linhaIdx: m['linha_idx'] as int?,
        productId: m['product_id'] as String?,
        nome: (m['nome'] as String?) ?? '',
        opcoes: ((m['opcoes'] as List?) ?? const [])
            .whereType<Map<String, dynamic>>()
            .map(SelectedOption.fromJson)
            .toList(),
        quantidade: (m['quantidade'] as int?) ?? 1,
        precoUnitario: _d(m['preco_unitario']),
        subtotalAntes: _d(m['subtotal_antes']),
        subtotalDepois: _d(m['subtotal_depois']),
        totalAntes: _d(m['total_antes']),
        totalDepois: _d(m['total_depois']),
        estado: orderEditEstadoFromDb(m['estado'] as String?),
        motivo: m['motivo'] as String?,
        liquidacao: (m['liquidacao'] as Map?)?.cast<String, dynamic>() ?? const {},
        respondidoEm: DateTime.tryParse('${m['respondido_em'] ?? ''}'),
        aplicadoEm: DateTime.tryParse('${m['aplicado_em'] ?? ''}'),
        criadoEm: DateTime.tryParse('${m['criado_em'] ?? ''}') ?? DateTime.now(),
      );
}

/// Uma proposta inteira (todas as linhas com o mesmo `grupo_id`).
class OrderEditGrupo {
  final String grupoId;
  final List<OrderEditLinha> linhas;

  OrderEditGrupo(this.grupoId, this.linhas) : assert(linhas.isNotEmpty);

  OrderEditLinha get _p => linhas.first;
  String get orderId => _p.orderId;
  OrderEditEstado get estado => _p.estado;
  bool get eTirar => linhas.every((l) => l.tipo == OrderEditTipo.remove);
  double get totalAntes => _p.totalAntes;
  double get totalDepois => _p.totalDepois;
  double get diferenca => _round2(totalDepois - totalAntes);
  DateTime get criadoEm => _p.criadoEm;
  String? get motivo => _p.motivo;
  Map<String, dynamic> get liquidacao => _p.liquidacao;

  /// "2× Açaí 500ml, 1× Água" — o que o cliente/parceiro lê.
  String get resumo =>
      linhas.map((l) => '${l.quantidade}× ${l.nome}').join(', ');

  /// À espera de pagamento da diferença (cliente aceitou, cartão/MB Way).
  bool get aguardaPagamento =>
      estado == OrderEditEstado.aceite && liquidacao['estado'] == 'a_cobrar';

  /// Agrupa linhas soltas (ordem: mais recente primeiro).
  static List<OrderEditGrupo> agrupar(Iterable<OrderEditLinha> linhas) {
    final porGrupo = <String, List<OrderEditLinha>>{};
    for (final l in linhas) {
      porGrupo.putIfAbsent(l.grupoId, () => []).add(l);
    }
    final grupos = porGrupo.entries
        .map((e) => OrderEditGrupo(e.key, e.value))
        .toList()
      ..sort((a, b) => b.criadoEm.compareTo(a.criadoEm));
    return grupos;
  }
}

double _round2(double v) => (v * 100).roundToDouble() / 100;

/// Texto do estado para o parceiro e para o cliente (PT-PT).
String orderEditEstadoTexto(OrderEditGrupo g) {
  switch (g.estado) {
    case OrderEditEstado.pendenteCliente:
      return 'À espera do cliente';
    case OrderEditEstado.aceite:
      return g.aguardaPagamento ? 'Aceite · a pagar' : 'Aceite';
    case OrderEditEstado.recusado:
      return 'Recusado';
    case OrderEditEstado.aplicado:
      return g.eTirar ? 'Em falta · devolvido' : 'Aceite';
    case OrderEditEstado.cancelado:
      return 'Cancelado';
  }
}

/// Rascunho que o parceiro monta antes de enviar. Só serve para montar o JSON
/// `alteracoes` que o servidor recebe e para uma conta rápida do subtotal
/// enquanto o orçamento do servidor não chega. **O número que vale é sempre o
/// do servidor** (`order_edit_quote`) — ele é que aplica taxas e comissões.
class OrderEditRascunho {
  final List<Map<String, dynamic>> _alteracoes = [];
  double _deltaSubtotal = 0;

  bool get vazio => _alteracoes.isEmpty;
  List<Map<String, dynamic>> get alteracoes => List.unmodifiable(_alteracoes);
  double get deltaSubtotal => _round2(_deltaSubtotal);

  /// Tirar [quantidade] unidades da linha [linhaIdx] (preço unitário [preco]).
  void tirar({
    required int linhaIdx,
    required String productId,
    required int quantidade,
    required double preco,
  }) {
    if (quantidade <= 0) return;
    _alteracoes.add({
      'tipo': 'remove',
      'linha_idx': linhaIdx,
      'product_id': productId,
      'quantidade': quantidade,
    });
    _deltaSubtotal -= _round2(preco) * quantidade;
  }

  /// Acrescentar um produto (com as opções escolhidas, como no carrinho).
  void acrescentar({
    required String productId,
    required int quantidade,
    required double precoUnitarioComExtras,
    List<SelectedOption> opcoes = const [],
  }) {
    if (quantidade <= 0) return;
    _alteracoes.add({
      'tipo': 'add',
      'product_id': productId,
      'quantidade': quantidade,
      if (opcoes.isNotEmpty) 'opcoes': opcoes.map((o) => o.toJson()).toList(),
    });
    _deltaSubtotal += _round2(precoUnitarioComExtras) * quantidade;
  }
}
