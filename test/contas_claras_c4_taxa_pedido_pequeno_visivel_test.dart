import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// [contas-claras · C4 · 21/09/2026] Cobrar sem mostrar não é permitido: a
/// taxa de pedido pequeno (platform_settings.small_order_fee_cents = 139,
/// ligada) tem de aparecer ao cliente, com nome claro, antes de confirmar.
///
/// O que se tranca aqui (só fonte; os números provam-se em SQL, ver
/// `.claude/.ai/provas/contas-claras-20260921/c4-taxa-pedido-pequeno.sql`):
///  1. os três ecrãs do cliente (carrinho, pagamento, detalhe do pedido) têm a
///     linha "Taxa de pedido pequeno";
///  2. no pagamento o valor é o do servidor (`quote_order_pricing` →
///     `small_order_fee`), preferido ao cálculo local;
///  3. o estafeta cobra em dinheiro o que o servidor gravou
///     (`cash_total_due` → `final_total` → `total`), nunca uma soma sua.
void main() {
  final cart = File('lib/screens/cart_screen.dart').readAsStringSync();
  final pay = File('lib/screens/payment_method_screen.dart').readAsStringSync();
  final det = File('lib/screens/order_details_screen.dart').readAsStringSync();
  final store = File('lib/stores/cart_store.dart').readAsStringSync();
  final model = File('lib/models/order_model.dart').readAsStringSync();

  test('a linha "Taxa de pedido pequeno" existe no carrinho, no pagamento e no detalhe', () {
    expect(cart, contains("'Taxa de pedido pequeno'.tr"));
    expect(pay, contains("'Taxa de pedido pequeno'.tr"));
    expect(det, contains("'Taxa de pedido pequeno'.tr"));
  });

  test('no pagamento o valor vem do quote do servidor (small_order_fee), preferido ao local', () {
    expect(store, contains("_quoteCache?['small_order_fee']"));
    expect(store, contains('if (doServidor != null) return doServidor;'));
    expect(pay, contains('cartStore.smallOrderFee'));
    // o pagamento pede o quote ao arrancar
    expect(pay, contains('cartStore.quoteOrderPricing('));
  });

  test('o estafeta cobra em dinheiro o valor gravado pelo servidor', () {
    expect(model, contains('(cashTotalDue ?? finalTotal ?? total) + debtCollectedCents / 100.0'));
  });
}
