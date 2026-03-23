import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/order_model.dart';
import '../models/partner_product.dart';
import '../models/restaurant_model.dart';
import '../services/product_scraper_service.dart';

class RestaurantStore extends ChangeNotifier {
  final supabase = Supabase.instance.client;

  // Single source of truth — populated only from Supabase.
  final List<RestaurantModel> _restaurants = [];

  RealtimeChannel? _restaurantsChannel;
  RealtimeChannel? _productsChannel;

  RestaurantStore() {
    _init();
  }

  /// Sequences restaurant load first, then product load, to satisfy the FK
  /// constraint when seeding both tables on first run.
  /// Scraping runs in the background after the core load completes.
  Future<void> _init() async {
    await loadRestaurantsFromSupabase();
    await loadProductsFromSupabase();
    // Fire-and-forget: scraping is slow and deduplication in
    // syncProductsFromExternalSource makes concurrent calls safe.
    loadScrapedProductsForStore('market-continente', 'continente').ignore();
    loadScrapedProductsForStore('market-pingo-doce', 'pingodoce').ignore();
  }

  final Map<String, List<PartnerProduct>> _productsByRestaurant = {};

  final Map<String, Map<String, OrderModel>> _ordersByRestaurant = {};
  final Map<String, int> _orderStatusCache = {};

  // ─── Default seed data ────────────────────────────────────────────────────
  // Inserted into Supabase on first run only (when DB table is empty).
  // Upsert is NOT used here intentionally — manual DB edits are preserved.

  static final List<Map<String, dynamic>> _kDefaultRestaurants = [
    // ── Partner restaurants (real menus come from products table) ────────────
    {
      'id': 'rest-pizzahut',
      'name': 'Pizza Hut',
      'phone': '210000001',
      'address': 'Av. de Berna 12, Lisboa',
      'email': 'contato@pizzahut.pt',
      'photo_url': 'https://via.placeholder.com/240x140.png?text=Pizza+Hut',
      'cuisine_type': 'Pizzaria',
      'is_partner': true,
      'category': 'restaurant',
      'is_online': true,
      'lat': 38.7441,
      'lng': -9.1602,
    },
    {
      'id': 'rest-kfc',
      'name': 'KFC',
      'phone': '210000002',
      'address': 'Praça Martim Moniz 2, Lisboa',
      'email': 'contato@kfc.pt',
      'photo_url': 'https://via.placeholder.com/240x140.png?text=KFC',
      'cuisine_type': 'Frango Frito',
      'is_partner': true,
      'category': 'restaurant',
      'is_online': true,
      'lat': 38.7362,
      'lng': -9.1283,
    },
    // ── Non-partner restaurants (driver buys on behalf of client) ────────────
    {
      'id': 'rest-mcdonalds',
      'name': "McDonald's",
      'phone': '210000003',
      'address': 'Av. Fontes Pereira de Melo 5, Lisboa',
      'email': 'contato@mcdonalds.pt',
      'photo_url':
          "https://via.placeholder.com/240x140.png?text=McDonald%27s",
      'cuisine_type': 'Fast Food',
      'is_partner': false,
      'category': 'restaurant',
      'is_online': true,
      'lat': 38.7265,
      'lng': -9.1409,
    },
    {
      'id': 'rest-burger-king',
      'name': 'Burger King',
      'phone': '210000004',
      'address': 'R. Joaquim António de Aguiar 16, Lisboa',
      'email': 'contato@burgerking.pt',
      'photo_url':
          'https://via.placeholder.com/240x140.png?text=Burger+King',
      'cuisine_type': 'Hambúrgueres',
      'is_partner': false,
      'category': 'restaurant',
      'is_online': true,
      'lat': 38.7301,
      'lng': -9.1467,
    },
    // ── Non-partner supermarkets ──────────────────────────────────────────────
    {
      'id': 'market-pingo-doce',
      'name': 'Pingo Doce',
      'phone': '210000101',
      'address': 'Av. João XXI 50, Lisboa',
      'email': 'contacto@pingodoce.pt',
      'photo_url':
          'https://via.placeholder.com/240x140.png?text=Pingo+Doce',
      'cuisine_type': 'Supermercado',
      'is_partner': false,
      'category': 'supermarket',
      'is_online': true,
      'lat': 38.7377,
      'lng': -9.1382,
    },
    {
      'id': 'market-continente',
      'name': 'Continente',
      'phone': '210000102',
      'address': 'Centro Colombo, Av. Lusíada, Lisboa',
      'email': 'contacto@continente.pt',
      'photo_url':
          'https://via.placeholder.com/240x140.png?text=Continente',
      'cuisine_type': 'Supermercado',
      'is_partner': false,
      'category': 'supermarket',
      'is_online': true,
      'lat': 38.7532,
      'lng': -9.1836,
    },
    {
      'id': 'market-lidl',
      'name': 'Lidl',
      'phone': '210000103',
      'address': 'Rua Capitão Renato Baptista 18, Lisboa',
      'email': 'contacto@lidl.pt',
      'photo_url': 'https://via.placeholder.com/240x140.png?text=Lidl',
      'cuisine_type': 'Supermercado',
      'is_partner': false,
      'category': 'supermarket',
      'is_online': true,
      'lat': 38.7460,
      'lng': -9.1460,
    },
    {
      'id': 'market-mercadona',
      'name': 'Mercadona',
      'phone': '210000104',
      'address': 'Av. Infante D. Henrique 333, Lisboa',
      'email': 'contacto@mercadona.pt',
      'photo_url':
          'https://via.placeholder.com/240x140.png?text=Mercadona',
      'cuisine_type': 'Supermercado',
      'is_partner': false,
      'category': 'supermarket',
      'is_online': true,
      'lat': 38.7200,
      'lng': -9.1120,
    },
    // ── Non-partner pharmacy ─────────────────────────────────────────────────
    {
      'id': 'pharmacy-central',
      'name': 'Farmácia Central',
      'phone': '210000301',
      'address': 'Rossio 28, Lisboa',
      'email': 'atendimento@farmaciacentral.pt',
      'photo_url':
          'https://via.placeholder.com/240x140.png?text=Farmacia',
      'cuisine_type': 'Saúde e bem-estar',
      'is_partner': false,
      'category': 'pharmacy',
      'is_online': true,
      'lat': 38.7140,
      'lng': -9.1401,
    },
    // ── Non-partner local store ───────────────────────────────────────────────
    {
      'id': 'store-loja-local',
      'name': 'Loja Local Exemplo',
      'phone': '210000201',
      'address': 'Rua Augusta 150, Lisboa',
      'email': 'contacto@lojalocal.pt',
      'photo_url':
          'https://via.placeholder.com/240x140.png?text=Loja+Local',
      'cuisine_type': 'Artigos locais',
      'is_partner': false,
      'category': 'store',
      'is_online': true,
      'lat': 38.7091,
      'lng': -9.1376,
    },
  ];

