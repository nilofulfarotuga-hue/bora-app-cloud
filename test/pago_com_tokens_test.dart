// Caso do pedido 9124cfa5 (05/11/2026): MB Way com 2,63 € em tokens. O cliente tem
// de ver a conta fechar: total 19,46 €, desconto 2,63 €, pago 16,83 €.
import 'package:bora_app/models/order_model.dart';
import 'package:bora_app/utils/conta_curta_dinheiro.dart';
import 'package:flutter_test/flutter_test.dart';

OrderModel _pedido({
  PaymentMethod meio = PaymentMethod.mbway,
  PaymentStatus pagamento = PaymentStatus.paid,
  int tokens = 263,
  int saldo = 0,
}) =>
    OrderModel(
      id: '9124cfa5-9de3-43d3-8a4b-0641e946fa38',
      total: 19.46,
      serviceType: OrderServiceType.restaurant,
      status: OrderStatus.delivered,
      paymentMethod: meio,
      paymentStatus: pagamento,
      tokensAppliedValueCents: tokens,
      walletAppliedCents: saldo,
      createdAt: DateTime.utc(2026, 11, 5, 13, 48),
    );

void main() {
  test('MB Way com tokens: pago = total menos o desconto', () {
    expect(pagoPorCartaoOuMbWay(_pedido()), closeTo(16.83, 0.001));
  });

  test('cartão com tokens e saldo: tira os dois', () {
    expect(pagoPorCartaoOuMbWay(_pedido(meio: PaymentMethod.card, saldo: 100)), closeTo(15.83, 0.001));
  });

  test('sem desconto o Total já é o que se paga: não há linha', () {
    expect(pagoPorCartaoOuMbWay(_pedido(tokens: 0)), isNull);
  });

  test('dinheiro tem a sua própria conta', () {
    expect(pagoPorCartaoOuMbWay(_pedido(meio: PaymentMethod.cash)), isNull);
  });

  test('ainda por pagar: não se diz "Pago"', () {
    expect(pagoPorCartaoOuMbWay(_pedido(pagamento: PaymentStatus.pending)), isNull);
  });
}
