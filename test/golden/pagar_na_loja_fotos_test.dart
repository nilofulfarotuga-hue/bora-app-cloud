import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:bora_app/models/cart_item.dart';
import 'package:bora_app/models/order_model.dart';
import 'package:bora_app/widgets/admin/admin_pago_loja_section.dart';
import 'package:bora_app/widgets/partner/aviso_pagamento_estafeta.dart';
import 'package:bora_app/widgets/payments/loja_pagamento.dart';

import 'fabrica_de_fotos.dart';

/// pagar-na-loja (10/11/2026): fotos dos ecrãs novos, com os números do pedido
/// de 10/11 (Boom! Burger: balcão 13,80 €, cliente 19,71 €). O mapa do
/// estafeta é desenhado a cinzento (o Google Maps não corre no flutter test);
/// a faixa fica no mesmo sítio do ecrã real (topo, sempre à vista).
OrderModel _p({
  required String estado,
  OrderStatus status = OrderStatus.driverAccepted,
  PaymentMethod pagamento = PaymentMethod.cash,
  bool parceira = true,
  OrderServiceType servico = OrderServiceType.restaurant,
  List<CartItem>? itens,
  double? pago,
}) =>
    OrderModel(
      id: 'foto-pagar-na-loja',
      total: 19.71,
      cashTotalDue: pagamento == PaymentMethod.cash ? 19.71 : null,
      serviceType: servico,
      orderType:
          parceira ? OrderType.partnerRestaurant : OrderType.nonPartnerPurchase,
      isPartnerStore: parceira,
      status: status,
      paymentMethod: pagamento,
      lojaPagamentoEstado: estado,
      lojaPagarValor: estado == 'pagar_loja' ? 13.80 : 0,
      finalPurchaseValue: pago,
      isPurchaseFinalized: pago != null,
      items: itens,
      vendorName: 'Boom! Burger',
    );

Widget _mapa(OrderModel o) => Scaffold(
      body: Stack(children: [
        Container(color: const Color(0xFFDDE3E8)),
        const Center(
            child: Text('(mapa)',
                style: TextStyle(color: Color(0xFF8A96A3), fontSize: 18))),
        Positioned(
            top: 80, left: 12, right: 12, child: FaixaDinheiroEstafeta(order: o)),
        Positioned(
          left: 0,
          right: 0,
          bottom: 0,
          child: Container(
            height: 120,
            decoration: const BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
            ),
            alignment: Alignment.center,
            child: const Text('Boom! Burger · painel (fechado)'),
          ),
        ),
      ]),
    );

