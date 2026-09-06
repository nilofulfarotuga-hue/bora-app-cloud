// Prova do defeito apanhado pelo Danilo no telemovel (2026-08-25):
//   1) a faixa verde de "adicionado ao carrinho" ficava presa no ecra;
//   2) a ficha do produto nao fechava depois de adicionar.
//
// O teste reproduz a condicao REAL que prendia o aviso: adicionar e navegar
// logo a seguir. Nesse caso o temporizador interno do SnackBar nunca chega a
// ser armado (ScaffoldMessenger so o cria num rebuild com route.isCurrent),
// e sem a rede de seguranca do helper a faixa ficaria para sempre.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:bora_app/utils/cart_feedback.dart';

void main() {
  testWidgets('o aviso desaparece aos 2s MESMO com navegacao a seguir',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (context) => ElevatedButton(
            // Exactamente o que a ficha do produto faz agora:
            // mostra o aviso e fecha-se (navega).
            onPressed: () {
              showAddedToCartSnack(context, 'Cento de Salgados no carrinho');
              Navigator.of(context).push(MaterialPageRoute(
                builder: (_) => const Scaffold(body: Text('menu da loja')),
              ));
            },
            child: const Text('Adicionar ao carrinho'),
          ),
        ),
      ),
    ));

    await tester.tap(find.text('Adicionar ao carrinho'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    // ANTES: o aviso aparece (e o cliente ja esta noutro ecra).
    expect(find.text('Cento de Salgados no carrinho'), findsOneWidget,
        reason: 'o aviso tem de aparecer ao adicionar');
    expect(find.text('menu da loja'), findsOneWidget,
        reason: 'a navegacao aconteceu — e aqui que o temporizador nativo falha');

    // DEPOIS: aos 2 segundos sai sozinho.
    await tester.pump(const Duration(seconds: 2));
    await tester.pumpAndSettle();
    expect(find.text('Cento de Salgados no carrinho'), findsNothing,
        reason: 'aos 2s o aviso tem de ter saido sozinho');
  });

  testWidgets('o aviso nao tapa a barra do carrinho (fica acima dela)',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (context) => Column(
            children: [
              ElevatedButton(
                onPressed: () => showAddedToCartSnack(context, 'x no carrinho'),
                child: const Text('Adicionar'),
              ),
              const Spacer(),
              const SizedBox(
                  height: 52,
                  child: Center(child: Text('Ver carrinho · €10,00'))),
            ],
          ),
        ),
      ),
    ));

    await tester.tap(find.text('Adicionar'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    final aviso = tester.getRect(find.text('x no carrinho'));
    final barra = tester.getRect(find.text('Ver carrinho · €10,00'));
    expect(aviso.bottom, lessThan(barra.top),
        reason: 'o aviso tem de ficar ACIMA da barra do carrinho, nunca por cima');

    // deixar o temporizador dos 2s completar antes de fechar o teste
    await tester.pump(const Duration(seconds: 2));
    await tester.pumpAndSettle();
  });

  testWidgets('DEPOIS: sai aos 2s mesmo com TalkBack/VoiceOver ligado',
      (tester) async {
    // Esta e a condicao EXACTA do defeito do Danilo: o Flutter documenta que
    // "a SnackBar with an action will not time out when TalkBack or VoiceOver
    // are enabled" (snack_bar.dart). O nosso aviso tem a accao "Ver", logo
    // sem a rede de seguranca ficaria no ecra para sempre — reproduzido: 30s
    // depois ainda la estava.
    await tester.pumpWidget(MaterialApp(
      home: MediaQuery(
        data: const MediaQueryData(accessibleNavigation: true),
        child: Scaffold(
          body: Builder(
            builder: (context) => ElevatedButton(
              onPressed: () =>
                  showAddedToCartSnack(context, 'Coxinha no carrinho'),
              child: const Text('Adicionar'),
            ),
          ),
        ),
      ),
    ));

    await tester.tap(find.text('Adicionar'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('Coxinha no carrinho'), findsOneWidget);

    await tester.pump(const Duration(seconds: 2));
    await tester.pumpAndSettle();
    expect(find.text('Coxinha no carrinho'), findsNothing,
        reason: 'com acessibilidade ligada o Flutter nao arma o temporizador — '
            'quem fecha o aviso e a rede de seguranca do helper');
  });
}