  /// Sample products seeded alongside restaurants on first run.
  /// Non-partner products have base prices — the 15% markup is applied
  /// at cart time via CartStore.addItem() → PricingService.applyMarkup().
  static final List<Map<String, dynamic>> _kDefaultProducts = [
    // McDonald's menu (non-partner)
    {'id': 'prod-mcd-1', 'restaurant_id': 'rest-mcdonalds', 'name': 'Big Mac', 'description': 'Dois patties de vaca, alface, queijo, pickles e molho especial', 'price': 7.50, 'photo_url': '', 'is_available': true},
    {'id': 'prod-mcd-2', 'restaurant_id': 'rest-mcdonalds', 'name': 'McChicken', 'description': 'Hambúrguer de frango panado com maionese e alface', 'price': 6.20, 'photo_url': '', 'is_available': true},
    {'id': 'prod-mcd-3', 'restaurant_id': 'rest-mcdonalds', 'name': 'McNuggets 9 pcs', 'description': 'Nuggets de frango crocante', 'price': 4.90, 'photo_url': '', 'is_available': true},
    {'id': 'prod-mcd-4', 'restaurant_id': 'rest-mcdonalds', 'name': 'Batatas Fritas M', 'description': 'Batatas fritas estaladiças tamanho médio', 'price': 2.50, 'photo_url': '', 'is_available': true},
    {'id': 'prod-mcd-5', 'restaurant_id': 'rest-mcdonalds', 'name': 'Coca Cola M', 'description': 'Refrigerante tamanho médio', 'price': 1.80, 'photo_url': '', 'is_available': true},
    // Burger King menu (non-partner)
    {'id': 'prod-bk-1', 'restaurant_id': 'rest-burger-king', 'name': 'Whopper', 'description': 'Hambúrguer grelhado com alface, tomate, cebola, pickles e maionese', 'price': 7.90, 'photo_url': '', 'is_available': true},
    {'id': 'prod-bk-2', 'restaurant_id': 'rest-burger-king', 'name': 'Chicken Royale', 'description': 'Hambúrguer de frango crocante com maionese e alface', 'price': 6.80, 'photo_url': '', 'is_available': true},
    {'id': 'prod-bk-3', 'restaurant_id': 'rest-burger-king', 'name': 'Onion Rings M', 'description': 'Anéis de cebola estaladiços', 'price': 2.80, 'photo_url': '', 'is_available': true},
    {'id': 'prod-bk-4', 'restaurant_id': 'rest-burger-king', 'name': 'Batatas Fritas M', 'description': 'Batatas fritas crocantes tamanho médio', 'price': 2.60, 'photo_url': '', 'is_available': true},
    {'id': 'prod-bk-5', 'restaurant_id': 'rest-burger-king', 'name': 'Pepsi M', 'description': 'Refrigerante tamanho médio', 'price': 1.90, 'photo_url': '', 'is_available': true},
    // Pingo Doce (non-partner supermarket)
    {'id': 'prod-pd-1', 'restaurant_id': 'market-pingo-doce', 'name': 'Banana', 'description': 'Banana tropical, aprox. 1 kg', 'price': 1.29, 'photo_url': '', 'is_available': true},
    {'id': 'prod-pd-2', 'restaurant_id': 'market-pingo-doce', 'name': 'Leite meio-gordo 1L', 'description': 'Leite UHT meio-gordo', 'price': 0.89, 'photo_url': '', 'is_available': true},
    {'id': 'prod-pd-3', 'restaurant_id': 'market-pingo-doce', 'name': 'Pão de forma', 'description': 'Pão de forma fatiado 500g', 'price': 1.49, 'photo_url': '', 'is_available': true},
    {'id': 'prod-pd-4', 'restaurant_id': 'market-pingo-doce', 'name': 'Ovos M (10 un)', 'description': 'Ovos brancos categoria M', 'price': 2.39, 'photo_url': '', 'is_available': true},
    {'id': 'prod-pd-5', 'restaurant_id': 'market-pingo-doce', 'name': 'Arroz carolino 1kg', 'description': 'Arroz carolino branco', 'price': 1.19, 'photo_url': '', 'is_available': true},
    {'id': 'prod-pd-6', 'restaurant_id': 'market-pingo-doce', 'name': 'Azeite virgem extra 75cl', 'description': 'Azeite virgem extra português', 'price': 4.99, 'photo_url': '', 'is_available': true},
    // Continente (non-partner supermarket)
    {'id': 'prod-cont-1', 'restaurant_id': 'market-continente', 'name': 'Banana', 'description': 'Banana tropical, aprox. 1 kg', 'price': 1.19, 'photo_url': '', 'is_available': true},
    {'id': 'prod-cont-2', 'restaurant_id': 'market-continente', 'name': 'Leite UHT 1L', 'description': 'Leite UHT meio-gordo Continente', 'price': 0.79, 'photo_url': '', 'is_available': true},
    {'id': 'prod-cont-3', 'restaurant_id': 'market-continente', 'name': 'Pão de forma integral', 'description': 'Pão de forma integral fatiado 400g', 'price': 1.39, 'photo_url': '', 'is_available': true},
    {'id': 'prod-cont-4', 'restaurant_id': 'market-continente', 'name': 'Ovos L (6 un)', 'description': 'Ovos brancos categoria L', 'price': 2.29, 'photo_url': '', 'is_available': true},
    {'id': 'prod-cont-5', 'restaurant_id': 'market-continente', 'name': 'Massa esparguete 500g', 'description': 'Massa esparguete de trigo durum', 'price': 1.09, 'photo_url': '', 'is_available': true},
    {'id': 'prod-cont-6', 'restaurant_id': 'market-continente', 'name': 'Azeite 75cl', 'description': 'Azeite virgem português', 'price': 4.79, 'photo_url': '', 'is_available': true},
    // Lidl (non-partner supermarket)
    {'id': 'prod-lidl-1', 'restaurant_id': 'market-lidl', 'name': 'Banana bio', 'description': 'Banana biológica certificada, aprox. 1 kg', 'price': 1.39, 'photo_url': '', 'is_available': true},
    {'id': 'prod-lidl-2', 'restaurant_id': 'market-lidl', 'name': 'Leite gordo 1L', 'description': 'Leite UHT gordo Milbona', 'price': 0.85, 'photo_url': '', 'is_available': true},
    {'id': 'prod-lidl-3', 'restaurant_id': 'market-lidl', 'name': 'Pão de mistura', 'description': 'Pão de mistura trigo e centeio 500g', 'price': 1.59, 'photo_url': '', 'is_available': true},
    {'id': 'prod-lidl-4', 'restaurant_id': 'market-lidl', 'name': 'Ovos XL (10 un)', 'description': 'Ovos brancos categoria XL', 'price': 2.49, 'photo_url': '', 'is_available': true},
    {'id': 'prod-lidl-5', 'restaurant_id': 'market-lidl', 'name': 'Arroz longo 1kg', 'description': 'Arroz de grão longo tipo Basmati', 'price': 1.29, 'photo_url': '', 'is_available': true},
    {'id': 'prod-lidl-6', 'restaurant_id': 'market-lidl', 'name': 'Azeite bio 75cl', 'description': 'Azeite virgem extra biológico', 'price': 5.49, 'photo_url': '', 'is_available': true},
    // Mercadona (non-partner supermarket)
    {'id': 'prod-merc-1', 'restaurant_id': 'market-mercadona', 'name': 'Banana', 'description': 'Banana Hacendado, aprox. 1 kg', 'price': 1.25, 'photo_url': '', 'is_available': true},
    {'id': 'prod-merc-2', 'restaurant_id': 'market-mercadona', 'name': 'Leite semi-desnatado 1L', 'description': 'Leite UHT semi-desnatado Hacendado', 'price': 0.82, 'photo_url': '', 'is_available': true},
    {'id': 'prod-merc-3', 'restaurant_id': 'market-mercadona', 'name': 'Pão de centeio', 'description': 'Pão de centeio fatiado 500g', 'price': 1.45, 'photo_url': '', 'is_available': true},
    {'id': 'prod-merc-4', 'restaurant_id': 'market-mercadona', 'name': 'Ovos M (12 un)', 'description': 'Ovos brancos categoria M Hacendado', 'price': 2.35, 'photo_url': '', 'is_available': true},
    {'id': 'prod-merc-5', 'restaurant_id': 'market-mercadona', 'name': 'Macarrão 500g', 'description': 'Macarrão de trigo durum Hacendado', 'price': 0.99, 'photo_url': '', 'is_available': true},
    {'id': 'prod-merc-6', 'restaurant_id': 'market-mercadona', 'name': 'Azeite virgem 75cl', 'description': 'Azeite virgem Hacendado', 'price': 4.89, 'photo_url': '', 'is_available': true},
    // Farmácia Central (non-partner pharmacy)
    {'id': 'prod-farm-1', 'restaurant_id': 'pharmacy-central', 'name': 'Paracetamol 500mg', 'description': 'Analgésico e antipirético, 20 comprimidos', 'price': 3.50, 'photo_url': '', 'is_available': true},
    {'id': 'prod-farm-2', 'restaurant_id': 'pharmacy-central', 'name': 'Ibuprofeno 400mg', 'description': 'Anti-inflamatório, 20 comprimidos', 'price': 4.10, 'photo_url': '', 'is_available': true},
    {'id': 'prod-farm-3', 'restaurant_id': 'pharmacy-central', 'name': 'Vitamina C 1000mg', 'description': 'Suplemento vitamínico, 30 comprimidos efervescentes', 'price': 6.90, 'photo_url': '', 'is_available': true},
    {'id': 'prod-farm-4', 'restaurant_id': 'pharmacy-central', 'name': 'Gel desinfetante 500ml', 'description': 'Gel antisséptico de mãos', 'price': 3.20, 'photo_url': '', 'is_available': true},
    {'id': 'prod-farm-5', 'restaurant_id': 'pharmacy-central', 'name': 'Penso rápido', 'description': 'Caixa com 20 pensos de vários tamanhos', 'price': 2.60, 'photo_url': '', 'is_available': true},
    {'id': 'prod-farm-6', 'restaurant_id': 'pharmacy-central', 'name': 'Termómetro digital', 'description': 'Termómetro digital de ouvido com display LCD', 'price': 8.90, 'photo_url': '', 'is_available': true},
    // Loja Local Exemplo (non-partner store)
    {'id': 'prod-loja-1', 'restaurant_id': 'store-loja-local', 'name': 'Caneca de cerâmica', 'description': 'Caneca artesanal portuguesa decorada, 350ml', 'price': 12.90, 'photo_url': '', 'is_available': true},
    {'id': 'prod-loja-2', 'restaurant_id': 'store-loja-local', 'name': 'Tote bag Lisboa', 'description': 'Saco de pano com motivos de Lisboa', 'price': 8.50, 'photo_url': '', 'is_available': true},
    {'id': 'prod-loja-3', 'restaurant_id': 'store-loja-local', 'name': 'Porta-chaves artesanal', 'description': 'Porta-chaves em cortiça portuguesa', 'price': 5.90, 'photo_url': '', 'is_available': true},
    {'id': 'prod-loja-4', 'restaurant_id': 'store-loja-local', 'name': 'Postal ilustrado', 'description': 'Conjunto de 4 postais com ilustrações de Lisboa', 'price': 2.50, 'photo_url': '', 'is_available': true},
  ];

