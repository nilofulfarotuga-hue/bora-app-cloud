import 'dart:async';

import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart' hide LatLng;
import 'package:latlong2/latlong.dart' as ll;
import 'package:provider/provider.dart';

import '../models/chat_message.dart';
import '../models/order_model.dart';
import '../services/directions_service.dart';
import '../services/navigation_service.dart';
import '../services/route_optimizer.dart';
import '../stores/driver_store.dart';
import '../stores/order_store.dart';
import '../utils/map_utils.dart';
import 'chat_screen.dart';
import 'driver_order_action_helper.dart';

const String _mapStyle = '''[
  {"featureType":"poi","stylers":[{"visibility":"off"}]},
  {"featureType":"transit","stylers":[{"visibility":"simplified"}]},
  {"featureType":"road","elementType":"labels.icon","stylers":[{"visibility":"off"}]},
  {"featureType":"road","elementType":"geometry.fill","stylers":[{"color":"#FFFFFF"}]},
  {"featureType":"road.arterial","elementType":"geometry.fill","stylers":[{"color":"#F3F4F6"}]},
  {"featureType":"road.highway","elementType":"geometry.fill","stylers":[{"color":"#E5E7EB"}]},
  {"featureType":"water","elementType":"geometry","stylers":[{"color":"#BAE6FD"}]},
  {"featureType":"landscape","elementType":"geometry","stylers":[{"color":"#F9FAFB"}]},
  {"featureType":"administrative","elementType":"labels.text.fill","stylers":[{"color":"#6B7280"}]}
]''';

class DriverMapScreen extends StatefulWidget {
  const DriverMapScreen({super.key});

  @override
  State<DriverMapScreen> createState() => _DriverMapScreenState();
}

class _DriverMapScreenState extends State<DriverMapScreen> {
  final Completer<GoogleMapController> _mapController = Completer();
  final DirectionsService _directionsService = DirectionsService();

  ll.LatLng? _lastAnimatedPosition;
  String? _lastAnimatedStopsKey;
  List<ll.LatLng> _routePoints = <ll.LatLng>[];
  String? _activeRouteKey;
  int _routeRequestId = 0;
  StreamSubscription<Position>? _positionSubscription;
  double? _routeDurationMinutes;
  ll.LatLng? _lastRouteOrigin;

  // Debounce timer: delays the Directions API call by 2.5 s after the last
  // qualifying movement, preventing bursts during rapid position updates.
  Timer? _debounceTimer;

  @override
  void initState() {
    super.initState();
    _listenToDriverLocation();
  }

  @override
  void dispose() {
    _debounceTimer?.cancel();
    _positionSubscription?.cancel();
    _directionsService.dispose();
    super.dispose();
  }

  Future<void> _listenToDriverLocation() async {
    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }

    if (permission == LocationPermission.denied ||
        permission == LocationPermission.deniedForever) {
      return;
    }

