// Autorização de promoções (03/11/2026, missão boom-hamburguer-mes, bloco H).
//   - a pergunta só aparece se o servidor disser que falta, e uma vez por sessão;
//   - nada vem pré-marcado: "Sim" grava true, "Agora não" grava false;
//   - o ecrã admin mostra os números e a lista.
import 'package:bora_app/screens/admin/admin_autorizacao_promocoes_screen.dart';
import 'package:bora_app/widgets/pergunta_promocoes.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _app(void Function(BuildContext) aoAbrir) => MaterialApp(
      home: Builder(builder: (context) {
        WidgetsBinding.instance.addPostFrameCallback((_) => aoAbrir(context));
        return const Scaffold(body: Text('início'));
      }),
    );

void main() {
  setUp(PerguntaPromocoes.esquecerParaTeste);

  testWidgets('falta responder: mostra o texto e "Sim" grava true', (t) async {
    final gravados = <bool>[];
    await t.pumpWidget(_app((c) => PerguntaPromocoes.mostrarSeFaltar(c,
        pendente: () async => true, gravar: (v) async => gravados.add(v))));
    await t.pumpAndSettle();
    expect(find.textContaining('Queres receber promoções e novidades das lojas da Guarda?'),
        findsOneWidget);
    expect(find.byType(Checkbox), findsNothing); // nada pré-marcado
    expect(find.byType(Switch), findsNothing);
    await t.tap(find.byKey(const Key('pergunta_promocoes_sim')));
    await t.pumpAndSettle();
    expect(gravados, [true]);
    expect(find.byKey(const Key('pergunta_promocoes')), findsNothing);
  });

  testWidgets('"Agora não" grava false e não volta a perguntar na sessão', (t) async {
    final gravados = <bool>[];
    Future<void> abrir(BuildContext c) => PerguntaPromocoes.mostrarSeFaltar(c,
        pendente: () async => true, gravar: (v) async => gravados.add(v));
    late BuildContext ctx;
    await t.pumpWidget(_app((c) {
      ctx = c;
      abrir(c);
    }));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const Key('pergunta_promocoes_nao')));
    await t.pumpAndSettle();
    expect(gravados, [false]);
    abrir(ctx);
    await t.pumpAndSettle();
    expect(find.byKey(const Key('pergunta_promocoes')), findsNothing);
  });

  testWidgets('já respondeu: não mostra nada', (t) async {
    await t.pumpWidget(_app((c) => PerguntaPromocoes.mostrarSeFaltar(c,
        pendente: () async => false, gravar: (_) async {})));
    await t.pumpAndSettle();
    expect(find.byKey(const Key('pergunta_promocoes')), findsNothing);
  });

  testWidgets('servidor em baixo: não mostra nem rebenta', (t) async {
    await t.pumpWidget(_app((c) => PerguntaPromocoes.mostrarSeFaltar(c,
        pendente: () async => throw Exception('sem rede'), gravar: (_) async {})));
    await t.pumpAndSettle();
    expect(find.byKey(const Key('pergunta_promocoes')), findsNothing);
  });

  testWidgets('painel admin: números e lista de quem aceitou', (t) async {
    await t.pumpWidget(MaterialApp(
      home: AdminAutorizacaoPromocoesScreen(
        carregar: () async => {
          'clientes': 195,
          'aceitaram': 3,
          'recusaram': 1,
          'sem_resposta': 191,
          'lista': [
            {'nome': 'Ana', 'email': 'ana@exemplo.pt', 'telefone': null, 'aceitou_em': '2026-11-03T12:00:00Z'},
          ],
        },
      ),
    ));
    await t.pumpAndSettle();
    expect(find.text('3'), findsOneWidget);
    expect(find.text('191'), findsOneWidget);
    expect(find.text('Nunca responderam'), findsOneWidget);
    expect(find.text('Ana'), findsOneWidget);
  });
}
