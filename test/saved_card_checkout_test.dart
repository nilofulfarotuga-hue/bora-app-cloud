// Cartão guardado: nada é cobrado sem o cliente ver o valor e dizer que sim.
//
// Cicatriz de 22/09/2026: o Danilo escolheu cartão numa corrida de 5,00 €, não
// apareceu tela nenhuma e a app foi direita a "à procura de motorista". Tinha
// pago — o caminho do cartão guardado cria o PaymentIntent já confirmado
// `off_session` e cobra sem folha. Agora há sempre um "Confirmar" humano.
//
// O contrato mudou de propósito: `context` e `amountEur` passaram a ser
// obrigatórios. O TVDE chamava `authorize()` sem valor — esquecê-lo deixou de
// compilar.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:bora_app/models/saved_card.dart';
import 'package:bora_app/services/card_wallet_service.dart';
import 'package:bora_app/services/payment_biometric_gate.dart';
import 'package:bora_app/services/saved_card_checkout.dart';
import 'package:bora_app/widgets/payments/folha_confirmar_cartao.dart';

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

/// Corre o `authorize` dentro de uma árvore real (precisa de `BuildContext`) e
/// devolve o resultado.
Future<SavedCardAuthorization> _autorizar(
  WidgetTester tester, {
  SavedCard? card,
  bool capable = true,
  bool approves = true,
  double amountEur = 3.0,
  EscolhaDoCartao escolha = EscolhaDoCartao.confirmar,
  List<String>? motivos,
  List<double>? valoresVistosNaFolha,
  List<SavedCard>? cartoesVistosNaFolha,
}) async {
  final checkout = SavedCardCheckout(
    wallet: _FakeWallet(card),
    gate: PaymentBiometricGate(
      isWeb: false,
      isCapable: () async => capable,
      authenticate: (motivo) async {
        motivos?.add(motivo);
        return approves;
      },
    ),
    confirmar: (_, {required amountEur, required card}) async {
      valoresVistosNaFolha?.add(amountEur);
      cartoesVistosNaFolha?.add(card);
      return escolha;
    },
  );

  SavedCardAuthorization? resultado;
  await tester.pumpWidget(MaterialApp(
    home: Builder(
      builder: (ctx) => TextButton(
        onPressed: () async {
          resultado =
              await checkout.authorize(context: ctx, amountEur: amountEur);
        },
        child: const Text('pagar'),
      ),
    ),
  ));
  await tester.tap(find.text('pagar'));
  await tester.pumpAndSettle();
  return resultado!;
}

void main() {
  testWidgets('folha confirmada + biometria aceite → cobra com o pm_id',
      (tester) async {
    final motivos = <String>[];
    final auth = await _autorizar(tester, card: _visa, motivos: motivos);

    expect(auth.cancelled, isFalse);
    expect(auth.savedPmId, 'pm_visa');
    expect(auth.usesSavedCard, isTrue);
    expect(auth.card?.last4, '4242');
    expect(motivos, ['Confirma o pagamento de €3,00']);
  });

  testWidgets('a folha recebe o valor e o cartão que vão ser cobrados',
      (tester) async {
    final valores = <double>[];
    final cartoes = <SavedCard>[];
    await _autorizar(tester,
        card: _visa,
        amountEur: 5.0,
        valoresVistosNaFolha: valores,
        cartoesVistosNaFolha: cartoes);

    // O "Pagar 5,00 €" tem de ser o valor a sério, não um placeholder.
    expect(valores, [5.0]);
    expect(cartoes.single.id, 'pm_visa');
  });

  testWidgets('"Outro método" → cancelado e NEM SEQUER pede biometria',
      (tester) async {
    final motivos = <String>[];
    final auth = await _autorizar(tester,
        card: _visa,
        escolha: EscolhaDoCartao.outroMetodo,
        motivos: motivos);

    expect(auth.cancelled, isTrue);
    expect(auth.savedPmId, isNull);
    expect(motivos, isEmpty, reason: 'sair do cartão não é autorizar nada');
  });

  testWidgets('"Trocar de cartão" → segue pelo PaymentSheet, sem pm_id',
      (tester) async {
    final motivos = <String>[];
    final auth = await _autorizar(tester,
        card: _visa,
        escolha: EscolhaDoCartao.trocarDeCartao,
        motivos: motivos);

    expect(auth.cancelled, isFalse);
    expect(auth.savedPmId, isNull);
    expect(auth.usesSavedCard, isFalse);
    expect(motivos, isEmpty,
        reason: 'introduzir um cartão novo já é prova suficiente');
  });

  testWidgets('biometria recusada depois de confirmar → não cobra',
      (tester) async {
    final auth = await _autorizar(tester, card: _visa, approves: false);

    expect(auth.cancelled, isTrue);
    expect(auth.savedPmId, isNull);
  });

  testWidgets('sem cartão guardado → nem folha nem biometria (PaymentSheet)',
      (tester) async {
    final motivos = <String>[];
    final valores = <double>[];
    final auth = await _autorizar(tester,
        card: null, motivos: motivos, valoresVistosNaFolha: valores);

    expect(auth.cancelled, isFalse);
    expect(auth.savedPmId, isNull);
    expect(auth.usesSavedCard, isFalse);
    expect(valores, isEmpty);
    expect(motivos, isEmpty, reason: 'cartão novo não pede biometria');
  });

  testWidgets(
      'aparelho sem biometria continua a pagar — mas passa pela folha na '
      'mesma', (tester) async {
    // Era aqui que se cobrava em silêncio: `if (!await _isCapable()) return
    // true` deixava passar sem perguntar nada a ninguém.
    final valores = <double>[];
    final auth = await _autorizar(tester,
        card: _visa,
        capable: false,
        approves: false,
        valoresVistosNaFolha: valores);

    expect(auth.cancelled, isFalse);
    expect(auth.savedPmId, 'pm_visa');
    expect(valores, [3.0], reason: 'o "Confirmar" humano tem de existir sempre');
  });

  testWidgets('aparelho sem biometria: "Outro método" continua a travar',
      (tester) async {
    final auth = await _autorizar(tester,
        card: _visa, capable: false, escolha: EscolhaDoCartao.outroMetodo);

    expect(auth.cancelled, isTrue);
  });
}
