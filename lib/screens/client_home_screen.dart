import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../auth/auth_store.dart';
import '../config/app_colors.dart';
import '../config/app_spacing.dart';
import '../config/maps_config.dart';
import '../models/restaurant_model.dart';
import '../services/location_service.dart';
import '../stores/cart_store.dart';
import '../stores/restaurant_store.dart';
import '../stores/session_store.dart';
import '../widgets/address_autocomplete_field.dart';
import '../widgets/bora/bora.dart';
import '../widgets/bora_support_fab.dart';
import '../widgets/notification_bell.dart';
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

  /// Pre-fills the CartStore delivery address on startup.
  /// Priority: 1) existing address from prefs  2) Casa  3) GPS
  Future<void> _detectLocation() async {
    if (!mounted) return;
    final cartStore = context.read<CartStore>();

    if (cartStore.dropoffStreet.isNotEmpty) return;

    final sessionStore = context.read<SessionStore>();
    if (sessionStore.hasHomeAddress) {
      cartStore.updateDeliveryAddress(
        street: sessionStore.homeStreet!,
        city: sessionStore.homeCity ?? '',
        postalCode: '',
        location: sessionStore.homeLocation,
      );
      return;
    }

    final location = await LocationService.getCurrentLocation();
    if (location == null || !mounted) return;

    final address =
        await LocationService.reverseGeocode(location, googleApiKey);
    if (!mounted) return;
    if (cartStore.dropoffStreet.isNotEmpty) return;

    cartStore.updateDeliveryAddress(
      street: address ??
          '${location.latitude.toStringAsFixed(4)}, ${location.longitude.toStringAsFixed(4)}',
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

  void _openAddressPicker() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const _AddressPickerScreen()),
    );
  }

  void _navigateWithAddressGuard(VoidCallback nav) {
    final street = context.read<CartStore>().dropoffStreet;
    if (street.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Define o teu endereço de entrega para continuar.'),
          backgroundColor: AppColors.error,
          duration: Duration(seconds: 3),
        ),
      );
      _openAddressPicker();
      return;
    }
    nav();
  }

  @override
  Widget build(BuildContext context) {
    final addressLine = context.select<CartStore, String>((store) {
      final street = store.dropoffStreet.trim();
      final city = store.dropoffCity.trim();
      if (street.isEmpty && city.isEmpty) return 'Seleccionar endereço';
      if (street.isEmpty) return city;
      if (city.isEmpty) return street;
      return '$street, $city';
    });

    final authStore = context.watch<AuthStore>();
    final firstName = () {
      final name = authStore.displayName ?? '';
      return name.isEmpty ? 'Olá!' : 'Olá, ${name.split(' ').first}!';
    }();

    return Scaffold(
      backgroundColor: AppColors.surface,
      floatingActionButton: const BoraSupportFab(),
      body: Column(
        children: [
          BoraAppBar(
            title: firstName,
            subtitle: 'O que precisas hoje?',
            actions: [
              // BUG 4 (Fase 6 / 2026-04-30): NotificationBell agora visível.
              const NotificationBell(),
              IconButton(
                icon: const Icon(Icons.swap_horiz, color: Colors.white),
                tooltip: 'Mudar modo',
                onPressed: _handleTestMode,
              ),
            ],
          ),
          Expanded(
            child: SingleChildScrollView(
              physics: const BouncingScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(
                Spacing.lg,
                Spacing.lg,
                Spacing.lg,
                Spacing.xxxl,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  BoraAddressBar(
                    label: 'Entrega em',
                    address: addressLine,
                    onTap: _openAddressPicker,
                  ),
                  const SizedBox(height: Spacing.md),
                  BoraSearchField(
                    hint: 'O que queres pedir hoje?',
                    readOnly: true,
                    onTap: () {
                      _navigateWithAddressGuard(() {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => const RestaurantsScreen(),
                          ),
                        );
                      });
                    },
                  ),
                  const SizedBox(height: Spacing.xl),
                  _buildCategoryGrid(context),
                  const SizedBox(height: Spacing.xl),
                  BoraPromoBanner(
                    title: 'Entregas rápidas\ne seguras',
                    subtitle: 'Tudo o que precisas à distância de um toque',
                    trailingIcon: Icons.delivery_dining,
                    onTap: () => _navigateWithAddressGuard(() {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => const RestaurantsScreen(),
                        ),
                      );
                    }),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCategoryGrid(BuildContext context) {
    final tiles = <_TileData>[
      _TileData(
        label: 'Restaurantes',
        gradient: AppColors.tileRestaurants,
        icon: Icons.restaurant_menu,
        onTap: () => _navigateWithAddressGuard(() {
          Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const RestaurantsScreen()),
          );
        }),
      ),
      _TileData(
        label: 'Supermercados',
        gradient: AppColors.tileSupermarkets,
        icon: Icons.shopping_cart,
        onTap: () => _navigateWithAddressGuard(() {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => const StoresScreen(
                  initialCategory: BusinessCategory.supermarket),
            ),
          );
        }),
      ),
      _TileData(
        label: 'Farmácia',
        gradient: AppColors.tilePharmacy,
        icon: Icons.local_pharmacy,
        onTap: () => _navigateWithAddressGuard(() {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => const StoresScreen(
                  initialCategory: BusinessCategory.pharmacy),
            ),
          );
        }),
      ),
      _TileData(
        label: 'Enviar\nEncomenda',
        gradient: AppColors.tileSendPackage,
        icon: Icons.local_shipping,
        onTap: () => _navigateWithAddressGuard(() {
          Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const SendPackageFormScreen()),
          );
        }),
      ),
      _TileData(
        label: 'Levar\nCompras',
        gradient: AppColors.tileCarryGroceries,
        icon: Icons.shopping_bag,
        onTap: () => _navigateWithAddressGuard(() {
          Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const CarryGroceriesScreen()),
          );
        }),
      ),
      _TileData(
        label: 'Reservar\nMesa',
        gradient: AppColors.tileReserveTable,
        icon: Icons.event_seat_outlined,
        onTap: () => _navigateWithAddressGuard(() {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                  'Escolhe um restaurante para reservar mesa. (BR §14)'),
              duration: Duration(seconds: 2),
            ),
          );
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) =>
                  const RestaurantsScreen(reservationsOnly: true),
            ),
          );
        }),
      ),
    ];

    return GridView.count(
      crossAxisCount: 3,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      crossAxisSpacing: Spacing.md,
      mainAxisSpacing: Spacing.md,
      childAspectRatio: 0.95,
      children: tiles
          .map((t) => BoraTileCard(
                label: t.label,
                gradient: t.gradient,
                iconData: t.icon,
                onTap: t.onTap,
              ))
          .toList(),
    );
  }
}

