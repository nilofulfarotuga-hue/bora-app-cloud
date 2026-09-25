// Prende a regra que custou uma cliente a 22/09/2026.
//
// A Priscila Prates registou-se pelo site às 13:29 num iPhone, pediu uma
// corrida às 13:34 e nunca lhe apareceu onde pôr o cartão. O Safari bloqueou a
// janela nova; o código lia `popup.closed` dentro de um `try` e, no `catch`,
// concluía "cross-origin, logo está viva". A app ficou à espera para sempre de
// uma janela que nunca existiu e a corrida morreu em `payment_failed`.
//
// Duas regras saem daqui, e são estes testes que as prendem:
//   1. janela bloqueada (ou telemóvel) = caminho do mesmo separador;
//   2. nunca esperar para sempre.

import 'package:flutter_test/flutter_test.dart';

import 'package:bora_app/services/web_checkout_regras.dart';

void main() {
  group('por onde sai o pagamento', () {
    test('telemóvel nunca tenta a janela nova', () {
      expect(
        escolherCaminhoDoCheckout(
            ehBrowserDeTelemovel: true, janelaAbriu: false),
        CaminhoDoCheckout.mesmoSeparador,
      );
      // Mesmo que por milagre a janela abrisse, no telemóvel não se usa.
      expect(
        escolherCaminhoDoCheckout(
            ehBrowserDeTelemovel: true, janelaAbriu: true),
        CaminhoDoCheckout.mesmoSeparador,
      );
    });

    test('janela bloqueada no computador → mesmo separador', () {
      expect(
        escolherCaminhoDoCheckout(
            ehBrowserDeTelemovel: false, janelaAbriu: false),
        CaminhoDoCheckout.mesmoSeparador,
      );
    });

    test('computador com janela aberta → janela nova', () {
      expect(
        escolherCaminhoDoCheckout(
            ehBrowserDeTelemovel: false, janelaAbriu: true),
        CaminhoDoCheckout.janelaNova,
      );
    });
  });

  group('a espera tem sempre fim', () {
    PassoDaEspera passo({
      bool deuSinal = true,
      bool aPagar = false,
      bool janelaFechada = false,
      Duration desdeAbertura = Duration.zero,
      Duration desdeUltimoSinal = Duration.zero,
    }) =>
        avaliarEspera(
          deuSinal: deuSinal,
          aPagar: aPagar,
          janelaFechada: janelaFechada,
          desdeAbertura: desdeAbertura,
          desdeUltimoSinal: desdeUltimoSinal,
        );

    test('sem sinal dentro do prazo → continua à espera', () {
      expect(
        passo(deuSinal: false, desdeAbertura: const Duration(milliseconds: 900)),
        PassoDaEspera.continuar,
      );
    });

    test('sem sinal passado o prazo → trata como bloqueada', () {
      expect(
        passo(deuSinal: false, desdeAbertura: const Duration(seconds: 2)),
        PassoDaEspera.tratarComoBloqueada,
      );
    });

    test(
        'janela que nunca deu sinal e parece fechada NÃO é cancelamento do '
        'cliente — é bloqueio', () {
      // A diferença importa: dizer "cancelaste" a quem nunca viu nada é
      // mentira, e foi o que a cliente levou.
      expect(
        passo(
          deuSinal: false,
          janelaFechada: true,
          desdeAbertura: const Duration(seconds: 2),
        ),
        PassoDaEspera.tratarComoBloqueada,
      );
    });

    test('janela viva fechada no X → cancelamento', () {
      expect(passo(janelaFechada: true), PassoDaEspera.cancelar);
    });

    test('silêncio a mais antes de pagar → desiste com mensagem', () {
      expect(
        passo(desdeUltimoSinal: const Duration(seconds: 91)),
        PassoDaEspera.desistirPorSilencio,
      );
      // Dentro do tecto continua à espera — o batimento é de 10 em 10 s.
      expect(
        passo(desdeUltimoSinal: const Duration(seconds: 30)),
        PassoDaEspera.continuar,
      );
    });

    test('depois do "Pagar" o tecto estica: 3-D Secure no banco demora', () {
      // Sem isto matávamos um pagamento a sério aos 90 s, com o cliente a
      // escrever o código do SMS.
      expect(
        passo(aPagar: true, desdeUltimoSinal: const Duration(minutes: 5)),
        PassoDaEspera.continuar,
      );
      // Mas nem esse caminho é infinito.
      expect(
        passo(aPagar: true, desdeUltimoSinal: const Duration(minutes: 11)),
        PassoDaEspera.desistirPorSilencio,
      );
    });

    test('caso normal: viva, em silêncio curto → continua', () {
      expect(passo(), PassoDaEspera.continuar);
    });
  });
}
