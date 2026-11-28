// Sugestões da lupa desde a 1.ª letra (17/11/2026, missão lupa-sugestoes-17-11).
import 'package:bora_app/screens/admin/admin_menu_registry.dart';
import 'package:bora_app/utils/lupa_sugestoes.dart';
import 'package:bora_app/utils/pesquisa_lupa.dart';
import 'package:bora_app/widgets/lupa_sugestoes_painel.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const _todas = <SugestaoLupa>[
  SugestaoLupa(texto: 'Água', tipo: TipoSugestao.palavra),
  SugestaoLupa(
      texto: 'Águas e Sumos',
      tipo: TipoSugestao.seccao,
      ref: 'águas e sumos',
      restaurantId: 'continente-guarda'),
  SugestaoLupa(
      texto: 'Água de Nascente 1,5 L',
      tipo: TipoSugestao.produto,
      ref: 'cont-1',
      restaurantId: 'continente-guarda'),
  SugestaoLupa(
      texto: 'Auchan',
      tipo: TipoSugestao.loja,
      ref: 'auchan-guarda',
      restaurantId: 'auchan-guarda'),
  SugestaoLupa(texto: 'Arroz', tipo: TipoSugestao.palavra),
];

/// Fonte falsa: devolve as sugestões que começam pelo texto e conta os pedidos.
class _Fonte {
  int pedidos = 0;
  final List<String> textos = [];
  Object? erro;

  Future<List<SugestaoLupa>> call(String texto, String? loja) async {
    pedidos++;
    textos.add(texto);
    if (erro != null) throw erro!;
    final p = normalizarParaSugestao(texto);
    return _todas
        .where((s) => normalizarParaSugestao(s.texto).startsWith(p))
        .toList();
  }
}

Widget _app(Widget filho) => MaterialApp(home: Scaffold(body: filho));

