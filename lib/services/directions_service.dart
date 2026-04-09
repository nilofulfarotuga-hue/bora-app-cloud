import 'package:latlong2/latlong.dart' as ll;

import 'directions_service_stub.dart'
    if (dart.library.html) 'directions_service_web.dart'
    if (dart.library.io) 'directions_service_io.dart';

/// Decoded route returned by [DirectionsService.fetchRoute].
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

/// Travel mode used by the Directions API.
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

/// Platform-adaptive Directions API client.
///
/// On mobile (Android / iOS) the implementation calls the Google Directions
/// REST API directly over HTTP.
///
/// On web the implementation delegates to the Google Maps JavaScript SDK
/// (already loaded in index.html), avoiding CORS issues entirely.
///
/// Usage:
/// ```dart
/// final service = DirectionsService();
/// final route = await service.fetchRoute(origin: a, destination: b);
/// service.dispose();
/// ```
abstract class DirectionsService {
  /// Factory constructor — returns the platform-appropriate implementation
  /// via conditional import. Callers do not need to know which platform
  /// they are running on.
  factory DirectionsService() => createDirectionsServiceImpl();

  /// Fetches a driving/walking/bicycling route between [origin] and
  /// [destination], optionally passing through [waypoints].
  ///
  /// Returns null when the API is unavailable, the key is missing, or the
  /// request fails for any reason. Callers should fall back to a
  /// straight-line display in that case.
  Future<DirectionsRoute?> fetchRoute({
    required ll.LatLng origin,
    required ll.LatLng destination,
    List<ll.LatLng> waypoints = const [],
    TravelMode mode = TravelMode.driving,
  });

  /// Releases any resources held by this service instance.
  void dispose();
}
