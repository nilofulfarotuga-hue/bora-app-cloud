class MenuItem {
  final String name;
  final double price;

  MenuItem({
    required this.name,
    required this.price,
  });

  MenuItem copyWith({String? name, double? price}) {
    return MenuItem(
      name: name ?? this.name,
      price: price ?? this.price,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'name': name,
      'price': price,
    };
  }

  factory MenuItem.fromMap(Map<String, dynamic> map) {
    return MenuItem(
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
  final List<MarketProduct> products;

  const RetailStore({
    required this.name,
    required this.isPartner,
    required this.category,
    required this.products,
  });
}

