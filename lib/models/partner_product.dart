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
    this.category = '',
    this.categoryRoot = '',
    this.isPopular = false,
    this.isOnSale = false,
    this.discountPrice,
    this.source = ProductSource.api,
    this.hasRequiredOptions = false,
  });

  final String id;
  final String restaurantId;
  final String name;
  final String description;
  final double price;
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

  PartnerProduct copyWith({
    String? name,
    String? description,
    double? price,
    String? photoUrl,
    bool? isAvailable,
    String? category,
    String? categoryRoot,
    bool? isPopular,
    bool? isOnSale,
    double? discountPrice,
    ProductSource? source,
    bool? hasRequiredOptions,
  }) {
    return PartnerProduct(
      id: id,
      restaurantId: restaurantId,
      name: name ?? this.name,
      description: description ?? this.description,
      price: price ?? this.price,
      photoUrl: photoUrl ?? this.photoUrl,
      isAvailable: isAvailable ?? this.isAvailable,
      category: category ?? this.category,
      categoryRoot: categoryRoot ?? this.categoryRoot,
      isPopular: isPopular ?? this.isPopular,
      isOnSale: isOnSale ?? this.isOnSale,
      discountPrice: discountPrice ?? this.discountPrice,
      source: source ?? this.source,
      hasRequiredOptions: hasRequiredOptions ?? this.hasRequiredOptions,
    );
  }
}
