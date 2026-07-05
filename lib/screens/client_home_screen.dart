import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../auth/auth_store.dart';
import '../config/app_colors.dart';
import '../config/app_spacing.dart';
import '../config/maps_config.dart';
import '../models/client_address.dart';
import '../models/order_model.dart';
import '../models/rating_model.dart';
import '../models/restaurant_model.dart';
import '../services/client_address_service.dart';
import '../services/location_service.dart';
import '../stores/cart_store.dart';
import '../stores/order_store.dart';
import '../stores/restaurant_store.dart';
import '../stores/session_store.dart';
import '../widgets/address_autocomplete_field.dart';
import '../widgets/bora/bora.dart';
import '../widgets/bora_support_fab.dart';
import '../widgets/notification_bell.dart';
import 'carry_groceries_screen.dart';
import 'client/cleaning/cleaning_bookings_screen.dart';
import 'client/services/services_category_screen.dart';
import 'client_addresses_screen.dart';
import 'rating_screen.dart';
import 'restaurants_screen.dart';
import 'send_package_form_screen.dart';
import 'errand_form_screen.dart';
import 'stores_screen.dart';
import '../stores/tvde_store.dart';
import 'client/tvde/tvde_unlock_screen.dart';
import 'client/tvde/tvde_request_ride_screen.dart';

class ClientHomeScreen extends StatefulWidget {
  const ClientHomeScreen({super.key});

  @override
  State<ClientHomeScreen> createState() => _ClientHomeScreenState();
}

