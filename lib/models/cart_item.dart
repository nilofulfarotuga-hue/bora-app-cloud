class CartItem {
  final String productId;
  final String name;
  final double price;
  int quantity;
  String purchaseStatus; // 'pending', 'bought', 'unavailable'
  double? actualPrice; // real price if different from estimated (future use)

  // Sessão 4 B5 (mitigação dev/debug only — asserts strip em release):
  // Callers DEVEM passar productId real (TEXT) da row em public.products.
  // Fallback `?? name` removido. fromJson usa _raw (sem asserts) por
  // tolerância a legacy data persistida em orders.items pré-Bug-B fix.
  // Fix transversal completo (107 call sites, limpeza retroactiva
  // orders.items) → Sessão 4C dedicada.
  CartItem({
    required this.productId,
    required this.name,
    required this.price,
    this.quantity = 1,
    this.purchaseStatus = 'pending',
    this.actualPrice,
  })  : assert(productId.isNotEmpty, 'CartItem.productId vazio'),
        assert(!productId.contains(' '),
            'CartItem.productId com espaço — parece nome ($productId)'),
        assert(productId.length < 200,
            'CartItem.productId muito longo — parece nome (len=${productId.length})');

  // Construtor sem asserts para desserializar legacy data persistida em
  // orders.items (productId pode ser nome literal pré-Bug-B fix). Não usar
  // para criar novas instâncias — usar [CartItem.new] que valida via asserts.
  CartItem._raw({
    required this.productId,
    required this.name,
    required this.price,
    this.quantity = 1,
    this.purchaseStatus = 'pending',
    this.actualPrice,
  });

  Map<String, dynamic> toJson() => {
        'productId': productId,
        'name': name,
        'price': price,
        'quantity': quantity,
        'purchaseStatus': purchaseStatus,
        if (actualPrice != null) 'actualPrice': actualPrice,
      };

  factory CartItem.fromJson(Map<String, dynamic> json) {
    final rawId = json['productId'] as String?;
    final name = json['name'] as String;
    return CartItem._raw(
      productId: (rawId == null || rawId.isEmpty) ? name : rawId,
      name: name,
      price: (json['price'] as num).toDouble(),
      quantity: json['quantity'] as int? ?? 1,
      purchaseStatus: json['purchaseStatus'] as String? ?? 'pending',
      actualPrice: (json['actualPrice'] as num?)?.toDouble(),
    );
  }
}
