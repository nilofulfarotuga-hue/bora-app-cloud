enum ProductSource { api }

class PartnerProduct {
  const PartnerProduct({
    required this.id,
    required this.restaurantId,
    required this.name,
    required this.description,
    required this.price,
    required this.photoUrl,
    required this.isAvailable,
    this.partnerShelfPrice,
    this.category = '',
    this.categoryRoot = '',
    this.isPopular = false,
    this.isOnSale = false,
    this.discountPrice,
    this.source = ProductSource.api,
    this.hasRequiredOptions = false,
    this.allergens = const [],
    this.soldByWeight = false,
    this.shelfPricePerKg,
    this.ageRestricted = false,
    this.dietTags = const [],
    this.variableWeight = false,
    this.depositUnits = 0,
  });

  final String id;
  final String restaurantId;
  final String name;
  final String description;

  /// `products.price` — o preço que o cliente vê (já com a comissão por cima).
  /// Num produto ao peso é o preço da porção base de 200 g.
  final double price;

  /// `products.partner_shelf_price` — o preço de balcão, o que o parceiro
  /// recebe. Null nos produtos antigos ainda sem balcão gravado (a edição
  /// cai então para [price]). Ver `PartnerPriceRules`.
  final double? partnerShelfPrice;
  final String photoUrl;
  final bool isAvailable;
  final String category;
  final String categoryRoot;
  final bool isPopular;
  final bool isOnSale;
  final double? discountPrice;
  final ProductSource source;

  /// True when this product has at least one required option group
  /// (is_required + min_choices >= 1). Drives the listing "+" button:
  /// if true, "+" opens the detail screen (to choose options) instead of
  /// adding directly. Populated by RestaurantStore from product_option_groups.
  final bool hasRequiredOptions;

  /// B6 (2026-06-12): slugs dos 14 alergénios UE 1169/2011 declarados pelo
  /// parceiro (ver kAllergenLabels). Vazio = não preenchido → o detalhe do
  /// produto mostra o disclaimer "consulte o estabelecimento".
  final List<String> allergens;

  /// `products.sold_by_weight` (2026-09-18): o preço da linha é a porção de
  /// 200 g e o grupo obrigatório "Escolhe a quantidade" traz 300/400/500 g e
  /// 1 kg. Ver `WeightPortions` e `set_product_weight_pricing` no servidor.
  final bool soldByWeight;

  /// `products.shelf_price_per_kg` — o preço por quilo que o parceiro recebe.
  /// Só faz sentido com [soldByWeight].
  final double? shelfPricePerKg;

  /// `products.age_restricted` (missão maiores-18, 07/10/2026): tabaco ou
  /// bebida alcoólica. Etiqueta "+18" no cartão; o estafeta pede documento na
  /// entrega. Marcado no servidor (classificador + painel admin). Default
  /// false — a coluna pode ainda não existir numa base antiga.
  final bool ageRestricted;

  /// `products.diet_tags` (29/10/2026): etiquetas do menu (vegetariano, picante,
  /// sem glúten). Sugeridas pela IA a partir da descrição e corrigidas pelo
  /// parceiro. Ver `lib/models/etiquetas_dieta.dart`.
  final List<String> dietTags;

  /// `products.variable_weight` (31/10/2026): produto ao quilo dos mercados
  /// NÃO-parceiros (fruta, legumes, talho, peixaria). O cliente pede por
  /// unidades, o preço mostrado é aproximado e o estafeta pesa e escreve o
  /// valor da balança (`estafeta_ajustar_peso`). Não é o mesmo que
  /// [soldByWeight] (porções de 200 g dos parceiros). Default false.
  final bool variableWeight;

  /// `products.deposit_units` (09/11/2026): quantas embalagens com depósito
  /// Volta (latas e garrafas de plástico até 3 L, 0,10 € cada) leva UMA
  /// unidade deste produto — 1 numa lata, 6 num pack de 6. 0 = sem depósito.
  /// Só serve para a nota no cartão e na ficha; quem calcula e cobra é o
  /// servidor. Default 0 — a coluna pode ainda não existir numa base antiga.
  final int depositUnits;

  PartnerProduct copyWith({
    String? name,
    String? description,
    double? price,
    double? partnerShelfPrice,
    String? photoUrl,
    bool? isAvailable,
    String? category,
    String? categoryRoot,
    bool? isPopular,
    bool? isOnSale,
    double? discountPrice,
    ProductSource? source,
    bool? hasRequiredOptions,
    List<String>? allergens,
    bool? soldByWeight,
    double? shelfPricePerKg,
    bool? ageRestricted,
    List<String>? dietTags,
    bool? variableWeight,
    int? depositUnits,
  }) {
    return PartnerProduct(
      id: id,
      restaurantId: restaurantId,
      name: name ?? this.name,
      description: description ?? this.description,
      price: price ?? this.price,
      partnerShelfPrice: partnerShelfPrice ?? this.partnerShelfPrice,
      photoUrl: photoUrl ?? this.photoUrl,
      isAvailable: isAvailable ?? this.isAvailable,
      category: category ?? this.category,
      categoryRoot: categoryRoot ?? this.categoryRoot,
      isPopular: isPopular ?? this.isPopular,
      isOnSale: isOnSale ?? this.isOnSale,
      discountPrice: discountPrice ?? this.discountPrice,
      source: source ?? this.source,
      hasRequiredOptions: hasRequiredOptions ?? this.hasRequiredOptions,
      allergens: allergens ?? this.allergens,
      soldByWeight: soldByWeight ?? this.soldByWeight,
      shelfPricePerKg: shelfPricePerKg ?? this.shelfPricePerKg,
      ageRestricted: ageRestricted ?? this.ageRestricted,
      dietTags: dietTags ?? this.dietTags,
      variableWeight: variableWeight ?? this.variableWeight,
      depositUnits: depositUnits ?? this.depositUnits,
    );
  }
}

/// `products.variable_weight` lido de uma linha do banco (ou de uma RPC).
/// Sem a chave, ou com null, dá false — nunca parte um produto antigo.
bool pesoVariavelDaLinha(Map<String, dynamic> row) =>
    row['variable_weight'] == true;

/// Depósito Volta (09/11/2026): 0,10 € por embalagem. É o valor que a app
/// mostra antes do quote; o servidor devolve-o em `deposit_unit_cents` e é
/// ele que manda no que se cobra.
const int kCentimosPorEmbalagemVolta = 10;

/// `deposit_units` lido de uma linha do banco (produto ou opção de menu).
/// Sem a chave, com null ou negativo, dá 0 — nunca parte uma linha antiga.
int unidadesDepositoDaLinha(Map<String, dynamic> row) {
  final v = (row['deposit_units'] as num?)?.toInt() ?? 0;
  return v < 0 ? 0 : v;
}

/// O erro do servidor é "a coluna `deposit_units` não existe" (base ainda
/// sem a migração do depósito Volta). Quem pede a coluna repete sem ela.
bool faltaColunaDeposito(Object erro) =>
    erro.toString().contains('deposit_units');
