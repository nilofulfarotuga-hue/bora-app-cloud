import '../models/cart_item.dart';
import '../models/order_model.dart';
import '../models/order_service_type.dart';
import '../models/partner_product.dart';
import '../models/restaurant_model.dart';
import '../stores/cart_store.dart';
import '../stores/partner_product_store.dart';
import '../stores/restaurant_store.dart';

/// Helper to reapply a past order back into the cart (Uber Eats "order again").
class ReorderService {
  /// Returns true when the order can be re-placed: must be a food/shopping
  /// order with at least one item. Pure logistics (`carryGroceries`,
  /// `sendPackage`) and empty orders are excluded.
  static bool isReorderable(OrderModel order) {
    if (order.items.isEmpty) return false;
    return order.serviceType == OrderServiceType.restaurant ||
        order.serviceType == OrderServiceType.storeShopping;
  }

  /// Applies the order to the cart. Returns the list of item names whose
  /// current price differs from the historical price (partner store only);
  /// caller can show a toast warning the user.
  static List<String> applyTo({
    required CartStore cart,
    required OrderModel order,
    PartnerProductStore? partnerStore,
    RestaurantStore? restaurantStore,
  }) {
    cart.clearCart();
    cart.configureSession(
      serviceType: order.serviceType,
      isPartnerStore: order.isPartnerStore,
      vendorName: order.vendorName,
      pickupLocation: order.pickupLocation,
      pickupStreet: order.pickupStreet,
    );

    final changedPrices = <String>[];

    List<PartnerProduct>? liveProducts;
    if (order.isPartnerStore &&
        partnerStore != null &&
        restaurantStore != null) {
      final RestaurantModel? restaurant =
          restaurantStore.restaurantByName(order.vendorName);
      if (restaurant != null) {
        liveProducts = partnerStore.productsForRestaurant(restaurant.id);
      }
    }

    for (final it in order.items) {
      double currentPrice = it.price;
      if (liveProducts != null) {
        final fresh = _findMatch(liveProducts, it);
        if (fresh != null && (fresh.price - it.price).abs() > 0.01) {
          changedPrices.add(it.name);
          currentPrice = fresh.price;
        }
      }
      cart.addItem(CartItem(
        productId: it.productId,
        name: it.name,
        price: currentPrice,
        quantity: it.quantity,
      ));
    }
    return changedPrices;
  }

  static PartnerProduct? _findMatch(
      List<PartnerProduct> products, CartItem historical) {
    for (final p in products) {
      if (p.id == historical.productId) return p;
    }
    final key = historical.name.trim().toLowerCase();
    for (final p in products) {
      if (p.name.trim().toLowerCase() == key) return p;
    }
    return null;
  }
}
