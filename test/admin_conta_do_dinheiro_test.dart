// 28/10/2026 (missao-geral, Bloco 1, C4/C7): painel admin — "Conta do
// dinheiro (linha a linha)" e o aviso vermelho com a mesma regra da vigia do
// servidor (cash_total_due > total − saldo − tokens − crédito + 0,01).
// Falha no código de antes: a secção não existia.
import 'package:bora_app/config/app_colors.dart';
import 'package:bora_app/screens/admin/admin_order_detail_screen.dart';
import 'package:bora_app/utils/conta_do_dinheiro_admin.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, dynamic> _pedido({
  String metodo = 'cash',
  num? cashTotalDue = 3.31,
  num? finalTotal,
  int credito = 0,
  int divida = 0,
}) =>
    {
      'id': '00000000-0000-4000-8000-0000000000a4',
      'payment_method': metodo,
      'price': 14.35,
      if (finalTotal != null) 'final_total': finalTotal,
      'cash_total_due': cashTotalDue,
      'wallet_applied_cents': 1031,
      'tokens_applied_value_cents': 73,
      'menu_credit_applied_cents': credito,
      'debt_collected_cents': divida,
    };

String _valor(ContaDoDinheiroAdmin c, String rotulo) =>
    c.linhas.firstWhere((l) => l.rotulo == rotulo).valor;

void main() {
  group('contaDoDinheiroAdmin', () {
    test('linha a linha: total, saldo, tokens, crédito, dívida, porta, talão',
        () {
      final c = contaDoDinheiroAdmin(_pedido(credito: 50, divida: 250),
          talaoLoja: 10.12);
      expect(c.linhas.map((l) => l.rotulo).toList(), [
        'Total do pedido',
        'Saldo Bora usado',
        'Tokens usados (valor em €)',
        'Crédito de menu',
        'Dívida anterior',
        'Dinheiro a cobrar na porta (valor gravado pelo servidor)',
        'Valor do talão da loja',
      ]);
      expect(_valor(c, 'Total do pedido'), '€14.35');
      expect(_valor(c, 'Saldo Bora usado'), '€10.31');
      expect(_valor(c, 'Tokens usados (valor em €)'), '€0.73');
      expect(_valor(c, 'Crédito de menu'), '€0.50');
      expect(_valor(c, 'Dívida anterior'), '€2.50');
      expect(
          _valor(c, 'Dinheiro a cobrar na porta (valor gravado pelo servidor)'),
          '€3.31');
      expect(_valor(c, 'Valor do talão da loja'), '€10.12');
    });

    test('depois do talão o total é o final_total', () {
      final c = contaDoDinheiroAdmin(_pedido(finalTotal: 16.20));
      expect(_valor(c, 'Total do pedido'), '€16.20');
      expect(_valor(c, 'Valor do talão da loja'), '—');
    });

    test('conta certa (3,31 = 14,35 − 10,31 − 0,73): sem aviso', () {
      expect(contaDoDinheiroAdmin(_pedido()).aviso, isNull);
    });

    test('cobrar o total bruto com saldo/tokens: aviso vermelho', () {
      final c = contaDoDinheiroAdmin(_pedido(cashTotalDue: 14.35));
      expect(c.aviso, isNotNull);
      expect(c.aviso, contains('€14.35'));
      expect(c.aviso, contains('€3.31'));
    });

    test('1 cêntimo de folga, como a vigia do servidor', () {
      expect(contaDoDinheiroAdmin(_pedido(cashTotalDue: 3.32)).aviso, isNull);
      expect(
          contaDoDinheiroAdmin(_pedido(cashTotalDue: 3.33)).aviso, isNotNull);
    });

    test('dívida anterior fica fora da regra (o servidor também a deixa fora)',
        () {
      expect(contaDoDinheiroAdmin(_pedido(divida: 250)).aviso, isNull);
    });

    test('cartão/MB Way ou sem cash_total_due: sem aviso', () {
      expect(contaDoDinheiroAdmin(_pedido(metodo: 'card', cashTotalDue: 14.35))
          .aviso, isNull);
      final semValor = contaDoDinheiroAdmin(_pedido(cashTotalDue: null));
      expect(semValor.aviso, isNull);
      expect(
          _valor(semValor,
              'Dinheiro a cobrar na porta (valor gravado pelo servidor)'),
          '—');
    });
  });

  testWidgets('cartão do painel mostra as linhas e o aviso a vermelho',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: ContaDoDinheiroCard(
              conta: contaDoDinheiroAdmin(_pedido(cashTotalDue: 14.35),
                  talaoLoja: 9.50)),
        ),
      ),
    ));
    expect(find.text('Conta do dinheiro (linha a linha)'), findsOneWidget);
    expect(find.text('Saldo Bora usado'), findsOneWidget);
    expect(find.text('€10.31'), findsOneWidget);
    expect(find.text('€9.50'), findsOneWidget);
    final aviso = tester.widget<Text>(
        find.byKey(const Key('admin_conta_do_dinheiro_aviso')));
    expect(aviso.style?.color, AppColors.error);
    expect(aviso.data, contains('só deve €3.31'));
  });
}
