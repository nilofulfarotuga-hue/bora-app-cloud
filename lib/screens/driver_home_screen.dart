import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart' hide LatLng;
import 'package:vibration/vibration.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show Supabase;

import '../auth/auth_store.dart';
import 'package:url_launcher/url_launcher.dart';
import '../utils/map_utils.dart';

import '../models/chat_message.dart';
import '../models/driver_model.dart';
import '../models/order_model.dart';
import '../services/navigation_service.dart';
import '../services/sound_service.dart';
import '../stores/driver_store.dart';
import '../stores/order_store.dart';
import '../stores/session_store.dart';
import 'chat_screen.dart';
import 'driver_earnings_screen.dart';
import 'driver_map_screen.dart';
import 'driver_order_action_helper.dart';

class DriverHomeScreen extends StatefulWidget {
  const DriverHomeScreen({super.key});

  @override
  State<DriverHomeScreen> createState() => _DriverHomeScreenState();
}

class _DriverHomeScreenState extends State<DriverHomeScreen> {
  Set<String> _knownOrderIds = {};
  bool _isShowingDialog = false;
  String? _highlightedOrderId;
  final SoundService _soundService = SoundService();
  final Set<String> _processingOrderIds = {};
  StreamSubscription<Position>? _positionSubscription;
  OrderStore? _orderStore; // held so we can remove the listener in dispose

  /// GPS position obtained via getCurrentPosition() at startup.
  /// Used as the idle-map initial camera center so the map opens on the
  /// driver's real location instead of the default fallback.
  LatLng? _initialGpsCenter;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;

      // ── FIX: Ensure DriverStore has the current driver configured.
      // On session restore (app restart, hot reload), AuthStore restores
      // currentDriver from SharedPreferences but nobody calls
      // configurePrimaryDriver on DriverStore. This leaves _primaryDriverId
      // as 'driver-main' and _drivers empty, causing getDriverById to
      // return null and availableOrders to return an empty list.
      //
      // This sync runs once on screen init and is idempotent — if the
      // driver is already configured, configurePrimaryDriver just updates.
      _ensureDriverConfigured();

