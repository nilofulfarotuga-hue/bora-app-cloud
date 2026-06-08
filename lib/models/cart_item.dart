import 'product_option.dart';

class CartItem {
  final String productId;
  final String name;
  final double price;
  int quantity;
  String purchaseStatus; // 'pending', 'bought', 'unavailable'
  double? actualPrice; // real price if different from estimated (future use)

  /// Modifiers chosen for this line (e.g. açaí toppings). Empty for normal
  /// products. [price] already includes any paid extras. Persisted in
  /// orders.items JSONB as `selected_options`.
  final List<SelectedOption> selectedOptions;

  // Sessão 4C (2026-05-04): defesa run-time em release.
  // Asserts (4B5) STRIP em release → asserts são detectores dev. Validação
  // crítica usa `if-throw` no body do constructor (executa também em release).
  // Callers DEVEM passar productId real (TEXT) da row em public.products.
  // fromJson usa _raw (sem validação) por tolerância a legacy data persistida
  // em orders.items pré-Bug-B fix.
  CartItem({
    required this.productId,
    required this.name,
    required this.price,
    this.quantity = 1,
    this.purchaseStatus = 'pending',
    this.actualPrice,
    this.selectedOptions = const [],
  })  : assert(productId.isNotEmpty, 'CartItem.productId vazio'),
        assert(!productId.contains(' '),
            'CartItem.productId com espaço — parece nome ($productId)'),
        assert(productId.length < 200,
            'CartItem.productId muito longo — parece nome (len=${productId.length})') {
    if (productId.isEmpty) {
      throw ArgumentError.value(productId, 'productId',
          'CartItem.productId vazio');
    }
    if (productId.contains(' ')) {
      throw ArgumentError.value(productId, 'productId',
          'CartItem.productId contém espaço — parece nome');
    }
    if (productId.length > 200) {
      throw ArgumentError.value(productId, 'productId',
          'CartItem.productId muito longo (${productId.length} chars) — parece nome');
    }
  }

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
    this.selectedOptions = const [],
  });

  /// Cart dedup key. Two lines with different option selections are distinct.
  /// Equals [name] when there are no options → products without modifiers keep
  /// the previous name-based merge behaviour unchanged.
  String get lineKey => selectedOptions.isEmpty
      ? name
      : '$name|${selectedOptions.map((o) => '${o.group}=${o.items.join(",")}').join(';')}';

  Map<String, dynamic> toJson() => {
        'productId': productId,
        'name': name,
        'price': price,
        'quantity': quantity,
        'purchaseStatus': purchaseStatus,
        if (actualPrice != null) 'actualPrice': actualPrice,
        if (selectedOptions.isNotEmpty)
          'selected_options':
              selectedOptions.map((o) => o.toJson()).toList(),
      };

  factory CartItem.fromJson(Map<String, dynamic> json) {
    final rawId = json['productId'] as String?;
    final name = json['name'] as String;
    final rawOpts = json['selected_options'] as List?;
    return CartItem._raw(
      productId: (rawId == null || rawId.isEmpty) ? name : rawId,
      name: name,
      price: (json['price'] as num).toDouble(),
      quantity: json['quantity'] as int? ?? 1,
      purchaseStatus: json['purchaseStatus'] as String? ?? 'pending',
      actualPrice: (json['actualPrice'] as num?)?.toDouble(),
      selectedOptions: rawOpts == null
          ? const []
          : rawOpts
              .map((e) => SelectedOption.fromJson(e as Map<String, dynamic>))
              .toList(),
    );
  }
}
