// Dívida anterior no ecrã do cliente (13/10/2026). O cliente com dívida de
// cancelamento que paga em dinheiro via só o total do pedido (24,03 €) e o
// estafeta via "RECEBER 26,53 €" com "inclui 2,50 € de dívida anterior".
// Cada teste falha no código de antes: não havia total com a dívida para o
// cliente, e o resumo do pedido mostrava 24,03 €.
import 'package:bora_app/models/order_model.dart';
import 'package:bora_app/screens/order_details_screen.dart';
import 'package:bora_app/stores/driver_store.dart';
import 'package:bora_app/stores/order_store.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

OrderModel pedido({
  PaymentMethod pagamento = PaymentMethod.cash,
  double total = 24.03,
  double? finalTotal,
  int divida = 250,
}) {
  return OrderModel(
    id: '6a1b2c3d-0000-4000-8000-000000000001',
    total: total,
    finalTotal: finalTotal,
    serviceType: OrderServiceType.restaurant,
    status: OrderStatus.preparing,
    paymentMethod: pagamento,
    debtCollectedCents: divida,
    vendorName: 'Loja de prova',
  );
}

void main() {
  setUpAll(() async {
    // Fora do relógio falso do testWidgets: o arranque do Supabase cria um
    // temporizador periódico que, dentro dele, ficava pendurado no fim.
    SharedPreferences.setMockInitialValues({});
    await Supabase.initialize(
      url: 'http://127.0.0.1:9',
      anonKey: 'chave-de-prova',
      authOptions: const FlutterAuthClientOptions(autoRefreshToken: false),
    );
  });

  group('totalWithDebt', () {
    test('dinheiro: é o mesmo número que o estafeta cobra', () {
      final o = pedido();
      expect(o.totalWithDebt, closeTo(26.53, 0.001));
      expect(o.totalWithDebt, o.totalToCollectCash);
    });

    test('cartão/MB Way: total do pedido + dívida', () {
      expect(pedido(pagamento: PaymentMethod.card).totalWithDebt,
          closeTo(26.53, 0.001));
      expect(
          pedido(pagamento: PaymentMethod.mbway, finalTotal: 25.00)
              .totalWithDebt,
          closeTo(27.50, 0.001));
    });

    test('sem dívida não soma nada', () {
      expect(pedido(pagamento: PaymentMethod.card, divida: 0).totalWithDebt,
          closeTo(24.03, 0.001));
    });
  });

  testWidgets('resumo do pedido mostra a dívida e o total com ela',
      (t) async {
    final driverStore = _DriverStoreFalso();
    final orderStore = _OrderStoreFalso();
    t.view.physicalSize = const Size(1080, 4000);
    t.view.devicePixelRatio = 2.0;
    addTearDown(t.view.reset);

    await t.pumpWidget(MultiProvider(
      providers: [
        ChangeNotifierProvider<DriverStore>.value(value: driverStore),
        ChangeNotifierProvider<OrderStore>.value(value: orderStore),
      ],
      child: MaterialApp(home: OrderDetailsScreen(order: pedido())),
    ));
    await t.pump(const Duration(milliseconds: 200));

    expect(find.text('Dívida anterior'), findsOneWidget);
    expect(find.text('€2.50'), findsOneWidget);
    expect(find.text('€26.53'), findsOneWidget);
    expect(find.text('€24.03'), findsNothing);
  });
}

/// Stores falsos: o ecrã só lê `orders` (pedido ao vivo) e, com estafeta,
/// `getDriverById`. Os reais ligam-se ao servidor e religam em ciclo.
class _OrderStoreFalso extends ChangeNotifier implements OrderStore {
  @override
  List<OrderModel> get orders => const [];

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

class _DriverStoreFalso extends ChangeNotifier implements DriverStore {
  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}
