class CartItem {
  final String productId;
  final String name;
  final double price;
  int quantity;
  String purchaseStatus; // 'pending', 'bought', 'unavailable'
  double? actualPrice; // real price if different from estimated (future use)

  // Bug-B fix 2026-04-30: callers MUST now pass real productId for product
  // flows (restaurant menu, store products). Fallback to name only kept for
  // logistics services (carryGroceries / sendPackage) and legacy paths where
  // create_order ignores product_lines anyway. Real-product call sites have
  // been updated in business_mapper.dart, restaurant_menu_screen.dart,
  // cart_store.dart.
  CartItem({
    String? productId,
    required this.name,
    required this.price,
    this.quantity = 1,
    this.purchaseStatus = 'pending',
    this.actualPrice,
  }) : productId = productId ?? name;

  Map<String, dynamic> toJson() => {
        'productId': productId,
        'name': name,
        'price': price,
        'quantity': quantity,
        'purchaseStatus': purchaseStatus,
        if (actualPrice != null) 'actualPrice': actualPrice,
      };

  factory CartItem.fromJson(Map<String, dynamic> json) => CartItem(
        productId: json['productId'] as String?,
        name: json['name'] as String,
        price: (json['price'] as num).toDouble(),
        quantity: json['quantity'] as int? ?? 1,
        purchaseStatus: json['purchaseStatus'] as String? ?? 'pending',
        actualPrice: (json['actualPrice'] as num?)?.toDouble(),
      );
}