      // Attach a store listener so _handleNewOrders runs exactly once per
      // store change — not on every build frame. This prevents stale closure
      // accumulation from addPostFrameCallback inside build().
      _orderStore = context.read<OrderStore>();
      _orderStore!.addListener(_onOrderStoreChanged);
      _orderStore!.loadOrders();
      // Seed with current state in case orders already exist.
      _onOrderStoreChanged();
    });
    _startIdleLocationTracking();
    _fetchInitialGpsCenter();
  }

  void _onOrderStoreChanged() {
    if (!mounted) return;
    final store = _orderStore;
    if (store == null) return;
    // Process new orders immediately — OrderStore via context.watch already
    // handles rebuild scheduling, and setState in _handleNewOrders is safe
    // because it's now guarded by _isShowingDialog check.
    final orders = store.availableOrders;
    _handleNewOrders(orders, store);
  }

  /// One-shot position request so the idle map opens centred on the driver's
  /// real GPS coordinates. Runs in parallel with the stream subscription.
  Future<void> _fetchInitialGpsCenter() async {
    try {
      // Quick service + permission check before issuing a hardware request.
      if (!await Geolocator.isLocationServiceEnabled()) {
        _resolveGpsFallback();
        return;
      }
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        _resolveGpsFallback();
        return;
      }

      final pos = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      );
      if (!mounted) return;
      final gps = LatLng(pos.latitude, pos.longitude);
      setState(() => _initialGpsCenter = gps);
      // Propagate to DriverStore so the idle-map marker is also correct.
      final driverStore = context.read<DriverStore>();
      driverStore.updateDriverLocation(driverStore.currentDriverId, gps);
    } catch (_) {
      // Hardware unavailable — resolve with DriverStore fallback.
      _resolveGpsFallback();
    }
  }

  void _resolveGpsFallback() {
    if (!mounted) return;
    final driverStore = context.read<DriverStore>();
    final fallback = driverStore.currentDriver?.location;
    if (fallback != null) {
      setState(() => _initialGpsCenter = fallback);
    } else {
      // Último recurso — centro padrão.
      setState(() => _initialGpsCenter = const LatLng(38.7223, -9.1393));
    }
  }

  /// Syncs DriverStore with AuthStore so the current driver always exists
  /// in the _drivers list with the correct ID.
  void _ensureDriverConfigured() {
    final authStore = context.read<AuthStore>();
    final driverStore = context.read<DriverStore>();
    final driver = authStore.currentDriver;
    if (driver == null) return;

    // Use the Supabase auth user ID if available — this matches the ID
    // stored in the 'drivers' table and used by registerDriverAsync.
    final authUserId = Supabase.instance.client.auth.currentUser?.id;

    driverStore.configurePrimaryDriver(
      name: driver.name,
      phone: driver.phone,
      vehicleType: driver.vehicleType,
      licensePlate: driver.licensePlate,
      driverId: authUserId,
    );

    debugPrint(
      'DriverHomeScreen: ensureDriverConfigured — '
      'id=${driverStore.currentDriverId}, '
      'name=${driver.name}, '
      'authUid=$authUserId',
    );
  }

  @override
  void dispose() {
    _orderStore?.removeListener(_onOrderStoreChanged);
    _positionSubscription?.cancel();
    _soundService.dispose();
    super.dispose();
  }

  /// Keeps driver location in DriverStore fresh while on the home screen.
  /// Low frequency (10 m filter) — the active-delivery map uses 5 m.
  /// Includes GPS service + permission checks with user-facing guidance.
  Future<void> _startIdleLocationTracking() async {
    // GPS service check.
    final serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      if (mounted) {
        _resolveGpsFallback();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
                'GPS desativado. Ative a localização para ver a sua posição.'),
            duration: Duration(seconds: 8),
            action: SnackBarAction(
              label: 'Ativar',
              onPressed: Geolocator.openLocationSettings,
            ),
          ),
        );
      }
      return;
    }

    // Permission check.
    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    if (!mounted) return;

    if (permission == LocationPermission.deniedForever) {
      _resolveGpsFallback();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
              'Permissão de localização bloqueada. Ative nas definições.'),
          duration: Duration(seconds: 8),
          action: SnackBarAction(
            label: 'Definições',
            onPressed: Geolocator.openAppSettings,
          ),
        ),
      );
      return;
    }
    if (permission == LocationPermission.denied) {
      _resolveGpsFallback();
      return;
    }

    // Platform-specific settings (no foreground notification on idle screen).
    final LocationSettings locationSettings;
    if (defaultTargetPlatform == TargetPlatform.android) {
      locationSettings = AndroidSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 10,
        intervalDuration: const Duration(seconds: 5),
      );
    } else {
      locationSettings = const LocationSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 10,
      );
    }

    _positionSubscription = Geolocator.getPositionStream(
      locationSettings: locationSettings,
    ).listen((position) {
      if (!mounted) return;
      final driverStore = context.read<DriverStore>();
      driverStore.updateDriverLocation(
        driverStore.currentDriverId,
        LatLng(position.latitude, position.longitude),
      );
    });
  }

  Future<void> _handleTestMode() async {
    final authStore = context.read<AuthStore>();
    final sessionStore = context.read<SessionStore>();
    authStore.logout();
    await sessionStore.clearRole();
    if (!mounted) return;
    Navigator.of(context).popUntil((route) => route.isFirst);
  }

  @override
  Widget build(BuildContext context) {
    // ── Approval gate — block non-approved drivers ─────────────────────────
    final driverStatus = context.watch<AuthStore>().currentDriverStatus;
    if (driverStatus != DriverStatus.approved) {
      return _buildPendingScreen(context, driverStatus);
    }

    final theme = Theme.of(context);
    final switchModeColor = theme.appBarTheme.foregroundColor ?? theme.colorScheme.onPrimary;
    final orderStore = context.watch<OrderStore>();
    // PERFORMANCE: read DriverStore (no full subscription) and use scoped
    // selectors below. The unscoped watch was rebuilding the entire screen
    // (incl. GoogleMap) on every animation step of EVERY driver received via
    // the `drivers` realtime channel — a constant 10–60 rebuilds/second when
    // multiple drivers are online. select() rebuilds only when the selected
    // value actually changes, eliminating cross-driver noise.
    final driverStore = context.read<DriverStore>();
    final vehicleType = context.select<DriverStore, VehicleType>(
      (s) => s.currentVehicleType,
    );
    final tokenBalance = context.select<DriverStore, int>(
      (s) => s.tokenBalance,
    );
    final availableOrders = orderStore.availableOrders;
    final myOrders = orderStore.myOrders;
    final isAvailable = orderStore.isDriverAvailable;
    final highlightedOrder = _findOrderById(availableOrders, _highlightedOrderId);
    final canInteractWithOrders = isAvailable;
    final List<OrderModel> otherOrders = highlightedOrder == null
        ? availableOrders
        : availableOrders
            .where((order) => order.id != highlightedOrder.id)
            .toList();

    // Idle map mode — no active orders, no incoming offers.
    // Shows a full-screen map like Uber/Glovo. Reverts automatically when
    // orders appear because availableOrders / myOrders are watched above.
    if (myOrders.isEmpty && availableOrders.isEmpty) {
      return _buildIdleMapScaffold(
        context,
        driverStore,
        orderStore,
        isAvailable,
        tokenBalance,
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text("Painel do Estafeta"),
        actions: [
          TextButton.icon(
            onPressed: _handleTestMode,
            style: TextButton.styleFrom(
              foregroundColor: switchModeColor,
              padding: const EdgeInsets.symmetric(horizontal: 12),
            ),
            icon: Icon(Icons.bug_report_outlined, color: switchModeColor),
            label: const Text('Teste'),
          ),
          Row(
            children: [
              Text(
                isAvailable ? "Online" : "Offline",
                style: const TextStyle(fontSize: 12),
              ),
              Switch(
                value: isAvailable,
                onChanged: (value) {
                  orderStore.toggleDriverAvailability(value);
                },
              ),
            ],
          ),
          // Token balance chip — uses scoped selector value (no full watch).
          _TokenChip(balance: tokenBalance),
          IconButton(
            tooltip: "Ganhos",
            icon: const Icon(Icons.bar_chart),
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => const DriverEarningsScreen(),
                ),
              );
            },
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Card(
              margin: const EdgeInsets.only(bottom: 16),
              child: ListTile(
                leading: Icon(
                  vehicleType == VehicleType.car
                      ? Icons.directions_car
                      : Icons.motorcycle,
                ),
                title: Text('Veículo: ${vehicleType.label}'),
                subtitle: Text(
                  vehicleType == VehicleType.car
                      ? 'Pode aceitar todos os serviços disponíveis.'
                      : 'Disponível para restaurantes e pequenas entregas.',
                ),
              ),
            ),
            if (myOrders.isNotEmpty) ...[
              for (final order in myOrders) ...[
                Expanded(
                  child: _buildActiveOrderCard(context, orderStore, order),
                ),
                const SizedBox(height: 16),
              ],
            ] else ...[
              const Text(
                "Pedidos disponíveis",
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                ),
              ),
              const SizedBox(height: 12),
              Expanded(
                child: ListView(
                  children: [
                    if (highlightedOrder != null) ...[
                      _DriverOrderAlertCard(
                        key: ValueKey(highlightedOrder.id),
                        order: highlightedOrder,
                        isEnabled: canInteractWithOrders,
                        onAccept: () async {
                          await _handleAcceptOrder(
                            highlightedOrder,
                            orderStore,
                            driverStore,
                            isAvailable,
                          );
                        },
                        onReject: () =>
                            _handleRejectOrder(highlightedOrder, orderStore),
                      ),
                      const SizedBox(height: 16),
                    ],
                    if (highlightedOrder == null && otherOrders.isEmpty)
                      _buildEmptyState(myOrders.isNotEmpty)
                    else
                      ...otherOrders.map(
                        (order) => _AvailableOrderCard(
                          key: ValueKey(order.id),
                          order: order,
                          isEnabled: canInteractWithOrders,
                          onAccept: () async {
                            await _handleAcceptOrder(
                              order,
                              orderStore,
                              driverStore,
                              isAvailable,
                            );
                          },
                          onReject: () =>
                              _handleRejectOrder(order, orderStore),
                        ),
                      ),
                    if (orderStore.completedOrders.isNotEmpty) ...[
                      const SizedBox(height: 24),
                      const Text(
                        "Entregas concluídas",
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                        ),
                      ),
                      const SizedBox(height: 8),
                      ...orderStore.completedOrders.map(
                        (order) => ListTile(
                          contentPadding: EdgeInsets.zero,
                          title: Text(order.serviceType.label),
                          subtitle: Text(
                            "€${order.total.toStringAsFixed(2)} • ${order.distanceKm.toStringAsFixed(1)} km",
                          ),
                          trailing: Text(
                            "+€${order.driverEarnings.toStringAsFixed(2)}",
                            style: const TextStyle(fontWeight: FontWeight.bold),
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  /// Shown when the driver account is pending approval or rejected.
  Widget _buildPendingScreen(BuildContext context, DriverStatus status) {
    final isRejected = status == DriverStatus.rejected;
    return Scaffold(
      appBar: AppBar(
        title: const Text('BORA — Estafeta'),
        actions: [
          IconButton(
            icon: const Icon(Icons.logout),
            tooltip: 'Terminar sessão',
            onPressed: () async {
              context.read<AuthStore>().logout();
              await context.read<SessionStore>().clearRole();
            },
          ),
        ],
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                isRejected ? Icons.cancel_outlined : Icons.hourglass_top,
                size: 72,
                color: isRejected ? Colors.red : Colors.orange,
              ),
              const SizedBox(height: 24),
              Text(
                isRejected ? 'Conta rejeitada' : 'Conta em análise',
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
              ),
              const SizedBox(height: 16),
              Text(
                isRejected
                    ? 'A sua candidatura não foi aprovada. Contacte o suporte para mais informações.'
                    : 'A sua conta está a ser verificada pela nossa equipa. Receberá uma notificação quando for aprovada.',
                textAlign: TextAlign.center,
                style: Theme.of(context)
                    .textTheme
                    .bodyMedium
                    ?.copyWith(color: Colors.grey.shade600),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Full-screen map shown when the driver has no active or incoming orders.
  /// Mirrors the Uber/Glovo idle state: clean map + floating status controls.
  Widget _buildIdleMapScaffold(
    BuildContext context,
    DriverStore driverStore,
    OrderStore orderStore,
    bool isAvailable,
    int tokenBalance,
  ) {
    // Block rendering until the one-shot GPS fetch completes so the map
    // never opens at the default fallback coordinates.
    if (_initialGpsCenter == null) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    final driverPos = _initialGpsCenter!;
    final driverName = driverStore.currentDriver?.name ?? 'Estafeta';

    return Scaffold(
      body: Stack(
        children: [
          // ── Full-screen map ───────────────────────────────────────────
          // Markers are rebuilt via a scoped Selector listening ONLY to the
          // current driver's location. Other drivers' realtime updates no
          // longer trigger this scaffold to rebuild.
          Selector<DriverStore, LatLng?>(
            selector: (_, s) => s.currentDriver?.location,
            builder: (_, driverLocation, __) {
              return GoogleMap(
                initialCameraPosition: CameraPosition(
                  target: driverPos.toGMaps(),
                  zoom: 15,
                ),
                myLocationEnabled: true,
                myLocationButtonEnabled: false,
                zoomControlsEnabled: false,
                compassEnabled: false,
                markers: driverLocation != null
                    ? {
                        Marker(
                          markerId: const MarkerId('driver'),
                          position: driverLocation.toGMaps(),
                          icon: BitmapDescriptor.defaultMarkerWithHue(
                              BitmapDescriptor.hueGreen),
                          infoWindow: InfoWindow(title: driverName),
                        ),
                      }
                    : {},
                onMapCreated: (_) {},
              );
            },
          ),

          // ── Top controls ─────────────────────────────────────────────
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Row(
                children: [
                  // Status chip
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 8),
                    decoration: BoxDecoration(
                      color: isAvailable
                          ? Colors.green.shade600
                          : Colors.grey.shade700,
                      borderRadius: BorderRadius.circular(24),
                      boxShadow: const [
                        BoxShadow(
                          color: Color(0x33000000),
                          blurRadius: 8,
                          offset: Offset(0, 2),
                        ),
                      ],
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          width: 8,
                          height: 8,
                          decoration: BoxDecoration(
                            color: isAvailable
                                ? Colors.greenAccent.shade100
                                : Colors.grey.shade400,
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: 6),
                        Text(
                          isAvailable ? 'Online' : 'Offline',
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w700,
                            fontSize: 13,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const Spacer(),
                  // Token balance chip — uses scoped selector value.
                  _TokenChip(balance: tokenBalance),
                  const SizedBox(width: 8),
                  // Earnings shortcut
                  _FloatingIconButton(
                    icon: Icons.bar_chart,
                    tooltip: 'Ganhos',
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                          builder: (_) => const DriverEarningsScreen()),
                    ),
                  ),
                  const SizedBox(width: 8),
                  // Test / switch mode
                  _FloatingIconButton(
                    icon: Icons.bug_report_outlined,
                    tooltip: 'Teste',
                    onTap: _handleTestMode,
                  ),
                ],
              ),
            ),
          ),

          // ── Bottom status card ────────────────────────────────────────
          Positioned(
            left: 16,
            right: 16,
            bottom: MediaQuery.of(context).padding.bottom + 16,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(20),
                boxShadow: const [
                  BoxShadow(
                    color: Color(0x26000000),
                    blurRadius: 16,
                    offset: Offset(0, -2),
                  ),
                ],
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          isAvailable
                              ? 'À espera de pedidos…'
                              : 'Estás offline',
                          style: const TextStyle(
                            fontWeight: FontWeight.w700,
                            fontSize: 15,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          isAvailable
                              ? 'Novos pedidos aparecerão aqui.'
                              : 'Ativa para começar a receber pedidos.',
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.grey.shade600,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Switch(
                    value: isAvailable,
                    onChanged: (v) => orderStore.toggleDriverAvailability(v),
                    activeThumbColor: Colors.green.shade600,
                    activeTrackColor: Colors.green.shade200,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState(bool hasActiveOrder) {
    final message = hasActiveOrder
        ? "Conclua o pedido atual para receber novas entregas."
        : "Nenhum pedido disponível no momento.";

    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.grey.shade100,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Center(
        child: Text(
          message,
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 16),
        ),
      ),
    );
  }

  Widget _buildActiveOrderCard(
    BuildContext context,
    OrderStore orderStore,
    OrderModel order,
  ) {
    final nextAction = resolveDriverOrderAction(orderStore, order);
    final pickupTarget = order.pickupLocation ?? order.destination;
    final deliveryTarget = order.destination;
    final hasPickedUp = order.status.index >= OrderStatus.pickedUp.index;
    final LatLng? navigationTarget = hasPickedUp ? deliveryTarget : pickupTarget;
    final String navigationLabel = hasPickedUp
        ? "Navegar para cliente"
        : "Navegar para recolha";

    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── scrollable content ──────────────────────────────────────
            Expanded(
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      "Entrega em andamento",
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 12,
                      runSpacing: 8,
                      children: [
                        _InfoChip(
                          icon: Icons.restaurant,
                          label: "Serviço",
                          value: order.serviceType.label,
                        ),
                        _InfoChip(
                          icon: Icons.euro,
                          label: "Pedido",
                          value: "€${order.total.toStringAsFixed(2)}",
                        ),
                        _InfoChip(
                          icon: Icons.payments,
                          label: "Ganhos",
                          value: "+€${order.driverEarnings.toStringAsFixed(2)}",
                        ),
                        _InfoChip(
                          icon: Icons.social_distance,
                          label: "Distância",
                          value: "${order.distanceKm.toStringAsFixed(1)} km",
                        ),
                      ],
                    ),
                    if (order.vendorName != null) ...[
                      const SizedBox(height: 12),
                      Text(
                        order.vendorName!,
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                    ],
                    if (order.pickupAddress != null && order.pickupAddress!.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      const Text(
                        "Recolha:",
                        style: TextStyle(fontWeight: FontWeight.w600),
                      ),
                      Text(order.pickupAddress!),
                    ],
                    if (order.dropoffAddress != null && order.dropoffAddress!.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      const Text(
                        "Entrega:",
                        style: TextStyle(fontWeight: FontWeight.w600),
                      ),
                      Text(order.dropoffAddress!),
                    ],
                    if (order.customerNotes != null && order.customerNotes!.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      const Text(
                        "Nota do cliente:",
                        style: TextStyle(fontWeight: FontWeight.w600),
                      ),
                      Text(order.customerNotes!),
                    ],
                    if (order.apartmentDelivery) ...[
                      const SizedBox(height: 12),
                      const _ApartmentDeliveryBanner(),
                    ],
                    const SizedBox(height: 16),
                    Text("Status atual: ${order.status.label}"),
                    if (order.isPurchaseFinalized) ...[
                      const SizedBox(height: 8),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 8),
                        decoration: BoxDecoration(
                          color: Colors.green.shade50,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: Colors.green.shade200),
                        ),
                        child: Row(
                          children: [
                            Icon(Icons.check_circle_outline,
                                color: Colors.green.shade700, size: 16),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                order.finalTotal != null
                                    ? 'Compra realizada · Valor: €${order.finalTotal!.toStringAsFixed(2)}'
                                    : 'Compra realizada',
                                style: TextStyle(
                                  color: Colors.green.shade700,
                                  fontWeight: FontWeight.w600,
                                  fontSize: 13,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
            // ── fixed buttons ────────────────────────────────────────────
            const SizedBox(height: 16),
            Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                // Row 1: map + navigation (equal width, never overflow)
                Row(
                  children: [
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed: () {
                          final driverStore = context.read<DriverStore>();
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => const DriverMapScreen(),
                            ),
                          ).then((_) {
                            if (!mounted) return;
                            driverStore.loadTokenBalance();
                          });
                        },
                        icon: const Icon(Icons.map),
                        label: const Text("Ver mapa"),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: navigationTarget == null
                            ? null
                            : () {
                                NavigationService.openNavigationOptions(
                                  context,
                                  navigationTarget,
                                );
                              },
                        icon: const Icon(Icons.navigation),
                        label: Text(navigationLabel),
                      ),
                    ),
                  ],
                ),
                // Row 2: status-advance action (full width, shown when available)
                if (nextAction != null) ...[
                  const SizedBox(height: 8),
                  ElevatedButton(
                    onPressed: _processingOrderIds.contains(order.id)
                        ? null
                        : () async {
                            final messenger = ScaffoldMessenger.of(context);
                            setState(
                                () => _processingOrderIds.add(order.id));
                            final success = await nextAction.execute();
                            if (mounted) {
                              setState(() =>
                                  _processingOrderIds.remove(order.id));
                            }
                            messenger.showSnackBar(
                              SnackBar(
                                content: Text(
                                  success
                                      ? nextAction.successMessage
                                      : "Não foi possível atualizar o pedido.",
                                ),
                              ),
                            );
                          },
                    child: _processingOrderIds.contains(order.id)
                        ? const SizedBox(
                            height: 16,
                            width: 16,
                            child:
                                CircularProgressIndicator(strokeWidth: 2),
                          )
                        : Text(nextAction.label),
                  ),
                ],
                // Row 3: cancel delivery — only while order is driverAccepted
                if (order.status == OrderStatus.driverAccepted) ...[
                  const SizedBox(height: 8),
                  OutlinedButton.icon(
                    onPressed: _processingOrderIds.contains(order.id)
                        ? null
                        : () async {
                            final confirmed =
                                await _confirmCancelDelivery(context);
                            if (!confirmed) return;
                            setState(
                                () => _processingOrderIds.add(order.id));
                            await _handleCancelDelivery(order, orderStore);
                            if (mounted) {
                              setState(() =>
                                  _processingOrderIds.remove(order.id));
                            }
                          },
                    icon: const Icon(Icons.cancel_outlined),
                    label: const Text('Cancelar entrega'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.red,
                      side: const BorderSide(color: Colors.red),
                    ),
                  ),
                ],
              ],
            ),
            const SizedBox(height: 12),
            Text(
              'Telefone do cliente: '
              '${(order.clientPhone ?? '').isNotEmpty ? order.clientPhone! : 'Não disponível'}',
            ),
            const SizedBox(height: 4),
            Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: (order.clientPhone ?? '').isEmpty
                        ? null
                        : () => _callPhone(order.clientPhone!),
                    icon: const Icon(Icons.call),
                    label: const Text('Ligar cliente'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => ChatScreen(
                            order: order,
                            senderType: ChatSenderType.driver,
                          ),
                        ),
                      );
                    },
                    icon: const Icon(Icons.chat_bubble_outline),
                    label: const Text('Chat'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _callPhone(String phone) async {
    final uri = Uri(scheme: 'tel', path: phone);
    // On web, url_launcher routes tel: via window.open internally.
    // On mobile, it hands off to the system dialler.
    final mode = LaunchMode.externalApplication;
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: mode);
    } else if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Não foi possível iniciar a chamada.')),
      );
    }
  }

  Future<bool> _confirmCancelDelivery(BuildContext ctx) async {
    return await showDialog<bool>(
          context: ctx,
          builder: (_) => AlertDialog(
            title: const Text('Cancelar entrega?'),
            content: const Text(
              'O pedido voltará para o sistema e outro estafeta poderá aceitá-lo.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(false),
                child: const Text('Não'),
              ),
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(true),
                style: TextButton.styleFrom(foregroundColor: Colors.red),
                child: const Text('Sim, cancelar'),
              ),
            ],
          ),
        ) ??
        false;
  }

  Future<void> _handleCancelDelivery(
      OrderModel order, OrderStore orderStore) async {
    final success = await orderStore.cancelDelivery(order);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          success
              ? 'Entrega cancelada. Pedido devolvido ao sistema.'
              : 'Não foi possível cancelar a entrega.',
        ),
      ),
    );
  }

  Future<void> _handleAcceptOrder(
    OrderModel order,
    OrderStore orderStore,
    DriverStore driverStore,
    bool isDriverAvailable,
  ) async {
    if (!isDriverAvailable) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            "Fique online para aceitar pedidos.",
          ),
        ),
      );
      return;
    }

    final driver = driverStore.currentDriver;
    if (driver == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("Erro: estafeta não configurado."),
        ),
      );
      return;
    }
    if (!driver.supportsService(order.serviceType, requiresCar: order.requiresCar)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            "Este pedido requer um veículo do tipo carro.",
          ),
        ),
      );
      return;
    }

    debugPrint('[DriverHome] Accept button tapped — order=${order.id}');
    final success = await orderStore.acceptOrder(order);
    if (!success) {
      debugPrint('[DriverHome] acceptOrder failed — order=${order.id}');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("Não foi possível aceitar este pedido."),
        ),
      );
      return;
    }

    if (!mounted) return;

    debugPrint('[DriverHome] acceptOrder success — order=${order.id}');
    unawaited(_soundService.stop());
    // Open map IMMEDIATELY without waiting for state updates.
    // DriverMapScreen renders instantly with driver.location fallback.
    // GPS and order data update in background via animateCamera.
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => const DriverMapScreen(),
      ),
    ).then((_) {
      if (!mounted) return;
      driverStore.loadTokenBalance();
    });
  }

  void _handleRejectOrder(OrderModel order, OrderStore orderStore) {
    orderStore.rejectAvailableOrder(order);
    unawaited(_soundService.stop());
    setState(() => _highlightedOrderId = null);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Text("Pedido rejeitado."),
      ),
    );
  }

  OrderModel? _findOrderById(List<OrderModel> orders, String? id) {
    if (id == null) return null;
    for (final order in orders) {
      if (order.id == id) {
        return order;
      }
    }
    return null;
  }

  void _handleNewOrders(List<OrderModel> orders, OrderStore store) {
    final currentIds = orders.map((o) => o.id).toSet();
    final newIds = currentIds.difference(_knownOrderIds);

    String? highlightCandidate = _highlightedOrderId;
    if (highlightCandidate != null && !currentIds.contains(highlightCandidate)) {
      highlightCandidate = null;
    }

    if (newIds.isNotEmpty) {
      final newestOrders = orders
          .where((order) => newIds.contains(order.id))
          .toList()
        ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
      final newOrder = newestOrders.first;
      highlightCandidate = newOrder.id;

      if (newOrder.status == OrderStatus.callingDriver) {
        unawaited(_triggerNewOrderFeedback(newOrder));
        unawaited(_soundService.playLoop());
      }

      if (!_isShowingDialog) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          _showNewOrderDialog(newOrder, store);
        });
      }
    } else if (highlightCandidate == null && orders.isNotEmpty) {
      highlightCandidate = orders.first.id;
    }

    if (highlightCandidate != _highlightedOrderId && mounted) {
      setState(() {
        _highlightedOrderId = highlightCandidate;
      });
    }

    _knownOrderIds = currentIds;

    // Stop sound as soon as there are no more available orders for this driver
    // (covers: order accepted, order expired, driver rejected last order).
    if (orders.isEmpty) {
      unawaited(_soundService.stop());
    }
  }

  Future<void> _triggerNewOrderFeedback(OrderModel order) async {
    if (order.status != OrderStatus.callingDriver) return;

    try {
      await SystemSound.play(SystemSoundType.alert);
    } catch (_) {}

    try {
      if (await Vibration.hasCustomVibrationsSupport()) {
        await Vibration.vibrate(pattern: [0, 500, 150, 500]);
        return;
      }
      if (await Vibration.hasVibrator()) {
        await Vibration.vibrate(duration: 800);
      }
    } catch (_) {}
  }

  Future<void> _showNewOrderDialog(OrderModel order, OrderStore store) async {
    if (order.status != OrderStatus.callingDriver) {
      return;
    }

    _isShowingDialog = true;

    if (!mounted) {
      _isShowingDialog = false;
      return;
    }

    final description = order.vendorName ?? order.serviceType.label;

    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Novo pedido disponível'),
        content: Text(
          'Um novo pedido de $description está disponível. Deseja verificar? ',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Ok'),
          ),
        ],
      ),
    );

    _isShowingDialog = false;
  }
}

