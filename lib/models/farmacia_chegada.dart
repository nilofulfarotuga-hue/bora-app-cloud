// Produto que só chega mais tarde à farmácia (missão farmacias-loja-2026-11-14, bloco 3).
// Uma linha de `pedido_chegada_tardia`: a farmácia marca "chega às HH:MM" (um produto ou o
// pedido todo) e o cliente escolhe esperar, tirar o produto ou cancelar sem custo.

/// Estado da hora marcada (`pedido_chegada_tardia.estado`).
enum EstadoChegada {
  /// À espera da resposta do cliente.
  pendente,

  /// O cliente espera: o pedido fica agendado para a hora marcada.
  esperar,

  /// O cliente prefere sem o produto: a farmácia tira-o em "Marcar em falta".
  tirar,

  /// O cliente cancelou sem custo.
  cancelar,

  /// A farmácia anulou (enganou-se ou o produto chegou antes).
  anulado;

  static EstadoChegada fromDb(String? v) {
    switch (v) {
      case 'esperar':
        return EstadoChegada.esperar;
      case 'tirar':
        return EstadoChegada.tirar;
      case 'cancelar':
        return EstadoChegada.cancelar;
      case 'anulado':
        return EstadoChegada.anulado;
      case 'pendente':
      default:
        return EstadoChegada.pendente;
    }
  }

  /// Valor gravado na base / enviado a `farmacia_chegada_responder`.
  String get db => switch (this) {
        EstadoChegada.pendente => 'pendente',
        EstadoChegada.esperar => 'esperar',
        EstadoChegada.tirar => 'tirar',
        EstadoChegada.cancelar => 'cancelar',
        EstadoChegada.anulado => 'anulado',
      };

  /// Ainda segura o pedido (só pode haver uma destas por pedido).
  bool get viva => this == EstadoChegada.pendente || this == EstadoChegada.esperar;
}

/// A escolha do cliente (o que se manda a `farmacia_chegada_responder`).
enum EscolhaChegada {
  esperar,
  tirar,
  cancelar;

  String get db => switch (this) {
        EscolhaChegada.esperar => 'esperar',
        EscolhaChegada.tirar => 'tirar',
        EscolhaChegada.cancelar => 'cancelar',
      };
}

class FarmaciaChegada {
  const FarmaciaChegada({
    required this.id,
    required this.orderId,
    required this.restaurantId,
    required this.chegaAs,
    required this.estado,
    required this.criadoEm,
    this.linhaIdx,
    this.productId,
    this.produtoNome,
  });

  final String id;
  final String orderId;
  final String restaurantId;

  /// Linha de `orders.items` (0 = 1.ª). Null = o pedido todo.
  final int? linhaIdx;
  final String? productId;
  final String? produtoNome;

  /// Instante em que o produto chega (local do telemóvel; mostrar em hora de Lisboa).
  final DateTime chegaAs;
  final EstadoChegada estado;
  final DateTime criadoEm;

  /// true = um produto; false = o pedido todo.
  bool get eUmProduto => linhaIdx != null;

  static DateTime _data(Object? v) =>
      DateTime.tryParse(v?.toString() ?? '')?.toLocal() ?? DateTime.now();

  factory FarmaciaChegada.fromMap(Map<String, dynamic> m) => FarmaciaChegada(
        id: m['id'].toString(),
        orderId: m['order_id'].toString(),
        restaurantId: (m['restaurant_id'] ?? '').toString(),
        linhaIdx: (m['linha_idx'] as num?)?.toInt(),
        productId: m['product_id']?.toString(),
        produtoNome: (m['produto_nome'] as String?)?.trim().isEmpty ?? true
            ? null
            : (m['produto_nome'] as String).trim(),
        chegaAs: _data(m['chega_as']),
        estado: EstadoChegada.fromDb(m['estado']?.toString()),
        criadoEm: _data(m['criado_em']),
      );

  /// A mais recente de uma lista (a que conta para o ecrã).
  static FarmaciaChegada? maisRecente(Iterable<FarmaciaChegada> lista) {
    FarmaciaChegada? r;
    for (final c in lista) {
      if (r == null || c.criadoEm.isAfter(r.criadoEm)) r = c;
    }
    return r;
  }
}
