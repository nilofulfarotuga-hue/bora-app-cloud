import '../models/order_service_type.dart';

/// As linhas automáticas que a app põe no PRINCÍPIO da nota do pedido
/// (`orders.customer_notes`), antes do texto que o cliente escreveu.
///
/// É a forma de levar três coisas ao parceiro, ao estafeta e ao admin sem
/// coluna nova em `orders`: talheres, troco e andar/porta/código da morada.
/// O parceiro, o estafeta e o admin já mostram a nota (29/10/2026).
///
/// Tudo aqui é função pura: o ecrã de pagamento só junta as peças e a nota
/// passa nos testes sem Flutter.
class NotaDoPedido {
  NotaDoPedido._();

  static const String semTalheres = 'SEM TALHERES';
  static const String comTalheres = 'COM TALHERES';

  /// Máximo de caracteres que o cliente escreve (o campo da nota já o impõe).
  /// As linhas automáticas juntam-se depois e não contam para este limite.
  static const int maxTextoDoCliente = 200;

  /// Só restaurante (entrega) e "ir buscar" levam talheres. Mercado, favor,
  /// encomenda e levar compras não perguntam.
  static bool perguntaTalheres(OrderServiceType tipo) =>
      tipo == OrderServiceType.restaurant || tipo == OrderServiceType.takeaway;

  /// As notas que se oferecem para o troco: só as MAIORES que o total.
  /// Sem nenhuma, não há pergunta.
  static List<int> notasParaTroco(double total) =>
      const <int>[10, 20, 50].where((n) => n > total).toList();

  static String linhaTalheres(bool preciso) =>
      preciso ? comTalheres : semTalheres;

  static String linhaTroco(int nota) => 'TROCO PARA $nota €';

  /// "MORADA: 2.º Dto · código 1234" (vazio → sem linha).
  static String? linhaMorada(String? detalhes) {
    final t = (detalhes ?? '').trim();
    return t.isEmpty ? null : 'MORADA: $t';
  }

  /// Junta as linhas automáticas ao texto do cliente.
  ///
  /// * [precisaTalheres] `null` = a pergunta não foi feita (interruptor
  ///   desligado ou tipo de pedido sem talheres): não entra linha nenhuma.
  /// * [trocoPara] `null` = pagou com valor certo ou não é dinheiro.
  /// * [textoDoCliente] e [marcaFestas] vão no fim, pela ordem em que o ecrã
  ///   de pagamento já os juntava.
  ///
  /// Devolve `null` quando não há nada para enviar.
  static String? compor({
    String? textoDoCliente,
    String? marcaFestas,
    bool? precisaTalheres,
    int? trocoPara,
    String? detalhesMorada,
  }) {
    final linhas = <String>[
      if (precisaTalheres != null) linhaTalheres(precisaTalheres),
      if (trocoPara != null) linhaTroco(trocoPara),
      if (linhaMorada(detalhesMorada) != null) linhaMorada(detalhesMorada)!,
    ];
    final texto = (textoDoCliente ?? '').trim();
    final marca = (marcaFestas ?? '').trim();
    final fim = marca.isEmpty
        ? texto
        : (texto.isEmpty ? marca : '$marca · $texto');
    if (fim.isNotEmpty) linhas.add(fim);
    return linhas.isEmpty ? null : linhas.join('\n');
  }

  /// O parceiro precisa de ver a linha dos talheres bem à vista: devolve
  /// `true` se a nota começa por uma das duas linhas automáticas.
  static bool temLinhaDeTalheres(String? nota) {
    final n = (nota ?? '').trimLeft();
    return n.startsWith(semTalheres) || n.startsWith(comTalheres);
  }
}
