import 'dart:async';

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../dispatch/driver_capacity_service.dart';
import '../models/driver_model.dart';
import '../models/order_model.dart';
import '../utils/constants.dart';

class DriverStore extends ChangeNotifier {
  String _primaryDriverId = 'driver-main';
  static const int _locationAnimationSteps = 12;
  static const Duration _locationAnimationStepDuration =
      Duration(milliseconds: 80);

  DriverStore({DriverCapacityService? capacityService})
      : _capacityService = capacityService ?? DriverCapacityService() {
    _initialiseRealtimeDriverTracking();
    _listenAuthChanges();
  }

  final DriverCapacityService _capacityService;
  final List<DriverModel> _drivers = [];
  final SupabaseClient _client = Supabase.instance.client;

  // _trackingTimer / _trackedOrderId are kept for API compatibility with
  // OrderStore callers (startTracking / stopTracking / updateTrackingTarget),
  // but _tickTracking no longer simulates movement — real GPS from
  // DriverHomeScreen._startIdleLocationTracking and
  // DriverMapScreen._listenToDriverLocation owns the driver position.
  Timer? _trackingTimer;
  String? _trackedOrderId;
  RealtimeChannel? _driverLocationChannel;
  final Map<String, Timer> _locationAnimations = <String, Timer>{};
  StreamSubscription<AuthState>? _authSubscription;
  StreamSubscription<String>? _fcmTokenRefreshSubscription;

  DriverModel? get currentDriver => getDriverById(_primaryDriverId);

  VehicleType get currentVehicleType =>
      currentDriver?.vehicleType ?? VehicleType.motorcycle;

  String get currentDriverId => _primaryDriverId;

  List<DriverModel> get drivers => List.unmodifiable(_drivers);

  List<DriverModel> get onlineDrivers =>
      _drivers.where((driver) => driver.isOnline).toList(growable: false);

  DriverCapacityService get capacityService => _capacityService;

  // ── Token balance ──────────────────────────────────────────────────────────
  int _tokenBalance = 0;
  int get tokenBalance => _tokenBalance;

