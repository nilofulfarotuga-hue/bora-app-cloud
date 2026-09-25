import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// [Missão dinheiro 06/09] A segunda chamada não pode cobrar nem devolver
/// outra vez.
///
/// Os três buracos diagnosticados ontem estão tapados no SERVIDOR (verificado
/// por leitura do que está mesmo no ar, não do repositório):
///
///  1. `tvde-plan-payment` v9 — chave de idempotência no pacote ida-e-volta e
///     no plano, cartão e MB Way. Sem ela, um pedido repetido criava um
///     segundo PaymentIntent; no MB Way, um segundo pedido no telemóvel.
///  2. `cleaning-checkout` v6 — o estorno pergunta primeiro à Stripe se já
///     estornou e usa chave fixa por reserva. Antes, duas chamadas devolviam
///     o dinheiro duas vezes.
///  3. `create_cleaning_booking` — chave de idempotência, trava de
///     concorrência e recuperação do duplicado. Antes, um timeout podia criar
///     duas reservas.
///
/// **O que estes testes guardam é o lado do APP**, que é onde a corrente
/// partia: uma chave de idempotência só serve se a segunda tentativa mandar a
/// MESMA chave. Um id novo a cada toque não protege nada — e é pior do que não
/// mandar nenhum, porque desliga o recurso do servidor (a janela por
/// utilizador+valor). Foi exactamente isso que estava a acontecer no pacote
/// ida-e-volta.
void main() {
  String fonte(String caminho) => File(caminho).readAsStringSync();

  group('pacote ida-e-volta — a chave é da COMPRA, não do toque', () {
    final tela =
        fonte('lib/screens/client/tvde/tvde_request_ride_screen.dart');

    test('o id NÃO nasce dentro do método de pagamento', () {
      // A regressão exacta: `final requestId = const Uuid().v4();` dentro de
      // `_solicitarRoundtripOnline`. Cada toque gerava chave nova, e a Stripe
      // criava um PaymentIntent por toque.
      expect(
        RegExp(r'final\s+requestId\s*=\s*const\s+Uuid\(\)\.v4\(\)')
            .hasMatch(tela),
        isFalse,
        reason: 'o id da compra voltou a nascer a cada chamada — dois toques '
            'passam a ser duas cobranças, e o recurso do servidor (janela de '
            '10 min) fica desligado porque o app manda uma chave sempre nova',
      );
    });

    test('o id vive no ecrã e é reutilizado enquanto a compra é a mesma', () {
      expect(tela, contains('_idDaCompraRoundtrip'));
      expect(tela, contains('_idDaCompraRoundtripAtual'));
      // `??=` é o que garante a reutilização: só cria se ainda não houver.
      expect(RegExp(r'_idDaCompraRoundtrip\s*\?\?=').hasMatch(tela), isTrue,
          reason: 'sem o `??=` cada leitura criaria um id novo');
    });

    test('a chave é renovada quando a compra fecha', () {
      // Senão, uma segunda compra igual reusava a chave e a Stripe devolvia o
      // PaymentIntent antigo — a segunda não era cobrada de todo.
      expect(RegExp(r'_idDaCompraRoundtrip\s*=\s*null').hasMatch(tela), isTrue,
          reason: 'a chave tem de sair de cena quando a compra completa');
    });

    test('a chave é renovada quando o preço muda', () {
      // A Stripe REJEITA a mesma chave com um valor diferente. Sem renovar,
      // mudar a rota depois de uma tentativa dava erro em vez de compra nova.
      final i = tela.indexOf('_roundtripPriceCents = (quote');
      expect(i, greaterThan(-1), reason: 'o sítio onde o preço é actualizado '
          'mudou de forma — este teste precisa de ser reapontado');
      final bloco = tela.substring(i, (i + 800).clamp(0, tela.length));
      expect(bloco, contains('_idDaCompraRoundtrip = null'),
          reason: 'mudar o preço tem de limpar a chave, senão a Stripe rejeita '
              'a reutilização com um valor diferente');
    });

    test('a chave chega mesmo aos dois caminhos de pagamento', () {
      // `await store.` de propósito: sem isso o `indexOf` apanhava a primeira
      // menção ao nome do método, que está num COMENTÁRIO, e o teste falhava
      // com o código certo.
      for (final metodo
          in ['createRoundtripPaymentMbway', 'createRoundtripPayment(']) {
        final i = tela.indexOf('await store.$metodo');
        expect(i, greaterThan(-1),
            reason: 'a chamada a $metodo desapareceu do ecrã');
        final chamada = tela.substring(i, (i + 200).clamp(0, tela.length));
        expect(chamada, contains('requestId: requestId'),
            reason: '$metodo deixou de levar a chave de idempotência');
      }
    });
  });

  group('planos TVDE — já estavam certos, e têm de continuar', () {
    final tela = fonte('lib/screens/client/tvde/tvde_plans_screen.dart');

    test('o id é guardado por plano, não gerado a cada toque', () {
      // `putIfAbsent` é o que faz o segundo toque reusar a chave do primeiro.
      expect(RegExp(r'_idDaCompra\.putIfAbsent').hasMatch(tela), isTrue,
          reason: 'o ecrã dos planos perdeu a reutilização da chave');
    });

    test('a chave vai nos dois caminhos, cartão e MB Way', () {
      expect(tela, contains('requestId: requestId'));
      expect(RegExp(r'requestId:\s*requestId').allMatches(tela).length,
          greaterThanOrEqualTo(2),
          reason: 'faltou a chave num dos caminhos de pagamento');
    });
  });

  group('reserva de limpeza — a chave tem de sair do app', () {
    final store = fonte('lib/stores/cleaning_store.dart');

    test('o app manda `p_idempotency_key` ao criar a reserva', () {
      // A RPC aceita a chave e recupera o duplicado. Mas se o app não a
      // mandar, resta o recurso dos 15 minutos por assinatura do pedido —
      // mais fraco, e o mecanismo que repete em timeout deixa de estar coberto.
      expect(store, contains('p_idempotency_key'),
          reason: 'a reserva de limpeza deixou de mandar a chave; um timeout '
              'volta a poder criar duas reservas');
    });

    test('a chave da marcação existe e é estável', () {
      expect(store, contains('chaveDaMarcacao'));
    });
  });

  group('o contrato do store TVDE mantém a chave opcional mas usada', () {
    final store = fonte('lib/stores/tvde_store.dart');

    test('os quatro caminhos de pagamento aceitam e reencaminham a chave', () {
      // Se um deles deixar de reencaminhar, o servidor cai na janela de 10 min
      // — que ainda protege, mas com menos precisão.
      expect(RegExp(r"'request_id':\s*requestId").allMatches(store).length, 4,
          reason: 'os quatro caminhos (plano cartão, plano MB Way, pacote '
              'cartão, pacote MB Way) têm de reencaminhar a chave');
    });
  });
}
