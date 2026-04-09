import 'package:flutter/foundation.dart';
import 'package:latlong2/latlong.dart';

import '../config/maps_config.dart';
import '../services/location_service.dart';

/// Lightweight reverse-geocoding helper with an in-memory cache.
///
/// Call [resolve] with a [LatLng] to get a human-readable address string.
/// Results are cached for the lifetime of the app process so repeated
/// lookups for the same coordinates never hit the network twice.
///
/// If the Google Geocoding API fails or returns nothing, the original
/// coordinates are returned as a formatted string (fallback).
class AddressResolver {
  AddressResolver._();

  // Cache keyed by "lat,lng" rounded to 4 decimals (~11 m precision).
  // This avoids duplicate calls for nearly-identical positions.
  static final Map<String, String> _cache = {};

  /// Returns a human-readable address for [coords].
  ///
  /// - Checks cache first (instant, no network).
  /// - Falls back to LocationService.reverseGeocode (async, network).
  /// - If everything fails, returns the raw coordinates as a string.
  static Future<String> resolve(LatLng coords) async {
    final key = _cacheKey(coords);

    // Cache hit — return immediately.
    if (_cache.containsKey(key)) {
      return _cache[key]!;
    }

    // Network lookup via existing LocationService.
    try {
      final address = await LocationService.reverseGeocode(
        coords,
        googleApiKey,
      );
      if (address != null && address.isNotEmpty) {
        _cache[key] = address;
        return address;
      }
    } catch (e) {
      debugPrint('AddressResolver: reverseGeocode error => $e');
    }

    // Fallback: formatted coordinates.
    final fallback =
        '${coords.latitude.toStringAsFixed(4)}, ${coords.longitude.toStringAsFixed(4)}';
    _cache[key] = fallback;
    return fallback;
  }

  /// Returns true when [text] looks like raw coordinates rather than a
  /// real address. Useful to decide whether to trigger a resolve.
  ///
  /// Matches patterns like "38.7223, -9.1393" or "-9.1393, 38.7223".
  static bool looksLikeCoordinates(String? text) {
    if (text == null || text.isEmpty) return false;
    // Simple heuristic: if the string is just two numbers separated by
    // comma+space, it's almost certainly coordinates, not an address.
    final trimmed = text.trim();
    final parts = trimmed.split(',');
    if (parts.length != 2) return false;
    final a = double.tryParse(parts[0].trim());
    final b = double.tryParse(parts[1].trim());
    return a != null && b != null;
  }

  /// Clears the entire cache. Useful in tests or after a locale change.
  static void clearCache() => _cache.clear();

  static String _cacheKey(LatLng coords) =>
      '${coords.latitude.toStringAsFixed(4)},${coords.longitude.toStringAsFixed(4)}';
}