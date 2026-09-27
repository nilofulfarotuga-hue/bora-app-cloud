// Missão redondo-total-2026-09-26, bloco B9 — prova da venda ao peso no ecrã
// de produto, com os dados REAIS da base (lidos por SELECT a 27/09/2026):
//   products 58584f34-4477-4d4c-be22-ca5ed9f4a9d1 "Jiló (ao peso)",
//   Sabores de Casa Açaí (parceiro), price 1.75 (porção de 200 g),
//   shelf_price_per_kg 7.5, sold_by_weight true;
//   product_option_groups "<id>-gq" "Escolhe a quantidade", obrigatório,
//   1 escolha; itens 200 g +0 · 300 g +0.88 · 400 g +1.75 ·
//   500 g (meio quilo) +2.63 · 1 kg +7.
// O ecrã verdadeiro (ProductDetailScreen) lê o grupo do Supabase; aqui o
// cliente HTTP devolve essa mesma linha, e nada sai para a rede.
import 'dart:convert';

import 'package:bora_app/models/partner_product.dart';
import 'package:bora_app/screens/product_detail_screen.dart';
import 'package:bora_app/stores/cart_store.dart';
import 'package:bora_app/stores/restaurant_store.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

const _jiloId = '58584f34-4477-4d4c-be22-ca5ed9f4a9d1';

final _grupoReal = [
  {
    'id': '$_jiloId-gq',
    'product_id': _jiloId,
    'name': 'Escolhe a quantidade',
    'description': 'Preço calculado ao peso.',
    'is_required': true,
    'min_choices': 1,
    'max_choices': 1,
    'sort_order': 0,
    'product_option_items': [
      {'id': 'aefcde01-b76a-4868-95a4-181f73f6bfc6', 'name': '200 g', 'price_add': 0, 'is_available': true, 'sort_order': 0},
      {'id': '05b335d0-ac6a-4722-a43b-3aac827c1310', 'name': '300 g', 'price_add': 0.88, 'is_available': true, 'sort_order': 1},
      {'id': '47238d01-fcfc-4183-a711-60d50a5b940d', 'name': '400 g', 'price_add': 1.75, 'is_available': true, 'sort_order': 2},
      {'id': '75738d13-93f1-4a63-a0ab-745d83f5440b', 'name': '500 g (meio quilo)', 'price_add': 2.63, 'is_available': true, 'sort_order': 3},
      {'id': '8c0d4138-ee49-4d47-bd4f-161196fb8ecf', 'name': '1 kg', 'price_add': 7, 'is_available': true, 'sort_order': 4},
    ],
  }
];

void main() {
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await Supabase.initialize(
      url: 'http://127.0.0.1:1',
      anonKey: 'teste',
      debug: false,
      httpClient: MockClient((req) async {
        if (req.url.path.endsWith('/product_option_groups')) {
          return http.Response(jsonEncode(_grupoReal), 200, request: req,
              headers: {'content-type': 'application/json; charset=utf-8'});
        }
        return http.Response('[]', 200, request: req,
            headers: {'content-type': 'application/json; charset=utf-8'});
      }),
    );
  });

  testWidgets(
      'Jiló: "Escolhe a quantidade" aparece, é obrigatório e cada porção '
      'soma certo até ao carrinho', (tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 2.6;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final cart = CartStore();
    const jilo = PartnerProduct(
      id: _jiloId,
      restaurantId: '12aa2cbb-01bd-443b-a17e-633c169d4864',
      name: 'Jiló (ao peso)',
      description: '',
      price: 1.75,
      photoUrl: '',
      isAvailable: true,
      hasRequiredOptions: true,
      soldByWeight: true,
      shelfPricePerKg: 7.5,
    );

    await tester.pumpWidget(MultiProvider(
      providers: [
        ChangeNotifierProvider<CartStore>.value(value: cart),
        ChangeNotifierProvider<RestaurantStore>(create: (_) => RestaurantStore()),
      ],
      child: const MaterialApp(
        home: ProductDetailScreen(product: jilo, isPartnerStore: true),
      ),
    ));
    // Deixa o _loadGroups responder (cliente HTTP de brincar): o pedido corre
    // em tempo real, fora do relógio de brincar do teste.
    for (var i = 0; i < 20 && find.text('Escolhe a quantidade').evaluate().isEmpty; i++) {
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 100)));
      await tester.pump();
    }

    // 1. O grupo aparece e trava o botão até escolher.
    expect(find.text('Escolhe a quantidade'), findsOneWidget);
    expect(find.textContaining('Completa as escolhas obrigatórias'),
        findsOneWidget);

    // 2. Cada porção mostra no botão o preço certo (parceiro: preço puro).
    const esperado = {
      '200 g': '1.75',
      '300 g': '2.63',
      '400 g': '3.50',
      '500 g (meio quilo)': '4.38',
      '1 kg': '8.75',
    };
    for (final e in esperado.entries) {
      final alvo = find.text(e.key);
      await tester.ensureVisible(alvo);
      await tester.tap(alvo);
      await tester.pump();
      expect(find.textContaining('Adicionar ao carrinho · €${e.value}'),
          findsOneWidget,
          reason: '${e.key} devia dar €${e.value}');
    }

    // 3. Meio quilo entra no carrinho a €4.38 a unidade, com a porção escrita.
    await tester.ensureVisible(find.text('500 g (meio quilo)'));
    await tester.tap(find.text('500 g (meio quilo)'));
    await tester.pump();
    final botao = find.textContaining('Adicionar ao carrinho · €4.38');
    await tester.ensureVisible(botao);
    await tester.tap(botao);
    await tester.pump();
    expect(cart.items, hasLength(1));
    expect(cart.items.first.price, closeTo(4.38, 0.001));
    expect(cart.items.first.productId, _jiloId);
    final escolhas = cart.items.first.selectedOptions;
    expect(escolhas.single.group, 'Escolhe a quantidade');
    expect(escolhas.single.items, ['500 g (meio quilo)']);

    // O aviso verde "adicionado" vive uns segundos: deixa-o sair antes de
    // desmontar (senão a animação dele corre já sem dono).
    await tester.pump(const Duration(seconds: 10));
    await tester.pump(const Duration(seconds: 1));
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(minutes: 5));
    tester.takeException();
  });
}
