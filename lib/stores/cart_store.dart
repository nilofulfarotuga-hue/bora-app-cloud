import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';

import '../models/cart_item.dart';
import '../models/order_model.dart';
import '../services/pricing_service.dart';
import '../stores/order_store.dart';



class CartStore extends ChangeNotifier {
  static const LatLng _defaultCustomerLocation = LatLng(38.7223, -9.1393);

  final List<CartItem> _items = [];

    OrderServiceType _serviceType = OrderServiceType.restaurant;
  bool _isPartnerStore = true;
  String? _vendorName;
  String? _pickupStreet;
  String? _pickupCity;
  String? _pickupPostalCode;
  String _dropoffStreet = "Rua Augusta";
  String _dropoffCity = "Lisboa";
  String _dropoffPostalCode = "1100-053";
  double _distanceKm = PricingService.defaultDistanceKm;
    LatLng? _pickupLocation;
  LatLng _deliveryLocation = _defaultCustomerLocation;
  bool _apartmentDelivery = false;

  List<CartItem> get items => List.unmodifiable(_items);


  double get subtotal =>
      _items.fold(0, (sum, item) => sum + item.price * item.quantity);

  double get total => subtotal;

  OrderServiceType get serviceType => _serviceType;

  bool get isPartnerStore => _isPartnerStore;

  bool get apartmentDelivery => _apartmentDelivery;

  double get distanceKm => _distanceKm;

  LatLng? get pickupLocation => _pickupLocation;

  LatLng get deliveryLocation => _deliveryLocation;

  String? get vendorName => _vendorName;

  String? get pickupStreet => _pickupStreet;
  String? get pickupCity => _pickupCity;
  String? get pickupPostalCode => _pickupPostalCode;
  String get dropoffStreet => _dropoffStreet;
  String get dropoffCity => _dropoffCity;
  String get dropoffPostalCode => _dropoffPostalCode;

  OrderPricingBreakdown get pricingBreakdown => PricingService.calculateBreakdown(
        serviceType: _serviceType,
        subtotal: subtotal,
        distanceKm: _distanceKm,
        isPartnerStore: _isPartnerStore,
        apartmentDelivery: _apartmentDelivery,
      );


  void configureSession({
    required OrderServiceType serviceType,
    bool isPartnerStore = true,
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
    }

    _serviceType = serviceType;
    _isPartnerStore = isPartnerStore;
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

    if (_pickupLocation != null) {
      final distance = const Distance().as(
        LengthUnit.Kilometer,
        _pickupLocation!,
        _deliveryLocation,
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
    final effectivePrice = PricingService.applyMarkup(item.price, _isPartnerStore);
    final cartItem = effectivePrice != item.price
        ? CartItem(name: item.name, price: effectivePrice, quantity: item.quantity)
        : item;

    final index = _items.indexWhere((i) => i.name == cartItem.name);

    if (index >= 0) {
      _items[index].quantity++;
    } else {
      _items.add(cartItem);
    }

    notifyListeners();
  }

    void clearCart() {
    _items.clear();
    _apartmentDelivery = false;
    notifyListeners();
  }

  Future<bool> finishOrder(
    OrderStore orderStore, {
    required PaymentMethod paymentMethod,
    PaymentStatus paymentStatus = PaymentStatus.pending,
    String? paymentIntentId,
    String? notes,
    String? clientPhone,
    String? customerName,
  }) async {
    if (_items.isEmpty) return false;

    final breakdown = pricingBreakdown;

    final success = await orderStore.createOrder(
      serviceType: _serviceType,
      itemsSubtotal: breakdown.subtotal,
      destination: _deliveryLocation,
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
      vendorName: _vendorName,
      pickupAddress: _pickupStreet ?? _vendorName,
      pickupStreet: _pickupStreet,
      pickupCity: _pickupCity,
      pickupPostalCode: _pickupPostalCode,
      dropoffAddress: [_dropoffStreet, _dropoffCity]
          .where((s) => s.isNotEmpty)
          .join(', '),
      dropoffStreet: _dropoffStreet,
      dropoffCity: _dropoffCity,
      dropoffPostalCode: _dropoffPostalCode,
      customerNotes: notes,
      clientPhone: clientPhone,
      customerName: customerName,
      apartmentDelivery: _apartmentDelivery,
    );

    if (!success) return false;
    clearCart();
    return true;
  }
}