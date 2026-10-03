// BUG-OPCOES-ESTAFETA (2026-09-20) — prova VISUAL da lista de compras.
//
// O bug (pedido real 9cba3644 — McDonald's): o estafeta via o produto mas
// nunca as escolhas da cliente. Este golden fotografa a tile da lista de
// compras com o McMenu Big Mac completo (tamanho, bebida, acompanhamento,
// molho, complemento, ketchup e remoções) nas três larguras canónicas —
// o harness falha sozinho em qualquer estouro, e o PNG fica para o Danilo
// ver exactamente o que o estafeta vê.
//
// A tile é reconstruída aqui com os MESMOS widgets do
// driver_map_screen._ShoppingListSheetContent (estado pendente, loja
// não-parceira), em vez de arrastar o mapa inteiro — mesmo padrão do
// grelha_categorias_test.
import 'dart:io';

import 'package:bora_app/models/cart_item.dart';
import 'package:bora_app/models/product_option.dart';
import 'package:bora_app/widgets/driver_item_options.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fabrica_de_fotos.dart';

CartItem _mcItem() => CartItem(
      productId: '5a4f2567-c7ce-40a6-b720-67cd19317894',
      name: 'McMenu Big Mac',
      price: 12.90,
      quantity: 1,
      purchaseStatus: 'pending',
      basePrice: 11.22,
      selectedOptionsPriced: const [
        SelectedOption(group: 'Tamanho', items: ['Médio']),
        SelectedOption(group: 'Bebida', items: ['Coca-Cola Média']),
        SelectedOption(group: 'Acompanhamento', items: ['Batata']),
        SelectedOption(group: 'Molho', items: ['Sem molho']),
        SelectedOption(group: 'Complemento', items: ['Chicken McNuggets 4 (+€2.30)']),
        SelectedOption(group: 'Ketchup', items: ['Sem ketchup']),
        SelectedOption(group: 'Sem Big Mac', items: ['Sem pickles', 'Sem cebola']),
      ],
    );

/// Cópia fiel da tile da sheet (não-parceiro, pendente). Se mudar lá, muda aqui.
class _TileDaLista extends StatelessWidget {
  const _TileDaLista({required this.item});

  final CartItem item;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 4),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.grey.shade200, width: 0.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.radio_button_unchecked,
                  color: Colors.grey.shade400, size: 20),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${item.name} × ${item.quantity}',
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                        color: Colors.black87,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    DriverItemOptions(item: item),
                  ],
                ),
              ),
              Text(
                '€${(item.basePrice ?? item.price).toStringAsFixed(2)}',
                style: const TextStyle(
                  fontWeight: FontWeight.w600,
                  fontSize: 14,
                  color: Colors.black87,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ListaCompras extends StatelessWidget {
  const _ListaCompras();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                "Lista de compras — McDonald's",
                style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 16),
              _TileDaLista(item: _mcItem()),
            ],
          ),
        ),
      ),
    );
  }
}

void main() {
  setUpAll(() async {
    await carregaFonteInter();
    await carregaFontesSdk();
    gravaVersaoHarness();
  });

  for (final tam in kTamanhos) {
    testWidgets(
        'lista de compras com McMenu completo cabe e mostra as escolhas '
        '(${tam.$1})',
        (tester) async {
      await fotografaTela(
        tester,
        nome: 'estafeta_lista_compras',
        tela: const _ListaCompras(),
        tamanho: tam,
      );
      expect(
        File('test/golden/_fotos/estafeta_lista_compras_${tam.$1}.png')
            .existsSync(),
        isTrue,
      );
    });
  }
}