    _positionSubscription = Geolocator.getPositionStream(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 5,
      ),
    ).listen((position) {
      if (!mounted) return;

      final orderStore = context.read<OrderStore>();
      if (orderStore.myOrders.isEmpty) return;

      final driverStore = context.read<DriverStore>();
      final updatedLocation = ll.LatLng(position.latitude, position.longitude);

      driverStore.updateDriverLocation(
        driverStore.currentDriverId,
        updatedLocation,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final orderStore = context.watch<OrderStore>();
    final driverStore = context.watch<DriverStore>();

    final driver = driverStore.currentDriver;
    if (driver == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Mapa da entrega')),
        body: const Center(
          child: Padding(
            padding: EdgeInsets.all(24),
            child: Text('Estafeta não configurado.', textAlign: TextAlign.center),
          ),
        ),
      );
    }

    final myOrders = orderStore.myOrders;
    if (myOrders.isEmpty) {
      return Scaffold(
        appBar: AppBar(title: const Text('Mapa da entrega')),
        body: const Center(
          child: Padding(
            padding: EdgeInsets.all(24),
            child: Text(
              'Aceite um pedido para visualizar a rota.',
              textAlign: TextAlign.center,
            ),
          ),
        ),
      );
    }

    final driverPosition = driver.location;
    final optimizedRoute = RouteOptimizer.optimize(myOrders, driverPosition);
    final nextStop = optimizedRoute.stops.isNotEmpty ? optimizedRoute.stops.first : null;

    // Focus order: the order whose next stop comes first.
    final focusOrder = nextStop != null
        ? myOrders.firstWhere(
            (o) => o.id == nextStop.orderId,
            orElse: () => myOrders.first,
          )
        : myOrders.first;

    // Trigger multi-stop route fetch.
    if (nextStop != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _updateRouteMulti(driverPosition, optimizedRoute.stops);
      });
    } else if (_routePoints.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        setState(() {
          _routePoints = <ll.LatLng>[];
          _activeRouteKey = null;
          _routeDurationMinutes = null;
          _lastRouteOrigin = null;
        });
      });
    }

    // ── Markers ────────────────────────────────────────────────────────────
    final markers = <Marker>{
      Marker(
        markerId: const MarkerId('driver'),
        position: driverPosition.toGMaps(),
        icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueAzure),
        infoWindow: const InfoWindow(title: 'Estafeta'),
        zIndex: 2,
      ),
    };

    for (var i = 0; i < optimizedRoute.stops.length; i++) {
      final stop = optimizedRoute.stops[i];
      final isPickup = stop.isPickup;
      final stepLabel = optimizedRoute.stops.length > 1 ? ' ${i + 1}' : '';
      markers.add(
        Marker(
          markerId: MarkerId('stop_$i'),
          position: stop.location.toGMaps(),
          icon: BitmapDescriptor.defaultMarkerWithHue(
            isPickup ? BitmapDescriptor.hueOrange : BitmapDescriptor.hueRed,
          ),
          infoWindow: InfoWindow(
            title: isPickup ? 'Recolha$stepLabel' : 'Entrega$stepLabel',
            snippet: stop.label,
          ),
          zIndex: 1,
        ),
      );
    }

    // ── Polyline ────────────────────────────────────────────────────────────
    final allStopPoints = [
      driverPosition,
      ...optimizedRoute.stops.map((s) => s.location),
    ];

    final polylines = <Polyline>{};
    if (_routePoints.isNotEmpty) {
      polylines.add(
        Polyline(
          polylineId: const PolylineId('driver-route'),
          color: const Color(0xFF1C6EF2),
          width: 6,
          points: _routePoints.toGMaps(),
          startCap: Cap.roundCap,
          endCap: Cap.roundCap,
          jointType: JointType.round,
        ),
      );
    } else if (nextStop != null) {
      polylines.add(
        Polyline(
          polylineId: const PolylineId('driver-route'),
          color: const Color(0xFF1C6EF2),
          width: 5,
          points: allStopPoints.toGMaps(),
          patterns: [PatternItem.dash(20), PatternItem.gap(10)],
          startCap: Cap.roundCap,
          endCap: Cap.roundCap,
        ),
      );
    }

    // ── Camera ──────────────────────────────────────────────────────────────
    final stopsKey = optimizedRoute.stops.map((s) => s.orderId).join(',');

    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      if (!_mapController.isCompleted) return;
      if (_lastAnimatedPosition == driverPosition &&
          _lastAnimatedStopsKey == stopsKey) {
        return;
      }

      _lastAnimatedPosition = driverPosition;
      _lastAnimatedStopsKey = stopsKey;

      final controller = await _mapController.future;
      final bounds = boundsFromPoints(
        _routePoints.isNotEmpty ? _routePoints : allStopPoints,
      );

      if (bounds != null) {
        await controller.animateCamera(
          CameraUpdate.newLatLngBounds(bounds, 100),
        );
      }
    });

    final nextAction = resolveDriverOrderAction(orderStore, focusOrder);
    final topPadding = MediaQuery.of(context).padding.top;
    final mapCenter = nextStop?.location ?? driverPosition;

    return Scaffold(
      body: Stack(
        children: [
          GoogleMap(
            initialCameraPosition: CameraPosition(
              target: mapCenter.toGMaps(),
              zoom: 14,
            ),
            markers: markers,
            polylines: polylines,
            myLocationEnabled: true,
            myLocationButtonEnabled: false,
            zoomControlsEnabled: false,
            mapToolbarEnabled: false,
            onMapCreated: (controller) {
              if (!_mapController.isCompleted) {
                _mapController.complete(controller);
              }
              controller.setMapStyle(_mapStyle);
            },
          ),

          // Back button
          Positioned(
            top: topPadding + 8,
            left: 12,
            child: _MapButton(
              icon: Icons.arrow_back,
              onTap: () => Navigator.of(context).maybePop(),
            ),
          ),

          // Center-on-driver button
          Positioned(
            top: topPadding + 8,
            right: 12,
            child: _MapButton(
              icon: Icons.my_location,
              onTap: () async {
                if (!_mapController.isCompleted) return;
                final controller = await _mapController.future;
                controller.animateCamera(
                  CameraUpdate.newLatLng(driverPosition.toGMaps()),
                );
              },
            ),
          ),

          // Bottom info panel
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: _BottomPanel(
              focusOrder: focusOrder,
              nextStop: nextStop,
              allStops: optimizedRoute.stops,
              nextAction: nextAction,
              routeDurationMinutes: _routeDurationMinutes,
            ),
          ),
        ],
      ),
    );
  }

  void _updateRouteMulti(ll.LatLng origin, List<RouteStop> stops) {
    if (stops.isEmpty) return;

    final destination = stops.last.location;
    final waypointLocations = stops.length > 1
        ? stops.take(stops.length - 1).map((s) => s.location).toList()
        : const <ll.LatLng>[];

    // Build a key encoding origin + every stop location.
    final stopPart = stops
        .map(
          (s) =>
              '${s.location.latitude.toStringAsFixed(5)},${s.location.longitude.toStringAsFixed(5)}',
        )
        .join('|');
    final key =
        '${origin.latitude.toStringAsFixed(5)},${origin.longitude.toStringAsFixed(5)}|$stopPart';

    // Exact same request already pending or resolved — nothing to do.
    if (_activeRouteKey == key && _routePoints.isNotEmpty) return;

    // 50 m throttle: when only the origin changes (stops are the same),
    // skip unless the driver has moved at least 50 m since the last fetch.
    if (_routePoints.isNotEmpty && _lastRouteOrigin != null) {
      final lastStopPart = _activeRouteKey?.split('|').skip(1).join('|') ?? '';
      if (stopPart == lastStopPart) {
        final movedKm = const ll.Distance().as(
          ll.LengthUnit.Kilometer,
          _lastRouteOrigin!,
          origin,
        );
        if (movedKm < 0.05) return;
      }
    }

    // Record now so duplicate calls within the debounce window return early.
    _activeRouteKey = key;
    _lastRouteOrigin = origin;

    // Debounce: cancel any pending timer and reschedule.
    // The API call fires only after 2.5 s of inactivity, batching rapid
    // position updates into a single request.
    _debounceTimer?.cancel();
    _debounceTimer = Timer(const Duration(milliseconds: 2500), () {
      if (!mounted) return;
      final requestId = ++_routeRequestId;

      _directionsService
          .fetchRoute(
            origin: origin,
            destination: destination,
            waypoints: waypointLocations,
          )
          .then((route) {
        if (!mounted || _routeRequestId != requestId) return;

        if (route != null && route.points.isNotEmpty) {
          // Only rebuild if the route meaningfully changed — prevents flicker
          // when the driver moves slightly and the road path is unchanged.
          if (_routePointsChanged(route.points)) {
            setState(() {
              _routePoints = route.points;
              _routeDurationMinutes = route.durationMinutes;
            });
          }
        } else {
          // API failed: preserve last real polyline and ETA to avoid flicker
          // and ETA reset. Show straight-line only on the very first load.
          if (_routePoints.isEmpty) {
            setState(() {
              _routePoints = [origin, ...stops.map((s) => s.location)];
              // _routeDurationMinutes left null — no ETA yet.
            });
          }
          // else: keep existing polyline and existing _routeDurationMinutes.
        }
      });
    });
  }

  /// Returns true when [newPoints] differs enough from [_routePoints] to
  /// warrant a polyline redraw. Compares point count + first/last coordinates.
  bool _routePointsChanged(List<ll.LatLng> newPoints) {
    if (newPoints.length != _routePoints.length) return true;
    if (newPoints.isEmpty) return false;
    const eps = 1e-6;
    final nf = newPoints.first;
    final nl = newPoints.last;
    final cf = _routePoints.first;
    final cl = _routePoints.last;
    return (nf.latitude - cf.latitude).abs() > eps ||
        (nf.longitude - cf.longitude).abs() > eps ||
        (nl.latitude - cl.latitude).abs() > eps ||
        (nl.longitude - cl.longitude).abs() > eps;
  }
}

