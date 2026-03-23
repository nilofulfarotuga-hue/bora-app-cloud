import 'dart:async';

import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../dispatch/driver_capacity_service.dart';
import '../models/driver_model.dart';
import '../models/order_model.dart';

class DriverStore extends ChangeNotifier {
  String _primaryDriverId = 'driver-main';
  static const int _locationAnimationSteps = 12;
  static const Duration _locationAnimationStepDuration =
      Duration(milliseconds: 80);

  DriverStore({DriverCapacityService? capacityService})
      : _capacityService = capacityService ?? DriverCapacityService() {
    _initialiseRealtimeDriverTracking();
  }

  final DriverCapacityService _capacityService;
  final List<DriverModel> _drivers = [];
  final SupabaseClient _client = Supabase.instance.client;

  Timer? _trackingTimer;
  String? _trackedOrderId;
  RealtimeChannel? _driverLocationChannel;
  final Map<String, Timer> _locationAnimations = <String, Timer>{};

  DriverModel? get currentDriver => getDriverById(_primaryDriverId);

  VehicleType get currentVehicleType =>
      currentDriver?.vehicleType ?? VehicleType.motorcycle;

  String get currentDriverId => _primaryDriverId;

  List<DriverModel> get drivers => List.unmodifiable(_drivers);

  List<DriverModel> get onlineDrivers =>
      _drivers.where((driver) => driver.isOnline).toList(growable: false);

  DriverCapacityService get capacityService => _capacityService;

  void configurePrimaryDriver({
    required String name,
    required String phone,
    required VehicleType vehicleType,
    String? licensePlate,
    String? driverId,
  }) {
    // Prefer the Supabase auth user ID when provided; fall back to a
    // phone-derived ID so the demo account and existing sessions keep working.
    final newId = (driverId != null && driverId.isNotEmpty)
        ? driverId
        : 'driver-${phone.replaceAll(RegExp(r'[^0-9a-zA-Z]'), '')}';

    // If the ID changed (first login or different driver), drop the old slot.
    if (_primaryDriverId != newId) {
      _drivers.removeWhere((d) => d.id == _primaryDriverId);
      _primaryDriverId = newId;
    }

    var driver = getDriverById(_primaryDriverId);
    if (driver == null) {
      driver = DriverModel(
        id: _primaryDriverId,
        name: name,
        location: const LatLng(38.7223, -9.1393),
        vehicleType: vehicleType,
        phone: phone,
        isOnline: false,
      );
      _drivers.add(driver);
    } else {
      driver
        ..name = name
        ..phone = phone
        ..vehicleType = vehicleType
        ..licensePlate = licensePlate;
    }
    notifyListeners();
  }

  DriverModel? getDriverById(String id) {
    try {
      return _drivers.firstWhere((driver) => driver.id == id);
    } catch (_) {
      return null;
    }
  }

  bool toggleAvailability(String driverId, bool value) {
    final driver = getDriverById(driverId);
    if (driver == null) return false;
    if (!value && driver.activeAssignments.isNotEmpty) {
      return false;
    }
    if (driver.isOnline == value) {
      return true;
    }
    driver.isOnline = value;
    notifyListeners();
    unawaited(updateDriverOnlineStatus(driverId, value));
    return true;
  }

  Future<void> updateDriverOnlineStatus(String driverId, bool isOnline) async {
    try {
      await _client
          .from('drivers')
          .update({'is_online': isOnline})
          .eq('id', driverId);
    } catch (e) {
      debugPrint('DriverStore: updateDriverOnlineStatus error => $e');
    }
  }

  bool registerOrderForDriver(String driverId, OrderModel order) {
    final driver = getDriverById(driverId);
    if (driver == null) return false;
    if (!driver.supportsService(order.serviceType)) {
      return false;
    }
    if (driver.activeAssignments.any((info) => info.orderId == order.id)) {
      return true;
    }
    driver.activeAssignments.add(
      DriverAssignmentInfo(
        orderId: order.id,
        serviceType: order.serviceType,
        isPartnerOrder: order.isPartnerOrder,
        vendorName: order.vendorName,
        pickupLocation: order.pickupLocation ?? order.destination,
        pickupStreet: order.pickupStreet ?? order.pickupAddress,
      ),
    );
    order.driverPhone = driver.phone;
    notifyListeners();
    return true;
  }

