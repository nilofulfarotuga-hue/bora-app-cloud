import 'dart:async';

import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart' hide LatLng;
import 'package:latlong2/latlong.dart' as ll;
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show Supabase;

import '../config/app_colors.dart';
import '../config/app_spacing.dart';
import '../models/chat_message.dart';
import '../models/driver_model.dart';
import '../models/order_model.dart';
import '../models/rating_model.dart';
import '../widgets/address_text.dart';
import '../widgets/bora_support_fab.dart';
import '../widgets/errand_budget_banner.dart';
import '../widgets/takeaway/pickup_code_card.dart';
import '../widgets/takeaway/preparing_countdown_banner.dart';
import '../services/directions_service.dart';
import '../services/order_eta_service.dart';
import '../stores/driver_store.dart';
import '../stores/order_store.dart';
import '../utils/constants.dart';
import '../utils/map_marker_helper.dart';
import '../utils/map_utils.dart';
import '../services/notification_service.dart';
import '../widgets/chat_bubble_button.dart';
import 'chat_screen.dart';
import 'rating_screen.dart';

import '../l10n/tr.dart';

class OrderTrackingScreen extends StatefulWidget {
  const OrderTrackingScreen({super.key, required this.order});

  final OrderModel order;

  @override
  State<OrderTrackingScreen> createState() => _OrderTrackingScreenState();
}

class _OrderTrackingScreenState extends State<OrderTrackingScreen> {
  final Completer<GoogleMapController> _mapController = Completer();
  final DirectionsService _directionsService = DirectionsService();

  List<ll.LatLng> _routePoints = <ll.LatLng>[];
  String? _activeRouteKey;
  int _routeRequestId = 0;
  ll.LatLng? _lastCameraDriver;
  ll.LatLng? _lastCameraTarget;
  bool _ratingNavigated = false;

  // BUG #3 (sessão exec post-test 2026-05-12) — fallback fetch para o nome
  // do estafeta quando DriverStore.getDriverById retorna null (driver não
  // está carregado em memória mas existe em DB).
  String? _fetchedDriverName;
  // BLOCO 3 — veículo + matrícula do estafeta para o cliente ver no tracking
  // (padrão Uber/Glovo). Vêm do mesmo fetch best-effort do nome.
  String? _fetchedVehicleType;
  String? _fetchedLicensePlate;
  // Avaliação REAL do estafeta (era um '4.9' fixo — a tela nunca inventa).
  double? _fetchedAvgRating;
  String? _fetchedFor;

  // ── Waze-style camera (BUG B) — client overview pose ────────────────────
  // Wider than driver's pose so origin+destination+driver fit on screen.
  static const double _wazeZoom = 16.5;
  static const double _wazeTilt = 30.0;
  static const Duration _followResumeDelay = Duration(seconds: 15);
  bool _followCamera = true;
  Timer? _followResumeTimer;
  bool _programmaticMove = false;
  Timer? _programmaticMoveTimer;

  @override
  void initState() {
    super.initState();
    MapMarkerHelper.preload();
    // [31/08] carrega as chaves eta_* das definições (uma vez, best-effort).
    OrderEtaService.ensureConfigured();
  }

  /// BUG #3 + BLOCO 3 — Best-effort fetch de nome/veículo/matrícula do estafeta
  /// quando DriverStore não tem o driver carregado. Idempotente (cache por
  /// driverId). Silencioso: se falhar, cai nos defaults ('Estafeta', sem veículo).
  Future<void> _maybeFetchDriverInfo(String driverId) async {
    if (_fetchedFor == driverId) return;
    _fetchedFor = driverId;
    try {
      final row = await Supabase.instance.client
          .from('drivers')
          .select('name, vehicle_type, license_plate, avg_rating')
          .eq('id', driverId)
          .maybeSingle();
      if (row == null || !mounted) return;
      setState(() {
        final name = row['name'] as String?;
        if (name != null && name.isNotEmpty) _fetchedDriverName = name;
        _fetchedVehicleType = row['vehicle_type'] as String?;
        _fetchedLicensePlate = row['license_plate'] as String?;
        _fetchedAvgRating = (row['avg_rating'] as num?)?.toDouble();
      });
    } catch (_) {/* silent — falls back to 'Estafeta' */}
  }

  @override
  void dispose() {
    _directionsService.dispose();
    _followResumeTimer?.cancel();
    _programmaticMoveTimer?.cancel();
    super.dispose();
  }

  Future<void> _animateCameraProgrammatic(CameraUpdate update) async {
    _programmaticMove = true;
    _programmaticMoveTimer?.cancel();
    _programmaticMoveTimer = Timer(const Duration(milliseconds: 250), () {
      _programmaticMove = false;
    });
    if (!_mapController.isCompleted) return;
    final controller = await _mapController.future;
    await controller.animateCamera(update);
  }

  CameraUpdate _wazeCameraUpdate(ll.LatLng target) =>
      CameraUpdate.newCameraPosition(CameraPosition(
        target: target.toGMaps(),
        zoom: _wazeZoom,
        tilt: _wazeTilt,
        bearing: 0, // client view is north-up
      ));

  void _onUserCameraMoveStarted() {
    if (_programmaticMove) return;
    _followResumeTimer?.cancel();
    _followResumeTimer = Timer(_followResumeDelay, () {
      if (!mounted) return;
      setState(() => _followCamera = true);
      // Force a re-fit on next build by clearing the dedup memo.
      _lastCameraDriver = null;
      _lastCameraTarget = null;
    });
    if (_followCamera) {
      setState(() => _followCamera = false);
    }
  }

