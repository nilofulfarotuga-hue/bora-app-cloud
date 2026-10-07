// BORA ASSISTENTE (07/10/2026) — o cartão de proposta desenha o que o
// servidor manda (total, poupança, +18, loja fechada) e o ecrã vazio
// oferece as 3 sugestões clicáveis.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:bora_app/screens/client/assistant/assistant_cards.dart';
import 'package:bora_app/services/assistant_service.dart';

AssistantProposal _proposta({
  bool open = true,
  int savingsCents = 120,
  bool maior18 = true,
}) =>
    AssistantProposal.fromJson({
      'proposal_id': '11111111-2222-3333-4444-555555555555',
      'restaurant_id': 'continente-guarda',
      'restaurant_name': 'Continente Guarda',
      'is_partner': false,
      'service_type': 'storeShopping',
      'open': open,
      'coverage_pct': 75,
      'rank': 1,
      'kind': 'single',
      'items': [
        {
          'product_id': 'cnt-1',
          'name': 'Arroz Carolino 1kg',
          'quantity': 2,
          'unit_price': 1.49,
          'base_price': 1.30,
          'line_total': 2.98,
          'confidence': 'alta',
          'maior_18': false,
          'query': 'arroz',
        },
        {
          'product_id': 'cnt-2',
          'name': 'Vinho Tinto Dão 75cl',
          'quantity': 1,
          'unit_price': 4.99,
          'base_price': 4.34,
          'line_total': 4.99,
          'confidence': 'parecido',
          'maior_18': maior18,
          'query': 'vinho',
        },
      ],
      'missing_items': [
        {'query': 'ovos', 'quantity': 1},
      ],
      'subtotal': 7.97,
      'delivery_fee': 2.50,
      'service_fee': 0.00,
      'small_order_fee': 1.00,
      'bag_fee': 0.10,
      'customer_total': 11.57,
      'savings_cents': savingsCents,
      'has_maior_18': maior18,
      'distance_km': 1.8,
    });

Widget _host(Widget child) => MaterialApp(
      home: Scaffold(body: SingleChildScrollView(child: child)),
    );

void main() {
  testWidgets('cartão da proposta: total em grande, poupança, +18, parecido',
      (tester) async {
    var tocou = false;
    await tester.pumpWidget(_host(AssistantProposalCard(
      proposta: _proposta(),
      onEncher: () => tocou = true,
    )));

    expect(find.text('Continente Guarda'), findsOneWidget);
    expect(find.text('Mercado'), findsOneWidget, reason: 'não-parceiro');
    expect(find.text('Total'), findsOneWidget);
    expect(find.text('€11.57'), findsOneWidget, reason: 'o total do servidor');
    expect(find.text('Poupas €1.20 face à loja mais cara'), findsOneWidget);
    expect(find.text('+18: o estafeta pede documento na entrega.'),
        findsOneWidget);
    expect(find.text('Parecido — confirma'), findsOneWidget);
    expect(find.text('Sem ovos (1×) nesta loja'), findsOneWidget);
    expect(find.text('Taxa de pedido pequeno'), findsOneWidget);
    expect(find.text('Sacos'), findsOneWidget);
    expect(find.text('Tem 75% da tua lista'), findsOneWidget);
    expect(find.text('Fechada agora'), findsNothing);

    await tester.tap(find.text('Encher o carrinho'));
    await tester.pump();
    expect(tocou, isTrue, reason: 'o botão laranja chama onEncher');
  });

  testWidgets('cartão sem poupança nem +18 não mostra esses avisos; fechada avisa',
      (tester) async {
    await tester.pumpWidget(_host(AssistantProposalCard(
      proposta: _proposta(open: false, savingsCents: 0, maior18: false),
      onEncher: () {},
    )));
    expect(find.textContaining('Poupas'), findsNothing);
    expect(find.textContaining('+18'), findsNothing);
    expect(find.text('Fechada agora'), findsOneWidget);
  });

  testWidgets('ecrã vazio: 3 sugestões clicáveis', (tester) async {
    String? enviado;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: AssistantEmptyState(onSugestao: (t) => enviado = t),
      ),
    ));
    expect(find.text('Diz-me o que precisas'), findsOneWidget);
    for (final s in AssistantEmptyState.sugestoes) {
      expect(find.text(s), findsOneWidget);
    }
    expect(AssistantEmptyState.sugestoes.length, 3);

    await tester.tap(find.text('o de sempre'));
    await tester.pump();
    expect(enviado, 'o de sempre');
  });

  test('a resposta estruturada do servidor desserializa inteira', () {
    final r = AssistantReply.fromJson({
      'ok': true,
      'conversation_id': 'c1',
      'texto': 'Encontrei em 2 lojas.',
      'propostas': [
        {
          'proposal_id': 'p1',
          'restaurant_id': 'r1',
          'restaurant_name': 'Loja',
          'is_partner': true,
          'items': [],
          'subtotal': 1,
          'customer_total': 3.5,
        }
      ],
      'divisao': {
        'customer_total': 9.9,
        'savings_vs_best_single_cents': 80,
        'split_group': 'g1',
        'parts': [
          {'proposal_id': 'p2', 'restaurant_id': 'r2', 'restaurant_name': 'A', 'customer_total': 5},
          {'proposal_id': 'p3', 'restaurant_id': 'r3', 'restaurant_name': 'B', 'customer_total': 4.9},
        ],
      },
      'favores': [
        {'query': 'tabaco', 'quantity': 1, 'maior_18': true}
      ],
      'favor_preco': {
        'available': true,
        'normal_fee': 4.5,
        'express_fee': 6.5,
        'normal_sla_minutes': 60,
        'express_sla_minutes': 30,
        'max_advance_cents': 4000,
      },
      'lista_extraida': [
        {'query': 'leite', 'quantity': 2}
      ],
      'acoes': [
        {'tipo': 'abrir_favores', 'rotulo': 'Pedir favor', 'destino': 'tabaco'}
      ],
      'handoff': false,
      'ticket_id': null,
      'messages_remaining_today': 27,
      'poupanca_acumulada_cents': 350,
    });
    expect(r.conversationId, 'c1');
    expect(r.propostas.single.isPartner, isTrue);
    expect(r.propostas.single.customerTotal, 3.5);
    expect(r.divisao!.parts.length, 2);
    expect(r.divisao!.savingsVsBestSingleCents, 80);
    expect(r.favores.single.maior18, isTrue);
    expect(r.favorPreco!.expressFee, 6.5);
    expect(r.listaExtraida!.single.quantity, 2);
    expect(r.acoes.single.tipo, 'abrir_favores');
    expect(r.messagesRemainingToday, 27);
    expect(r.poupancaAcumuladaCents, 350);
    expect(r.temCartoes, isTrue);
  });
}
