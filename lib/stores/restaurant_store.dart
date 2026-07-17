import 'dart:async';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/order_model.dart';
import '../models/partner_product.dart';
import '../models/product_variant.dart';
import '../models/restaurant_model.dart';
import '../services/foreground_service.dart';

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
          // B5 (2026-06-12): o load de produtos agora depende da lista de
          // restaurantes (filtra parceiros+restaurantes) — recarregar em
          // cadeia quando a 1ª tentativa correu sem sessão.
          loadRestaurantsFromSupabase().then((_) {
            if (_productsByRestaurant.isEmpty) {
              loadProductsFromSupabase();
            }
          });
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

  /// product_ids that have at least one required option group. The listing
  /// "+" opens the detail screen for these (to choose options) instead of
  /// adding directly. Loaded lightweight (ids only) in loadProductsFromSupabase.
  final Set<String> _requiredOptionProductIds = <String>{};
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

  // ─── Catálogo de mercados/lojas: full-load on-demand (B5 + hotfix 2026-06-12)
  // Arranque NÃO carrega os ~45k produtos (só parceiros + restaurantes). Ao
  // ABRIR um mercado/loja/farmácia carrega-se a loja INTEIRA on-demand
  // (1000/página) para `_productsByRestaurant` — assim os carrosséis por
  // categoria, a tab Categorias e o filtro por categoria voltam a ver TODAS as
  // categorias (modelo em-memória que sempre funcionou). Memória limitada: só
  // 1 mercado fica carregado de cada vez (eviction dos outros). Pesquisa
  // continua na DB (RPC search_products).
  //
  // Regressão corrigida: o B5 v1 paginava por 30 e os ecrãs agrupavam
  // categorias em memória sobre esse conjunto parcial → só aparecia 1
  // categoria e a tela de categoria ficava em branco (build 288). O full-load
  // ao abrir resolve sem perder o ganho de arranque.

  static const int _storePageSize = 1000; // Supabase: máx 1000 rows/query.
  final Map<String, bool> _storeLoading = {};
  final Map<String, bool> _storeFullyLoaded = {};

  bool storeProductsLoading(String restaurantId) =>
      _storeLoading[restaurantId] ?? false;

  bool storeFullyLoaded(String restaurantId) =>
      _storeFullyLoaded[restaurantId] ?? false;

  int storeLoadedCount(String restaurantId) =>
      _productsByRestaurant[restaurantId]?.length ?? 0;

  /// Carrega TODOS os produtos disponíveis de uma loja de mercado on-demand.
  /// Idempotente (flag _storeFullyLoaded). notifyListeners por página → os
  /// carrosséis preenchem progressivamente. Limita memória: ao abrir um
  /// mercado descarrega os outros mercados (parceiros/restaurantes do arranque
  /// NUNCA entram em _storeFullyLoaded → ficam sempre intactos).
  Future<void> loadFullStoreProducts(String restaurantId) async {
    if (restaurantId.isEmpty) return;
    if (_storeFullyLoaded[restaurantId] == true) return;
    if (_storeLoading[restaurantId] == true) return;

    // Eviction de outros mercados já carregados (mantém 1 loja de cada vez).
    for (final otherId in _storeFullyLoaded.keys.toList()) {
      if (otherId == restaurantId) continue;
      _productsByRestaurant.remove(otherId);
      _storeFullyLoaded.remove(otherId);
    }

    _storeLoading[restaurantId] = true;
    notifyListeners();
    try {
      final list = _productsByRestaurant.putIfAbsent(
          restaurantId, () => <PartnerProduct>[]);
      final seen = <String>{for (final e in list) e.id};
      int offset = list.length;
      while (true) {
        final List<dynamic> page = await supabase
            .from('products')
            .select(_productProjection)
            .eq('restaurant_id', restaurantId)
            .eq('is_available', true)
            .order('sort_order', ascending: true, nullsFirst: false)
            .order('id', ascending: true)
            .range(offset, offset + _storePageSize - 1);
        for (final record in page) {
          final product = _productFromRow(record as Map<String, dynamic>);
          if (product == null) continue;
          if (!seen.add(product.id)) continue; // dedupe O(1)
          list.add(product);
        }
        notifyListeners(); // carrosséis preenchem à medida que chegam páginas
        if (page.length < _storePageSize) break;
        offset += _storePageSize;
      }
      _storeFullyLoaded[restaurantId] = true;
    } catch (e) {
      debugPrint(
          'RestaurantStore: loadFullStoreProducts($restaurantId) error => $e');
    } finally {
      _storeLoading[restaurantId] = false;
      notifyListeners();
    }
  }

  // 2026-05-14 perf: projecção explícita evita transferir colunas grandes
  // não usadas (search_normalized, taxonomy_*, needs_review, ...).
  static const String _productProjection =
      'id,restaurant_id,name,description,price,price_low,photo_url,'
      'is_available,category,category_root,is_popular,is_on_sale,'
      'discount_price,allergens';

  /// B5 (2026-06-12): parse partilhado row→PartnerProduct (arranque +
  /// páginas lazy). Devolve null para rows sem restaurant_id.
  PartnerProduct? _productFromRow(Map<String, dynamic> data) {
    final restaurantId = (data['restaurant_id'] ?? '').toString();
    if (restaurantId.isEmpty) return null;

    final productId = (data['id'] ?? '').toString();
    // DB schema uses price_low/price_mid/price_premium; no single 'price'
    // or 'is_available' column. Use price_low as the displayed price.
    final price = double.tryParse(
          data['price_low']?.toString() ?? '',
        ) ??
        double.tryParse(data['price']?.toString() ?? '') ??
        0.0;
    final discountPrice = data['discount_price'] != null
        ? double.tryParse(data['discount_price'].toString())
        : null;
    // B6 (2026-06-12): alergénios UE 1169/2011 (text[] → List<String>).
    final allergens = (data['allergens'] as List?)
            ?.map((e) => e.toString())
            .toList() ??
        const <String>[];
    return PartnerProduct(
      id: productId,
      restaurantId: restaurantId,
      name: data['name'] ?? '',
      description: (data['description'] ?? '').toString(),
      price: price,
      photoUrl: data['photo_url'] ?? '',
      isAvailable: (data['is_available'] as bool?) ?? true,
      category: (data['category'] ?? '').toString(),
      categoryRoot: (data['category_root'] ?? '').toString(),
      isPopular: (data['is_popular'] as bool?) ?? false,
      isOnSale: (data['is_on_sale'] as bool?) ?? false,
      discountPrice: discountPrice,
      source: ProductSource.api,
      hasRequiredOptions: _requiredOptionProductIds.contains(productId),
      allergens: allergens,
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

  /// Checks for a restaurant owned by [userId] regardless of approval_status
  /// (pending/rejected included) — deliberately NOT merged into `_restaurants`
  /// (that list stays approved-only for client browsing). Used by
  /// PartnerEntryScreen to recognise an in-review signup after logout/login
  /// instead of restarting the wizard from zero.
  Future<String?> ownRestaurantApprovalStatus(String userId) async {
    try {
      // .limit(1) em vez de .maybeSingle(): se existirem linhas duplicadas
      // para o mesmo user_id (candidaturas antigas submetidas antes da
      // Edge Function register-partner passar a ser idempotente),
      // .maybeSingle() lança PGRST116 ("multiple rows") e o catch abaixo
      // devolvia null — reabrindo o wizard do zero em vez de reconhecer a
      // candidatura já em curso.
      final records = await supabase
          .from('restaurants')
          .select('approval_status')
          .eq('user_id', userId)
          .order('submitted_at', ascending: false)
          .limit(1);
      final record = (records as List).isEmpty ? null : records.first;
      return record?['approval_status'] as String?;
    } catch (e) {
      debugPrint('RestaurantStore: ownRestaurantApprovalStatus error => $e');
      return null;
    }
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
          .eq('is_active_admin', true)
          .eq('approval_status', 'approved');

      // Seed defaults only when the DB table is empty (first run).
      if (response.isEmpty) {
        await _seedDefaultRestaurants();
        response = await supabase
            .from('restaurants')
            .select()
            .eq('is_active_admin', true)
            .eq('approval_status', 'approved');
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

      // B5 (2026-06-12): o arranque deixou de puxar os ~45k produtos dos
      // mercados (45 requests + tudo em RAM). Aqui carregam-se APENAS os
      // catálogos pequenos que os ecrãs precisam completos em memória:
      // parceiros (gestão + menus) e restaurantes não-parceiros (menus
      // fast-food). Mercados/lojas/farmácia não-parceiros carregam a loja
      // inteira on-demand ao abrir (loadFullStoreProducts).
      final includeIds = _restaurants
          .where((r) =>
              r.isPartner || r.category == BusinessCategory.restaurant)
          .map((r) => r.id)
          .toList();
      if (includeIds.isEmpty) {
        debugPrint(
            'RestaurantStore: sem restaurantes carregados — produtos adiados');
        _subscribeProductsRealtime();
        return;
      }

      while (true) {
        final List<dynamic> page = await supabase
            .from('products')
            .select(_productProjection)
            .inFilter('restaurant_id', includeIds)
            // Ordem de exibição: mercados usam sort_order (sequência da fonte,
            // ex. Glovo); parceiros têm sort_order NULL -> caem no desempate por
            // id (determinístico, paginação estável). 2026-06-06.
            .order('sort_order', ascending: true, nullsFirst: false)
            .order('id', ascending: true)
            .range(offset, offset + pageSize - 1);
        allRecords.addAll(page);
        if (page.length < pageSize) break;
        offset += pageSize;
      }

      _productsByRestaurant.clear();
      _storeFullyLoaded.clear();
      _storeLoading.clear();

      // Which products have a required option group (is_required + min>=1).
      // Lightweight: fetch only the product_ids (paginated). The option items
      // themselves stay lazy-loaded by ProductDetailScreen. Drives the "+"
      // button: required-option products open detail instead of adding direct.
      _requiredOptionProductIds.clear();
      try {
        int reqOffset = 0;
        while (true) {
          final List<dynamic> reqPage = await supabase
              .from('product_option_groups')
              .select('product_id')
              .eq('is_required', true)
              .gte('min_choices', 1)
              .range(reqOffset, reqOffset + pageSize - 1);
          for (final r in reqPage) {
            final pid = ((r as Map)['product_id'] ?? '').toString();
            if (pid.isNotEmpty) _requiredOptionProductIds.add(pid);
          }
          if (reqPage.length < pageSize) break;
          reqOffset += pageSize;
        }
      } catch (e) {
        debugPrint('RestaurantStore: required-options flag load error => $e');
      }

      for (final record in allRecords) {
        final product = _productFromRow(record as Map<String, dynamic>);
        if (product == null) continue;
        _productsByRestaurant
            .putIfAbsent(product.restaurantId, () => <PartnerProduct>[])
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
            hasRequiredOptions: list[index].hasRequiredOptions,
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

    // user_ é o owner do restaurante (auth.uid()). Sem isto o RLS bloqueia
    // tudo o que o parceiro tenta fazer no seu próprio restaurante.
    final ownerUid = supabase.auth.currentUser?.id;
    if (ownerUid == null) {
      throw StateError('Sessão expirada — faz login novamente.');
    }

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
        'user_': ownerUid,
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
    String category = '',
    List<String> allergens = const [],
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
      category: category.trim(),
      source: ProductSource.api,
      allergens: allergens,
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
        // BUG 1 (2026-07-17): categoria declarada pelo parceiro no formulário
        // — sem isto o menu do parceiro cai todo em "Outros".
        'category': product.category,
        // B6: alergénios UE 1169/2011 (vazio = não declarado).
        'allergens': product.allergens,
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
    String? category,
    List<String>? allergens,
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
      category: category?.trim().isEmpty == true
          ? current.category
          : category?.trim(),
      allergens: allergens,
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
            'category': updated.category,
            'allergens': updated.allergens,
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
    // Sessão 2026-05-17 — foreground service: loja aberta = app sempre activa
    // para receber pedidos (padrão Glovo/Uber Eats partner).
    unawaited(_syncForegroundService(isOnline));
  }

  /// Liga foreground service quando loja vai Online; pára quando offline.
  /// Pede POST_NOTIFICATIONS (Android 13+) se ainda não concedido.
  Future<void> _syncForegroundService(bool online) async {
    try {
      if (online) {
        final granted =
            await BoraForegroundService.ensureNotificationPermission();
        if (!granted) {
          debugPrint(
              '[RestaurantStore] foreground notif perm denied — service não iniciado');
          return;
        }
        await BoraForegroundService.startPartner();
      } else {
        await BoraForegroundService.stop();
      }
    } catch (e) {
      debugPrint('[RestaurantStore] _syncForegroundService error: $e');
    }
  }

  // ─── Reservations opt-in toggle (BR §14.10) ─────────────────────────────
  Future<void> toggleReservationsEnabled(
      String restaurantId, bool enabled) async {
    final index = _restaurants.indexWhere((r) => r.id == restaurantId);
    final previous = index != -1 ? _restaurants[index].reservationsEnabled : null;
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
      // BUG 3 (2026-07-17) — reverter o optimistic update: sem isto o UI
      // mostra "ligado" mesmo quando a escrita na DB falhou (ex.: RLS por
      // sessão Supabase Auth ainda não estabelecida), e o valor volta a
      // "desligado" silenciosamente no próximo login.
      final revertIndex = _restaurants.indexWhere((r) => r.id == restaurantId);
      if (revertIndex != -1 && previous != null) {
        _restaurants[revertIndex] =
            _restaurants[revertIndex].copyWith(reservationsEnabled: previous);
        notifyListeners();
      }
    }
  }

  // ─── Takeaway opt-in toggle (BR §14.9) ──────────────────────────────────
  Future<void> toggleTakeawayEnabled(
      String restaurantId, bool enabled) async {
    final index = _restaurants.indexWhere((r) => r.id == restaurantId);
    final previousTakeaway =
        index != -1 ? _restaurants[index].takeawayEnabled : null;
    final previousCurbside =
        index != -1 ? _restaurants[index].curbsideEnabled : null;
    if (index != -1) {
      _restaurants[index] =
          _restaurants[index].copyWith(takeawayEnabled: enabled);
      // Curbside só faz sentido se takeaway estiver activo — desactivar
      // automaticamente para evitar estado inconsistente na UI cliente.
      if (!enabled) {
        _restaurants[index] =
            _restaurants[index].copyWith(curbsideEnabled: false);
      }
      notifyListeners();
    }
    try {
      final updates = <String, dynamic>{'takeaway_enabled': enabled};
      if (!enabled) updates['curbside_enabled'] = false;
      await supabase
          .from('restaurants')
          .update(updates)
          .eq('id', restaurantId);
    } catch (e) {
      debugPrint('RestaurantStore: toggleTakeawayEnabled error => $e');
      final revertIndex = _restaurants.indexWhere((r) => r.id == restaurantId);
      if (revertIndex != -1 && previousTakeaway != null) {
        _restaurants[revertIndex] = _restaurants[revertIndex].copyWith(
          takeawayEnabled: previousTakeaway,
          curbsideEnabled: previousCurbside ?? false,
        );
        notifyListeners();
      }
    }
  }

  // ─── Curbside opt-in toggle (BR §14.9b) ─────────────────────────────────
  /// Só efectivo se takeawayEnabled=true. UI desactiva o switch quando
  /// takeaway está off.
  Future<void> toggleCurbsideEnabled(
      String restaurantId, bool enabled) async {
    final index = _restaurants.indexWhere((r) => r.id == restaurantId);
    final previous = index != -1 ? _restaurants[index].curbsideEnabled : null;
    if (index != -1) {
      _restaurants[index] =
          _restaurants[index].copyWith(curbsideEnabled: enabled);
      notifyListeners();
    }
    try {
      await supabase
          .from('restaurants')
          .update({'curbside_enabled': enabled}).eq('id', restaurantId);
    } catch (e) {
      debugPrint('RestaurantStore: toggleCurbsideEnabled error => $e');
      final revertIndex = _restaurants.indexWhere((r) => r.id == restaurantId);
      if (revertIndex != -1 && previous != null) {
        _restaurants[revertIndex] =
            _restaurants[revertIndex].copyWith(curbsideEnabled: previous);
        notifyListeners();
      }
    }
  }

  // ─── Default prep minutes (BR §14.9c) ───────────────────────────────────
  /// Aceita 3-60 min. Valores fora desta janela são clamped.
  Future<void> setTakeawayDefaultPrepMinutes(
      String restaurantId, int minutes) async {
    final clamped = minutes.clamp(3, 60);
    final index = _restaurants.indexWhere((r) => r.id == restaurantId);
    if (index != -1) {
      _restaurants[index] = _restaurants[index]
          .copyWith(takeawayDefaultPrepMinutes: clamped);
      notifyListeners();
    }
    try {
      await supabase
          .from('restaurants')
          .update({'takeaway_default_prep_minutes': clamped})
          .eq('id', restaurantId);
    } catch (e) {
      debugPrint(
          'RestaurantStore: setTakeawayDefaultPrepMinutes error => $e');
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
        takeawayEnabled: old.takeawayEnabled,
        curbsideEnabled: old.curbsideEnabled,
        takeawayDefaultPrepMinutes: old.takeawayDefaultPrepMinutes,
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
      takeawayEnabled: data['takeaway_enabled'] as bool? ?? false,
      curbsideEnabled: data['curbside_enabled'] as bool? ?? false,
      takeawayDefaultPrepMinutes:
          (data['takeaway_default_prep_minutes'] as num?)?.toInt() ?? 15,
      businessHours: BusinessHours.fromJson(data['business_hours']),
      avgRating: (data['avg_rating'] as num?)?.toDouble(),
      ratingsCount: (data['ratings_count'] as num?)?.toInt() ?? 0,
      heroImageUrl: data['hero_image_url'] as String?,
    );
  }

  bool _isRestaurantPartnerOrder(OrderModel order) {
    // 2026-05-14 fix: takeaway tambem e' um pedido de partner-restaurant
    // (mesmo balcao, mesmo dashboard — apenas sem estafeta). Sem este OR,
    // pedidos com service_type='takeaway' eram silenciosamente excluidos
    // do bucket _ordersByRestaurant e o parceiro nao os via no dashboard.
    return (order.serviceType == OrderServiceType.restaurant ||
            order.serviceType == OrderServiceType.takeaway) &&
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