  void _onRecenter() {
    _followResumeTimer?.cancel();
    setState(() => _followCamera = true);
    _lastCameraDriver = null;
    _lastCameraTarget = null;
    // Force an immediate camera refresh on the next frame.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) setState(() {});
    });
  }

  OrderModel _freshOrder(OrderStore orderStore) {
    try {
      return orderStore.orders.firstWhere((o) => o.id == widget.order.id);
    } catch (_) {
      return widget.order;
    }
  }

  // BR §26.2 — Auto-abrir ecrã de avaliação após entrega.
  // T2.1: avalia driver E parceiro (sequencial, ambos opcionais skip).
  void _maybeOpenRating(OrderModel order) {
    if (_ratingNavigated) return;
    if (order.status != OrderStatus.delivered) return;
    final driverId = order.assignedDriverId;
    // BLOCO 2.1 — subject_id partner deve ser restaurant_id (UUID), nunca
    // vendor_name. Se restaurantId estiver vazio, NÃO abrir partial rating
    // (evita ambíguos legacy).
    final restaurantId = order.restaurantId;
    final hasPartner = order.isPartnerStore &&
        restaurantId != null &&
        restaurantId.isNotEmpty;
    if ((driverId == null || driverId.isEmpty) && !hasPartner) return;
    _ratingNavigated = true;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      // 1) Avaliar estafeta
      if (driverId != null && driverId.isNotEmpty) {
        await Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => RatingScreen(
              order: order,
              subjectType: RatingSubjectType.driver,
              subjectId: driverId,
            ),
          ),
        );
      }
      if (!mounted) return;
      // 2) Avaliar parceiro (se aplicável)
      if (hasPartner) {
        await Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => RatingScreen(
              order: order,
              subjectType: RatingSubjectType.partner,
              subjectId: restaurantId,
            ),
          ),
        );
      }
    });
  }

  ll.LatLng? _resolveTarget(OrderModel order) {
    if (order.status.index <= OrderStatus.driverAccepted.index) {
      return order.pickupLocation ?? order.destination;
    }
    if (order.status.index < OrderStatus.delivered.index) {
      return order.destination ?? order.pickupLocation;
    }
    return null;
  }

  void _updateRoute(ll.LatLng origin, ll.LatLng destination) {
    final key =
        '${origin.latitude.toStringAsFixed(4)},${origin.longitude.toStringAsFixed(4)}'
        '|${destination.latitude.toStringAsFixed(4)},${destination.longitude.toStringAsFixed(4)}';
    if (_activeRouteKey == key && _routePoints.isNotEmpty) return;
    _activeRouteKey = key;
    final requestId = ++_routeRequestId;
    _directionsService
        .fetchRoute(origin: origin, destination: destination)
        .then((route) {
      if (!mounted || _routeRequestId != requestId) return;
      setState(() {
        _routePoints = (route != null && route.points.isNotEmpty)
            ? route.points
            : <ll.LatLng>[origin, destination];
      });
    });
  }

  Future<void> _fitCamera(ll.LatLng driver, ll.LatLng target) async {
    if (!_followCamera) return; // user is panning manually
    if (!_mapController.isCompleted) return;
    if (_lastCameraDriver == driver && _lastCameraTarget == target) return;
    _lastCameraDriver = driver;
    _lastCameraTarget = target;
    final bounds = boundsFromPoints(
      _routePoints.isNotEmpty ? _routePoints : <ll.LatLng>[driver, target],
    );
    if (bounds != null) {
      await _animateCameraProgrammatic(
        CameraUpdate.newLatLngBounds(bounds, 100),
      );
    } else {
      // Single point fallback: Waze pose centred on the driver.
      await _animateCameraProgrammatic(_wazeCameraUpdate(driver));
    }
  }

  @override
  Widget build(BuildContext context) {
    final orderStore = context.watch<OrderStore>();
    // PERFORMANCE: read DriverStore (no full subscription) and use a scoped
    // selector below to react ONLY to the assigned driver's location. Without
    // this scoping, the screen rebuilt on every interpolation step (10×/sec)
    // of EVERY driver received via the `drivers` realtime channel.
    final driverStore = context.read<DriverStore>();
    final order = _freshOrder(orderStore);

    _maybeOpenRating(order);

    final assignedId = order.assignedDriverId;
    final driver =
        assignedId != null ? driverStore.getDriverById(assignedId) : null;
    // BUG #3 + BLOCO 3 — fetch best-effort de nome/veículo/matrícula via
    // Supabase (o realtime channel não traz matrícula). Idempotente.
    if (assignedId != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _maybeFetchDriverInfo(assignedId);
      });
    }
    // Veículo + matrícula para o cliente ver. Prefere o fetch da DB; cai no
    // DriverStore em memória como último recurso.
    final vehicleRaw = _fetchedVehicleType ?? driver?.vehicleType.dbValue;
    final driverVehicleLabel =
        vehicleRaw != null ? VehicleTypeDb.fromDb(vehicleRaw).label : null;
    final driverPlate = (_fetchedLicensePlate ?? driver?.licensePlate ?? '')
            .trim()
            .isNotEmpty
        ? (_fetchedLicensePlate ?? driver?.licensePlate)!.trim()
        : null;
    // Single source of truth: DriverStore.currentDriver.location, synced in
    // real time via the `drivers` table subscription. Scoped via select() so
    // that only changes to THIS driver's location trigger a rebuild.
    final driverPosition = assignedId == null
        ? null
        : context.select<DriverStore, ll.LatLng?>(
            (s) => s.getDriverById(assignedId)?.location,
          );
    final target = _resolveTarget(order);

    if (driverPosition != null && target != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _updateRoute(driverPosition, target);
        _fitCamera(driverPosition, target);
      });
    }

    // ── Markers ──────────────────────────────────────────────────────────────
    final markers = <Marker>{};

    if (order.destination != null) {
      markers.add(Marker(
        markerId: const MarkerId('client'),
        position: order.destination!.toGMaps(),
        icon: MapMarkerHelper.clientIcon,
        infoWindow: InfoWindow(title: 'Destino'.tr),
        zIndexInt: 1,
      ));
    }
    if (order.pickupLocation != null) {
      markers.add(Marker(
        markerId: const MarkerId('pickup'),
        position: order.pickupLocation!.toGMaps(),
        icon: MapMarkerHelper.pickupIcon,
        infoWindow: InfoWindow(title: 'Recolha'.tr),
        zIndexInt: 1,
      ));
    }
    if (driverPosition != null) {
      markers.add(Marker(
        markerId: const MarkerId('driver'),
        position: driverPosition.toGMaps(),
        icon: MapMarkerHelper.driverIcon,
        infoWindow: InfoWindow(title: (driver?.name ?? _fetchedDriverName ?? 'Estafeta')),
        zIndexInt: 2,
      ));
    }

    // ── Polyline ─────────────────────────────────────────────────────────────
    final polylines = <Polyline>{};
    if (_routePoints.isNotEmpty) {
      polylines.add(Polyline(
        polylineId: const PolylineId('route'),
        color: const Color(0xFF1A73E8),
        width: 5,
        points: _routePoints.toGMaps(),
      ));
    } else if (driverPosition != null && target != null) {
      polylines.add(Polyline(
        polylineId: const PolylineId('route'),
        color: const Color(0xFF1A73E8),
        width: 4,
        points: [driverPosition.toGMaps(), target.toGMaps()],
      ));
    }

    final mapCenter = driverPosition ??
        order.destination ??
        order.pickupLocation ??
        const ll.LatLng(kGuardaLat, kGuardaLng);

    return Scaffold(
      floatingActionButton: BoraSupportFab(orderId: widget.order.id),
      body: Stack(
        children: [
          // ── Fullscreen map ─────────────────────────────────────────────────
          GoogleMap(
            initialCameraPosition: CameraPosition(
              target: mapCenter.toGMaps(),
              zoom: _wazeZoom,
              tilt: _wazeTilt,
            ),
            markers: markers,
            polylines: polylines,
            myLocationEnabled: true,
            myLocationButtonEnabled: false,
            compassEnabled: false,
            zoomControlsEnabled: false,
            onMapCreated: (c) {
              if (!_mapController.isCompleted) _mapController.complete(c);
            },
            onCameraMoveStarted: _onUserCameraMoveStarted,
          ),

          // ── Recenter button (BUG E) — mid-right, doesn't collide with
          // BoraSupportFab (top-right) or the draggable bottom sheet.
          Positioned(
            right: 16,
            top: MediaQuery.of(context).size.height * 0.62,
            child: Semantics(
              label: 'Centralizar mapa'.tr,
              button: true,
              child: FloatingActionButton.small(
                heroTag: 'map_recenter_btn_client',
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white,
                onPressed: _onRecenter,
                child: const Icon(Icons.my_location),
              ),
            ),
          ),

          // ── Takeaway preparing countdown banner ────────────────────────────
          // Quando o parceiro aceita o pedido takeaway com um ETA, o servidor
          // grava takeawayReadyAt. Mostramos uma barra com headline dinâmico
          // ("Pronto em ~X min") que actualiza a cada 30s.
          if (widget.order.isTakeaway &&
              widget.order.status == OrderStatus.preparing &&
              widget.order.takeawayReadyAt != null)
            SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(
                    Spacing.lg, 60, Spacing.lg, Spacing.lg),
                child: PreparingCountdownBanner(order: widget.order),
              ),
            ),

          // ── Takeaway readyForPickup banner ─────────────────────────────────
          // BR §14.11 — quando o parceiro marca pronto, sobrepõe um card grande
          // sobre o mapa com o pickup_code. Mantém o mapa atrás (UX consistente
          // com o resto do ecrã) e desaparece ao mudar de estado.
          if (widget.order.status == OrderStatus.readyForPickup)
            SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(
                    Spacing.lg, 60, Spacing.lg, Spacing.lg),
                child: PickupCodeCard(order: widget.order),
              ),
            ),

          // ── Back button ────────────────────────────────────────────────────
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(50),
                  boxShadow: AppColors.shadowSm,
                ),
                child: Material(
                  color: Colors.transparent,
                  borderRadius: BorderRadius.circular(50),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(50),
                    onTap: () => Navigator.maybePop(context),
                    child: const Padding(
                      padding: EdgeInsets.all(10),
                      child: Icon(Icons.arrow_back, size: 22),
                    ),
                  ),
                ),
              ),
            ),
          ),

          // ── Draggable bottom sheet ─────────────────────────────────────────
          DraggableScrollableSheet(
            initialChildSize: 0.38,
            minChildSize: 0.22,
            maxChildSize: 0.80,
            snap: true,
            snapSizes: const [0.22, 0.38, 0.80],
            builder: (_, scrollController) => _BottomCard(
              scrollController: scrollController,
              order: order,
              driverName: driver?.name ?? _fetchedDriverName,
              driverVehicleLabel: driverVehicleLabel,
              driverPlate: driverPlate,
              driverRating: _fetchedAvgRating ?? driver?.avgRating,
              // [31/08] posição VIVA do estafeta (realtime) → ETA nunca
              // congela na coordenada velha gravada na linha do pedido.
              driverPos: driverPosition,
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Bottom draggable card
// ─────────────────────────────────────────────────────────────────────────────

class _BottomCard extends StatefulWidget {
  const _BottomCard({
    required this.scrollController,
    required this.order,
    required this.driverName,
    this.driverVehicleLabel,
    this.driverPlate,
    this.driverRating,
    this.driverPos,
  });

  final ScrollController scrollController;
  final OrderModel order;
  final String? driverName;
  final String? driverVehicleLabel;
  final String? driverPlate;

  /// [31/08] Posição realtime do estafeta (DriverStore) para o ETA vivo.
  final ll.LatLng? driverPos;

  /// Avaliação média REAL do estafeta (null/0 = esconder a linha).
  final double? driverRating;

  @override
  State<_BottomCard> createState() => _BottomCardState();
}

class _BottomCardState extends State<_BottomCard> {
  bool _sendingCode = false;

  bool get _driverAssigned =>
      widget.order.status.index >= OrderStatus.driverAccepted.index &&
      widget.order.status != OrderStatus.rejected;

  bool get _isActive =>
      widget.order.status != OrderStatus.delivered &&
      widget.order.status != OrderStatus.rejected &&
      widget.order.status != OrderStatus.cancelled;

  /// Client can cancel from any non-terminal state (BR §8.3).
  /// Fee tier is decided server-side based on current status.
  bool get _canCancel =>
      widget.order.status != OrderStatus.delivered &&
      widget.order.status != OrderStatus.rejected &&
      widget.order.status != OrderStatus.cancelled;

  Future<void> _resendDeliveryCode() async {
    final order = widget.order;
    final phone = order.clientPhone;
    if (phone == null || phone.trim().isEmpty) return;
    if (_sendingCode) return;
    setState(() => _sendingCode = true);
    await NotificationService.instance.notifyClient(
      clientPhone: phone,
      title: 'O seu código de entrega'.tr,
      body: 'Código: {0} — Mostre ao estafeta na entrega.'.trArgs([order.deliveryCode]),
    );
    if (!mounted) return;
    setState(() => _sendingCode = false);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Código reenviado por notificação.'.tr)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final order = widget.order;
    final driverName = widget.driverName;
    final scrollController = widget.scrollController;
    final theme = Theme.of(context);

    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        boxShadow: AppColors.shadowNav,
      ),
      child: ListView(
        controller: scrollController,
        padding: EdgeInsets.zero,
        physics: const ClampingScrollPhysics(),
        children: [
          Center(
            child: Container(
              margin: const EdgeInsets.symmetric(vertical: Spacing.md),
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: AppColors.divider,
                borderRadius: BorderRadius.circular(Radii.sm / 2),
              ),
            ),
          ),

          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 28),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // ── 8.2 Banner de autorização de orçamento (errand) ──────
                ErrandBudgetBanner(order: order),
                // ── Order code + status ──────────────────────────────────
                Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            order.status.label,
                            style: theme.textTheme.titleLarge?.copyWith(
                              fontWeight: FontWeight.w800,
                              letterSpacing: -0.3,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            'Pedido {0}'.trArgs([order.orderCode]),
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: AppColors.textSecondary,
                              letterSpacing: 0.5,
                            ),
                          ),
                        ],
                      ),
                    ),
                    // Status dot
                    Container(
                      width: 12,
                      height: 12,
                      decoration: BoxDecoration(
                        color: _statusColor(order.status),
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: _statusColor(order.status)
                                .withValues(alpha: 0.4),
                            blurRadius: 8,
                            spreadRadius: 2,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),

                // ── Festas: encomenda agendada + tempo anunciado ──────────
                if (order.scheduledFor != null) ...[
                  const SizedBox(height: 14),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 10),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFDF2F8),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: const Color(0xFFFBCFE8)),
                    ),
                    child: Text(
                      '📅 Encomenda para {0}/{1} às {2}:{3}{4}'.trArgs([order.scheduledFor!.day.toString().padLeft(2, '0'), order.scheduledFor!.month.toString().padLeft(2, '0'), order.scheduledFor!.hour.toString().padLeft(2, '0'), order.scheduledFor!.minute.toString().padLeft(2, '0'), order.status == OrderStatus.preparing && order.prepTimeMinutes != null ? ' · fica pronta em ${order.prepTimeMinutes} min' : '']),
                      style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 13.5,
                        color: Color(0xFF9D174D),
                      ),
                    ),
                  ),
                ],
                // ── ETA badge ────────────────────────────────────────────
                // Encomenda agendada: o ETA por distância não faz sentido
                // (o pedido sai na data marcada) — esconder o badge.
                if (OrderEtaService.label(order,
                            driverPos: widget.driverPos) !=
                        null &&
                    order.scheduledFor == null) ...[
                  const SizedBox(height: 14),
                  _EtaBadge(
                    label: OrderEtaService.label(order,
                        driverPos: widget.driverPos)!,
                    status: order.status,
                    serviceType: order.serviceType,
                    vendorName: order.vendorName,
                  ),
                ],
                // Festas "na hora" aceite com tempo: mostrar o prazo anunciado.
                if (order.scheduledFor == null &&
                    order.status == OrderStatus.preparing &&
                    order.prepTimeMinutes != null) ...[
                  const SizedBox(height: 8),
                  Text(
                    'A loja aceitou — fica pronto em {0} min.'.trArgs([order.prepTimeMinutes]),
                    style: const TextStyle(
                        fontSize: 13, fontWeight: FontWeight.w600),
                  ),
                ],

                const SizedBox(height: 20),

                // ── Driver card ──────────────────────────────────────────
                if (_driverAssigned) ...[
                  Container(
                    padding: const EdgeInsets.all(Spacing.lg),
                    decoration: BoxDecoration(
                      color: AppColors.surface,
                      borderRadius: BorderRadius.circular(Radii.lg),
                      border: Border.all(color: AppColors.divider),
                      boxShadow: AppColors.shadowSm,
                    ),
                    child: Row(
                      children: [
                        Stack(
                          children: [
                            CircleAvatar(
                              radius: 26,
                              backgroundColor:
                                  AppColors.primary.withValues(alpha: 0.12),
                              child: const Icon(
                                Icons.delivery_dining,
                                size: 28,
                                color: AppColors.primary,
                              ),
                            ),
                            Positioned(
                              bottom: 0,
                              right: 0,
                              child: Container(
                                width: 14,
                                height: 14,
                                decoration: BoxDecoration(
                                  color: AppColors.success,
                                  shape: BoxShape.circle,
                                  border:
                                      Border.all(color: Colors.white, width: 2),
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(width: Spacing.md),
                        // Name + details
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                driverName ?? 'Estafeta',
                                style: theme.textTheme.titleSmall?.copyWith(
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              const SizedBox(height: 3),
                              // Avaliação REAL (era '4.9' fixo). Sem avaliação
                              // → só a distância, nunca um número inventado.
                              Row(
                                children: [
                                  if ((widget.driverRating ?? 0) > 0) ...[
                                    Icon(Icons.star_rounded,
                                        size: 14,
                                        color: Colors.amber.shade600),
                                    const SizedBox(width: 3),
                                    Text(
                                      widget.driverRating!.toStringAsFixed(1),
                                      style:
                                          theme.textTheme.bodySmall?.copyWith(
                                        fontWeight: FontWeight.w600,
                                        color: AppColors.textPrimary,
                                      ),
                                    ),
                                  ],
                                  if (order.distanceKm > 0) ...[
                                    Text(
                                      (widget.driverRating ?? 0) > 0
                                          ? '  ·  ${order.distanceKm.toStringAsFixed(1)} km'
                                          : '${order.distanceKm.toStringAsFixed(1)} km',
                                      style: theme.textTheme.bodySmall
                                          ?.copyWith(
                                              color: AppColors.textSecondary),
                                    ),
                                  ],
                                ],
                              ),
                              if ((order.driverPhone ?? '').isNotEmpty) ...[
                                const SizedBox(height: 2),
                                Text(
                                  order.driverPhone!,
                                  style: theme.textTheme.bodySmall?.copyWith(
                                    color: AppColors.textSecondary,
                                  ),
                                ),
                              ],
                              // BLOCO 3 — veículo + matrícula do estafeta
                              if (widget.driverVehicleLabel != null ||
                                  (widget.driverPlate ?? '').isNotEmpty) ...[
                                const SizedBox(height: 3),
                                Row(
                                  children: [
                                    Icon(_vehicleIcon(widget.driverVehicleLabel),
                                        size: 14,
                                        color: AppColors.textSecondary),
                                    const SizedBox(width: 4),
                                    Flexible(
                                      child: Text(
                                        [
                                          if (widget.driverVehicleLabel != null)
                                            widget.driverVehicleLabel!,
                                          if ((widget.driverPlate ?? '')
                                              .isNotEmpty)
                                            widget.driverPlate!,
                                        ].join('  ·  '),
                                        overflow: TextOverflow.ellipsis,
                                        style:
                                            theme.textTheme.bodySmall?.copyWith(
                                          color: AppColors.textSecondary,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 14),

                  // M11 (padrão Uber Eats): 2 acessos de chat com badge de
                  // não-lidas + preview — restaurante E estafeta (após aceitar).
                  // Lojas NÃO-parceiras (mercados, Wells, Leroy...) não têm
                  // ninguém do outro lado — chat com a loja só se parceiro.
                  if (_isActive) ...[
                    if (order.isPartnerStore)
                      ChatBubbleButton(
                        order: order,
                        senderType: ChatSenderType.client,
                        chatTarget: ChatTarget.partner,
                        label: 'Falar com o Restaurante'.tr,
                        showPreview: true,
                      ),
                    if (order.assignedDriverId != null) ...[
                      if (order.isPartnerStore) const SizedBox(height: Spacing.sm),
                      ChatBubbleButton(
                        order: order,
                        senderType: ChatSenderType.client,
                        chatTarget: ChatTarget.driver,
                        label: 'Falar com o Estafeta'.tr,
                        showPreview: true,
                      ),
                    ],
                  ],

                  // ── Cancel order (BR §8.3) ─────────────────────────────
                  if (_canCancel) ...[
                    const SizedBox(height: Spacing.sm),
                    SizedBox(
                      width: double.infinity,
                      child: Semantics(
                        identifier: 'btn_cancelar_pedido',
                        child: OutlinedButton.icon(
                          style: OutlinedButton.styleFrom(
                            foregroundColor: AppColors.error,
                            side: const BorderSide(color: AppColors.error),
                            padding: const EdgeInsets.symmetric(
                                vertical: Spacing.md),
                            shape: RoundedRectangleBorder(
                              borderRadius:
                                  BorderRadius.circular(Radii.md + 2),
                            ),
                          ),
                          onPressed: () => _confirmClientCancel(context),
                          icon: const Icon(Icons.cancel_outlined, size: 18),
                          label: Text('Cancelar pedido'.tr),
                        ),
                      ),
                    ),
                  ],

                  // ── Delivery code ──────────────────────────────────────
                  if (_isActive) ...[
                    const SizedBox(height: 14),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 20, vertical: 14),
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [
                            Colors.orange.shade50,
                            Colors.amber.shade50,
                          ],
                        ),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: Colors.orange.shade200),
                      ),
                      child: Column(
                        children: [
                          Text(
                            'Código de entrega'.tr,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: Colors.orange.shade700,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              for (final ch in order.deliveryCode.split(''))
                                _CodeDigit(digit: ch),
                            ],
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Mostre ao estafeta na entrega'.tr,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: Colors.orange.shade600,
                              fontSize: 11,
                            ),
                          ),
                          const SizedBox(height: 6),
                          TextButton.icon(
                            onPressed: _sendingCode
                                ? null
                                : _resendDeliveryCode,
                            style: TextButton.styleFrom(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 12, vertical: 4),
                              minimumSize: Size.zero,
                              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                            ),
                            icon: _sendingCode
                                ? SizedBox(
                                    width: 13,
                                    height: 13,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: Colors.orange.shade700,
                                    ),
                                  )
                                : Icon(Icons.notifications_outlined,
                                    size: 15,
                                    color: Colors.orange.shade700),
                            label: Text(
                              _sendingCode
                                  ? 'A reenviar…'.tr
                                  : 'Reenviar código',
                              style: TextStyle(
                                  fontSize: 12,
                                  color: Colors.orange.shade700),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],

                  const SizedBox(height: 20),
                  Divider(color: Colors.grey.shade200, height: 1),
                  const SizedBox(height: 16),
                ],

                // ── Addresses ────────────────────────────────────────────
                if ((order.pickupAddress ?? '').isNotEmpty ||
                    order.pickupLocation != null)
                  _AddressRow(
                    icon: Icons.store_outlined,
                    iconColor: Colors.blueGrey.shade400,
                    child: AddressText(
                      rawAddress: order.pickupAddress,
                      coords: order.pickupLocation,
                      prefix: 'Recolha: '.tr,
                      style: theme.textTheme.bodySmall,
                    ),
                  ),
                if ((order.dropoffAddress ?? '').isNotEmpty ||
                    order.destination != null) ...[
                  const SizedBox(height: 8),
                  _AddressRow(
                    icon: Icons.place_outlined,
                    iconColor: Colors.red.shade400,
                    child: AddressText(
                      rawAddress: order.dropoffAddress,
                      coords: order.destination,
                      prefix: 'Entrega: '.tr,
                      style: theme.textTheme.bodySmall,
                    ),
                  ),
                ],

                // ── Resumo do pedido ─────────────────────────────────────
                // BUG #4 (2026-05-13) — decomposição completa em vez do
                // total monolítico. Mostra subtotal, taxa entrega, taxa
                // serviço, gorjeta, saldo aplicado + total final.
                const SizedBox(height: 16),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  decoration: BoxDecoration(
                    color: AppColors.surface2,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (order.subtotal > 0)
                        _SummaryRow(
                            label: 'Subtotal'.tr, value: order.subtotal),
                      if (order.deliveryFee > 0)
                        _SummaryRow(
                            label: 'Taxa de entrega'.tr,
                            value: order.deliveryFee),
                      if (order.serviceFee > 0)
                        _SummaryRow(
                            label: 'Taxa de serviço'.tr,
                            value: order.serviceFee),
                      if (order.tipCents > 0)
                        _SummaryRow(
                            label: 'Gorjeta'.tr,
                            value: order.tipCents / 100,
                            accent: true),
                      if (order.walletAppliedCents > 0)
                        _SummaryRow(
                            label: 'Saldo Bora aplicado'.tr,
                            value: -(order.walletAppliedCents / 100),
                            isDiscount: true),
                      Divider(color: Colors.grey.shade300, height: 16),
                      _SummaryRow(
                        label: 'Total do pedido'.tr,
                        value: order.total,
                        isStrong: true,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  IconData _vehicleIcon(String? label) {
    switch (label) {
      case 'Carro':
      case 'Carro — Passageiros':
        return Icons.directions_car_outlined;
      case 'Bicicleta':
        return Icons.pedal_bike_outlined;
      default:
        return Icons.two_wheeler_outlined;
    }
  }

  Color _statusColor(OrderStatus status) {
    switch (status) {
      case OrderStatus.delivered:
        return AppColors.success;
      case OrderStatus.rejected:
      case OrderStatus.cancelled:
        return AppColors.error;
      case OrderStatus.driverAccepted:
      case OrderStatus.pickedUp:
      case OrderStatus.onTheWay:
        return AppColors.info;
      default:
        return AppColors.warning;
    }
  }

  // ── Client cancel (BR §8.3) ──────────────────────────────────────────────
  String _feeLabelForStatus(OrderStatus status, double total) {
    switch (status) {
      case OrderStatus.created:
      case OrderStatus.preparing:
      case OrderStatus.callingDriver:
        return '€1,00';
      case OrderStatus.driverAccepted:
        return '€2,50';
      case OrderStatus.pickedUp:
      case OrderStatus.onTheWay:
        return '100% (€${total.toStringAsFixed(2)})';
      case OrderStatus.readyForPickup:
        // Takeaway pronto não cancelável pelo cliente (suporte humano trata).
        return '—';
      case OrderStatus.delivered:
      case OrderStatus.rejected:
      case OrderStatus.cancelled:
        return '—';
    }
  }

  Future<void> _confirmClientCancel(BuildContext context) async {
    // BUG #2 (2026-05-12) — dropdown 8 motivos fixos PT-PT + campo livre se "Outro motivo".
    const reasonOptions = <String>[
      'Esperei muito tempo',
      'Fiz o pedido por engano',
      'Quero alterar o pedido',
      'Restaurante/loja demorou demais',
      'Preço diferente do esperado',
      'Problema com o pagamento',
      'Endereço de entrega errado',
      'Outro motivo',
    ];
    String? selectedReason;
    final otherReasonController = TextEditingController();
    // Bloco 4 — estágio de cancelamento ao vivo (o servidor é a fonte da verdade).
    const graceSeconds = 180;
    final ageSeconds =
        DateTime.now().difference(widget.order.createdAt).inSeconds;
    final isGrace =
        widget.order.assignedDriverId == null && ageSeconds <= graceSeconds;
    final graceLeft = (graceSeconds - ageSeconds).clamp(0, graceSeconds);
    final isElectronic = widget.order.paymentMethod.name != 'cash';
    const refundableStatuses = [
      OrderStatus.created,
      OrderStatus.preparing,
      OrderStatus.callingDriver,
      OrderStatus.driverAccepted,
    ];
    final canChooseRefund =
        isElectronic && refundableStatuses.contains(widget.order.status);
    String refundTarget = 'card';
    final feeLabel = isGrace
        ? 'Grátis'.tr
        : _feeLabelForStatus(widget.order.status, widget.order.total);

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: Text('Cancelar pedido'.tr),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Taxa de cancelamento: {0}'.trArgs([feeLabel]),
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 12),
              if (isGrace)
                Text(
                  'Cancelamento grátis — ainda dentro do tempo de cortesia{0}.'.trArgs([graceLeft > 0 ? ' (${(graceLeft ~/ 60).toString().padLeft(2, '0')}:${(graceLeft % 60).toString().padLeft(2, '0')})' : '']),
                  style: const TextStyle(
                      color: AppColors.primary, fontWeight: FontWeight.w600),
                )
              else
                Text('Tens a certeza que queres cancelar este pedido?'.tr),
              if (canChooseRefund) ...[
                const SizedBox(height: 12),
                Text('Como queres o reembolso?'.tr,
                    style: const TextStyle(fontWeight: FontWeight.w600)),
                RadioListTile<String>(
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                  value: 'card',
                  groupValue: refundTarget,
                  onChanged: (v) => setDialogState(() => refundTarget = v!),
                  title: Text('De volta ao cartão (~5 dias úteis)'.tr),
                ),
                RadioListTile<String>(
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                  value: 'wallet',
                  groupValue: refundTarget,
                  onChanged: (v) => setDialogState(() => refundTarget = v!),
                  title: Text(
                      'Na carteira, imediato (80% saldo + 20% pontos)'.tr),
                ),
              ],
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                value: selectedReason,
                isExpanded: true,
                decoration: InputDecoration(
                  labelText: 'Motivo (obrigatório)'.tr,
                  border: const OutlineInputBorder(),
                ),
                items: reasonOptions
                    .map((r) => DropdownMenuItem<String>(
                          value: r,
                          child: Text(r, overflow: TextOverflow.ellipsis),
                        ))
                    .toList(),
                onChanged: (v) => setDialogState(() => selectedReason = v),
              ),
              if (selectedReason == 'Outro motivo') ...[
                const SizedBox(height: 8),
                TextField(
                  controller: otherReasonController,
                  maxLines: 2,
                  decoration: InputDecoration(
                    labelText: 'Descreve o motivo (opcional)'.tr,
                    border: const OutlineInputBorder(),
                  ),
                ),
              ],
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: Text('Não'.tr),
            ),
            TextButton(
              onPressed: selectedReason == null
                  ? null
                  : () => Navigator.of(ctx).pop(true),
              style: TextButton.styleFrom(foregroundColor: Colors.red),
              child: Text('Confirmar cancelamento'.tr),
            ),
          ],
        ),
      ),
    );

    if (confirmed != true || !context.mounted) return;

    final orderStore = context.read<OrderStore>();
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);

    // Compor reason final: dropdown + campo livre se "Outro motivo"
    // Fica SEMPRE em português, mesmo com a app em inglês: este texto é
    // gravado no pedido e quem o lê é o painel admin (PT-BR), não o cliente.
    final finalReason = selectedReason == 'Outro motivo' &&
            otherReasonController.text.trim().isNotEmpty
        ? 'Outro motivo: ${otherReasonController.text.trim()}'
        : (selectedReason ?? '');

    final result = await orderStore.clientCancelOrder(
      widget.order,
      reason: finalReason,
      refundTarget: refundTarget,
    );

    if (!context.mounted) return;

    if (result.success) {
      messenger.showSnackBar(
        SnackBar(
          content: Text(result.feeEur != null && result.feeEur! > 0
              ? 'Pedido cancelado. Taxa: €{0}.'.trArgs([result.feeEur!.toStringAsFixed(2)])
              : 'Pedido cancelado.'),
        ),
      );
      navigator.pop();
    } else {
      // Bloco 4 — mensagens PT-PT para os bloqueios do servidor.
      final raw = result.error ?? '';
      // 2026-08-16: "already_finalized" cobre delivered E cancelled. Se o
      // pedido JÁ está cancelado (outro device / admin / cron), isso é
      // sucesso para o cliente — confirmar e sair, nunca o botão ficar mudo.
      if (raw.contains('already_finalized')) {
        OrderModel? atual;
        for (final o in orderStore.orders) {
          if (o.id == widget.order.id) {
            atual = o;
            break;
          }
        }
        if (atual != null && atual.status == OrderStatus.cancelled) {
          messenger.showSnackBar(
              SnackBar(content: Text('O pedido já estava cancelado.'.tr)));
          navigator.pop();
          return;
        }
      }
      final msg = raw.contains('errand_already_purchased')
          ? 'A compra já foi feita pelo estafeta — a entrega vai continuar e não pode ser cancelada.'.tr
          : raw.contains('already_finalized')
              ? 'Este pedido já não pode ser cancelado.'.tr
              : 'Falha ao cancelar. Tenta novamente.';
      messenger.showSnackBar(SnackBar(content: Text(msg)));
    }
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Helpers
// ─────────────────────────────────────────────────────────────────────────────

class _CodeDigit extends StatelessWidget {
  const _CodeDigit({required this.digit});

  final String digit;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 44,
      height: 52,
      margin: const EdgeInsets.symmetric(horizontal: 4),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.orange.shade300, width: 1.5),
        boxShadow: const [
          BoxShadow(
            color: Colors.black12,
            blurRadius: 4,
            offset: Offset(0, 2),
          ),
        ],
      ),
      alignment: Alignment.center,
      child: Text(
        digit,
        style: TextStyle(
          fontSize: 26,
          fontWeight: FontWeight.w900,
          color: Colors.orange.shade900,
          height: 1,
        ),
      ),
    );
  }
}

class _AddressRow extends StatelessWidget {
  const _AddressRow({
    required this.icon,
    required this.iconColor,
    required this.child,
  });

  final IconData icon;
  final Color iconColor;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 1),
          child: Icon(icon, size: 16, color: iconColor),
        ),
        const SizedBox(width: 8),
        Expanded(child: child),
      ],
    );
  }
}

