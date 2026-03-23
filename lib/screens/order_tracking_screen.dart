import 'dart:async';

import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart' hide LatLng;
import 'package:latlong2/latlong.dart' as ll;
import 'package:provider/provider.dart';

import '../models/order_model.dart';
import '../services/directions_service.dart';
import '../stores/driver_store.dart';
import '../stores/order_store.dart';
import '../utils/map_utils.dart';

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

  @override
  void dispose() {
    _directionsService.dispose();
    super.dispose();
  }

  /// Returns the current tracked order from the store (keeps status fresh).
  OrderModel _freshOrder(OrderStore orderStore) {
    try {
      return orderStore.orders.firstWhere((o) => o.id == widget.order.id);
    } catch (_) {
      return widget.order;
    }
  }

  /// The point the driver is currently heading to, based on order status.
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
      _routePoints.isNotEmpty
          ? _routePoints
          : <ll.LatLng>[driver, target],
    );
    if (bounds != null) {
      await controller.animateCamera(
        CameraUpdate.newLatLngBounds(bounds, 80),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final orderStore = context.watch<OrderStore>();
    final driverStore = context.watch<DriverStore>();
    final order = _freshOrder(orderStore);

    // Find assigned driver by ID stored on the order.
    final assignedId = order.assignedDriverId;
    final driver = assignedId != null
        ? driverStore.getDriverById(assignedId)
        : null;
    final driverPosition = driver?.location ??
        (order.driverLat != null && order.driverLng != null
            ? ll.LatLng(order.driverLat!, order.driverLng!)
            : null);

    final target = _resolveTarget(order);

    // Schedule route fetch + camera fit after build.
    if (driverPosition != null && target != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _updateRoute(driverPosition, target);
        _fitCamera(driverPosition, target);
      });
    }

    // ── Markers ────────────────────────────────────────────────────────────
    final markers = <Marker>{};

    if (order.destination != null) {
      markers.add(Marker(
        markerId: const MarkerId('client'),
        position: order.destination!.toGMaps(),
        icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueRed),
        infoWindow: const InfoWindow(title: 'Destino'),
      ));
    }

    if (order.pickupLocation != null) {
      markers.add(Marker(
        markerId: const MarkerId('pickup'),
        position: order.pickupLocation!.toGMaps(),
        icon:
            BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueOrange),
        infoWindow: const InfoWindow(title: 'Recolha'),
      ));
    }

    if (driverPosition != null) {
      markers.add(Marker(
        markerId: const MarkerId('driver'),
        position: driverPosition.toGMaps(),
        icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueGreen),
        infoWindow: InfoWindow(title: driver?.name ?? 'Estafeta'),
      ));
    }

    // ── Polyline ───────────────────────────────────────────────────────────
    final polylines = <Polyline>{};
    if (_routePoints.isNotEmpty) {
      polylines.add(Polyline(
        polylineId: const PolylineId('tracking-route'),
        color: Colors.blueAccent,
        width: 5,
        points: _routePoints.toGMaps(),
      ));
    } else if (driverPosition != null && target != null) {
      polylines.add(Polyline(
        polylineId: const PolylineId('tracking-route'),
        color: Colors.blueAccent,
        width: 4,
        points: [driverPosition.toGMaps(), target.toGMaps()],
      ));
    }

    // ── Initial camera center ──────────────────────────────────────────────
    final mapCenter = driverPosition ??
        order.destination ??
        order.pickupLocation ??
        const ll.LatLng(38.7223, -9.1393);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Acompanhar pedido'),
      ),
      body: Column(
        children: [
          Expanded(
            child: GoogleMap(
              initialCameraPosition: CameraPosition(
                target: mapCenter.toGMaps(),
                zoom: 14,
              ),
              markers: markers,
              polylines: polylines,
              myLocationEnabled: true,
              myLocationButtonEnabled: false,
              compassEnabled: true,
              onMapCreated: (controller) {
                if (!_mapController.isCompleted) {
                  _mapController.complete(controller);
                }
              },
            ),
          ),
          _TrackingInfoPanel(order: order, driverName: driver?.name),
        ],
      ),
    );
  }
}

// ── Info panel ─────────────────────────────────────────────────────────────

class _TrackingInfoPanel extends StatelessWidget {
  const _TrackingInfoPanel({
    required this.order,
    required this.driverName,
  });

  final OrderModel order;
  final String? driverName;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDelivered = order.status == OrderStatus.delivered;
    final isRejected = order.status == OrderStatus.rejected;

    return Container(
      width: double.infinity,
      color: Colors.white,
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: _statusColor(order.status).withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  order.status.label,
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: _statusColor(order.status),
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              if (!isDelivered && !isRejected && order.distanceKm > 0) ...[
                const SizedBox(width: 12),
                Text(
                  '${order.distanceKm.toStringAsFixed(1)} km',
                  style: theme.textTheme.bodyMedium,
                ),
              ],
            ],
          ),
          if (driverName != null) ...[
            const SizedBox(height: 10),
            Row(
              children: [
                const Icon(Icons.person_outline, size: 18),
                const SizedBox(width: 6),
                Text(
                  driverName!,
                  style: theme.textTheme.bodyMedium
                      ?.copyWith(fontWeight: FontWeight.w600),
                ),
              ],
            ),
          ],
          if ((order.driverPhone ?? '').isNotEmpty) ...[
            const SizedBox(height: 4),
            Row(
              children: [
                const Icon(Icons.phone_outlined, size: 18),
                const SizedBox(width: 6),
                Text(
                  order.driverPhone!,
                  style: theme.textTheme.bodyMedium,
                ),
              ],
            ),
          ],
          const SizedBox(height: 10),
          if ((order.pickupAddress ?? '').isNotEmpty)
            _AddressRow(
              icon: Icons.store_outlined,
              label: 'Recolha',
              value: order.pickupAddress!,
            ),
          if ((order.dropoffAddress ?? '').isNotEmpty) ...[
            const SizedBox(height: 4),
            _AddressRow(
              icon: Icons.flag_outlined,
              label: 'Entrega',
              value: order.dropoffAddress!,
            ),
          ],
          const SizedBox(height: 10),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Total',
                style: theme.textTheme.bodyMedium,
              ),
              Text(
                '€${order.total.toStringAsFixed(2)}',
                style: theme.textTheme.titleMedium
                    ?.copyWith(fontWeight: FontWeight.bold),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Color _statusColor(OrderStatus status) {
    switch (status) {
      case OrderStatus.delivered:
        return Colors.green.shade700;
      case OrderStatus.rejected:
        return Colors.red.shade700;
      case OrderStatus.driverAccepted:
      case OrderStatus.pickedUp:
      case OrderStatus.onTheWay:
        return Colors.blue.shade700;
      default:
        return Colors.orange.shade700;
    }
  }
}

class _AddressRow extends StatelessWidget {
  const _AddressRow({
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 16, color: Colors.grey.shade600),
        const SizedBox(width: 6),
        Expanded(
          child: RichText(
            text: TextSpan(
              style: theme.textTheme.bodySmall,
              children: [
                TextSpan(
                  text: '$label: ',
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
                TextSpan(text: value),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