  bool releaseOrderForDriver(String driverId, String orderId) {
    final driver = getDriverById(driverId);
    if (driver == null) return false;
    final before = driver.activeAssignments.length;
    driver.activeAssignments.removeWhere((info) => info.orderId == orderId);
    final removed = before != driver.activeAssignments.length;
    if (removed) {
      notifyListeners();
    }
    return removed;
  }

  List<DriverAssignmentInfo> assignmentsFor(String driverId) {
    final driver = getDriverById(driverId);
    if (driver == null) return const <DriverAssignmentInfo>[];
    return List.unmodifiable(driver.activeAssignments);
  }

  bool hasActiveOrders(String driverId) {
    final driver = getDriverById(driverId);
    if (driver == null) return false;
    return driver.activeAssignments.isNotEmpty;
  }

  bool canAcceptOrder(String driverId, OrderModel order) {
    final driver = getDriverById(driverId);
    if (driver == null) return false;
    if (!driver.supportsService(order.serviceType)) {
      return false;
    }
    return _capacityService.canAssignOrder(driver, order);
  }

  void updateDriverLocation(String driverId, LatLng location) {
    final driver = getDriverById(driverId);
    if (driver == null) return;
    driver.location = location;
    notifyListeners();

    _client.from('drivers').upsert({
      'id': driverId,
      'lat': location.latitude,
      'lng': location.longitude,
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    });
  }

  void startTracking(OrderModel order) {
    if (order.destination == null && order.pickupLocation == null) {
      return;
    }
    _trackedOrderId = order.id;
    _trackingTimer?.cancel();
    _trackingTimer = Timer.periodic(const Duration(seconds: 2), (_) {
      _tickTracking(order);
    });
  }

  void updateTrackingTarget(OrderModel order) {
    if (_trackedOrderId != order.id) {
      return;
    }
    if (order.status == OrderStatus.delivered) {
      stopTracking(order.id);
    }
  }

  void stopTracking(String orderId) {
    if (_trackedOrderId != orderId) {
      return;
    }
    _trackedOrderId = null;
    _trackingTimer?.cancel();
    _trackingTimer = null;
  }

  void _tickTracking(OrderModel order) {
    if (_trackedOrderId != order.id) {
      return;
    }

    final driver = currentDriver;
    if (driver == null) return;
    final target = _resolveTrackingTarget(order);
    if (target == null) {
      stopTracking(order.id);
      return;
    }

    final distanceKm = const Distance().as(
      LengthUnit.Kilometer,
      driver.location,
      target,
    );

    if (!distanceKm.isFinite) {
      return;
    }

    if (distanceKm <= 0.05) {
      if (order.status == OrderStatus.delivered) {
        stopTracking(order.id);
      }
      return;
    }

    const stepKm = 0.2;
    final ratio = (stepKm / distanceKm).clamp(0.0, 1.0);

    final nextLat = driver.location.latitude +
        (target.latitude - driver.location.latitude) * ratio;
    final nextLon = driver.location.longitude +
        (target.longitude - driver.location.longitude) * ratio;

    driver.location = LatLng(nextLat, nextLon);
    notifyListeners();
  }

  LatLng? _resolveTrackingTarget(OrderModel order) {
    if (order.status.index <= OrderStatus.driverAccepted.index) {
      return order.pickupLocation ?? order.destination;
    }
    if (order.status.index < OrderStatus.delivered.index) {
      return order.destination ?? order.pickupLocation;
    }
    return null;
  }

  void _initialiseRealtimeDriverTracking() {
    Future.microtask(_loadInitialDriverLocations);

    _driverLocationChannel = _client
        .channel('drivers_channel')
      ..onPostgresChanges(
        event: PostgresChangeEvent.insert,
        schema: 'public',
        table: 'drivers',
        callback: (payload) => _handleRealtimeDriverRecord(payload.newRecord),
      )
      ..onPostgresChanges(
        event: PostgresChangeEvent.update,
        schema: 'public',
        table: 'drivers',
        callback: (payload) => _handleRealtimeDriverRecord(payload.newRecord),
      )
      ..subscribe();
  }

