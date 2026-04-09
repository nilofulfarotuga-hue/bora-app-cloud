// lib/dispatch/dispatch_service.dart
//
// Improved driver selection for the BORA dispatch system.
//
// Responsibilities:
//   - Haversine distance between driver and pickup
//   - Cost calculation  (distância × cost_per_km)
//   - Composite score   (−distance×5) + (−cost×1)   →  higher = better
//   - ETA estimation    round(distance / 30 * 60) minutes
//
// This service is used CLIENT-SIDE (Flutter) to:
//   1. Pre-rank drivers for the local DriverAssignmentService (order of offers)
//   2. Calculate ETA for display to the client after a driver is assigned
//
// The backend Edge Function (supabase/functions/dispatch-engine/index.ts) uses
// the same scoring formula so both sides stay in sync.
//
// DOES NOT touch:
//   - attempted_driver_ids / driverOfferHistory  (owned by OrderModel / backend)
//   - 40-second offer timeout                    (owned by backend)
//   - re-dispatch loop                           (owned by backend)
//   - 1-driver-at-a-time guarantee               (owned by backend)

import 'dart:math' as math;

import 'package:flutter/foundation.dart';

import '../models/driver_model.dart';
import '../models/order_model.dart';
import '../stores/driver_store.dart';
import 'driver_capacity_service.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Public result type
// ─────────────────────────────────────────────────────────────────────────────

class DispatchResult {
  const DispatchResult({
    required this.driver,
    required this.distanceKm,
    required this.cost,
    required this.score,
    required this.etaMinutes,
  });

  final DriverModel driver;
  final double distanceKm;
  final double cost;
  final double score;

  /// Estimated time of arrival in minutes.
  /// Informational only — NOT used for dispatch ordering.
  final int etaMinutes;

  @override
  String toString() =>
      'DispatchResult(driver=${driver.id} dist=${distanceKm.toStringAsFixed(2)}km '
      'cost=${cost.toStringAsFixed(2)} score=${score.toStringAsFixed(2)} eta=${etaMinutes}min)';
}

// ─────────────────────────────────────────────────────────────────────────────
// DispatchService
// ─────────────────────────────────────────────────────────────────────────────

class DispatchService {
  DispatchService({
    required DriverStore driverStore,
    required DriverCapacityService capacityService,
    double costPerKm = 1.0,
  })  : _driverStore = driverStore,
        _capacityService = capacityService,
        _costPerKm = costPerKm;

  final DriverStore _driverStore;
  final DriverCapacityService _capacityService;
  final double _costPerKm;

  // Scoring weights — must match the Edge Function constants.
  static const double _distanceWeight = 5.0;
  static const double _costWeight = 1.0;

  // Average driver speed used for ETA (km/h).
  static const double _avgSpeedKmh = 30.0;

  // ── Public API ─────────────────────────────────────────────────────────────

  /// Returns the best ranked driver for [order], or `null` when no valid
  /// candidate exists (caller should fall back to original logic).
  ///
  /// [attemptedIds] mirrors attempted_driver_ids / driverOfferHistory so that
  /// already-tried drivers are excluded from ranking.
  DispatchResult? findBestDriver(
    OrderModel order, {
    List<String> attemptedIds = const [],
  }) {
    try {
      return _rank(order, attemptedIds);
    } catch (e, st) {
      debugPrint('[Dispatch] findBestDriver ERROR — falling back: $e\n$st');
      return null; // Caller must fall back to original logic.
    }
  }

  /// Returns all valid candidates ranked best-first.
  /// Empty list means caller should use original logic.
  List<DispatchResult> rankDrivers(
    OrderModel order, {
    List<String> attemptedIds = const [],
  }) {
    try {
      return _rankAll(order, attemptedIds);
    } catch (e) {
      debugPrint('[Dispatch] rankDrivers ERROR: $e');
      return const [];
    }
  }

  // ── Haversine ──────────────────────────────────────────────────────────────

  /// Straight-line distance between two lat/lng points in kilometres.
  /// Matches the Haversine implementation in the backend Edge Function.
  static double haversineKm(
    double lat1,
    double lng1,
    double lat2,
    double lng2,
  ) {
    const r = 6371.0;
    final dLat = (lat2 - lat1) * math.pi / 180;
    final dLng = (lng2 - lng1) * math.pi / 180;
    final a = math.pow(math.sin(dLat / 2), 2) +
        math.cos(lat1 * math.pi / 180) *
            math.cos(lat2 * math.pi / 180) *
            math.pow(math.sin(dLng / 2), 2);
    return r * 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
  }