  Future<int> fetchTokenBalance() async {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) return 0;
    try {
      final response = await _client.rpc(
        'get_user_tokens',
        params: {'p_user_id': userId},
      );
      return (response as num?)?.toInt() ?? 0;
    } catch (e) {
      debugPrint('[DriverStore] fetchTokenBalance error: $e');
      return 0;
    }
  }

  Future<void> loadTokenBalance() async {
    _tokenBalance = await fetchTokenBalance();
    notifyListeners();
  }

  Future<void> _saveFcmToken() async {
    final driverId = _primaryDriverId;
    if (driverId.isEmpty || driverId == 'driver-main') return;
    try {
      final messaging = FirebaseMessaging.instance;
      final settings = await messaging.requestPermission();
      if (settings.authorizationStatus == AuthorizationStatus.denied) return;

      final token = await messaging.getToken();
      if (token != null) {
        await _client
            .from('drivers')
            .update({'fcm_token': token}).eq('id', driverId);
        debugPrint('[DriverStore] FCM token saved for driver=$driverId');
      }

      _fcmTokenRefreshSubscription?.cancel();
      _fcmTokenRefreshSubscription =
          messaging.onTokenRefresh.listen((newToken) async {
        await _client
            .from('drivers')
            .update({'fcm_token': newToken}).eq('id', _primaryDriverId);
        debugPrint(
            '[DriverStore] FCM token refreshed for driver=$_primaryDriverId');
      });
    } catch (e) {
      debugPrint('[DriverStore] _saveFcmToken error: $e');
    }
  }

  void _listenAuthChanges() {
    _authSubscription = _client.auth.onAuthStateChange.listen((authState) {
      final user = authState.session?.user;

      if (user == null) {
        // Logout — clear all driver state so the next login starts clean.
        // Without this, the previous driver's data leaks into the next session.
        _drivers.clear();
        _primaryDriverId = 'driver-main';
        notifyListeners();
        debugPrint('DriverStore: session ended — driver state cleared.');
        _restartLocationChannel();
        return;
      }

      final meta = user.userMetadata ?? {};
      final role = meta['bora_role'] as String?;
      if (role != 'driver') return;
      syncDriverWithAuth(user.id);
    });
  }

  Future<void> syncDriverWithAuth(String uid) async {
    if (uid.isEmpty) return;
    if (_primaryDriverId == uid && getDriverById(uid) != null) return;

    final oldId = _primaryDriverId;
    if (oldId != uid) {
      // Remove the old placeholder or previous driver slot.
      _drivers.removeWhere((d) => d.id == oldId);
      _primaryDriverId = uid;
    }

    final existing = getDriverById(uid);
    if (existing != null) {
      notifyListeners();
      return;
    }

    try {
      final rows =
          await _client.from('drivers').select().eq('id', uid).limit(1);

      if (rows.isNotEmpty) {
        final row = rows.first;
        final lat = row['lat'] as num?;
        final lng = row['lng'] as num?;
        final rawVehicle = row['vehicle_type'] as String?;

        final driver = DriverModel(
          id: uid,
          name: row['name'] as String? ?? uid,
          location: (lat != null && lng != null)
              ? LatLng(lat.toDouble(), lng.toDouble())
              : const LatLng(40.5321, -7.2671),
          vehicleType: VehicleType.values.firstWhere(
              (v) => v.name == (rawVehicle ?? ''),
              orElse: () => VehicleType.motorcycle),
          phone: row['phone'] as String? ?? '',
          isOnline: row['is_online'] as bool? ?? false,
          avgRating: (row['avg_rating'] as num?)?.toDouble(),
          ratingsCount: (row['ratings_count'] as num?)?.toInt() ?? 0,
        );
        _drivers.add(driver);
        debugPrint(
            '[DriverStore] syncDriverWithAuth: loaded "$uid" from DB (is_online=${driver.isOnline})');
      } else {
        // No drivers row exists — this happens when the drivers table was reset
        // but auth.users was not (common in dev), OR registration created the
        // auth user but failed to insert the drivers row.
        // UPSERT so the dispatch engine can find this driver immediately.
        debugPrint(
            '[DriverStore] syncDriverWithAuth: no row for "$uid" — upserting drivers row');
        _drivers.add(DriverModel(
          id: uid,
          name: uid,
          location: kGuardaCenter,
          vehicleType: VehicleType.motorcycle,
          isOnline: false,
        ));
        unawaited(_upsertDriverRow(uid));
      }
    } catch (e) {
      debugPrint('DriverStore.syncDriverWithAuth: error => $e');
    }

    notifyListeners();
    // Load token balance in background after driver row is ready.
    unawaited(loadTokenBalance());
    // Save FCM token now that _primaryDriverId is a valid auth UID.
    unawaited(_saveFcmToken());
  }

  void configurePrimaryDriver({
    required String name,
    required String phone,
    required VehicleType vehicleType,
    String? licensePlate,
    String? driverId,
  }) {
    // Priority: explicit driverId > auth UID > phone-derived (demo/test only).
    // Never use a phone-derived ID when a real auth session exists — it would
    // mismatch the 'drivers' table PK and cause all DB operations to fail silently.
    final authUid = _client.auth.currentUser?.id;
    final resolvedId = (driverId != null && driverId.isNotEmpty)
        ? driverId
        : (authUid != null && authUid.isNotEmpty)
            ? authUid
            : 'driver-${phone.replaceAll(RegExp(r'[^0-9a-zA-Z]'), '')}';

    if (_primaryDriverId != resolvedId) {
      _drivers.removeWhere((d) => d.id == _primaryDriverId);
      _primaryDriverId = resolvedId;
    }

    var driver = getDriverById(_primaryDriverId);
    if (driver == null) {
      driver = DriverModel(
        id: _primaryDriverId,
        name: name,
        location: kGuardaCenter,
        vehicleType: vehicleType,
        phone: phone,
        isOnline: false,
      );
      _drivers.add(driver);
      debugPrint(
          '[DriverStore] configurePrimaryDriver: new driver id=$_primaryDriverId — upserting DB row');
      unawaited(_upsertDriverRow(_primaryDriverId));
    } else {
      driver
        ..name = name
        ..phone = phone
        ..vehicleType = vehicleType
        ..licensePlate = licensePlate;
    }
    notifyListeners();

    // Trigger a full DB sync to pick up persisted fields (location, vehicle, etc.).
    syncDriverWithAuth(_primaryDriverId);
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
    if (!value && driver.activeAssignments.isNotEmpty) return false;
    if (driver.isOnline == value) return true;
    driver.isOnline = value;
    notifyListeners();
    unawaited(updateDriverOnlineStatus(driverId, value));
    return true;
  }

  /// INSERT a drivers row for [uid] only if one does not already exist.
  /// Uses INSERT ... ON CONFLICT DO NOTHING so an existing row — including
  /// its current is_online value — is never overwritten.  Calling this with
  /// unawaited is safe because a conflict is silently ignored.
  Future<void> _upsertDriverRow(String uid) async {
    if (uid.isEmpty || uid == 'driver-main') return;
    final existing = getDriverById(uid);
    try {
      await _client.from('drivers').upsert(
        {
          'id': uid,
          'name': existing?.name ?? '',
          'phone': existing?.phone ?? '',
          'email': '',
          'vehicle_type': existing?.vehicleType.name ?? 'motorcycle',
          'license_plate': '',
          'is_online': false,
          'lat': kGuardaLat,
          'lng': kGuardaLng,
          'user_id': uid,
        },
        onConflict: 'id',
        ignoreDuplicates:
            true, // ON CONFLICT DO NOTHING — never overwrite is_online
      );
      debugPrint('[DriverStore] _upsertDriverRow: OK uid=$uid');
    } catch (e) {
      debugPrint('[DriverStore] _upsertDriverRow: error uid=$uid => $e');
    }
  }

  Future<void> updateDriverOnlineStatus(String driverId, bool isOnline) async {
    try {
      await _client
          .from('drivers')
          .update({'is_online': isOnline}).eq('id', driverId);

      // Trigger dispatch imediato para pedidos pendentes sem driver
      if (isOnline) {
        try {
          final pendingOrders = await _client
              .from('orders')
              .select('id')
              .eq('status', 'callingDriver')
              .isFilter('assigned_driver_id', null)
              .isFilter('current_driver_offer_id', null);
          for (final order in List<Map<String, dynamic>>.from(pendingOrders)) {
            await _client.functions.invoke(
              'dispatch-engine',
              body: {'orderId': order['id'] as String},
            );
          }
        } catch (e) {
          debugPrint('[DriverStore] dispatch trigger on online error: $e');
        }
      }
    } catch (e) {
      debugPrint('DriverStore: updateDriverOnlineStatus error => $e');
    }
  }

  bool registerOrderForDriver(String driverId, OrderModel order) {
    final driver = getDriverById(driverId);
    if (driver == null) return false;
    if (!driver.supportsService(order.serviceType,
        requiresCar: order.requiresCar)) {
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
    if (removed) notifyListeners();
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
    if (!driver.supportsService(order.serviceType,
        requiresCar: order.requiresCar)) {
      return false;
    }
    return _capacityService.canAssignOrder(driver, order);
  }

  // BUG 4 — throttle para orders.driver_lat/lng (max 1 update / 5s).
  DateTime? _lastOrderLocationDbUpdate;

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

    // BUG 4 — também actualiza orders.driver_lat/lng quando há pedido activo
    // em fase em que cliente vê estafeta no mapa. Throttle 5s.
    final trackedId = _trackedOrderId;
    if (trackedId == null || trackedId.isEmpty) return;
    final now = DateTime.now();
    if (_lastOrderLocationDbUpdate != null &&
        now.difference(_lastOrderLocationDbUpdate!).inSeconds < 5) {
      return;
    }
    _lastOrderLocationDbUpdate = now;
    unawaited(
      _client
          .from('orders')
          .update({
            'driver_lat': location.latitude,
            'driver_lng': location.longitude,
          })
          .eq('id', trackedId)
          .inFilter('status',
              ['driverAccepted', 'pickedUp', 'onTheWay']).catchError((e) {
        debugPrint('[DriverStore] orders.driver_lat update err: $e');
        return <Map<String, dynamic>>[];
      }),
    );
  }

  /// Marks this order as the currently tracked one and starts the periodic
  /// timer. The timer NO LONGER simulates movement — real GPS handles position.
  /// It only exists to detect when the order reaches `delivered` and stop.
  void startTracking(OrderModel order) {
    if (order.destination == null && order.pickupLocation == null) return;
    _trackedOrderId = order.id;
    _trackingTimer?.cancel();
    _trackingTimer = Timer.periodic(const Duration(seconds: 2), (_) {
      _tickTracking(order);
    });
  }

  void updateTrackingTarget(OrderModel order) {
    if (_trackedOrderId != order.id) return;
    if (order.status == OrderStatus.delivered) {
      stopTracking(order.id);
    }
  }

  void stopTracking(String orderId) {
    if (_trackedOrderId != orderId) return;
    _trackedOrderId = null;
    _trackingTimer?.cancel();
    _trackingTimer = null;
  }

  /// FIX: No longer simulates movement. Real GPS position comes from
  /// DriverHomeScreen._startIdleLocationTracking (idle) and
  /// DriverMapScreen._listenToDriverLocation (active delivery).
  /// This method only stops tracking once the order is delivered.
  void _tickTracking(OrderModel order) {
    if (_trackedOrderId != order.id) return;
    // Stop tracking when order is done — no position simulation.
    final target = _resolveTrackingTarget(order);
    if (target == null) {
      stopTracking(order.id);
    }
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

  void _restartLocationChannel() {
    _driverLocationChannel?.unsubscribe();
    _driverLocationChannel = null;
    _initialiseRealtimeDriverTracking();
    debugPrint('[DriverStore] location channel restarted');
  }

  void _initialiseRealtimeDriverTracking() {
    Future.microtask(_loadInitialDriverLocations);

    _driverLocationChannel = _client.channel('drivers_channel')
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
          .select('id, lat, lng, is_online, name, vehicle_type, phone');

      var updated = false;
      for (final item in response) {
        final id = item['id'];
        final lat = item['lat'];
        final lng = item['lng'];
        if (id is! String || lat is! num || lng is! num) continue;

        final location = LatLng(lat.toDouble(), lng.toDouble());
        var driver = getDriverById(id);
        if (driver == null) {
          final rawName = item['name'];
          final rawVehicle = item['vehicle_type'];
          driver = DriverModel(
            id: id,
            name: rawName is String && rawName.isNotEmpty ? rawName : id,
            location: location,
            vehicleType: VehicleType.values.firstWhere(
                (v) => v.name == (rawVehicle ?? ''),
                orElse: () => VehicleType.motorcycle),
            phone: item['phone'] as String? ?? '',
            isOnline: item['is_online'] as bool? ?? false,
          );
          _drivers.add(driver);
        } else {
          driver.location = location;
          driver.isOnline = item['is_online'] as bool? ?? false;
        }
        updated = true;
      }

      final authUser = _client.auth.currentUser;
      if (authUser != null) {
        final meta = authUser.userMetadata ?? {};
        if (meta['bora_role'] == 'driver') {
          final uid = authUser.id;
          // Only auto-sync when _primaryDriverId is still the initial
          // placeholder. If it was already updated by _listenAuthChanges or
          // configurePrimaryDriver, leave it alone — overwriting it here
          // would re-introduce the multi-login data leak.
          if (_primaryDriverId == 'driver-main' && getDriverById(uid) != null) {
            _drivers.removeWhere((d) => d.id == 'driver-main');
            _primaryDriverId = uid;
            updated = true;
            debugPrint(
                'DriverStore: auto-synced primaryDriverId to auth uid "$uid"');
          }
        }
      }

      if (updated) notifyListeners();
    } catch (error) {
      debugPrint('DriverStore: Failed to bootstrap driver locations => $error');
    }
  }

  void _handleRealtimeDriverRecord(Map<String, dynamic>? record) {
    if (record == null) return;
    final id = record['id'];
    final lat = record['lat'];
    final lng = record['lng'];
    if (id is! String || lat is! num || lng is! num) return;

    final target = LatLng(lat.toDouble(), lng.toDouble());
    var driver = getDriverById(id);
    if (driver == null) {
      final rawName = record['name'];
      driver = DriverModel(
        id: id,
        name: rawName is String && rawName.isNotEmpty ? rawName : id,
        location: target,
        vehicleType: VehicleType.motorcycle,
        isOnline: record['is_online'] as bool? ?? false,
      );
      _drivers.add(driver);
      notifyListeners();
      return;
    }
    final isOnlineRaw = record['is_online'] as bool?;
    if (isOnlineRaw != null) driver.isOnline = isOnlineRaw;
    _animateDriverTowards(driver, target);
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
        final nextLng = current.longitude +
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
    _authSubscription?.cancel();
    _fcmTokenRefreshSubscription?.cancel();
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