  Future<void> _loadInitialDriverLocations() async {
    try {
      final response = await _client
          .from('drivers')
          .select('id, lat, lng, is_online, name, vehicle_type');

      var updated = false;
      for (final item in response) {
        final id = item['id'];
        final lat = item['lat'];
        final lng = item['lng'];
        if (id is! String || lat is! num || lng is! num) continue;

        final location = LatLng(lat.toDouble(), lng.toDouble());
        var driver = _ensureDriver(id, location);
        if (driver == null) {
          // Create a minimal tracking record so all devices can see this driver.
          final rawName = item['name'];
          final rawVehicle = item['vehicle_type'];
          driver = DriverModel(
            id: id,
            name: rawName is String && rawName.isNotEmpty ? rawName : id,
            location: location,
            vehicleType:
                rawVehicle == 'car' ? VehicleType.car : VehicleType.motorcycle,
            isOnline: item['is_online'] as bool? ?? false,
          );
          _drivers.add(driver);
        } else {
          driver.location = location;
          driver.isOnline = item['is_online'] as bool? ?? false;
        }
        updated = true;
      }

      if (updated) {
        notifyListeners();
      }
    } catch (error) {
      debugPrint('DriverStore: Failed to bootstrap driver locations => $error');
    }
  }

  void _handleRealtimeDriverRecord(Map<String, dynamic>? record) {
    if (record == null) return;

    final id = record['id'];
    final lat = record['lat'];
    final lng = record['lng'];

    if (id is! String || lat is! num || lng is! num) {
      return;
    }

    final target = LatLng(lat.toDouble(), lng.toDouble());
    var driver = _ensureDriver(id, target, notify: true);
    if (driver == null) {
      // Create a minimal tracking record for devices that didn't register
      // this driver locally (e.g. client or partner devices).
      final rawName = record['name'];
      driver = DriverModel(
        id: id,
        name: rawName is String && rawName.isNotEmpty ? rawName : id,
        location: target,
        vehicleType: VehicleType.motorcycle,
        isOnline: record['is_online'] as bool? ?? true,
      );
      _drivers.add(driver);
      notifyListeners();
      return;
    }
    final isOnlineRaw = record['is_online'] as bool?;
    if (isOnlineRaw != null) driver.isOnline = isOnlineRaw;
    _animateDriverTowards(driver, target);
  }

  // Only updates existing drivers from Supabase location data.
  // Never creates fake/placeholder drivers for unknown IDs.
  DriverModel? _ensureDriver(
    String id,
    LatLng fallbackLocation, {
    bool notify = false,
  }) {
    final existing = getDriverById(id);
    if (existing != null) {
      return existing;
    }
    // Unknown id — not a registered driver on this device; ignore.
    return null;
  }

  void _animateDriverTowards(DriverModel driver, LatLng target) {
    final current = driver.location;
    if ((current.latitude - target.latitude).abs() < 1e-6 &&
        (current.longitude - target.longitude).abs() < 1e-6) {
      return;
    }

    _locationAnimations.remove(driver.id)?.cancel();

    final distanceKm = const Distance().as(
      LengthUnit.Kilometer,
      current,
      target,
    );

    if (!distanceKm.isFinite || distanceKm < 0.01) {
      driver.location = target;
      notifyListeners();
      return;
    }

    var step = 0;
    _locationAnimations[driver.id] = Timer.periodic(
      _locationAnimationStepDuration,
      (timer) {
        step++;
        final progress = step / _locationAnimationSteps;
        final nextLat =
            current.latitude + (target.latitude - current.latitude) * progress;
        final nextLng =
            current.longitude +
                (target.longitude - current.longitude) * progress;
        driver.location = LatLng(nextLat, nextLng);
        notifyListeners();

        if (step >= _locationAnimationSteps) {
          timer.cancel();
          _locationAnimations.remove(driver.id);
          driver.location = target;
          notifyListeners();
        }
      },
    );
  }

  @override
  void dispose() {
    _trackingTimer?.cancel();
    for (final timer in _locationAnimations.values) {
      timer.cancel();
    }
    _locationAnimations.clear();
    if (_driverLocationChannel != null) {
      unawaited(_driverLocationChannel!.unsubscribe());
    }
    _driverLocationChannel = null;
    super.dispose();
  }
}
