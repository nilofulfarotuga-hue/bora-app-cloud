import 'package:flutter_test/flutter_test.dart';

import 'package:bora_app/models/saved_card.dart';
import 'package:bora_app/services/card_wallet_service.dart';
import 'package:bora_app/services/payment_biometric_gate.dart';
import 'package:bora_app/services/saved_card_checkout.dart';

class _FakeWallet extends CardWalletService {
  _FakeWallet(this.card);
  final SavedCard? card;
  @override
  Future<SavedCard?> defaultCard() async => card;
}

const _visa = SavedCard(
  id: 'pm_visa',
  brand: 'visa',
  last4: '4242',
  expMonth: 4,
  expYear: 2030,
  isDefault: true,
);

SavedCardCheckout _checkout({
  SavedCard? card,
  bool capable = true,
  bool approves = true,
  List<String>? reasons,
}) {
  return SavedCardCheckout(
    wallet: _FakeWallet(card),
    gate: PaymentBiometricGate(
      isWeb: false,
      isCapable: () async => capable,
      authenticate: (reason) async {
        reasons?.add(reason);
        return approves;
      },
    ),
  );
}

void main() {
  test('cartão guardado + biometria aceite → cobra com o pm_id', () async {
    final reasons = <String>[];
    final auth = await _checkout(card: _visa, reasons: reasons)
        .authorize(amountEur: 3.0);

    expect(auth.cancelled, isFalse);
    expect(auth.savedPmId, 'pm_visa');
    expect(auth.usesSavedCard, isTrue);
    expect(auth.card?.last4, '4242');
    expect(reasons, ['Confirma o pagamento de €3,00']);
  });

  test('biometria recusada → cancelado, sem pm_id', () async {
    final auth =
        await _checkout(card: _visa, approves: false).authorize(amountEur: 3.0);

    expect(auth.cancelled, isTrue);
    expect(auth.savedPmId, isNull);
  });

  test('sem cartão guardado → segue sem biometria e sem pm_id (PaymentSheet)',
      () async {
    var asked = false;
    final checkout = SavedCardCheckout(
      wallet: _FakeWallet(null),
      gate: PaymentBiometricGate(
        isWeb: false,
        isCapable: () async => true,
        authenticate: (_) async {
          asked = true;
          return false;
        },
      ),
    );

    final auth = await checkout.authorize(amountEur: 3.0);

    expect(auth.cancelled, isFalse);
    expect(auth.savedPmId, isNull);
    expect(auth.usesSavedCard, isFalse);
    expect(asked, isFalse, reason: 'cartão novo não pede biometria');
  });

  test('aparelho sem biometria continua a poder pagar com cartão guardado',
      () async {
    final auth = await _checkout(card: _visa, capable: false, approves: false)
        .authorize(amountEur: 3.0);

    expect(auth.cancelled, isFalse);
    expect(auth.savedPmId, 'pm_visa');
  });

  test('sem valor, o motivo é genérico', () async {
    final reasons = <String>[];
    await _checkout(card: _visa, reasons: reasons).authorize();
    expect(reasons, ['Confirma o pagamento']);
  });
}
