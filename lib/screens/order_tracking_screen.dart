import 'dart:async';

import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart' hide LatLng;
import 'package:latlong2/latlong.dart' as ll;
import 'package:provider/provider.dart';

import '../config/app_colors.dart';
import '../config/app_spacing.dart';
import '../models/chat_message.dart';
import '../models/order_model.dart';
import '../models/rating_model.dart';
import '../widgets/address_text.dart';
import '../widgets/bora_support_fab.dart';
import '../services/directions_service.dart';
import '../services/order_eta_service.dart';
import '../stores/driver_store.dart';
import '../stores/order_store.dart';
import '../utils/constants.dart';
import '../utils/map_marker_helper.dart';
import '../utils/map_utils.dart';
import '../services/notification_service.dart';
import 'chat_screen.dart';
import 'rating_screen.dart';

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

  @override
  void initState() {
    super.initState();
    MapMarkerHelper.preload();
  }

  @override
  void dispose() {
    _directionsService.dispose();
    super.dispose();
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
    final hasPartner = order.isPartnerStore &&
        (order.vendorName != null && order.vendorName!.isNotEmpty);
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
              subjectId: order.vendorName!,
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
    if (!_mapController.isCompleted) return;
    if (_lastCameraDriver == driver && _lastCameraTarget == target) return;
    _lastCameraDriver = driver;
    _lastCameraTarget = target;
    final controller = await _mapController.future;
    final bounds = boundsFromPoints(
      _routePoints.isNotEmpty ? _routePoints : <ll.LatLng>[driver, target],
    );
    if (bounds != null) {
      await controller.animateCamera(CameraUpdate.newLatLngBounds(bounds, 100));
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
        infoWindow: const InfoWindow(title: 'Destino'),
        zIndexInt: 1,
      ));
    }
    if (order.pickupLocation != null) {
      markers.add(Marker(
        markerId: const MarkerId('pickup'),
        position: order.pickupLocation!.toGMaps(),
        icon: MapMarkerHelper.pickupIcon,
        infoWindow: const InfoWindow(title: 'Recolha'),
        zIndexInt: 1,
      ));
    }
    if (driverPosition != null) {
      markers.add(Marker(
        markerId: const MarkerId('driver'),
        position: driverPosition.toGMaps(),
        icon: MapMarkerHelper.driverIcon,
        infoWindow: InfoWindow(title: driver?.name ?? 'Estafeta'),
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
              zoom: 14,
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
          ),

          // ── Back button ────────────────────────────────────────────────────
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Material(
                color: Colors.white,
                borderRadius: BorderRadius.circular(50),
                elevation: 4,
                shadowColor: Colors.black26,
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
              driverName: driver?.name,
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
  });

  final ScrollController scrollController;
  final OrderModel order;
  final String? driverName;

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
      title: 'O seu código de entrega',
      body: 'Código: ${order.deliveryCode} — Mostre ao estafeta na entrega.',
    );
    if (!mounted) return;
    setState(() => _sendingCode = false);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Código reenviado por notificação.')),
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
        boxShadow: [
          BoxShadow(
            color: Colors.black12,
            blurRadius: 20,
            offset: Offset(0, -4),
          ),
        ],
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
                            'Pedido ${order.orderCode}',
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

                // ── ETA badge ────────────────────────────────────────────
                if (OrderEtaService.label(order) != null) ...[
                  const SizedBox(height: 14),
                  _EtaBadge(
                    label: OrderEtaService.label(order)!,
                    status: order.status,
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
                              Row(
                                children: [
                                  Icon(Icons.star_rounded,
                                      size: 14, color: Colors.amber.shade600),
                                  const SizedBox(width: 3),
                                  Text(
                                    '4.9',
                                    style: theme.textTheme.bodySmall?.copyWith(
                                      fontWeight: FontWeight.w600,
                                      color: AppColors.textPrimary,
                                    ),
                                  ),
                                  if (order.distanceKm > 0) ...[
                                    Text(
                                      '  ·  ${order.distanceKm.toStringAsFixed(1)} km',
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
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 14),

                  if (_isActive)
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton.icon(
                        style: FilledButton.styleFrom(
                          backgroundColor: AppColors.info,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(
                              vertical: Spacing.md),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(Radii.md + 2),
                          ),
                          textStyle: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        onPressed: () => Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => ChatScreen(
                              order: order,
                              senderType: ChatSenderType.client,
                            ),
                          ),
                        ),
                        icon: const Icon(Icons.chat_bubble_outline, size: 18),
                        label: const Text('Falar com o estafeta'),
                      ),
                    ),

                  // ── Cancel order (BR §8.3) ─────────────────────────────
                  if (_canCancel) ...[
                    const SizedBox(height: Spacing.sm),
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(
                          foregroundColor: AppColors.error,
                          side: const BorderSide(color: AppColors.error),
                          padding: const EdgeInsets.symmetric(
                              vertical: Spacing.md),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(Radii.md + 2),
                          ),
                        ),
                        onPressed: () => _confirmClientCancel(context),
                        icon: const Icon(Icons.cancel_outlined, size: 18),
                        label: const Text('Cancelar pedido'),
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
                            'Código de entrega',
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
                            'Mostre ao estafeta na entrega',
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
                                  ? 'A reenviar…'
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
                      prefix: 'Recolha: ',
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
                      prefix: 'Entrega: ',
                      style: theme.textTheme.bodySmall,
                    ),
                  ),
                ],

                // ── Total ────────────────────────────────────────────────
                const SizedBox(height: 16),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  decoration: BoxDecoration(
                    color: Colors.grey.shade50,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Total do pedido',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: Colors.grey.shade600,
                        ),
                      ),
                      Text(
                        '€${order.total.toStringAsFixed(2)}',
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w800,
                        ),
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
      case OrderStatus.delivered:
      case OrderStatus.rejected:
      case OrderStatus.cancelled:
        return '—';
    }
  }

  Future<void> _confirmClientCancel(BuildContext context) async {
    final reasonController = TextEditingController();
    final feeLabel = _feeLabelForStatus(widget.order.status, widget.order.total);

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Cancelar pedido'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Taxa de cancelamento: $feeLabel',
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 12),
            const Text(
              'Tens a certeza que queres cancelar este pedido?',
            ),
            const SizedBox(height: 12),
            TextField(
              controller: reasonController,
              maxLines: 2,
              decoration: const InputDecoration(
                labelText: 'Razão (opcional)',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Não'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Confirmar cancelamento'),
          ),
        ],
      ),
    );

    if (confirmed != true || !context.mounted) return;

    final orderStore = context.read<OrderStore>();
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);

    final result = await orderStore.clientCancelOrder(
      widget.order,
      reason: reasonController.text,
    );

    if (!context.mounted) return;

    if (result.success) {
      messenger.showSnackBar(
        SnackBar(
          content: Text(result.feeEur != null
              ? 'Pedido cancelado. Taxa: €${result.feeEur!.toStringAsFixed(2)}.'
              : 'Pedido cancelado.'),
        ),
      );
      navigator.pop();
    } else {
      messenger.showSnackBar(
        SnackBar(content: Text(result.error ?? 'Falha ao cancelar.')),
      );
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
  const _EtaBadge({required this.label, required this.status});

  final String label;
  final OrderStatus status;

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
    switch (s) {
      case OrderStatus.created:
      case OrderStatus.preparing:
        return 'Restaurante a preparar o pedido';
      case OrderStatus.callingDriver:
        return 'À procura de estafeta';
      case OrderStatus.driverAccepted:
        return 'Estafeta a caminho do restaurante';
      case OrderStatus.pickedUp:
      case OrderStatus.onTheWay:
        return 'Estafeta a caminho da sua morada';
      default:
        return '';
    }
  }
}
