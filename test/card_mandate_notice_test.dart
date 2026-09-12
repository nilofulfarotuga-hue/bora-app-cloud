import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:bora_app/models/saved_card.dart';
import 'package:bora_app/services/card_wallet_service.dart';
import 'package:bora_app/widgets/card_mandate_notice.dart';

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

Future<void> _pump(WidgetTester tester, {SavedCard? card}) async {
  await tester.pumpWidget(MaterialApp(
    home: Scaffold(body: CardMandateNotice(wallet: _FakeWallet(card))),
  ));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('sem cartão guardado, mostra o mandato (é o 1.º cartão)',
      (tester) async {
    await _pump(tester, card: null);
    expect(find.text(mandateText), findsOneWidget);
  });

  testWidgets('com cartão já guardado, não mostra nada', (tester) async {
    await _pump(tester, card: _visa);
    expect(find.text(mandateText), findsNothing);
  });

  testWidgets('não pisca antes de saber — nada no 1.º frame', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(body: CardMandateNotice(wallet: _FakeWallet(_visa))),
    ));
    // Ainda não resolveu a carteira: não pode já ter desenhado a frase.
    expect(find.text(mandateText), findsNothing);
    await tester.pumpAndSettle();
    expect(find.text(mandateText), findsNothing);
  });

  group('texto do mandato', () {
    test('diz o que é guardado, quem confirma e como se remove', () {
      expect(mandateText, contains('guardar este cartão'));
      expect(mandateText, contains('confirmado por ti'));
      expect(mandateText, contains('Meus Cartões'));
    });

    test('é PT-PT — não usa "você" nem grafia PT-BR', () {
      expect(mandateText.toLowerCase(), isNot(contains('você')));
      expect(mandateText.toLowerCase(), isNot(contains('cartao')));
    });
  });
}
