import 'dart:async';

import 'package:flutter/foundation.dart' show defaultTargetPlatform, TargetPlatform;
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart' hide LatLng;
import 'package:latlong2/latlong.dart' as ll;
import 'package:provider/provider.dart';

import '../config/business_rules.dart' show BRDriver;
import '../models/chat_message.dart';
import '../models/order_model.dart';
import '../services/directions_service.dart';
import '../services/navigation_service.dart';
import '../services/route_optimizer.dart';
import '../stores/driver_store.dart';
import '../stores/order_store.dart';
import '../utils/map_marker_helper.dart';
import '../utils/map_utils.dart';
import '../widgets/address_text.dart';
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
  GoogleMapController? _mapController;
  late DriverStore _driverStore;
  final DirectionsService _directionsService = DirectionsService();

  /// One-shot GPS result — drives the camera follow logic AFTER the map is
  /// already rendered. Does NOT gate rendering.
  ll.LatLng? _gpsCenter;

  /// IMMUTABLE initial camera target. Captured ONCE in [initState] and never
  /// recomputed — GoogleMap.initialCameraPosition only reads this on the very
  /// first creation, and Flutter Web is sensitive to target values changing
  /// during the first frame. Keeping it stable guarantees the PlatformView
  /// mounts deterministically on frame 1.
  late final ll.LatLng _stableInitialCenter;

  /// Fallback coordinate used when nothing else is known (centro de Portugal).
  static const ll.LatLng _defaultFallbackCenter = ll.LatLng(38.7223, -9.1393);

  /// GoogleMap created once, never destroyed. Prevents PlatformView crash.
  bool _mapReady = false;

  String? _lastAnimatedStopsKey;
  List<ll.LatLng> _routePoints = <ll.LatLng>[];
  String? _activeRouteKey;
  int _routeRequestId = 0;
  StreamSubscription<Position>? _positionSubscription;
  double? _routeDurationMinutes;
  ll.LatLng? _lastRouteOrigin;

  // ── Smooth movement interpolation (Uber-style) ────────────────────────────
  //
  // Every GPS fix triggers an interpolation from the CURRENT displayed
  // position (_smoothedPosition) to the new raw GPS position. Both the
  // marker and the camera animate in sync, frame by frame, at ~60 fps.
  //
  // Key invariants:
  //   • _smoothedPosition is the source of truth for the MARKER/CAMERA.
  //   • driver.location (DriverStore) remains the raw GPS source of truth
  //     and drives routes / RouteOptimizer (no jitter in polylines).
  //   • Restarting mid-animation always resumes from the current interpolated
  //     position, never from the previous start — no snap-back artefacts.
  ll.LatLng? _smoothedPosition;
  Timer? _interpolationTimer;
  static const Duration _interpolationDuration = Duration(milliseconds: 600);
  static const Duration _interpolationFrame = Duration(milliseconds: 16); // ~60 fps
  static const double _jitterThresholdMetres = 1.0; // skip animation below this

  // Debounce timer: delays the Directions API call by 2.5 s after the last
  // qualifying movement, preventing bursts during rapid position updates.
  Timer? _debounceTimer;

  @override
  void initState() {
    super.initState();
    // Capture DriverStore once in initState so fallback logic can access it
    // safely without async context issues.
    _driverStore = context.read<DriverStore>();

    // Freeze the initial camera target for the lifetime of this State.
    // Priority: current driver location → fallback padrão.
    // This value is passed to GoogleMap.initialCameraPosition ONCE and then
    // never changes, regardless of GPS, store, realtime, or any async event.
    _stableInitialCenter =
        _driverStore.currentDriver?.location ?? _defaultFallbackCenter;

    MapMarkerHelper.preload();
    _startLocationTracking();
  }

  @override
  void dispose() {
    _debounceTimer?.cancel();
    _interpolationTimer?.cancel();
    _positionSubscription?.cancel();
    _directionsService.dispose();
    super.dispose();
  }

  /// Single entry point for all GPS tracking.
  ///
  /// Flow:
  ///   1. Check GPS service enabled   → show snackbar + fallback if not.
  ///   2. Check/request permission    → show snackbar + fallback if denied.
  ///   3. getLastKnownPosition()      → instant unblock of GPS-first guard.
  ///   4. getPositionStream()         → continuous real-time tracking.
  ///      On Android: uses AndroidSettings with ForegroundNotificationConfig
  ///      so the stream survives app minimisation (foreground service).
  Future<void> _startLocationTracking() async {
    
    // ── 1. GPS service check ────────────────────────────────────────────────
    final serviceEnabled = await Geolocator.isLocationServiceEnabled();
    
    if (!serviceEnabled) {
      if (!mounted) return;
      // GPS is disabled — attempt to unblock rendering with DriverStore fallback
      final fallback = _driverStore.currentDriver?.location;
      
      if (fallback != null && mounted) {
        setState(() => _gpsCenter = fallback);
        _mapController?.animateCamera(CameraUpdate.newLatLng(fallback.toGMaps()));
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('GPS desativado. Ative a localização para tracking.'),
          duration: Duration(seconds: 8),
          action: SnackBarAction(
            label: 'Ativar',
            onPressed: Geolocator.openLocationSettings,
          ),
        ),
      );
      return;
    }

    // ── 2. Permission check/request ─────────────────────────────────────────
    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    if (!mounted) return;

    if (permission == LocationPermission.deniedForever) {
      // Location permission permanently denied — attempt to unblock rendering
      final fallback = _driverStore.currentDriver?.location;
      if (fallback != null && mounted) {
        setState(() => _gpsCenter = fallback);
        _mapController?.animateCamera(CameraUpdate.newLatLng(fallback.toGMaps()));
      }
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
      // Location permission denied — attempt to unblock rendering
      final fallback = _driverStore.currentDriver?.location;
      if (fallback != null && mounted) {
        setState(() => _gpsCenter = fallback);
        _mapController?.animateCamera(CameraUpdate.newLatLng(fallback.toGMaps()));
      }
      return;
    }

    // ── 3. Fast path: last known position (OS cache, no hardware query) ─────
    // Unblocks the GPS-first rendering guard without waiting for a new fix.
    // On Web, getLastKnownPosition may be slow or unreliable, so use timeout.
    try {
      
      final last = await Geolocator.getLastKnownPosition()
          .timeout(const Duration(seconds: 5), onTimeout: () {
        
        return null;
      });
      
      if (last != null && mounted && _gpsCenter == null) {
        final loc = ll.LatLng(last.latitude, last.longitude);
        setState(() => _gpsCenter = loc);
        _mapController?.animateCamera(CameraUpdate.newLatLng(loc.toGMaps()));
        // DO NOT add postFrameCallback here — setState above already triggers
        // rebuild. The GoogleMap's ValueKey(_gpsCenter) detects the change.
        final driverStore = context.read<DriverStore>();
        driverStore.updateDriverLocation(driverStore.currentDriverId, loc);
      } else if (mounted && _gpsCenter == null) {
        // getLastKnownPosition() returned null (cold start / no OS cache).
        // Attempt to unblock the rendering guard using the last position
        // already held by DriverStore. If that's also null, use a safe default
        // and wait for stream to refine with real GPS.
        final fallback = _driverStore.currentDriver?.location;
        
        if (fallback != null) {
          setState(() => _gpsCenter = fallback);
          _mapController?.animateCamera(CameraUpdate.newLatLng(fallback.toGMaps()));
        } else {
          // Último recurso: centro padrão para desbloquear renderização.
          // O stream substituirá com GPS real assim que disponível.
          setState(() => _gpsCenter = _defaultFallbackCenter);
          _mapController?.animateCamera(
              CameraUpdate.newLatLng(_defaultFallbackCenter.toGMaps()));

        }
        // Stream will refine with real GPS location (see line 214-220)
      }
    } catch (e) {
      // Non-fatal — stream still provides a real fix.
      
    }

    // ── 4. Continuous stream ─────────────────────────────────────────────────
    // Real-time GPS tracking (Uber-style): continuous position updates
    // with best accuracy and no distance filtering.
    // AndroidSettings with ForegroundNotificationConfig keeps the stream alive
    // even when the app is minimised (Android foreground service).
    // On iOS, standard LocationSettings suffice (the OS handles background).
    final LocationSettings locationSettings;
    if (defaultTargetPlatform == TargetPlatform.android) {
      locationSettings = AndroidSettings(
        // bestForNavigation: highest accuracy, continuous updates
        accuracy: LocationAccuracy.bestForNavigation,
        // distanceFilter: 0 = update on every movement (no throttling)
        distanceFilter: 0,
        // Update frequency: 1 second (fast enough for real-time tracking)
        intervalDuration: const Duration(seconds: 1),
        foregroundNotificationConfig: const ForegroundNotificationConfig(
          notificationTitle: 'BORA em execução',
          notificationText: 'Localização ativa para entregas',
          enableWakeLock: true,
        ),
      );
    } else {
      locationSettings = const LocationSettings(
        // bestForNavigation: highest accuracy for navigation apps
        accuracy: LocationAccuracy.bestForNavigation,
        // distanceFilter: 0 = update on every movement (no throttling)
        distanceFilter: 0,
      );
    }

    _positionSubscription = Geolocator.getPositionStream(
      locationSettings: locationSettings,
    ).listen((position) {
      if (!mounted) return;
      final newLoc = ll.LatLng(position.latitude, position.longitude);

      // Update _gpsCenter (always)
      if (_gpsCenter != newLoc) {
        _gpsCenter = newLoc;
        // Start a smooth interpolation from the currently-displayed position
        // to the new raw GPS fix (marker + camera together).
        _animateToNewPosition(newLoc);
      }

      // DriverStore remains the single source of truth for raw location.
      // Route computation (RouteOptimizer) still reads driver.location —
      // the smoothed overlay only affects the marker and camera.
      final driverStore = context.read<DriverStore>();
      driverStore.updateDriverLocation(driverStore.currentDriverId, newLoc);
    });
  }

  /// Smooth Uber-style interpolation from the CURRENT displayed position to
  /// the new GPS fix. Updates both the marker (via [_smoothedPosition] +
  /// setState) and the camera (via [animateCamera]) in lockstep at ~60 fps.
  ///
  /// Re-entrancy safe: if a new GPS fix arrives while an animation is
  /// running, the current interpolated position becomes the new start — no
  /// snap-back, no concurrent animations.
  void _animateToNewPosition(ll.LatLng newPos) {
    // Cancel any running animation. The next call will start from whatever
    // _smoothedPosition is RIGHT NOW (the last interpolated frame), not from
    // the previous animation's starting point.
    _interpolationTimer?.cancel();
    _interpolationTimer = null;

    // First fix ever — snap directly, no animation required.
    if (_smoothedPosition == null) {
      _smoothedPosition = newPos;
      if (mounted) setState(() {});
      _mapController?.animateCamera(
        CameraUpdate.newLatLng(newPos.toGMaps()),
      );
      return;
    }

    final startPos = _smoothedPosition!;

    // Jitter filter: ignore sub-metre noise to avoid pointless animations
    // when the driver is stationary.
    final distanceMetres = const ll.Distance().as(
      ll.LengthUnit.Meter,
      startPos,
      newPos,
    );
    if (distanceMetres < _jitterThresholdMetres) {
      return;
    }

    final totalFrames =
        (_interpolationDuration.inMilliseconds / _interpolationFrame.inMilliseconds)
            .round();
    var currentFrame = 0;

    _interpolationTimer = Timer.periodic(_interpolationFrame, (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      currentFrame++;
      final progress = (currentFrame / totalFrames).clamp(0.0, 1.0);

      // Linear interpolation (fast, predictable, matches Uber's behaviour).
      final lat = startPos.latitude +
          (newPos.latitude - startPos.latitude) * progress;
      final lng = startPos.longitude +
          (newPos.longitude - startPos.longitude) * progress;
      final intermediate = ll.LatLng(lat, lng);

      // Marker position (drives build()) + camera follow in lockstep.
      setState(() {
        _smoothedPosition = intermediate;
      });
      _mapController?.animateCamera(
        CameraUpdate.newLatLng(intermediate.toGMaps()),
      );

      if (currentFrame >= totalFrames) {
        // Clamp to exact target and stop.
        _smoothedPosition = newPos;
        timer.cancel();
        _interpolationTimer = null;
      }
    });
  }

  /// Resolves the GPS-first rendering guard using the DriverStore location
  /// when real GPS is unavailable (permission denied, service disabled, etc.).
  /// Note: This method is no longer called; fallback check is inlined in
  /// _startLocationTracking() to avoid silent failures when location is null.
  void _resolveGpsTrackingFallback() {
    if (!mounted) return;
    final fallback = _driverStore.currentDriver?.location;
    if (fallback != null) {
      setState(() => _gpsCenter = fallback);
      _mapController?.animateCamera(CameraUpdate.newLatLng(fallback.toGMaps()));
    }
  }

  @override
  Widget build(BuildContext context) {
    // Watch OrderStore so the widget rebuilds when an order is accepted/updated.
    // DriverStore uses read (location updates handled via setState in GPS stream).
    final driverStore = context.read<DriverStore>();
    final orderStore = context.watch<OrderStore>();

    // NO early returns. GoogleMap must mount on the FIRST frame regardless of
    // whether the driver has been hydrated yet. When the driver is null we
    // still render a fully functional map using the stable fallback center;
    // markers/routes simply populate on the next rebuild once the driver
    // becomes available.
    final driver = driverStore.currentDriver;

    // Mark map as ready on first render (kept for future diagnostics).
    if (!_mapReady) {
      _mapReady = true;
    }

    final myOrders = driver != null ? orderStore.myOrders : const <OrderModel>[];
    // Raw GPS position — used for routes, RouteOptimizer, polylines.
    // Never jitters on every animation frame (drives expensive computations).
    final driverPosition = driver?.location ?? _stableInitialCenter;
    // Visually-displayed position — interpolated in _animateToNewPosition.
    // Used ONLY for the driver marker and camera follow. Falls back to the
    // raw position until the first GPS fix kicks the interpolation loop.
    final displayPosition = _smoothedPosition ?? driverPosition;
    final optimizedRoute = RouteOptimizer.optimize(myOrders, driverPosition);
    final nextStop = optimizedRoute.stops.isNotEmpty ? optimizedRoute.stops.first : null;

    // Focus order: the order whose next stop comes first.
    // If no orders, focusOrder is null (will render empty map).
    final focusOrder = myOrders.isNotEmpty
        ? (nextStop != null
            ? myOrders.firstWhere(
                (o) => o.id == nextStop.orderId,
                orElse: () => myOrders.first,
              )
            : myOrders.first)
        : null;

    // Route updates are deferred to AFTER the current frame is painted.
    // Using addPostFrameCallback (instead of microtask) guarantees the
    // GoogleMap has a chance to mount on frame 1 without competing with
    // async side-effects. Guarded by _mapController so nothing runs before
    // the PlatformView is alive.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (_mapController == null) return;
      if (nextStop != null) {
        _updateRouteMulti(driverPosition, optimizedRoute.stops);
      } else if (_routePoints.isNotEmpty) {
        setState(() {
          _routePoints = <ll.LatLng>[];
          _activeRouteKey = null;
          _routeDurationMinutes = null;
          _lastRouteOrigin = null;
        });
      }
    });

    // ── Markers ────────────────────────────────────────────────────────────
    // Driver marker uses the smoothed (interpolated) position so it glides
    // between GPS fixes instead of teleporting.
    final markers = <Marker>{
      Marker(
        markerId: const MarkerId('driver'),
        position: displayPosition.toGMaps(),
        icon: MapMarkerHelper.driverIcon,
        infoWindow: const InfoWindow(title: 'Estafeta'),
        zIndexInt: 2,
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
          icon: isPickup ? MapMarkerHelper.pickupIcon : MapMarkerHelper.deliveryIcon,
          infoWindow: InfoWindow(
            title: isPickup ? 'Recolha$stepLabel' : 'Entrega$stepLabel',
            snippet: stop.label,
          ),
          zIndexInt: 1,
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
    // Only ONE camera-update path is allowed at a time:
    //   • Stops change   → overview: fit all waypoints + driver in view
    //     (handled here, in a postFrameCallback).
    //   • Position-only  → follow: handled ENTIRELY by _animateToNewPosition
    //     which runs the 60 fps interpolation loop. No camera update for
    //     position changes is scheduled here to avoid competing with the
    //     interpolation timer.
    final stopsKey = optimizedRoute.stops.map((s) => s.orderId).join(',');

    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      if (_mapController == null) return;

      final stopsChanged = _lastAnimatedStopsKey != stopsKey;
      if (!stopsChanged) return;

      final controller = _mapController!;
      if (!mounted) return;

      // New or completed stop → full route overview.
      _lastAnimatedStopsKey = stopsKey;
      final bounds = boundsFromPoints(
        _routePoints.isNotEmpty ? _routePoints : allStopPoints,
      );
      if (bounds != null) {
        await controller.animateCamera(
          CameraUpdate.newLatLngBounds(bounds, 100),
        );
      }
    });

    final nextAction = focusOrder != null
        ? resolveDriverOrderAction(orderStore, focusOrder)
        : null;
    final topPadding = MediaQuery.of(context).padding.top;

    return Scaffold(
      body: Stack(
        children: [
          // GoogleMap must have explicit size on Web (PlatformView requirement).
          // Use SizedBox.expand to fill entire Stack with the map.
          SizedBox.expand(
            child: GoogleMap(
              // DO NOT use ValueKey — causes PlatformView recreation which crashes.
              // GoogleMap created once, never destroyed.
              initialCameraPosition: CameraPosition(
                // IMMUTABLE: captured once in initState. Never depends on
                // GPS, store state, realtime events, or any async value.
                // Guarantees the map mounts on frame 1 with a valid target.
                target: _stableInitialCenter.toGMaps(),
                zoom: 14,
              ),
              markers: markers,
              polylines: polylines,
              myLocationEnabled: true,
              myLocationButtonEnabled: false,
              zoomControlsEnabled: false,
              mapToolbarEnabled: false,
              onMapCreated: (controller) {
                _mapController = controller;
                controller.setMapStyle(_mapStyle);
              },
            ),
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

          // Center-on-driver button — centres on the currently-displayed
          // (smoothed) position so the camera lands exactly where the marker
          // is, even mid-animation.
          Positioned(
            top: topPadding + 8,
            right: 12,
            child: _MapButton(
              icon: Icons.my_location,
              onTap: () {
                _mapController?.animateCamera(
                  CameraUpdate.newLatLng(displayPosition.toGMaps()),
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
    _debounceTimer?.cancel();

    // Capture before async gap — needed for the fallback straight-line.
    final isFirstLoad = _routePoints.isEmpty;

    void execute() {
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
          if (isFirstLoad) {
            setState(() {
              _routePoints = [origin, ...stops.map((s) => s.location)];
              // _routeDurationMinutes left null — no ETA yet.
            });
          }
          // else: keep existing polyline and existing _routeDurationMinutes.
        }
      });
    }

    if (isFirstLoad) {
      // No prior polyline — fetch immediately so the real route appears
      // as soon as the API responds instead of after an arbitrary wait.
      execute();
    } else {
      // Subsequent position updates: short debounce batches rapid GPS ticks
      // into a single Directions API call (300 ms << previous 2500 ms).
      _debounceTimer = Timer(const Duration(milliseconds: 300), execute);
    }
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

  final OrderModel? focusOrder;
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

  /// Shows a 4-digit code dialog before completing the delivery.
  /// Returns `true` if the driver entered the correct code and the order
  /// action succeeded, `false` otherwise (wrong code, cancelled, or failure).
  Future<bool> _showDeliveryCodeDialog(DriverOrderAction action) async {
    final controller = TextEditingController();
    final formKey = GlobalKey<FormState>();
    String? errorText;

    final confirmed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (ctx, setDialogState) {
            return AlertDialog(
              title: const Text('Código de entrega'),
              content: Form(
                key: formKey,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Peça ao cliente o código de 4 dígitos para confirmar a entrega.',
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: controller,
                      keyboardType: TextInputType.number,
                      maxLength: 4,
                      autofocus: true,
                      decoration: InputDecoration(
                        labelText: 'Código',
                        counterText: '',
                        errorText: errorText,
                        border: const OutlineInputBorder(),
                      ),
                      onChanged: (_) {
                        if (errorText != null) {
                          setDialogState(() => errorText = null);
                        }
                      },
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(dialogContext).pop(false),
                  child: const Text('Cancelar'),
                ),
                ElevatedButton(
                  onPressed: () {
                    final entered = controller.text.trim();
                    if (entered.length != 4) {
                      setDialogState(
                          () => errorText = 'Digite os 4 dígitos.');
                      return;
                    }
                    if (entered != widget.focusOrder?.deliveryCode) {
                      setDialogState(
                          () => errorText = 'Código incorreto. Tente novamente.');
                      controller.clear();
                      return;
                    }
                    Navigator.of(dialogContext).pop(true);
                  },
                  child: const Text('Confirmar'),
                ),
              ],
            );
          },
        );
      },
    );

    if (confirmed != true) return false;

    // Code was correct — proceed with the action.
    if (!mounted) return false;
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    setState(() => _isLoading = true);
    final success = await action.execute();
    if (mounted) setState(() => _isLoading = false);
    if (success) {
      messenger.showSnackBar(
        SnackBar(
          content: Text(action.successMessage),
          duration: const Duration(seconds: 2),
        ),
      );
      // Refresh token balance in the background — the trigger already ran on
      // the DB side, so this fetch will return the updated value.
      if (mounted) {
        unawaited(context.read<DriverStore>().loadTokenBalance());
      }
      navigator.maybePop();
    } else {
      messenger.showSnackBar(
        const SnackBar(
          content: Text('Não foi possível atualizar o pedido.'),
        ),
      );
    }
    return success;
  }

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

              // Show order details only if focusOrder is available
              if (focusOrder != null) ...[
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
                  _InfoItem(
                    icon: Icons.monetization_on_outlined,
                    label: 'Tokens',
                    value: '+${(focusOrder.driverEarnings * BRDriver.DRIVER_TOKENS_PER_EUR).round()}',
                    valueColor: Colors.amber.shade700,
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
                                final willFinish = widget.focusOrder?.status ==
                                    OrderStatus.onTheWay;

                                // Delivery step: validate code before executing.
                                if (willFinish) {
                                  await _showDeliveryCodeDialog(action);
                                  return;
                                }

                                final messenger =
                                    ScaffoldMessenger.of(context);
                                setState(() => _isLoading = true);
                                final success = await action.execute();
                                if (success) {
                                  if (mounted) {
                                    setState(() => _isLoading = false);
                                  }
                                  messenger.showSnackBar(
                                    SnackBar(
                                      content: Text(action.successMessage),
                                      duration: const Duration(seconds: 2),
                                    ),
                                  );
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
              ] else ...[
                // No order accepted — show empty map message
                Center(
                  child: Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Text(
                      'Aceite um pedido para visualizar detalhes.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: Colors.grey.shade600,
                        fontSize: 14,
                      ),
                    ),
                  ),
                ),
              ],

              // If focusOrder is available: show finalize/chat sections
              if (focusOrder != null) ...[
                // Finalize purchase — only for orders where driver buys goods
                if (!_isMultiStop &&
                    !focusOrder.isPartnerStore &&
                    (focusOrder.serviceType == OrderServiceType.storeShopping ||
                        focusOrder.serviceType == OrderServiceType.restaurant) &&
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
              ],

              // Customer notes (single order only — too noisy for multi)
              if (!_isMultiStop &&
                  focusOrder != null &&
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
                          focusOrder!.customerNotes!,
                          style: TextStyle(
                              fontSize: 13, color: Colors.grey.shade700),
                        ),
                      ),
                    ],
                  ),
                ),
              ],

              if (!_isMultiStop && focusOrder != null && focusOrder.apartmentDelivery) ...[
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
              AddressText(
                rawAddress: stop.label,
                coords: stop.location,
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
          child: AddressText(
            rawAddress: order.pickupAddress,
            coords: order.pickupLocation,
            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
          ),
        ),
        Padding(
          padding: const EdgeInsets.only(left: 5),
          child: Container(height: 18, width: 2, color: Colors.grey.shade300),
        ),
        _AddressRow(
          icon: Icons.location_on_rounded,
          iconColor: const Color(0xFF1C6EF2),
          iconSize: 18,
          child: AddressText(
            rawAddress: order.dropoffAddress,
            coords: order.destination,
            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
            prefix: 'Entrega: ',
          ),
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
    this.label,
    this.child,
  }) : assert(label != null || child != null,
            '_AddressRow requires either label or child');

  final IconData icon;
  final Color iconColor;
  final double iconSize;
  final String? label;
  final Widget? child;

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
          child: child ??
              Text(
                label!,
                style:
                    const TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
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
              'Entrega em apartamento — bónus +€1 para o estafeta',
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
