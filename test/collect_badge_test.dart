import 'package:bora_app/widgets/payments/collect_badge.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Future<void> _pump(WidgetTester tester, Widget child) =>
    tester.pumpWidget(MaterialApp(home: Scaffold(body: child)));

void main() {
  testWidgets('collectCash mostra o valor a cobrar', (tester) async {
    await _pump(tester,
        const CollectBadge(state: CollectState.collectCash, amountCents: 750));
    expect(find.textContaining('COBRAR EM DINHEIRO'), findsOneWidget);
    expect(find.textContaining('7.50'), findsOneWidget);
  });

  testWidgets('paidOnline mostra "não cobrar" (sem valor)', (tester) async {
    await _pump(tester, const CollectBadge(state: CollectState.paidOnline));
    expect(find.textContaining('JÁ PAGO NA APP'), findsOneWidget);
    expect(find.textContaining('não cobrar'), findsOneWidget);
  });

  testWidgets('coveredByPlan mostra "coberto pelo plano"', (tester) async {
    await _pump(tester, const CollectBadge(state: CollectState.coveredByPlan));
    expect(find.textContaining('COBERTO PELO PLANO'), findsOneWidget);
  });

  test('collectCash SEM amountCents falha (assert)', () {
    expect(() => CollectBadge(state: CollectState.collectCash),
        throwsAssertionError);
  });
}
