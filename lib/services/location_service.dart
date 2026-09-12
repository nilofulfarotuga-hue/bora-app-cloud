import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';

class LocationService {
  static bool _consentGranted = true;

  /// Whether [getCurrentLocation] returned null specifically because the user
  /// has not granted location consent in the GDPR banner.
  /// Use this at call sites to show a targeted SnackBar instead of a generic
  /// error message.
  static bool get isConsentBlocked => !_consentGranted;

  /// Called by [ConsentStore] whenever the user saves their GDPR preferences.
  static void applyLocationConsent(bool allowed) {
    _consentGranted = allowed;
    debugPrint('LocationService: consent = $allowed');
  }

  /// Returns the device's current GPS location, or null when unavailable.
  ///
  /// Handles all permission states including [LocationPermission.deniedForever].
  /// Never throws — returns null on any failure.
  /// Returns null immediately (without requesting OS permission) when the user
  /// has rejected location consent in the GDPR banner.
  static Future<LatLng?> getCurrentLocation() async {
    if (!_consentGranted) {
      debugPrint('LocationService: location consent not granted — returning null');
      return null;
    }
    // On web, isLocationServiceEnabled() always returns true; skip the check.
    if (!kIsWeb) {
      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        debugPrint('LocationService: location services disabled');
        return null;
      }
    }

    LocationPermission permission = await Geolocator.checkPermission();

    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }

    if (permission == LocationPermission.denied ||
        permission == LocationPermission.deniedForever) {
      debugPrint(
          'LocationService: permission $permission — cannot get location');
      return null;
    }

    try {
      // [4F · 05/09] Forma nova do geolocator 14 — `desiredAccuracy` ficou
      // deprecado na subida de pacote desta missão. Mesma precisão.
      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
        ),
      ).timeout(const Duration(seconds: 15));
      return LatLng(position.latitude, position.longitude);
    } catch (e) {
      debugPrint('LocationService: getCurrentPosition error => $e');
      return null;
    }
  }

  /// Reverse-geocodes [location] to a human-readable address string via the
  /// Google Geocoding API. Returns null on failure.
  static Future<String?> reverseGeocode(LatLng location, String apiKey) async {
    if (apiKey.isEmpty) return null;

    final uri = Uri.https(
      'maps.googleapis.com',
      '/maps/api/geocode/json',
      {
        'latlng': '${location.latitude},${location.longitude}',
        'key': apiKey,
        'language': 'pt-PT',
        'result_type': 'street_address',
      },
    );

    try {
      final response = await http.get(uri);
      if (response.statusCode != 200) {
        debugPrint(
            'LocationService.reverseGeocode: HTTP ${response.statusCode}');
        return null;
      }
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      final status = data['status'] as String?;
      if (status != 'OK') {
        debugPrint('LocationService.reverseGeocode: status=$status');
        return null;
      }
      final results = data['results'] as List<dynamic>?;
      if (results == null || results.isEmpty) return null;
      return (results.first as Map<String, dynamic>)['formatted_address']
          as String?;
    } catch (e) {
      debugPrint('LocationService.reverseGeocode: error => $e');
      return null;
    }
  }
}
