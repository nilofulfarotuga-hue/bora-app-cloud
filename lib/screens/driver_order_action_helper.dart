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

DriverOrderAction? resolveDriverOrderAction(OrderStore store, OrderModel order) {
  switch (order.status) {
    case OrderStatus.driverAccepted:
      return DriverOrderAction(
        label: "Confirmar recolha",
        successMessage: "Encomenda recolhida",
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
