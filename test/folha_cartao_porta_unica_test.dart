// PORQUE ESTE TESTE EXISTE (2026-10-03).
//
// O cartão no iPhone ficava só a rodar: com UIScene o plugin do Stripe não
// achava a janela (AppDelegate.window vazio) e `presentPaymentSheet()` nunca
// devolvia. Nenhum cartão de iPhone passou entre 21/09 e 02/10. O conserto
// tem duas metades, e este teste segura as duas:
//
//   1. `ios/Runner/AppDelegate.swift` tem de dar a janela do Flutter ao
//      AppDelegate e responder aos métodos nativos `prepararFolhaStripe` e
//      `folhaStripeVisivel` que `lib/services/folha_cartao.dart` usa;
//   2. ninguém pode voltar a chamar `Stripe.instance.presentPaymentSheet`
//      directamente — tem de passar por `apresentarFolhaCartao`, que tem o
//      tempo limite, confirma que a folha apareceu e grava o erro real.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('só folha_cartao.dart abre a folha do Stripe', () {
    final infractores = <String>[];
    for (final f in Directory('lib').listSync(recursive: true)) {
      if (f is! File || !f.path.endsWith('.dart')) continue;
      final nome = f.path.replaceAll('\\', '/');
      if (nome.endsWith('lib/services/folha_cartao.dart')) continue;
      final src = f.readAsStringSync();
      if (src.contains('Stripe.instance.presentPaymentSheet') ||
          src.contains('Stripe.instance.initPaymentSheet')) {
        infractores.add(nome);
      }
    }
    expect(infractores, isEmpty,
        reason: 'Estes ficheiros abrem a folha do Stripe por fora da porta '
            'única (usa apresentarFolhaCartao): $infractores');
  });

  test('a porta única tem tempo limite, vigia no iOS e registo da falha', () {
    final src = File('lib/services/folha_cartao.dart').readAsStringSync();
    expect(src, contains("'payment_sheet_timeout_seconds'"));
    expect(src, contains("'prepararFolhaStripe'"));
    expect(src, contains("'folhaStripeVisivel'"));
    expect(src, contains("'log_payment_failure'"));
    expect(src, contains('.timeout(limite)'));
  });

  test('AppDelegate liga a janela do Flutter ao Stripe (UIScene)', () {
    final swift = File('ios/Runner/AppDelegate.swift').readAsStringSync();
    expect(swift, contains('UIWindow.didBecomeKeyNotification'));
    expect(swift, contains('self?.window = janela'));
    expect(swift, contains('case "prepararFolhaStripe"'));
    expect(swift, contains('case "folhaStripeVisivel"'));
    // A cena continua ligada — o conserto não pode ser "desligar o UIScene".
    final plist = File('ios/Runner/Info.plist').readAsStringSync();
    expect(plist, contains('UIApplicationSceneManifest'));
  });
}