  /// IDs of products that were seeded on first run — used to tag in-memory
  /// instances with [ProductSource.localSeed] after loading from Supabase.
  static final Set<String> _kSeedProductIds = {
    for (final p in _kDefaultProducts) p['id'] as String,
  };

  // ─── Getters ──────────────────────────────────────────────────────────────

  List<RestaurantModel> get restaurants => List.unmodifiable(_restaurants);

  List<PartnerProduct> partnerProductsForRestaurant(
    String restaurantId, {
    bool onlyAvailable = false,
  }) {
    final products = List<PartnerProduct>.of(
      _productsByRestaurant[restaurantId] ?? const <PartnerProduct>[],
    );
    if (!onlyAvailable) {
      return List.unmodifiable(products);
    }
    return List.unmodifiable(
      products.where((product) => product.isAvailable),
    );
  }

  List<OrderModel> ordersForRestaurant(String restaurantId) {
    final orders = _ordersByRestaurant[restaurantId]?.values ??
        const Iterable<OrderModel>.empty();
    return orders
        .where(
          (order) =>
              order.status == OrderStatus.created ||
              order.status == OrderStatus.preparing ||
              order.status == OrderStatus.callingDriver,
        )
        .toList(growable: false)
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
  }

  RestaurantModel? restaurantByName(String? vendorName) {
    if (vendorName == null) return null;
    final normalized = vendorName.toLowerCase();
    try {
      return restaurants.firstWhere(
        (restaurant) =>
            restaurant.isPartner &&
            restaurant.name.toLowerCase() == normalized,
      );
    } catch (_) {
      return null;
    }
  }