class _ClientHomeScreenState extends State<ClientHomeScreen>
    with WidgetsBindingObserver {
  // BUG 3 (2026-05-17) — Realtime listener for the unrated rating dialog.
  // OrderStore exposes `lastDeliveredAt`, updated whenever an order
  // transitions to delivered via Realtime. When the timestamp moves into
  // the recent past (≤10s), we re-run _checkUnratedOrders after a small
  // UX delay so the dialog appears in foreground without an app reopen.
  OrderStore? _orderStore;
  // BUG 3 (2026-05-17) — guard against concurrent runs.
  // _checkUnratedOrders is now triggered from three places (initState,
  // didChangeAppLifecycleState.resumed, OrderStore listener) so a quick
  // resume + Realtime delivered could stack two RatingScreen pushes.
  bool _ratingCheckInFlight = false;

  @override
  void initState() {
    super.initState();
    // BUG #5 (2026-05-12) — observa lifecycle para re-checar pedidos avaliáveis
    // quando app volta ao foreground (não precisa reabrir manualmente).
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      context.read<RestaurantStore>().loadRestaurantsFromSupabase();
      // TVDE — re-lê tvde_access para mostrar/esconder a categoria escondida.
      context.read<TvdeStore>().refreshAccess();
      _detectLocation();
      // Sessão 6 §44 — abre RatingScreen se há pedido entregue ainda não avaliado.
      _checkUnratedOrders();
      // BUG 3 (2026-05-17) — attach Realtime listener on OrderStore.
      _orderStore = context.read<OrderStore>();
      _orderStore!.addListener(_onOrderStoreChanged);
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _orderStore?.removeListener(_onOrderStoreChanged);
    super.dispose();
  }

  // BUG #5 (2026-05-12) — quando a app volta ao foreground (resumed),
  // re-verifica pedidos delivered não-avaliados. Resolve "modal só aparece
  // ao reabrir app" sem precisar de fechar/reabrir manualmente.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && mounted) {
      _checkUnratedOrders();
      // TVDE — categoria escondida aparece/some reativamente após aprovação.
      context.read<TvdeStore>().refreshAccess();
    }
  }

  void _onOrderStoreChanged() {
    if (!mounted) return;
    final stamp = _orderStore?.lastDeliveredAt;
    if (stamp == null) return;
    if (DateTime.now().difference(stamp).inSeconds > 10) return;
    // Small UX delay so the user sees the delivered status before the
    // rating prompt covers it.
    Future<void>.delayed(const Duration(seconds: 2), () {
      if (mounted) _checkUnratedOrders();
    });
  }

  /// BR §44.6 — pós-login/abertura, procura pedido `delivered` recente
  /// (≤ 48h) com avaliação pendente (driver e/ou partner). Abre
  /// RatingScreen sequencialmente para cada sujeito ainda não avaliado.
  ///
  /// Anti-spam (DEFAULT padrão Glovo, 2026-05-11): se o cliente saltar
  /// o mesmo pedido 2× consecutivas (counter em SharedPreferences), o
  /// pedido deixa de prompt. Total = 1 mostra automática + 2 skips.
  ///
  /// Aplica a TODOS service_type (restaurant, storeShopping,
  /// carryGroceries, sendPackage). Falhas silenciosas.
  Future<void> _checkUnratedOrders() async {
    if (_ratingCheckInFlight) return;
    _ratingCheckInFlight = true;
    try {
      final supabase = Supabase.instance.client;
      final user = supabase.auth.currentUser;
      if (user == null) return;

      // 1) Candidatos: pedidos delivered nas últimas 48h.
      final since = DateTime.now()
          .toUtc()
          .subtract(const Duration(hours: 48))
          .toIso8601String();
      final List<dynamic> candidateRows = await supabase
          .from('orders')
          .select()
          .eq('user_id', user.id)
          .eq('status', 'delivered')
          .gte('delivered_at', since)
          .order('delivered_at', ascending: false);
      if (!mounted) return;
      if (candidateRows.isEmpty) return;

      // 2) Subjects já avaliados por este utilizador para estes pedidos.
      final orderIds = candidateRows
          .map((r) => (r as Map)['id'] as String?)
          .whereType<String>()
          .toList();
      if (orderIds.isEmpty) return;
      final List<dynamic> ratedRows = await supabase
          .from('ratings')
          .select('order_id, subject_type')
          .eq('rater_user_id', user.id)
          .inFilter('order_id', orderIds);
      final ratedBySubject = <String, Set<String>>{};
      for (final r in ratedRows) {
        final m = (r as Map);
        final oid = m['order_id'] as String?;
        final st = m['subject_type'] as String?;
        if (oid == null || st == null) continue;
        ratedBySubject.putIfAbsent(oid, () => <String>{}).add(st);
      }

      // 3) Skip counters (anti-spam).
      final prefs = await SharedPreferences.getInstance();

      // 4) Procurar primeiro pedido com pelo menos um sujeito pendente.
      for (final raw in candidateRows) {
        final row = (raw as Map).cast<String, dynamic>();
        final orderId = row['id'] as String?;
        if (orderId == null) continue;

        final skipKey = 'rating_skipped_${orderId}_count';
        if ((prefs.getInt(skipKey) ?? 0) >= 2) continue;

        final order = OrderModel.fromSupabase(row);
        final rated = ratedBySubject[orderId] ?? const <String>{};
        final driverId = order.assignedDriverId;
        final restaurantId = row['restaurant_id'] as String?;
        final needsDriver = driverId != null &&
            driverId.isNotEmpty &&
            !rated.contains('driver');
        final needsPartner = order.isPartnerStore &&
            restaurantId != null &&
            restaurantId.isNotEmpty &&
            !rated.contains('partner');

        if (!needsDriver && !needsPartner) continue;

        await Future<void>.delayed(const Duration(milliseconds: 1200));
        if (!mounted) return;

        var anySkipped = false;
        if (needsDriver) {
          final result = await Navigator.of(context).push<bool>(
            MaterialPageRoute<bool>(
              builder: (_) => RatingScreen(
                order: order,
                subjectType: RatingSubjectType.driver,
                subjectId: driverId,
              ),
            ),
          );
          if (result != true) anySkipped = true;
        }
        if (!mounted) return;
        if (needsPartner) {
          final result = await Navigator.of(context).push<bool>(
            MaterialPageRoute<bool>(
              builder: (_) => RatingScreen(
                order: order,
                subjectType: RatingSubjectType.partner,
                subjectId: restaurantId,
              ),
            ),
          );
          if (result != true) anySkipped = true;
        }

        if (anySkipped) {
          await prefs.setInt(
              skipKey, (prefs.getInt(skipKey) ?? 0) + 1);
        }
        break; // only ever ask about one order per app open
      }
    } catch (e) {
      debugPrint('[unrated_orders] $e');
    } finally {
      _ratingCheckInFlight = false;
    }
  }

  /// Pre-fills the CartStore delivery address on startup.
  /// Priority: 1) cart já preenchido  2) client_addresses default
  ///           3) Casa (SessionStore legacy)  4) GPS
  Future<void> _detectLocation() async {
    if (!mounted) return;
    final cartStore = context.read<CartStore>();

    if (cartStore.dropoffStreet.isNotEmpty) return;

    // 2) endereço default em client_addresses (padrão Uber/Glovo).
    try {
      final list = await ClientAddressService.instance.list();
      if (!mounted) return;
      if (cartStore.dropoffStreet.isNotEmpty) return;
      final defaultAddr = list.where((a) => a.isDefault).cast<ClientAddress?>()
          .firstWhere((_) => true, orElse: () => null);
      if (defaultAddr != null) {
        cartStore.updateDeliveryAddress(
          street: defaultAddr.address,
          city: defaultAddr.city ?? '',
          postalCode: defaultAddr.postalCode ?? '',
          location: (defaultAddr.lat != null && defaultAddr.lng != null)
              ? LatLng(defaultAddr.lat!, defaultAddr.lng!)
              : null,
        );
        return;
      }
    } catch (_) {/* sem rede ou sem auth — cai para Casa/GPS */}

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
    // L3 — troca de modo, não "Sair": preserva biometria.
    authStore.logout(wipeBiometrics: false);
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
      backgroundColor: AppColors.background,
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
                    onHeader: true,
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
                  _buildTvdeEntry(context),
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
        imageAsset: 'assets/categories/cat_restaurantes.png',
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
        imageAsset: 'assets/categories/cat_supermercados.png',
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
        imageAsset: 'assets/categories/cat_farmacia.png',
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
        label: 'Lojas',
        gradient: AppColors.tileStores,
        imageAsset: 'assets/categories/cat_lojas.png',
        onTap: () => _navigateWithAddressGuard(() {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => const StoresScreen(
                  initialCategory: BusinessCategory.store),
            ),
          );
        }),
      ),
      _TileData(
        label: 'Enviar\nEncomenda',
        gradient: AppColors.tileSendPackage,
        imageAsset: 'assets/categories/cat_encomenda.png',
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
        imageAsset: 'assets/categories/cat_compras.png',
        onTap: () => _navigateWithAddressGuard(() {
          Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const CarryGroceriesScreen()),
          );
        }),
      ),
      _TileData(
        label: 'Favores',
        gradient: AppColors.tileErrand,
        imageAsset: 'assets/categories/cat_favores.png',
        onTap: () => _navigateWithAddressGuard(() {
          Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const ErrandFormScreen()),
          );
        }),
      ),
      _TileData(
        label: 'Reservar\nMesa',
        gradient: AppColors.tileReserveTable,
        imageAsset: 'assets/categories/cat_reservar_mesa.png',
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
      _TileData(
        label: 'Beleza',
        gradient: AppColors.tileServices,
        imageAsset: 'assets/categories/cat_beleza.png',
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const ServicesCategoryScreen()),
        ),
      ),
      _TileData(
        label: 'Limpeza',
        gradient: AppColors.tileCleaning,
        imageAsset: 'assets/categories/cat_limpeza.png',
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const CleaningBookingsScreen()),
        ),
      ),
    ];

    // TVDE — categoria ESCONDIDA: só aparece quando o admin aprovou tvde_access.
    if (context.watch<TvdeStore>().tvdeAccess) {
      tiles.add(
        _TileData(
          label: 'Bora\nMotorista',
          gradient: AppColors.tileServices,
          imageAsset: 'assets/categories/cat_motorista.png',
          onTap: () => _navigateWithAddressGuard(() {
            Navigator.push(
              context,
              MaterialPageRoute(
                  builder: (_) => const TvdeRequestRideScreen()),
            );
          }),
        ),
      );
    }

    return GridView.count(
      crossAxisCount: 3,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      crossAxisSpacing: Spacing.md,
      mainAxisSpacing: Spacing.md,
      childAspectRatio: 0.95,
      children: tiles.map((t) {
        if (t.imageAsset != null) {
          return BoraTileCard.image(
            label: t.label,
            gradient: t.gradient,
            imageAsset: t.imageAsset!,
            onTap: t.onTap,
          );
        }
        // Fallback legacy (ainda sem PNG da categoria) — ver TODO no tile.
        // ignore: deprecated_member_use_from_same_package
        return BoraTileCard(
          label: t.label,
          gradient: t.gradient,
          iconData: t.iconData,
          onTap: t.onTap,
        );
      }).toList(),
    );
  }

  /// TVDE — entrada DISCRETA para desbloquear a categoria escondida.
  /// Só aparece enquanto o cliente ainda não tem acesso aprovado.
  Widget _buildTvdeEntry(BuildContext context) {
    final store = context.watch<TvdeStore>();
    if (store.tvdeAccess) return const SizedBox.shrink();

    final pending = store.accessRequestStatus == 'pendente';
    return Padding(
      padding: const EdgeInsets.only(top: Spacing.md),
      child: InkWell(
        borderRadius: BorderRadius.circular(Radii.md),
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const TvdeUnlockScreen()),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(
              vertical: Spacing.sm, horizontal: Spacing.xs),
          child: Row(
            children: [
              Icon(pending ? Icons.hourglass_top : Icons.lock_open,
                  size: 18, color: AppColors.textSecondary),
              const SizedBox(width: Spacing.sm),
              Expanded(
                child: Text(
                  pending
                      ? 'Pedido de categoria exclusiva em análise'
                      : 'Quero desbloquear uma categoria exclusiva',
                  style: TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 13,
                      fontWeight: FontWeight.w500),
                ),
              ),
              Icon(Icons.chevron_right,
                  size: 18, color: AppColors.textSubtle),
            ],
          ),
        ),
      ),
    );
  }
}

