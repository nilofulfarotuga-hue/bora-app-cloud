// BUG-OPCOES-ESTAFETA (2026-09-20, pedido real 9cba3644 — McDonald's): a
// lista de compras do estafeta reconstruía cada CartItem SÓ com id/nome/
// preço/quantidade e descartava `selected_options`, `selected_options_priced`
// e `basePrice` — o estafeta via "McMenu Big Mac" mas nunca o tamanho, a
// bebida, o acompanhamento, os complementos nem as remoções que o cliente
// escolheu. Este ficheiro é a fonte única dessa cópia e da apresentação das
// opções, pública para o teste de regressão (test/driver_item_options_test.dart).
//
// A6 ronda-fecho (2026-09-23): a apresentação deixou de passar por
// CartItem.displayOptions (que devolve SÓ a lista com preço quando ela
// existe) — [optionsForDriver] junta as escolhas grátis e os extras pagos.
import 'package:flutter/material.dart';

import '../models/cart_item.dart';
import '../models/product_option.dart';
import '../services/weight_portions.dart';

/// Cópia defensiva dos items do pedido para a lista de compras do estafeta:
/// preserva TODOS os campos (incluindo opções e basePrice) em objects novos,
/// para o estado bought/unavailable da sheet não mutar os items do pedido
/// original. Era aqui que as opções se perdiam.
List<CartItem> copyOrderItemsForDriverSheet(List<CartItem> items) {
  return items
      .map((i) => CartItem(
            productId: i.productId,
            name: i.name,
            price: i.price,
            quantity: i.quantity,
            purchaseStatus: i.purchaseStatus,
            actualPrice: i.actualPrice,
            basePrice: i.basePrice,
            selectedOptions: i.selectedOptions,
            selectedOptionsPriced: i.selectedOptionsPriced,
          ))
      .toList();
}

/// As opções a listar ao estafeta por baixo do nome do produto: as escolhas
/// grátis (`selected_options` — "Sem cebola", "Sem molho") E os extras pagos
/// (`selected_options_priced` — "Chicken McNuggets 4 (+€2.30)"), juntos.
///
/// Não usa [CartItem.displayOptions]: esse getter devolve SÓ a lista com
/// preço quando ela existe (é o que o histórico do cliente e o painel do
/// parceiro querem) — mas se o servidor gravar em `selected_options_priced`
/// apenas os grupos pagos, as escolhas grátis desapareciam do ecrã do
/// estafeta. Regra da junção: um grupo que está nas duas listas entra UMA
/// vez, na versão com preço (a do servidor, que diz o que foi cobrado); os
/// grupos que só existem nas escolhas locais entram a seguir, pela ordem do
/// checkout. A porção ao peso ([WeightPortions.kGroupName]) sai porque já vai
/// no nome ([WeightPortions.displayName]).
List<SelectedOption> optionsForDriver(CartItem item) {
  final priced = item.selectedOptionsPriced;
  final pricedGroups = priced.map((o) => o.group).toSet();
  return [
    ...priced,
    ...item.selectedOptions.where((o) => !pricedGroups.contains(o.group)),
  ].where((o) => o.group != WeightPortions.kGroupName).toList();
}

/// Linhas com as escolhas do cliente por baixo do nome do produto: tamanho,
/// bebida, acompanhamento, complementos, molhos e remoções — as grátis e as
/// pagas, cada grupo uma só vez (ver [optionsForDriver]). Produtos sem
/// opções (pedidos antigos) não mostram nada.
class DriverItemOptions extends StatelessWidget {
  const DriverItemOptions({super.key, required this.item});

  final CartItem item;

  @override
  Widget build(BuildContext context) {
    final options = optionsForDriver(item);
    if (options.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 2),
      child: Text(
        options.map((o) => '${o.group}: ${o.items.join(', ')}').join('\n'),
        style: TextStyle(
          fontSize: 12,
          height: 1.3,
          color: Colors.grey.shade600,
        ),
      ),
    );
  }
}
