import 'package:bora_app/screens/client/receita_do_dia_screen.dart';
import 'package:bora_app/services/assistant_service.dart';
import 'package:bora_app/services/receita_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Receita do Dia — "Pôr no carrinho" (missão final-app-2026-10-29, bloco 7 C2).
/// O ecrã da receita cota os ingredientes, mostra o que vai entrar e o que
/// falta, e só enche o carrinho depois do toque do cliente. Aqui o servidor e
/// o carrinho são substituídos (`cotar` / `encher`), por isso nada toca na rede.
void main() {
  ReceitaHoje hoje({bool avisoLigado = false}) => ReceitaHoje.fromJson({
        'enabled': true,
        'dia': '2026-10-29',
        'aviso_disponivel': true,
        'aviso_hora': 10,
        'aviso_ligado': avisoLigado,
        'receita': {
          'id': 'r1',
          'titulo': 'Esparguete à bolonhesa',
          'resumo': 'O jantar que agrada a miúdos e graúdos.',
          'ingredientes': [
            {'nome': 'Esparguete', 'quantidade': '500 g', 'pesquisa': 'esparguete'},
            {'nome': 'Polpa de tomate', 'quantidade': '1 embalagem', 'pesquisa': 'polpa de tomate'},
            {'nome': 'Carne picada', 'quantidade': '500 g', 'pesquisa': 'carne picada de vaca'},
          ],
          'passos': ['Aloura a cebola.', 'Junta a carne.', 'Coze o esparguete.'],
          'tempo_min': 35,
          'doses': 4,
        },
      })!;

  // 2 ingredientes encontrados, 1 em falta (a carne picada).
  AssistantProposal proposta({bool aberta = true}) =>
      AssistantProposal.fromJson({
        'proposal_id': 'p1',
        'restaurant_id': 'continente-guarda',
        'restaurant_name': 'Continente Guarda',
        'is_partner': false,
        'service_type': 'storeShopping',
        'open': aberta,
        'coverage_pct': 66,
        'items': [
          {'product_id': 'a', 'name': 'Esparguete Milaneza 500 g', 'quantity': 1, 'query': 'esparguete'},
          {'product_id': 'b', 'name': 'Polpa de tomate Compal', 'quantity': 1, 'query': 'polpa de tomate'},
        ],
        'missing_items': [
          {'query': 'carne picada de vaca', 'quantity': 1},
        ],
        'subtotal': 3.2,
      });

  Future<void> abrir(
    WidgetTester tester, {
    required Future<ReceitaCesto> Function(ReceitaDoDia) cotar,
    required List<AssistantProposal> encheu,
    ReceitaHoje? receita,
  }) async {
    await tester.pumpWidget(MaterialApp(
      home: ReceitaDoDiaScreen(
        hoje: receita ?? hoje(),
        cotar: cotar,
        encher: (context, p) async {
          encheu.add(p);
          return true;
        },
      ),
    ));
    await tester.pump();
  }

  // Com o resumo aberto o botão de trás ainda mostra o círculo a rodar (carrinho a montar),
  // por isso não se usa pumpAndSettle enquanto o diálogo está aberto.
  Future<void> esperarResumo(WidgetTester t) async {
    await t.pump();
    await t.pump(const Duration(milliseconds: 400));
  }

  final botaoPrincipal = find.byKey(const Key('receita_por_no_carrinho'));
  final botaoDoDialogo = find.descendant(
    of: find.byType(AlertDialog),
    matching: find.text('Pôr no carrinho'),
  );

  testWidgets('mostra os ingredientes e os passos da receita', (tester) async {
    await abrir(tester,
        cotar: (_) async => const ReceitaCesto(erro: 'sem_loja'), encheu: []);
    expect(find.text('Esparguete à bolonhesa'), findsOneWidget);
    expect(find.text('Esparguete — 500 g'), findsOneWidget);
    expect(find.text('Carne picada — 500 g'), findsOneWidget);
    expect(find.text('Coze o esparguete.'), findsOneWidget);
  });

  testWidgets('2 ingredientes encontrados e 1 em falta: lista os dois e avisa do que falta',
      (tester) async {
    final encheu = <AssistantProposal>[];
    ReceitaDoDia? cotada;
    await abrir(tester, encheu: encheu, cotar: (r) async {
      cotada = r;
      return ReceitaCesto(proposta: proposta());
    });

    await tester.tap(botaoPrincipal);
    await esperarResumo(tester);

    // O servidor recebeu a receita inteira (3 ingredientes).
    expect(cotada!.ingredientes.length, 3);
    // O cliente vê o que vai entrar, em que loja, e o que não existe.
    expect(find.text('No carrinho do Continente Guarda'), findsOneWidget);
    expect(find.text('1 × Esparguete Milaneza 500 g'), findsOneWidget);
    expect(find.text('1 × Polpa de tomate Compal'), findsOneWidget);
    expect(find.text('Não há: Carne picada.'), findsOneWidget);
    // Nada entrou no carrinho antes do toque.
    expect(encheu, isEmpty);

    await tester.tap(botaoDoDialogo);
    await tester.pumpAndSettle();

    expect(encheu.length, 1);
    expect(encheu.single.restaurantId, 'continente-guarda');
    expect(encheu.single.items.length, 2);
    expect(encheu.single.missingItems.single.query, 'carne picada de vaca');
  });

  testWidgets('cancelar no resumo não enche o carrinho', (tester) async {
    final encheu = <AssistantProposal>[];
    await abrir(tester,
        encheu: encheu, cotar: (_) async => ReceitaCesto(proposta: proposta()));
    await tester.tap(botaoPrincipal);
    await esperarResumo(tester);
    await tester.tap(find.text('Cancelar'));
    await tester.pumpAndSettle();
    expect(encheu, isEmpty);
    expect(find.byType(AlertDialog), findsNothing);
  });

  testWidgets('tudo encontrado: não aparece a linha "Não há"', (tester) async {
    final encheu = <AssistantProposal>[];
    final completa = AssistantProposal.fromJson({
      'proposal_id': 'p2',
      'restaurant_id': 'auchan-guarda',
      'restaurant_name': 'Auchan Guarda',
      'open': true,
      'items': [
        {'product_id': 'a', 'name': 'Esparguete Milaneza 500 g', 'quantity': 1},
      ],
      'missing_items': [],
    });
    await abrir(tester,
        encheu: encheu, cotar: (_) async => ReceitaCesto(proposta: completa));
    await tester.tap(botaoPrincipal);
    await esperarResumo(tester);
    expect(find.textContaining('Não há:'), findsNothing);
  });

  testWidgets('sem morada: avisa e não abre o resumo', (tester) async {
    final encheu = <AssistantProposal>[];
    await abrir(tester,
        encheu: encheu,
        cotar: (_) async => const ReceitaCesto(erro: 'sem_morada'));
    await tester.tap(botaoPrincipal);
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsNothing);
    expect(
        find.text('Escolhe primeiro a tua morada de entrega na página inicial.'),
        findsOneWidget);
    expect(encheu, isEmpty);
  });

  testWidgets('nenhum mercado com os ingredientes: avisa e não abre o resumo',
      (tester) async {
    await abrir(tester,
        encheu: [], cotar: (_) async => const ReceitaCesto(erro: 'sem_loja'));
    await tester.tap(botaoPrincipal);
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsNothing);
    expect(
        find.text(
            'Não encontrámos estes ingredientes nos supermercados agora. Tenta mais tarde.'),
        findsOneWidget);
  });

  testWidgets('o servidor falha: mensagem simples e o botão volta a funcionar',
      (tester) async {
    await abrir(tester, encheu: [], cotar: (_) async => throw StateError('rede'));
    await tester.tap(botaoPrincipal);
    await tester.pumpAndSettle();
    expect(find.text('Não foi possível montar o carrinho agora. Tenta outra vez.'),
        findsOneWidget);
    final botao = tester.widget<ElevatedButton>(botaoPrincipal);
    expect(botao.onPressed, isNotNull);
  });

  testWidgets('o interruptor do aviso aparece com o estado que o servidor deu',
      (tester) async {
    await abrir(tester,
        encheu: [],
        receita: hoje(avisoLigado: true),
        cotar: (_) async => const ReceitaCesto(erro: 'sem_loja'));
    final sw = tester.widget<SwitchListTile>(find.byKey(const Key('receita_aviso_switch')));
    expect(sw.value, isTrue);
    expect(find.text('Avisar-me todos os dias às 10h'), findsOneWidget);
  });
}
