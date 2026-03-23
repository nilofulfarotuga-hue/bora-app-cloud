import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_polyline_points/flutter_polyline_points.dart';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart' as ll;

import '../config/maps_config.dart';

class DirectionsRoute {
  DirectionsRoute({
    required this.points,
    required this.distanceMeters,
    required this.durationSeconds,
  });

  final List<ll.LatLng> points;
  final double distanceMeters;
  final double durationSeconds;

  double get distanceKm => distanceMeters / 1000;
  double get durationMinutes => durationSeconds / 60;
}

enum TravelMode {
  driving,
  walking,
  bicycling,
}

extension TravelModeValue on TravelMode {
  String get value {
    switch (this) {
      case TravelMode.driving:
        return 'driving';
      case TravelMode.walking:
        return 'walking';
      case TravelMode.bicycling:
        return 'bicycling';
    }
  }
}

class DirectionsService {
  DirectionsService({http.Client? client}) : _client = client ?? http.Client();

  final http.Client _client;

  static const String _endpoint =
      'https://maps.googleapis.com/maps/api/directions/json';

  Future<DirectionsRoute?> fetchRoute({
    required ll.LatLng origin,
    required ll.LatLng destination,
    List<ll.LatLng> waypoints = const [],
    TravelMode mode = TravelMode.driving,
  }) async {
    if (googleApiKey.isEmpty) {
      debugPrint(
        'DirectionsService: GOOGLE_MAPS_API_KEY was not provided. Falling back to straight-line route.',
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
          'DirectionsService: Request failed with status ${response.statusCode}',
        );
        return null;
      }

      final json = jsonDecode(response.body) as Map<String, dynamic>;
      final status = json['status'] as String?;
      if (status != 'OK') {
        debugPrint(
          'DirectionsService: Unexpected status $status => ${json['error_message']}',
        );
        return null;
      }

      final routes = json['routes'] as List<dynamic>?;
      if (routes == null || routes.isEmpty) {
        return null;
      }

      final route = routes.first as Map<String, dynamic>;
      final polyline = (route['overview_polyline'] as Map<String, dynamic>?)?['points']
          as String?;
      if (polyline == null || polyline.isEmpty) {
        return null;
      }

      final decoded = PolylinePoints.decodePolyline(polyline);
      if (decoded.isEmpty) {
        return null;
      }

      double distanceMeters = 0;
      double durationSeconds = 0;
      final legs = route['legs'] as List<dynamic>?;
      if (legs != null && legs.isNotEmpty) {
        for (final rawLeg in legs) {
          final leg = rawLeg as Map<String, dynamic>;
          final legDistance = leg['distance'] as Map<String, dynamic>?;
          final legDuration = leg['duration'] as Map<String, dynamic>?;
          final valueDistance = legDistance?['value'];
          final valueDuration = legDuration?['value'];
          if (valueDistance is num) {
            distanceMeters += valueDistance.toDouble();
          }
          if (valueDuration is num) {
            durationSeconds += valueDuration.toDouble();
          }
        }
      }

      final points = decoded
          .map((point) => ll.LatLng(point.latitude, point.longitude))
          .toList(growable: false);

      return DirectionsRoute(
        points: points,
        distanceMeters: distanceMeters,
        durationSeconds: durationSeconds,
      );
    } catch (error, stackTrace) {
      debugPrint('DirectionsService: $error');
      debugPrint('$stackTrace');
      return null;
    }
  }

  void dispose() {
    _client.close();
  }
}
