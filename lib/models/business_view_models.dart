class MenuItem {
  /// Source product id (`products.id`). Required for create_order RPC
  /// (server-side DB lookup uses this). NEVER use the name as fallback —
  /// see Bug-B fix 2026-04-30.
  final String? productId;
  final String name;
  final double price;

  MenuItem({
    this.productId,
    required this.name,
    required this.price,
  });

  MenuItem copyWith({String? productId, String? name, double? price}) {
    return MenuItem(
      productId: productId ?? this.productId,
      name: name ?? this.name,
      price: price ?? this.price,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      if (productId != null) 'productId': productId,
      'name': name,
      'price': price,
    };
  }

  factory MenuItem.fromMap(Map<String, dynamic> map) {
    return MenuItem(
      productId: map['productId'] as String?,
      name: map['name'] as String? ?? '',
      price: (map['price'] as num?)?.toDouble() ?? 0,
    );
  }
}

class Restaurant {
  final String name;
  final bool isPartner;
  final List<MenuItem> menu;

  const Restaurant({
    required this.name,
    required this.isPartner,
    required this.menu,
  });
}

class MarketProduct {
  final String name;
  final double price;

  MarketProduct({
    required this.name,
    required this.price,
  });
}

enum StoreCategory { market, pharmacy }

class RetailStore {
  final String name;
  final bool isPartner;
  final StoreCategory category;

  const RetailStore({
    required this.name,
    required this.isPartner,
    required this.category,
  });
}
