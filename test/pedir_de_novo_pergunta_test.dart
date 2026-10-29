import 'dart:io';

import 'package:bora_app/models/cart_item.dart';
import 'package:bora_app/stores/cart_store.dart';
import 'package:bora_app/widgets/confirmar_substituir_carrinho.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// [melhorias-paridade 26/10, item 7] "Pedir de novo" pergunta antes de
/// substituir o carrinho (antes apagava calado, reorder_service.dart).
void main() {
  Future<bool?> correr(WidgetTester tester, CartStore cart, {String? tocar}) async {
    bool? resultado;
    await tester.pumpWidget(MaterialApp(
      home: Builder(
        builder: (ctx) => TextButton(
          onPressed: () async => resultado = await confirmarSubstituirCarrinho(ctx, cart),
          child: const Text('ir'),
        ),
      ),
    ));
    await tester.tap(find.text('ir'));
    await tester.pumpAndSettle();
    if (tocar != null) {
      await tester.tap(find.text(tocar));
      await tester.pumpAndSettle();
    }
    return resultado;
  }

  testWidgets('carrinho vazio: segue sem perguntar', (tester) async {
    expect(await correr(tester, CartStore()), isTrue);
    expect(find.byType(AlertDialog), findsNothing);
  });

  testWidgets('com artigos: pergunta; "Manter o carrinho" não substitui', (tester) async {
    final cart = CartStore()
      ..addItem(CartItem(productId: 'p', name: 'Menu', price: 9.65, quantity: 1));
    expect(await correr(tester, cart, tocar: 'Manter o carrinho'), isFalse);
    expect(cart.items, isNotEmpty);
  });

  testWidgets('com artigos: "Substituir" deixa seguir', (tester) async {
    final cart = CartStore()
      ..addItem(CartItem(productId: 'p', name: 'Menu', price: 9.65, quantity: 1));
    expect(await correr(tester, cart, tocar: 'Substituir'), isTrue);
  });

  test('os dois botões "Pedir de novo" passam pela pergunta', () {
    for (final p in ['lib/screens/orders_screen.dart', 'lib/widgets/market/market_reorder_tab.dart']) {
      final s = File(p).readAsStringSync();
      final i = s.indexOf('confirmarSubstituirCarrinho(');
      final j = s.indexOf('ReorderService.applyTo(');
      expect(i, greaterThan(0), reason: p);
      expect(i < j, isTrue, reason: '$p: a pergunta vem antes de mexer no carrinho');
    }
  });
}
