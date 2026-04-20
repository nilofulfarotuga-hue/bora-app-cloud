class CartItem {
  final String productId;
  final String name;
  final double price;
  int quantity;
  String purchaseStatus; // 'pending', 'bought', 'unavailable'
  double? actualPrice; // real price if different from estimated (future use)

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
