class CartItem {
  final String productId;
  final String name;
  final double price;
  int quantity;

  CartItem({
    String? productId,
    required this.name,
    required this.price,
    this.quantity = 1,
  }) : productId = productId ?? name;

  Map<String, dynamic> toJson() => {
        'productId': productId,
        'name': name,
        'price': price,
        'quantity': quantity,
      };

  factory CartItem.fromJson(Map<String, dynamic> json) => CartItem(
        productId: json['productId'] as String?,
        name: json['name'] as String,
        price: (json['price'] as num).toDouble(),
        quantity: json['quantity'] as int? ?? 1,
      );
}
