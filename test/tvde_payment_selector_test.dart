import 'package:bora_app/widgets/tvde/tvde_payment_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Future<void> _pump(
  WidgetTester tester, {
  required bool cardEnabled,
  String current = 'cash',
  ValueChanged<String>? onChanged,
  TextEditingController? phoneController,
  String? phoneError,
}) async {
  await tester.pumpWidget(MaterialApp(
    home: Scaffold(
      body: TvdePaymentSelector(
        current: current,
        cardEnabled: cardEnabled,
        onChanged: onChanged ?? (_) {},
        phoneController: phoneController,
        phoneError: phoneError,
      ),
    ),
  ));
}

final _phoneField = find.byKey(const Key('tvde_pay_mbway_phone'));

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

  // ── Campo do número MB Way ────────────────────────────────────────────────
  // Regressão do bug que impedia QUALQUER pagamento MB Way no TVDE: sem este
  // campo o `phone` chegava vazio à Edge Function, o E.164 ficava "+351" e a
  // Stripe recusava o PaymentIntent.

  testWidgets('MB Way escolhido → mostra o campo do número', (tester) async {
    await _pump(tester,
        cardEnabled: true,
        current: 'mbway',
        phoneController: TextEditingController());
    expect(_phoneField, findsOneWidget);
    expect(find.text('Número MBWay'), findsOneWidget);
  });

  testWidgets('Dinheiro escolhido → sem campo de número', (tester) async {
    await _pump(tester,
        cardEnabled: true,
        current: 'cash',
        phoneController: TextEditingController());
    expect(_phoneField, findsNothing);
  });

  testWidgets('Cartão escolhido → sem campo de número', (tester) async {
    await _pump(tester,
        cardEnabled: true,
        current: 'card',
        phoneController: TextEditingController());
    expect(_phoneField, findsNothing);
  });

  testWidgets('kill switch OFF ganha ao método → sem campo de número',
      (tester) async {
    await _pump(tester,
        cardEnabled: false,
        current: 'mbway',
        phoneController: TextEditingController());
    expect(_phoneField, findsNothing);
  });

  testWidgets('o número escrito fica no controller do pai', (tester) async {
    final ctrl = TextEditingController();
    await _pump(tester,
        cardEnabled: true, current: 'mbway', phoneController: ctrl);
    await tester.enterText(_phoneField, '931992662');
    expect(ctrl.text, '931992662');
  });

  testWidgets('erro de validação aparece no campo', (tester) async {
    await _pump(tester,
        cardEnabled: true,
        current: 'mbway',
        phoneController: TextEditingController(),
        phoneError: 'Número MBWay inválido (9 dígitos).');
    expect(find.text('Número MBWay inválido (9 dígitos).'), findsOneWidget);
  });
}
