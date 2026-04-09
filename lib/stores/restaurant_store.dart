import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/order_model.dart';
import '../models/partner_product.dart';
import '../models/restaurant_model.dart';

class RestaurantStore extends ChangeNotifier {
  final supabase = Supabase.instance.client;

  // Single source of truth — populated only from Supabase.
  final List<RestaurantModel> _restaurants = [];

  RealtimeChannel? _restaurantsChannel;
  RealtimeChannel? _productsChannel;

  RestaurantStore() {
    _init();
    // Reload restaurants whenever a Supabase auth session becomes active.
    // This handles the case where _init() runs before the anonymous session
    // is established (RLS requires auth.uid() IS NOT NULL for SELECT).
    supabase.auth.onAuthStateChange.listen((data) {
      if (data.event == AuthChangeEvent.signedIn ||
          data.event == AuthChangeEvent.tokenRefreshed) {
        if (_restaurants.isEmpty) {
          loadRestaurantsFromSupabase();
        }
      }
    });
  }

  /// Sequences restaurant load first, then product load, to satisfy the FK
  /// constraint when seeding both tables on first run.
  /// Scraping runs in the background after the core load completes.
  Future<void> _init() async {
    await loadRestaurantsFromSupabase();
    await loadProductsFromSupabase();
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
      'address': 'Av. de Berna 12',
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
      'address': 'Praça Martim Moniz 2',
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
      'address': 'Av. Fontes Pereira de Melo 5',
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
      'address': 'R. Joaquim António de Aguiar 16',
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
      'address': 'Av. João XXI 50',
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
      'address': 'Centro Colombo, Av. Lusíada',
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
      'address': 'Rua Capitão Renato Baptista 18',
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
      'address': 'Av. Infante D. Henrique 333',
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
    {
      'id': 'market-auchan',
      'name': 'Auchan',
      'phone': '210000105',
      'address': 'Av. do Brasil 101',
      'email': 'contacto@auchan.pt',
      'photo_url': 'https://via.placeholder.com/240x140.png?text=Auchan',
      'cuisine_type': 'Supermercado',
      'is_partner': false,
      'category': 'supermarket',
      'is_online': true,
      'lat': 38.7480,
      'lng': -9.1540,
    },
    // ── Non-partner pharmacy ─────────────────────────────────────────────────
    {
      'id': 'pharmacy-central',
      'name': 'Farmácia Central',
      'phone': '210000301',
      'address': 'Rossio 28',
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
      'address': 'Rua Augusta 150',
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

  /// Inserts default restaurants into Supabase.
  /// Called only when the restaurants table is empty (first run).
  Future<void> _seedDefaultRestaurants() async {
    try {
      await supabase.from('restaurants').insert(_kDefaultRestaurants);
      debugPrint(
          'RestaurantStore: seeded ${_kDefaultRestaurants.length} restaurants');
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
          source: ProductSource.api,
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
