import 'package:bora_app/models/cart_item.dart';
import 'package:bora_app/models/product_option.dart';
import 'package:bora_app/services/partner_price_rules.dart';
import 'package:bora_app/services/weight_portions.dart';
import 'package:flutter_test/flutter_test.dart';

/// Venda ao peso (2026-09-18). Os números são os que a função do servidor
/// `set_product_weight_pricing` gravou na Abóbora Cabotiá (balcão 4,89 €/kg,
/// comissão visível 10 %, markup oculto 5 %) — provado por SQL a 18/09. As porções
/// são múltiplos exactos da base de 200 g (1 kg = 5 × 1,14 = 5,70).
void main() {
  const rules = PartnerPriceRules(
    visibleCommissionPct: 0.10,
    hiddenMarkupPct: 0.05,
  );

  test('porções da Abóbora batem ao cêntimo com o servidor', () {
    expect(WeightPortions.clientPriceFor(4.89, 200, rules), 1.14);
    expect(WeightPortions.clientPriceFor(4.89, 300, rules), 1.71);
    expect(WeightPortions.clientPriceFor(4.89, 400, rules), 2.28);
    expect(WeightPortions.clientPriceFor(4.89, 500, rules), 2.85);
    expect(WeightPortions.clientPriceFor(4.89, 1000, rules), 5.70);
  });

  test('porções do Jiló (7,50 €/kg)', () {
    expect(WeightPortions.clientPriceFor(7.50, 200, rules), 1.75);
    expect(WeightPortions.clientPriceFor(7.50, 300, rules), 2.63);
    expect(WeightPortions.clientPriceFor(7.50, 1000, rules), 8.75);
  });

  test('loja não parceira: preço puro, sem comissão', () {
    expect(WeightPortions.clientPriceFor(4.89, 200, null), 0.98);
    expect(WeightPortions.clientPriceFor(4.89, 1000, null), 4.90);
  });

  test('preço ao cliente por kg deriva da porção base de 200 g', () {
    expect(WeightPortions.clientPerKgFromBase(1.14), 5.70);
  });

  test('rótulos das porções', () {
    expect(WeightPortions.preview(4.89, rules).map((p) => p.label).toList(),
        ['200 g', '300 g', '400 g', '500 g (meio quilo)', '1 kg']);
  });

  test('nome no carrinho leva a porção por extenso', () {
    final item = CartItem(
      productId: '7c6144bc-421b-44d3-8edb-17bdd5c842d1',
      name: 'Abóbora Cabotiá (ao peso)',
      price: 2.85,
      selectedOptions: const [
        SelectedOption(group: 'Escolhe a quantidade', items: ['500 g (meio quilo)']),
        SelectedOption(group: 'Extras', items: ['Sem sal']),
      ],
    );
    expect(WeightPortions.displayName(item),
        'Abóbora Cabotiá (ao peso) — 500 g (meio quilo)');
    expect(WeightPortions.optionsWithoutWeight(item).map((o) => o.group),
        ['Extras']);
  });

  test('produto normal fica com o nome tal como está', () {
    final item = CartItem(productId: 'x1', name: 'Pastel de Nata', price: 1.2);
    expect(WeightPortions.displayName(item), 'Pastel de Nata');
  });
}