void main() {
  test('painel admin: "Sugestões da lupa" está no menu (paridade admin)', () {
    final item =
        adminMenuAllItems().where((i) => i.id == 'clientes_lupa_sugestoes');
    expect(item, hasLength(1));
    expect(item.single.title, 'Sugestões da lupa');
    expect(item.single.matches('autocompletar'), isTrue);
  });

  group('modoDaLupa', () {
    test('nada escrito, espaços ou só pontuação = vazio', () {
      expect(modoDaLupa(''), ModoLupa.vazio);
      expect(modoDaLupa('   '), ModoLupa.vazio);
      expect(modoDaLupa('!!'), ModoLupa.vazio);
    });

    test('1 ou 2 letras = sugestões (acentos contam como letra)', () {
      expect(modoDaLupa('a'), ModoLupa.sugestoes);
      expect(modoDaLupa('Á'), ModoLupa.sugestoes);
      expect(modoDaLupa('ag'), ModoLupa.sugestoes);
      expect(modoDaLupa(' a g '), ModoLupa.sugestoes);
    });

    test('3 letras ou mais = pesquisa completa (como hoje)', () {
      expect(modoDaLupa('agu'), ModoLupa.pesquisa);
      expect(modoDaLupa('água'), ModoLupa.pesquisa);
      expect(modoDaLupa('7up'), ModoLupa.pesquisa);
    });
  });

  group('sugestoesDasLinhas', () {
    test('lê os quatro tipos e ignora o que não presta', () {
      final l = sugestoesDasLinhas([
        {'texto': 'Água', 'tipo': 'palavra', 'ref': null, 'restaurant_id': null},
        {'texto': 'Auchan', 'tipo': 'loja', 'ref': 'auchan-guarda', 'restaurant_id': 'auchan-guarda'},
        {'texto': 'Talho', 'tipo': 'seccao', 'ref': 'talho', 'restaurant_id': 'cont'},
        {'texto': 'Leite UHT', 'tipo': 'produto', 'ref': 'p1', 'restaurant_id': 'cont'},
        {'texto': '   ', 'tipo': 'palavra'},
        'lixo',
        42,
      ]);
      expect(l.map((s) => s.tipo).toList(), [
        TipoSugestao.palavra,
        TipoSugestao.loja,
        TipoSugestao.seccao,
        TipoSugestao.produto,
      ]);
      expect(l[1].ref, 'auchan-guarda');
      expect(l[0].restaurantId, isNull);
    });

    test('resposta que não é lista = nenhuma sugestão', () {
      expect(sugestoesDasLinhas(null), isEmpty);
      expect(sugestoesDasLinhas({'x': 1}), isEmpty);
    });
  });

  test('normalizarParaSugestao igual ao lupa_norm do servidor', () {
    expect(normalizarParaSugestao('Água com Gás'), 'agua com gas');
    expect(normalizarParaSugestao('  Pão-de-Ló!! '), 'pao de lo');
    expect(normalizarParaSugestao('Coração'), 'coracao');
  });

  group('LupaSugestoesPainel', () {
    testWidgets('1 letra: pede ao fim de 250 ms e mostra as sugestões',
        (tester) async {
      final fonte = _Fonte();
      await tester.pumpWidget(_app(LupaSugestoesPainel(
        texto: 'a',
        fonte: fonte.call,
        memoria: MemoriaPesquisa<List<SugestaoLupa>>(),
        aoEscolher: (_) {},
      )));
      expect(fonte.pedidos, 0, reason: 'espera 250 ms antes de pedir');
      await tester.pump(const Duration(milliseconds: 260));
      await tester.pump();
      expect(fonte.pedidos, 1);
      expect(find.text('Água'), findsOneWidget);
      expect(find.text('Auchan'), findsOneWidget);
      expect(find.text('Arroz'), findsOneWidget);
      // um ícone por tipo
      expect(find.byIcon(Icons.storefront_outlined), findsOneWidget);
      expect(find.byIcon(Icons.category_outlined), findsOneWidget);
      expect(find.byIcon(Icons.shopping_basket_outlined), findsOneWidget);
      expect(find.textContaining('Não encontrei'), findsNothing);
    });

    testWidgets('2 letras: a lista encolhe logo e depois vem a do servidor',
        (tester) async {
      final fonte = _Fonte();
      final memoria = MemoriaPesquisa<List<SugestaoLupa>>();
      Widget painel(String t) => _app(LupaSugestoesPainel(
            texto: t,
            fonte: fonte.call,
            memoria: memoria,
            aoEscolher: (_) {},
          ));
      await tester.pumpWidget(painel('a'));
      await tester.pump(const Duration(milliseconds: 260));
      await tester.pump();
      await tester.pumpWidget(painel('ag'));
      // antes do novo pedido já só ficam as que começam por "ag"
      expect(find.text('Arroz'), findsNothing);
      expect(find.text('Auchan'), findsNothing);
      expect(find.text('Água'), findsOneWidget);
      await tester.pump(const Duration(milliseconds: 260));
      await tester.pump();
      expect(fonte.textos, ['a', 'ag']);
      expect(find.text('Águas e Sumos'), findsOneWidget);
    });

    testWidgets('escrever depressa faz um pedido só (o da última letra)',
        (tester) async {
      final fonte = _Fonte();
      final memoria = MemoriaPesquisa<List<SugestaoLupa>>();
      Widget painel(String t) => _app(LupaSugestoesPainel(
            texto: t,
            fonte: fonte.call,
            memoria: memoria,
            aoEscolher: (_) {},
          ));
      await tester.pumpWidget(painel('a'));
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pumpWidget(painel('ag'));
      await tester.pump(const Duration(milliseconds: 260));
      await tester.pump();
      expect(fonte.textos, ['ag']);
    });

    testWidgets('o mesmo prefixo outra vez vem da memória (10 min)',
        (tester) async {
      final fonte = _Fonte();
      final memoria = MemoriaPesquisa<List<SugestaoLupa>>(
          validade: kMemoriaSugestoes);
      await tester.pumpWidget(_app(LupaSugestoesPainel(
        key: const ValueKey(1),
        texto: 'a',
        fonte: fonte.call,
        memoria: memoria,
        aoEscolher: (_) {},
      )));
      await tester.pump(const Duration(milliseconds: 260));
      await tester.pump();
      // outro ecrã (outra lupa) com o mesmo texto
      await tester.pumpWidget(_app(LupaSugestoesPainel(
        key: const ValueKey(2),
        texto: 'a',
        fonte: fonte.call,
        memoria: memoria,
        aoEscolher: (_) {},
      )));
      expect(find.text('Água'), findsOneWidget,
          reason: 'aparece logo, sem esperar');
      await tester.pump(const Duration(milliseconds: 300));
      expect(fonte.pedidos, 1);
    });

    testWidgets('tocar numa sugestão entrega-a a quem chamou',
        (tester) async {
      final fonte = _Fonte();
      SugestaoLupa? escolhida;
      await tester.pumpWidget(_app(LupaSugestoesPainel(
        texto: 'au',
        fonte: fonte.call,
        memoria: MemoriaPesquisa<List<SugestaoLupa>>(),
        aoEscolher: (s) => escolhida = s,
      )));
      await tester.pump(const Duration(milliseconds: 260));
      await tester.pump();
      await tester.tap(find.text('Auchan'));
      expect(escolhida, isNotNull);
      expect(escolhida!.tipo, TipoSugestao.loja);
      expect(escolhida!.ref, 'auchan-guarda');
    });

    testWidgets('sem sugestões: nunca "Não encontrei", só "Escreve mais letras"',
        (tester) async {
      final fonte = _Fonte();
      await tester.pumpWidget(_app(LupaSugestoesPainel(
        texto: 'zq',
        fonte: fonte.call,
        memoria: MemoriaPesquisa<List<SugestaoLupa>>(),
        aoEscolher: (_) {},
      )));
      await tester.pump(const Duration(milliseconds: 260));
      await tester.pump();
      expect(fonte.pedidos, 1);
      expect(find.byType(ListTile), findsNothing);
      expect(find.textContaining('Não encontrei'), findsNothing);
      expect(find.text('Escreve mais letras para ver todos os produtos.'),
          findsOneWidget);
    });

    testWidgets('servidor em baixo: não rebenta nem diz "Não encontrei"',
        (tester) async {
      final fonte = _Fonte()..erro = Exception('sem rede');
      await tester.pumpWidget(_app(LupaSugestoesPainel(
        texto: 'a',
        fonte: fonte.call,
        memoria: MemoriaPesquisa<List<SugestaoLupa>>(),
        aoEscolher: (_) {},
      )));
      await tester.pump(const Duration(milliseconds: 260));
      await tester.pump();
      expect(tester.takeException(), isNull);
      expect(find.textContaining('Não encontrei'), findsNothing);
      expect(find.text('Escreve mais letras para ver todos os produtos.'),
          findsOneWidget);
    });

    testWidgets('3 letras: o painel não pede sugestões (é a pesquisa completa)',
        (tester) async {
      final fonte = _Fonte();
      await tester.pumpWidget(_app(LupaSugestoesPainel(
        texto: 'agu',
        fonte: fonte.call,
        memoria: MemoriaPesquisa<List<SugestaoLupa>>(),
        aoEscolher: (_) {},
      )));
      await tester.pump(const Duration(milliseconds: 300));
      expect(fonte.pedidos, 0);
    });
  });
}
