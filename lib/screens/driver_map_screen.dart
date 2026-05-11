import 'dart:async';
import 'dart:io' show File;
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, kIsWeb, TargetPlatform;
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart' hide LatLng;
import 'package:latlong2/latlong.dart' as ll;
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../config/business_rules.dart' show BRBags, BRDriver;
import '../models/cart_item.dart';
import '../models/chat_message.dart';
import '../models/order_model.dart';
import '../services/directions_service.dart';
import '../services/navigation_service.dart';
import '../widgets/bora_support_fab.dart';
import '../services/route_optimizer.dart';
import '../stores/driver_store.dart';
import '../stores/order_store.dart';
import '../stores/restaurant_store.dart';
import '../utils/constants.dart';
import '../utils/map_marker_helper.dart';
import '../utils/map_utils.dart';
import '../widgets/address_text.dart';
import 'chat_screen.dart';
import 'driver_order_action_helper.dart';

// BUG 29: Google sobrepunha o nome da rua mais próxima (ex: "Alexandre
// Herculano") perto do marker do dropoff, fazendo crer ao estafeta que a
// entrega era nessa rua e não na real (Rua do Torreão). orders.dropoff_address
// na DB é correcto; era o Google a renderizar o POI label nativo.
// Fix: esconder labels de texto em road.local (mantém arterial+highway para
// orientação geral). Driver navega pela polyline + GPS da app de mapas.
const String _mapStyle = '''[
  {"featureType":"poi","stylers":[{"visibility":"off"}]},
  {"featureType":"transit","stylers":[{"visibility":"simplified"}]},
  {"featureType":"road","elementType":"labels.icon","stylers":[{"visibility":"off"}]},
  {"featureType":"road.local","elementType":"labels.text","stylers":[{"visibility":"off"}]},
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
  static const ll.LatLng _defaultFallbackCenter =
      ll.LatLng(kGuardaLat, kGuardaLng);

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

  // ── Driver-arrow marker (Uber-style bearing rotation) ─────────────────────
  double _bearing = 0.0;
  BitmapDescriptor? _driverArrowIcon;
  static const Duration _interpolationDuration = Duration(milliseconds: 600);
  static const Duration _interpolationFrame =
      Duration(milliseconds: 16); // ~60 fps
  static const double _jitterThresholdMetres = 1.0; // skip animation below this

  // ── Waze-style camera (BUG B) ─────────────────────────────────────────────
  // Driver pose: closer zoom, 3D tilt, bearing follows direction of travel.
  static const double _wazeZoom = 17.5;
  static const double _wazeTilt = 45.0;
  // Auto-resume follow after 15 s if user pans manually.
  static const Duration _followResumeDelay = Duration(seconds: 15);
  bool _followCamera = true;
  Timer? _followResumeTimer;
  // Differentiate user-initiated vs programmatic camera moves. Set true
  // immediately before any animateCamera call; reset after 250 ms.
  bool _programmaticMove = false;
  Timer? _programmaticMoveTimer;

  // Debounce timer: delays the Directions API call by 2.5 s after the last
  // qualifying movement, preventing bursts during rapid position updates.
  Timer? _debounceTimer;

  // Off-route rerouting throttle — prevents hammering the Directions API.
  DateTime? _lastRerouteTime;
  static const double _offRouteThresholdMetres = 50.0;
  static const int _rerouteThrottleSeconds = 15;

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
    _loadDriverArrowIcon();
  }

  /// Builds the green arrow marker used for the driver. Runs off Web
  /// (BitmapDescriptor.fromBytes is not supported on the web platform);
  /// on Web the driver simply falls back to the native blue dot.
  Future<void> _loadDriverArrowIcon() async {
    if (kIsWeb) return;
    try {
      final bytes = await _createArrowIcon();
      if (!mounted) return;
      setState(() => _driverArrowIcon = BitmapDescriptor.bytes(bytes));
    } catch (_) {
      // Silent fallback — marker simply remains null and the Marker is skipped.
    }
  }

  Future<Uint8List> _createArrowIcon() async {
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    const size = 56.0;
    final paint = Paint()..color = const Color(0xFF1B5E20); // Bora deep green
    final path = Path()
      ..moveTo(size / 2, 0) // top point
      ..lineTo(size, size) // bottom-right
      ..lineTo(size / 2, size * 0.7) // notch
      ..lineTo(0, size) // bottom-left
      ..close();
    canvas.drawPath(path, paint);
    final stroke = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3;
    canvas.drawPath(path, stroke);
    final picture = recorder.endRecording();
    final img = await picture.toImage(size.toInt(), size.toInt());
    final bytes = await img.toByteData(format: ui.ImageByteFormat.png);
    return bytes!.buffer.asUint8List();
  }

  @override
  void dispose() {
    _debounceTimer?.cancel();
    _interpolationTimer?.cancel();
    _followResumeTimer?.cancel();
    _programmaticMoveTimer?.cancel();
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
        _mapController
            ?.animateCamera(CameraUpdate.newLatLng(fallback.toGMaps()));
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
        _mapController
            ?.animateCamera(CameraUpdate.newLatLng(fallback.toGMaps()));
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content:
              Text('Permissão de localização bloqueada. Ative nas definições.'),
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
        _mapController
            ?.animateCamera(CameraUpdate.newLatLng(fallback.toGMaps()));
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
          _mapController
              ?.animateCamera(CameraUpdate.newLatLng(fallback.toGMaps()));
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

      // 2B: trim polyline segments already passed by the driver.
      _trimPassedRoutePoints(newLoc);
      // 2C/2D: reroute if driver strays > 50 m from the current polyline.
      _checkOffRouteAndReroute(newLoc);
    });
  }

  /// Removes polyline points the driver has already passed.
  /// Finds the closest point in [_routePoints] to [currentPos] and discards
  /// everything before it (keeping one point behind for a smooth visual start).
  void _trimPassedRoutePoints(ll.LatLng currentPos) {
    if (_routePoints.length < 3) return;
    int closestIdx = 0;
    double closestDist = double.infinity;
    for (int i = 0; i < _routePoints.length; i++) {
      final d = const ll.Distance()
          .as(ll.LengthUnit.Meter, currentPos, _routePoints[i]);
      if (d < closestDist) {
        closestDist = d;
        closestIdx = i;
      }
    }
    final trimFrom = closestIdx > 0 ? closestIdx - 1 : 0;
    if (trimFrom > 0) {
      setState(() {
        _routePoints = _routePoints.sublist(trimFrom);
      });
    }
  }

  /// Returns the distance in metres from [pos] to the nearest point in
  /// [_routePoints]. Used to detect when the driver left the route.
  double _nearestPolylineDistanceMetres(ll.LatLng pos) {
    if (_routePoints.isEmpty) return 0.0;
    double min = double.infinity;
    for (final pt in _routePoints) {
      final d = const ll.Distance().as(ll.LengthUnit.Meter, pos, pt);
      if (d < min) min = d;
    }
    return min;
  }

  /// Detects off-route situations and forces a route recalculation.
  /// Bypasses the 50 m movement throttle in [_updateRouteMulti] by resetting
  /// the cached route key/origin. Throttled to once every 15 s.
  void _checkOffRouteAndReroute(ll.LatLng currentPos) {
    if (_routePoints.length < 2) return;
    final now = DateTime.now();
    if (_lastRerouteTime != null &&
        now.difference(_lastRerouteTime!).inSeconds < _rerouteThrottleSeconds) {
      return;
    }
    final dist = _nearestPolylineDistanceMetres(currentPos);
    if (dist <= _offRouteThresholdMetres) return;
    _lastRerouteTime = now;
    // Reset cached keys so _updateRouteMulti fetches immediately (no 50 m gate).
    _activeRouteKey = null;
    _lastRouteOrigin = null;
    debugPrint(
        '[DriverMap] Off-route (${dist.toStringAsFixed(0)} m) — forcing reroute');
    // A setState here triggers build() → postFrameCallback → _updateRouteMulti.
    if (mounted) setState(() {});
  }

  /// Wraps animateCamera so user-vs-programmatic moves can be told apart.
  /// Sets [_programmaticMove] for ~250 ms; onCameraMoveStarted treats moves
  /// during that window as system-driven and won't pause follow mode.
  void _animateCameraProgrammatic(CameraUpdate update) {
    _programmaticMove = true;
    _programmaticMoveTimer?.cancel();
    _programmaticMoveTimer = Timer(const Duration(milliseconds: 250), () {
      _programmaticMove = false;
    });
    _mapController?.animateCamera(update);
  }

  /// Builds the Waze-style camera pose for the driver map (zoom 17.5,
  /// tilt 45°, bearing follows direction of travel).
  CameraUpdate _wazeCameraUpdate(ll.LatLng target) {
    return CameraUpdate.newCameraPosition(CameraPosition(
      target: target.toGMaps(),
      zoom: _wazeZoom,
      tilt: _wazeTilt,
      bearing: _bearing,
    ));
  }

  /// User panned the map manually → pause auto-follow for [_followResumeDelay].
  void _onUserCameraMoveStarted() {
    if (_programmaticMove) return; // ignore our own animateCamera triggers
    _followResumeTimer?.cancel();
    _followResumeTimer = Timer(_followResumeDelay, () {
      if (!mounted) return;
      setState(() => _followCamera = true);
      final pos = _smoothedPosition;
      if (pos != null) {
        _animateCameraProgrammatic(_wazeCameraUpdate(pos));
      }
    });
    if (_followCamera) {
      setState(() => _followCamera = false);
    }
  }

  /// Recenter button → snap to driver with full Waze pose + resume follow.
  void _onRecenter() {
    final pos = _smoothedPosition;
    _followResumeTimer?.cancel();
    setState(() => _followCamera = true);
    if (pos != null) {
      _animateCameraProgrammatic(_wazeCameraUpdate(pos));
    }
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
      if (_followCamera) {
        _animateCameraProgrammatic(_wazeCameraUpdate(newPos));
      } else {
        _animateCameraProgrammatic(
          CameraUpdate.newLatLng(newPos.toGMaps()),
        );
      }
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

    // Compute bearing once per animation (direction of travel). Updating it
    // per frame would amplify sub-metre noise into marker rotation jitter.
    final dLng = (newPos.longitude - startPos.longitude) * math.pi / 180;
    final lat1 = startPos.latitude * math.pi / 180;
    final lat2 = newPos.latitude * math.pi / 180;
    final y = math.sin(dLng) * math.cos(lat2);
    final x = math.cos(lat1) * math.sin(lat2) -
        math.sin(lat1) * math.cos(lat2) * math.cos(dLng);
    final newBearing = math.atan2(y, x) * 180 / math.pi;
    _bearing = (newBearing + 360) % 360;

    final totalFrames = (_interpolationDuration.inMilliseconds /
            _interpolationFrame.inMilliseconds)
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
      final lat =
          startPos.latitude + (newPos.latitude - startPos.latitude) * progress;
      final lng = startPos.longitude +
          (newPos.longitude - startPos.longitude) * progress;
      final intermediate = ll.LatLng(lat, lng);

      // Marker position (drives build()) + camera follow in lockstep.
      setState(() {
        _smoothedPosition = intermediate;
      });
      if (_followCamera) {
        _animateCameraProgrammatic(_wazeCameraUpdate(intermediate));
      }

      if (currentFrame >= totalFrames) {
        // Clamp to exact target and stop.
        _smoothedPosition = newPos;
        timer.cancel();
        _interpolationTimer = null;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    // Watch OrderStore so the widget rebuilds when an order is accepted/updated.
    // DriverStore uses read (location updates handled via setState in GPS stream).
    final driverStore = context.read<DriverStore>();
    final orderStore = context.watch<OrderStore>();
    final restaurantStore = context.watch<RestaurantStore>();

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

    final myOrders =
        driver != null ? orderStore.myOrders : const <OrderModel>[];
    // Raw GPS position — used for routes, RouteOptimizer, polylines.
    // Never jitters on every animation frame (drives expensive computations).
    final driverPosition = driver?.location ?? _stableInitialCenter;
    // Visually-displayed position — interpolated in _animateToNewPosition.
    // Used ONLY for the driver marker and camera follow. Falls back to the
    // raw position until the first GPS fix kicks the interpolation loop.
    final displayPosition = _smoothedPosition ?? driverPosition;
    final optimizedRoute = _withRealPickupCoords(
      RouteOptimizer.optimize(myOrders, driverPosition),
      myOrders,
      restaurantStore,
    );
    final nextStop =
        optimizedRoute.stops.isNotEmpty ? optimizedRoute.stops.first : null;

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
    // Driver rendered as a green arrow that rotates with the direction of
    // travel (bearing). Falls back to the native blue dot on Web (where the
    // custom BitmapDescriptor is not supported) by leaving the marker off and
    // re-enabling myLocationEnabled only when the icon hasn't loaded yet.
    final markers = <Marker>{};

    if (_driverArrowIcon != null) {
      markers.add(
        Marker(
          markerId: const MarkerId('driver_self'),
          position: displayPosition.toGMaps(),
          rotation: _bearing,
          icon: _driverArrowIcon!,
          anchor: const Offset(0.5, 0.5),
          flat: true,
          zIndexInt: 2,
        ),
      );
    }

    // BUG 7 (Fase 6 / 2026-04-30): mostrar TODOS os stops simultaneamente.
    // Antes: só o NEXT stop tinha marker → estafeta não via partner pin
    // depois de marcar pickup nem em pedidos com batching.
    // Agora: pickup laranja + delivery verde sempre visíveis em paralelo.
    final totalStops = optimizedRoute.stops.length;
    for (var i = 0; i < totalStops; i++) {
      final stop = optimizedRoute.stops[i];
      final isPickup = stop.isPickup;
      final stepLabel = totalStops > 1 ? ' ${i + 1}/$totalStops' : '';
      markers.add(
        Marker(
          markerId: MarkerId('stop_${i}_${stop.orderId}'),
          position: stop.location.toGMaps(),
          icon: isPickup
              ? MapMarkerHelper.pickupIcon
              : MapMarkerHelper.deliveryIcon,
          infoWindow: InfoWindow(
            title: isPickup ? 'Recolha$stepLabel' : 'Entrega$stepLabel',
            snippet: stop.label,
          ),
          // Stop seguinte (i==0) tem zIndex maior para destaque.
          zIndexInt: i == 0 ? 2 : 1,
        ),
      );
    }

    // ── Polyline ────────────────────────────────────────────────────────────
    // Uber/Glovo style: câmara e polyline fallback focam só no próximo stop.
    final allStopPoints = [
      driverPosition,
      if (nextStop != null) nextStop.location,
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
      floatingActionButton: const BoraSupportFab(
        position: FabPosition.topRight,
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.endTop,
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
              style: _mapStyle,
              // Use the native blue dot only when the custom arrow icon hasn't
              // loaded yet (e.g. on Web, where fromBytes isn't supported).
              myLocationEnabled: _driverArrowIcon == null,
              myLocationButtonEnabled: false,
              zoomControlsEnabled: false,
              mapToolbarEnabled: false,
              onMapCreated: (controller) {
                _mapController = controller;
              },
              onCameraMoveStarted: _onUserCameraMoveStarted,
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

          // Recenter button — restores Waze pose (zoom 17.5, tilt 45°,
          // bearing) and resumes follow mode. Positioned mid-right so it
          // doesn't collide with the support FAB (top) or the bottom sheet.
          Positioned(
            right: 16,
            top: MediaQuery.of(context).size.height * 0.62,
            child: Semantics(
              label: 'Centralizar mapa',
              button: true,
              child: FloatingActionButton.small(
                heroTag: 'map_recenter_btn_driver',
                backgroundColor: const Color(0xFF1B5E20),
                foregroundColor: Colors.white,
                onPressed: _onRecenter,
                child: const Icon(Icons.my_location),
              ),
            ),
          ),

          // Bottom info panel — draggable sheet: map fills most of the screen,
          // panel minimised by default, expands on drag.
          Positioned.fill(
            child: DraggableScrollableSheet(
              initialChildSize: 0.15,
              minChildSize: 0.15,
              maxChildSize: 0.50,
              snap: true,
              snapSizes: const [0.15, 0.50],
              builder: (context, scrollController) {
                return SingleChildScrollView(
                  controller: scrollController,
                  physics: const ClampingScrollPhysics(),
                  child: _BottomPanel(
                    focusOrder: focusOrder,
                    nextStop: nextStop,
                    allStops: optimizedRoute.stops,
                    orders: myOrders,
                    driverPosition: displayPosition,
                    nextAction: nextAction,
                    routeDurationMinutes: _routeDurationMinutes,
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  /// Visual-only override: for each pickup stop, if the order has a
  /// vendorName that matches a known restaurant, replace the stop location
  /// with the real restaurant coordinates. Does NOT mutate the order or
  /// affect pricing — only the marker/polyline rendering.
  OptimizedRoute _withRealPickupCoords(
    OptimizedRoute route,
    List<OrderModel> orders,
    RestaurantStore restaurantStore,
  ) {
    if (route.stops.isEmpty) return route;
    final corrected = route.stops.map((stop) {
      if (!stop.isPickup) return stop;
      OrderModel? order;
      for (final o in orders) {
        if (o.id == stop.orderId) {
          order = o;
          break;
        }
      }
      final vendorName = order?.vendorName;
      if (vendorName == null || vendorName.isEmpty) return stop;
      ll.LatLng? realLoc;
      for (final r in restaurantStore.restaurants) {
        if (r.name == vendorName) {
          realLoc = r.location;
          break;
        }
      }
      if (realLoc == null) return stop;
      return RouteStop(
        type: stop.type,
        orderId: stop.orderId,
        location: realLoc,
        label: stop.label,
      );
    }).toList();
    return OptimizedRoute(
      stops: corrected,
      totalDistanceKm: route.totalDistanceKm,
    );
  }

  void _updateRouteMulti(ll.LatLng origin, List<RouteStop> stops) {
    if (stops.isEmpty) return;

    // Uber/Glovo style: mapa mostra SÓ a rota para o PRÓXIMO ponto.
    // A lista completa de stops é mostrada no painel inferior (_StopList).
    final destination = stops.first.location;
    const waypointLocations = <ll.LatLng>[];

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
    required this.orders,
    required this.driverPosition,
    required this.nextAction,
    this.routeDurationMinutes,
  });

  final OrderModel? focusOrder;
  final RouteStop? nextStop;
  final List<RouteStop> allStops;
  final List<OrderModel> orders;
  final ll.LatLng? driverPosition;
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
                      setDialogState(() => errorText = 'Digite os 4 dígitos.');
                      return;
                    }
                    if (entered != widget.focusOrder?.deliveryCode) {
                      setDialogState(() =>
                          errorText = 'Código incorreto. Tente novamente.');
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

  void _showShoppingListSheet(BuildContext context, OrderModel order) {
    final items = order.items;
    if (items.isEmpty) return;

    final editableItems = items
        .map((i) => CartItem(
              productId: i.productId,
              name: i.name,
              price: i.price,
              quantity: i.quantity,
              purchaseStatus: i.purchaseStatus,
              actualPrice: i.actualPrice,
            ))
        .toList();

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => _ShoppingListSheetContent(
        order: order,
        initialItems: editableItems,
      ),
    );
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
                  _StopList(
                    stops: widget.allStops,
                    orders: widget.orders,
                    driverPosition: widget.driverPosition,
                  )
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
                      value:
                          '+€${focusOrder.driverEarnings.toStringAsFixed(2)}',
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
                      value:
                          '+${(focusOrder.driverEarnings * BRDriver.DRIVER_TOKENS_PER_EUR).round()}',
                      valueColor: Colors.amber.shade700,
                    ),
                  ],
                ),

                const SizedBox(height: 16),

                // "Ver compras" button — pickup phase only, if order has items
                if (focusOrder.items.isNotEmpty &&
                    (focusOrder.status == OrderStatus.driverAccepted ||
                        focusOrder.status == OrderStatus.pickedUp)) ...[
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: () =>
                          _showShoppingListSheet(context, focusOrder),
                      icon: Icon(Icons.receipt_long,
                          size: 18, color: Colors.green.shade700),
                      label: Text(
                        'Ver compras (${focusOrder.items.length} ${focusOrder.items.length == 1 ? 'item' : 'itens'})',
                        style: TextStyle(color: Colors.green.shade700),
                      ),
                      style: OutlinedButton.styleFrom(
                        side: BorderSide(color: Colors.green.shade400),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        padding: const EdgeInsets.symmetric(vertical: 12),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                ],

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
                                  final willFinish =
                                      widget.focusOrder?.status ==
                                          OrderStatus.onTheWay;

                                  // BUG 33: cash skips the 4-digit code
                                  // (driver receives physical cash = real
                                  // validation). Card/MBWay still require code.
                                  final isCash = widget.focusOrder
                                          ?.paymentMethod ==
                                      PaymentMethod.cash;
                                  if (willFinish && !isCash) {
                                    await _showDeliveryCodeDialog(action);
                                    return;
                                  }

                                  final messenger =
                                      ScaffoldMessenger.of(context);
                                  final nav = Navigator.of(context);
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
                                    // BUG 5 — pós Concluir entrega volta para
                                    // home estafeta em vez de ficar na tela
                                    // detail vazia.
                                    if (willFinish && mounted) {
                                      nav.popUntil((route) => route.isFirst);
                                    }
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
                // Finalize purchase — only for orders where driver buys goods.
                // Available from driverAccepted onwards so the driver can
                // finalize BEFORE confirming pickup (Confirmar recolha is
                // hidden while !isPurchaseFinalized in driverAccepted).
                if (!_isMultiStop &&
                    !focusOrder.isPartnerStore &&
                    (focusOrder.serviceType == OrderServiceType.storeShopping ||
                        focusOrder.serviceType ==
                            OrderServiceType.restaurant) &&
                    (focusOrder.status == OrderStatus.driverAccepted ||
                        focusOrder.status == OrderStatus.pickedUp ||
                        focusOrder.status == OrderStatus.onTheWay)) ...[
                  const SizedBox(height: 12),
                  if (focusOrder.isPurchaseFinalized &&
                      focusOrder.finalTotal != null)
                    _FinalizedBanner(order: focusOrder),
                ],

                // Chat + Call buttons — always visible for active single orders
                if (!_isMultiStop) ...[
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
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
                          label: const Text('Chat'),
                        ),
                      ),
                      // FASE 5: tel: link directo. Twilio masking
                      // post-launch (anotado em todos-pos-launch.md).
                      if (focusOrder.clientPhone != null &&
                          focusOrder.clientPhone!.trim().isNotEmpty) ...[
                        const SizedBox(width: 8),
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: () async {
                              final tel = focusOrder.clientPhone!.trim();
                              final uri = Uri.parse('tel:$tel');
                              try {
                                await launchUrl(uri);
                              } catch (e) {
                                if (!context.mounted) return;
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(content: Text('Não foi possível ligar: $e')),
                                );
                              }
                            },
                            icon: const Icon(Icons.phone_outlined),
                            label: const Text('Ligar'),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: Colors.green.shade700,
                              side: BorderSide(color: Colors.green.shade300),
                            ),
                          ),
                        ),
                      ],
                    ],
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
                          focusOrder.customerNotes!,
                          style: TextStyle(
                              fontSize: 13, color: Colors.grey.shade700),
                        ),
                      ),
                    ],
                  ),
                ),
              ],

              if (!_isMultiStop &&
                  focusOrder != null &&
                  focusOrder.apartmentDelivery) ...[
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
  const _StopList({
    required this.stops,
    required this.orders,
    required this.driverPosition,
  });

  final List<RouteStop> stops;
  final List<OrderModel> orders;
  final ll.LatLng? driverPosition;

  OrderModel? _orderFor(RouteStop stop) {
    for (final o in orders) {
      if (o.id == stop.orderId) return o;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 0; i < stops.length; i++) ...[
          _StopRow(
            stop: stops[i],
            index: i,
            order: _orderFor(stops[i]),
            driverPosition: driverPosition,
          ),
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
  const _StopRow({
    required this.stop,
    required this.index,
    this.order,
    this.driverPosition,
  });

  final RouteStop stop;
  final int index;
  final OrderModel? order;
  final ll.LatLng? driverPosition;

  String? _buildVendorLine() {
    if (!stop.isPickup) return null;
    final vendorName = order?.vendorName;
    if (vendorName == null || vendorName.isEmpty) return null;
    final pickupLoc = order?.pickupLocation;
    if (driverPosition != null && pickupLoc != null) {
      final km = const ll.Distance().as(
        ll.LengthUnit.Kilometer,
        driverPosition!,
        pickupLoc,
      );
      return '$vendorName · ${km.toStringAsFixed(1)} km';
    }
    return vendorName;
  }

  @override
  Widget build(BuildContext context) {
    final isPickup = stop.isPickup;
    final color = isPickup ? Colors.orange.shade600 : const Color(0xFF1C6EF2);
    final icon = isPickup ? Icons.circle : Icons.location_on_rounded;
    final iconSize = isPickup ? 11.0 : 18.0;
    final typeLabel = isPickup ? 'Recolha' : 'Entrega';
    final vendorLine = _buildVendorLine();

    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        // Step pill
        Container(
          width: 20,
          height: 20,
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.12),
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
              if (vendorLine != null)
                Text(
                  vendorLine,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              AddressText(
                rawAddress: stop.label,
                coords: stop.location,
                style:
                    const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
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
      case OrderStatus.cancelled:
        return Colors.red;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: _color.withValues(alpha: 0.12),
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

class _SummaryRow extends StatelessWidget {
  const _SummaryRow({
    required this.label,
    required this.value,
    this.color,
    this.bold = false,
  });

  final String label;
  final double value;
  final Color? color;
  final bool bold;

  @override
  Widget build(BuildContext context) {
    final style = TextStyle(
      fontSize: 13,
      fontWeight: bold ? FontWeight.w700 : FontWeight.w500,
      color: color,
    );
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: style),
          Text('€${value.toStringAsFixed(2)}', style: style),
        ],
      ),
    );
  }
}

/// Banner shown after the driver has confirmed the real purchase value.
class _FinalizedBanner extends StatelessWidget {
  const _FinalizedBanner({required this.order});

  final OrderModel order;

  @override
  Widget build(BuildContext context) {
    final finalTotal = order.finalTotal ?? 0;
    final isCash = order.paymentMethod == PaymentMethod.cash;
    // Sessão 3: cash_total_due acumula extras pós-finalização (ex.: sacos
    // mercado a €0.10/saco). NULL → usar finalTotal como fallback histórico.
    final amountToCollect = order.cashTotalDue ?? finalTotal;
    final hasBagSurcharge =
        order.cashTotalDue != null && order.cashTotalDue! > finalTotal;
    final bagSurcharge =
        hasBagSurcharge ? order.cashTotalDue! - finalTotal : 0.0;

    if (isCash) {
      // BUG 32: aviso GRANDE para o estafeta cobrar antes de entregar.
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        decoration: BoxDecoration(
          color: const Color(0xFFE65100),
          borderRadius: BorderRadius.circular(12),
          boxShadow: const [
            BoxShadow(
              color: Color(0x33000000),
              blurRadius: 8,
              offset: Offset(0, 2),
            ),
          ],
        ),
        child: Row(
          children: [
            const Text('💵', style: TextStyle(fontSize: 28)),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'RECEBER €${amountToCollect.toStringAsFixed(2)} EM DINHEIRO',
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w800,
                      fontSize: 22,
                      letterSpacing: 0.3,
                    ),
                  ),
                  if (hasBagSurcharge) ...[
                    const SizedBox(height: 4),
                    Text(
                      'inclui +€${bagSurcharge.toStringAsFixed(2)} de sacos',
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w600,
                        fontSize: 13,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      );
    }

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

// ────────────────────────────────────────────────────────────────────────────
// Shopping-list bottom-sheet — proper StatefulWidget so that state (bought /
// unavailable marks, added products) survives across rebuilds triggered by
// keyboard show/hide or dialog open/close.
// ────────────────────────────────────────────────────────────────────────────
class _ShoppingListSheetContent extends StatefulWidget {
  final OrderModel order;
  final List<CartItem> initialItems;

  const _ShoppingListSheetContent({
    required this.order,
    required this.initialItems,
  });

  @override
  State<_ShoppingListSheetContent> createState() =>
      _ShoppingListSheetContentState();
}

class _ShoppingListSheetContentState extends State<_ShoppingListSheetContent> {
  late final List<CartItem> _items;
  late int _bagCount;

  bool get _isRestaurant =>
      widget.order.serviceType == OrderServiceType.restaurant;

  bool get _isPartnerStore => widget.order.isPartnerStore;

  double get _bagFee {
    if (_isRestaurant) {
      // BUG 4: partner restaurant absorbs the bag (0€), non-partner pays
      // the fixed €0.30 already collected at checkout.
      return _isPartnerStore ? 0 : BRBags.RESTAURANT_BAG_FEE;
    }
    return _bagCount * BRBags.MARKET_BAG_FEE;
  }

  @override
  void initState() {
    super.initState();
    _items = List.of(widget.initialItems);
    _bagCount = widget.order.bagCount > 0
        ? widget.order.bagCount
        : (_isRestaurant ? 1 : 1);
  }

  // ── Add-product dialog ──────────────────────────────────────────────────
  Future<CartItem?> _showAddProductDialog() {
    return showDialog<CartItem>(
      context: context,
      builder: (dialogCtx) {
        final nameCtrl = TextEditingController();
        final priceCtrl = TextEditingController();
        int qty = 1;
        String? nameError;
        String? priceError;

        return StatefulBuilder(
          builder: (_, setDialogState) {
            return AlertDialog(
              title: const Text('Novo produto'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: nameCtrl,
                    decoration: InputDecoration(
                      labelText: 'Nome do produto',
                      errorText: nameError,
                      isDense: true,
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 10),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                    textCapitalization: TextCapitalization.sentences,
                    autofocus: true,
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: priceCtrl,
                    decoration: InputDecoration(
                      labelText: 'Preço (€)',
                      errorText: priceError,
                      isDense: true,
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 10),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      const Text('Quantidade:', style: TextStyle(fontSize: 13)),
                      const SizedBox(width: 8),
                      IconButton(
                        onPressed:
                            qty > 1 ? () => setDialogState(() => qty--) : null,
                        icon: const Icon(Icons.remove_circle_outline, size: 22),
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(),
                        color: Colors.green.shade700,
                      ),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                        child: Text(
                          '$qty',
                          style: const TextStyle(
                            fontWeight: FontWeight.w700,
                            fontSize: 15,
                          ),
                        ),
                      ),
                      IconButton(
                        onPressed: () => setDialogState(() => qty++),
                        icon: const Icon(Icons.add_circle_outline, size: 22),
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(),
                        color: Colors.green.shade700,
                      ),
                    ],
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(dialogCtx),
                  child: const Text('Cancelar'),
                ),
                ElevatedButton(
                  onPressed: () {
                    final name = nameCtrl.text.trim();
                    final priceText =
                        priceCtrl.text.trim().replaceAll(',', '.');
                    final price = double.tryParse(priceText) ?? 0;
                    String? nErr;
                    String? pErr;
                    if (name.isEmpty) nErr = 'Nome obrigatório';
                    if (price <= 0) pErr = 'Preço inválido';
                    if (nErr != null || pErr != null) {
                      setDialogState(() {
                        nameError = nErr;
                        priceError = pErr;
                      });
                      return;
                    }
                    Navigator.pop(
                      dialogCtx,
                      CartItem(
                        productId:
                            'extra_${DateTime.now().millisecondsSinceEpoch}',
                        name: name,
                        price: price,
                        quantity: qty,
                        purchaseStatus: 'bought',
                      ),
                    );
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.green.shade600,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  child: const Text('Adicionar'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  bool _isExtraItem(CartItem i) => i.productId.startsWith('extra_');

  static const double _markupPctDisplay = 0.15; // server is source of truth

  // ── Build ───────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final order = widget.order;
    // Canonical items (from orders.items) vs extra items (driver-added).
    final canonicalItems = _items.where((i) => !_isExtraItem(i)).toList();
    final extraItems = _items
        .where((i) => _isExtraItem(i) && i.purchaseStatus == 'bought')
        .toList();

    final boughtCount =
        canonicalItems.where((i) => i.purchaseStatus == 'bought').length;
    final unavailableCount =
        canonicalItems.where((i) => i.purchaseStatus == 'unavailable').length;
    final totalCount = canonicalItems.length;
    final pendingCount = totalCount - boughtCount - unavailableCount;
    final allDecided = pendingCount == 0;

    final boughtTotal = canonicalItems
        .where((i) => i.purchaseStatus == 'bought')
        .fold<double>(0, (s, i) => s + i.price * i.quantity);

    // Extra items: estafeta meteu o preço base; aplicamos +15% para display.
    // Server faz o mesmo cálculo autoritativo.
    final addedFinalTotal = extraItems.fold<double>(
        0, (s, i) => s + (i.price * (1 + _markupPctDisplay) * i.quantity));

    final origTotal = order.paymentBufferTotal;
    final adjustedTotal = boughtTotal + _bagFee + addedFinalTotal;
    final diff = adjustedTotal - origTotal;
    // BUG 16+17 — extraToCharge/refundDue retirados; agora exibimos
    // diff directo com texto explicativo distinto por payment_method.

    final isCash = order.paymentMethod == PaymentMethod.cash;

    final progress = totalCount > 0 ? boughtCount / totalCount : 0.0;

    return Padding(
      padding: EdgeInsets.fromLTRB(
        20,
        16,
        20,
        24 + MediaQuery.of(context).viewInsets.bottom,
      ),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.85,
        ),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ── Handle ──
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
              // ── Title ──
              Text(
                'Lista de compras — ${order.vendorName ?? "Loja"}',
                style: const TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 4),
              // ── Progress text ──
              Text(
                '$boughtCount de $totalCount comprados',
                style: TextStyle(
                  fontSize: 13,
                  color: Colors.grey.shade600,
                ),
              ),
              const SizedBox(height: 8),
              // ── Progress bar ──
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: progress,
                  backgroundColor: Colors.grey.shade200,
                  valueColor:
                      AlwaysStoppedAnimation<Color>(Colors.green.shade600),
                  minHeight: 6,
                ),
              ),
              const SizedBox(height: 12),
              const Divider(height: 1),
              const SizedBox(height: 4),
              // ── Item list ──
              ConstrainedBox(
                constraints: BoxConstraints(
                  maxHeight: MediaQuery.of(context).size.height * 0.45,
                ),
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: _items.length,
                  itemBuilder: (_, index) {
                    final item = _items[index];
                    final isBought = item.purchaseStatus == 'bought';
                    final isUnavailable = item.purchaseStatus == 'unavailable';
                    final isPending = item.purchaseStatus == 'pending';

                    Color bgColor;
                    if (isBought) {
                      bgColor = Colors.green.shade50;
                    } else if (isUnavailable) {
                      bgColor = Colors.grey.shade100;
                    } else {
                      bgColor = Colors.white;
                    }

                    return GestureDetector(
                      onTap: (isBought || isUnavailable)
                          ? () {
                              setState(() {
                                item.purchaseStatus = 'pending';
                              });
                            }
                          : null,
                      child: Container(
                        margin: const EdgeInsets.symmetric(vertical: 4),
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: bgColor,
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                            color: Colors.grey.shade200,
                            width: 0.5,
                          ),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                if (isBought)
                                  Icon(Icons.check_circle,
                                      color: Colors.green.shade600, size: 20)
                                else if (isUnavailable)
                                  Icon(Icons.cancel,
                                      color: Colors.red.shade400, size: 20)
                                else
                                  Icon(Icons.radio_button_unchecked,
                                      color: Colors.grey.shade400, size: 20),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    '${item.name} × ${item.quantity}',
                                    style: TextStyle(
                                      fontSize: 14,
                                      fontWeight: FontWeight.w500,
                                      decoration: isUnavailable
                                          ? TextDecoration.lineThrough
                                          : null,
                                      color: isUnavailable
                                          ? Colors.grey
                                          : Colors.black87,
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                                Text(
                                  // BUG 38: items adicionados pelo estafeta
                                  // mostram preço FINAL (com markup +15%) já
                                  // aqui, para coincidir com o resumo lá em
                                  // baixo. Items canónicos mostram price tal
                                  // como vieram (cliente já pagou esse).
                                  '€${(_isExtraItem(item) ? item.price * (1 + _markupPctDisplay) * item.quantity : item.price * item.quantity).toStringAsFixed(2)}',
                                  style: TextStyle(
                                    fontWeight: FontWeight.w600,
                                    fontSize: 14,
                                    decoration: isUnavailable
                                        ? TextDecoration.lineThrough
                                        : null,
                                    color: isUnavailable
                                        ? Colors.grey
                                        : Colors.black87,
                                  ),
                                ),
                              ],
                            ),
                            if (isPending) ...[
                              const SizedBox(height: 8),
                              Row(
                                children: [
                                  Expanded(
                                    child: SizedBox(
                                      height: 32,
                                      child: ElevatedButton.icon(
                                        onPressed: () {
                                          setState(() {
                                            item.purchaseStatus = 'bought';
                                          });
                                        },
                                        icon: const Icon(Icons.check, size: 16),
                                        label: const Text('Comprado',
                                            style: TextStyle(fontSize: 12)),
                                        style: ElevatedButton.styleFrom(
                                          backgroundColor:
                                              Colors.green.shade600,
                                          foregroundColor: Colors.white,
                                          shape: RoundedRectangleBorder(
                                            borderRadius:
                                                BorderRadius.circular(8),
                                          ),
                                          padding: const EdgeInsets.symmetric(
                                              horizontal: 8),
                                        ),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: SizedBox(
                                      height: 32,
                                      child: ElevatedButton.icon(
                                        onPressed: () {
                                          setState(() {
                                            item.purchaseStatus =
                                                'unavailable';
                                          });
                                        },
                                        icon: const Icon(Icons.close,
                                            size: 16),
                                        label: const Text('Não há',
                                            style: TextStyle(fontSize: 12)),
                                        style: ElevatedButton.styleFrom(
                                          backgroundColor: Colors.red.shade600,
                                          foregroundColor: Colors.white,
                                          shape: RoundedRectangleBorder(
                                            borderRadius:
                                                BorderRadius.circular(8),
                                          ),
                                          padding: const EdgeInsets.symmetric(
                                              horizontal: 8),
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
              const SizedBox(height: 8),
              const Divider(height: 1),
              const SizedBox(height: 12),
              // ── Add product button ──
              Center(
                child: OutlinedButton.icon(
                  onPressed: () async {
                    final newItem = await _showAddProductDialog();
                    if (newItem != null && mounted) {
                      setState(() {
                        _items.add(newItem);
                      });
                    }
                  },
                  icon: const Icon(Icons.add, size: 18),
                  label: const Text('Adicionar produto'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.green.shade700,
                    side: BorderSide(color: Colors.green.shade700),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                    padding:
                        const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  ),
                ),
              ),
              // ── Bags section ──
              // BUG 4: partner restaurant absorbs the bag (hide section).
              // Non-partner restaurant: fixed €0.30. storeShopping: per-bag slider.
              if (!(_isRestaurant && _isPartnerStore)) ...[
                const SizedBox(height: 12),
                Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.orange.shade50,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: Colors.orange.shade200, width: 0.5),
                ),
                child: _isRestaurant
                    ? Row(
                        children: [
                          const Text('🛍️', style: TextStyle(fontSize: 18)),
                          const SizedBox(width: 8),
                          const Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Sacos',
                                  style: TextStyle(
                                    fontWeight: FontWeight.w600,
                                    fontSize: 14,
                                  ),
                                ),
                                Text(
                                  '€0.30 (fixo)',
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: Colors.grey,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Text(
                            '€${BRBags.RESTAURANT_BAG_FEE.toStringAsFixed(2)}',
                            style: const TextStyle(
                              fontWeight: FontWeight.w700,
                              fontSize: 14,
                            ),
                          ),
                        ],
                      )
                    : Row(
                        children: [
                          const Text('🛍️', style: TextStyle(fontSize: 18)),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  'Sacos',
                                  style: TextStyle(
                                    fontWeight: FontWeight.w600,
                                    fontSize: 14,
                                  ),
                                ),
                                Text(
                                  '(€${BRBags.MARKET_BAG_FEE.toStringAsFixed(2)} por saco)',
                                  style: const TextStyle(
                                    fontSize: 11,
                                    color: Colors.grey,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          IconButton(
                            onPressed: _bagCount > 0
                                ? () => setState(() => _bagCount--)
                                : null,
                            icon: const Icon(Icons.remove_circle_outline,
                                size: 22),
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(),
                            color: Colors.orange.shade700,
                          ),
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 8),
                            child: Text(
                              '$_bagCount',
                              style: const TextStyle(
                                fontWeight: FontWeight.w700,
                                fontSize: 15,
                              ),
                            ),
                          ),
                          IconButton(
                            // Cap 5 sacos × €0.10 = €0.50 max (Sessão 3 / 2026-05-04)
                            onPressed: _bagCount < 5
                                ? () => setState(() => _bagCount++)
                                : null,
                            icon:
                                const Icon(Icons.add_circle_outline, size: 22),
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(),
                            color: Colors.orange.shade700,
                          ),
                          const SizedBox(width: 8),
                          Text(
                            '€${_bagFee.toStringAsFixed(2)}',
                            style: const TextStyle(
                              fontWeight: FontWeight.w700,
                              fontSize: 14,
                            ),
                          ),
                        ],
                      ),
              ),
              ],
              const SizedBox(height: 12),
              // ── Totals breakdown ──
              _SummaryRow(
                  label: 'Subtotal comprado', value: boughtTotal),
              const SizedBox(height: 4),
              _SummaryRow(label: 'Sacos', value: _bagFee),
              if (addedFinalTotal > 0) ...[
                const SizedBox(height: 4),
                _SummaryRow(
                    label: 'Adicionados',
                    value: addedFinalTotal,
                    color: Colors.blue),
              ],
              const SizedBox(height: 6),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'Total ajustado:',
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 15,
                    ),
                  ),
                  Text(
                    '€${adjustedTotal.toStringAsFixed(2)}',
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 15,
                      color: Colors.green.shade700,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              if (isCash) ...[
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      'Cliente paga na entrega:',
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 16,
                      ),
                    ),
                    Text(
                      '€${adjustedTotal.toStringAsFixed(2)}',
                      style: TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 16,
                        color: Colors.green.shade700,
                      ),
                    ),
                  ],
                ),
              ] else ...[
                // BUG 16+17 fix — pedido MBWay/Stripe: cliente JÁ pagou na app.
                // NÃO mostrar "Cliente pagou" (era confuso e usava field errado).
                // Mostrar valor que Bora reembolsa ao estafeta + diferença vs
                // estimativa.
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      'Bora reembolsa-te:',
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 16,
                      ),
                    ),
                    Text(
                      '€${adjustedTotal.toStringAsFixed(2)}',
                      style: TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 16,
                        color: Colors.green.shade700,
                      ),
                    ),
                  ],
                ),
                if (diff.abs() > 0.01)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(
                      diff < 0
                          ? 'Cliente recebe €${(-diff).toStringAsFixed(2)} de reembolso (compras saíram mais baratas)'
                          : 'Cliente será cobrado +€${diff.toStringAsFixed(2)} (compras saíram mais caras)',
                      style: TextStyle(
                        fontSize: 12,
                        color: diff < 0
                            ? Colors.green.shade700
                            : Colors.orange.shade700,
                        fontStyle: FontStyle.italic,
                      ),
                    ),
                  ),
              ],
              if (unavailableCount > 0)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                    '($unavailableCount produto${unavailableCount > 1 ? 's' : ''} indisponível${unavailableCount > 1 ? 'eis' : ''})',
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.grey.shade600,
                    ),
                  ),
                ),
              const SizedBox(height: 16),
              // ── Confirm button ──
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: allDecided
                      ? () async {
                          final orderStore = context.read<OrderStore>();
                          final messenger = ScaffoldMessenger.of(context);
                          final nav = Navigator.of(context);
                          final itemsAdded = extraItems
                              .map((i) => <String, dynamic>{
                                    'name': i.name,
                                    'price_base_cents':
                                        (i.price * 100).round(),
                                    'qty': i.quantity,
                                    'reason': 'driver_added',
                                  })
                              .toList();

                          // BUG 1 — Fork V2 para storeShopping não-parceiro.
                          // Decisão NOVA: foto+valor obrigatórios em TODOS
                          // payment_methods para auditoria admin.
                          final useV2 = order.serviceType ==
                                  OrderServiceType.storeShopping &&
                              !order.isPartnerStore;
                          if (useV2) {
                            final result =
                                await _captureReceiptForV2(context, order);
                            if (!mounted) return;
                            if (result == null) return; // cancelado
                            final photoFile = result.$1;
                            final totalCents = result.$2;

                            String storagePath;
                            try {
                              final bytes = await photoFile.readAsBytes();
                              storagePath = 'receipts/${order.id}.jpg';
                              await Supabase.instance.client.storage
                                  .from('receipts')
                                  .uploadBinary(
                                    storagePath,
                                    bytes,
                                    fileOptions: const FileOptions(
                                      upsert: true,
                                      contentType: 'image/jpeg',
                                    ),
                                  );
                            } catch (e) {
                              messenger.showSnackBar(SnackBar(
                                  content: Text('Erro upload talão: $e')));
                              return;
                            }

                            final reason = await orderStore
                                .finalizeStoreShoppingV2WithReceipt(
                              orderId: order.id,
                              photoStoragePath: storagePath,
                              driverTypedTotalCents: totalCents,
                              items: canonicalItems,
                              itemsAdded: itemsAdded,
                            );
                            if (!mounted) return;
                            if (reason != null) {
                              messenger.showSnackBar(
                                  SnackBar(content: Text(reason)));
                            } else {
                              nav.pop();
                              messenger.showSnackBar(const SnackBar(
                                  content: Text(
                                      'Compra finalizada — siga para entrega')));
                            }
                            return;
                          }

                          // V1 legacy (storeShopping partner OU restaurant).
                          final reason =
                              await orderStore.finalizePurchaseV2(
                            orderId: order.id,
                            items: canonicalItems,
                            itemsAdded: itemsAdded,
                            bagCount: _isRestaurant ? 1 : _bagCount,
                          );
                          if (!mounted) return;
                          if (reason != null) {
                            messenger.showSnackBar(
                              SnackBar(content: Text(reason)),
                            );
                          } else {
                            nav.pop();
                            messenger.showSnackBar(
                              const SnackBar(
                                content: Text(
                                    'Compra confirmada — siga para entrega'),
                              ),
                            );
                          }
                        }
                      : null,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.green.shade600,
                    foregroundColor: Colors.white,
                    disabledBackgroundColor: Colors.grey.shade300,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                  child: Text(
                    allDecided
                        ? 'Confirmar compra'
                        : 'Marque todos os items ($pendingCount restante${pendingCount > 1 ? 's' : ''})',
                    style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 15,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─── BUG 1 — Capture receipt photo + typed total (modal bottom sheet) ──────

/// Mostra modal para estafeta tirar foto do talão + digitar valor total.
/// Returns (File, totalCents) ou null se cancelado. Decisão G: só câmara.
Future<(File, int)?> _captureReceiptForV2(
    BuildContext context, OrderModel order) async {
  final isCash = order.paymentMethod == PaymentMethod.cash;
  return showModalBottomSheet<(File, int)>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (sheetCtx) {
      return _ReceiptCaptureSheet(isCash: isCash);
    },
  );
}

class _ReceiptCaptureSheet extends StatefulWidget {
  const _ReceiptCaptureSheet({required this.isCash});
  final bool isCash;

  @override
  State<_ReceiptCaptureSheet> createState() => _ReceiptCaptureSheetState();
}

class _ReceiptCaptureSheetState extends State<_ReceiptCaptureSheet> {
  File? _photo;
  final _totalCtrl = TextEditingController();
  bool _submitting = false;

  @override
  void dispose() {
    _totalCtrl.dispose();
    super.dispose();
  }

  Future<void> _takePhoto() async {
    try {
      final picker = ImagePicker();
      final picked = await picker.pickImage(
        source: ImageSource.camera, // Decisão G — só câmara
        preferredCameraDevice: CameraDevice.rear,
        imageQuality: 80,
        maxWidth: 1600,
      );
      if (picked != null && mounted) {
        setState(() => _photo = File(picked.path));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erro câmara: $e')),
        );
      }
    }
  }

  void _onSubmit() {
    final eur = double.tryParse(_totalCtrl.text.replaceAll(',', '.'));
    if (eur == null || eur <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Valor do talão inválido.')),
      );
      return;
    }
    if (_photo == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Tira foto do talão primeiro.')),
      );
      return;
    }
    final cents = (eur * 100).round();
    setState(() => _submitting = true);
    Navigator.of(context).pop<(File, int)>((_photo!, cents));
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    final hint = widget.isCash
        ? 'Foto guardada para registo Bora (auditoria).'
        : 'Foto + valor permitem Bora reembolsar-te o valor correcto do talão.';
    return Padding(
      padding: EdgeInsets.only(bottom: bottomInset),
      child: Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
        ),
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey.shade300,
                borderRadius: BorderRadius.circular(2),
              ),
              margin: const EdgeInsets.only(bottom: 16),
            ),
            const Text(
              'Foto do talão + valor pago',
              style: TextStyle(fontWeight: FontWeight.w700, fontSize: 17),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 4),
            Text(
              hint,
              style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            GestureDetector(
              onTap: _takePhoto,
              child: Container(
                height: 160,
                decoration: BoxDecoration(
                  color: Colors.grey.shade100,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: Colors.grey.shade300),
                ),
                child: _photo == null
                    ? const Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.camera_alt, size: 36),
                            SizedBox(height: 8),
                            Text('Tirar foto do talão'),
                          ],
                        ),
                      )
                    : ClipRRect(
                        borderRadius: BorderRadius.circular(10),
                        child:
                            Image.file(_photo!, fit: BoxFit.cover),
                      ),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _totalCtrl,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(
                labelText: 'Valor total no talão (€)',
                prefixIcon: Icon(Icons.euro),
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              onPressed: _submitting ? null : _onSubmit,
              icon: _submitting
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white),
                    )
                  : const Icon(Icons.check),
              label: Text(_submitting ? 'A enviar...' : 'Confirmar'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.green.shade600,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
            ),
            const SizedBox(height: 8),
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Cancelar'),
            ),
          ],
        ),
      ),
    );
  }
}
