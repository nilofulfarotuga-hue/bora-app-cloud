import '../models/business_view_models.dart';
import '../models/restaurant_model.dart';
import '../stores/restaurant_store.dart';

class BusinessMapper {
  const BusinessMapper._();

  /// Builds a [Restaurant] view-model from the DB-backed [RestaurantStore].
  /// Products come exclusively from Supabase (no fake-data fallback).
  /// Non-partner restaurants show their seeded menu; the 15% markup is applied
  /// at cart time via CartStore.addItem() → PricingService.applyMarkup().
  static Restaurant buildRestaurantMenu({
    required RestaurantStore restaurantStore,
    required RestaurantModel business,
  }) {
    final partnerProducts = restaurantStore.partnerProductsForRestaurant(
      business.id,
      onlyAvailable: true,
    );

    // Bug-B fix 2026-04-30: propagate product.id so cart writes a real UUID
    // (not the product name) into create_order's product_lines.
    final menu = partnerProducts
        .map((product) => MenuItem(
              productId: product.id,
              name: product.name,
              price: product.price,
            ))
        .toList();

    return Restaurant(
      name: business.name,
      isPartner: business.isPartner,
      menu: menu,
    );
  }

  /// Builds a [RetailStore] view-model (metadata only — no products).
  /// Returns null only for [BusinessCategory.restaurant] entries.
  /// Products are loaded on-demand by [StoreProductsScreen] via [RestaurantStore].
  static RetailStore? buildRetailStore({
    required RestaurantStore restaurantStore,
    required RestaurantModel business,
  }) {
    if (business.category == BusinessCategory.restaurant) return null;

    return RetailStore(
      name: business.name,
      isPartner: business.isPartner,
      category: _mapStoreCategory(business.category),
    );
  }

  static StoreCategory _mapStoreCategory(BusinessCategory category) {
    switch (category) {
      case BusinessCategory.pharmacy:
        return StoreCategory.pharmacy;
      case BusinessCategory.restaurant:
      case BusinessCategory.supermarket:
      case BusinessCategory.store:
        return StoreCategory.market;
    }
  }
}
