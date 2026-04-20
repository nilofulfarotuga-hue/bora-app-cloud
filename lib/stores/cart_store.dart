import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/cart_item.dart';
import '../models/order_model.dart';
import '../config/business_rules.dart' show BRTokens;
import '../services/pricing_service.dart';
import 'order_store.dart';

class CartStore extends ChangeNotifier {
  static const _kPrefsKey = 'bora_cart_v1';

  final List<CartItem> _items = [];

  OrderServiceType _serviceType = OrderServiceType.restaurant;
  bool _isPartnerStore = true;
  String? _vendorName;
  String? _pickupStreet;
  String? _pickupCity;
  String? _pickupPostalCode;
  String _dropoffStreet = "";
  String _dropoffCity = "";
  String _dropoffPostalCode = "";
  double _distanceKm = PricingService.defaultDistanceKm;
  LatLng? _pickupLocation;
  LatLng? _deliveryLocation;
  bool _apartmentDelivery = false;
  bool _requiresCar = false;

  CartStore() {
    _loadCart();
  }

  // ── Persistence ──────────────────────────────────────────────────────────

  Future<void> _saveCart() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final data = jsonEncode({
        'items': _items.map((i) => i.toJson()).toList(),
        'serviceType': _serviceType.name,
        'isPartnerStore': _isPartnerStore,
        'vendorName': _vendorName,
        'pickupStreet': _pickupStreet,
        'pickupCity': _pickupCity,
        'pickupPostalCode': _pickupPostalCode,
        'dropoffStreet': _dropoffStreet,
        'dropoffCity': _dropoffCity,
        'dropoffPostalCode': _dropoffPostalCode,
        'pickupLat': _pickupLocation?.latitude,
        'pickupLng': _pickupLocation?.longitude,
        'deliveryLat': _deliveryLocation?.latitude,
        'deliveryLng': _deliveryLocation?.longitude,
        'distanceKm': _distanceKm,
        'apartmentDelivery': _apartmentDelivery,
      });
      await prefs.setString(_kPrefsKey, data);
    } catch (e) {
      debugPrint('CartStore._saveCart error: $e');
    }
  }

  Future<void> _loadCart() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_kPrefsKey);
      if (raw == null) return;
      final map = jsonDecode(raw) as Map<String, dynamic>;
      final itemsJson = map['items'] as List<dynamic>? ?? [];
      _items.clear();
      for (final j in itemsJson) {
        _items.add(CartItem.fromJson(j as Map<String, dynamic>));
      }
      _serviceType = OrderServiceType.values.firstWhere(
        (e) => e.name == map['serviceType'],
        orElse: () => OrderServiceType.restaurant,
      );
      _isPartnerStore = map['isPartnerStore'] as bool? ?? true;
      _vendorName = map['vendorName'] as String?;
      _pickupStreet = map['pickupStreet'] as String?;
      _pickupCity = map['pickupCity'] as String?;
      _pickupPostalCode = map['pickupPostalCode'] as String?;
      _dropoffStreet = map['dropoffStreet'] as String? ?? '';
      _dropoffCity = map['dropoffCity'] as String? ?? '';
      _dropoffPostalCode = map['dropoffPostalCode'] as String? ?? '';
      final pickupLat = map['pickupLat'] as double?;
      final pickupLng = map['pickupLng'] as double?;
      if (pickupLat != null && pickupLng != null) {
        _pickupLocation = LatLng(pickupLat, pickupLng);
      }
      final deliveryLat = map['deliveryLat'] as double?;
      final deliveryLng = map['deliveryLng'] as double?;
      if (deliveryLat != null && deliveryLng != null) {
        _deliveryLocation = LatLng(deliveryLat, deliveryLng);
      }
      _distanceKm = (map['distanceKm'] as num?)?.toDouble() ??
          PricingService.defaultDistanceKm;
      _apartmentDelivery = map['apartmentDelivery'] as bool? ?? false;
      notifyListeners();
    } catch (e) {
      debugPrint('CartStore._loadCart error: $e');
    }
  }

  // ── Getters ───────────────────────────────────────────────────────────────

  List<CartItem> get items => List.unmodifiable(_items);

  int get totalItems => _items.fold(0, (sum, item) => sum + item.quantity);

  double get subtotal =>
      _items.fold(0, (sum, item) => sum + item.price * item.quantity);

  double get total => subtotal;

  OrderServiceType get serviceType => _serviceType;

  bool get isPartnerStore => _isPartnerStore;

  bool get apartmentDelivery => _apartmentDelivery;

  double get distanceKm => _distanceKm;

  LatLng? get pickupLocation => _pickupLocation;

  LatLng? get deliveryLocation => _deliveryLocation;

  String? get vendorName => _vendorName;

  String? get pickupStreet => _pickupStreet;
  String? get pickupCity => _pickupCity;
  String? get pickupPostalCode => _pickupPostalCode;
  String get dropoffStreet => _dropoffStreet;
  String get dropoffCity => _dropoffCity;
  String get dropoffPostalCode => _dropoffPostalCode;

  // ── FIX: Expose whether the cart has a valid pickup location so that
  // UI screens can disable checkout when coordinates are missing.
  bool get hasValidPickupLocation => _pickupLocation != null;

  OrderPricingBreakdown get pricingBreakdown =>
      PricingService.calculateBreakdown(
        serviceType: _serviceType,
        subtotal: subtotal,
        distanceKm: _distanceKm,
        isPartnerStore: _isPartnerStore,
        apartmentDelivery: _apartmentDelivery,
      );

  // Takeaway flag for partner restaurants (BR §14.9).
  bool _isTakeaway = false;
  bool get isTakeaway => _isTakeaway;
  void setTakeaway(bool v) {
    _isTakeaway = v;
    notifyListeners();
  }

  // Client gratuity at checkout (BR §4.5). Split 80/20 handled post-delivery.
  int _tipCents = 0;
  int get tipCents => _tipCents;
  double get tipEur => _tipCents / 100.0;
  void setTipCents(int v) {
    _tipCents = v < 0 ? 0 : v;
    notifyListeners();
  }

  // Optional photos for sendPackage / carryGroceries (BR §7.5/7.6).
  String? _packagePhotoUrl;
  String? _groceriesPhotoUrl;
  String? get packagePhotoUrl => _packagePhotoUrl;
  String? get groceriesPhotoUrl => _groceriesPhotoUrl;
  void setPackagePhotoUrl(String? url) {
    _packagePhotoUrl = url;
    notifyListeners();
  }

  void setGroceriesPhotoUrl(String? url) {
    _groceriesPhotoUrl = url;
    notifyListeners();
  }

  void configureSession({
    required OrderServiceType serviceType,
    bool isPartnerStore = true,
    bool requiresCar = false,
    String? vendorName,
    String? pickupStreet,
    String? pickupCity,
    String? pickupPostalCode,
    double? distanceKm,
    LatLng? pickupLocation,
    LatLng? deliveryLocation,
    String? dropoffStreet,
    String? dropoffCity,
    String? dropoffPostalCode,
  }) {
    final isSameContext = _serviceType == serviceType &&
        _vendorName == vendorName &&
        _isPartnerStore == isPartnerStore;

    if (_items.isNotEmpty && !isSameContext) {
      _items.clear();
      _saveCart();
    }

    _serviceType = serviceType;
    _isPartnerStore = isPartnerStore;
    _requiresCar = requiresCar;
    _vendorName = vendorName;
    _pickupStreet = pickupStreet;
    _pickupCity = pickupCity;
    _pickupPostalCode = pickupPostalCode;
    if (dropoffStreet != null) _dropoffStreet = dropoffStreet;
    if (dropoffCity != null) _dropoffCity = dropoffCity;
    if (dropoffPostalCode != null) _dropoffPostalCode = dropoffPostalCode;
    _pickupLocation = pickupLocation;
    if (deliveryLocation != null) {
      _deliveryLocation = deliveryLocation;
    }

    _apartmentDelivery = false;

    // ── FIX: Log when pickup is null so developers can trace the issue
    // immediately in the console instead of discovering it at order time.
    if (_pickupLocation == null) {
      debugPrint(
        'CartStore.configureSession: WARNING — pickupLocation is null '
        'for vendor "$vendorName". Distance will use default fallback.',
      );
    }

    if (distanceKm != null) {
      _distanceKm = distanceKm;
    } else {
      _recalculateDistance();
    }

    notifyListeners();
  }

  void updateDeliveryAddress({
    required String street,
    required String city,
    required String postalCode,
    LatLng? location,
  }) {
    _dropoffStreet = street;
    _dropoffCity = city;
    _dropoffPostalCode = postalCode;
    if (location != null) {
      _deliveryLocation = location;
    }
    _recalculateDistance();
    notifyListeners();
  }

  void setApartmentDelivery(bool value) {
    if (_apartmentDelivery == value) return;
    _apartmentDelivery = value;
    notifyListeners();
  }

  void _recalculateDistance() {
    if (_pickupLocation != null && _deliveryLocation != null) {
      final distance = const Distance().as(
        LengthUnit.Kilometer,
        _pickupLocation!,
        _deliveryLocation!,
      );
      if (distance.isFinite && distance > 0) {
        _distanceKm = distance;
      } else {
        _distanceKm = PricingService.defaultDistanceKm;
      }
      return;
    }
    _distanceKm = PricingService.defaultDistanceKm;
  }

  void addItem(CartItem item) {
    // Apply the 15% non-partner markup once, at the point of adding to cart.
    // PricingService.calculateBreakdown will NOT add it again.
    final effectivePrice =
        PricingService.applyMarkup(item.price, _isPartnerStore);
    final cartItem = effectivePrice != item.price
        ? CartItem(
            name: item.name, price: effectivePrice, quantity: item.quantity)
        : item;

    final index = _items.indexWhere((i) => i.name == cartItem.name);

    if (index >= 0) {
      _items[index].quantity++;
    } else {
      _items.add(cartItem);
    }

    notifyListeners();
    _saveCart();
  }

  void removeItem(CartItem item) {
    _items.removeWhere((i) => i.name == item.name);
    notifyListeners();
    _saveCart();
  }

  void increaseQuantity(CartItem item) {
    final index = _items.indexWhere((i) => i.name == item.name);
    if (index >= 0) {
      _items[index].quantity++;
      notifyListeners();
      _saveCart();
    }
  }

  void decreaseQuantity(CartItem item) {
    final index = _items.indexWhere((i) => i.name == item.name);
    if (index >= 0) {
      if (_items[index].quantity <= 1) {
        _items.removeAt(index);
      } else {
        _items[index].quantity--;
      }
      notifyListeners();
      _saveCart();
    }
  }

  void clearCart() {
    _items.clear();
    _apartmentDelivery = false;
    notifyListeners();
    _saveCart();
  }

  Future<bool> finishOrder(
    OrderStore orderStore, {
    required PaymentMethod paymentMethod,
    PaymentStatus paymentStatus = PaymentStatus.pending,
    String? paymentIntentId,
    String? notes,
    String? clientPhone,
    String? customerName,
    // Tokens applied as a discount at checkout. Stored for future consumption
    // phase (FIFO) — not yet deducted from bora_tokens table.
    int tokensUsed = 0,
  }) async {
    // Items are required for shopping-type orders; logistics orders (carry
    // groceries, send package) have no cart items by design.
    final isShoppingOrder = _serviceType == OrderServiceType.restaurant ||
        _serviceType == OrderServiceType.storeShopping;
    if (isShoppingOrder && _items.isEmpty) return false;

    // ── FIX: Block order creation when pickup coordinates are missing.
    // Previously, null pickupLocation silently passed through, causing:
    //   - MapsService skipped (no origin to calculate from)
    //   - distance stuck at default ~1.0 km
    //   - driver map showing two pins at the same location
    //   - incorrect pricing
    // Now we fail explicitly so the UI can show a clear error.
    if (_pickupLocation == null) {
      debugPrint(
        'CartStore.finishOrder: BLOCKED — pickupLocation is null for '
        'vendor "$_vendorName". Cannot create order without pickup coords.',
      );
      return false;
    }

    if (_deliveryLocation == null) {
      debugPrint(
        'CartStore.finishOrder: BLOCKED — deliveryLocation is null. '
        'User must define a delivery address before placing an order.',
      );
      return false;
    }

    if (_dropoffStreet.isEmpty) {
      debugPrint('CartStore.finishOrder: BLOCKED — dropoffStreet is empty.');
      return false;
    }

    final breakdown = pricingBreakdown;

    final success = await orderStore.createOrder(
      serviceType: _serviceType,
      itemsSubtotal: breakdown.subtotal,
      destination: _deliveryLocation!,
      paymentMethod: paymentMethod,
      paymentStatus: paymentStatus,
      paymentIntentId: paymentIntentId,
      items: _items
          .map(
            (item) => CartItem(
              name: item.name,
              price: item.price,
              quantity: item.quantity,
            ),
          )
          .toList(),
      pickupLocation: _pickupLocation,
      distanceKm: breakdown.distanceKm,
      isPartnerStore: _isPartnerStore,
      requiresCar: _requiresCar,
      vendorName: _vendorName,
      pickupAddress: _pickupStreet ?? _vendorName,
      pickupStreet: _pickupStreet,
      pickupCity: _pickupCity,
      pickupPostalCode: _pickupPostalCode,
      dropoffAddress:
          [_dropoffStreet, _dropoffCity].where((s) => s.isNotEmpty).join(', '),
      dropoffStreet: _dropoffStreet,
      dropoffCity: _dropoffCity,
      dropoffPostalCode: _dropoffPostalCode,
      customerNotes: notes,
      clientPhone: clientPhone,
      customerName: customerName,
      apartmentDelivery: _apartmentDelivery,
      tokenDiscountEur: tokensUsed * BRTokens.TOKEN_VALUE_EUR,
      packagePhotoUrl: _packagePhotoUrl,
      groceriesPhotoUrl: _groceriesPhotoUrl,
      isTakeaway: _isTakeaway,
      tipCents: _tipCents,
    );

    if (!success) return false;
    _packagePhotoUrl = null;
    _groceriesPhotoUrl = null;
    _isTakeaway = false;
    _tipCents = 0;
    clearCart();
    return true;
  }
}
