import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Streams the driver's real GPS position directly into the `orders` table
/// (`driver_lat` / `driver_lng`) so clients can track delivery in real time
/// via the existing Supabase realtime ORDER UPDATE channel.
class DriverLocationService {
  final _supabase = Supabase.instance.client;

  StreamSubscription<Position>? _subscription;
  String? _activeOrderId;

  bool get isTracking => _activeOrderId != null;

  /// Starts writing GPS fixes to `orders.driver_lat/driver_lng` for [orderId].
  /// Safe to call multiple times — stops any previous tracking first.
  Future<void> startTracking(String orderId) async {
    await stopTracking();

    if (kIsWeb) return; // Geolocator position stream not supported on web

    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    if (permission == LocationPermission.denied ||
        permission == LocationPermission.deniedForever) {
      debugPrint('DriverLocationService: location permission denied');
      return;
    }

    _activeOrderId = orderId;
    _subscription = Geolocator.getPositionStream(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 10, // metres — prevents excessive DB writes
      ),
    ).listen(
      (position) => _persist(position),
      onError: (e) => debugPrint('DriverLocationService stream error => $e'),
    );

    debugPrint('DriverLocationService: tracking started for order $orderId');
  }

  Future<void> stopTracking() async {
    await _subscription?.cancel();
    _subscription = null;
    _activeOrderId = null;
    debugPrint('DriverLocationService: tracking stopped');
  }

  void dispose() {
    _subscription?.cancel();
  }

  Future<void> _persist(Position position) async {
    final orderId = _activeOrderId;
    if (orderId == null) return;
    try {
      await _supabase.from('orders').update({
        'driver_lat': position.latitude,
        'driver_lng': position.longitude,
      }).eq('id', orderId);
    } catch (e) {
      debugPrint('DriverLocationService._persist error => $e');
    }
  }
}
