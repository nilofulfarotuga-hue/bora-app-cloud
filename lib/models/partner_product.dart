enum ProductSource { localSeed, api, scraped }

class PartnerProduct {
  const PartnerProduct({
    required this.id,
    required this.restaurantId,
    required this.name,
    required this.description,
    required this.price,
    required this.photoUrl,
    required this.isAvailable,
    this.source = ProductSource.localSeed,
  });

  final String id;
  final String restaurantId;
  final String name;
  final String description;
  final double price;
  final String photoUrl;
  final bool isAvailable;
  final ProductSource source;

  PartnerProduct copyWith({
    String? name,
    String? description,
    double? price,
    String? photoUrl,
    bool? isAvailable,
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
      source: source ?? this.source,
    );
  }
}