// ─── Bottom panel ─────────────────────────────────────────────────────────────

class _BottomPanel extends StatefulWidget {
  const _BottomPanel({
    required this.focusOrder,
    required this.nextStop,
    required this.allStops,
    required this.nextAction,
    this.routeDurationMinutes,
  });

  final OrderModel focusOrder;
  final RouteStop? nextStop;
  final List<RouteStop> allStops;
  final DriverOrderAction? nextAction;
  final double? routeDurationMinutes;

  @override
  State<_BottomPanel> createState() => _BottomPanelState();
}

class _BottomPanelState extends State<_BottomPanel> {
  bool _isLoading = false;

  bool get _isMultiStop => widget.allStops.length > 1;

  @override
  Widget build(BuildContext context) {
    final focusOrder = widget.focusOrder;
    final nextStop = widget.nextStop;
    final nextAction = widget.nextAction;
    final eta = widget.routeDurationMinutes != null
        ? '${widget.routeDurationMinutes!.round()} min'
        : null;

    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.only(
          topLeft: Radius.circular(24),
          topRight: Radius.circular(24),
        ),
        boxShadow: [
          BoxShadow(
            color: Color(0x26000000),
            blurRadius: 16,
            offset: Offset(0, -4),
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Drag handle
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.grey.shade300,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 16),

              // Status + ETA row
              Row(
                children: [
                  _StatusBadge(status: focusOrder.status),
                  const Spacer(),
                  if (eta != null) ...[
                    Icon(Icons.access_time_rounded,
                        size: 16, color: Colors.grey.shade600),
                    const SizedBox(width: 4),
                    Text(
                      eta,
                      style: const TextStyle(
                          fontWeight: FontWeight.w700, fontSize: 15),
                    ),
                  ],
                ],
              ),
              const SizedBox(height: 16),

              if (_isMultiStop)
                _StopList(stops: widget.allStops)
              else
                _SingleOrderAddresses(order: focusOrder),

              const SizedBox(height: 16),
              const Divider(height: 1),
              const SizedBox(height: 14),

              // Stats row
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  _InfoItem(
                    icon: Icons.receipt_long_outlined,
                    label: 'Pedido',
                    value: '€${focusOrder.total.toStringAsFixed(2)}',
                  ),
                  _InfoItem(
                    icon: Icons.payments_outlined,
                    label: 'Ganhos',
                    value: '+€${focusOrder.driverEarnings.toStringAsFixed(2)}',
                    valueColor: Colors.green.shade700,
                  ),
                  _InfoItem(
                    icon: Icons.route_outlined,
                    label: 'Distância',
                    value: '${focusOrder.distanceKm.toStringAsFixed(1)} km',
                  ),
                ],
              ),

