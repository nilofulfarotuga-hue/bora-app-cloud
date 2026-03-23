import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';

import '../models/order_service_type.dart';
import '../models/restaurant_model.dart';
import '../stores/cart_store.dart';
import '../stores/restaurant_store.dart';
import '../utils/business_mapper.dart';
import 'restaurant_menu_screen.dart';

class RestaurantsScreen extends StatelessWidget {
  const RestaurantsScreen({super.key});

  static const Map<String, _RestaurantInfo> _restaurantMetadata = {
    'Pizzaria do Zé': _RestaurantInfo(
      location: LatLng(38.7124, -9.1403),
      street: 'Rua dos Sapateiros 122',
      city: 'Lisboa',
      postalCode: '1100-587',
    ),
    'Kebab do Mané': _RestaurantInfo(
      location: LatLng(38.7165, -9.1298),
      street: 'Rua do Ouro 210',
      city: 'Lisboa',
      postalCode: '1100-062',
    ),
    'Hamburgueria Lisboa Grill': _RestaurantInfo(
      location: LatLng(38.7208, -9.1481),
      street: 'Av. da Liberdade 204',
      city: 'Lisboa',
      postalCode: '1250-147',
    ),
    'Pastelaria Central': _RestaurantInfo(
      location: LatLng(38.7201, -9.1407),
      street: 'Praça da Figueira 13',
      city: 'Lisboa',
      postalCode: '1100-240',
    ),
    'Churrasqueira do Bairro': _RestaurantInfo(
      location: LatLng(38.7256, -9.1552),
      street: 'Rua de São Bento 91',
      city: 'Lisboa',
      postalCode: '1200-819',
    ),
    'Burger King': _RestaurantInfo(
      location: LatLng(38.7301, -9.1467),
      street: 'R. Joaquim António de Aguiar 16',
      city: 'Lisboa',
      postalCode: '1070-150',
    ),
    'KFC': _RestaurantInfo(
      location: LatLng(38.7362, -9.1283),
      street: 'Praça Martim Moniz 2',
      city: 'Lisboa',
      postalCode: '1100-341',
    ),
    'McDonald\'s': _RestaurantInfo(
      location: LatLng(38.7265, -9.1409),
      street: 'Av. Fontes Pereira de Melo 5',
      city: 'Lisboa',
      postalCode: '1050-116',
    ),
    'Pizza Hut': _RestaurantInfo(
      location: LatLng(38.7441, -9.1602),
      street: 'Av. de Berna 12',
      city: 'Lisboa',
      postalCode: '1050-042',
    ),
  };

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
        appBar: AppBar(
          title: const Text('Restaurants'),
        ),
        body: const Center(
          child: Text('Nenhum restaurante disponível no momento.'),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Restaurants'),
      ),
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
    final metadata = _restaurantMetadata[business.name];
    context.read<CartStore>().configureSession(
          serviceType: OrderServiceType.restaurant,
          isPartnerStore: business.isPartner,
          vendorName: business.name,
          pickupLocation: metadata?.location ?? business.location,
          pickupStreet: metadata?.street ?? business.address,
          pickupCity: metadata?.city,
          pickupPostalCode: metadata?.postalCode,
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

class _RestaurantInfo {
  const _RestaurantInfo({
    required this.location,
    required this.street,
    required this.city,
    required this.postalCode,
  });

  final LatLng location;
  final String street;
  final String city;
  final String postalCode;
}