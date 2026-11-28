// Planos de limpeza (28/11/2026): uma visita de plano paga-se e devolve-se só pelo servidor
// (cleaning-plan-charge). O pagamento de sempre (cleaning-checkout) recusa-a antes de falar com a Stripe.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('cleaning-checkout recusa visitas de plano antes de qualquer chamada à Stripe', () {
    final src = File('supabase/functions/cleaning-checkout/index.ts').readAsStringSync();
    final dono = src.indexOf("return json({ error: 'booking_not_yours' }, 403);");
    final trava = src.indexOf('if (booking.plan_id) {');
    final primeiraStripe = src.indexOf('stripe.', trava < 0 ? 0 : trava);
    final conta = src.indexOf('stripeParaNovoPagamento(admin');
    expect(dono, greaterThan(0));
    expect(trava, greaterThan(dono), reason: 'a trava vem depois de confirmar o dono da reserva');
    expect(conta, greaterThan(trava), reason: 'antes de escolher a conta Stripe');
    expect(primeiraStripe, greaterThan(trava), reason: 'antes de qualquer chamada à Stripe');
    expect(src, contains("note: 'plano_devolve_no_servidor'"));
    expect(src, contains("error: 'plan_visit_paid_by_plan'"));
  });
}
