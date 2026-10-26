import 'package:bora_app/models/carwash_models.dart';
import 'package:flutter_test/flutter_test.dart';

// [24/10/2026 · bloco 4a / N3b achado 2] Cada lado da lavagem só pede o
// dinheiro que lhe diz respeito.
void main() {
  List<String> colunas(String s) => s.split(',').map((c) => c.trim()).toList();

  test('o cliente não pede o ganho do lavador nem a parte da Bora', () {
    final c = colunas(kCarwashColunasCliente);
    expect(c, isNot(contains('washer_earnings_cents')));
    expect(c, isNot(contains('bora_fee_cents')));
    expect(c, containsAll(['id', 'status', 'total_cents', 'payment_status']));
  });

  test('o lavador pede o seu ganho, não a parte da Bora', () {
    final c = colunas(kCarwashColunasLavador);
    expect(c, contains('washer_earnings_cents'));
    expect(c, isNot(contains('bora_fee_cents')));
  });

  test('sem a coluna, o modelo fica a 0 (não rebenta)', () {
    final b = CarwashBooking.fromSupabase({
      'id': 'b1',
      'client_user_id': 'u',
      'status': 'scheduled',
      'service_type': 'exterior',
      'total_cents': 2000,
    });
    expect(b.boraFeeCents, 0);
    expect(b.washerEarningsCents, 0);
  });
}
