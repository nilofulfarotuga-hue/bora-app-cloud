import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// [melhorias-paridade 26/10, itens 13 e 14]
/// 13 — no computador (1440 px) a foto do produto tapava o ecrã todo
///      (`expandedHeight` = largura do ecrã). Agora a ficha tem largura máxima.
/// 14 — textos do carrinho e do produto sem tradução.
void main() {
  String ler(String p) => File(p).readAsStringSync();

  test('ficha do produto com largura máxima e foto limitada', () {
    final s = ler('lib/screens/product_detail_screen.dart');
    expect(s.contains('const double _larguraMaxFicha = 720;'), isTrue);
    expect(s.contains('constraints: const BoxConstraints(maxWidth: _larguraMaxFicha)'), isTrue);
    expect(s.contains('expandedHeight: MediaQuery.of(context).size.width,'), isFalse);
  });

  test('textos do carrinho e do produto passam pela tradução', () {
    final c = ler('lib/screens/cart_screen.dart');
    for (final t in ["'Finalizar pedido'", "'Total a pagar'", "'Entrega'"]) {
      expect(c.contains('$t,'), isFalse, reason: '$t sem .tr');
    }
    final p = ler('lib/screens/product_detail_screen.dart');
    expect(p.contains("'Preço indisponível',"), isFalse);
    expect(p.contains("'Completa as escolhas obrigatórias',"), isFalse);
  });
}
