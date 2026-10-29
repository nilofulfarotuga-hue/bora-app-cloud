// 28/10/2026 (missao-geral, Bloco 1, C3/C7): a "conta curta" do dinheiro.
// Caso real: pedido de 14,35 € pago quase todo com saldo (10,31 €) e tokens
// (0,73 €) — o estafeta via RECEBER 14,35 € e o cliente só devia 3,31 €.
// Cada teste falha no código de antes: não havia linha nenhuma a explicar o
// valor, a faixa laranja só dizia o número, e depois do talão a app deitava
// fora o cash_total_due que o servidor devolvia.
import 'package:bora_app/models/order_model.dart';
import 'package:bora_app/screens/driver_map_screen.dart';
import 'package:bora_app/services/talao_nao_parceiro_service.dart';
import 'package:bora_app/utils/conta_curta_dinheiro.dart';
import 'package:bora_app/widgets/favor_passos_card.dart';
import 'package:bora_app/widgets/payments/conta_curta_dinheiro_texto.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';

OrderModel _mercado({
  PaymentMethod pagamento = PaymentMethod.cash,
  double price = 14.35,
  double? finalTotal,
  double? cashTotalDue,
  int saldo = 1031,
  int tokens = 73,
  int credito = 0,
  int divida = 0,
  bool finalizado = false,
  OrderStatus status = OrderStatus.onTheWay,
}) {
  return OrderModel(
    id: '00000000-0000-4000-8000-0000000000c7',
    total: price,
    finalTotal: finalTotal,
    cashTotalDue: cashTotalDue,
    serviceType: OrderServiceType.storeShopping,
    orderType: OrderType.nonPartnerPurchase,
    status: status,
    paymentMethod: pagamento,
    walletAppliedCents: saldo,
    tokensAppliedValueCents: tokens,
    menuCreditAppliedCents: credito,
    debtCollectedCents: divida,
    isPurchaseFinalized: finalizado,
    vendorName: 'Mercado Teste',
  );
}

OrderModel _favor({
  bool dinheiroDeCasa = false,
  int saldo = 400,
  int tokens = 100,
}) {
  return OrderModel(
    id: '00000000-0000-4000-8000-0000000000f7',
    total: 6.00,
    finalTotal: 26.00,
    cashTotalDue: 21.00,
    serviceType: OrderServiceType.errand,
    orderType: OrderType.errand,
    status: OrderStatus.onTheWay,
    paymentMethod: PaymentMethod.cash,
    walletAppliedCents: saldo,
    tokensAppliedValueCents: tokens,
    isPurchaseFinalized: true,
    errandHasPurchase: true,
    errandPasso: 2,
    errandHomeStop: dinheiroDeCasa,
    errandHomeStopReason: dinheiroDeCasa ? 'dinheiro' : null,
    errandHomeStopCashCents: dinheiroDeCasa ? 4000 : null,
    finalPurchaseValue: 20.00,
    deliveryFee: 6.00,
    customerName: 'Cliente Teste',
    errandDescription: 'Comprar pão',
    errandLocation: 'Padaria Teste, Guarda',
    dropoffAddress: 'Rua de Teste 1, Guarda',
    destination: const LatLng(40.537, -7.268),
  );
}

Widget _app(Widget filho) => MaterialApp(
      home: Scaffold(body: SingleChildScrollView(child: filho)),
    );