  RestaurantModel? restaurantByEmail(String? email) {
    if (email == null) return null;
    final normalized = email.toLowerCase();
    try {
      return restaurants.firstWhere(
        (restaurant) => restaurant.email.toLowerCase() == normalized,
      );
    } catch (_) {
      return null;
    }
  }

  bool hasPartnerWithEmail(String email) {
    final normalized = email.trim().toLowerCase();
    return restaurants
        .any((restaurant) => restaurant.email.toLowerCase() == normalized);
  }

  // ─── Load from Supabase ───────────────────────────────────────────────────

  Future<void> loadRestaurantsFromSupabase() async {
    try {
      List<dynamic> response = await supabase.from('restaurants').select();

      // Seed defaults only when the DB table is empty (first run).
      if (response.isEmpty) {
        await _seedDefaultRestaurants();
        response = await supabase.from('restaurants').select();
      }

      _restaurants.clear();
      for (final record in response) {
        _restaurants.add(_restaurantFromRecord(record as Map<String, dynamic>));
      }

      notifyListeners();
      debugPrint(
          'RestaurantStore: loaded ${_restaurants.length} restaurants from DB');
    } catch (e) {
      debugPrint('RestaurantStore: loadRestaurantsFromSupabase error => $e');
    }

    _subscribeRestaurantsRealtime();
  }

