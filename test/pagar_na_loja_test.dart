// pagar-na-loja (10/11/2026, business_rules 2.4.2).
//
// Caso real: pedido 6d38f5e5 (Boom! Burger, dinheiro). O ecrã do
// estafeta dizia "RECEBER 19,71 € — entregar ao parceiro"; a loja cobrou-lhe
// 13,80 ao balcão e ele não sabia se estava certo. Agora o SERVIDOR diz o que o
// estafeta faz na loja (orders.loja_pagamento_estado + loja_pagar_valor) e a app
// só mostra, em letra grande. Estes testes fixam o que se mostra nos 5 casos:
//   R1 app + loja parceira + dinheiro  → paga 13,80 à loja, cobra 19,71
//   R2 app + loja parceira + MB Way    → não paga nem cobra
//   R3 loja não parceira               → faz a compra (como sempre)
//   R4 parceiro chama estafeta (2.4.1) → banner de sempre
//   R5 ir buscar (takeaway)            → nada (não há estafeta)
// As contas do dinheiro (fecho do estafeta e da loja) foram provadas no
// servidor em transacção desfeita (e2e_log pagar-na-loja-2026-11-10).
import 'package:bora_app/models/cart_item.dart';
import 'package:bora_app/models/order_model.dart';
import 'package:bora_app/services/notification_service.dart'
    show textosNotificacaoOferta;
import 'package:bora_app/widgets/partner/aviso_pagamento_estafeta.dart';
import 'package:bora_app/widgets/payments/loja_pagamento.dart';
import 'package:flutter_test/flutter_test.dart';

OrderModel _pedido({
  String? estado,
  double pagarLoja = 0,
  PaymentMethod pagamento = PaymentMethod.cash,
  OrderStatus status = OrderStatus.driverAccepted,
  OrderServiceType servico = OrderServiceType.restaurant,
  bool parceira = true,
  double total = 19.71,
  double? cashTotalDue = 19.71,
  int divida = 0,
  List<CartItem>? itens,
  double? pagoDeFacto,
}) {
  return OrderModel(
    id: '6d38f5e5-0000-4000-8000-00000000r1r1',
    total: total,
    cashTotalDue: cashTotalDue,
    serviceType: servico,
    orderType: parceira
        ? OrderType.partnerRestaurant
        : OrderType.nonPartnerPurchase,
    isPartnerStore: parceira,
    status: status,
    paymentMethod: pagamento,
    debtCollectedCents: divida,
    lojaPagamentoEstado: estado,
    lojaPagarValor: pagarLoja,
    items: itens,
    finalPurchaseValue: pagoDeFacto,
    isPurchaseFinalized: pagoDeFacto != null,
    vendorName: 'Boom! Burger',
  );
}

