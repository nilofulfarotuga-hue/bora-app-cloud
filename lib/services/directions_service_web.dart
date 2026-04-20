// ignore_for_file: avoid_web_libraries_in_flutter

import 'dart:async';
import 'dart:js' as js;

import 'package:flutter/foundation.dart';
import 'package:latlong2/latlong.dart' as ll;

import 'directions_service.dart';

/// Conditional-import entry point — called by [DirectionsService] factory
/// on Flutter Web.
DirectionsService createDirectionsServiceImpl() => _WebDirectionsService();

/// Web implementation that delegates to the Google Maps JavaScript SDK
/// already loaded in index.html — no HTTP calls, no CORS issues.
///
/// Follows the same JS-interop pattern as place_autocomplete_service_web.dart.
class _WebDirectionsService implements DirectionsService {
  js.JsObject? _directionsSvc;
  js.JsFunction? _latLngCtor;

  /// Lazily creates the JS DirectionsService and caches the LatLng constructor.
  /// Returns false if google.maps is not yet available.
  bool _init() {
    if (_directionsSvc != null) return true;

    try {
      final googleRaw = js.context['google'];
      if (googleRaw == null || googleRaw is! js.JsObject) return false;

      final mapsRaw = googleRaw['maps'];
      if (mapsRaw == null || mapsRaw is! js.JsObject) return false;

      final dirCtor = mapsRaw['DirectionsService'];
      if (dirCtor == null || dirCtor is! js.JsFunction) return false;

      final llCtor = mapsRaw['LatLng'];
      if (llCtor == null || llCtor is! js.JsFunction) return false;

      _directionsSvc = js.JsObject(dirCtor);
      _latLngCtor = llCtor;
      return true;
    } catch (e) {
      debugPrint('DirectionsService (web): _init error => $e');
      return false;
    }
  }

  /// Resolves the JS TravelMode enum value for [mode].
  /// Falls back to the uppercase string if the enum object is unavailable.
  dynamic _resolveTravelMode(TravelMode mode) {
    try {
      final googleRaw = js.context['google'] as js.JsObject;
      final mapsRaw = googleRaw['maps'] as js.JsObject;
      final tmRaw = mapsRaw['TravelMode'];
      if (tmRaw != null && tmRaw is js.JsObject) {
        final resolved = tmRaw[mode.value.toUpperCase()];
        if (resolved != null) return resolved;
      }
    } catch (_) {}
    // Fallback: the JS API also accepts plain strings.
    return mode.value.toUpperCase();
  }

  @override
  Future<DirectionsRoute?> fetchRoute({
    required ll.LatLng origin,
    required ll.LatLng destination,
    List<ll.LatLng> waypoints = const [],
    TravelMode mode = TravelMode.driving,
  }) async {
    if (!_init()) {
      debugPrint(
        'DirectionsService (web): google.maps not available — returning null.',
      );
      return null;
    }

    // Build origin / destination as google.maps.LatLng JS objects.
    final originJs =
        js.JsObject(_latLngCtor!, [origin.latitude, origin.longitude]);
    final destJs = js.JsObject(
        _latLngCtor!, [destination.latitude, destination.longitude]);

    // Build the request object. We set simple Dart values via jsify and
    // attach JsObject values (LatLng instances) directly to avoid
    // double-wrapping.
    final request = js.JsObject.jsify(<String, dynamic>{
      'optimizeWaypoints': false,
    });
    request['origin'] = originJs;
    request['destination'] = destJs;
    request['travelMode'] = _resolveTravelMode(mode);

    // Waypoints (if any).
    if (waypoints.isNotEmpty) {
      final wpArray = js.JsArray<js.JsObject>();
      for (final w in waypoints) {
        final wpObj = js.JsObject.jsify(<String, dynamic>{'stopover': true});
        wpObj['location'] =
            js.JsObject(_latLngCtor!, [w.latitude, w.longitude]);
        wpArray.add(wpObj);
      }
      request['waypoints'] = wpArray;
    }

    // Call google.maps.DirectionsService.route(request, callback).
    final completer = Completer<DirectionsRoute?>();

    _directionsSvc!.callMethod('route', <dynamic>[
      request,
      (dynamic result, dynamic status) {
        if (completer.isCompleted) return;

        if (status?.toString() != 'OK' || result == null) {
          debugPrint('DirectionsService (web): status=$status');
          completer.complete(null);
          return;
        }

        try {
          completer.complete(_parseResult(result as js.JsObject));
        } catch (e) {
          debugPrint('DirectionsService (web): parse error => $e');
          completer.complete(null);
        }
      },
    ]);

    try {
      return await completer.future.timeout(const Duration(seconds: 15));
    } catch (e) {
      debugPrint('DirectionsService (web): timeout / error => $e');
      return null;
    }
  }

  /// Parses a JS DirectionsResult into a [DirectionsRoute].
  DirectionsRoute? _parseResult(js.JsObject result) {
    final routes = result['routes'];
    if (routes == null) return null;

    final routesArr = routes as js.JsArray;
    if (routesArr.isEmpty) return null;

    final route = routesArr[0] as js.JsObject;

    // ── Points from overview_path (already decoded by the JS SDK) ────────
    final overviewPath = route['overview_path'];
    if (overviewPath == null) return null;

    final pathArr = overviewPath as js.JsArray;
    if (pathArr.isEmpty) return null;

    final points = <ll.LatLng>[];
    for (var i = 0; i < pathArr.length; i++) {
      final point = pathArr[i] as js.JsObject;
      final lat =
          (point.callMethod('lat', const <dynamic>[]) as num).toDouble();
      final lng =
          (point.callMethod('lng', const <dynamic>[]) as num).toDouble();
      points.add(ll.LatLng(lat, lng));
    }

    // ── Distance and duration from legs ──────────────────────────────────
    double distanceMeters = 0;
    double durationSeconds = 0;

    final legs = route['legs'];
    if (legs != null && legs is js.JsArray) {
      for (var i = 0; i < legs.length; i++) {
        final leg = legs[i] as js.JsObject;

        final dist = leg['distance'];
        if (dist != null && dist is js.JsObject) {
          final v = dist['value'];
          if (v is num) distanceMeters += v.toDouble();
        }

        final dur = leg['duration'];
        if (dur != null && dur is js.JsObject) {
          final v = dur['value'];
          if (v is num) durationSeconds += v.toDouble();
        }
      }
    }

    return DirectionsRoute(
      points: points,
      distanceMeters: distanceMeters,
      durationSeconds: durationSeconds,
    );
  }

  @override
  void dispose() {
    _directionsSvc = null;
    _latLngCtor = null;
  }
}