class _EtaBadge extends StatelessWidget {
  const _EtaBadge({
    required this.label,
    required this.status,
    this.serviceType,
    this.vendorName,
  });

  final String label;
  final OrderStatus status;
  // BUG 3 — opcionais para text dinâmico por service_type.
  final OrderServiceType? serviceType;
  final String? vendorName;

  @override
  Widget build(BuildContext context) {
    final isClose = status == OrderStatus.pickedUp ||
        status == OrderStatus.onTheWay;
    final accent = isClose ? Colors.green.shade600 : Colors.orange.shade700;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: accent.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(Radii.lg),
        border: Border.all(color: accent.withValues(alpha: 0.35)),
      ),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: accent.withValues(alpha: 0.18),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(Icons.delivery_dining, color: accent, size: 22),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w800,
                    color: accent,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  _subLabel(status),
                  style: const TextStyle(
                    fontSize: 12,
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _subLabel(OrderStatus s) {
    // BUG 3 — texto dinâmico por service_type (memory: sessão 17-bugs 2026-05-11).
    final vendor = (vendorName ?? '').trim();
    final isStore = serviceType == OrderServiceType.storeShopping;
    final isErrand = serviceType == OrderServiceType.errand;
    final pickupLabel = isStore
        ? (vendor.isEmpty ? 'da loja' : 'do $vendor')
        : 'do restaurante'.tr;
    final preparingLabel = isStore
        ? (vendor.isEmpty
            ? 'A loja a preparar o pedido'.tr
            : '$vendor a preparar o pedido')
        : 'Restaurante a preparar o pedido'.tr;
    // FAVORES — textos próprios (NUNCA textos de restaurante)
    if (isErrand) {
      switch (s) {
        case OrderStatus.created:
        case OrderStatus.preparing:
          return 'A organizar o teu favor'.tr;
        case OrderStatus.callingDriver:
          return 'À procura de estafeta'.tr;
        case OrderStatus.driverAccepted:
          return 'Estafeta a caminho da tua casa'.tr;
        case OrderStatus.pickedUp:
          return 'Estafeta a tratar do teu favor'.tr;
        case OrderStatus.onTheWay:
          return 'A caminho da entrega'.tr;
        default:
          return '';
      }
    }
    switch (s) {
      case OrderStatus.created:
      case OrderStatus.preparing:
        return preparingLabel;
      case OrderStatus.callingDriver:
        return 'À procura de estafeta'.tr;
      case OrderStatus.driverAccepted:
        return 'Estafeta a caminho {0}'.trArgs([pickupLabel]);
      case OrderStatus.pickedUp:
      case OrderStatus.onTheWay:
        return 'Estafeta a caminho da sua morada'.tr;
      default:
        return '';
    }
  }
}

// BUG #4 (2026-05-13) — _SummaryRow privado para a decomposição do resumo
// no _BottomCard. Espelha o widget homónimo em cart_screen.dart, com extra
// `isDiscount` para mostrar valores negativos (saldo aplicado).
class _SummaryRow extends StatelessWidget {
  const _SummaryRow({
    required this.label,
    required this.value,
    this.isStrong = false,
    this.accent = false,
    this.isDiscount = false,
  });

  final String label;
  final double value;
  final bool isStrong;
  final bool accent;
  final bool isDiscount;

  @override
  Widget build(BuildContext context) {
    final color = accent
        ? AppColors.accent
        : (isDiscount
            ? AppColors.success
            : (isStrong ? AppColors.textPrimary : AppColors.textSecondary));
    final style = TextStyle(
      fontSize: isStrong ? 16 : 14,
      fontWeight: isStrong ? FontWeight.w800 : FontWeight.w500,
      color: color,
    );
    final displayValue = isDiscount
        ? '-€${value.abs().toStringAsFixed(2)}'
        : '€${value.toStringAsFixed(2)}';

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: style),
          Text(displayValue, style: style),
        ],
      ),
    );
  }
}
