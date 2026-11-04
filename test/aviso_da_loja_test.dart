// Aviso da loja no topo (04/11/2026): a Mercadona · Beleza e Higiene mostra o seu about_text ao entrar.
import 'package:bora_app/widgets/aviso_da_loja.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _app(Future<String?> Function(String) ler) => MaterialApp(
      home: Scaffold(body: AvisoDaLoja(restaurantId: 'mercadona-guarda', ler: ler)),
    );

void main() {
  testWidgets('mostra o texto da loja', (t) async {
    await t.pumpWidget(_app((_) async =>
        'Por agora, só perfumaria, cosmética e higiene do Mercadona da Guarda, ao preço da prateleira. Em breve, mais produtos.'));
    await t.pump();
    expect(find.byKey(const Key('aviso_da_loja')), findsOneWidget);
    expect(find.textContaining('só perfumaria, cosmética e higiene'), findsOneWidget);
  });

  testWidgets('sem texto não mostra nada', (t) async {
    await t.pumpWidget(_app((_) async => null));
    await t.pump();
    expect(find.byKey(const Key('aviso_da_loja')), findsNothing);
  });

  testWidgets('erro de rede não rebenta nem mostra', (t) async {
    await t.pumpWidget(_app((_) async => throw Exception('sem rede')));
    await t.pump();
    expect(find.byKey(const Key('aviso_da_loja')), findsNothing);
  });
}