// ── Floating icon button used in idle map overlay ─────────────────────────────

// ─── Token balance chip ───────────────────────────────────────────────────────
// Compact pill showing the driver's current token balance.
// Used in both the AppBar (active orders) and the idle map overlay.

class _TokenChip extends StatelessWidget {
  const _TokenChip({required this.balance});

  final int balance;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: const [
          BoxShadow(
            color: Color(0x33000000),
            blurRadius: 6,
            offset: Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.monetization_on, color: Colors.amber, size: 16),
          const SizedBox(width: 4),
          Text(
            '$balance',
            style: const TextStyle(
              fontWeight: FontWeight.w700,
              fontSize: 13,
            ),
          ),
        ],
      ),
    );
  }
}

class _FloatingIconButton extends StatelessWidget {
  const _FloatingIconButton({
    required this.icon,
    required this.onTap,
    this.tooltip,
  });

  final IconData icon;
  final VoidCallback onTap;
  final String? tooltip;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip ?? '',
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          width: 40,
          height: 40,
          decoration: const BoxDecoration(
            color: Colors.white,
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(
                color: Color(0x33000000),
                blurRadius: 8,
                offset: Offset(0, 2),
              ),
            ],
          ),
          child: Icon(icon, size: 20, color: Colors.black87),
        ),
      ),
    );
  }
}

