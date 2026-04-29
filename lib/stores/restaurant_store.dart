import 'dart:async';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/order_model.dart';
import '../models/partner_product.dart';
import '../models/product_variant.dart';
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
    await loadVariantsFromSupabase();
  }

  final Map<String, List<PartnerProduct>> _productsByRestaurant = {};
  final Map<String, List<ProductVariant>> _variantsByProduct = {};

  final Map<String, Map<String, OrderModel>> _ordersByRestaurant = {};
  final Map<String, int> _orderStatusCache = {};

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

  List<ProductVariant> variantsForProduct(String productId) =>
      List.unmodifiable(
          _variantsByProduct[productId] ?? const <ProductVariant>[]);

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
            restaurant.isPartner && restaurant.name.toLowerCase() == normalized,
      );
    } catch (_) {
      return null;
    }
  }

  RestaurantModel? restaurantById(String? id) {
    if (id == null || id.isEmpty) return null;
    try {
      return restaurants.firstWhere((restaurant) => restaurant.id == id);
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
      // BUG 4 follow-up: hide admin-suspended partners from public reads.
      // Admin can still see suspended ones via admin_partners_screen which
      // queries `restaurants` directly without this filter.
      List<dynamic> response = await supabase
          .from('restaurants')
          .select()
          .eq('is_active_admin', true);

      // Seed defaults only when the DB table is empty (first run).
      if (response.isEmpty) {
        await _seedDefaultRestaurants();
        response = await supabase
            .from('restaurants')
            .select()
            .eq('is_active_admin', true);
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
    // Fire-and-forget: card badges can appear later without blocking.
    unawaited(_loadAverageRatings());
  }

  // ─── Average ratings cache (for restaurant cards) ───────────────────────
  final Map<String, double> _avgRatings = {};

  /// Returns the average rating (1.0–5.0) for a restaurant, or null if none.
  double? avgRatingFor(String restaurantId) => _avgRatings[restaurantId];

  Future<void> _loadAverageRatings() async {
    try {
      final rows = await supabase
          .from('ratings')
          .select('subject_id, rating')
          .eq('subject_type', 'restaurant');

      final buckets = <String, List<int>>{};
      for (final row in (rows as List)) {
        final id = (row['subject_id'] as String?)?.trim();
        final r = (row['rating'] as num?)?.toInt();
        if (id == null || id.isEmpty || r == null) continue;
        buckets.putIfAbsent(id, () => <int>[]).add(r);
      }

      _avgRatings.clear();
      buckets.forEach((id, list) {
        if (list.isEmpty) return;
        final avg = list.reduce((a, b) => a + b) / list.length;
        _avgRatings[id] = avg;
      });

      if (_avgRatings.isNotEmpty) notifyListeners();
      debugPrint(
          'RestaurantStore: loaded ratings for ${_avgRatings.length} restaurants');
    } catch (e) {
      debugPrint('RestaurantStore: _loadAverageRatings error => $e');
    }
  }

  /// Inserts default restaurants into Supabase.
  /// Called only when the restaurants table is empty (first run).
  /// No-op until seed data is provided — insert directly via Supabase dashboard.
  Future<void> _seedDefaultRestaurants() async {
    debugPrint('RestaurantStore: no seed data configured, skipping seed');
  }

  Future<void> loadProductsFromSupabase() async {
    try {
      // Supabase returns max 1000 rows per query.
      // Paginate until all products are fetched.
      const int pageSize = 1000;
      int offset = 0;
      final List<dynamic> allRecords = [];

      while (true) {
        final List<dynamic> page = await supabase
            .from('products')
            .select()
            .range(offset, offset + pageSize - 1);
        allRecords.addAll(page);
        if (page.length < pageSize) break;
        offset += pageSize;
      }

      _productsByRestaurant.clear();

      for (final record in allRecords) {
        final data = record as Map<String, dynamic>;

        final restaurantId = (data['restaurant_id'] ?? '').toString();
        if (restaurantId.isEmpty) continue;

        final productId = (data['id'] ?? '').toString();
        // DB schema uses price_low/price_mid/price_premium; no single 'price'
        // or 'is_available' column. Use price_low as the displayed price.
        final price = double.tryParse(
              data['price_low']?.toString() ?? '',
            ) ??
            double.tryParse(data['price']?.toString() ?? '') ??
            0.0;
        final description = (data['description'] ?? '').toString();
        final category = (data['category'] ?? '').toString();
        final categoryRoot = (data['category_root'] ?? '').toString();
        final isPopular = (data['is_popular'] as bool?) ?? false;
        final isOnSale = (data['is_on_sale'] as bool?) ?? false;
        final discountPrice = data['discount_price'] != null
            ? double.tryParse(data['discount_price'].toString())
            : null;
        final product = PartnerProduct(
          id: productId,
          restaurantId: restaurantId,
          name: data['name'] ?? '',
          description: description,
          price: price,
          photoUrl: data['photo_url'] ?? '',
          isAvailable: (data['is_available'] as bool?) ?? true,
          category: category,
          categoryRoot: categoryRoot,
          isPopular: isPopular,
          isOnSale: isOnSale,
          discountPrice: discountPrice,
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

  Future<void> loadVariantsFromSupabase() async {
    try {
      final List<dynamic> response =
          await supabase.from('product_variants').select();
      _variantsByProduct.clear();
      for (final record in response) {
        final data = record as Map<String, dynamic>;
        final variant = ProductVariant.fromSupabase(data);
        if (variant.productId.isEmpty) continue;
        _variantsByProduct
            .putIfAbsent(variant.productId, () => <ProductVariant>[])
            .add(variant);
      }
      notifyListeners();
      debugPrint(
          'RestaurantStore: loaded variants for ${_variantsByProduct.length} products');
    } catch (e) {
      debugPrint('RestaurantStore: loadVariantsFromSupabase error => $e');
    }
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
            description: (data['description'] ?? '').toString(),
            price: (data['price'] as num? ?? 0).toDouble(),
            photoUrl: data['photo_url'] ?? '',
            isAvailable: data['is_available'] ?? true,
            category: (data['category'] ?? '').toString(),
            categoryRoot: (data['category_root'] ?? '').toString(),
            isPopular: (data['is_popular'] as bool?) ?? false,
            isOnSale: (data['is_on_sale'] as bool?) ?? false,
            discountPrice: data['discount_price'] != null
                ? double.tryParse(data['discount_price'].toString())
                : null,
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
            category: (data['category'] ?? list[index].category).toString(),
            categoryRoot:
                (data['category_root'] ?? list[index].categoryRoot).toString(),
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
        'business_hours': restaurant.businessHours.toJson(),
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

  // addPartnerProduct inserts optimistically into local list then awaits
  // Supabase. On DB failure the local insert is rolled back and the error
  // is re-thrown so the calling screen can show feedback.
  Future<PartnerProduct> addPartnerProduct({
    required String restaurantId,
    required String name,
    required String description,
    required double price,
    required String photoUrl,
    required bool isAvailable,
  }) async {
    final trimmedName = name.trim();
    final trimmedDescription = description.trim();
    // Empty photoUrl → use empty string so UI fallback (initials) kicks in.
    // Never depend on via.placeholder.com (external CDN, unreliable in prod).
    final normalizedPhoto = photoUrl.trim();

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

    // Optimistic insert — UI reflects immediately.
    _productsByRestaurant
        .putIfAbsent(restaurantId, () => <PartnerProduct>[])
        .add(product);
    notifyListeners();

    try {
      await supabase.from('products').insert({
        'id': product.id,
        'restaurant_id': restaurantId,
        'name': product.name,
        'description': product.description,
        'price': product.price,
        'photo_url': product.photoUrl,
        'is_available': product.isAvailable,
      });
      debugPrint('RestaurantStore: product saved to Supabase');
    } catch (e) {
      // Rollback: remove the optimistically-inserted product.
      debugPrint('RestaurantStore: product insert error => $e — rolling back');
      _productsByRestaurant[restaurantId]
          ?.removeWhere((p) => p.id == product.id);
      notifyListeners();
      rethrow;
    }

    return product;
  }

  Future<bool> updatePartnerProduct({
    required String restaurantId,
    required String productId,
    String? name,
    String? description,
    double? price,
    String? photoUrl,
    bool? isAvailable,
  }) async {
    final list = _productsByRestaurant[restaurantId];
    if (list == null) return false;

    final index = list.indexWhere((item) => item.id == productId);
    if (index == -1) return false;

    final current = list[index];
    final previous = current; // snapshot for rollback

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

    // Optimistic update.
    list[index] = updated;
    notifyListeners();

    try {
      await supabase
          .from('products')
          .update({
            'name': updated.name,
            'description': updated.description,
            'price': updated.price,
            'photo_url': updated.photoUrl,
            'is_available': updated.isAvailable,
          })
          .eq('id', productId);
      debugPrint('RestaurantStore: product updated in Supabase');
    } catch (e) {
      // Rollback to previous state.
      debugPrint('RestaurantStore: product update error => $e — rolling back');
      list[index] = previous;
      notifyListeners();
      return false;
    }

    return true;
  }

  Future<bool> deletePartnerProduct({
    required String restaurantId,
    required String productId,
  }) async {
    final list = _productsByRestaurant[restaurantId];
    if (list == null) return false;

    // Snapshot for rollback before mutation.
    final backup = List<PartnerProduct>.from(list);
    list.removeWhere((item) => item.id == productId);
    if (list.length == backup.length) return false; // not found

    // Optimistic removal.
    notifyListeners();

    try {
      await supabase.from('products').delete().eq('id', productId);
      debugPrint('RestaurantStore: product deleted from Supabase');
    } catch (e) {
      // Rollback: restore the full list.
      debugPrint('RestaurantStore: product delete error => $e — rolling back');
      _productsByRestaurant[restaurantId] = backup;
      notifyListeners();
      return false;
    }

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

  // ─── Reservations opt-in toggle (BR §14.10) ─────────────────────────────
  Future<void> toggleReservationsEnabled(
      String restaurantId, bool enabled) async {
    final index = _restaurants.indexWhere((r) => r.id == restaurantId);
    if (index != -1) {
      _restaurants[index] =
          _restaurants[index].copyWith(reservationsEnabled: enabled);
      notifyListeners();
    }
    try {
      await supabase
          .from('restaurants')
          .update({'reservations_enabled': enabled}).eq('id', restaurantId);
    } catch (e) {
      debugPrint('RestaurantStore: toggleReservationsEnabled error => $e');
    }
  }

  // ─── Business hours ──────────────────────────────────────────────────────
  Future<void> updateBusinessHours(
      String restaurantId, BusinessHours hours) async {
    final index = _restaurants.indexWhere((r) => r.id == restaurantId);
    if (index != -1) {
      _restaurants[index] =
          _restaurants[index].copyWith(businessHours: hours);
      notifyListeners();
    }
    try {
      await supabase
          .from('restaurants')
          .update({'business_hours': hours.toJson()}).eq('id', restaurantId);
    } catch (e) {
      debugPrint('RestaurantStore: updateBusinessHours error => $e');
    }
  }

  // ─── BR §6.7 — Partner open/closed status (rich) ──────────────────────────
  /// Calls public.is_partner_open(restaurant_id, NOW()). Returns the JSONB
  /// payload `{is_open, override_active, closes_in_minutes, opens_at}`.
  /// Returns null on error so callers can fall back to client-side
  /// `RestaurantModel.isOpenNow()`.
  Future<Map<String, dynamic>?> fetchPartnerOpenStatus(String restaurantId) async {
    try {
      final res = await supabase.rpc('is_partner_open', params: {
        'p_restaurant_id': restaurantId,
        'p_at': DateTime.now().toUtc().toIso8601String(),
      });
      if (res is Map) return Map<String, dynamic>.from(res);
      if (res is bool) return {'is_open': res};
      return null;
    } catch (e) {
      debugPrint('RestaurantStore: fetchPartnerOpenStatus error => $e');
      return null;
    }
  }

  /// Admin RPC: force-close or force-open a partner.
  Future<Map<String, dynamic>> adminSetPartnerOverride({
    required String restaurantId,
    required String state, // 'open' | 'closed'
    required String reason,
    DateTime? endsAt,
  }) async {
    final res = await supabase.rpc('admin_set_partner_override', params: {
      'p_restaurant_id': restaurantId,
      'p_state': state,
      'p_reason': reason,
      'p_ends_at': endsAt?.toUtc().toIso8601String(),
    });
    return Map<String, dynamic>.from(res as Map);
  }

  Future<Map<String, dynamic>> adminClearPartnerOverride(
      String restaurantId) async {
    final res = await supabase.rpc('admin_clear_partner_override',
        params: {'p_restaurant_id': restaurantId});
    return Map<String, dynamic>.from(res as Map);
  }

  Future<Map<String, dynamic>> adminUpdatePartnerHours({
    required String restaurantId,
    required BusinessHours hours,
  }) async {
    final res = await supabase.rpc('admin_update_partner_hours', params: {
      'p_restaurant_id': restaurantId,
      'p_hours': hours.toJson(),
    });
    // Update local cache.
    final index = _restaurants.indexWhere((r) => r.id == restaurantId);
    if (index != -1) {
      _restaurants[index] = _restaurants[index].copyWith(businessHours: hours);
      notifyListeners();
    }
    return Map<String, dynamic>.from(res as Map);
  }

  /// T15 — Admin updates partner identity fields. Pass null for fields you
  /// don't want to change. Returns audit diff in the response.
  Future<Map<String, dynamic>> adminUpdatePartnerData({
    required String restaurantId,
    String? name,
    String? address,
    String? category, // 'restaurant' | 'supermarket' | 'store' | 'pharmacy'
    String? phone,
  }) async {
    final res = await supabase.rpc('admin_update_partner_data', params: {
      'p_restaurant_id': restaurantId,
      'p_name': name,
      'p_address': address,
      'p_category': category,
      'p_phone': phone,
    });
    final result = Map<String, dynamic>.from(res as Map);
    // Update local cache if any field changed.
    final index = _restaurants.indexWhere((r) => r.id == restaurantId);
    if (index != -1 && result['no_changes'] != true) {
      final old = _restaurants[index];
      _restaurants[index] = RestaurantModel(
        id: old.id,
        name: name ?? old.name,
        phone: phone ?? old.phone,
        address: address ?? old.address,
        email: old.email,
        photoUrl: old.photoUrl,
        cuisineType: old.cuisineType,
        isPartner: old.isPartner,
        category: category != null
            ? BusinessCategory.values.firstWhere((e) => e.name == category,
                orElse: () => old.category)
            : old.category,
        isOnline: old.isOnline,
        lat: old.lat,
        lng: old.lng,
        reservationsEnabled: old.reservationsEnabled,
        businessHours: old.businessHours,
      );
      notifyListeners();
    }
    return result;
  }

  Future<Map<String, dynamic>> adminSetPartnerSpecialDate({
    required String restaurantId,
    required DateTime date,
    required Map<String, dynamic> dayHours,
  }) async {
    final dateStr = '${date.year.toString().padLeft(4, '0')}-'
        '${date.month.toString().padLeft(2, '0')}-'
        '${date.day.toString().padLeft(2, '0')}';
    final res = await supabase.rpc('admin_set_partner_special_date', params: {
      'p_restaurant_id': restaurantId,
      'p_date': dateStr,
      'p_day_hours': dayHours,
    });
    return Map<String, dynamic>.from(res as Map);
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
      reservationsEnabled: data['reservations_enabled'] as bool? ?? false,
      businessHours: BusinessHours.fromJson(data['business_hours']),
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