// ─── Internal ──────────────────────────────────────────────────────────────

class _TileData {
  _TileData({
    required this.label,
    required this.gradient,
    required this.onTap,
    this.imageAsset,
    this.iconData,
  }) : assert(imageAsset != null || iconData != null,
            'tile precisa de imageAsset ou iconData');

  final String label;
  final Gradient gradient;
  final VoidCallback onTap;

  /// Asset PNG 3D (preferido). Quando ausente, usa [iconData] no tile legacy.
  final String? imageAsset;

  /// Fallback enquanto o asset PNG da categoria não existir (ex.: Serviços).
  final IconData? iconData;
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
  List<ClientAddress> _savedAddresses = const [];
  bool _loadingSaved = true;

  @override
  void initState() {
    super.initState();
    _loadSavedAddresses();
  }

  Future<void> _loadSavedAddresses() async {
    try {
      final list = await ClientAddressService.instance.list();
      if (mounted) {
        setState(() {
          _savedAddresses = list;
          _loadingSaved = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loadingSaved = false);
    }
  }

  void _useSaved(ClientAddress a) {
    final LatLng? loc = (a.lat != null && a.lng != null)
        ? LatLng(a.lat!, a.lng!)
        : null;
    context.read<CartStore>().updateDeliveryAddress(
          street: a.address,
          city: a.city ?? '',
          postalCode: a.postalCode ?? '',
          location: loc,
        );
    Navigator.of(context).pop();
  }

  Future<void> _openManageAddresses() async {
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const ClientAddressesScreen()),
    );
    // Reload after returning — utilizador pode ter adicionado/editado.
    await _loadSavedAddresses();
  }

