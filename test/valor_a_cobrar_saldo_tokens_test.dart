// 28/10/2026 (missao-geral, Bloco C3): o valor que o estafeta cobra em
// dinheiro vem sempre do servidor (cash_total_due), que já desconta o saldo
// Bora, os tokens e o crédito de menu. Sem ele, é o total menos o que o
// cliente já pagou — nunca o total bruto. A dívida antiga soma-se por cima.
import 'package:bora_app/models/order_model.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, dynamic> _pedido({
  String serviceType = 'storeShopping',
  String orderType = 'nonPartnerPurchase',
  double price = 14.35,
  double? finalTotal,
  double? cashTotalDue,
  int saldo = 0,
  int tokens = 0,
  int credito = 0,
  int divida = 0,
  bool finalizado = false,
}) =>
    {
      'id': '00000000-0000-4000-8000-0000000000c3',
      'status': 'driverAccepted',
      'service_type': serviceType,
      'order_type': orderType,
      'payment_method': 'cash',
      'price': price,
      'vendor_name': 'Mercado Teste',
      'is_partner_store': false,
      'items': const [],
      if (finalTotal != null) 'final_total': finalTotal,
      if (cashTotalDue != null) 'cash_total_due': cashTotalDue,
      'wallet_applied_cents': saldo,
      'tokens_applied_value_cents': tokens,
      'menu_credit_applied_cents': credito,
      'debt_collected_cents': divida,
      'is_purchase_finalized': finalizado,
    };

void main() {
  test('lê tokens_applied_value_cents do servidor', () {
    final o = OrderModel.fromSupabase(_pedido(tokens: 73));
    expect(o.tokensAppliedValueCents, 73);
  });

  test('com cash_total_due do servidor cobra esse valor (antes do talão)', () {
    final o = OrderModel.fromSupabase(
        _pedido(cashTotalDue: 3.31, saldo: 1031, tokens: 73));
    expect(o.totalToCollectCash, closeTo(3.31, 0.001));
  });

  test('sem cash_total_due: total − saldo − tokens, nunca o total bruto', () {
    final o = OrderModel.fromSupabase(_pedido(saldo: 1031, tokens: 73));
    expect(o.totalToCollectCash, closeTo(3.31, 0.001));
  });

  test('depois do talão sem cash_total_due: final_total − saldo − tokens', () {
    final o = OrderModel.fromSupabase(_pedido(
        finalTotal: 16.20, saldo: 1031, tokens: 73, finalizado: true));
    expect(o.totalToCollectCash, closeTo(5.16, 0.001));
  });

  test('artigo "não há": o final_total desce e o valor a cobrar desce o mesmo',
      () {
    final antes = OrderModel.fromSupabase(_pedido(saldo: 500, tokens: 100));
    final depois = OrderModel.fromSupabase(_pedido(
        finalTotal: 14.35 - 2.49, saldo: 500, tokens: 100, finalizado: true));
    expect(antes.totalToCollectCash - depois.totalToCollectCash,
        closeTo(2.49, 0.001));
  });

  test('Favor depois da compra: usa o cash_total_due do servidor', () {
    final o = OrderModel.fromSupabase(_pedido(
        serviceType: 'errand',
        orderType: 'errand',
        price: 6.00,
        finalTotal: 26.00,
        cashTotalDue: 21.00,
        saldo: 400,
        tokens: 100,
        finalizado: true));
    expect(o.totalToCollectCash, closeTo(21.00, 0.001));
  });

  test('Favor depois da compra sem cash_total_due: final_total − já pago', () {
    final o = OrderModel.fromSupabase(_pedido(
        serviceType: 'errand',
        orderType: 'errand',
        price: 6.00,
        finalTotal: 26.00,
        saldo: 400,
        tokens: 100,
        finalizado: true));
    expect(o.totalToCollectCash, closeTo(21.00, 0.001));
  });

  test('depois da compra, cópia local antiga (price) não cobra a mais', () {
    final o = OrderModel.fromSupabase(_pedido(
        serviceType: 'errand',
        orderType: 'errand',
        price: 12.00,
        finalTotal: 9.88,
        cashTotalDue: 12.00,
        saldo: 200,
        finalizado: true));
    expect(o.totalToCollectCash, closeTo(7.88, 0.001));
  });

  test('crédito de menu também desconta', () {
    final o = OrderModel.fromSupabase(
        _pedido(price: 20.00, credito: 500, tokens: 200));
    expect(o.totalToCollectCash, closeTo(13.00, 0.001));
  });

  test('a dívida antiga soma-se por cima (como no create_order)', () {
    final o = OrderModel.fromSupabase(
        _pedido(price: 13.59, tokens: 502, divida: 250));
    expect(o.totalToCollectCash, closeTo(11.07, 0.001));
    final s = OrderModel.fromSupabase(
        _pedido(price: 13.59, cashTotalDue: 8.57, tokens: 502, divida: 250));
    expect(s.totalToCollectCash, closeTo(11.07, 0.001));
  });

  test('pago todo com saldo: cobra 0, nunca negativo', () {
    final o = OrderModel.fromSupabase(_pedido(price: 5.00, saldo: 700));
    expect(o.totalToCollectCash, 0);
  });

  test('sem saldo nem tokens: cobra o total (como antes)', () {
    final o = OrderModel.fromSupabase(_pedido(price: 12.90));
    expect(o.totalToCollectCash, closeTo(12.90, 0.001));
  });
}
