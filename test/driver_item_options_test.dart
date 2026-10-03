// BUG-OPCOES-ESTAFETA (2026-09-20) — teste de regressão do pedido REAL
// 9cba3644-5733-4fe4-9898-d24b896ff3f9 (McDonald's, McMenu Big Mac).
//
// A cliente escolheu: Médio · Coca-Cola Média · Batata · Chicken McNuggets 4 ·
// sem molho · sem ketchup · Big Mac sem pickles · Big Mac sem cebola. Tudo
// isso está gravado em orders.items (selected_options + selected_options_priced)
// mas o estafeta NÃO via nada: a lista de compras reconstruía o CartItem sem
// as opções (driver_map_screen._showShoppingListSheet).
//
// Este teste prova o caminho COMPLETO até à apresentação ao estafeta:
//   DB (row Supabase) → OrderModel.fromSupabase → CartItem.fromJson
//   → copyOrderItemsForDriverSheet (a cópia que a sheet usa)
//   → DriverItemOptions (o widget que a sheet renderiza).
//
// Grupos conforme os reais do McMenu Big Mac no catálogo (relatório
// FASE2_OPCOES_GLOVO_2026_06_09.md): Tamanho · Bebida · Acompanhamento ·
// Molho · Complemento · Ketchup · Sem Big Mac.
import 'package:bora_app/models/order_model.dart';
import 'package:bora_app/services/weight_portions.dart';
import 'package:bora_app/widgets/driver_item_options.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:bora_app/models/cart_item.dart';
import 'package:bora_app/models/product_option.dart';

/// Row equivalente à do pedido real 9cba3644: restaurante não-parceiro
/// (McDonald's), cash, um McMenu Big Mac com TODAS as escolhas da cliente
/// nos dois formatos que a DB grava.
Map<String, dynamic> _mcOrderRow() => {
      'id': '9cba3644-5733-4fe4-9898-d24b896ff3f9',
      'status': 'driverAccepted',
      'service_type': 'restaurant',
      'order_type': 'nonPartnerPurchase',
      'payment_method': 'cash',
      'price': 12.90,
      'vendor_name': "McDonald's",
      'is_partner_store': false,
      'items': [
        {
          'productId': '5a4f2567-c7ce-40a6-b720-67cd19317894',
          'name': 'McMenu Big Mac',
          'price': 12.90,
          'quantity': 1,
          'purchaseStatus': 'pending',
          'basePrice': 11.22,
          'selected_options': [
            {'group': 'Tamanho', 'items': ['Médio']},
            {'group': 'Bebida', 'items': ['Coca-Cola Média']},
            {'group': 'Acompanhamento', 'items': ['Batata']},
            {'group': 'Molho', 'items': ['Sem molho']},
            {'group': 'Complemento', 'items': ['Chicken McNuggets 4']},
            {'group': 'Ketchup', 'items': ['Sem ketchup']},
            {
              'group': 'Sem Big Mac',
              'items': ['Sem pickles', 'Sem cebola'],
            },
          ],
          'selected_options_priced': [
            {
              'group': 'Tamanho',
              'items': [
                {'name': 'Médio', 'price_add': 0},
              ]
            },
            {
              'group': 'Bebida',
              'items': [
                {'name': 'Coca-Cola Média', 'price_add': 0},
              ]
            },
            {
              'group': 'Acompanhamento',
              'items': [
                {'name': 'Batata', 'price_add': 0},
              ]
            },
            {
              'group': 'Molho',
              'items': [
                {'name': 'Sem molho', 'price_add': 0},
              ]
            },
            {
              'group': 'Complemento',
              'items': [
                {'name': 'Chicken McNuggets 4', 'price_add': 2.30},
              ]
            },
            {
              'group': 'Ketchup',
              'items': [
                {'name': 'Sem ketchup', 'price_add': 0},
              ]
            },
            {
              'group': 'Sem Big Mac',
              'items': [
                {'name': 'Sem pickles', 'price_add': 0},
                {'name': 'Sem cebola', 'price_add': 0},
              ]
            },
          ],
        },
      ],
    };

