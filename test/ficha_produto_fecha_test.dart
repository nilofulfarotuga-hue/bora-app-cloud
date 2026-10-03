// Prova do 2.o defeito apanhado pelo Danilo (2026-08-25): a ficha do produto
// ficava aberta depois de "Adicionar ao carrinho" e o cliente nao percebia
// que o produto tinha entrado.
//
// Duas camadas:
//   1) MECANICA — o mesmo par de chamadas que a ficha real faz agora
//      (mostrar aviso + fecharFichaAposAdicionar) fecha o ecra e devolve o
//      cliente ao menu, com o aviso a sair aos 2s.
//   2) GUARDA — os TRES caminhos de adicionar do ecra real (variante, simples
//      e com opcoes) chamam mesmo o fecho. Se alguem os mudar, este teste
//      falha. Evita montar o ProductDetailScreen inteiro, que arrasta Supabase
//      e temporizadores de retry dos stores (ruido que nada prova).
//
// A ficha e UNICA em toda a app — aberta pelo menu do restaurante (que serve
// restaurantes e festas), pelos ecras de loja/supermercado/farmacia e pelos
// cartoes de mercado. Vale para todas as categorias.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:bora_app/utils/cart_feedback.dart';

void main() {
  testWidgets('MECANICA: adicionar fecha a ficha e volta ao menu da loja',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (menu) => ElevatedButton(
            onPressed: () => Navigator.of(menu).push(MaterialPageRoute(
              builder: (_) => Scaffold(
                body: Builder(
                  builder: (ficha) => ElevatedButton(
                    // exactamente o que _snackEFecha faz no ecra real
                    onPressed: () {
                      showAddedToCartSnack(
                          ficha, 'Coxinha com Catupiri × 1 adicionado ao carrinho');
                      fecharFichaAposAdicionar(ficha);
                    },
                    child: const Text('Adicionar ao carrinho · €3.68'),
                  ),
                ),
              ),
            )),
            child: const Text('menu da loja'),
          ),
        ),
      ),
    ));

    await tester.tap(find.text('menu da loja'));
    await tester.pumpAndSettle();
    expect(find.text('Adicionar ao carrinho · €3.68'), findsOneWidget,
        reason: 'estamos dentro da ficha');

    await tester.tap(find.text('Adicionar ao carrinho · €3.68'));
    await tester.pump();
    await tester.pumpAndSettle();   // deixa a transicao de fecho terminar

    // a ficha fechou-se e o aviso esta por cima do menu
    expect(find.text('Adicionar ao carrinho · €3.68'), findsNothing,
        reason: 'a ficha tem de fechar sozinha depois de adicionar');
    expect(find.text('menu da loja'), findsOneWidget,
        reason: 'o cliente volta ao menu da loja');
    expect(find.text('Coxinha com Catupiri × 1 adicionado ao carrinho'),
        findsOneWidget,
        reason: 'o aviso sobrevive ao fecho da ficha');

    // e aos 2s o aviso sai sozinho
    await tester.pump(const Duration(seconds: 2));
    await tester.pumpAndSettle();
    expect(find.text('Coxinha com Catupiri × 1 adicionado ao carrinho'),
        findsNothing);
  });

  test('GUARDA: os 3 caminhos de adicionar da ficha real fecham o ecra', () {
    final fonte =
        File('lib/screens/product_detail_screen.dart').readAsStringSync();

    // o helper de fecho existe e e chamado no ponto unico
    expect(fonte.contains('fecharFichaAposAdicionar(context)'), isTrue,
        reason: 'a ficha tem de chamar o fecho partilhado');

    // os tres caminhos usam esse ponto unico
    for (final metodo in const [
      'void _addToCart(',
      'void _addNoVariantToCart(',
      'void _addWithOptions(',
    ]) {
      final i = fonte.indexOf(metodo);
      expect(i, greaterThan(0), reason: 'metodo $metodo tem de existir');
      final corpo = fonte.substring(i, fonte.indexOf('\n  }', i));
      expect(corpo.contains('_snackEFecha('), isTrue,
          reason: '$metodo tem de avisar E fechar a ficha');
    }

    // e a guarda das opcoes obrigatorias continua intacta
    expect(fonte.contains("'Completa as escolhas obrigatórias'"), isTrue,
        reason: 'sem as opcoes obrigatorias o botao continua desactivado');
    expect(fonte.contains('onPressed: ok ? () => _addWithOptions(context) : null'),
        isTrue,
        reason: 'o botao so chama o adicionar quando as escolhas estao feitas');
  });
}
