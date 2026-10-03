import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/cart_item.dart';
import '../models/product_option.dart';
import 'partner_price_rules.dart';

/// Venda ao peso (2026-09-18).
///
/// O parceiro escreve o preço por quilo que quer receber; a app monta sozinha
/// as porções de 200 g / 300 g / 400 g / 500 g / 1 kg. O preço da linha do
/// produto (`products.price`) é a porção base de 200 g e o resto vive no grupo
/// obrigatório "Escolhe a quantidade" (`product_option_groups`), com o
/// `price_add` de cada porção.
///
/// Quem GRAVA é o servidor — `public.set_product_weight_pricing` — a partir
/// das percentagens de `platform_settings`. Aqui só se calcula a
/// pré-visualização ("Recebes X por kg / o cliente vê Y por kg") com o mesmo
/// [PartnerPriceRules] que já serve o "Preço que recebes", para o parceiro
/// nunca fazer contas.
class WeightPortions {
  WeightPortions._();

  /// Nome do grupo obrigatório — tem de bater com o servidor.
  static const String kGroupName = 'Escolhe a quantidade';

  /// Porção base: `products.price` vale isto num produto ao peso.
  static const int kBaseGrams = 200;

  static const List<int> kGrams = [200, 300, 400, 500, 1000];

  static String label(int grams) {
    if (grams == 1000) return '1 kg';
    if (grams == 500) return '500 g (meio quilo)';
    return '$grams g';
  }

  /// Preço que o cliente vê para [grams] gramas, dado o balcão por quilo.
  /// A MESMA conta que `set_product_weight_pricing`: só a porção de 200 g
  /// passa pela fórmula (balcão × (1 + markup) ÷ (1 − comissão), multiplicando
  /// antes de dividir); as outras são múltiplos exactos dela (300 g = 1,5×,
  /// 1 kg = 5×), para o "€/kg" do cartão ser sempre o preço do 1 kg.
  /// [rules] null = loja não parceira → preço puro (o markup de não-parceiro
  /// é aplicado em runtime pela app, como nos outros produtos de mercado).
  static double clientPriceFor(
      double shelfPerKg, int grams, PartnerPriceRules? rules) {
    final base = basePrice(shelfPerKg, rules);
    return _round2(base * grams / kBaseGrams);
  }

  /// Preço ao cliente da porção base (200 g) — o que vai para `products.price`.
  static double basePrice(double shelfPerKg, PartnerPriceRules? rules) {
    final shelf = shelfPerKg * kBaseGrams / 1000;
    if (rules == null) return _round2(shelf);
    if (rules.usesStoreMarkup) {
      return _round2(shelf * (1 + rules.appMarkupPct!));
    }
    return _round2(
        shelf * (1 + rules.hiddenMarkupPct) / (1 - rules.visibleCommissionPct));
  }

  /// Preço ao cliente por quilo — a linha pequena "5,70 €/kg" do cartão e
  /// do detalhe. Derivado do preço já exibido da porção base, para não
  /// precisar das percentagens no lado do cliente.
  static double clientPerKgFromBase(double displayedBasePrice) =>
      _round2(displayedBasePrice * 1000 / kBaseGrams);

  /// Pré-visualização das cinco porções (nome, preço ao cliente).
  static List<({String label, double price})> preview(
      double shelfPerKg, PartnerPriceRules? rules) {
    return [
      for (final g in kGrams)
        (label: label(g), price: clientPriceFor(shelfPerKg, g, rules)),
    ];
  }

  /// Grava no servidor: colunas + grupo das porções, numa transacção só.
  /// Devolve o JSON da função (`success`, `price`, `portions`…).
  static Future<Map<String, dynamic>> apply({
    required String productId,
    required bool soldByWeight,
    double? shelfPricePerKg,
    String? reason,
  }) async {
    final res = await Supabase.instance.client.rpc(
      'set_product_weight_pricing',
      params: {
        'p_product_id': productId,
        'p_sold_by_weight': soldByWeight,
        'p_shelf_price_per_kg': soldByWeight ? shelfPricePerKg : null,
        'p_reason': reason,
      },
    );
    return (res as Map).cast<String, dynamic>();
  }

  /// "Abóbora Cabotiá — 500 g (meio quilo)": o nome com a porção escolhida,
  /// para o carrinho, a lista de compras do estafeta e o detalhe do pedido.
  /// Sem porção (produto normal) devolve o nome tal como está.
  static String displayName(CartItem item) {
    for (final o in item.displayOptions) {
      if (o.group == kGroupName && o.items.isNotEmpty) {
        return '${item.name} — ${o.items.first}';
      }
    }
    return item.name;
  }

  /// As opções a listar por baixo do nome, sem repetir a porção que já vai
  /// no [displayName].
  static List<SelectedOption> optionsWithoutWeight(CartItem item) =>
      item.displayOptions.where((o) => o.group != kGroupName).toList();

  static double _round2(double v) => ((v * 100) + 1e-9).round() / 100;
}
