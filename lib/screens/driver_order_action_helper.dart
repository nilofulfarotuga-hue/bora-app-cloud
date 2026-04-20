import 'dart:async';

import '../models/order_model.dart';
import '../stores/order_store.dart';

class DriverOrderAction {
  const DriverOrderAction({
    required this.label,
    required this.successMessage,
    required this.execute,
  });

  final String label;
  final String successMessage;
  final Future<bool> Function() execute;
}

DriverOrderAction? resolveDriverOrderAction(
    OrderStore store, OrderModel order) {
  switch (order.status) {
    case OrderStatus.driverAccepted:
      // For non-partner store/restaurant pickups the driver must first
      // finalize the purchase (enter the real amount paid) before confirming
      // pickup. Hide the button until isPurchaseFinalized == true — the
      // _FinalizePurchaseButton is shown in its place during driverAccepted.
      final needsPurchaseFinalize = !order.isPartnerStore &&
          (order.serviceType == OrderServiceType.storeShopping ||
              order.serviceType == OrderServiceType.restaurant);
      if (needsPurchaseFinalize && !order.isPurchaseFinalized) {
        return null;
      }
      return DriverOrderAction(
        label: "Recolher pedido",
        successMessage: "Pedido recolhido",
        execute: () => store.pickUpOrder(order),
      );
    case OrderStatus.pickedUp:
      return DriverOrderAction(
        label: "Iniciar entrega",
        successMessage: "Entrega iniciada",
        execute: () => store.startDelivery(order),
      );
    case OrderStatus.onTheWay:
      return DriverOrderAction(
        label: "Concluir entrega",
        successMessage: "Pedido entregue",
        execute: () => store.finishOrder(order),
      );
    default:
      return null;
  }
}
