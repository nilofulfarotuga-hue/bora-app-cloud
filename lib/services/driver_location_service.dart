import 'dart:async';

/// ─────────────────────────────────────────────────────────────────────────────
/// DEPRECATED — location source of truth unified.
///
/// Historically this service ran a SECOND Geolocator stream (in addition to
/// the one in DriverMapScreen) and wrote positions directly to
/// `orders.driver_lat/driver_lng`. That created two problems:
///
///   1. Two concurrent GPS streams with different distance filters, competing
///      for the same hardware and producing divergent data.
///   2. A duplicated source of truth (`orders.driver_lat/driver_lng`) alongside
///      `DriverStore.currentDriver.location` (backed by the `drivers` table).
///
/// The single source of truth is now `DriverStore.currentDriver.location`,
/// which:
///   • is written exclusively by the driver UI via DriverStore.updateDriverLocation
///     (which upserts into the `drivers` table);
///   • is read by every other client via the Supabase Realtime subscription on
///     `drivers` already wired in DriverStore._initialiseRealtimeDriverTracking.
///
/// This class is kept only to preserve the existing OrderStore call sites
/// (acceptOrder / finishOrder / cancelDelivery / dispose). All methods are
/// intentional no-ops.
/// ─────────────────────────────────────────────────────────────────────────────
class DriverLocationService {
  bool get isTracking => false;

  Future<void> startTracking(String orderId) async {
    // No-op. GPS tracking is handled by DriverMapScreen which writes
    // exclusively to DriverStore (single source of truth).
  }

  Future<void> stopTracking() async {
    // No-op.
  }

  void dispose() {
    // No-op.
  }
}
