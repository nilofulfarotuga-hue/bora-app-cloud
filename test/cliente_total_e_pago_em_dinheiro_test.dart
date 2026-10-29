// 28/10/2026 (missao-geral, Bloco 1, C3/C7): o cliente que paga a dinheiro
// com parte em saldo/tokens vê o TOTAL do pedido (14,35 €) e, à parte,
// quanto paga em dinheiro à porta (3,31 €). Falha no código de antes: o
// "Total" já vinha descontado (3,31 €) e não havia linha a dizer porquê.
import 'package:bora_app/models/order_model.dart';
import 'package:bora_app/screens/order_details_screen.dart';
import 'package:bora_app/stores/driver_store.dart';
import 'package:bora_app/stores/order_store.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

OrderModel _pedido({int divida = 0, int saldo = 1031, int tokens = 73}) {
  return OrderModel(
    id: '6a1b2c3d-0000-4000-8000-0000000000c3',
    total: 14.35,
    serviceType: OrderServiceType.storeShopping,
    status: OrderStatus.preparing,
    paymentMethod: PaymentMethod.cash,
    walletAppliedCents: saldo,
    tokensAppliedValueCents: tokens,
    debtCollectedCents: divida,
    vendorName: 'Loja de prova',
  );
}

Future<void> _abrir(WidgetTester t, OrderModel o) async {
  t.view.physicalSize = const Size(1080, 4000);
  t.view.devicePixelRatio = 2.0;
  addTearDown(t.view.reset);
  await t.pumpWidget(MultiProvider(
    providers: [
      ChangeNotifierProvider<DriverStore>.value(value: _DriverStoreFalso()),
      ChangeNotifierProvider<OrderStore>.value(value: _OrderStoreFalso()),
    ],
    child: MaterialApp(home: OrderDetailsScreen(order: o)),
  ));
  await t.pump(const Duration(milliseconds: 200));
}

void main() {
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await Supabase.initialize(
      url: 'http://127.0.0.1:9',
      publishableKey: 'chave-de-prova',
      authOptions: const FlutterAuthClientOptions(autoRefreshToken: false),
    );
  });

  testWidgets('Total 14,35 € e, à parte, Paga em dinheiro 3,31 €', (t) async {
    await _abrir(t, _pedido());
    expect(find.text('Total'), findsOneWidget);
    expect(find.text('14,35 €'), findsOneWidget);
    expect(find.text('Paga em dinheiro'), findsOneWidget);
    expect(find.text('3,31 €'), findsOneWidget);
    expect(find.text('Já pago com saldo/tokens'), findsOneWidget);
    expect(find.text('11,04 €'), findsOneWidget);
  });

  testWidgets('com dívida anterior: Total 16,85 € e Paga em dinheiro 5,81 €',
      (t) async {
    await _abrir(t, _pedido(divida: 250));
    expect(find.text('Dívida anterior'), findsOneWidget);
    expect(find.text('16,85 €'), findsOneWidget);
    expect(find.text('5,81 €'), findsOneWidget);
  });

  testWidgets('sem saldo/tokens: só o Total, sem a linha do dinheiro',
      (t) async {
    await _abrir(t, _pedido(saldo: 0, tokens: 0));
    expect(find.text('14,35 €'), findsOneWidget);
    expect(find.text('Paga em dinheiro'), findsNothing);
  });
}

/// Stores falsos (o mesmo padrão de divida_anterior_cliente_test.dart).
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
