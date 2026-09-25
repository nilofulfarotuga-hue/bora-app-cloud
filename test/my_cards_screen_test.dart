import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:bora_app/models/saved_card.dart';
import 'package:bora_app/screens/my_cards_screen.dart';
import 'package:bora_app/services/card_wallet_service.dart';

/// Carteira falsa em memória — não toca em Supabase nem em SharedPreferences.
class _FakeCardWallet extends CardWalletService {
  _FakeCardWallet(this._cards);

  List<SavedCard> _cards;

  final List<String> setDefaultCalls = [];
  final List<String> removeCalls = [];

  /// Quando definido, [removeCard] falha com esta mensagem.
  String? removeFailure;

  @override
  Future<List<SavedCard>> listCards() async => _cards;

  @override
  Future<String?> getDefaultCardId() async {
    for (final c in _cards) {
      if (c.isDefault) return c.id;
    }
    return null;
  }

  @override
  Future<void> clearDefaultCard() async {}

  @override
  Future<void> setDefaultCard(String paymentMethodId) async {
    setDefaultCalls.add(paymentMethodId);
    _cards = [
      for (final c in _cards)
        SavedCard(
          id: c.id,
          brand: c.brand,
          last4: c.last4,
          expMonth: c.expMonth,
          expYear: c.expYear,
          isDefault: c.id == paymentMethodId,
        ),
    ];
  }

  @override
  Future<void> removeCard(String paymentMethodId) async {
    removeCalls.add(paymentMethodId);
    if (removeFailure != null) throw CardWalletException(removeFailure!);
    _cards = _cards.where((c) => c.id != paymentMethodId).toList();
  }
}

const _visa = SavedCard(
  id: 'pm_visa',
  brand: 'visa',
  last4: '4242',
  expMonth: 4,
  expYear: 2030,
  isDefault: true,
);

const _mc = SavedCard(
  id: 'pm_mc',
  brand: 'mastercard',
  last4: '5556',
  expMonth: 11,
  expYear: 2028,
);

Future<_FakeCardWallet> _pumpScreen(
  WidgetTester tester, {
  List<SavedCard> cards = const [_visa, _mc],
}) async {
  final wallet = _FakeCardWallet([...cards]);
  await tester.pumpWidget(
    MaterialApp(home: MyCardsScreen(service: wallet)),
  );
  await tester.pumpAndSettle();
  return wallet;
}

void main() {
  testWidgets('lista cartões com marca e últimos 4 dígitos', (tester) async {
    await _pumpScreen(tester);

    expect(find.text('Visa •••• 4242'), findsOneWidget);
    expect(find.text('Mastercard •••• 5556'), findsOneWidget);
    expect(find.text('Validade 04/30'), findsOneWidget);
  });

  testWidgets('marca o cartão padrão com o selo Principal', (tester) async {
    await _pumpScreen(tester);

    // Só o cartão padrão tem o selo — nunca os dois.
    expect(find.text('Principal'), findsOneWidget);
  });

  testWidgets('estado vazio quando não há cartões guardados', (tester) async {
    await _pumpScreen(tester, cards: const []);

    expect(find.text('Ainda não tens cartões guardados'), findsOneWidget);
    expect(find.byType(PopupMenuButton<String>), findsNothing);
  });

  testWidgets('tornar principal chama setDefaultCard e move o selo',
      (tester) async {
    final wallet = await _pumpScreen(tester);

    // Menu do segundo cartão (o que ainda não é principal).
    await tester.tap(find.byType(PopupMenuButton<String>).last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Tornar principal'));
    await tester.pumpAndSettle();

    expect(wallet.setDefaultCalls, ['pm_mc']);
    expect(find.text('Principal'), findsOneWidget);
  });

  testWidgets('o cartão principal não oferece "Tornar principal"',
      (tester) async {
    await _pumpScreen(tester);

    await tester.tap(find.byType(PopupMenuButton<String>).first);
    await tester.pumpAndSettle();

    expect(find.text('Tornar principal'), findsNothing);
    expect(find.text('Remover cartão'), findsOneWidget);
  });

  testWidgets('remover pede confirmação e só remove depois do "Remover"',
      (tester) async {
    final wallet = await _pumpScreen(tester);

    await tester.tap(find.byType(PopupMenuButton<String>).last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Remover cartão'));
    await tester.pumpAndSettle();

    expect(find.text('Remover cartão?'), findsOneWidget);

    // Cancelar não remove nada.
    await tester.tap(find.text('Cancelar'));
    await tester.pumpAndSettle();
    expect(wallet.removeCalls, isEmpty);
    expect(find.text('Mastercard •••• 5556'), findsOneWidget);

    // Confirmar remove.
    await tester.tap(find.byType(PopupMenuButton<String>).last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Remover cartão'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Remover'));
    await tester.pumpAndSettle();

    expect(wallet.removeCalls, ['pm_mc']);
    expect(find.text('Mastercard •••• 5556'), findsNothing);
  });

  testWidgets('falha ao remover mostra o erro e mantém o cartão',
      (tester) async {
    final wallet = await _pumpScreen(tester);
    wallet.removeFailure = 'Esse cartão não pertence a esta conta.';

    await tester.tap(find.byType(PopupMenuButton<String>).last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Remover cartão'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Remover'));
    await tester.pump();

    expect(find.text('Esse cartão não pertence a esta conta.'), findsOneWidget);
    await tester.pumpAndSettle();
    expect(find.text('Mastercard •••• 5556'), findsOneWidget);
  });
}
