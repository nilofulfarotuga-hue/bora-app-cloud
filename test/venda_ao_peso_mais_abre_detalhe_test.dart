// Venda ao peso (2026-09-18) — o "+" de um produto com escolha obrigatória
// NUNCA adiciona directo ao carrinho. Antes desta missão o cartão de mercado
// (MarketProductCard) e o cartão grande do ecrã de loja (_ProductCard em
// store_products_screen) só olhavam para as variantes; um produto ao peso
// (grupo obrigatório "Escolhe a quantidade") entrava ao preço da porção de
// 200 g sem o cliente escolher nada — e o estafeta não sabia quantas gramas.
//
//   1) MECÂNICA — MarketProductCard real, produto ao peso com
//      hasRequiredOptions=true: tocar no "+" deixa o carrinho vazio e empurra
//      um ecrã novo (o detalhe, onde a escolha é obrigatória).
//   2) GUARDA — os QUATRO caminhos de "+" da app olham para
//      hasRequiredOptions, e o detalhe exige as escolhas (_requiredOk).
import 'dart:io';

import 'package:bora_app/models/partner_product.dart';
import 'package:bora_app/stores/cart_store.dart';
import 'package:bora_app/stores/restaurant_store.dart';
import 'package:bora_app/widgets/market/market_product_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class _Observer extends NavigatorObserver {
  int pushes = 0;
  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    pushes++;
  }
}

void main() {
  setUpAll(() async {
    // O RestaurantStore pega no Supabase.instance no construtor. Um Supabase
    // de brincar, a apontar para uma porta fechada: nada sai para a rede.
    SharedPreferences.setMockInitialValues({});
    await Supabase.initialize(
      url: 'http://127.0.0.1:1',
      anonKey: 'teste',
      debug: false,
    );
  });

  testWidgets('MECÂNICA: "+" num produto ao peso abre o detalhe, não adiciona',
      (tester) async {
    final cart = CartStore();
    final observer = _Observer();
    const abobora = PartnerProduct(
      id: '7c6144bc-421b-44d3-8edb-17bdd5c842d1',
      restaurantId: '12aa2cbb-01bd-443b-a17e-633c169d4864',
      name: 'Abóbora Cabotiá (ao peso)',
      description: '',
      price: 1.14,
      photoUrl: '',
      isAvailable: true,
      hasRequiredOptions: true,
      soldByWeight: true,
      shelfPricePerKg: 4.89,
    );

    await tester.pumpWidget(MultiProvider(
      providers: [
        ChangeNotifierProvider<CartStore>.value(value: cart),
        ChangeNotifierProvider<RestaurantStore>(create: (_) => RestaurantStore()),
      ],
      child: MaterialApp(
        navigatorObservers: [observer],
        home: const Scaffold(
          body: Center(
            child: MarketProductCard(
              product: abobora,
              restaurantId: '12aa2cbb-01bd-443b-a17e-633c169d4864',
              storeName: 'Sabores de Casa Açaí',
              isPartnerStore: true,
            ),
          ),
        ),
      ),
    ));

    // O cartão mostra "desde" e o preço por quilo ao cliente (5 × 1,14).
    expect(find.textContaining('desde'), findsOneWidget);
    expect(find.text('€5.70/kg'), findsOneWidget);

    final pushesBefore = observer.pushes;
    await tester.tap(find.byIcon(Icons.add));
    // Sem pumpAndSettle: o detalhe arrasta Supabase; basta ver que foi
    // empurrado e que nada entrou no carrinho.
    expect(cart.items, isEmpty, reason: 'entrou no carrinho sem escolher gramas');
    expect(observer.pushes, pushesBefore + 1, reason: 'não abriu o detalhe');
    await tester.pump();
    tester.takeException();

    // Desmonta tudo e deixa o relógio de brincar correr para os temporizadores
    // do Realtime (que a loja de mentira nunca chega a ligar) se apagarem.
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(minutes: 5));
    tester.takeException();
  });

  test('GUARDA: os quatro "+" da app respeitam hasRequiredOptions', () {
    final market =
        File('lib/widgets/market/market_product_card.dart').readAsStringSync();
    final store = File('lib/screens/store_products_screen.dart').readAsStringSync();
    final card = File('lib/widgets/bora/bora_product_card.dart').readAsStringSync();
    final detail = File('lib/screens/product_detail_screen.dart').readAsStringSync();

    expect(market, contains('variants.isNotEmpty || product.hasRequiredOptions'),
        reason: 'MarketProductCard._handleAdd deixou de olhar para as opções obrigatórias');
    expect(store, contains('if (widget.product.hasRequiredOptions) {'),
        reason: 'o "+" do _ProductCard em store_products_screen deixou de abrir o detalhe');
    expect(card, contains('product.hasRequiredOptions ? onTap : onAdd'),
        reason: 'BoraProductCard deixou de abrir o detalhe para opções obrigatórias');
    expect(detail, contains('_requiredOk'),
        reason: 'o detalhe deixou de exigir as escolhas obrigatórias');
  });
}