void main() {
  setUpAll(() async {
    await carregaFonteInter();
    await carregaFontesSdk();
  });

  const tel = ('telemovel', Size(390, 844));

  testWidgets('estafeta na loja — R1 paga 13,80 € à loja', (tester) async {
    await fotografaTela(tester,
        nome: 'pagar_na_loja_estafeta_loja_r1',
        tamanho: tel,
        tela: _mapa(_p(estado: 'pagar_loja')));
    expect(find.text('PAGA 13,80 € À LOJA'), findsOneWidget);
  });

  testWidgets('estafeta no cliente — R1 cobra 19,71 €', (tester) async {
    await fotografaTela(tester,
        nome: 'pagar_na_loja_estafeta_cliente_r1',
        tamanho: tel,
        tela: _mapa(_p(estado: 'pagar_loja', status: OrderStatus.onTheWay, pago: 13.80)));
    expect(find.text('COBRA 19,71 € AO CLIENTE'), findsOneWidget);
  });

  testWidgets('estafeta na loja — R2 já pago', (tester) async {
    await fotografaTela(tester,
        nome: 'pagar_na_loja_estafeta_loja_r2',
        tamanho: tel,
        tela: _mapa(_p(estado: 'ja_pago', pagamento: PaymentMethod.mbway)));
    expect(find.text('JÁ ESTÁ PAGO — não pagas nada na loja'), findsOneWidget);
  });

  testWidgets('estafeta no cliente — R2 não cobra', (tester) async {
    await fotografaTela(tester,
        nome: 'pagar_na_loja_estafeta_cliente_r2',
        tamanho: tel,
        tela: _mapa(_p(
            estado: 'ja_pago',
            pagamento: PaymentMethod.mbway,
            status: OrderStatus.pickedUp)));
    expect(find.text('JÁ ESTÁ PAGO — não cobres nada'), findsOneWidget);
  });

  testWidgets('estafeta na loja — R3 faz a compra', (tester) async {
    await fotografaTela(tester,
        nome: 'pagar_na_loja_estafeta_loja_r3',
        tamanho: tel,
        tela: _mapa(_p(
          estado: 'fazer_compra',
          parceira: false,
          servico: OrderServiceType.storeShopping,
          itens: [CartItem(productId: 'a', name: 'Leite', price: 1.15, basePrice: 1.0, quantity: 4)],
        )));
    expect(find.text('TENS DE FAZER A COMPRA'), findsOneWidget);
  });

  testWidgets('oferta e lista do estafeta — as três linhas', (tester) async {
    await fotografaTela(tester,
        nome: 'pagar_na_loja_oferta_linhas',
        tamanho: tel,
        tela: Scaffold(
          backgroundColor: const Color(0xFFF3F4F6),
          body: ListView(padding: const EdgeInsets.all(16), children: [
            for (final o in [
              _p(estado: 'pagar_loja'),
              _p(estado: 'ja_pago', pagamento: PaymentMethod.mbway),
              _p(estado: 'fazer_compra', parceira: false),
            ])
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('Novo pedido · Ganhas 4,24 €',
                            style: TextStyle(
                                fontSize: 16, fontWeight: FontWeight.w800)),
                        const SizedBox(height: 8),
                        LojaDinheiroResumo(order: o, dense: true),
                        const SizedBox(height: 8),
                        LojaDinheiroResumo(order: o),
                      ]),
                ),
              ),
          ]),
        ));
    expect(find.text('Pagas 13,80 € na loja · Cobras 19,71 €'), findsNWidgets(2));
  });

  testWidgets('painel do parceiro — aviso em cada pedido com entrega',
      (tester) async {
    await fotografaTela(tester,
        nome: 'pagar_na_loja_parceiro_avisos',
        tamanho: tel,
        tela: Scaffold(
          backgroundColor: const Color(0xFFF3F4F6),
          body: ListView(padding: const EdgeInsets.all(16), children: [
            const Text('Pedido #6d38 · Dinheiro · Entrega',
                style: TextStyle(fontWeight: FontWeight.w700)),
            const SizedBox(height: 8),
            AvisoPagamentoEstafeta(order: _p(estado: 'pagar_loja')),
            const SizedBox(height: 20),
            const Text('Pedido #a1b2 · MB Way · Entrega',
                style: TextStyle(fontWeight: FontWeight.w700)),
            const SizedBox(height: 8),
            AvisoPagamentoEstafeta(
                order: _p(estado: 'ja_pago', pagamento: PaymentMethod.mbway)),
            const SizedBox(height: 20),
            const Text('Pedido #6d38 · depois da recolha',
                style: TextStyle(fontWeight: FontWeight.w700)),
            const SizedBox(height: 8),
            AvisoPagamentoEstafeta(
                order: _p(
                    estado: 'pagar_loja',
                    status: OrderStatus.delivered,
                    pago: 13.80)),
          ]),
        ));
    expect(
        find.text(
            'O estafeta paga-te 13,80 € em dinheiro quando vier buscar o pedido.'),
        findsOneWidget);
  });

  testWidgets('painel admin — loja e entregador, com correção', (tester) async {
    await fotografaTela(tester,
        nome: 'pagar_na_loja_admin_secao',
        tamanho: ('tablet', const Size(800, 700)),
        tela: const Scaffold(
          backgroundColor: Color(0xFFF3F4F6),
          body: Padding(
            padding: EdgeInsets.all(16),
            child: SingleChildScrollView(
              child: AdminPagoLojaSection(order: {
                'id': '6d38f5e5-53ae-4468-b272-f746ce60b8a2',
                'loja_pagamento_estado': 'pagar_loja',
                'loja_pagar_valor': 13.80,
                'is_purchase_finalized': true,
                'final_purchase_value': 13.80,
              }),
            ),
          ),
        ));
    expect(find.text('Estafeta paga à loja: 13,80 €'), findsOneWidget);
    expect(find.text('Pago de fato à loja (registrado): 13,80 €'), findsOneWidget);
  });
}
