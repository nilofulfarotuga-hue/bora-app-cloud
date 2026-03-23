import 'package:flutter/foundation.dart';
import 'package:latlong2/latlong.dart';

import 'directions_service.dart';
import 'distance_service.dart';

class MapsService {
  /// Returns the real road distance in km between [origin] and [destination]
  /// using the Google Directions API.
  ///
  /// Falls back to straight-line Haversine distance if:
  /// - The API key is not configured.
  /// - The network request fails.
  /// - The API returns no valid route.
  static Future<double?> getDistanceKm(
    LatLng origin,
    LatLng destination,
  ) async {
    final service = DirectionsService();
    try {
      final route = await service.fetchRoute(
        origin: origin,
        destination: destination,
        mode: TravelMode.driving,
      );
      if (route != null && route.distanceKm > 0) {
        return route.distanceKm;
      }
    } catch (e) {
      debugPrint('MapsService: getDistanceKm error => $e');
    } finally {
      service.dispose();
    }

    // Fallback: straight-line distance.
    return DistanceService.calculateDistanceKm(
      origin.latitude,
      origin.longitude,
      destination.latitude,
      destination.longitude,
    );
  }
}
