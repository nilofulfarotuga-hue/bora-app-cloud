// Missão farmacias-loja-2026-11-14 · bloco 4 — na loja da farmácia o
// "Tenho receita" nunca desaparece: botão grande na capa, chip na barra fina
// quando o botão sai do ecrã. Testes sem rede (visivelParaTeste).
import 'package:bora_app/widgets/farmacia/farmacia_botoes_topo.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _app(Widget filho) => MaterialApp(home: Scaffold(body: filho));

void main() {
  testWidgets('visíveis: avisam o ecrã e o botão grande leva a chave que o ecrã mede', (t) async {
    final avisos = <bool>[];
    final chave = GlobalKey();
    await t.pumpWidget(_app(FarmaciaBotoesTopo(
      restaurantId: 'x',
      storeName: 'Farmácia da Sé',
      visivelParaTeste: true,
      onVisivel: avisos.add,
      chaveBotaoReceita: chave,
    )));
    await t.pump();
    expect(avisos, [true]);
    final caixa = chave.currentContext!.findRenderObject()! as RenderBox;
    expect(caixa.size.height, 54);
    expect(
      find.descendant(of: find.byKey(chave), matching: find.text('Tenho receita')),
      findsOneWidget,
    );
    expect(t.takeException(), isNull);
  });

  testWidgets('escondidos: avisam false e não há botão para medir', (t) async {
    final avisos = <bool>[];
    final chave = GlobalKey();
    await t.pumpWidget(_app(FarmaciaBotoesTopo(
      restaurantId: 'x',
      storeName: 'Farmácia da Sé',
      visivelParaTeste: false,
      onVisivel: avisos.add,
      chaveBotaoReceita: chave,
    )));
    await t.pump();
    expect(avisos, [false]);
    expect(chave.currentContext, isNull);
    expect(find.text('Tenho receita'), findsNothing);
  });

  testWidgets('chip "Tenho receita" cabe na barra fina de um telemóvel pequeno', (t) async {
    t.view.physicalSize = const Size(360, 640);
    t.view.devicePixelRatio = 1.0;
    addTearDown(t.view.reset);
    await t.pumpWidget(_app(const Row(children: [
      FarmaciaReceitaChip(restaurantId: 'x', storeName: 'Farmácia da Sé'),
    ])));
    expect(find.byKey(const ValueKey('farmacia_tenho_receita_chip')), findsOneWidget);
    expect(find.text('Tenho receita'), findsOneWidget);
    final chip = t.getSize(find.byKey(const ValueKey('farmacia_tenho_receita_chip')));
    expect(chip.height, lessThanOrEqualTo(50), reason: 'a linha das categorias tem 50 px');
    expect(t.takeException(), isNull);
  });
}
