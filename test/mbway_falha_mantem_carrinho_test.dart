// Missão fechar-app-15-11, Bloco 5 — pagamentos MB WAY que falham.
//
// Medido a 14/11: 4 pedidos cancelados por `payment_failed` em 14 dias, todos
// MB WAY, cancelados 5 a 43 segundos depois de criados. O cliente via "Não foi
// possível iniciar o pagamento MBWay" sem motivo, o carrinho já tinha sido
// esvaziado (o pedido nasce antes do pagamento) e a app mandava-o para o
// início. Agora: diz porquê, o carrinho fica, e ele continua no ecrã do
// pagamento para tentar outra vez ou escolher outro meio.
//
// Revisão 15/11 (achado 11): os testes provam COMPORTAMENTO, não texto do
// código. Com o servidor trocado por portas de mentira (as mesmas do teste do
// agendar), prova-se que:
//  * `manterCarrinho: true` mantém os itens e a hora marcada, e marca o pedido
//    MB WAY que ficou à espera; a 2.ª tentativa leva a mesma hora;
//  * `limparDepoisDoPedido()` limpa tudo (itens, hora, marca);
//  * pedido anterior pago (ou ainda não cancelado) → o carrinho limpa-se e
//    não se cria outro pedido; cancelado e por pagar → pode criar-se outro;
//  * a marca sobrevive a a app morrer e é lida ao repor o carrinho.
//
// Só fluxo e texto: nenhum valor muda.
import 'dart:convert';

import 'package:bora_app/models/order_model.dart';
import 'package:bora_app/stores/cart_store.dart';
import 'package:bora_app/utils/mensagem_mbway.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'agendar_mercados_test.dart'
    show
        MarcacaoFalsa,
        OrderStoreFalso,
        ServidorFalso,
        carrinhoDoContinente,
        estado,
        janela,
        leite,
        servidor;

/// O `finishOrder` do MB WAY, como o ecrã de pagamento o chama.
Future<bool> pedidoMbway(CartStore c, List<String> log) => c.finishOrder(
      OrderStoreFalso(log),
      paymentMethod: PaymentMethod.mbway,
      paymentStatus: PaymentStatus.pending,
      manterCarrinho: true,
    );

