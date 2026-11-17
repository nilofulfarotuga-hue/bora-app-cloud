// Imprimir documentos (17/11/2026): o Danilo pediu "tira foto, puxa o PDF", igual à receita da
// farmácia. O ecrã tem de mostrar logo os três caminhos: câmara, galeria e ficheiro PDF.
import 'package:bora_app/screens/impressao/impressao_enviar_screen.dart';
import 'package:bora_app/services/impressao_service.dart';
import 'dart:io';

import 'package:bora_app/widgets/impressao/impressao_botoes_topo.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class _LojaLigada extends ImpressaoService {
  _LojaLigada({this.ligado = true});
  final bool ligado;

  @override
  Future<ImpressaoLoja?> loja(String restaurantId) async => ImpressaoLoja(
        restaurantId: restaurantId,
        ligado: ligado,
        personalizados: true,
        permiteLevantar: true,
        permiteEntrega: true,
        maxFicheiros: 10,
        maxPaginas: 500,
      );
}

void main() {
  testWidgets('ecrã de imprimir mostra Tirar foto, Fotos da galeria e Ficheiro PDF', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: ImpressaoEnviarScreen(restaurantId: 'a3-guarda', lojaNome: 'A3 Guarda', service: _LojaLigada()),
    ));
    await tester.pump();

    expect(find.byKey(const ValueKey('impressao_tirar_foto')), findsOneWidget);
    expect(find.byKey(const ValueKey('impressao_fotos_galeria')), findsOneWidget);
    expect(find.byKey(const ValueKey('impressao_escolher_ficheiros')), findsOneWidget);
    expect(find.text('Tirar foto'), findsOneWidget);
    expect(find.text('Fotos da galeria'), findsOneWidget);
    expect(find.text('Ficheiro PDF (ou imagem)'), findsOneWidget);
  });

  testWidgets('topo da loja: cartão de imprimir diz que dá para tirar foto', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: ImpressaoBotoesTopo(restaurantId: 'a3-guarda', storeName: 'A3 Guarda', service: _LojaLigada()),
      ),
    ));
    await tester.pump();

    expect(find.text('Imprimir documentos'), findsOneWidget);
    expect(find.text('Tire uma foto ou envie o PDF e veja o preço'), findsOneWidget);
    expect(find.text('Personalizados'), findsOneWidget);
  });

  testWidgets('loja sem o serviço ligado não mostra os cartões', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: ImpressaoBotoesTopo(
            restaurantId: 'outra-loja', storeName: 'Outra', service: _LojaLigada(ligado: false)),
      ),
    ));
    await tester.pump();

    expect(find.text('Imprimir documentos'), findsNothing);
  });

  test('a entrada das lojas grandes (A3) mostra os cartões de imprimir antes da pesquisa', () {
    // A A3 é categoria store: abre o MarketStoreTab, não o StoreProductsScreen.
    final s = File('lib/widgets/market/market_store_tab.dart').readAsStringSync();
    final cartoes = s.indexOf('ImpressaoBotoesTopo(');
    final pesquisa = s.indexOf('child: _SearchBar(');
    final categorias = s.indexOf('child: _CategoryGrid(');
    expect(cartoes, isNonNegative);
    expect(cartoes, lessThan(pesquisa));
    expect(cartoes, lessThan(categorias));
  });
}
