// Missão receita-cartao-mbway-17-11 — testes sem rede dos ecrãs da receita com pedido real.
import 'package:bora_app/models/pedido_prescricao.dart';
import 'package:bora_app/screens/farmacia/prescricao_estado_screen.dart';
import 'package:bora_app/screens/partner/farmacia/parceiro_prescricoes_screen.dart';
import 'package:bora_app/services/prescricao_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

PedidoPrescricao _pedido(String estado, {bool demo = false, String? orderId, String? metodo, String? pagMetodo, String? pagOrder}) =>
    PedidoPrescricao.fromMap({
      'id': '00000000-0000-4000-8000-000000000002',
      'created_at': '2026-11-17T10:00:00Z',
      'restaurant_id': 'farmacia-se-guarda',
      'user_id': '4f61dd31-5e9e-4a7c-a557-7d53d2ceded7',
      'tipo': 'receita',
      'estado': estado,
      'morada': 'Rua do Comércio 10, Guarda',
      'valor_medicamentos_cents': 1250,
      'taxa_servico_cents': 600,
      'total_cents': estado == 'confirmado' ? 1850 : null,
      'metodo_pagamento': metodo,
      'codigo_levantamento': estado == 'confirmado' ? 'K7Q2MX' : null,
      'codigo_entrega': estado == 'confirmado' ? '4821' : null,
      'order_id': orderId,
      'is_demo': demo,
      'pagamento_metodo': pagMetodo,
      'pagamento_order_id': pagOrder,
    });

Widget _app(Widget filho) => MaterialApp(home: Scaffold(body: filho));

void _tamanho(WidgetTester t) {
  t.view.physicalSize = const Size(360, 1800);
  t.view.devicePixelRatio = 1.0;
  addTearDown(t.view.reset);
}

void main() {
  testWidgets('cliente: MB Way pede o número e explica a margem', (t) async {
    _tamanho(t);
    await t.pumpWidget(_app(PrescricaoEstadoCorpo(pedido: _pedido('aceite'), taxaServicoCents: 600, farmaciaNome: 'Farmácia da Sé')));
    expect(find.byKey(const Key('prescricao_mbway_telefone')), findsNothing);
    expect(find.byKey(const Key('prescricao_nota_margem')), findsOneWidget); // cartão por defeito
    await t.tap(find.text('MB Way'));
    await t.pump();
    expect(find.byKey(const Key('prescricao_mbway_telefone')), findsOneWidget);
    expect(find.textContaining('app MB WAY antes de aprovar'), findsOneWidget);
    // A devolução automática da margem está desligada no servidor: o ecrã não a promete.
    expect(find.textContaining('volta'), findsNothing);
    await t.tap(find.text('Dinheiro na entrega'));
    await t.pump();
    expect(find.byKey(const Key('prescricao_nota_margem')), findsNothing);
  });

  testWidgets('cliente: MB Way por aprovar mostra o mesmo pedido, sem outro botão de pagar', (t) async {
    _tamanho(t);
    await t.pumpWidget(_app(PrescricaoEstadoCorpo(
      pedido: _pedido('aceite', pagMetodo: 'mbway', pagOrder: 'ord-1'),
      taxaServicoCents: 600,
      farmaciaNome: 'Farmácia da Sé',
    )));
    expect(find.byKey(const Key('prescricao_mbway_pendente')), findsOneWidget);
    expect(find.text('Pedir o MB WAY outra vez'), findsOneWidget);
    expect(find.text('Cancelar este MB WAY'), findsOneWidget);
    expect(find.text('Confirmar e pagar'), findsNothing);
  });

  testWidgets('cliente: confirmado com pedido real mostra "Acompanhar a entrega"', (t) async {
    _tamanho(t);
    await t.pumpWidget(_app(PrescricaoEstadoCorpo(
      pedido: _pedido('confirmado', orderId: 'ord-1', metodo: 'card'),
      taxaServicoCents: 600,
      farmaciaNome: 'Farmácia da Sé',
    )));
    expect(find.byKey(const Key('prescricao_acompanhar_entrega')), findsOneWidget);
    expect(find.text('4821'), findsOneWidget);
    expect(find.textContaining('cartão'), findsWidgets);
  });

  testWidgets('cliente: demonstração confirmada não tem "Acompanhar a entrega"', (t) async {
    _tamanho(t);
    await t.pumpWidget(_app(PrescricaoEstadoCorpo(
      pedido: _pedido('confirmado', demo: true, metodo: 'card'),
      taxaServicoCents: 600,
      farmaciaNome: 'Farmácia da Sé',
    )));
    expect(find.byKey(const Key('prescricao_acompanhar_entrega')), findsNothing);
  });

  testWidgets('farmácia: confirmado real mostra o que o estafeta paga (sem a taxa da Bora)', (t) async {
    _tamanho(t);
    await t.pumpWidget(_app(ParceiroPrescricaoCorpo(
      pedido: _pedido('confirmado', orderId: 'ord-1', metodo: 'cash'),
      semImagens: true,
    )));
    expect(find.byKey(const Key('farmacia_estafeta_paga')), findsOneWidget);
    expect(find.text('12,50 €'), findsOneWidget);
    expect(find.text('18,50 €'), findsNothing);
    expect(find.textContaining('Total'), findsNothing);
  });

  test('farmácia fechada: frase com a hora', () {
    const c = PrescricaoConsentimento(versao: 'v', texto: 't', taxaServicoCents: 600, aberta: false, abreAs: '09:00', abreDia: 'hoje');
    expect(c.avisoFechada, contains('Abre às 09:00'));
    const amanha = PrescricaoConsentimento(versao: 'v', texto: 't', taxaServicoCents: 600, aberta: false, abreAs: '09:00', abreDia: 'amanhã');
    expect(amanha.avisoFechada, contains('Abre amanhã às 09:00'));
    const aberta = PrescricaoConsentimento(versao: 'v', texto: 't', taxaServicoCents: 600);
    expect(aberta.avisoFechada, isNull);
  });

  test('entrega: frases para a farmácia', () {
    expect(const PrescricaoEntrega(prescricaoId: 'a', orderId: 'o', estadoPedido: 'callingDriver').rotulo, 'À procura de estafeta');
    expect(const PrescricaoEntrega(prescricaoId: 'a', orderId: 'o', estadoPedido: 'driverAccepted', estafetaNome: 'Rui').rotulo,
        'Rui vem a caminho da farmácia');
    expect(const PrescricaoEntrega(prescricaoId: 'a', orderId: 'o', estadoPedido: 'delivered').rotulo, 'Entregue ao cliente');
  });
}
