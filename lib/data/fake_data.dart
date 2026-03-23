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

final List<Restaurant> fakeRestaurants = [
  Restaurant(
    name: "Pizzaria do Zé",
    isPartner: true,
    menu: [
      MenuItem(name: "Pizza Margherita", price: 8.50),
      MenuItem(name: "Pizza Pepperoni", price: 9.20),
      MenuItem(name: "Pizza Portuguesa", price: 9.80),
      MenuItem(name: "Pão de Alho", price: 3.40),
      MenuItem(name: "Tiramisu", price: 4.50),
    ],
  ),
  Restaurant(
    name: "Kebab do Mané",
    isPartner: true,
    menu: [
      MenuItem(name: "Kebab no pão", price: 6.20),
      MenuItem(name: "Kebab no prato", price: 7.80),
      MenuItem(name: "Batatas fritas", price: 2.50),
      MenuItem(name: "Refrigerante", price: 1.80),
    ],
  ),
  Restaurant(
    name: "Hamburgueria Lisboa Grill",
    isPartner: true,
    menu: [
      MenuItem(name: "Burger clássico", price: 7.90),
      MenuItem(name: "Burger bacon", price: 8.40),
      MenuItem(name: "Batata frita", price: 3.00),
      MenuItem(name: "Milkshake", price: 3.90),
    ],
  ),
  Restaurant(
    name: "Pastelaria Central",
    isPartner: true,
    menu: [
      MenuItem(name: "Pastel de nata", price: 1.20),
      MenuItem(name: "Bola de berlim", price: 1.80),
      MenuItem(name: "Sandes mista", price: 3.20),
      MenuItem(name: "Café cappuccino", price: 2.10),
    ],
  ),
  Restaurant(
    name: "Churrasqueira do Bairro",
    isPartner: true,
    menu: [
      MenuItem(name: "Frango assado inteiro", price: 9.50),
      MenuItem(name: "Batatas assadas", price: 3.10),
      MenuItem(name: "Salada mista", price: 2.80),
      MenuItem(name: "Molho picante", price: 1.00),
    ],
  ),
  Restaurant(
    name: "Burger King",
    isPartner: false,
    menu: [
      MenuItem(name: "Whopper", price: 7.90),
      MenuItem(name: "Cheeseburger", price: 3.50),
      MenuItem(name: "Onion Rings", price: 2.80),
      MenuItem(name: "French Fries", price: 2.60),
      MenuItem(name: "Coca Cola", price: 1.90),
    ],
  ),
  Restaurant(
    name: "KFC",
    isPartner: false,
    menu: [
      MenuItem(name: "Balde de Frango", price: 12.00),
      MenuItem(name: "Chicken Burger", price: 6.50),
      MenuItem(name: "Hot Wings", price: 5.20),
      MenuItem(name: "Pepsi", price: 1.90),
    ],
  ),
  Restaurant(
    name: "McDonald's",
    isPartner: false,
    menu: [
      MenuItem(name: "Big Mac", price: 7.50),
      MenuItem(name: "McChicken", price: 6.20),
      MenuItem(name: "McNuggets", price: 4.90),
      MenuItem(name: "Fries", price: 2.50),
      MenuItem(name: "Coca Cola", price: 1.80),
    ],
  ),
  Restaurant(
    name: "Pizza Hut",
    isPartner: false,
    menu: [
      MenuItem(name: "Pizza Pepperoni Lovers", price: 10.20),
      MenuItem(name: "Pizza Super Supreme", price: 11.40),
      MenuItem(name: "Garlic Bread", price: 3.30),
      MenuItem(name: "Cinnamon Sticks", price: 3.80),
      MenuItem(name: "Coca Cola", price: 1.90),
    ],
  ),
];

final List<RetailStore> fakeMarkets = [
  RetailStore(
    name: "Mini Mercado Lisboa",
    isPartner: true,
    category: StoreCategory.market,
    products: [
      MarketProduct(name: "Banana", price: 1.80),
      MarketProduct(name: "Apple", price: 2.10),
      MarketProduct(name: "Bread", price: 1.50),
      MarketProduct(name: "Milk", price: 1.10),
      MarketProduct(name: "Eggs", price: 2.20),
      MarketProduct(name: "Rice", price: 2.40),
      MarketProduct(name: "Pasta", price: 1.90),
      MarketProduct(name: "Olive oil", price: 5.50),
    ],
  ),
  RetailStore(
    name: "Super Bairro Market",
    isPartner: true,
    category: StoreCategory.market,
    products: [
      MarketProduct(name: "Banana", price: 1.70),
      MarketProduct(name: "Apple", price: 1.95),
      MarketProduct(name: "Bread", price: 1.40),
      MarketProduct(name: "Milk", price: 1.05),
      MarketProduct(name: "Eggs", price: 2.15),
      MarketProduct(name: "Rice", price: 2.30),
      MarketProduct(name: "Pasta", price: 1.85),
      MarketProduct(name: "Olive oil", price: 5.30),
    ],
  ),
  RetailStore(
    name: "Mercado Fresco",
    isPartner: true,
    category: StoreCategory.market,
    products: [
      MarketProduct(name: "Banana", price: 1.85),
      MarketProduct(name: "Apple", price: 2.05),
      MarketProduct(name: "Bread", price: 1.55),
      MarketProduct(name: "Milk", price: 1.15),
      MarketProduct(name: "Eggs", price: 2.25),
      MarketProduct(name: "Rice", price: 2.45),
      MarketProduct(name: "Pasta", price: 1.95),
      MarketProduct(name: "Olive oil", price: 5.60),
    ],
  ),
];

final List<RetailStore> fakePharmacies = [
  RetailStore(
    name: "Farmácia Central",
    isPartner: false,
    category: StoreCategory.pharmacy,
    products: [
      MarketProduct(name: "Paracetamol", price: 3.50),
      MarketProduct(name: "Ibuprofen", price: 4.10),
      MarketProduct(name: "Vitamin C", price: 6.90),
      MarketProduct(name: "Hand sanitizer", price: 3.20),
      MarketProduct(name: "Bandages", price: 2.60),
    ],
  ),
  RetailStore(
    name: "Farmácia Lisboa",
    isPartner: false,
    category: StoreCategory.pharmacy,
    products: [
      MarketProduct(name: "Paracetamol", price: 3.40),
      MarketProduct(name: "Ibuprofen", price: 4.00),
      MarketProduct(name: "Vitamin C", price: 6.70),
      MarketProduct(name: "Hand sanitizer", price: 3.10),
      MarketProduct(name: "Bandages", price: 2.50),
    ],
  ),
  RetailStore(
    name: "Farmácia Saúde",
    isPartner: false,
    category: StoreCategory.pharmacy,
    products: [
      MarketProduct(name: "Paracetamol", price: 3.60),
      MarketProduct(name: "Ibuprofen", price: 4.20),
      MarketProduct(name: "Vitamin C", price: 7.10),
      MarketProduct(name: "Hand sanitizer", price: 3.30),
      MarketProduct(name: "Bandages", price: 2.70),
    ],
  ),
];

final Map<String, RetailStore> fakeStoreLookup = {
  for (final store in [...fakeMarkets, ...fakePharmacies]) store.name: store,
};