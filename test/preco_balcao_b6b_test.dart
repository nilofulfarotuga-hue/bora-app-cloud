// 14/11/2026 (missão estafeta-lento, B.6b + adendo 2): o caso real do pedido
// 7f527ceb (Jyosmi Sushi). O balcão é 46,00 € (11 + 2 Média e 12 + 21 Grande)
// e a app do estafeta dizia 23,00 € no cartão e 11,00 € / 12,00 € na lista.
// Fonte única: lib/services/preco_balcao.dart.

import 'package:bora_app/models/cart_item.dart';
import 'package:bora_app/models/order_model.dart';
import 'package:bora_app/screens/driver_map_screen.dart';
import 'package:bora_app/services/preco_balcao.dart';
import 'package:bora_app/widgets/driver_item_options.dart';
import 'package:bora_app/widgets/payments/loja_pagamento.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

CartItem _linha(String nome, double price, double base, String opcao,
        double add) =>
    CartItem.fromJson({
      'productId': nome.toLowerCase().replaceAll(' ', '-'),
      'name': nome,
      'price': price,
      'basePrice': base,
      'quantity': 1,
      'selected_options_priced': [
        {
          'group': 'Tamanho',
          'items': [
            {'name': opcao, 'price_add': add}
          ]
        }
      ],
    });

final _itens = [
  _linha('Caixa de Sushi Fritos', 14.95, 11, 'Média (18 peças)', 2),
  _linha('Combinado de Fusão', 37.95, 12, 'Grande (44 peças)', 21),
];

OrderModel _pedido() => OrderModel(
      id: '7f527ceb-0000-4000-8000-000000000b6b',
      total: 60,
      serviceType: OrderServiceType.restaurant,
      orderType: OrderType.nonPartnerPurchase,
      isPartnerStore: false,
      status: OrderStatus.driverAccepted,
      paymentMethod: PaymentMethod.cash,
      lojaPagamentoEstado: 'fazer_compra',
      items: _itens,
      vendorName: 'Jyosmi Sushi',
    );

void main() {
  test('uma só conta: 13,00 + 33,00 = 46,00 €', () {
    expect(_itens.map(precoBalcaoLinha), [13.0, 33.0]);
    expect(totalBalcao(_itens), closeTo(46.0, 0.0001));
    expect(estimativaCompraLoja(_pedido()), closeTo(46.0, 0.0001));
  });

  testWidgets('cartão laranja: Valor estimado 46,00 €', (t) async {
    await t.pumpWidget(MaterialApp(
        home: Scaffold(body: FaixaDinheiroEstafeta(order: _pedido()))));
    expect(find.text('TENS DE FAZER A COMPRA'), findsOneWidget);
    expect(
        find.text('Paga na caixa e tira foto do talão. Valor estimado: 46,00 €'),
        findsOneWidget);
  });

  testWidgets('lista: a opção diz só o tamanho, sem "(+2,00 €)"', (t) async {
    await t.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Column(children: [
          for (final i in copyOrderItemsForDriverSheet(_itens))
            DriverItemOptions(item: i),
        ]),
      ),
    ));
    expect(find.text('Tamanho: Média (18 peças)'), findsOneWidget);
    expect(find.text('Tamanho: Grande (44 peças)'), findsOneWidget);
    expect(find.textContaining('(+'), findsNothing);
    // E a cópia da lista continua a saber o preço das opções.
    expect(copyOrderItemsForDriverSheet(_itens).map(precoBalcaoLinha),
        [13.0, 33.0]);
  });

  testWidgets('talão: o valor sugerido é o mesmo 46,00 €', (t) async {
    await t.pumpWidget(MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: ReceiptCaptureSheet(
              isCash: false, valorEstimado: totalBalcao(_itens)),
        ),
      ),
    ));
    await t.pump();
    expect(find.text('Valor estimado: 46,00 €'), findsOneWidget);
  });
}
