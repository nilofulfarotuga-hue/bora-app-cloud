// BUG-OPCOES-ESTAFETA (2026-09-20, pedido real 9cba3644 — McDonald's): a
// lista de compras do estafeta reconstruía cada CartItem SÓ com id/nome/
// preço/quantidade e descartava `selected_options`, `selected_options_priced`
// e `basePrice` — o estafeta via "McMenu Big Mac" mas nunca o tamanho, a
// bebida, o acompanhamento, os complementos nem as remoções que o cliente
// escolheu. Este ficheiro é a fonte única dessa cópia e da apresentação das
// opções, pública para o teste de regressão (test/driver_item_options_test.dart).
import 'package:flutter/material.dart';

import '../models/cart_item.dart';
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

/// Linhas com as escolhas do cliente por baixo do nome do produto: tamanho,
/// bebida, acompanhamento, complementos, molhos e remoções.
///
/// Usa [CartItem.displayOptions] — mostra as opções COM preço quando o
/// servidor as gravou (`selected_options_priced`, histórico) e só as locais
/// (`selected_options`) quando não; nunca as duas ao mesmo tempo → sem
/// duplicação. A porção ao peso não se repete porque já vai no nome
/// ([WeightPortions.displayName]). Produtos sem opções (pedidos antigos)
/// não mostram nada.
class DriverItemOptions extends StatelessWidget {
  const DriverItemOptions({super.key, required this.item});

  final CartItem item;

  @override
  Widget build(BuildContext context) {
    final options = WeightPortions.optionsWithoutWeight(item);
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
