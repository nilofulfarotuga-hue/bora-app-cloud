import '../models/cart_item.dart';
import '../models/order_model.dart';
import '../models/order_service_type.dart';
import '../models/partner_product.dart';
import '../models/restaurant_model.dart';
import '../services/pricing_service.dart';
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
    // Festas: re-pedir numa loja de festas volta a exigir o calendário —
    // resolver a categoria pelo nome da loja quando o store está disponível.
    final vendorFestas = restaurantStore?.restaurants
            .where((r) => r.name == order.vendorName)
            .any((r) => r.belongsTo(BusinessCategory.festas)) ??
        false;
    // Taxa de pedido pequeno: precisa do id da loja para saber se ela tem
    // minimo proprio. O pedido antigo so guarda o nome.
    final vendorId = restaurantStore?.restaurants
        .where((r) => r.name == order.vendorName)
        .map((r) => r.id)
        .firstOrNull;
    cart.configureSession(
      serviceType: order.serviceType,
      isPartnerStore: order.isPartnerStore,
      vendorIsFestas: vendorFestas,
      vendorName: order.vendorName,
      vendorRestaurantId: vendorId,
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

    final isNonPartnerMarket = !order.isPartnerStore &&
        order.serviceType == OrderServiceType.storeShopping;

    for (final it in order.items) {
      double currentPrice = it.price;
      double? basePrice = it.basePrice;
      if (liveProducts != null) {
        final fresh = _findMatch(liveProducts, it);
        if (fresh != null && (fresh.price - it.price).abs() > 0.01) {
          changedPrices.add(it.name);
          currentPrice = fresh.price;
          basePrice = fresh.price; // parceiro: preço do menu é o cobrado
        }
      }
      // B1 (2026-06-11): pedidos de mercado anteriores ao fix gravavam
      // items[].price = preço BASE (sem markup) e sem basePrice. Reaplicar o
      // markup de exibição para o carrinho voltar a bater com o cobrado.
      // Restaurantes não-parceiro antigos já gravavam price com markup —
      // nesses, ficar como está (basePrice null → unit_price = price, igual
      // ao comportamento pré-fix).
      if (isNonPartnerMarket && it.basePrice == null) {
        basePrice = it.price;
        currentPrice = PricingService.applyMarkup(it.price, false);
      }
      cart.addItem(CartItem(
        productId: it.productId,
        name: it.name,
        price: currentPrice,
        basePrice: basePrice,
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
