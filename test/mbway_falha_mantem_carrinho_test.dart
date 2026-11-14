// Missão fechar-app-15-11, Bloco 5 — pagamentos MB WAY que falham.
//
// Medido a 14/11: 4 pedidos cancelados por `payment_failed` em 14 dias, todos
// MB WAY, cancelados 5 a 43 segundos depois de criados. O cliente via "Não foi
// possível iniciar o pagamento MBWay" sem motivo, o carrinho já tinha sido
// esvaziado (o pedido nasce antes do pagamento) e a app mandava-o para o
// início. Agora: diz porquê, o carrinho fica, e ele continua no ecrã do
// pagamento para tentar outra vez ou escolher outro meio.
//
// Só fluxo e texto: nenhum valor muda.
import 'dart:io';

import 'package:bora_app/utils/mensagem_mbway.dart';
import 'package:flutter_test/flutter_test.dart';

String _ler(String caminho) =>
    File(caminho).readAsStringSync().replaceAll(String.fromCharCode(13), '');

void main() {
  group('porque falhou, em português de Portugal', () {
    test('todas as frases dizem que o carrinho continua e o que fazer', () {
      final frases = [
        mensagemErroMbway(),
        mensagemErroMbway(status: 500, erro: 'Invalid phone number'),
        mensagemErroMbway(status: 400, erro: 'Amount too small (min 0.50 EUR)'),
        mensagemErroMbway(status: 409, erro: 'Order already processed'),
        mensagemErroMbway(status: 401, erro: 'unauthorized'),
        mensagemErroMbway(erro: 'SocketException: Failed host lookup'),
        mensagemErroMbway(status: 500, erro: 'qualquer coisa do servidor'),
        mbwayNaoConfirmado,
      ];
      for (final f in frases) {
        expect(f, contains('O teu carrinho continua aqui'), reason: f);
        expect(f, contains('escolhe outro meio de pagamento'), reason: f);
        // Nada de inglês nem de códigos a aparecer ao cliente.
        expect(f.toLowerCase(), isNot(contains('error')), reason: f);
        expect(f, isNot(contains('500')), reason: f);
      }
    });

    test('número que o MB WAY não aceita', () {
      expect(
        mensagemErroMbway(
            status: 500,
            erro: 'The phone number provided in billing_details is invalid'),
        startsWith('Esse número de telemóvel não foi aceite pelo MB WAY.'),
      );
    });

    test('valor abaixo do mínimo', () {
      expect(
        mensagemErroMbway(status: 400, erro: 'Amount too small (min 0.50 EUR)'),
        startsWith('O MB WAY só aceita pagamentos a partir de 0,50 €.'),
      );
    });

    test('sem internet (não houve resposta do servidor)', () {
      expect(
        mensagemErroMbway(erro: 'ClientException with SocketException'),
        startsWith('Não há ligação à internet'),
      );
    });

    test('sessão caída', () {
      expect(mensagemErroMbway(status: 401, erro: 'missing_token'),
          startsWith('A tua sessão terminou.'));
    });

    test('servidor com erro que não conhecemos: frase geral, sem o texto cru',
        () {
      final f = mensagemErroMbway(status: 500, erro: 'StripeAPIError: boom');
      expect(f,
          startsWith('O MB WAY não aceitou o pedido de pagamento neste momento.'));
      expect(f, isNot(contains('Stripe')));
    });

    test('não confirmado na app do banco', () {
      expect(mbwayNaoConfirmado,
          startsWith('O pagamento MB WAY não foi confirmado'));
    });
  });

  group('pela fonte: o fluxo', () {
    final ecra = _ler('lib/screens/payment_method_screen.dart');
    final carrinho = _ler('lib/stores/cart_store.dart');
    final servico = _ler('lib/services/payment_service.dart');

    test('MB WAY cria o pedido SEM esvaziar o carrinho', () {
      final ini = ecra.indexOf('case PaymentMethod.mbway:');
      final fim = ecra.indexOf('case PaymentMethod.cash:', ini);
      expect(ini, greaterThan(0));
      expect(fim, greaterThan(ini));
      final ramo = ecra.substring(ini, fim);
      expect(ramo, contains('manterCarrinho: true'));
      // Falhou: fica no ecrã do pagamento (duas saídas: ao iniciar e na espera).
      expect('ficarNoPagamento: true'.allMatches(ramo).length, 2);
      // Pagou: só então limpa o carrinho, antes de seguir.
      final limpar = ramo.indexOf('cartStore.limparDepoisDoPedido();');
      final seguir = ramo.indexOf('_consumeTokensAndNavigate(tokensUsed)');
      expect(limpar, greaterThan(0));
      expect(seguir, greaterThan(limpar));
      // A frase antiga, sem motivo, saiu.
      expect(ramo, isNot(contains('Não foi possível iniciar o pagamento MBWay.')));
    });

    test('ficar no pagamento = não voltar ao início', () {
      final ini = ecra.indexOf('Future<void> _bailOutAndCancel(');
      final corpo = ecra.substring(ini, ecra.indexOf('\n  }\n', ini));
      expect(corpo, contains('if (!ficarNoPagamento) {'));
      expect(corpo, contains("'reason': 'payment_failed'"),
          reason: 'o pedido órfão continua a ser cancelado sem custo');
    });

    test('quem não pede para manter continua a limpar como sempre', () {
      expect(carrinho, contains('bool manterCarrinho = false,'));
      expect(carrinho, contains('if (!manterCarrinho) limparDepoisDoPedido();'));
      final ini = carrinho.indexOf('void limparDepoisDoPedido() {');
      final corpo = carrinho.substring(ini, carrinho.indexOf('\n  }\n', ini));
      for (final linha in [
        '_errandSession = null;',
        '_tipCents = 0;',
        '_walletAppliedCents = 0;',
        'clearCart();',
      ]) {
        expect(corpo, contains(linha), reason: linha);
      }
    });

    test('o serviço guarda o motivo em vez de o deitar fora', () {
      expect(servico, contains('String? ultimoErroMbway;'));
      expect(servico, contains('on FunctionException catch (e)'));
      expect('ultimoErroMbway = mensagemErroMbway('.allMatches(servico).length,
          greaterThanOrEqualTo(4));
    });
  });
}
