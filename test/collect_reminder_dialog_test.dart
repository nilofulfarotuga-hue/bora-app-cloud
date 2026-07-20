import 'package:bora_app/widgets/payments/collect_badge.dart';
import 'package:bora_app/widgets/payments/collect_reminder_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// [Ronda 2] O lembrete que aparece quando o motorista finaliza a corrida.
/// O que se protege aqui é o número: numa perna do pacote €8 com uma parada o
/// motorista tem de recolher €10 em mão — mostrar os €2 do acerto final (ou os
/// €8 do pacote sem a parada) é dinheiro que se perde no passeio.
void main() {
  Future<void> abrir(
    WidgetTester tester, {
    required CollectState state,
    int amountCents = 0,
  }) async {
    await tester.pumpWidget(MaterialApp(
      home: Builder(
        builder: (context) => Scaffold(
          body: ElevatedButton(
            onPressed: () => showCollectReminderDialog(context,
                state: state, amountCents: amountCents),
            child: const Text('abrir'),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('abrir'));
    await tester.pumpAndSettle();
  }

  testWidgets('dinheiro mostra o total a recolher em GRANDE', (tester) async {
    await abrir(tester, state: CollectState.collectCash, amountCents: 1000);

    expect(find.text('COBRAR EM DINHEIRO'), findsOneWidget);
    expect(find.text('€10.00'), findsOneWidget);

    // Grande de propósito — é o ponto todo do lembrete.
    final valor = tester.widget<Text>(find.byKey(const Key(
        'collect_reminder_amount')));
    expect(valor.style!.fontSize, greaterThanOrEqualTo(28));
  });

  testWidgets('pago no app diz para NÃO cobrar e não mostra valor',
      (tester) async {
    await abrir(tester, state: CollectState.paidOnline);

    expect(find.text('JÁ PAGO NA APP'), findsOneWidget);
    expect(find.textContaining('Não cobres nada'), findsOneWidget);
    expect(find.byKey(const Key('collect_reminder_amount')), findsNothing);
  });

  testWidgets('coberto pelo plano também não cobra', (tester) async {
    await abrir(tester, state: CollectState.coveredByPlan);

    expect(find.text('COBERTO PELO PLANO'), findsOneWidget);
    expect(find.byKey(const Key('collect_reminder_amount')), findsNothing);
  });

  testWidgets('não se fecha a tocar fora — tem de ser tocado', (tester) async {
    await abrir(tester, state: CollectState.collectCash, amountCents: 1000);

    // Toque no barrier (canto superior esquerdo, fora do diálogo).
    await tester.tapAt(const Offset(10, 10));
    await tester.pumpAndSettle();
    expect(find.text('COBRAR EM DINHEIRO'), findsOneWidget);

    await tester.tap(find.byKey(const Key('collect_reminder_ok')));
    await tester.pumpAndSettle();
    expect(find.text('COBRAR EM DINHEIRO'), findsNothing);
  });
}