  /// Inserts default restaurants AND their sample products into Supabase.
  /// Called only when the restaurants table is empty (first run).
  Future<void> _seedDefaultRestaurants() async {
    try {
      await supabase.from('restaurants').insert(_kDefaultRestaurants);
      // Products are seeded alongside restaurants to satisfy the FK constraint.
      await supabase.from('products').insert(_kDefaultProducts);
      debugPrint(
          'RestaurantStore: seeded ${_kDefaultRestaurants.length} restaurants '
          'and ${_kDefaultProducts.length} products');
    } catch (e) {
      debugPrint('RestaurantStore: _seedDefaultRestaurants error => $e');
    }
  }

  Future<void> loadProductsFromSupabase() async {
    try {
      final List<dynamic> response = await supabase.from('products').select();

      _productsByRestaurant.clear();

      for (final record in response) {
        final data = record as Map<String, dynamic>;

        final restaurantId = (data['restaurant_id'] ?? '').toString();
        if (restaurantId.isEmpty) continue;

        final productId = (data['id'] ?? '').toString();
        final product = PartnerProduct(
          id: productId,
          restaurantId: restaurantId,
          name: data['name'] ?? '',
          description: data['description'] ?? '',
          price: (data['price'] as num? ?? 0).toDouble(),
          photoUrl: data['photo_url'] ?? '',
          isAvailable: data['is_available'] ?? true,
          source: _kSeedProductIds.contains(productId)
              ? ProductSource.localSeed
              : ProductSource.api,
        );

        _productsByRestaurant
            .putIfAbsent(restaurantId, () => <PartnerProduct>[])
            .add(product);
      }

      notifyListeners();
      debugPrint(
          'RestaurantStore: loaded products for ${_productsByRestaurant.length} restaurants');
    } catch (e) {
      debugPrint('RestaurantStore: loadProductsFromSupabase error => $e');
    }

    _subscribeProductsRealtime();
  }

  // ─── Realtime subscriptions ───────────────────────────────────────────────

  void _subscribeRestaurantsRealtime() {
    if (_restaurantsChannel != null) return;

    _restaurantsChannel = supabase.channel('restaurants_channel')
      ..onPostgresChanges(
        event: PostgresChangeEvent.insert,
        schema: 'public',
        table: 'restaurants',
        callback: (payload) {
          final data = payload.newRecord;
          if (data.isEmpty) return;
          final restaurant = _restaurantFromRecord(data);
          final exists = _restaurants.any((r) => r.id == restaurant.id);
          if (!exists) {
            _restaurants.add(restaurant);
            notifyListeners();
          }
        },
      )
      ..onPostgresChanges(
        event: PostgresChangeEvent.update,
        schema: 'public',
        table: 'restaurants',
        callback: (payload) {
          final data = payload.newRecord;
          if (data.isEmpty) return;
          final updated = _restaurantFromRecord(data);
          final index = _restaurants.indexWhere((r) => r.id == updated.id);
          if (index != -1) {
            _restaurants[index] = updated;
            notifyListeners();
          }
        },
      )
      ..subscribe((status, [error]) {
        debugPrint(
            'RestaurantStore restaurants Realtime: $status${error != null ? ' | $error' : ''}');
      });
  }

