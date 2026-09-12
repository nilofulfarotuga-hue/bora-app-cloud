import 'package:flutter/material.dart';

import 'market/market_store_screen.dart';

/// Wrapper fino que delega para [MarketStoreScreen].
/// Mantém a assinatura pública original — callers (stores_screen.dart)
/// não precisam de alterações.
class StoreCategoriesScreen extends StatelessWidget {
  const StoreCategoriesScreen({
    super.key,
    required this.restaurantId,
    required this.storeName,
    required this.isPartnerStore,
  });

  final String restaurantId;
  final String storeName;
  final bool isPartnerStore;

  @override
  Widget build(BuildContext context) => MarketStoreScreen(
        restaurantId: restaurantId,
        storeName: storeName,
        isPartnerStore: isPartnerStore,
        initialTab: 0,
      );
}