              const SizedBox(height: 16),

              // Action buttons row
              Row(
                children: [
                  OutlinedButton.icon(
                    onPressed: nextStop == null
                        ? null
                        : () => NavigationService.openNavigationOptions(
                              context,
                              nextStop.location,
                            ),
                    icon: const Icon(Icons.navigation_outlined, size: 18),
                    label: const Text('Navegar'),
                    style: OutlinedButton.styleFrom(
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 12),
                    ),
                  ),
                  if (nextAction != null) ...[
                    const SizedBox(width: 12),
                    Expanded(
                      child: ElevatedButton(
                        onPressed: _isLoading
                            ? null
                            : () async {
                                // Capture before async gap: the widget may be
                                // disposed when finishOrder removes it from
                                // myOrders, making mounted == false too early.
                                final action = nextAction;
                                final willFinish = widget.focusOrder.status ==
                                    OrderStatus.onTheWay;
                                final messenger =
                                    ScaffoldMessenger.of(context);
                                final navigator = Navigator.of(context);
                                setState(() => _isLoading = true);
                                final success = await action.execute();
                                if (success) {
                                  messenger.showSnackBar(
                                    SnackBar(
                                      content: Text(action.successMessage),
                                      duration: const Duration(seconds: 2),
                                    ),
                                  );
                                  // After delivery, myOrders is empty and this
                                  // widget is already disposed — pop explicitly.
                                  if (willFinish) navigator.maybePop();
                                } else {
                                  if (mounted) {
                                    setState(() => _isLoading = false);
                                  }
                                  messenger.showSnackBar(
                                    const SnackBar(
                                      content: Text(
                                          'Não foi possível atualizar o pedido.'),
                                    ),
                                  );
                                }
                              },
                        style: ElevatedButton.styleFrom(
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          padding: const EdgeInsets.symmetric(vertical: 14),
                        ),
                        child: _isLoading
                            ? const SizedBox(
                                height: 18,
                                width: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              )
                            : Text(
                                nextAction.label,
                                style: const TextStyle(
                                    fontWeight: FontWeight.w600),
                              ),
                      ),
                    ),
                  ],
                ],
              ),

              // Finalize purchase — non-partner only, while driver has the goods
              if (!_isMultiStop &&
                  !focusOrder.isPartnerStore &&
                  (focusOrder.status == OrderStatus.pickedUp ||
                      focusOrder.status == OrderStatus.onTheWay)) ...[
                const SizedBox(height: 12),
                if (focusOrder.isPurchaseFinalized &&
                    focusOrder.finalTotal != null)
                  _FinalizedBanner(finalTotal: focusOrder.finalTotal!)
                else
                  _FinalizePurchaseButton(order: focusOrder),
              ],

              // Chat button — always visible for active single orders
              if (!_isMultiStop) ...[
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => ChatScreen(
                          order: focusOrder,
                          senderType: ChatSenderType.driver,
                        ),
                      ),
                    ),
                    icon: const Icon(Icons.chat_bubble_outline),
                    label: const Text('Chat com cliente'),
                  ),
                ),
              ],

              // Customer notes (single order only — too noisy for multi)
              if (!_isMultiStop &&
                  focusOrder.customerNotes != null &&
                  focusOrder.customerNotes!.isNotEmpty) ...[
                const SizedBox(height: 12),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.grey.shade50,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: Colors.grey.shade200),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.notes_rounded,
                          size: 16, color: Colors.grey.shade500),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          focusOrder.customerNotes!,
                          style: TextStyle(
                              fontSize: 13, color: Colors.grey.shade700),
                        ),
                      ),
                    ],
                  ),
                ),
              ],

              if (!_isMultiStop && focusOrder.apartmentDelivery) ...[
                const SizedBox(height: 12),
                const _ApartmentDeliveryBanner(),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

// ─── Stop list (multi-order) ──────────────────────────────────────────────────

class _StopList extends StatelessWidget {
  const _StopList({required this.stops});

  final List<RouteStop> stops;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 0; i < stops.length; i++) ...[
          _StopRow(stop: stops[i], index: i),
          if (i < stops.length - 1)
            Padding(
              padding: const EdgeInsets.only(left: 15),
              child: Container(
                height: 14,
                width: 2,
                color: Colors.grey.shade300,
              ),
            ),
        ],
      ],
    );
  }
}

