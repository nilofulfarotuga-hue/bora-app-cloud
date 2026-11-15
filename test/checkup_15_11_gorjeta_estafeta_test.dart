// checkup-geral-15-11 (caixa 71, B3.4): a gorjeta do cliente aparece no pedido
// entregue da lista do estafeta (o extrato e os Ganhos já a mostravam).
import 'package:bora_app/models/order_model.dart';
import 'package:bora_app/screens/driver_main_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

final DateTime _agora = DateTime.utc(2026, 11, 15, 11);

OrderModel _entrega(String id, {int gorjeta = 0}) => OrderModel.fromSupabase({
      'id': id,
      'status': 'delivered',
      'service_type': 'restaurant',
      'payment_method': 'card',
      'price': 12,
      'driver_earnings': 4.5,
      'tip_amount_cents': gorjeta,
      'items': const [],
      'created_at': DateTime.utc(2026, 11, 15, 9).toIso8601String(),
      'delivered_at': DateTime.utc(2026, 11, 15, 9, 30).toIso8601String(),
    });

void main() {
  testWidgets('a gorjeta aparece só no pedido que a teve', (t) async {
    t.view.physicalSize = const Size(800, 3000);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    await t.pumpWidget(MaterialApp(
      home: PedidosEstafetaCorpo(
        emCurso: 0,
        ofertas: 0,
        historico: [_entrega('com', gorjeta: 150), _entrega('sem')],
        aoAbrirInicio: () {},
        agora: () => _agora,
      ),
    ));
    await t.pumpAndSettle();
    expect(find.textContaining('gorjeta +1,50'), findsOneWidget);
    expect(find.textContaining('gorjeta'), findsOneWidget);
  });
}
