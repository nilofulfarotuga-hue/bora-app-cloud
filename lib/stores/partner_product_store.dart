import 'package:flutter/foundation.dart';

import '../models/partner_product.dart';
import '../models/restaurant_model.dart';
import 'restaurant_store.dart';

class PartnerProductStore extends ChangeNotifier {
  PartnerProductStore();

  RestaurantStore? _restaurantStore;
  RestaurantModel? _selectedRestaurant;

  RestaurantModel? get selectedRestaurant => _selectedRestaurant;

  List<PartnerProduct> get selectedRestaurantProducts {
    final restaurant = _selectedRestaurant;
    if (restaurant == null) {
      return const [];
    }
    return productsForRestaurant(restaurant.id);
  }

  void updateRestaurantStore(RestaurantStore store) {
    _restaurantStore = store;
    notifyListeners();
  }

  void selectRestaurant(RestaurantModel restaurant) {
    if (_selectedRestaurant?.id == restaurant.id) {
      return;
    }
    _selectedRestaurant = restaurant;
    notifyListeners();
  }

  void clearSelectedRestaurant() {
    if (_selectedRestaurant == null) {
      return;
    }
    _selectedRestaurant = null;
    notifyListeners();
  }

  List<PartnerProduct> productsForRestaurant(String restaurantId) {
    final store = _restaurantStore;
    if (store == null) {
      return const [];
    }
    return store.partnerProductsForRestaurant(restaurantId);
  }

  PartnerProduct addProduct({
    required String restaurantId,
    required String name,
    required String description,
    required double price,
    required String photoUrl,
    required bool isAvailable,
  }) {
    final store = _restaurantStore;
    if (store == null) {
      throw StateError('Restaurant store is not attached to partner store.');
    }
    final product = store.addPartnerProduct(
      restaurantId: restaurantId,
      name: name,
      description: description,
      price: price,
      photoUrl: photoUrl,
      isAvailable: isAvailable,
    );
    notifyListeners();
    return product;
  }

  bool updateProduct({
    required String restaurantId,
    required String productId,
    String? name,
    String? description,
    double? price,
    String? photoUrl,
    bool? isAvailable,
  }) {
    final store = _restaurantStore;
    if (store == null) {
      return false;
    }
    final updated = store.updatePartnerProduct(
      restaurantId: restaurantId,
      productId: productId,
      name: name,
      description: description,
      price: price,
      photoUrl: photoUrl,
      isAvailable: isAvailable,
    );
    if (updated) {
      notifyListeners();
    }
    return updated;
  }

  bool toggleAvailability({
    required String restaurantId,
    required String productId,
    required bool isAvailable,
  }) {
    return updateProduct(
      restaurantId: restaurantId,
      productId: productId,
      isAvailable: isAvailable,
    );
  }

  bool deleteProduct({
    required String restaurantId,
    required String productId,
  }) {
    final store = _restaurantStore;
    if (store == null) {
      return false;
    }
    final deleted = store.deletePartnerProduct(
      restaurantId: restaurantId,
      productId: productId,
    );
    if (deleted) {
      notifyListeners();
    }
    return deleted;
  }
}
