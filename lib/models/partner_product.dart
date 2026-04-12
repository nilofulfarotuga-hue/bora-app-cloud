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
    this.isPopular = false,
    this.isOnSale = false,
    this.discountPrice,
    this.source = ProductSource.api,
  });

  final String id;
  final String restaurantId;
  final String name;
  final String description;
  final double price;
  final String photoUrl;
  final bool isAvailable;
  final String category;
  final bool isPopular;
  final bool isOnSale;
  final double? discountPrice;
  final ProductSource source;

  PartnerProduct copyWith({
    String? name,
    String? description,
    double? price,
    String? photoUrl,
    bool? isAvailable,
    String? category,
    bool? isPopular,
    bool? isOnSale,
    double? discountPrice,
    ProductSource? source,
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
      isPopular: isPopular ?? this.isPopular,
      isOnSale: isOnSale ?? this.isOnSale,
      discountPrice: discountPrice ?? this.discountPrice,
      source: source ?? this.source,
    );
  }
}
