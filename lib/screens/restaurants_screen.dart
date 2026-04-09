import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/order_service_type.dart';
import '../models/restaurant_model.dart';
import '../stores/cart_store.dart';
import '../stores/restaurant_store.dart';
import '../utils/business_mapper.dart';
import 'restaurant_menu_screen.dart';

class RestaurantsScreen extends StatelessWidget {
  const RestaurantsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final restaurantStore = context.watch<RestaurantStore>();
    final restaurants = restaurantStore.restaurants
        .where((business) =>
            business.category == BusinessCategory.restaurant &&
            business.isOnline)
        .toList()
      ..sort((a, b) => a.name.compareTo(b.name));

    if (restaurants.isEmpty) {
      return Scaffold(
        appBar: AppBar(title: const Text('Restaurantes')),
        body: const Center(
          child: Text('Nenhum restaurante disponível no momento.'),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Restaurantes')),
      body: ListView.builder(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
        itemCount: restaurants.length,
        itemBuilder: (context, index) {
          final business = restaurants[index];
          return _RestaurantTile(
            business: business,
            onTap: () => _openRestaurant(context, restaurantStore, business),
          );
        },
      ),
    );
  }

  void _openRestaurant(
    BuildContext context,
    RestaurantStore restaurantStore,
    RestaurantModel business,
  ) {
    if (business.location == null) {
      debugPrint(
        'RestaurantsScreen: BLOCKED — "${business.name}" has no coordinates.',
      );
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Restaurante sem localização definida. Contacte o suporte.',
          ),
          duration: Duration(seconds: 4),
        ),
      );
      return;
    }

    context.read<CartStore>().configureSession(
          serviceType: OrderServiceType.restaurant,
          isPartnerStore: business.isPartner,
          vendorName: business.name,
          pickupLocation: business.location!,
          pickupStreet: business.address,
          pickupCity: null,
          pickupPostalCode: null,
        );

    final restaurant = BusinessMapper.buildRestaurantMenu(
      restaurantStore: restaurantStore,
      business: business,
    );

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => RestaurantMenuScreen(restaurant: restaurant),
      ),
    );
  }
}

class _RestaurantTile extends StatelessWidget {
  const _RestaurantTile({required this.business, required this.onTap});

  final RestaurantModel business;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final isPartner = business.isPartner;
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 8),
      child: ListTile(
        title: Row(
          children: [
            Expanded(
              child: Text(
                business.name,
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            const SizedBox(width: 8),
            _PartnerBadge(isPartner: isPartner),
          ],
        ),
        subtitle: Text(
          isPartner
              ? 'Restaurante parceiro'
              : 'Um estafeta irá comprar por você',
        ),
        trailing: const Icon(Icons.arrow_forward_ios),
        onTap: onTap,
      ),
    );
  }
}

class _PartnerBadge extends StatelessWidget {
  const _PartnerBadge({required this.isPartner});

  final bool isPartner;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: isPartner ? Colors.green.shade100 : Colors.orange.shade100,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isPartner ? Colors.green : Colors.orange,
          width: 1,
        ),
      ),
      child: Text(
        isPartner ? 'Parceiro' : 'Não parceiro',
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: isPartner ? Colors.green.shade800 : Colors.orange.shade800,
        ),
      ),
    );
  }
}

