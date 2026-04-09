import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../auth/auth_store.dart';
import '../config/maps_config.dart';
import '../models/restaurant_model.dart';
import '../services/location_service.dart';
import '../stores/cart_store.dart';
import '../stores/restaurant_store.dart';
import '../stores/session_store.dart';
import '../widgets/address_autocomplete_field.dart';
import 'carry_groceries_screen.dart';
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
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      context.read<RestaurantStore>().loadRestaurantsFromSupabase();
      _detectLocation();
    });
  }

  /// Requests GPS permission, gets current position, reverse-geocodes it,
  /// and pre-fills the CartStore delivery address. Fails silently.
  Future<void> _detectLocation() async {
    final location = await LocationService.getCurrentLocation();
    if (location == null || !mounted) return;

    final address = await LocationService.reverseGeocode(location, googleApiKey);
    if (!mounted) return;

    // Only update if the user hasn't already chosen an address.
    final cartStore = context.read<CartStore>();
    if (cartStore.dropoffStreet.isNotEmpty) return;

    cartStore.updateDeliveryAddress(
      street: address ?? '${location.latitude.toStringAsFixed(4)}, ${location.longitude.toStringAsFixed(4)}',
      city: '',
      postalCode: '',
      location: location,
    );
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

  void _openAddressPicker(BuildContext context) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const _AddressPickerScreen()),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final restaurantStore = context.watch<RestaurantStore>();

    final addressLine = context.select<CartStore, String>((store) {
      final street = store.dropoffStreet.trim();
      final city = store.dropoffCity.trim();
      if (street.isEmpty && city.isEmpty) return 'Selecionar endereço';
      if (street.isEmpty) return city;
      if (city.isEmpty) return street;
      return '$street, $city';
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
      onTap: () => _openAddressPicker(context),
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
                    'Entrega em',
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
        title: 'Restaurantes',
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
        title: 'Supermercados',
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
        title: 'Lojas',
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
        title: 'Farmácia',
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
        title: 'Enviar Encomenda',
        icon: Icons.local_shipping,
        color: const Color(0xFF48CAE4),
        onTap: () {
          Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const SendPackageFormScreen()),
          );
        },
      ),
      _CategoryOption(
        title: 'Fazer Compras',
        icon: Icons.shopping_bag,
        color: const Color(0xFFB5838D),
        onTap: () {
          Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const CarryGroceriesScreen()),
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

// ─── Address picker screen ─────────────────────────────────────────────────

class _AddressPickerScreen extends StatefulWidget {
  const _AddressPickerScreen();

  @override
  State<_AddressPickerScreen> createState() => _AddressPickerScreenState();
}

class _AddressPickerScreenState extends State<_AddressPickerScreen> {
  final _ctrl = TextEditingController();

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Endereço de entrega')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            AddressAutocompleteField(
              controller: _ctrl,
              labelText: 'Pesquisar endereço',
              onSelected: (address, coords) {
                context.read<CartStore>().updateDeliveryAddress(
                      street: address,
                      city: '',
                      postalCode: '',
                      location: coords,
                    );
                Navigator.of(context).pop();
              },
            ),
            const SizedBox(height: 16),
            Text(
              'Comece a escrever o endereço e selecione uma sugestão.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Category helpers ──────────────────────────────────────────────────────

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
