import 'package:bora_app/widgets/admin/admin_telefone_aguardar_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

// 17/11/2026 — bloco "Encomendas por telefone a aguardar" no topo do painel.
void main() {
  final agora = DateTime.utc(2026, 11, 17, 20, 0, 0);

  test('contagem decrescente em minutos:segundos', () {
    expect(contagemAteChamar(agora.add(const Duration(minutes: 14, seconds: 5)), agora),
        'estafeta chamado sozinho em 14:05');
    expect(contagemAteChamar(agora.add(const Duration(seconds: 9)), agora),
        'estafeta chamado sozinho em 0:09');
  });

  test('passada a hora, diz que está a chamar agora', () {
    expect(contagemAteChamar(agora, agora), 'a chamar o estafeta agora…');
    expect(contagemAteChamar(agora.subtract(const Duration(minutes: 1)), agora),
        'a chamar o estafeta agora…');
  });

  Widget montar(List<Map<String, dynamic>> pedidos) => MaterialApp(
        home: Scaffold(
          body: Column(children: [
            AdminTelefoneAguardarCard(carregadorParaTeste: () async => pedidos),
          ]),
        ),
      );

  testWidgets('sem pedidos o bloco não aparece e o alerta fica a zero', (t) async {
    await t.pumpWidget(montar(const []));
    await t.pump();
    expect(find.byKey(const Key('admin_telefone_aguardar')), findsNothing);
    expect(AdminTelefoneAguardarCard.contagem.value, 0);
    await t.pumpWidget(const SizedBox());
  });

  testWidgets('com pedido mostra loja, cliente, contagem e os dois botões', (t) async {
    final daqui10 = DateTime.now().toUtc().add(const Duration(minutes: 10));
    await t.pumpWidget(montar([
      {
        'order_id': 'pedido-teste-1',
        'loja': 'Jyosmi Sushi',
        'telefone': '271000000',
        'cliente': 'Maria',
        'criado_em': DateTime.now().toUtc().toIso8601String(),
        'encomendado_em': null,
        'chama_estafeta_as': daqui10.toIso8601String(),
      },
    ]));
    await t.pump();
    expect(find.byKey(const Key('admin_telefone_aguardar')), findsOneWidget);
    expect(find.text('Encomendas por telefone a aguardar (1)'), findsOneWidget);
    expect(find.text('Jyosmi Sushi'), findsOneWidget);
    expect(find.textContaining('Maria'), findsOneWidget);
    expect(find.textContaining('estafeta chamado sozinho em'), findsOneWidget);
    expect(find.text('Chamar estafeta já'), findsOneWidget);
    expect(find.text('Encomendei à loja'), findsOneWidget);
    expect(AdminTelefoneAguardarCard.contagem.value, 1);
    await t.pumpWidget(const SizedBox());
  });

  testWidgets('já encomendado: some o "Encomendei à loja", fica o chamar', (t) async {
    await t.pumpWidget(montar([
      {
        'order_id': 'pedido-teste-2',
        'loja': 'Fuku Sushi',
        'cliente': '',
        'criado_em': DateTime.now().toUtc().toIso8601String(),
        'encomendado_em': DateTime.now().toUtc().toIso8601String(),
        'chama_estafeta_as': DateTime.now().toUtc().toIso8601String(),
      },
    ]));
    await t.pump();
    expect(find.text('Chamar estafeta já'), findsOneWidget);
    expect(find.text('Encomendei à loja'), findsNothing);
    await t.pumpWidget(const SizedBox());
  });
}
