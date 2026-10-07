// Cartão "Ativar notificações" da web para cliente e parceiro (07/10/2026).
// Fora da web o cartão não existe; aqui força-se a desenhar (forcarVisivel)
// e injecta-se o que o botão faz, para provar a máquina de estados:
//   permissão dada → nada; default → botão; toque → 'granted' → desaparece;
//   toque → continua 'default' → aviso de falha; 'denied' → sem botão;
//   "Agora não" → esconde; papel desconhecido → nada.
import 'package:bora_app/widgets/web_push_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _app(Widget filho) => MaterialApp(home: Scaffold(body: filho));

void main() {
  setUp(WebPushCard.limparDispensas);

  testWidgets('fora da web (sem forçar) não desenha nada', (tester) async {
    await tester.pumpWidget(_app(const WebPushCard(role: 'client')));
    expect(find.byKey(const Key('web_push_card_client')), findsNothing);
  });

  testWidgets('com a permissão já dada não desenha nada', (tester) async {
    await tester.pumpWidget(_app(const WebPushCard(
      role: 'partner',
      forcarVisivel: true,
      permissaoInicial: 'granted',
    )));
    expect(find.byKey(const Key('web_push_card_partner')), findsNothing);
  });

  testWidgets('papel que não é cliente nem parceiro não desenha nada',
      (tester) async {
    await tester.pumpWidget(_app(const WebPushCard(
      role: 'driver',
      forcarVisivel: true,
      permissaoInicial: 'default',
    )));
    expect(find.byType(FilledButton), findsNothing);
  });

  testWidgets('cliente: o toque pede a permissão e, dada, o cartão desaparece',
      (tester) async {
    var pedidos = 0;
    await tester.pumpWidget(_app(WebPushCard(
      role: 'client',
      forcarVisivel: true,
      permissaoInicial: 'default',
      ativar: () async {
        pedidos++;
        return 'granted';
      },
    )));
    expect(find.text('Recebe avisos do teu pedido'), findsOneWidget);
    expect(find.text(WebPushCard.textoBotao), findsOneWidget);

    await tester.tap(find.byKey(const Key('btn_web_push_client')));
    await tester.pumpAndSettle();

    expect(pedidos, 1);
    expect(find.byKey(const Key('web_push_card_client')), findsNothing,
        reason: 'permissão dada = já não há nada para pedir');
  });

  testWidgets('parceiro: se a permissão ficar por dar, avisa e deixa repetir',
      (tester) async {
    await tester.pumpWidget(_app(WebPushCard(
      role: 'partner',
      forcarVisivel: true,
      permissaoInicial: 'default',
      ativar: () async => 'default',
    )));
    expect(find.text('Recebe os pedidos novos'), findsOneWidget);

    await tester.tap(find.byKey(const Key('btn_web_push_partner')));
    await tester.pumpAndSettle();

    expect(
        find.textContaining('Não ficou ativo'), findsOneWidget);
    expect(find.byKey(const Key('btn_web_push_partner')), findsOneWidget,
        reason: 'o botão fica para tentar de novo');
  });

  testWidgets('bloqueada no navegador: explica e não mostra botão',
      (tester) async {
    await tester.pumpWidget(_app(const WebPushCard(
      role: 'client',
      forcarVisivel: true,
      permissaoInicial: 'denied',
    )));
    expect(find.textContaining('bloqueadas neste navegador'), findsOneWidget);
    expect(find.byType(FilledButton), findsNothing);
  });

  testWidgets('"Agora não" esconde o cartão', (tester) async {
    await tester.pumpWidget(_app(const WebPushCard(
      role: 'client',
      forcarVisivel: true,
      permissaoInicial: 'default',
    )));
    expect(find.byKey(const Key('web_push_card_client')), findsOneWidget);
    await tester.tap(find.byKey(const Key('web_push_card_agora_nao')));
    await tester.pump();
    expect(find.byKey(const Key('web_push_card_client')), findsNothing);
  });
}
