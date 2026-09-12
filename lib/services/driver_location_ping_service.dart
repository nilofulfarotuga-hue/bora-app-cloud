import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Throttled ping helper for the new admin live ops map (B1).
///
/// The driver app already streams GPS via Geolocator.getPositionStream — every
/// fix flows through `DriverStore.updateDriverLocation` (writes to drivers
/// table for the legacy realtime channel). This helper additionally upserts
/// `driver_locations` via the `driver_update_location` RPC at most once per
/// `minIntervalSeconds` (default 10s).
///
/// Foreground only. A real background service requires Android Foreground
/// Service + iOS Background Modes — documented as Grupo E E1.
class DriverLocationPingService {
  DriverLocationPingService._();
  static final instance = DriverLocationPingService._();

  DateTime? _lastPing;
  bool _inFlight = false;
  // 45s idle (was 10s): admin map freshness window is ~5min; 10s was 30× too eager.
  static const int minIntervalSeconds = 45;

  /// Best-effort ping. Safe to call on every GPS tick — internally throttled.
  /// Set [isOnline] to false on logout / go-offline so the driver disappears
  /// from the live map within ~5min freshness window.
  Future<void> ping({
    required double latitude,
    required double longitude,
    double? heading,
    double? speedKmh,
    bool isOnline = true,
  }) async {
    if (!isOnline) return; // no ping when offline — goOffline() handles final update
    if (_inFlight) return;
    final now = DateTime.now();
    if (_lastPing != null &&
        now.difference(_lastPing!).inSeconds < minIntervalSeconds) {
      return;
    }
    _inFlight = true;
    try {
      await Supabase.instance.client.rpc('driver_update_location', params: {
        'p_latitude': latitude,
        'p_longitude': longitude,
        if (heading != null) 'p_heading': heading,
        if (speedKmh != null) 'p_speed_kmh': speedKmh,
        'p_is_online': isOnline,
      });
      _lastPing = now;
    } catch (e) {
      debugPrint('[DriverLocationPing] failed: $e');
    } finally {
      _inFlight = false;
    }
  }

  /// Called on logout / go-offline — single ping with is_online=false so the
  /// admin map removes the driver immediately (no waiting for 5min freshness).
  Future<void> goOffline({
    required double latitude,
    required double longitude,
  }) async {
    _lastPing = null; // bypass throttle
    await ping(
      latitude: latitude,
      longitude: longitude,
      isOnline: false,
    );
  }
}
