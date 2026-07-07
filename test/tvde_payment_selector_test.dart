import 'package:bora_app/widgets/tvde/tvde_payment_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Future<void> _pump(
  WidgetTester tester, {
  required bool cardEnabled,
  String current = 'cash',
  ValueChanged<String>? onChanged,
}) async {
  await tester.pumpWidget(MaterialApp(
    home: Scaffold(
      body: TvdePaymentSelector(
        current: current,
        cardEnabled: cardEnabled,
        onChanged: onChanged ?? (_) {},
      ),
    ),
  ));
}

void main() {
  testWidgets('switch OFF → só Dinheiro (card/mbway escondidos)',
      (tester) async {
    await _pump(tester, cardEnabled: false);
    expect(find.byKey(const Key('tvde_pay_cash')), findsOneWidget);
    expect(find.byKey(const Key('tvde_pay_card')), findsNothing);
    expect(find.byKey(const Key('tvde_pay_mbway')), findsNothing);
    expect(find.text('Dinheiro'), findsOneWidget);
  });

  testWidgets('switch ON → Dinheiro + Cartão + MB Way', (tester) async {
    await _pump(tester, cardEnabled: true);
    expect(find.byKey(const Key('tvde_pay_cash')), findsOneWidget);
    expect(find.byKey(const Key('tvde_pay_card')), findsOneWidget);
    expect(find.byKey(const Key('tvde_pay_mbway')), findsOneWidget);
  });

  testWidgets('tocar num método chama onChanged com o valor certo',
      (tester) async {
    String? picked;
    await _pump(tester, cardEnabled: true, onChanged: (m) => picked = m);
    await tester.tap(find.byKey(const Key('tvde_pay_mbway')));
    await tester.pump();
    expect(picked, 'mbway');
  });
}
