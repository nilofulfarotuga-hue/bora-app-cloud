import 'package:bora_app/utils/ofertas_em_palavras.dart';
import 'package:bora_app/widgets/admin/admin_ofertas_do_pedido_section.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// M10 (09/11/2026) item 2.5 — botão "Forçar chamada" no painel do pedido
/// (`admin_forcar_chamada`, migração 20261109050000). Textos em PT-BR.
void main() {
  group('resposta do botão em palavras', () {
    test('ok com nome e sem nome', () {
      expect(forcarChamadaEmPalavras({'ok': true, 'nome': 'Valdemir'}),
          'Chamada forçada: o pedido está tocando no celular de Valdemir.');
      expect(forcarChamadaEmPalavras({'ok': true}),
          'Chamada forçada: o pedido está tocando no celular do entregador.');
    });

    test('cada motivo do servidor tem frase própria', () {
      expect(forcarChamadaEmPalavras({'ok': false, 'motivo': 'reforco_desligado'}),
          contains('chamada de reforço está desligada'));
      expect(forcarChamadaEmPalavras({'ok': false, 'motivo': 'pedido_nao_encontrado'}),
          'Pedido não encontrado.');
      expect(forcarChamadaEmPalavras({'ok': false, 'motivo': 'pedido_nao_esta_a_chamar'}),
          'Este pedido não está procurando entregador agora.');
      expect(forcarChamadaEmPalavras({'ok': false, 'motivo': 'oferta_a_decorrer'}),
          contains('Já há uma oferta tocando'));
      expect(forcarChamadaEmPalavras({'ok': false, 'motivo': 'ninguem_disponivel'}),
          contains('Aceito chamadas de reforço'));
      expect(forcarChamadaEmPalavras({'ok': false, 'motivo': 'nao_deu_para_oferecer'}),
          contains('o pedido mudou'));
      expect(forcarChamadaEmPalavras({'ok': false, 'motivo': 'outra_coisa'}),
          contains('outra_coisa'));
    });
  });

  group('ecrã', () {
    Widget app(Widget filho) => MaterialApp(
          home: Scaffold(body: SingleChildScrollView(child: filho)),
        );

    Future<Object?> semOfertas(String _) async => {'ok': true, 'itens': []};

    testWidgets('sem a opção, o botão não aparece', (tester) async {
      await tester.pumpWidget(app(AdminOfertasDoPedidoSection(
        pedidoRef: 'p1',
        carregar: semOfertas,
      )));
      await tester.pumpAndSettle();
      expect(find.text('Forçar chamada'), findsNothing);
    });

    testWidgets('confirma, chama o servidor com o pedido e mostra o nome',
        (tester) async {
      final pedidos = <String>[];
      var leituras = 0;
      await tester.pumpWidget(app(AdminOfertasDoPedidoSection(
        pedidoRef: 'p1',
        mostrarForcarChamada: true,
        carregar: (r) async {
          leituras++;
          return {'ok': true, 'itens': []};
        },
        forcar: (r) async {
          pedidos.add(r);
          return {'ok': true, 'nome': 'Valdemir', 'user_id': 'v'};
        },
      )));
      await tester.pumpAndSettle();
      expect(leituras, 1);

      await tester.tap(find.text('Forçar chamada'));
      await tester.pumpAndSettle();
      expect(find.text('Forçar chamada agora?'), findsOneWidget);
      // Cancelar não chama ninguém.
      await tester.tap(find.text('Cancelar'));
      await tester.pumpAndSettle();
      expect(pedidos, isEmpty);

      await tester.tap(find.text('Forçar chamada'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Chamar agora'));
      await tester.pumpAndSettle();
      expect(pedidos, ['p1']);
      expect(find.text('Chamada forçada: o pedido está tocando no celular de Valdemir.'),
          findsOneWidget);
      expect(leituras, 2, reason: 'recarrega quem foi chamado');
    });

    testWidgets('interruptor desligado: explica onde ligar', (tester) async {
      await tester.pumpWidget(app(AdminOfertasDoPedidoSection(
        pedidoRef: 'p1',
        mostrarForcarChamada: true,
        carregar: semOfertas,
        forcar: (_) async => {'ok': false, 'motivo': 'reforco_desligado'},
      )));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Forçar chamada'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Chamar agora'));
      await tester.pumpAndSettle();
      expect(find.textContaining('chamada de reforço está desligada'), findsOneWidget);
    });

    testWidgets('servidor sem a migração: "Ainda não ativo", não erro', (tester) async {
      await tester.pumpWidget(app(AdminOfertasDoPedidoSection(
        pedidoRef: 'p1',
        mostrarForcarChamada: true,
        carregar: semOfertas,
        forcar: (_) async => throw const PostgrestException(
            message: 'Could not find the function public.admin_forcar_chamada(p_order_id)',
            code: 'PGRST202'),
      )));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Forçar chamada'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Chamar agora'));
      await tester.pumpAndSettle();
      expect(find.textContaining(kAindaNaoAtivo), findsOneWidget);
      expect(find.textContaining('Não deu para forçar'), findsNothing);
    });
  });
}
