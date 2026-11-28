/// LOJA FECHADA — o travão da app ao CRIAR o pedido (27/11/2026, caso
/// Sabores do Brasil às 21:38, ordem do Danilo).
///
/// A app só recusa um pedido de loja parceira fechada quando ele é mesmo "para
/// agora": sem hora marcada (janela escolhida no carrinho) e sem ser encomenda
/// de festa (item da prateleira `Para festa (encomenda)`, data marcada a
/// seguir com `festas_set_schedule`). O servidor continua a ser a fonte de
/// verdade (`_store_closed_guard_orders` → `STORE_CLOSED`,
/// `_orders_agendado_na_criacao`).
///
/// Função pura, num ficheiro à parte, para o travão do `OrderStore` (zona
/// trancada) a chamar com uma linha e para os testes a provarem com relógio
/// fixo.
library;

import '../models/cart_item.dart';
import '../models/restaurant_model.dart';
import '../services/agendar_pedido_service.dart';

/// O carrinho de uma loja de Festas leva algum item de encomenda? (Carrinho
/// misto = festa, regra de 25/08.) [categoriaDoProduto] é a
/// `RestaurantStore.productCategoryById`.
bool itensComEncomendaFesta(
  List<CartItem>? itens,
  String? Function(String productId)? categoriaDoProduto,
) {
  if (itens == null || categoriaDoProduto == null) return false;
  return itens.any(
      (i) => categoriaDoProduto(i.productId) == kFestasPrateleiraEncomenda);
}

/// A loja [loja] está fechada e o pedido NÃO pode seguir? `false` quando a
/// loja está aberta, quando não se conhece a loja (decide o servidor), quando
/// há hora marcada para ela ou quando é encomenda de festa.
bool lojaFechadaTravaPedido({
  required RestaurantModel? loja,
  bool horaMarcada = false,
  bool encomendaFesta = false,
  DateTime? agora,
}) {
  if (loja == null) return false;
  if (loja.isOpenNow(agora)) return false;
  if (horaMarcada) return false;
  if (encomendaFesta && loja.belongsTo(BusinessCategory.festas)) return false;
  return true;
}

/// A forma de chamar a partir do `OrderStore.createOrder` /
/// `startCardPaymentDraft`: lê a hora escolhida no carrinho
/// ([AgendarPedidoEstado]) e as prateleiras dos itens.
bool lojaFechadaTravaPedidoDoCarrinho({
  required RestaurantModel? loja,
  required List<CartItem>? itens,
  required String? Function(String productId)? categoriaDoProduto,
  AgendarPedidoEstado? estado,
  DateTime? agora,
}) {
  final e = estado ?? AgendarPedidoEstado.instance;
  return lojaFechadaTravaPedido(
    loja: loja,
    horaMarcada: loja != null && e.ligado && e.escolhaPara(loja.id),
    encomendaFesta: itensComEncomendaFesta(itens, categoriaDoProduto),
    agora: agora,
  );
}
