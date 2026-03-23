import 'dart:async';

import '../models/driver_model.dart';
import '../models/order_model.dart';
import '../stores/driver_store.dart';
import '../stores/order_store.dart';
import 'driver_assignment_service.dart';
import 'driver_capacity_service.dart';

class DispatchEngine {
  DispatchEngine({
    DriverCapacityService? capacityService,
    Duration offerTimeout = const Duration(seconds: 10),
  })  : _capacityService = capacityService ?? DriverCapacityService(),
        _offerTimeout = offerTimeout;

  OrderStore? _orderStore;
  DriverStore? _driverStore;
  DriverAssignmentService? _assignmentService;
  DriverCapacityService _capacityService;
  final Duration _offerTimeout;
  final Map<String, Timer> _offerTimers = {};

  void attach({required OrderStore orderStore, required DriverStore driverStore}) {
    if (_orderStore == orderStore && _driverStore == driverStore) {
      return;
    }

    _orderStore?.removeListener(_handleOrderUpdates);
    _driverStore?.removeListener(_handleDriverUpdates);
    _cancelAllTimers();

    _orderStore = orderStore;
    _driverStore = driverStore;
    _capacityService = driverStore.capacityService;
    _assignmentService = DriverAssignmentService(
      driverStore: driverStore,
      capacityService: _capacityService,
    );

    _orderStore?.addListener(_handleOrderUpdates);
    _driverStore?.addListener(_handleDriverUpdates);

    _handleOrderUpdates();
  }

  void dispose() {
    _orderStore?.removeListener(_handleOrderUpdates);
    _driverStore?.removeListener(_handleDriverUpdates);
    _cancelAllTimers();
    _orderStore = null;
    _driverStore = null;
    _assignmentService = null;
  }

  void notifyOrderAccepted(OrderModel order) {
    _cancelTimer(order.id);
    order.currentDriverOfferId = null;
    _orderStore?.refresh();
  }

  void notifyOrderPickedUp(OrderModel order) {
    _cancelTimer(order.id);
    order.currentDriverOfferId = null;
    _orderStore?.refresh();
  }

  void notifyOrderReleased(OrderModel order) {
    _cancelTimer(order.id);
    order.currentDriverOfferId = null;
    _orderStore?.refresh();
  }

  void _handleOrderUpdates() {
    final orderStore = _orderStore;
    final driverStore = _driverStore;
    final assignmentService = _assignmentService;
    if (orderStore == null || driverStore == null || assignmentService == null) {
      return;
    }

    for (final order in orderStore.orders) {
      if (order.status != OrderStatus.callingDriver ||
          order.assignedDriverId != null) {
        _cancelTimer(order.id);
        continue;
      }

      final currentOfferId = order.currentDriverOfferId;
      if (currentOfferId != null) {
        final driver = driverStore.getDriverById(currentOfferId);
        final stillEligible = driver != null &&
            assignmentService.isDriverEligible(
              driver,
              order,
              ignoreHistory: true,
            );
        if (stillEligible) {
          continue;
        }

        if (currentOfferId.isNotEmpty &&
            !order.driverOfferHistory.contains(currentOfferId)) {
          order.driverOfferHistory.add(currentOfferId);
        }
        order.currentDriverOfferId = null;
        orderStore.refresh();
      }

      if (order.currentDriverOfferId == null) {
        _dispatchToNextDriver(order);
      }
    }
  }

  void _handleDriverUpdates() {
    _handleOrderUpdates();
  }

  void _dispatchToNextDriver(OrderModel order) {
    final orderStore = _orderStore;
    final assignmentService = _assignmentService;
    if (orderStore == null || assignmentService == null) {
      return;
    }

    final candidates = assignmentService.findEligibleDrivers(order);
    if (candidates.isEmpty) {
      _cancelTimer(order.id);
      if (order.currentDriverOfferId != null) {
        order.currentDriverOfferId = null;
        orderStore.refresh();
      }
      return;
    }

    _offerToCandidate(order, candidates, 0);
  }

  void _offerToCandidate(
    OrderModel order,
    List<DriverModel> candidates,
    int index,
  ) {
    final orderStore = _orderStore;
    if (orderStore == null) return;

    if (index >= candidates.length) {
      order.currentDriverOfferId = null;
      unawaited(orderStore.persistDriverOffer(order.id, null));
      orderStore.refresh();
      return;
    }

    final driver = candidates[index];
    order.currentDriverOfferId = driver.id;
    unawaited(orderStore.persistDriverOffer(order.id, driver.id));
    orderStore.refresh();

    _cancelTimer(order.id);

    _offerTimers[order.id] = Timer(_offerTimeout, () {
      final currentOrderStore = _orderStore;
      if (currentOrderStore == null) return;

      final stillWaiting = order.status == OrderStatus.callingDriver &&
          order.assignedDriverId == null &&
          order.currentDriverOfferId == driver.id;

      if (!stillWaiting) {
        return;
      }

      if (!order.driverOfferHistory.contains(driver.id)) {
        order.driverOfferHistory.add(driver.id);
      }

      order.currentDriverOfferId = null;
      unawaited(currentOrderStore.persistDriverOffer(order.id, null));
      currentOrderStore.refresh();
      _dispatchToNextDriver(order);
    });
  }

  void _cancelTimer(String orderId) {
    _offerTimers.remove(orderId)?.cancel();
  }

  void _cancelAllTimers() {
    for (final timer in _offerTimers.values) {
      timer.cancel();
    }
    _offerTimers.clear();
  }
}
