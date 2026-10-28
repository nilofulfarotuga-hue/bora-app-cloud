import 'dart:io';

import 'package:bora_app/utils/euros.dart';
import 'package:flutter_test/flutter_test.dart';

/// [melhorias-paridade 26/10, item 6] Preços no formato de Portugal: "9,65 €"
/// (a app mostrava "€9.65"). Só muda a forma de mostrar: o mesmo número, o
/// mesmo arredondamento (`toStringAsFixed(2)`).
void main() {
  test('vírgula decimal e o euro depois', () {
    expect(eur(9.65), '9,65 €');
    expect(eur(0.99), '0,99 €');
    expect(eur(12), '12,00 €');
    expect(eur(-1.5), '-1,50 €');
    expect(eurCents(965), '9,65 €');
  });

  test('arredonda igual ao que estava', () {
    for (final v in [9.645, 2.675, 1.005, 13.4449, 0.125]) {
      expect(eur(v), '${v.toStringAsFixed(2).replaceAll('.', ',')} €');
    }
  });

  test('o carrinho, o pagamento e o valor riscado usam o formato novo', () {
    expect(File('lib/widgets/valor_com_risco.dart').readAsStringSync().contains('eur('), isTrue);
    for (final p in ['lib/screens/cart_screen.dart', 'lib/screens/payment_method_screen.dart',
        'lib/screens/product_detail_screen.dart', 'lib/screens/restaurant_menu_screen.dart']) {
      final s = File(p).readAsStringSync();
      expect(RegExp(r"'€\$\{[^}]*toStringAsFixed\(2\)\}'").hasMatch(s), isFalse, reason: p);
    }
  });
}
