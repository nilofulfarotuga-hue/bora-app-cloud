import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';
import 'package:geocoding/geocoding.dart';

import '../services/location_service.dart';

import '../models/order_service_type.dart';
import '../auth/auth_store.dart';
import '../models/restaurant_model.dart';
import '../stores/cart_store.dart';
import '../stores/restaurant_store.dart';
import '../stores/session_store.dart';

import 'carry_groceries_screen.dart';
import 'map_screen.dart';
import 'restaurants_screen.dart';
import 'send_package_form_screen.dart';
import 'stores_screen.dart';

class ClientHomeScreen extends StatefulWidget {
  const ClientHomeScreen({super.key});

  @override
  State<ClientHomeScreen> createState() => _ClientHomeScreenState();
}

class _ClientHomeScreenState extends State<ClientHomeScreen> {

  @override
  void initState() {
    super.initState();
    _loadCurrentLocation();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      context.read<RestaurantStore>().loadRestaurantsFromSupabase();
    });
  }

  Future<void> _loadCurrentLocation() async {
    try {
      final location = await LocationService.getCurrentLocation();

      String street = "";
      String city = "";

      try {
        final placemarks = await placemarkFromCoordinates(
          location.latitude,
          location.longitude,
          localeIdentifier: 'pt_PT',
        );

        if (placemarks.isNotEmpty) {
          final place = placemarks.first;
          street = place.street ?? "";
          city = place.locality ?? "";
        }
      } catch (_) {
        debugPrint("Geocoding falhou");
      }

      context.read<CartStore>().updateDeliveryAddress(
        street: street,
        city: city,
        postalCode: "",
        location: location,
      );
    } catch (e) {
      debugPrint("Erro ao obter localização: $e");
    }
  }

  static const Map<String, _RestaurantInfo> _restaurantMetadata = {
    "Pizzaria do Zé": _RestaurantInfo(
      location: LatLng(38.7124, -9.1403),
      street: "Rua dos Sapateiros 122",
      city: "Lisboa",
      postalCode: "1100-587",
    ),
    "Kebab do Mané": _RestaurantInfo(
      location: LatLng(38.7165, -9.1298),
      street: "Rua do Ouro 210",
      city: "Lisboa",
      postalCode: "1100-062",
    ),
    "Hamburgueria Lisboa Grill": _RestaurantInfo(
      location: LatLng(38.7208, -9.1481),
      street: "Av. da Liberdade 204",
      city: "Lisboa",
      postalCode: "1250-147",
    ),
  };

  static const Map<String, _StoreInfo> _storeMetadata = {
    "Mini Mercado Lisboa": _StoreInfo(
      location: LatLng(38.7132, -9.1355),
      street: "Rua da Madalena 220",
      city: "Lisboa",
      postalCode: "1100-320",
    ),
  };

  OrderServiceType _serviceTypeForCategory(BusinessCategory category) {
    switch (category) {
      case BusinessCategory.restaurant:
        return OrderServiceType.restaurant;
      case BusinessCategory.supermarket:
      case BusinessCategory.store:
      case BusinessCategory.pharmacy:
        return OrderServiceType.storeShopping;
    }
  }

  Future<void> _handleTestMode() async {
    if (!mounted) return;

    final authStore = context.read<AuthStore>();
    final sessionStore = context.read<SessionStore>();

    authStore.logout();
    await sessionStore.clearRole();

    if (!mounted) return;

    Navigator.of(context).popUntil((route) => route.isFirst);
  }

  @override
  Widget build(BuildContext context) {

    final theme = Theme.of(context);
    final restaurantStore = context.watch<RestaurantStore>();

    final addressLine = context.select<CartStore, String>((store) {
      final street = store.dropoffStreet.trim();
      final city = store.dropoffCity.trim();

      if (street.isEmpty && city.isEmpty) {
        return "Selecionar endereço";
      }

      if (street.isEmpty) return city;
      if (city.isEmpty) return street;

      return "$street, $city";
    });

    return Scaffold(
      backgroundColor: theme.colorScheme.surface,
      body: SafeArea(
        child: SingleChildScrollView(
          physics: const BouncingScrollPhysics(),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [

              Align(
                alignment: Alignment.centerRight,
                child: TextButton.icon(
                  onPressed: _handleTestMode,
                  icon: const Icon(Icons.bug_report_outlined),
                  label: const Text('Teste'),
                ),
              ),

              const SizedBox(height: 16),

              _buildAddressBar(context, addressLine),

              const SizedBox(height: 16),

              _buildSearchBar(context, restaurantStore),

              const SizedBox(height: 24),

              _buildCategorySection(context),

              const SizedBox(height: 16),

            ],
          ),
        ),
      ),
    );
  }

  Widget _buildAddressBar(BuildContext context, String addressLine) {

    final theme = Theme.of(context);

    return GestureDetector(
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const MapScreen()),
        );
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
        decoration: BoxDecoration(
          color: theme.colorScheme.surface,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(
          children: [

            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: theme.colorScheme.primary.withOpacity(0.12),
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.location_on_rounded,
                color: theme.colorScheme.primary,
              ),
            ),

            const SizedBox(width: 16),

            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [

                  Text(
                    "Entrega em",
                    style: theme.textTheme.labelMedium,
                  ),

                  const SizedBox(height: 4),

                  Text(
                    addressLine,
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),

                ],
              ),
            ),

            const Icon(Icons.chevron_right_rounded),

          ],
        ),
      ),
    );
  }

  Widget _buildSearchBar(
    BuildContext context,
    RestaurantStore restaurantStore,
  ) {
    return const TextField(
      readOnly: true,
      decoration: InputDecoration(
        hintText: 'O que você quer hoje?',
        prefixIcon: Icon(Icons.search),
      ),
    );
  }

  Widget _buildCategorySection(BuildContext context) {

    final categories = [

      _CategoryOption(
        title: 'Restaurants',
        icon: Icons.restaurant_menu,
        color: const Color(0xFFFFC857),
        onTap: () {
          Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const RestaurantsScreen()),
          );
        },
      ),

      _CategoryOption(
        title: 'Supermarkets',
        icon: Icons.shopping_cart,
        color: const Color(0xFF57CC99),
        onTap: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) =>
                  const StoresScreen(initialCategory: BusinessCategory.supermarket),
            ),
          );
        },
      ),

      _CategoryOption(
        title: 'Stores',
        icon: Icons.storefront,
        color: const Color(0xFF5C7AEA),
        onTap: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) =>
                  const StoresScreen(initialCategory: BusinessCategory.store),
            ),
          );
        },
      ),

      _CategoryOption(
        title: 'Pharmacy',
        icon: Icons.local_pharmacy,
        color: const Color(0xFFEE6352),
        onTap: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) =>
                  const StoresScreen(initialCategory: BusinessCategory.pharmacy),
            ),
          );
        },
      ),

      _CategoryOption(
        title: 'Send Package',
        icon: Icons.local_shipping,
        color: const Color(0xFF48CAE4),
        onTap: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => const SendPackageFormScreen(),
            ),
          );
        },
      ),

      _CategoryOption(
        title: 'Deliver My Groceries',
        icon: Icons.shopping_bag,
        color: const Color(0xFFB5838D),
        onTap: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => const CarryGroceriesScreen(),
            ),
          );
        },
      ),

    ];

    return Wrap(
      spacing: 16,
      runSpacing: 16,
      children: categories
          .map((category) => _CategoryButton(option: category))
          .toList(),
    );
  }
}

class _CategoryOption {
  const _CategoryOption({
    required this.title,
    required this.icon,
    required this.color,
    required this.onTap,
  });

  final String title;
  final IconData icon;
  final Color color;
  final VoidCallback onTap;
}

class _CategoryButton extends StatelessWidget {
  const _CategoryButton({required this.option});

  final _CategoryOption option;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: option.onTap,
      child: Column(
        children: [
          Icon(option.icon, size: 32, color: option.color),
          const SizedBox(height: 8),
          Text(option.title),
        ],
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

class _StoreInfo {
  const _StoreInfo({
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