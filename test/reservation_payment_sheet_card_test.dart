import 'package:flutter_test/flutter_test.dart';

import 'package:bora_app/models/saved_card.dart';
import 'package:bora_app/screens/client/reservation/reservation_payment_method_sheet.dart';

/// Legenda da opção "Cartão" no sheet partilhado por reserva, marcação e
/// planos TVDE. O sheet em si não é testável como widget (exige AuthStore com
/// Supabase inicializado), por isso testa-se o texto, que é o que o cliente lê.
void main() {
  const visa = SavedCard(
    id: 'pm_visa',
    brand: 'visa',
    last4: '4242',
    expMonth: 4,
    expYear: 2030,
    isDefault: true,
  );

  test('com cartão guardado diz a marca, os últimos 4 e o "1 toque"', () {
    expect(cardOptionSubtitle(visa), 'Visa •••• 4242 · pagas num toque');
  });

  test('sem cartão guardado mantém o texto genérico de sempre', () {
    expect(cardOptionSubtitle(null), 'Pague com cartão de crédito ou débito.');
  });

  test('nunca expõe mais do que os últimos 4 dígitos', () {
    final texto = cardOptionSubtitle(visa);
    // O único grupo de dígitos presente é o last4.
    final digitos = RegExp(r'\d+').allMatches(texto).map((m) => m.group(0));
    expect(digitos, ['4242']);
  });

  test('marca desconhecida não rebenta — usa o que o Stripe devolveu', () {
    const outro = SavedCard(id: 'pm_x', brand: 'cartes_bancaires', last4: '0001');
    expect(cardOptionSubtitle(outro), 'cartes_bancaires •••• 0001 · pagas num toque');
  });
}