class _StopRow extends StatelessWidget {
  const _StopRow({required this.stop, required this.index});

  final RouteStop stop;
  final int index;

  @override
  Widget build(BuildContext context) {
    final isPickup = stop.isPickup;
    final color = isPickup ? Colors.orange.shade600 : const Color(0xFF1C6EF2);
    final icon = isPickup ? Icons.circle : Icons.location_on_rounded;
    final iconSize = isPickup ? 11.0 : 18.0;
    final typeLabel = isPickup ? 'Recolha' : 'Entrega';

    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        // Step pill
        Container(
          width: 20,
          height: 20,
          decoration: BoxDecoration(
            color: color.withOpacity(0.12),
            shape: BoxShape.circle,
          ),
          alignment: Alignment.center,
          child: Text(
            '${index + 1}',
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w700,
              color: color,
            ),
          ),
        ),
        const SizedBox(width: 8),
        // Type icon
        SizedBox(
          width: 20,
          child: Icon(icon, size: iconSize, color: color),
        ),
        const SizedBox(width: 8),
        // Address
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                typeLabel,
                style: TextStyle(
                  fontSize: 11,
                  color: Colors.grey.shade500,
                  fontWeight: FontWeight.w500,
                ),
              ),
              Text(
                stop.label ?? (isPickup ? 'Recolha' : 'Entrega'),
                style: const TextStyle(
                    fontSize: 13, fontWeight: FontWeight.w500),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ],
    );
  }
}