  // ── Score ──────────────────────────────────────────────────────────────────

  /// Composite score — HIGHER is better.
  ///
  ///   score = (−distance × 5) + (−cost × 1)
  ///
  /// Distance dominates (weight 5) so the nearest driver wins unless
  /// cost differences are very large.
  static double computeScore(double distanceKm, double cost) {
    return (-distanceKm * _distanceWeight) + (-cost * _costWeight);
  }

  // ── ETA ───────────────────────────────────────────────────────────────────

  /// Estimated arrival time in minutes.
  /// Uses average speed of 30 km/h.  Informational only — not used for
  /// dispatch ordering.
  static int estimateEtaMinutes(double distanceKm) {
    return (distanceKm / _avgSpeedKmh * 60).round();
  }

  // ── Internal ───────────────────────────────────────────────────────────────

  DispatchResult? _rank(OrderModel order, List<String> attemptedIds) {
    final all = _rankAll(order, attemptedIds);
    if (all.isEmpty) return null;
    return all.first;
  }

  List<DispatchResult> _rankAll(OrderModel order, List<String> attemptedIds) {
    // Validate pickup coordinates — without them distance is meaningless.
    final pickupLat = order.pickupLocation?.latitude;
    final pickupLng = order.pickupLocation?.longitude;

    if (pickupLat == null || pickupLng == null) {
      debugPrint('[Dispatch] order=${order.id} has no pickup coordinates — cannot rank by distance');
      return const [];
    }

    final candidates = <_ScoredCandidate>[];

    for (final driver in _driverStore.onlineDrivers) {
      // ── Filter 1: service support ────────────────────────────────────────
      if (!driver.supportsService(
        order.serviceType,
        requiresCar: order.requiresCar,
      )) {
        continue;
      }

      // ── Filter 2: already attempted ─────────────────────────────────────
      if (attemptedIds.contains(driver.id) ||
          order.driverOfferHistory.contains(driver.id)) {
        continue;
      }

      // ── Filter 3: capacity ───────────────────────────────────────────────
      if (!_capacityService.canAssignOrder(driver, order)) {
        continue;
      }

      // ── Filter 4: valid driver coordinates ──────────────────────────────
      final driverLat = driver.location.latitude;
      final driverLng = driver.location.longitude;

      // Skip drivers at (0,0) or obviously invalid positions.
      if (driverLat == 0.0 && driverLng == 0.0) {
        debugPrint('[Dispatch] Driver ${driver.id} has (0,0) coordinates — excluded');
        continue;
      }

      // ── Score ────────────────────────────────────────────────────────────
      final distanceKm = haversineKm(driverLat, driverLng, pickupLat, pickupLng);
      final cost       = distanceKm * _costPerKm;
      final score      = computeScore(distanceKm, cost);

      debugPrint(
        '[Dispatch] Driver ${driver.id} '
        'distância=${distanceKm.toStringAsFixed(2)}km '
        'custo=${cost.toStringAsFixed(2)} '
        'score=${score.toStringAsFixed(2)}',
      );

      candidates.add(_ScoredCandidate(
        driver:     driver,
        distanceKm: distanceKm,
        cost:       cost,
        score:      score,
      ));
    }

    if (candidates.isEmpty) {
      debugPrint('[Dispatch] Nenhum driver válido após filtros (order=${order.id})');
      return const [];
    }

    // Sort DESC — highest score first (= nearest / cheapest driver first).
    candidates.sort((a, b) => b.score.compareTo(a.score));

    final results = candidates.map((c) {
      final eta = estimateEtaMinutes(c.distanceKm);
      return DispatchResult(
        driver:     c.driver,
        distanceKm: c.distanceKm,
        cost:       c.cost,
        score:      c.score,
        etaMinutes: eta,
      );
    }).toList(growable: false);

    final best = results.first;
    debugPrint('[Dispatch] Driver selecionado=${best.driver.id}');
    debugPrint('[Dispatch] ETA estimado=${best.etaMinutes} minutos');

    return results;
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Internal candidate (not exported)
// ─────────────────────────────────────────────────────────────────────────────

class _ScoredCandidate {
  const _ScoredCandidate({
    required this.driver,
    required this.distanceKm,
    required this.cost,
    required this.score,
  });

  final DriverModel driver;
  final double distanceKm;
  final double cost;
  final double score;
}