  void _subscribeProductsRealtime() {
    if (_productsChannel != null) return;

    _productsChannel = supabase.channel('products_channel')
      ..onPostgresChanges(
        event: PostgresChangeEvent.insert,
        schema: 'public',
        table: 'products',
        callback: (payload) {
          final data = payload.newRecord;
          if (data.isEmpty) return;
          final restaurantId = (data['restaurant_id'] ?? '').toString();
          if (restaurantId.isEmpty) return;
          final productId = (data['id'] ?? '').toString();
          final product = PartnerProduct(
            id: productId,
            restaurantId: restaurantId,
            name: data['name'] ?? '',
            description: data['description'] ?? '',
            price: (data['price'] as num? ?? 0).toDouble(),
            photoUrl: data['photo_url'] ?? '',
            isAvailable: data['is_available'] ?? true,
            source: ProductSource.api,
          );
          final list = _productsByRestaurant.putIfAbsent(
              restaurantId, () => <PartnerProduct>[]);
          final exists = list.any((p) => p.id == product.id);
          if (!exists) {
            list.add(product);
            notifyListeners();
          }
        },
      )
      ..onPostgresChanges(
        event: PostgresChangeEvent.update,
        schema: 'public',
        table: 'products',
        callback: (payload) {
          final data = payload.newRecord;
          if (data.isEmpty) return;
          final restaurantId = (data['restaurant_id'] ?? '').toString();
          if (restaurantId.isEmpty) return;
          final productId = (data['id'] ?? '').toString();
          final list = _productsByRestaurant[restaurantId];
          if (list == null) return;
          final index = list.indexWhere((p) => p.id == productId);
          if (index == -1) return;
          list[index] = PartnerProduct(
            id: productId,
            restaurantId: restaurantId,
            name: data['name'] ?? '',
            description: data['description'] ?? '',
            price: (data['price'] as num? ?? 0).toDouble(),
            photoUrl: data['photo_url'] ?? '',
            isAvailable: data['is_available'] ?? true,
            source: list[index].source, // preserve original source on update
          );
          notifyListeners();
        },
      )
      ..onPostgresChanges(
        event: PostgresChangeEvent.delete,
        schema: 'public',
        table: 'products',
        callback: (payload) {
          final old = payload.oldRecord;
          if (old.isEmpty) return;
          final productId = (old['id'] ?? '').toString();
          final restaurantId = (old['restaurant_id'] ?? '').toString();
          final list = _productsByRestaurant[restaurantId];
          if (list == null) return;
          final before = list.length;
          list.removeWhere((p) => p.id == productId);
          if (list.length != before) notifyListeners();
        },
      )
      ..subscribe((status, [error]) {
        debugPrint(
            'RestaurantStore products Realtime: $status${error != null ? ' | $error' : ''}');
      });
  }

  // ─── Mutations ────────────────────────────────────────────────────────────

  Future<RestaurantModel> registerPartnerRestaurant({
    required String name,
    required String address,
    required String phone,
    required String email,
    required String photoUrl,
    required String cuisineType,
    required BusinessCategory category,
    double? lat,
    double? lng,
  }) async {
    final normalizedEmail = email.trim().toLowerCase();
    if (hasPartnerWithEmail(normalizedEmail)) {
      throw StateError('Já existe um restaurante parceiro com este email.');
    }

    final trimmedName = name.trim();
    final generatedPhoto = photoUrl.trim().isEmpty
        ? 'https://via.placeholder.com/240x140.png?text=${Uri.encodeComponent(trimmedName)}'
        : photoUrl.trim();

    final restaurant = RestaurantModel(
      id: 'partner-${DateTime.now().microsecondsSinceEpoch}',
      name: trimmedName,
      phone: phone.trim(),
      address: address.trim(),
      email: normalizedEmail,
      photoUrl: generatedPhoto,
      cuisineType: cuisineType.trim().isEmpty ? 'Variado' : cuisineType.trim(),
      isPartner: true,
      category: category,
      lat: lat,
      lng: lng,
    );

    debugPrint('RestaurantStore: registering partner ${restaurant.name}');

    try {
      await supabase.from('restaurants').insert({
        'id': restaurant.id,
        'name': restaurant.name,
        'address': restaurant.address,
        'phone': restaurant.phone,
        'email': restaurant.email,
        'photo_url': restaurant.photoUrl,
        'cuisine_type': restaurant.cuisineType,
        'is_partner': restaurant.isPartner,
        'category': restaurant.category.name,
        'is_online': true,
        if (restaurant.lat != null) 'lat': restaurant.lat,
        if (restaurant.lng != null) 'lng': restaurant.lng,
      });
      debugPrint('RestaurantStore: partner saved to Supabase');
      await loadRestaurantsFromSupabase();
    } catch (e) {
      debugPrint('RestaurantStore: Supabase insert error => $e');
      // Add locally so the session works even if DB is temporarily down.
      final exists = _restaurants.any((r) => r.id == restaurant.id);
      if (!exists) {
        _restaurants.add(restaurant);
        notifyListeners();
      }
    }

    return restaurant;
  }

