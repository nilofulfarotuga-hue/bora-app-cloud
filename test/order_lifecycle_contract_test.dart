import 'package:bora_app/models/order_model.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('order lifecycle keeps the canonical database status names', () {
    expect(
      [
        OrderStatus.created,
        OrderStatus.preparing,
        OrderStatus.callingDriver,
        OrderStatus.driverAccepted,
        OrderStatus.pickedUp,
        OrderStatus.onTheWay,
        OrderStatus.delivered,
      ].map((status) => status.name),
      [
        'created',
        'preparing',
        'callingDriver',
        'driverAccepted',
        'pickedUp',
        'onTheWay',
        'delivered',
      ],
    );
  });

  test('client and server delivery PIN formula stays compatible', () {
    final order = OrderModel(
      total: 10,
      id: '11111111-2222-4333-8444-555555555555',
      serviceType: OrderServiceType.restaurant,
      status: OrderStatus.onTheWay,
      orderType: OrderType.partnerRestaurant,
      paymentMethod: PaymentMethod.mbway,
      isPartnerStore: true,
    );

    expect(order.deliveryCode, '5369');
  });
}
