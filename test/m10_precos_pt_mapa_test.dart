// M10 b2-nif (09/11/2026), item 2.14 iii — o ecrã do estafeta mostrava preços
// no formato inglês ("€2.50", "RECEBER €3.31"). Passa ao formato de Portugal
// ("2,50 €") com o mesmo `eur(...)` que o cliente já usa. Só a forma de
// mostrar: os números e o arredondamento (toStringAsFixed(2)) são os mesmos.
import 'dart:io';

import 'package:bora_app/utils/euros.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final mapa = File('lib/screens/driver_map_screen.dart').readAsStringSync();

  test('nenhum preço com "€" à frente e ponto decimal no ecrã do estafeta', () {
    expect(RegExp(r'€\$\{').hasMatch(mapa), isFalse,
        reason: 'ainda há "€\${valor...}" (formato inglês)');
    expect(mapa, isNot(contains("'€0.30 (fixo)'")));
    expect(mapa, isNot(contains('bónus +€1')));
    expect(mapa, contains("import '../utils/euros.dart';"));
  });

  test('os sítios do dinheiro usam eur(...)', () {
    for (final s in [
      "'RECEBER \${eur(amount)} EM DINHEIRO'",
      "'RECEBER \${eur(amount)} DO CLIENTE EM DINHEIRO'",
      "'RECEBER \${eur(amount)} — entregar ao parceiro'",
      "'PAGAR \${eur(amount)} AO ESTABELECIMENTO'",
      "'inclui +\${eur(debtEur)} de dívida anterior'",
      "'Compra finalizada: \${eur(finalTotal)}'",
      "'+\${eur(focusOrder.driverEarnings)}'",
      "'(\${eur(BRBags.MARKET_BAG_FEE)} por saco)'",
    ]) {
      expect(mapa, contains(s), reason: s);
    }
  });

  test('eur: mesmo número, vírgula e símbolo depois', () {
    expect(eur(2.5), '2,50 €');
    expect(eur(3.31), '3,31 €');
    expect(eur(0.3), '0,30 €');
    expect(eur(14.345), '${14.345.toStringAsFixed(2).replaceAll('.', ',')} €');
  });
}