  // addPartnerProduct inserts into local list immediately (sync contract required
  // by PartnerProductStore) then persists to Supabase in the background.
  PartnerProduct addPartnerProduct({
    required String restaurantId,
    required String name,
    required String description,
    required double price,
    required String photoUrl,
    required bool isAvailable,
  }) {
    final trimmedName = name.trim();
    final trimmedDescription = description.trim();
    final normalizedPhoto = photoUrl.trim().isEmpty
        ? 'https://via.placeholder.com/240x140.png?text=${Uri.encodeComponent(trimmedName)}'
        : photoUrl.trim();

    final product = PartnerProduct(
      id: 'prod-${DateTime.now().microsecondsSinceEpoch}',
      restaurantId: restaurantId,
      name: trimmedName,
      description: trimmedDescription,
      price: price,
      photoUrl: normalizedPhoto,
      isAvailable: isAvailable,
      source: ProductSource.api,
    );

    _productsByRestaurant
        .putIfAbsent(restaurantId, () => <PartnerProduct>[])
        .add(product);
    notifyListeners();

    // Persist to Supabase asynchronously — fire and forget.
    supabase.from('products').insert({
      'id': product.id,
      'restaurant_id': restaurantId,
      'name': product.name,
      'description': product.description,
      'price': product.price,
      'photo_url': product.photoUrl,
      'is_available': product.isAvailable,
    }).then((_) {
      debugPrint('RestaurantStore: product saved to Supabase');
      loadProductsFromSupabase();
    }).catchError((Object e) {
      debugPrint('RestaurantStore: product insert error => $e');
    });

    return product;
  }

  bool updatePartnerProduct({
    required String restaurantId,
    required String productId,
    String? name,
    String? description,
    double? price,
    String? photoUrl,
    bool? isAvailable,
  }) {
    final list = _productsByRestaurant[restaurantId];
    if (list == null) return false;

    final index = list.indexWhere((item) => item.id == productId);
    if (index == -1) return false;

    final current = list[index];

    final updated = current.copyWith(
      name: name?.trim().isEmpty == true ? current.name : name?.trim(),
      description: description?.trim().isEmpty == true
          ? current.description
          : description?.trim(),
      price: price,
      photoUrl: photoUrl?.trim().isEmpty == true
          ? current.photoUrl
          : photoUrl?.trim(),
      isAvailable: isAvailable,
    );

    list[index] = updated;
    notifyListeners();

    // Persist update to Supabase asynchronously.
    supabase.from('products').update({
      'name': updated.name,
      'description': updated.description,
      'price': updated.price,
      'photo_url': updated.photoUrl,
      'is_available': updated.isAvailable,
    }).eq('id', productId).then((_) {
      debugPrint('RestaurantStore: product updated in Supabase');
    }).catchError((e) {
      debugPrint('RestaurantStore: product update error => $e');
    });

    return true;
  }

  bool deletePartnerProduct({
    required String restaurantId,
    required String productId,
  }) {
    final list = _productsByRestaurant[restaurantId];
    if (list == null) return false;

    final initialLength = list.length;
    list.removeWhere((item) => item.id == productId);
    if (list.length == initialLength) return false;

    notifyListeners();

    // Persist deletion to Supabase asynchronously.
    supabase.from('products').delete().eq('id', productId).then((_) {
      debugPrint('RestaurantStore: product deleted from Supabase');
    }).catchError((e) {
      debugPrint('RestaurantStore: product delete error => $e');
    });

    return true;
  }

  // ─── External product sync ───────────────────────────────────────────────

  /// Upserts a list of externally-sourced products (API / scraping) for a
  /// given restaurant into Supabase, deduplicating by [name + restaurantId].
  /// Products already present (same name, case-insensitive) are skipped.
  Future<void> syncProductsFromExternalSource({
    required String restaurantId,
    required List<PartnerProduct> products,
  }) async {
    final existing = _productsByRestaurant[restaurantId] ?? const <PartnerProduct>[];
    final existingNames = existing.map((p) => p.name.toLowerCase()).toSet();

    final toInsert = <Map<String, dynamic>>[];
    final toAddLocally = <PartnerProduct>[];

    for (final product in products) {
      if (existingNames.contains(product.name.toLowerCase())) continue;

      final id = product.id.isEmpty
          ? 'ext-$restaurantId-${DateTime.now().microsecondsSinceEpoch}'
          : product.id;

      final newProduct = PartnerProduct(
        id: id,
        restaurantId: restaurantId,
        name: product.name,
        description: product.description,
        price: product.price,
        photoUrl: product.photoUrl,
        isAvailable: product.isAvailable,
        source: product.source == ProductSource.localSeed
            ? ProductSource.scraped
            : product.source,
      );

      toInsert.add({
        'id': id,
        'restaurant_id': restaurantId,
        'name': newProduct.name,
        'description': newProduct.description,
        'price': newProduct.price,
        'photo_url': newProduct.photoUrl,
        'is_available': newProduct.isAvailable,
      });
      toAddLocally.add(newProduct);
      existingNames.add(newProduct.name.toLowerCase()); // guard within batch
    }

    if (toInsert.isEmpty) return;

    try {
      await supabase.from('products').upsert(toInsert, onConflict: 'id');
      _productsByRestaurant
          .putIfAbsent(restaurantId, () => <PartnerProduct>[])
          .addAll(toAddLocally);
      notifyListeners();
      debugPrint(
          'RestaurantStore: synced ${toInsert.length} external products for $restaurantId');
    } catch (e) {
      debugPrint('RestaurantStore: syncProductsFromExternalSource error => $e');
    }
  }