  Widget _savedAddressTile(ThemeData theme, ClientAddress a) {
    final icon = switch (a.label.toLowerCase()) {
      'casa' || 'home' => Icons.home_rounded,
      'trabalho' || 'work' => Icons.work_rounded,
      _ => Icons.place_rounded,
    };
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 4),
      child: ListTile(
        leading: Icon(icon, color: theme.colorScheme.primary),
        title: Row(
          children: [
            Flexible(
              child: Text(a.label,
                  style: const TextStyle(fontWeight: FontWeight.w700)),
            ),
            if (a.isDefault) ...[
              const SizedBox(width: 6),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.green.shade100,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Text('Predefinido',
                    style: TextStyle(fontSize: 10, color: Colors.green)),
              ),
            ],
          ],
        ),
        subtitle: Text(
          a.address,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
        trailing: const Icon(Icons.chevron_right),
        onTap: () => _useSaved(a),
      ),
    );
  }

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
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        elevation: 0,
        flexibleSpace: const DecoratedBox(
          decoration: BoxDecoration(gradient: AppColors.headerGradient),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.all(Spacing.lg),
        children: [
          // ── Endereços guardados (client_addresses) ─────────────────────
          if (_loadingSaved)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 12),
              child: Center(
                child: SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
            )
          else if (_savedAddresses.isNotEmpty) ...[
            Padding(
              padding: const EdgeInsets.only(left: 4, bottom: 4),
              child: Text(
                'Os meus endereços',
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            for (final a in _savedAddresses) _savedAddressTile(theme, a),
            const SizedBox(height: 8),
          ],
          ListTile(
            leading: const Icon(Icons.edit_location_alt_outlined),
            title: const Text('Gerir endereços'),
            subtitle: const Text('Adicionar, editar ou eliminar'),
            trailing: const Icon(Icons.chevron_right),
            onTap: _openManageAddresses,
          ),
          const Divider(height: Spacing.xl),
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
          // "Casa" legacy (SessionStore) — escondido se já há endereços
          // guardados em client_addresses (cliente migrou para o novo).
          if (_savedAddresses.isEmpty)
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
              trailing: session.hasHomeAddress
                  ? const Icon(Icons.chevron_right)
                  : null,
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