void main() {
  group('o modelo lê o que o servidor gravou', () {
    test('loja_pagamento_estado e loja_pagar_valor (número ou texto)', () {
      final base = <String, dynamic>{
        'id': 'x',
        'status': 'driverAccepted',
        'service_type': 'restaurant',
        'payment_method': 'cash',
        'price': 19.71,
      };
      final a = OrderModel.fromSupabase({
        ...base,
        'loja_pagamento_estado': 'pagar_loja',
        'loja_pagar_valor': 13.8,
      });
      expect(a.lojaPagamentoEstado, 'pagar_loja');
      expect(a.lojaPagarValor, 13.8);
      expect(a.lojaPagamento, LojaPagamento.pagarLoja);

      final b = OrderModel.fromSupabase({
        ...base,
        'loja_pagamento_estado': 'ja_pago',
        'loja_pagar_valor': '0.00',
      });
      expect(b.lojaPagamento, LojaPagamento.jaPago);
      expect(b.lojaPagarValor, 0);

      // Pedido antigo, sem as colunas: nada muda (null / 0).
      final c = OrderModel.fromSupabase(base);
      expect(c.lojaPagamento, isNull);
      expect(c.lojaPagarValor, 0);
    });
  });

  group('R1 — app + loja parceira + dinheiro (o caso real de 10/11)', () {
    final naLoja = _pedido(estado: 'pagar_loja', pagarLoja: 13.80);

    test('na loja: PAGA 13,80 € À LOJA, em laranja, com a explicação', () {
      final c = FaixaDinheiroEstafeta.conteudo(naLoja)!;
      expect(c.titulo, 'PAGA 13,80 € À LOJA');
      expect(c.sub,
          'Preço de balcão. É só isto que pagas. Depois cobras ao cliente.');
    });

    test('no cliente: COBRA 19,71 € AO CLIENTE (o total do servidor)', () {
      final c = FaixaDinheiroEstafeta.conteudo(
          _pedido(estado: 'pagar_loja', pagarLoja: 13.80, status: OrderStatus.onTheWay))!;
      expect(c.titulo, 'COBRA 19,71 € AO CLIENTE');
      expect(c.sub, isNull);
    });

    test('dívida antiga entra no que se cobra e diz-se quanto', () {
      final c = FaixaDinheiroEstafeta.conteudo(_pedido(
          estado: 'pagar_loja',
          pagarLoja: 13.80,
          status: OrderStatus.pickedUp,
          divida: 150))!;
      expect(c.titulo, 'COBRA 21,21 € AO CLIENTE');
      expect(c.sub, 'inclui +1,50 € de dívida anterior');
    });

    test('oferta e lista: "Pagas 13,80 € na loja · Cobras 19,71 €"', () {
      expect(linhaDinheiroEstafeta(naLoja),
          'Pagas 13,80 € na loja · Cobras 19,71 €');
    });

    test('notificação: a frase vem pronta do servidor e aparece no aviso', () {
      final t = textosNotificacaoOferta(
        vendorName: 'Boom! Burger',
        total: '19.71',
        distanceKm: '1.8',
        driverEarnings: '4.24',
        lojaLinha: 'Pagas 13,80 € na loja · Cobras 19,71 €',
      );
      expect(t.corpo,
          'Boom! Burger • Pagas 13,80 € na loja · Cobras 19,71 € • 1.8km');
      expect(t.grande, contains('💵 Pagas 13,80 € na loja · Cobras 19,71 €'));
      expect(t.grande, contains('Ganho: €4.24'));
    });

    test('parceiro: antes da recolha diz quanto recebe; depois, que recebeu',
        () {
      expect(AvisoPagamentoEstafeta.texto(naLoja),
          'O estafeta paga-te 13,80 € em dinheiro quando vier buscar o pedido.');
      expect(
          AvisoPagamentoEstafeta.texto(_pedido(
              estado: 'pagar_loja',
              pagarLoja: 13.80,
              status: OrderStatus.delivered,
              pagoDeFacto: 13.80)),
          'Recebeste 13,80 € em mão do estafeta na recolha.');
    });
  });

  group('R2 — app + loja parceira + cartão/MB Way', () {
    final p = _pedido(
        estado: 'ja_pago', pagamento: PaymentMethod.mbway, cashTotalDue: null);

    test('na loja: JÁ ESTÁ PAGO, em verde', () {
      expect(FaixaDinheiroEstafeta.conteudo(p)!.titulo,
          'JÁ ESTÁ PAGO — não pagas nada na loja');
    });
    test('no cliente: não cobra nada', () {
      final c = FaixaDinheiroEstafeta.conteudo(_pedido(
          estado: 'ja_pago',
          pagamento: PaymentMethod.mbway,
          cashTotalDue: null,
          status: OrderStatus.onTheWay))!;
      expect(c.titulo, 'JÁ ESTÁ PAGO — não cobres nada');
    });
    test('oferta e parceiro', () {
      expect(linhaDinheiroEstafeta(p), 'Já pago — não pagas nem cobras nada');
      expect(AvisoPagamentoEstafeta.texto(p),
          'Já pago pela app — não cobres nada ao estafeta. Recebes no fecho semanal.');
    });
  });

  group('R3 — loja não parceira: faz a compra, como sempre', () {
    final p = _pedido(
      estado: 'fazer_compra',
      parceira: false,
      servico: OrderServiceType.storeShopping,
      itens: [
        CartItem(productId: 'a', name: 'Leite', price: 1.15, basePrice: 1.00, quantity: 2),
        CartItem(productId: 'b', name: 'Pão', price: 2.30, quantity: 1),
      ],
    );
    test('na loja: TENS DE FAZER A COMPRA com o valor estimado de sempre', () {
      final c = FaixaDinheiroEstafeta.conteudo(p)!;
      expect(c.titulo, 'TENS DE FAZER A COMPRA');
      // 2 × 1,00 (preço da loja) + 2,30 / 1,15 = 4,00 €
      expect(c.sub,
          'Paga na caixa e tira foto do talão. Valor estimado: 4,00 €');
      expect(estimativaCompraLoja(p), closeTo(4.0, 0.0001));
    });
    test('oferta: "Fazes a compra"; o parceiro não vê aviso', () {
      expect(linhaDinheiroEstafeta(p), 'Fazes a compra');
      expect(AvisoPagamentoEstafeta.texto(p), isNull);
    });
  });

  group('R4 — parceiro chama estafeta: fica como estava', () {
    final p = _pedido(estado: 'parceiro_chamou', total: 12.83, cashTotalDue: null);
    test('na loja: o banner de sempre, com o mesmo texto', () {
      final c = FaixaDinheiroEstafeta.conteudo(p)!;
      expect(c.titulo, 'PAGAR 12,83 € AO ESTABELECIMENTO');
      expect(c.sub, startsWith('O cliente paga-te depois o mesmo valor'));
    });
    test('parceiro: sem aviso novo', () {
      expect(AvisoPagamentoEstafeta.texto(p), isNull);
    });
  });

  group('R5 — ir buscar (takeaway): não há estafeta', () {
    final p = _pedido(
        estado: 'ir_buscar',
        servico: OrderServiceType.takeaway,
        status: OrderStatus.preparing);
    test('nem faixa, nem linha, nem aviso novo', () {
      expect(FaixaDinheiroEstafeta.conteudo(p), isNull);
      expect(linhaDinheiroEstafeta(p), isNull);
      expect(AvisoPagamentoEstafeta.texto(p), isNull);
    });
  });

  group('pedidos sem loja e servidor antigo', () {
    test('Favor: a folha do Favor manda, não há faixa', () {
      final p = _pedido(estado: null, servico: OrderServiceType.errand);
      expect(FaixaDinheiroEstafeta.conteudo(p), isNull);
    });
    test('sem a frase do servidor, a notificação fica como era', () {
      final t = textosNotificacaoOferta(
          vendorName: 'Loja', total: '9.00', distanceKm: '2', driverEarnings: '4.00');
      expect(t.corpo, 'Loja • €9.00 • 2km');
    });
  });
}
