// Preço de BALCÃO (o que o estafeta paga na caixa da loja) — fonte única
// para o ecrã do estafeta: cartão laranja "TENS DE FAZER A COMPRA", lista de
// compras ("Ver compras"), total no topo da lista e valor sugerido do talão.
//
// 14/11/2026 (missão estafeta-lento, B.6b, pedido 7f527ceb Jyosmi Sushi): o
// `basePrice` gravado nos items é o do produto SEM as opções; as opções pagas
// vêm em `selected_options_priced[].items[].price_add`. Balcão de uma linha =
// (basePrice + soma dos price_add) × quantidade — o mesmo que o TOTAL BALCÃO do
// Telegram. Só ecrã: a conta do servidor não passa por aqui.

import '../config/business_rules.dart';
import '../models/cart_item.dart';

/// Preço de balcão de UMA unidade.
///
/// Sem `basePrice` (dados antigos) o `price` já traz as opções: reverte-se o
/// markup do não-parceiro (round(price ÷ 1,15) recupera a base exata); no
/// parceiro o `price` já é o de balcão.
double precoBalcaoUnidade(CartItem i, {bool parceiro = false}) {
  final b = i.basePriceWithOptions;
  if (b != null) return b;
  if (parceiro) return i.price;
  return ((i.price / (1 + BRBusiness.NON_PARTNER_MARKUP_RATIO)) * 100)
          .roundToDouble() /
      100;
}

/// Preço de balcão da linha inteira (unidade × quantidade).
double precoBalcaoLinha(CartItem i, {bool parceiro = false}) =>
    precoBalcaoUnidade(i, parceiro: parceiro) * i.quantity;

/// Total a pagar na caixa pelas linhas dadas.
double totalBalcao(Iterable<CartItem> items, {bool parceiro = false}) =>
    items.fold<double>(0, (s, i) => s + precoBalcaoLinha(i, parceiro: parceiro));