class _DriverOrderAlertCard extends StatefulWidget {
  const _DriverOrderAlertCard({
    super.key,
    required this.order,
    required this.isEnabled,
    required this.onAccept,
    required this.onReject,
  });

  final OrderModel order;
  final bool isEnabled;
  final Future<void> Function() onAccept;
  final VoidCallback onReject;

  @override
  State<_DriverOrderAlertCard> createState() => _DriverOrderAlertCardState();
}

class _DriverOrderAlertCardState extends State<_DriverOrderAlertCard>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  bool _isLoading = false;
  Timer? _countdownTimer;
  int _secondsLeft = 40;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat(reverse: true);
    _startCountdown();
  }

  void _startCountdown() {
    final expiry = widget.order.driverOfferExpiresAt;
    if (expiry != null) {
      _secondsLeft = expiry.difference(DateTime.now()).inSeconds.clamp(0, 40);
    }
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      final exp = widget.order.driverOfferExpiresAt;
      final secs = exp != null
          ? exp.difference(DateTime.now()).inSeconds.clamp(0, 40)
          : (_secondsLeft - 1).clamp(0, 40);
      setState(() => _secondsLeft = secs);
      if (_secondsLeft <= 0) {
        _countdownTimer?.cancel();
        widget.onReject();
      }
    });
  }

  @override
  void dispose() {
    _countdownTimer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final order = widget.order;
    final baseColor = Colors.orange.shade50;
    final highlightColor = Colors.orange.shade200.withOpacity(0.9);

    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        final t = _controller.value;
        final backgroundColor = Color.lerp(baseColor, highlightColor, t);
        final borderColor =
            Color.lerp(Colors.orange.shade400, Colors.orange.shade700, t) ??
                Colors.orange.shade500;
        final shadowColor = Colors.orange.withOpacity(0.25 + (0.25 * t));

        return Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: backgroundColor,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: borderColor, width: 2),
            boxShadow: [
              BoxShadow(
                color: shadowColor,
                blurRadius: 24,
                spreadRadius: 1,
                offset: const Offset(0, 12),
              ),
            ],
          ),
          child: child,
        );
      },
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.notifications_active,
                          color: Colors.orange.shade800,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          "Novo pedido disponível",
                          style: theme.textTheme.titleMedium?.copyWith(
                                fontWeight: FontWeight.bold,
                                color: Colors.orange.shade900,
                              ) ??
                              TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                                color: Colors.orange.shade900,
                              ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      order.serviceType.label,
                      style: theme.textTheme.titleLarge?.copyWith(
                            fontWeight: FontWeight.w700,
                          ) ??
                          const TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.w700,
                          ),
                    ),
                    if (order.vendorName != null &&
                        order.vendorName!.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(
                        order.vendorName!,
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                    if (order.pickupAddress != null &&
                        order.pickupAddress!.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      Text(
                        "Recolha: ${order.pickupAddress!}",
                        style: theme.textTheme.bodyMedium,
                      ),
                    ],
                    if (order.dropoffAddress != null &&
                        order.dropoffAddress!.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(
                        "Entrega: ${order.dropoffAddress!}",
                        style: theme.textTheme.bodyMedium,
                      ),
                    ],
                    if (order.customerNotes != null &&
                        order.customerNotes!.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      Text(
                        "Nota do cliente:",
                        style: theme.textTheme.bodySmall?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      Text(order.customerNotes!),
                    ],
                    if (order.apartmentDelivery) ...[
                      const SizedBox(height: 12),
                      const _ApartmentDeliveryBanner(),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 16),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    "+€${order.driverEarnings.toStringAsFixed(2)}",
                    style: theme.textTheme.headlineMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                          color: Colors.orange.shade900,
                        ) ??
                        TextStyle(
                          fontSize: 32,
                          fontWeight: FontWeight.bold,
                          color: Colors.orange.shade900,
                        ),
                  ),
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.9),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.social_distance,
                          color: Colors.orange.shade900,
                          size: 18,
                        ),
                        const SizedBox(width: 6),
                        Text(
                          "${order.distanceKm.toStringAsFixed(1)} km",
                          style: theme.textTheme.bodyMedium?.copyWith(
                                fontWeight: FontWeight.bold,
                              ) ??
                              const TextStyle(
                                fontWeight: FontWeight.bold,
                              ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 20),
          _CountdownBar(secondsLeft: _secondsLeft, totalSeconds: 40),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: widget.onReject,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.orange.shade900,
                    side: BorderSide(color: Colors.orange.shade900),
                  ),
                  child: const Text("Rejeitar"),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: ElevatedButton(
                  onPressed: (widget.isEnabled && !_isLoading)
                      ? () async {
                          setState(() => _isLoading = true);
                          await widget.onAccept();
                          if (mounted) setState(() => _isLoading = false);
                        }
                      : null,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.orange.shade700,
                    foregroundColor: Colors.white,
                  ),
                  child: _isLoading
                      ? const SizedBox(
                          height: 16,
                          width: 16,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Text("Aceitar pedido"),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _AvailableOrderCard extends StatefulWidget {
  final OrderModel order;
  final bool isEnabled;
  final Future<void> Function() onAccept;
  final VoidCallback onReject;

  const _AvailableOrderCard({
    super.key,
    required this.order,
    required this.isEnabled,
    required this.onAccept,
    required this.onReject,
  });

  @override
  State<_AvailableOrderCard> createState() => _AvailableOrderCardState();
}

class _AvailableOrderCardState extends State<_AvailableOrderCard> {
  bool _isLoading = false;

  @override
  Widget build(BuildContext context) {
    final order = widget.order;
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              order.serviceType.label,
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
            ),
            if (order.vendorName != null) ...[
              const SizedBox(height: 4),
              Text(order.vendorName!),
            ],
            const SizedBox(height: 8),
            Wrap(
              spacing: 12,
              runSpacing: 8,
              children: [
                _InfoChip(
                  icon: Icons.euro,
                  label: "Total",
                  value: "€${order.total.toStringAsFixed(2)}",
                ),
                _InfoChip(
                  icon: Icons.payments,
                  label: "Ganhos",
                  value: "+€${order.driverEarnings.toStringAsFixed(2)}",
                ),
                _InfoChip(
                  icon: Icons.social_distance,
                  label: "Distância",
                  value: "${order.distanceKm.toStringAsFixed(1)} km",
                ),
              ],
            ),
            if (order.pickupAddress != null && order.pickupAddress!.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text("Recolha: ${order.pickupAddress!}"),
            ],
            if (order.dropoffAddress != null && order.dropoffAddress!.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text("Entrega: ${order.dropoffAddress!}"),
            ],
            if (order.customerNotes != null && order.customerNotes!.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(
                "Nota do cliente:",
                style: TextStyle(color: Colors.grey.shade700),
              ),
              Text(order.customerNotes!),
            ],
            if (order.apartmentDelivery) ...[
              const SizedBox(height: 8),
              const _ApartmentDeliveryBanner(compact: true),
            ],
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: widget.onReject,
                    child: const Text("Rejeitar"),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton(
                    onPressed: (widget.isEnabled && !_isLoading)
                        ? () async {
                            setState(() => _isLoading = true);
                            await widget.onAccept();
                            if (mounted) setState(() => _isLoading = false);
                          }
                        : null,
                    child: _isLoading
                        ? const SizedBox(
                            height: 16,
                            width: 16,
                            child:
                                CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Text("Aceitar pedido"),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _CountdownBar extends StatelessWidget {
  const _CountdownBar({
    required this.secondsLeft,
    required this.totalSeconds,
  });

  final int secondsLeft;
  final int totalSeconds;

  @override
  Widget build(BuildContext context) {
    final progress =
        totalSeconds > 0 ? (secondsLeft / totalSeconds).clamp(0.0, 1.0) : 0.0;
    final isUrgent = secondsLeft <= 10;
    final color = isUrgent ? Colors.red.shade600 : Colors.orange.shade700;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Icon(Icons.timer_outlined, size: 16, color: color),
            const SizedBox(width: 6),
            Text(
              'Expira em ${secondsLeft}s',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: color,
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: LinearProgressIndicator(
            value: progress,
            backgroundColor: Colors.orange.shade100,
            valueColor: AlwaysStoppedAnimation<Color>(color),
            minHeight: 6,
          ),
        ),
      ],
    );
  }
}

class _ApartmentDeliveryBanner extends StatelessWidget {
  const _ApartmentDeliveryBanner({this.compact = false});

  final bool compact;

  @override
  Widget build(BuildContext context) {
    final background = Colors.orange.shade50;
    final borderColor = Colors.orange.shade200;
    final iconColor = Colors.orange.shade600;
    final textStyle = Theme.of(context).textTheme.bodyMedium?.copyWith(
          fontWeight: FontWeight.w600,
          color: Colors.orange.shade800,
        );

    return Container(
      width: double.infinity,
      padding: EdgeInsets.symmetric(
        vertical: compact ? 8 : 12,
        horizontal: compact ? 12 : 16,
      ),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: borderColor),
      ),
      child: Row(
        children: [
          Icon(Icons.apartment, color: iconColor),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              "Apartment delivery requested — +€1 bonus",
              style: textStyle,
            ),
          ),
        ],
      ),
    );
  }
}

class _InfoChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;

  const _InfoChip({
    required this.icon,
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.grey.shade200,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: Colors.grey.shade800),
          const SizedBox(width: 6),
          Text(
            "$label: $value",
            style: const TextStyle(fontSize: 12),
          ),
        ],
      ),
    );
  }
}