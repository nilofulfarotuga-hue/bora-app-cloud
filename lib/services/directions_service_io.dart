import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_polyline_points/flutter_polyline_points.dart'
    hide TravelMode;
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart' as ll;

import '../config/maps_config.dart';
import 'directions_service.dart';

/// Conditional-import entry point — called by [DirectionsService] factory
/// on Android / iOS / desktop.
DirectionsService createDirectionsServiceImpl() => _IoDirectionsService();

/// Mobile implementation that calls the Google Directions REST API directly
/// over HTTP. No CORS restrictions apply on native platforms.
class _IoDirectionsService implements DirectionsService {
  _IoDirectionsService() : _client = http.Client();

  final http.Client _client;

  static const String _endpoint =
      'https://maps.googleapis.com/maps/api/directions/json';

  @override
  Future<DirectionsRoute?> fetchRoute({
    required ll.LatLng origin,
    required ll.LatLng destination,
    List<ll.LatLng> waypoints = const [],
    TravelMode mode = TravelMode.driving,
  }) async {
    if (googleApiKey.isEmpty) {
      debugPrint(
        'DirectionsService (IO): API key not provided — returning null.',
      );
      return null;
    }

    final params = <String, String>{
      'origin': '${origin.latitude},${origin.longitude}',
      'destination': '${destination.latitude},${destination.longitude}',
      'mode': mode.value,
      'key': googleApiKey,
    };
    if (waypoints.isNotEmpty) {
      params['waypoints'] =
          waypoints.map((w) => '${w.latitude},${w.longitude}').join('|');
    }

    final uri = Uri.parse(_endpoint).replace(queryParameters: params);

    try {
      final response = await _client.get(uri);
      if (response.statusCode != 200) {
        debugPrint(
          'DirectionsService (IO): HTTP ${response.statusCode}',
        );
        return null;
      }

      final json = jsonDecode(response.body) as Map<String, dynamic>;
      final status = json['status'] as String?;
      if (status != 'OK') {
        debugPrint(
          'DirectionsService (IO): status=$status => ${json['error_message']}',
        );
        return null;
      }

      final routes = json['routes'] as List<dynamic>?;
      if (routes == null || routes.isEmpty) return null;

      final route = routes.first as Map<String, dynamic>;
      final polyline = (route['overview_polyline']
          as Map<String, dynamic>?)?['points'] as String?;
      if (polyline == null || polyline.isEmpty) return null;

      final decoded = PolylinePoints.decodePolyline(polyline);
      if (decoded.isEmpty) return null;

      double distanceMeters = 0;
      double durationSeconds = 0;
      final legs = route['legs'] as List<dynamic>?;
      if (legs != null) {
        for (final rawLeg in legs) {
          final leg = rawLeg as Map<String, dynamic>;
          final dVal = (leg['distance'] as Map<String, dynamic>?)?['value'];
          final tVal = (leg['duration'] as Map<String, dynamic>?)?['value'];
          if (dVal is num) distanceMeters += dVal.toDouble();
          if (tVal is num) durationSeconds += tVal.toDouble();
        }
      }

      final points = decoded
          .map((p) => ll.LatLng(p.latitude, p.longitude))
          .toList(growable: false);

      return DirectionsRoute(
        points: points,
        distanceMeters: distanceMeters,
        durationSeconds: durationSeconds,
      );
    } catch (error, stack) {
      debugPrint('DirectionsService (IO): $error');
      debugPrint('$stack');
      return null;
    }
  }

  @override
  void dispose() {
    _client.close();
  }
}
