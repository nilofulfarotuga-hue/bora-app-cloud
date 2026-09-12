import 'package:flutter/foundation.dart';
import 'package:latlong2/latlong.dart';

import 'directions_service.dart';

class MapsService {
  /// Returns the real road distance in km between [origin] and [destination]
  /// using the Google Directions API.
  ///
  /// Returns null if:
  /// - The API key is not configured.
  /// - The network request fails.
  /// - The API returns no valid route.
  ///
  /// Callers are responsible for applying a Haversine fallback when null is
  /// returned. This makes the estimated-distance flag accurate.
  static Future<double?> getDistanceKm(
    LatLng origin,
    LatLng destination,
  ) async {
    final service = DirectionsService();
    try {
      // [C] 2026-06-30 — timeout: sem isto a chamada de rota podia pendurar e
      // travar o cálculo de distância (e o preço a montante). Em timeout cai no
      // catch → null → o caller aplica o fallback Haversine.
      final route = await service
          .fetchRoute(
            origin: origin,
            destination: destination,
            mode: TravelMode.driving,
          )
          .timeout(const Duration(seconds: 12));
      if (route != null && route.distanceKm > 0) {
        return route.distanceKm;
      }
    } catch (e) {
      debugPrint('MapsService: getDistanceKm error => $e');
    } finally {
      service.dispose();
    }

    // API unavailable — return null so callers can set isDistanceEstimated.
    return null;
  }
}