// ─── Single-order address rows ────────────────────────────────────────────────

class _SingleOrderAddresses extends StatelessWidget {
  const _SingleOrderAddresses({required this.order});

  final OrderModel order;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _AddressRow(
          icon: Icons.circle,
          iconColor: Colors.orange.shade600,
          iconSize: 11,
          label: order.pickupAddress ?? 'Recolha',
        ),
        Padding(
          padding: const EdgeInsets.only(left: 5),
          child: Container(height: 18, width: 2, color: Colors.grey.shade300),
        ),
        _AddressRow(
          icon: Icons.location_on_rounded,
          iconColor: const Color(0xFF1C6EF2),
          iconSize: 18,
          label: order.dropoffAddress ?? 'Entrega',
        ),
      ],
    );
  }
}

// ─── Supporting widgets ───────────────────────────────────────────────────────

class _MapButton extends StatelessWidget {
  const _MapButton({required this.icon, required this.onTap});

  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(12),
      elevation: 4,
      shadowColor: const Color(0x33000000),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Icon(icon, size: 22),
        ),
      ),
    );
  }
}

class _StatusBadge extends StatelessWidget {
  const _StatusBadge({required this.status});

  final OrderStatus status;

  Color get _color {
    switch (status) {
      case OrderStatus.created:
      case OrderStatus.preparing:
        return Colors.orange;
      case OrderStatus.callingDriver:
      case OrderStatus.driverAccepted:
        return const Color(0xFF1C6EF2);
      case OrderStatus.pickedUp:
      case OrderStatus.onTheWay:
        return Colors.green;
      case OrderStatus.delivered:
        return Colors.green;
      case OrderStatus.rejected:
        return Colors.red;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: _color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(color: _color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 6),
          Text(
            status.label,
            style: TextStyle(
              color: _color,
              fontWeight: FontWeight.w600,
              fontSize: 13,
            ),
          ),
        ],
      ),
    );
  }
}

class _AddressRow extends StatelessWidget {
  const _AddressRow({
    required this.icon,
    required this.iconColor,
    required this.iconSize,
    required this.label,
  });

  final IconData icon;
  final Color iconColor;
  final double iconSize;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        SizedBox(
          width: 22,
          child: Icon(icon, size: iconSize, color: iconColor),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            label,
            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }
}

class _InfoItem extends StatelessWidget {
  const _InfoItem({
    required this.icon,
    required this.label,
    required this.value,
    this.valueColor,
  });

  final IconData icon;
  final String label;
  final String value;
  final Color? valueColor;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 18, color: Colors.grey.shade500),
        const SizedBox(height: 4),
        Text(
          value,
          style: TextStyle(
            fontWeight: FontWeight.w700,
            fontSize: 14,
            color: valueColor,
          ),
        ),
        Text(
          label,
          style: TextStyle(fontSize: 11, color: Colors.grey.shade500),
        ),
      ],
    );
  }
}