void main() {
  group('contaCurtaDinheiro', () {
    test('mercado não-parceiro antes do talão: price − saldo − tokens', () {
      expect(
        contaCurtaDinheiro(_mercado()),
        'Total 14,35 € · já pago com saldo/tokens 11,04 € · RECEBER 3,31 €',
      );
    });

    test('mercado não-parceiro depois do talão: final_total − saldo − tokens',
        () {
      expect(
        contaCurtaDinheiro(_mercado(finalTotal: 16.20, finalizado: true)),
        'Total 16,20 € · já pago com saldo/tokens 11,04 € · RECEBER 5,16 €',
      );
    });

    test('com o cash_total_due do servidor, RECEBER é esse valor', () {
      expect(
        contaCurtaDinheiro(_mercado(
            finalTotal: 16.20, cashTotalDue: 5.16, finalizado: true)),
        endsWith('RECEBER 5,16 €'),
      );
    });

    test('Favor com compra: total do talão, RECEBER do servidor', () {
      expect(
        contaCurtaDinheiro(_favor()),
        'Total 26,00 € · já pago com saldo/tokens 5,00 € · RECEBER 21,00 €',
      );
    });

    test('Favor com o dinheiro levantado em casa: sem conta curta (é troco)',
        () {
      expect(contaCurtaDinheiro(_favor(dinheiroDeCasa: true)), isNull);
    });

    test('artigo "não há": o final desce e o RECEBER desce o mesmo', () {
      final antes = _mercado(saldo: 500, tokens: 100);
      final depois = _mercado(
          finalTotal: 14.35 - 2.49, saldo: 500, tokens: 100, finalizado: true);
      expect(contaCurtaDinheiro(antes), endsWith('RECEBER 8,35 €'));
      expect(contaCurtaDinheiro(depois), endsWith('RECEBER 5,86 €'));
      expect(antes.totalToCollectCash - depois.totalToCollectCash,
          closeTo(2.49, 0.001));
    });

    test('dívida anterior: aparece na linha e o RECEBER inclui-a', () {
      expect(
        contaCurtaDinheiro(_mercado(divida: 250)),
        'Total 14,35 € · já pago com saldo/tokens 11,04 € · '
        'dívida anterior 2,50 € · RECEBER 5,81 €',
      );
    });

    test('crédito de menu também conta como já pago', () {
      expect(
        contaCurtaDinheiro(_mercado(saldo: 0, tokens: 0, credito: 200)),
        'Total 14,35 € · já pago com saldo/tokens 2,00 € · RECEBER 12,35 €',
      );
    });

    test('sem saldo/tokens/crédito → null', () {
      expect(contaCurtaDinheiro(_mercado(saldo: 0, tokens: 0)), isNull);
    });

    test('cartão e MB Way → null', () {
      expect(contaCurtaDinheiro(_mercado(pagamento: PaymentMethod.card)),
          isNull);
      expect(contaCurtaDinheiro(_mercado(pagamento: PaymentMethod.mbway)),
          isNull);
    });
  });

  group('dinheiroDoCliente', () {
    test('dinheiro com saldo/tokens: paga 3,31 € e já pagou 11,04 €', () {
      final d = dinheiroDoCliente(_mercado())!;
      expect(d.emDinheiro, closeTo(3.31, 0.001));
      expect(d.jaPago, closeTo(11.04, 0.001));
    });

    test('sem nada pago antes ou não-dinheiro → null', () {
      expect(dinheiroDoCliente(_mercado(saldo: 0, tokens: 0)), isNull);
      expect(dinheiroDoCliente(_mercado(pagamento: PaymentMethod.card)),
          isNull);
    });
  });

  group('totalWithDebt (cliente)', () {
    test('dinheiro com saldo/tokens: é o TOTAL do pedido, não o descontado',
        () {
      expect(_mercado().totalWithDebt, closeTo(14.35, 0.001));
      expect(_mercado(divida: 250).totalWithDebt, closeTo(16.85, 0.001));
    });

    test('dinheiro sem nada pago antes: continua = ao que o estafeta cobra', () {
      final o = _mercado(saldo: 0, tokens: 0, divida: 250);
      expect(o.totalWithDebt, o.totalToCollectCash);
    });
  });

  group('talão: cash_total_due da resposta do servidor', () {
    test('lê cash_total_due_cents da RPC em EUR', () {
      final r = TalaoResultado.sucesso(
          {'ok': true, 'status': 'onTheWay', 'cash_total_due_cents': 331});
      expect(r.cashTotalDueEur, closeTo(3.31, 0.0001));
    });

    test('sem o campo (cartão/MB Way) fica null', () {
      final r = TalaoResultado.sucesso({'ok': true, 'status': 'onTheWay'});
      expect(r.cashTotalDueEur, isNull);
      expect(TalaoResultado.erro('X', 'y').cashTotalDueEur, isNull);
    });
  });

  group('widgets do estafeta', () {
    testWidgets(
        'faixa laranja: RECEBER 3,31 € e a conta curta por baixo '
        '(total 14,35, saldo 10,31, tokens 0,73)', (tester) async {
      await tester.pumpWidget(_app(CashCollectBanner(order: _mercado())));
      expect(find.text('RECEBER €3.31 EM DINHEIRO'), findsOneWidget);
      expect(find.byKey(const Key('conta_curta_dinheiro')), findsOneWidget);
      expect(
        find.text(
            'Total 14,35 € · já pago com saldo/tokens 11,04 € · RECEBER 3,31 €'),
        findsOneWidget,
      );
    });

    testWidgets('faixa laranja sem saldo/tokens: sem conta curta',
        (tester) async {
      await tester.pumpWidget(
          _app(CashCollectBanner(order: _mercado(saldo: 0, tokens: 0))));
      expect(find.text('RECEBER €14.35 EM DINHEIRO'), findsOneWidget);
      expect(find.byKey(const Key('conta_curta_dinheiro')), findsNothing);
    });

    testWidgets('cartão do Favor, passo da entrega: cobrar + conta curta',
        (tester) async {
      await tester.pumpWidget(_app(FavorPassosCard(order: _favor())));
      expect(find.text('Cobrar à cliente: 21,00 €'), findsOneWidget);
      expect(
        find.text(
            'Total 26,00 € · já pago com saldo/tokens 5,00 € · RECEBER 21,00 €'),
        findsOneWidget,
      );
    });

    testWidgets('linha sozinha: some no cartão/MB Way', (tester) async {
      await tester.pumpWidget(_app(ContaCurtaDinheiroTexto(
          order: _mercado(pagamento: PaymentMethod.mbway))));
      expect(find.byKey(const Key('conta_curta_dinheiro')), findsNothing);
    });
  });
}
