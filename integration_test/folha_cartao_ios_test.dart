// Prova no simulador iOS: a folha do cartão (Stripe) APARECE mesmo.
//
// 2026-10-03 — o defeito do iPhone era a folha nunca aparecer (UIScene sem
// AppDelegate.window), ficando o botão a rodar para sempre. Este teste corre
// dentro da app real (Runner com SceneDelegate) e verifica, pela parte nativa
// (`folhaStripeVisivel`), que a folha foi mesmo apresentada.
//
// Só usa o modo de TESTE do Stripe — nunca a chave live:
//   --dart-define=STRIPE_TEST_PUBLISHABLE_KEY=pk_test_...
//   --dart-define=STRIPE_TEST_SECRET_KEY=sk_test_...
// Sem as duas chaves o teste diz "NAO PROVADO" e falha — não finge que passou.
//
// O que NÃO prova: escrever o cartão 4242 / 3D Secure 4000 0027 6000 3184
// dentro da folha. A folha é UI nativa do Stripe e o integration_test do
// Flutter não escreve nela; isso precisa de XCUITest (fica como continuação).
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_stripe/flutter_stripe.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

const _pkTeste = String.fromEnvironment('STRIPE_TEST_PUBLISHABLE_KEY');
const _skTeste = String.fromEnvironment('STRIPE_TEST_SECRET_KEY');
const _canal = MethodChannel('pt.boraapp.bora/native');

Future<String> _criarPaymentIntentDeTeste() async {
  final http = HttpClient();
  try {
    final pedido = await http
        .postUrl(Uri.parse('https://api.stripe.com/v1/payment_intents'));
    pedido.headers.set('Authorization', 'Bearer $_skTeste');
    pedido.headers.contentType =
        ContentType('application', 'x-www-form-urlencoded');
    pedido.write('amount=500&currency=eur&payment_method_types[]=card');
    final resposta = await pedido.close();
    final corpo = await resposta.transform(utf8.decoder).join();
    if (resposta.statusCode != 200) {
      throw StateError('Stripe (teste) devolveu ${resposta.statusCode}: $corpo');
    }
    return (jsonDecode(corpo) as Map<String, dynamic>)['client_secret'] as String;
  } finally {
    http.close();
  }
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('iOS: a folha do cartão aparece (não fica a rodar)',
      (tester) async {
    if (!_pkTeste.startsWith('pk_test_') || !_skTeste.startsWith('sk_test_')) {
      fail('NAO PROVADO: faltam STRIPE_TEST_PUBLISHABLE_KEY/STRIPE_TEST_SECRET_KEY '
          '(modo de teste). Nunca se usa a chave live aqui.');
    }
    Stripe.publishableKey = _pkTeste;
    Stripe.urlScheme = 'pt.boraapp.bora';
    await Stripe.instance.applySettings();

    await tester.pumpWidget(const MaterialApp(
        home: Scaffold(body: Center(child: Text('prova folha cartao')))));
    await tester.pump(const Duration(seconds: 1));

    final segredo = await _criarPaymentIntentDeTeste();
    final pronta = await _canal.invokeMethod<bool>('prepararFolhaStripe');
    expect(pronta, isTrue, reason: 'AppDelegate sem janela do Flutter');

    await Stripe.instance.initPaymentSheet(
      paymentSheetParameters: SetupPaymentSheetParameters(
        paymentIntentClientSecret: segredo,
        merchantDisplayName: 'BORA APP (teste)',
      ),
    );
    // Não se espera pelo resultado: ninguém vai escrever o cartão.
    // ignore: unawaited_futures
    Stripe.instance.presentPaymentSheet();

    var apareceu = false;
    for (var i = 0; i < 40 && !apareceu; i++) {
      await tester.pump(const Duration(milliseconds: 500));
      apareceu = await _canal.invokeMethod<bool>('folhaStripeVisivel') ?? false;
    }
    // ignore: avoid_print
    print('[folha-cartao-ios] folha visivel = $apareceu');
    expect(apareceu, isTrue,
        reason: 'A folha do Stripe não apareceu em 20 s — o defeito voltou.');
  });
}