// ─── Finalize purchase ────────────────────────────────────────────────────────

/// Button shown while purchase is not yet finalized.
/// Opens a dialog, validates input, then calls [OrderStore.finalizePurchase].
class _FinalizePurchaseButton extends StatefulWidget {
  const _FinalizePurchaseButton({required this.order});

  final OrderModel order;

  @override
  State<_FinalizePurchaseButton> createState() =>
      _FinalizePurchaseButtonState();
}

class _FinalizePurchaseButtonState extends State<_FinalizePurchaseButton> {
  bool _loading = false;

  Future<void> _openDialog() async {
    final value = await showDialog<double>(
      context: context,
      builder: (_) => const _FinalizePurchaseDialog(),
    );
    if (value == null || !mounted) return;

    setState(() => _loading = true);
    await context.read<OrderStore>().finalizePurchase(
          orderId: widget.order.id,
          purchaseValue: value,
        );
    if (mounted) setState(() => _loading = false);
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: OutlinedButton.icon(
        onPressed: _loading ? null : _openDialog,
        icon: _loading
            ? SizedBox(
                height: 16,
                width: 16,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Colors.orange.shade700,
                ),
              )
            : const Icon(Icons.shopping_cart_checkout_outlined, size: 18),
        label: const Text('Finalizar compra'),
        style: OutlinedButton.styleFrom(
          foregroundColor: Colors.orange.shade700,
          side: BorderSide(color: Colors.orange.shade300),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          padding: const EdgeInsets.symmetric(vertical: 12),
        ),
      ),
    );
  }
}

/// Dialog that collects and validates the real purchase amount from the driver.
class _FinalizePurchaseDialog extends StatefulWidget {
  const _FinalizePurchaseDialog();

  @override
  State<_FinalizePurchaseDialog> createState() =>
      _FinalizePurchaseDialogState();
}

class _FinalizePurchaseDialogState extends State<_FinalizePurchaseDialog> {
  final _controller = TextEditingController();
  String? _error;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _confirm() {
    final text = _controller.text.trim();
    if (text.isEmpty) {
      setState(() => _error = 'Introduza um valor');
      return;
    }
    final value = double.tryParse(text.replaceAll(',', '.'));
    if (value == null || value <= 0) {
      setState(() => _error = 'Valor inválido');
      return;
    }
    Navigator.pop(context, value);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Valor da compra'),
      content: TextField(
        controller: _controller,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        autofocus: true,
        decoration: InputDecoration(
          hintText: 'Ex: 18.50',
          prefixText: '€ ',
          errorText: _error,
          border: const OutlineInputBorder(),
        ),
        onSubmitted: (_) => _confirm(),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancelar'),
        ),
        TextButton(
          onPressed: _confirm,
          child: const Text('Confirmar'),
        ),
      ],
    );
  }
}

/// Banner shown after the driver has confirmed the real purchase value.
class _FinalizedBanner extends StatelessWidget {
  const _FinalizedBanner({required this.finalTotal});

  final double finalTotal;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.green.shade50,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.green.shade200),
      ),
      child: Row(
        children: [
          Icon(Icons.check_circle_outline,
              color: Colors.green.shade700, size: 18),
          const SizedBox(width: 8),
          Text(
            'Compra finalizada: €${finalTotal.toStringAsFixed(2)}',
            style: TextStyle(
              color: Colors.green.shade700,
              fontWeight: FontWeight.w600,
              fontSize: 13,
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────

class _ApartmentDeliveryBanner extends StatelessWidget {
  const _ApartmentDeliveryBanner();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final iconColor = Colors.orange.shade600;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.orange.shade50,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.orange.shade200),
      ),
      child: Row(
        children: [
          Icon(Icons.apartment, color: iconColor),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              'Apartment delivery requested — +€1 bonus',
              style: theme.textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.w600,
                color: Colors.orange.shade800,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
