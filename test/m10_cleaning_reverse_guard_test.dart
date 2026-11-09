// M10 (09/11/2026): "parar a série" devolve à Carteira Bora no servidor; o estorno ao cartão
// (cleaning-checkout, ação reverse) tem de recusar essas limpezas antes de falar com a Stripe.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('reverse recusa limpezas da série parada antes de chamar a Stripe', () {
    final src = File('supabase/functions/cleaning-checkout/index.ts').readAsStringSync();
    final reverse = src.indexOf("if (action === 'reverse')");
    final trava = src.indexOf("booking.cancel_reason === 'serie_terminada'");
    // O mesmo retrieve existe noutra ação mais acima: procura-se o do reverse, a partir dele.
    final stripe = src.indexOf(
        'stripe.paymentIntents.retrieve(booking.stripe_payment_intent_id)', reverse);
    expect(reverse, greaterThan(0));
    expect(trava, greaterThan(reverse), reason: 'a trava vive dentro do reverse');
    expect(stripe, greaterThan(trava), reason: 'a trava vem antes de qualquer chamada à Stripe');
    expect(src, contains("note: 'devolvido_a_carteira'"));
  });
}
