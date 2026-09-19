import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:bora_app/models/saved_card.dart';
import 'package:bora_app/services/card_wallet_service.dart';
import 'package:bora_app/services/payment_biometric_gate.dart';
import 'package:bora_app/widgets/unified_checkout_button.dart';

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

/// Gate com biometria controlada pelo teste.
PaymentBiometricGate _gate({
  required bool capable,
  required bool approves,
  List<String>? reasons,
}) {
  return PaymentBiometricGate(
    isWeb: false,
    isCapable: () async => capable,
    authenticate: (reason) async {
      reasons?.add(reason);
      return approves;
    },
  );
}

void main() {
  group('PaymentBiometricGate', () {
    test('cartão novo não pede biometria (o PaymentSheet já pede os dados)',
        () async {
      var asked = false;
      final gate = PaymentBiometricGate(
        isWeb: false,
        isCapable: () async => true,
        authenticate: (_) async {
          asked = true;
          return true;
        },
      );

      expect(await gate.ensureAuthorized(usingSavedCard: false), isTrue);
      expect(asked, isFalse);
    });

    test('aparelho sem biometria deixa pagar — não bloqueia a compra',
        () async {
      final gate = _gate(capable: false, approves: false);
      expect(await gate.ensureAuthorized(usingSavedCard: true), isTrue);
    });

    test('na web passa à frente (local_auth não existe)', () async {
      final gate = PaymentBiometricGate(
        isWeb: true,
        isCapable: () async => true,
        authenticate: (_) async => false,
      );
      expect(await gate.ensureAuthorized(usingSavedCard: true), isTrue);
    });

    test('cartão guardado + biometria recusada = NÃO autoriza', () async {
      final gate = _gate(capable: true, approves: false);
      expect(await gate.ensureAuthorized(usingSavedCard: true), isFalse);
    });

    test('cartão guardado + biometria aceite = autoriza', () async {
      final gate = _gate(capable: true, approves: true);
      expect(await gate.ensureAuthorized(usingSavedCard: true), isTrue);
    });

    test('o motivo mostrado ao cliente diz o valor em euros', () {
      expect(PaymentBiometricGate.reasonForAmount(12.4),
          'Confirma o pagamento de €12,40');
    });
  });

  group('UnifiedCheckoutButton', () {
    Future<void> pump(
      WidgetTester tester, {
      required PaymentBiometricGate gate,
      required List<String?> paid,
      SavedCard? card = _visa,
      bool showSavedCard = true,
      bool useOverride = false,
      String? override,
    }) async {
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: UnifiedCheckoutButton(
            label: 'Confirmar pagamento',
            amount: 12.40,
            wallet: _FakeWallet(card),
            gate: gate,
            showSavedCard: showSavedCard,
            useOverride: useOverride,
            savedPmIdOverride: override,
            onPay: (pmId) async => paid.add(pmId),
          ),
        ),
      ));
      await tester.pumpAndSettle();
    }

    testWidgets('mostra o cartão padrão que vai ser cobrado', (tester) async {
      await pump(tester, gate: _gate(capable: true, approves: true), paid: []);
      expect(find.text('Visa •••• 4242'), findsOneWidget);
    });

    testWidgets('biometria aceite → cobra com o saved_pm_id', (tester) async {
      final paid = <String?>[];
      final reasons = <String>[];
      await pump(
        tester,
        gate: _gate(capable: true, approves: true, reasons: reasons),
        paid: paid,
      );

      await tester.tap(find.text('Confirmar pagamento'));
      await tester.pumpAndSettle();

      expect(paid, ['pm_visa']);
      expect(reasons, ['Confirma o pagamento de €12,40']);
    });

    testWidgets('biometria recusada → NÃO cobra e avisa o cliente',
        (tester) async {
      final paid = <String?>[];
      await pump(
        tester,
        gate: _gate(capable: true, approves: false),
        paid: paid,
      );

      await tester.tap(find.text('Confirmar pagamento'));
      await tester.pumpAndSettle();

      expect(paid, isEmpty, reason: 'recusar a biometria não pode cobrar');
      expect(find.text('Pagamento cancelado. Não foi cobrado nada.'),
          findsOneWidget);
    });

    testWidgets('sem cartão guardado → cobra com null e não pede biometria',
        (tester) async {
      final paid = <String?>[];
      var asked = false;
      final gate = PaymentBiometricGate(
        isWeb: false,
        isCapable: () async => true,
        authenticate: (_) async {
          asked = true;
          return false;
        },
      );
      await pump(tester, gate: gate, paid: paid, card: null);

      await tester.tap(find.text('Confirmar pagamento'));
      await tester.pumpAndSettle();

      expect(paid, [null], reason: 'cai no PaymentSheet, como hoje');
      expect(asked, isFalse);
      expect(find.text('Visa •••• 4242'), findsNothing);
    });

    testWidgets('useOverride: a escolha do ecrã manda sobre o padrão',
        (tester) async {
      final paid = <String?>[];
      await pump(
        tester,
        gate: _gate(capable: true, approves: true),
        paid: paid,
        showSavedCard: false,
        useOverride: true,
        override: 'pm_outro',
      );

      await tester.tap(find.text('Confirmar pagamento'));
      await tester.pumpAndSettle();

      expect(paid, ['pm_outro']);
      expect(find.text('Visa •••• 4242'), findsNothing);
    });

    testWidgets('useOverride com null (cartão novo) não pede biometria',
        (tester) async {
      final paid = <String?>[];
      var asked = false;
      final gate = PaymentBiometricGate(
        isWeb: false,
        isCapable: () async => true,
        authenticate: (_) async {
          asked = true;
          return false;
        },
      );
      await pump(
        tester,
        gate: gate,
        paid: paid,
        showSavedCard: false,
        useOverride: true,
        override: null,
      );

      await tester.tap(find.text('Confirmar pagamento'));
      await tester.pumpAndSettle();

      expect(paid, [null]);
      expect(asked, isFalse);
    });
  });
}
