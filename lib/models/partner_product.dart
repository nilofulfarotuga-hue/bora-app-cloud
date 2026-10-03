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
    );
  }
}
