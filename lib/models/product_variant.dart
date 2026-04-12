class ProductVariant {
  final String id;
  final String productId;
  final String brandName;
  final double price;

  const ProductVariant({
    required this.id,
    required this.productId,
    required this.brandName,
    required this.price,
  });

  factory ProductVariant.fromSupabase(Map<String, dynamic> data) =>
      ProductVariant(
        id: (data['id'] ?? '').toString(),
        productId: (data['product_id'] ?? '').toString(),
        brandName: (data['brand_name'] ?? '').toString(),
        price: (data['price'] as num? ?? 0).toDouble(),
      );
}
