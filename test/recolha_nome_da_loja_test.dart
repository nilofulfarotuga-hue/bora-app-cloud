// Missão geral 28/10/2026, Bloco B — no pedido único o estafeta via só as
// moradas; agora vê como no _StopRow (e na Glovo/Uber Eats): "Recolha" + nome
// da loja a negrito + morada; "Entrega" + nome do cliente + morada.
// Nomes e moradas inventados.
import 'package:bora_app/models/order_model.dart';
import 'package:bora_app/screens/driver_map_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

OrderModel _pedido({String? loja, String? cliente}) => OrderModel(
      id: 'teste-recolha-28-10',
      total: 14.20,
      serviceType: OrderServiceType.storeShopping,
      status: OrderStatus.driverAccepted,
      paymentMethod: PaymentMethod.cash,
      vendorName: loja,
      customerName: cliente,
      pickupAddress: 'Rua das Flores 10, Guarda',
      dropoffAddress: 'Avenida do Teste 22, Guarda',
    );

Widget _app(OrderModel o) => MaterialApp(
      home: Scaffold(body: SingleOrderAddresses(order: o)),
    );

void main() {
  testWidgets('pedido único: nome da loja a negrito + morada da recolha',
      (tester) async {
    await tester.pumpWidget(
        _app(_pedido(loja: 'Mercearia Exemplo', cliente: 'Joana  Inventada')));
    await tester.pump();

    expect(find.text('Recolha'), findsOneWidget);
    expect(find.text('Mercearia Exemplo'), findsOneWidget);
    expect(find.text('Rua das Flores 10, Guarda'), findsOneWidget);
    final nomeLoja = tester.widget<Text>(find.text('Mercearia Exemplo'));
    expect(nomeLoja.style?.fontWeight, FontWeight.w700);

    expect(find.text('Entrega'), findsOneWidget);
    expect(find.text('Joana Inventada'), findsOneWidget);
    expect(find.text('Avenida do Teste 22, Guarda'), findsOneWidget);
    // Sem o prefixo antigo duplicado ("Entrega: <morada>").
    expect(find.text('Entrega: Avenida do Teste 22, Guarda'), findsNothing);
  });

  testWidgets('sem nome de loja nem de cliente: ficam as moradas',
      (tester) async {
    await tester.pumpWidget(_app(_pedido()));
    await tester.pump();

    expect(find.text('Recolha'), findsOneWidget);
    expect(find.text('Rua das Flores 10, Guarda'), findsOneWidget);
    expect(find.text('Entrega'), findsOneWidget);
    expect(find.text('Avenida do Teste 22, Guarda'), findsOneWidget);
  });
}