// ─── Internal ──────────────────────────────────────────────────────────────

class _TileData {
  _TileData({
    required this.label,
    required this.gradient,
    required this.icon,
    required this.onTap,
  });

  final String label;
  final Gradient gradient;
  final IconData icon;
  final VoidCallback onTap;
}

// ─── Address picker screen ─────────────────────────────────────────────────

class _AddressPickerScreen extends StatefulWidget {
  const _AddressPickerScreen();

  @override
  State<_AddressPickerScreen> createState() => _AddressPickerScreenState();
}

class _AddressPickerScreenState extends State<_AddressPickerScreen> {
  final _ctrl = TextEditingController();
  bool _loadingGps = false;

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  Future<void> _useGps() async {
    setState(() => _loadingGps = true);
    final location = await LocationService.getCurrentLocation();
    if (!mounted) return;
    setState(() => _loadingGps = false);

    if (location == null) {
      final msg = LocationService.isConsentBlocked
          ? 'Activa a localização nas definições para fazer pedidos'
          : 'Não foi possível obter a localização GPS.';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(msg)),
      );
      return;
    }

    final address =
        await LocationService.reverseGeocode(location, googleApiKey);
    if (!mounted) return;

    context.read<CartStore>().updateDeliveryAddress(
          street: address ??
              '${location.latitude.toStringAsFixed(4)}, ${location.longitude.toStringAsFixed(4)}',
          city: '',
          postalCode: '',
          location: location,
        );
    Navigator.of(context).pop();
  }

  void _useHome() {
    final session = context.read<SessionStore>();
    if (!session.hasHomeAddress) return;
    context.read<CartStore>().updateDeliveryAddress(
          street: session.homeStreet!,
          city: session.homeCity ?? '',
          postalCode: '',
          location: session.homeLocation,
        );
    Navigator.of(context).pop();
  }

  void _onAddressSelected(String address, dynamic coords) {
    context.read<CartStore>().updateDeliveryAddress(
          street: address,
          city: '',
          postalCode: '',
          location: coords,
        );
    _showSaveAsHomeDialog(address, coords);
  }

  void _showSaveAsHomeDialog(String address, dynamic coords) {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Guardar como Casa?'),
        content: Text(address),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.of(ctx).pop();
              Navigator.of(context).pop();
            },
            child: const Text('Não'),
          ),
          TextButton(
            onPressed: () {
              context.read<SessionStore>().setHomeAddress(
                    street: address,
                    city: '',
                    location: coords,
                  );
              Navigator.of(ctx).pop();
              Navigator.of(context).pop();
            },
            child: const Text('Guardar'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final session = context.watch<SessionStore>();

    return Scaffold(
      backgroundColor: AppColors.surface,
      appBar: AppBar(
        title: const Text(
          'Endereço de entrega',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        backgroundColor: Colors.transparent,
        foregroundColor: Colors.white,
        elevation: 0,
        flexibleSpace: const DecoratedBox(
          decoration: BoxDecoration(gradient: AppColors.headerGradient),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.all(Spacing.lg),
        children: [
          ListTile(
            leading: const Icon(Icons.my_location_rounded),
            title: const Text('Localização actual'),
            subtitle: const Text('Usar GPS do dispositivo'),
            trailing: _loadingGps
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.chevron_right),
            onTap: _loadingGps ? null : _useGps,
          ),
          ListTile(
            leading: Icon(
              Icons.home_rounded,
              color: session.hasHomeAddress ? theme.colorScheme.primary : null,
            ),
            title: Text(
              session.hasHomeAddress ? session.homeStreet! : 'Casa',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            subtitle: Text(
              session.hasHomeAddress
                  ? 'Endereço guardado'
                  : 'Nenhum endereço guardado',
            ),
            trailing:
                session.hasHomeAddress ? const Icon(Icons.chevron_right) : null,
            onTap: session.hasHomeAddress ? _useHome : null,
          ),
          const Divider(height: Spacing.xxxl),
          AddressAutocompleteField(
            controller: _ctrl,
            labelText: 'Pesquisar endereço',
            onSelected: _onAddressSelected,
          ),
          const SizedBox(height: Spacing.sm),
          Text(
            'Começa a escrever e selecciona uma sugestão.',
            style: theme.textTheme.bodySmall,
          ),
        ],
      ),
    );
  }
}