void main() {
  test(
      'DB → modelo: as escolhas do pedido 9cba3644 chegam inteiras ao OrderModel',
      () {
    final order = OrderModel.fromSupabase(_mcOrderRow());
    expect(order.items, hasLength(1));
    final item = order.items.single;

    expect(item.name, 'McMenu Big Mac');
    expect(item.basePrice, 11.22);

    // selected_options (escolhas puras do checkout)
    final grupos = item.selectedOptions.map((o) => o.group).toList();
    expect(grupos, [
      'Tamanho',
      'Bebida',
      'Acompanhamento',
      'Molho',
      'Complemento',
      'Ketchup',
      'Sem Big Mac',
    ]);
    expect(
        item.selectedOptions.firstWhere((o) => o.group == 'Bebida').items,
        ['Coca-Cola Média']);
    expect(
        item.selectedOptions
            .firstWhere((o) => o.group == 'Sem Big Mac')
            .items,
        ['Sem pickles', 'Sem cebola']);

    // selected_options_priced (versão do servidor com preço)
    expect(item.selectedOptionsPriced, hasLength(7));

    // SEM DUPLICAÇÃO: displayOptions prefere a versão com preço do servidor
    // e nunca junta as duas (7 grupos, não 14).
    expect(item.displayOptions, hasLength(7));
    expect(item.displayOptions, same(item.selectedOptionsPriced));
  });

  test(
      'REGRESSÃO: a cópia da lista de compras preserva as opções e o basePrice '
      '(o bug de 2026-09-20 descartava-as aqui)', () {
    final order = OrderModel.fromSupabase(_mcOrderRow());
    final sheetItems = copyOrderItemsForDriverSheet(order.items);
    final sheetItem = sheetItems.single;

    // As escolhas sobrevivem à cópia defensiva que a sheet recebe.
    expect(sheetItem.displayOptions, hasLength(7));
    expect(sheetItem.basePrice, 11.22);
    expect(
        sheetItem.displayOptions
            .firstWhere((o) => o.group == 'Complemento')
            .items,
        ['Chicken McNuggets 4 (+€2.30)']);
    expect(
        sheetItem.displayOptions.firstWhere((o) => o.group == 'Molho').items,
        ['Sem molho']);
    expect(
        sheetItem.displayOptions
            .firstWhere((o) => o.group == 'Sem Big Mac')
            .items,
        ['Sem pickles', 'Sem cebola']);

    // A cópia é defensiva: marcar comprado na sheet não mexe no pedido.
    sheetItem.purchaseStatus = 'bought';
    expect(order.items.single.purchaseStatus, 'pending');
    expect(identical(sheetItem, order.items.single), isFalse);
  });

  testWidgets(
      'apresentação ao estafeta: o McMenu Big Mac mostra tamanho, bebida, '
      'acompanhamento, complemento, molhos e remoções', (tester) async {
    final order = OrderModel.fromSupabase(_mcOrderRow());
    final sheetItem = copyOrderItemsForDriverSheet(order.items).single;

    // A MESMA disposição da lista de compras: nome em cima, opções por baixo.
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '${WeightPortions.displayName(sheetItem)} × ${sheetItem.quantity}',
              ),
              DriverItemOptions(item: sheetItem),
            ],
          ),
        ),
      ),
    ));

    expect(find.text('McMenu Big Mac × 1'), findsOneWidget);
    expect(find.textContaining('Tamanho: Médio'), findsOneWidget);
    expect(find.textContaining('Bebida: Coca-Cola Média'), findsOneWidget);
    expect(find.textContaining('Acompanhamento: Batata'), findsOneWidget);
    expect(find.textContaining('Molho: Sem molho'), findsOneWidget);
    expect(
        find.textContaining('Complemento: Chicken McNuggets 4 (+€2.30)'),
        findsOneWidget);
    expect(find.textContaining('Ketchup: Sem ketchup'), findsOneWidget);
    expect(
        find.textContaining('Sem Big Mac: Sem pickles, Sem cebola'),
        findsOneWidget);

    // SEM DUPLICAÇÃO no texto renderizado: cada grupo aparece UMA vez
    // (displayOptions não juntou selected_options com selected_options_priced).
    final textoOpcoes = tester.widget<Text>(find.descendant(
      of: find.byType(DriverItemOptions),
      matching: find.byType(Text),
    ));
    final dados = textoOpcoes.data!;
    for (final grupo in [
      'Tamanho:',
      'Bebida:',
      'Acompanhamento:',
      'Molho:',
      'Complemento:',
      'Ketchup:',
      'Sem Big Mac:',
    ]) {
      expect(dados.split(grupo).length - 1, 1,
          reason: '"$grupo" devia aparecer exatamente 1 vez em:\n$dados');
    }
    expect(tester.takeException(), isNull);
  });

  test(
      'sem selected_options_priced cai nas selected_options (pedido antigo '
      'com opções gravadas antes do T1)', () {
    final row = _mcOrderRow();
    (row['items'] as List).single.remove('selected_options_priced');
    final order = OrderModel.fromSupabase(row);
    final item = order.items.single;

    expect(item.selectedOptionsPriced, isEmpty);
    expect(item.displayOptions, hasLength(7));
    expect(
        item.displayOptions
            .firstWhere((o) => o.group == 'Complemento')
            .items,
        ['Chicken McNuggets 4']); // nome puro, sem preço
  });

  testWidgets(
      'pedido ANTIGO sem opções nenhumas: não mostra nada nem parte '
      '(compatibilidade)', (tester) async {
    final order = OrderModel.fromSupabase({
      'id': '00000000-0000-0000-0000-000000000001',
      'status': 'driverAccepted',
      'service_type': 'restaurant',
      'payment_method': 'cash',
      'price': 6.50,
      'vendor_name': "McDonald's",
      'items': [
        {
          'productId': '899e5e6b-7fa0-4a27-a86e-2fe3aa1426f1',
          'name': 'Big Mac',
          'price': 6.50,
          'quantity': 2,
          'purchaseStatus': 'pending',
        },
      ],
    });
    final sheetItem = copyOrderItemsForDriverSheet(order.items).single;

    expect(sheetItem.displayOptions, isEmpty);
    expect(sheetItem.selectedOptionsPriced, isEmpty);

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Column(
          children: [
            const Text('Big Mac × 2'),
            DriverItemOptions(item: sheetItem),
          ],
        ),
      ),
    ));
    expect(find.text('Big Mac × 2'), findsOneWidget);
    expect(find.byType(Text).evaluate(), hasLength(1)); // só o nome
    expect(find.textContaining('Tamanho:'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('produto ao peso: a porção vai no nome e NÃO se repete nas '
      'opções', (tester) async {
    final item = CartItem(
      productId: '7c6144bc-421b-44d3-8edb-17bdd5c842d1',
      name: 'Abóbora Cabotiá (ao peso)',
      price: 2.85,
      selectedOptions: const [
        SelectedOption(
            group: 'Escolhe a quantidade', items: ['500 g (meio quilo)']),
        SelectedOption(group: 'Extras', items: ['Sem sal']),
      ],
    );

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('${WeightPortions.displayName(item)} × 1'),
              DriverItemOptions(item: item),
            ],
          ),
        ),
      ),
    ));

    expect(
        find.text('Abóbora Cabotiá (ao peso) — 500 g (meio quilo) × 1'),
        findsOneWidget);
    expect(find.textContaining('Escolhe a quantidade:'), findsNothing);
    expect(find.textContaining('Extras: Sem sal'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  // ── A6 ronda-fecho (2026-09-23): grátis E pagas, juntas ─────────────────

  test('optionsForDriver junta as escolhas grátis com os extras pagos: um '
      'grupo que está nas duas listas entra UMA vez (na versão com preço), '
      'os só-grátis entram a seguir, a porção ao peso sai', () {
    final item = CartItem(
      productId: '5a4f2567-c7ce-40a6-b720-67cd19317894',
      name: 'McMenu Big Mac',
      price: 12.90,
      selectedOptions: const [
        SelectedOption(group: 'Molho', items: ['Sem molho']),
        SelectedOption(group: 'Complemento', items: ['Chicken McNuggets 4']),
        SelectedOption(
          group: 'Sem Big Mac',
          items: ['Sem pickles', 'Sem cebola'],
        ),
      ],
      selectedOptionsPriced: const [
        SelectedOption(
          group: 'Complemento',
          items: ['Chicken McNuggets 4 (+€2.30)'],
        ),
      ],
    );

    final opts = optionsForDriver(item);
    expect(opts.map((o) => o.group), ['Complemento', 'Molho', 'Sem Big Mac']);
    expect(opts[0].items, ['Chicken McNuggets 4 (+€2.30)']); // com preço
    expect(opts[1].items, ['Sem molho']);
    expect(opts[2].items, ['Sem pickles', 'Sem cebola']);

    // O que o getter partilhado faz (e por isso não serve ao estafeta):
    // só a lista com preço → 1 grupo, "Sem cebola" escondido.
    expect(item.displayOptions, hasLength(1));

    // Porção ao peso nas duas listas: sai das duas (já vai no nome).
    final aoPeso = CartItem(
      productId: '7c6144bc-421b-44d3-8edb-17bdd5c842d1',
      name: 'Abóbora Cabotiá (ao peso)',
      price: 2.85,
      selectedOptions: const [
        SelectedOption(
          group: WeightPortions.kGroupName,
          items: ['500 g (meio quilo)'],
        ),
      ],
      selectedOptionsPriced: const [
        SelectedOption(
          group: WeightPortions.kGroupName,
          items: ['500 g (meio quilo) (+€1.43)'],
        ),
      ],
    );
    expect(optionsForDriver(aoPeso), isEmpty);
    expect(
      WeightPortions.displayName(aoPeso),
      'Abóbora Cabotiá (ao peso) — 500 g (meio quilo) (+€1.43)',
    );
  });

  testWidgets(
    'REGRESSÃO: escolhas grátis SÓ em selected_options + extra pago SÓ em '
    'selected_options_priced → o estafeta vê as duas, cada grupo uma vez',
    (tester) async {
      final row = _mcOrderRow();
      final rawItem = (row['items'] as List).single as Map<String, dynamic>;
      // Servidor a gravar com preço SÓ o grupo pago. CartItem.displayOptions
      // (que o histórico do cliente e o painel do parceiro usam) devolve só
      // isto — e escondia ao estafeta "Sem cebola", "Sem molho", a bebida...
      rawItem['selected_options_priced'] = [
        {
          'group': 'Complemento',
          'items': [
            {'name': 'Chicken McNuggets 4', 'price_add': 2.30},
          ],
        },
      ];
      final order = OrderModel.fromSupabase(row);
      final sheetItem = copyOrderItemsForDriverSheet(order.items).single;
      expect(sheetItem.displayOptions, hasLength(1)); // o porquê do bug
      expect(sheetItem.selectedOptions, hasLength(7)); // o que estava gravado

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${WeightPortions.displayName(sheetItem)} × ${sheetItem.quantity}',
                  ),
                  DriverItemOptions(item: sheetItem),
                ],
              ),
            ),
          ),
        ),
      );

      // O extra pago, com o preço cobrado.
      expect(
        find.textContaining('Complemento: Chicken McNuggets 4 (+€2.30)'),
        findsOneWidget,
      );
      // As escolhas grátis que displayOptions escondia.
      expect(find.textContaining('Tamanho: Médio'), findsOneWidget);
      expect(find.textContaining('Bebida: Coca-Cola Média'), findsOneWidget);
      expect(find.textContaining('Acompanhamento: Batata'), findsOneWidget);
      expect(find.textContaining('Molho: Sem molho'), findsOneWidget);
      expect(find.textContaining('Ketchup: Sem ketchup'), findsOneWidget);
      expect(
        find.textContaining('Sem Big Mac: Sem pickles, Sem cebola'),
        findsOneWidget,
      );

      // Cada grupo UMA vez — o "Complemento" que está nas duas listas não se
      // repete, e o nome puro (sem preço) não aparece uma 2.ª vez.
      final dados = tester
          .widget<Text>(
            find.descendant(
              of: find.byType(DriverItemOptions),
              matching: find.byType(Text),
            ),
          )
          .data!;
      for (final grupo in [
        'Tamanho:',
        'Bebida:',
        'Acompanhamento:',
        'Molho:',
        'Complemento:',
        'Ketchup:',
        'Sem Big Mac:',
      ]) {
        expect(
          dados.split(grupo).length - 1,
          1,
          reason: '"$grupo" devia aparecer exatamente 1 vez em:\n$dados',
        );
      }
      expect(
        dados.split('Chicken McNuggets 4').length - 1,
        1,
        reason: 'o complemento pago não pode repetir-se sem preço:\n$dados',
      );
      expect(tester.takeException(), isNull);
    },
  );
}