  /// Returns true when [product] did not originate from the local seed data.
  bool isExternalProduct(PartnerProduct product) =>
      product.source != ProductSource.localSeed;

  /// Scrapes products for [restaurantId] from [source] (e.g. "continente",
  /// "pingodoce") and syncs them into Supabase via [syncProductsFromExternalSource].
  Future<void> loadScrapedProductsForStore(
    String restaurantId,
    String source,
  ) async {
    final scraper = ProductScraperService();
    final products = await scraper.scrapeProducts(source);
    if (products.isEmpty) return;
    await syncProductsFromExternalSource(
      restaurantId: restaurantId,
      products: products,
    );
  }

  // ─── Online / Offline toggle ─────────────────────────────────────────────

  Future<void> toggleRestaurantOnline(
      String restaurantId, bool isOnline) async {
    final index = _restaurants.indexWhere((r) => r.id == restaurantId);
    if (index != -1) {
      _restaurants[index] = _restaurants[index].copyWith(isOnline: isOnline);
      notifyListeners();
    }
    try {
      await supabase
          .from('restaurants')
          .update({'is_online': isOnline}).eq('id', restaurantId);
    } catch (e) {
      debugPrint('RestaurantStore: toggleRestaurantOnline error => $e');
    }
  }

  // ─── Order sync ───────────────────────────────────────────────────────────

  void syncPartnerOrders(List<OrderModel> orders) {
    final grouped = <String, Map<String, OrderModel>>{};
    final statusCache = <String, int>{};

    for (final order in orders) {
      if (!_isRestaurantPartnerOrder(order)) continue;
      if (!_shouldKeepOrder(order)) continue;

      final restaurant = restaurantByName(order.vendorName);
      if (restaurant == null) continue;

      final bucket = grouped.putIfAbsent(
        restaurant.id,
        () => <String, OrderModel>{},
      );
      bucket[order.id] = order;
      statusCache[order.id] = _fingerprintOrder(order);
    }

    final structureChanged = !_hasSameStructure(grouped);
    final statusChanged = !_hasSameStatusCache(statusCache);

    if (structureChanged || statusChanged) {
      _ordersByRestaurant
        ..clear()
        ..addEntries(
          grouped.entries.map(
            (entry) => MapEntry(
              entry.key,
              Map<String, OrderModel>.from(entry.value),
            ),
          ),
        );
      _orderStatusCache
        ..clear()
        ..addAll(statusCache);
      notifyListeners();
    }
  }

  // ─── Dispose ──────────────────────────────────────────────────────────────

  @override
  void dispose() {
    _restaurantsChannel?.unsubscribe();
    _productsChannel?.unsubscribe();
    super.dispose();
  }

  // ─── Private helpers ──────────────────────────────────────────────────────

  RestaurantModel _restaurantFromRecord(Map<String, dynamic> data) {
    final categoryStr = data['category'] as String? ?? 'restaurant';
    final category = BusinessCategory.values.firstWhere(
      (e) => e.name == categoryStr,
      orElse: () => BusinessCategory.restaurant,
    );
    return RestaurantModel(
      id: (data['id'] ?? '').toString(),
      name: data['name'] ?? '',
      address: data['address'] ?? '',
      phone: data['phone'] ?? '',
      email: data['email'] ?? '',
      photoUrl: data['photo_url'] ?? '',
      cuisineType: data['cuisine_type'] ?? '',
      isPartner: data['is_partner'] ?? true,
      category: category,
      isOnline: data['is_online'] ?? true,
      lat: (data['lat'] as num?)?.toDouble(),
      lng: (data['lng'] as num?)?.toDouble(),
    );
  }

  bool _isRestaurantPartnerOrder(OrderModel order) {
    return order.serviceType == OrderServiceType.restaurant &&
        order.isPartnerStore;
  }

  bool _shouldKeepOrder(OrderModel order) {
    return order.status.index <= OrderStatus.callingDriver.index;
  }

  bool _hasSameStructure(Map<String, Map<String, OrderModel>> next) {
    if (_ordersByRestaurant.length != next.length) return false;
    for (final entry in _ordersByRestaurant.entries) {
      final nextBucket = next[entry.key];
      if (nextBucket == null) return false;
      if (entry.value.length != nextBucket.length) return false;
      for (final orderId in entry.value.keys) {
        if (!nextBucket.containsKey(orderId)) return false;
      }
    }
    return true;
  }

  bool _hasSameStatusCache(Map<String, int> next) {
    if (_orderStatusCache.length != next.length) return false;
    for (final entry in _orderStatusCache.entries) {
      if (next[entry.key] != entry.value) return false;
    }
    return true;
  }

  int _fingerprintOrder(OrderModel order) {
    return Object.hash(
      order.status,
      order.assignedDriverId,
      order.currentDriverOfferId,
      order.driverOfferHistory.length,
      order.pickupWarningIssued,
    );
  }
}