const _hora = 'preparar:continente:2026-11-03T10:00:00.000Z';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues(<String, Object>{}));
  tearDown(() => estado.reporParaTeste(ServidorFalso(ligado: false)));

  group('carrinho mantido enquanto o MB WAY não entra', () {
    test('manterCarrinho: ficam os itens, a hora marcada e a marca do pedido',
        () async {
      final log = <String>[];
      await servidor(ServidorFalso(), MarcacaoFalsa(log, horaGravada: janela.instante));
      final c = await carrinhoDoContinente(fechada: true);
      c.addItem(leite());
      estado.escolher('continente', janela);

      expect(await pedidoMbway(c, log), isTrue);

      expect(log, [_hora, 'createOrder', 'hora:pedido-1']);
      expect(c.items, hasLength(1), reason: 'o pagamento ainda não entrou');
      expect(estado.escolha, janela,
          reason: 'sem a hora, a 2.ª tentativa sairia "para agora"');
      expect(estado.escolhaPara('continente'), isTrue);
      expect(c.mbwayPendenteId, 'pedido-1');
    });

    test('a 2.ª tentativa leva a mesma hora marcada', () async {
      final log = <String>[];
      await servidor(ServidorFalso(), MarcacaoFalsa(log, horaGravada: janela.instante));
      final c = await carrinhoDoContinente(fechada: true);
      c.addItem(leite());
      estado.escolher('continente', janela);

      expect(await pedidoMbway(c, log), isTrue);
      expect(await pedidoMbway(c, log), isTrue);

      expect(log.where((l) => l.startsWith('preparar:')).toList(), [_hora, _hora]);
      expect(log.where((l) => l == 'createOrder'), hasLength(2));
      expect(c.items, hasLength(1));
    });

    test('limparDepoisDoPedido limpa itens, hora marcada e a marca', () async {
      final log = <String>[];
      await servidor(ServidorFalso(), MarcacaoFalsa(log, horaGravada: janela.instante));
      final c = await carrinhoDoContinente(fechada: true);
      c.addItem(leite());
      estado.escolher('continente', janela);
      expect(await pedidoMbway(c, log), isTrue);

      c.limparDepoisDoPedido();

      expect(c.items, isEmpty);
      expect(estado.escolha, isNull);
      expect(c.mbwayPendenteId, isNull);
    });

    test('sem manterCarrinho (dinheiro) limpa como sempre e não marca nada',
        () async {
      final log = <String>[];
      await servidor(ServidorFalso(), MarcacaoFalsa(log, horaGravada: janela.instante));
      final c = await carrinhoDoContinente(fechada: true);
      c.addItem(leite());
      estado.escolher('continente', janela);

      expect(
          await c.finishOrder(OrderStoreFalso(log),
              paymentMethod: PaymentMethod.cash, paymentStatus: PaymentStatus.paid),
          isTrue);

      expect(c.items, isEmpty);
      expect(estado.escolha, isNull);
      expect(c.mbwayPendenteId, isNull);
    });
  });

  group('pedido MB WAY anterior (achado 1: não pagar duas vezes)', () {
    Future<CartStore> carrinhoComMbwayAEspera(List<String> log) async {
      await servidor(ServidorFalso(), MarcacaoFalsa(log));
      final c = await carrinhoDoContinente();
      c.addItem(leite());
      expect(await pedidoMbway(c, log), isTrue);
      expect(c.mbwayPendenteId, 'pedido-1');
      return c;
    }

    test('pago na app do banco depois de cancelado: limpa e NÃO cria outro',
        () async {
      final log = <String>[];
      final c = await carrinhoComMbwayAEspera(log);
      final lidos = <String>[];
      c.lerPedidoParaTeste = (id) async {
        lidos.add(id);
        // O webhook reativa o pedido cancelado quando o dinheiro entra.
        return {'status': 'created', 'payment_status': 'paid'};
      };

      expect(await c.verificarMbwayPendente(), PedidoMbwayAnterior.pago);
      expect(lidos, ['pedido-1']);
      expect(c.items, isEmpty, reason: 'o carrinho já virou o pedido pago');
      expect(c.mbwayPendenteId, isNull);

      // Mesmo que alguém tente criar outro, já não há carrinho para isso.
      log.clear();
      expect(await pedidoMbway(c, log), isFalse);
      expect(log, isNot(contains('createOrder')));
    });

    test('ainda não cancelado (cancelamento falhou): limpa e não cria outro',
        () async {
      final log = <String>[];
      final c = await carrinhoComMbwayAEspera(log);
      c.lerPedidoParaTeste =
          (_) async => {'status': 'created', 'payment_status': 'pending'};

      expect(await c.verificarMbwayPendente(), PedidoMbwayAnterior.ativo);
      expect(c.items, isEmpty);
    });

    test('cancelado e por pagar: o carrinho fica e pode criar-se outro', () async {
      final log = <String>[];
      final c = await carrinhoComMbwayAEspera(log);
      c.lerPedidoParaTeste =
          (_) async => {'status': 'cancelled', 'payment_status': 'pending'};

      expect(await c.verificarMbwayPendente(), PedidoMbwayAnterior.morto);
      expect(c.items, hasLength(1));

      log.clear();
      expect(await pedidoMbway(c, log), isTrue);
      expect(log, contains('createOrder'));
    });

    test('sem resposta do servidor: não mexe no carrinho', () async {
      final log = <String>[];
      final c = await carrinhoComMbwayAEspera(log);
      c.lerPedidoParaTeste = (_) async => throw Exception('SocketException');

      expect(await c.verificarMbwayPendente(), PedidoMbwayAnterior.semResposta);
      expect(c.items, hasLength(1));
      expect(c.mbwayPendenteId, 'pedido-1');
    });

    test('sem pedido à espera não pergunta nada ao servidor', () async {
      final c = await carrinhoDoContinente();
      c.addItem(leite());
      var perguntou = false;
      c.lerPedidoParaTeste = (_) async {
        perguntou = true;
        return null;
      };
      expect(await c.verificarMbwayPendente(), PedidoMbwayAnterior.nenhum);
      expect(perguntou, isFalse);
    });

    test('estado do pedido: pago manda sempre; cancelado/recusado é morto', () {
      expect(estadoDoPedidoMbway(null), PedidoMbwayAnterior.morto);
      expect(estadoDoPedidoMbway({'status': 'cancelled', 'payment_status': 'paid'}),
          PedidoMbwayAnterior.pago);
      expect(estadoDoPedidoMbway({'status': 'rejected', 'payment_status': 'pending'}),
          PedidoMbwayAnterior.morto);
      expect(estadoDoPedidoMbway({'status': 'preparing', 'payment_status': 'pending'}),
          PedidoMbwayAnterior.ativo);
    });
  });

  group('a app morreu enquanto o cliente aprovava no banco (achado 2)', () {
    // O carrinho reposto pergunta pela configuração do agendar: porta falsa.
    setUp(() => estado.reporParaTeste(ServidorFalso(ligado: false)));

    Map<String, Object> guardado() => {
          'bora_cart_v1': jsonEncode({
            'items': [
              {'productId': 'leite', 'name': 'Leite', 'price': 0.89, 'quantity': 2}
            ],
            'serviceType': 'storeShopping',
            'isPartnerStore': false,
            'vendorName': 'Continente',
            'mbwayPendenteId': 'pedido-velho',
          }),
        };

    test('pagamento entrou: o carrinho reposto limpa-se sozinho', () async {
      SharedPreferences.setMockInitialValues(guardado());
      final lidos = <String>[];
      final c = CartStore()
        ..lerParceiraParaTeste = ((_, __) async => null)
        ..lerPedidoParaTeste = (id) async {
          lidos.add(id);
          return {'status': 'preparing', 'payment_status': 'paid'};
        };
      await Future<void>.delayed(const Duration(milliseconds: 50));

      expect(lidos, ['pedido-velho']);
      expect(c.items, isEmpty);
      expect(c.mbwayPendenteId, isNull);
    });

    test('cancelado e por pagar: o carrinho reposto fica com a marca', () async {
      SharedPreferences.setMockInitialValues(guardado());
      final c = CartStore()
        ..lerParceiraParaTeste = ((_, __) async => null)
        ..lerPedidoParaTeste =
            (_) async => {'status': 'cancelled', 'payment_status': 'pending'};
      await Future<void>.delayed(const Duration(milliseconds: 50));

      expect(c.items, hasLength(1));
      expect(c.mbwayPendenteId, 'pedido-velho');
    });
  });

  group('porque falhou, em português de Portugal', () {
    test('as falhas dizem que o carrinho continua e para recusar o pedido antigo',
        () {
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
        expect(f, contains('recusa-o lá'), reason: f);
        expect(f, contains('MB WAY'), reason: f);
        expect(f, isNot(contains('MBWay')), reason: f);
        // Nada de inglês nem de códigos a aparecer ao cliente.
        expect(f.toLowerCase(), isNot(contains('error')), reason: f);
        expect(f, isNot(contains('500')), reason: f);
        expect(eMbwayDesligado(f), isFalse, reason: f);
      }
    });

    test('MB WAY desligado (503): só "escolhe outro meio", sem "tenta outra vez"',
        () {
      for (final f in [
        mensagemErroMbway(status: 503, erro: 'mbway_disabled'),
        mensagemErroMbway(erro: 'mbway_disabled'),
      ]) {
        expect(f, mbwayDesligado);
        expect(eMbwayDesligado(f), isTrue);
        expect(f, contains('escolhe outro meio de pagamento'));
        expect(f, isNot(contains('tenta outra vez')));
      }
    });

    test('409 já não se contradiz', () {
      expect(mensagemErroMbway(status: 409, erro: 'Order already processed'),
          startsWith('Este pedido já não estava à espera de pagamento'));
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
}
