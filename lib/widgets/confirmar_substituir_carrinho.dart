import 'package:flutter/material.dart';

import '../l10n/tr.dart';
import '../stores/cart_store.dart';

/// "PEDIR DE NOVO" PERGUNTA PRIMEIRO (melhorias-paridade 26/10, item 7).
///
/// Antes, `ReorderService.applyTo` esvaziava o carrinho atual sem dizer nada
/// (reorder_service.dart, `cart.clearCart()`). Agora, com artigos no
/// carrinho, pergunta-se antes. Carrinho vazio: segue sem perguntar.
/// Devolve `true` quando se pode substituir.
Future<bool> confirmarSubstituirCarrinho(
  BuildContext context,
  CartStore cart,
) async {
  if (cart.items.isEmpty) return true;
  final loja = cart.vendorName ?? '';
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text('Substituir o carrinho?'.tr),
      content: Text(loja.isEmpty
          ? 'Já tens artigos no carrinho. Se continuares, são trocados pelos do pedido anterior.'
              .tr
          : 'Já tens artigos de {0} no carrinho. Se continuares, são trocados pelos do pedido anterior.'
              .trArgs([loja])),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, false),
          child: Text('Manter o carrinho'.tr),
        ),
        TextButton(
          onPressed: () => Navigator.pop(ctx, true),
          child: Text('Substituir'.tr),
        ),
      ],
    ),
  );
  return ok == true;
}
