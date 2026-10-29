import 'package:bora_app/widgets/refund_choice_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// B.2 (k) da missão publica-2026-10-29 (adendo 3, regra do Danilo 29/10 18:34):
/// quando há dinheiro a devolver o cliente ESCOLHE sempre, entre duas opções
/// claras, nenhuma marcada à partida; o Confirmar só ativa depois de escolher.
void main() {
  Future<List<Map<String, String>>> abrir(
    WidgetTester tester, {
    String metodo = 'card',
    double tokensEur = 0,
  }) async {
    final chamadas = <Map<String, String>>[];
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: RefundChoiceDialog(
          orderId: 'pedido-1',
          refundableEur: 12.5,
          originalPaymentMethod: metodo,
          tokensEur: tokensEur,
          cancelar: ({
            required String orderId,
            required String reason,
            required String refundMethod,
          }) async {
            chamadas.add({'orderId': orderId, 'reason': reason, 'refundMethod': refundMethod});
          },
        ),
      ),
    ));
    await tester.pumpAndSettle();
    return chamadas;
  }

  FilledButton confirmar(WidgetTester tester) =>
      tester.widget<FilledButton>(find.widgetWithText(FilledButton, 'Confirmar'));

  testWidgets('duas opções grandes, nenhuma marcada, Confirmar desativado', (tester) async {
    await abrir(tester);
    expect(find.text('Carteira Bora'), findsOneWidget);
    expect(find.text('Devolver para a minha conta'), findsOneWidget);
    expect(find.textContaining('podes usar na mesma hora'), findsOneWidget);
    // o valor é igual nas duas opções (sem 80/20)
    expect(find.text('Recebes €12,50'), findsNWidgets(2));
    expect(find.textContaining('saldo livre'), findsNothing);
    expect(find.textContaining('80%'), findsNothing);
    expect(find.byIcon(Icons.radio_button_checked), findsNothing);
    expect(confirmar(tester).onPressed, isNull);
  });

  testWidgets('escolher Carteira Bora ativa o Confirmar e manda wallet', (tester) async {
    final chamadas = await abrir(tester);
    await tester.tap(find.text('Carteira Bora'));
    await tester.pumpAndSettle();
    expect(find.byIcon(Icons.radio_button_checked), findsOneWidget);
    expect(confirmar(tester).onPressed, isNotNull);
    await tester.enterText(find.byType(TextField), 'Já não quero');
    await tester.tap(find.widgetWithText(FilledButton, 'Confirmar'));
    await tester.pumpAndSettle();
    expect(chamadas, hasLength(1));
    expect(chamadas.single['refundMethod'], 'wallet');
    expect(chamadas.single['orderId'], 'pedido-1');
  });

  testWidgets('escolher Devolver para a minha conta manda stripe (cartão: 5 a 10 dias)', (tester) async {
    final chamadas = await abrir(tester, metodo: 'card');
    expect(find.text('Cartão: 5 a 10 dias úteis.'), findsOneWidget);
    await tester.tap(find.text('Devolver para a minha conta'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'Enganei-me no pedido');
    await tester.tap(find.widgetWithText(FilledButton, 'Confirmar'));
    await tester.pumpAndSettle();
    expect(chamadas.single['refundMethod'], 'stripe');
  });

  testWidgets('MB Way diz que chega normalmente na hora', (tester) async {
    await abrir(tester, metodo: 'mbway');
    expect(find.text('MB Way: chega normalmente na hora.'), findsOneWidget);
    expect(find.text('Cartão: 5 a 10 dias úteis.'), findsNothing);
  });

  testWidgets('sem motivo não cancela, mesmo com opção escolhida', (tester) async {
    final chamadas = await abrir(tester);
    await tester.tap(find.text('Carteira Bora'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Confirmar'));
    await tester.pumpAndSettle();
    expect(chamadas, isEmpty);
    expect(find.textContaining('Indica um motivo'), findsOneWidget);
  });

  testWidgets('tokens usados: linha "voltam como tokens" só quando há tokens', (tester) async {
    await abrir(tester, tokensEur: 1.5);
    expect(find.textContaining('voltam como tokens'), findsOneWidget);
    expect(find.textContaining('€1,50'), findsOneWidget);
    await abrir(tester, tokensEur: 0);
    expect(find.textContaining('voltam como tokens'), findsNothing);
  });

  test('sem escolha a dinheiro ou por pagar; com escolha em MB Way e cartão pagos', () {
    expect(escolhaDeReembolsoNecessaria(paymentMethod: 'cash', pago: true), isFalse);
    expect(escolhaDeReembolsoNecessaria(paymentMethod: 'card', pago: false), isFalse);
    expect(escolhaDeReembolsoNecessaria(paymentMethod: 'mbway', pago: false), isFalse);
    expect(escolhaDeReembolsoNecessaria(paymentMethod: 'card', pago: true), isTrue);
    expect(escolhaDeReembolsoNecessaria(paymentMethod: 'mbway', pago: true), isTrue);
  });
}
