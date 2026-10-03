import 'package:flutter/material.dart';

import '../models/restaurant_model.dart';
import '../screens/restaurants_screen.dart';
import '../screens/stores_screen.dart';
import '../stores/restaurant_store.dart';
import 'business_mapper.dart';

/// Abre um negócio a partir de QUALQUER secção do cliente (Restaurantes,
/// Supermercados, Lojas, Farmácias) — incluindo as secções em que ele só
/// aparece por `extra_categories`.
///
/// É sempre a MESMA loja: mesmo `restaurant_id`, mesmo catálogo, mesmo dono.
/// O detalhe abre com o layout da **categoria principal** do negócio
/// (cardápio para `restaurant`, grelha/categorias para mercado ou loja),
/// para não partir nem ficar em branco quando a secção difere.
Future<void> openBusiness(
  BuildContext context,
  RestaurantStore restaurantStore,
  RestaurantModel business, {
  bool reservationsOnly = false,
}) async {
  final retailStore = BusinessMapper.buildRetailStore(
    restaurantStore: restaurantStore,
    business: business,
  );
  if (retailStore == null) {
    // Categoria principal = restaurant → fluxo de restaurante.
    return openRestaurantBusiness(
      context,
      restaurantStore,
      business,
      reservationsOnly: reservationsOnly,
    );
  }
  return openRetailBusiness(context, business, retailStore);
}
