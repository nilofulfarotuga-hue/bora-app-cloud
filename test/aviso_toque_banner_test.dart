import 'package:bora_app/config/app_colors.dart';
import 'package:bora_app/services/permission_gate_service.dart';
import 'package:bora_app/widgets/aviso_toque_banner.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// [10/10/2026] Faixa no ecrã principal do profissional com o que pode calar
/// a oferta e o botão "Corrigir". A leitura e a correcção são injectadas: o
/// widget real pergunta ao Android, o teste não precisa dele.
void main() {
  const volumeZero = ProblemaToque(
    texto: 'Volume do alarme a zero: as ofertas não vão tocar.',
    grave: true,
    correcao: CorrecaoToque.volumeAlarme,
  );
  const semDnd = ProblemaToque(
    texto: 'Sem acesso ao "Não incomodar": de noite a oferta pode não tocar.',
    grave: false,
    correcao: CorrecaoToque.naoIncomodar,
  );
  const faixa = Key('aviso_toque_banner');

  Future<void> pump(WidgetTester tester, Widget child) async {
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: child)));
    await tester.pump();
  }

  Color corDaFaixa(WidgetTester tester) =>
      tester.widget<Material>(find.byKey(faixa)).color!;

  testWidgets('problema grave → faixa vermelha com o mais grave e "Corrigir"',
      (tester) async {
    CorrecaoToque? aberta;
    await pump(
      tester,
      AvisoToqueBanner(
        lerProblemas: () async => const [volumeZero, semDnd],
        corrigir: (c) async => aberta = c,
      ),
    );
    expect(find.text(volumeZero.texto), findsOneWidget);
    expect(find.text(semDnd.texto), findsNothing);
    expect(corDaFaixa(tester), AppColors.error);

    await tester.tap(find.text(AvisoToqueBanner.textoBotao));
    await tester.pump();
    expect(aberta, CorrecaoToque.volumeAlarme);
  });

  testWidgets('só avisos → faixa laranja', (tester) async {
    await pump(
      tester,
      AvisoToqueBanner(lerProblemas: () async => const [semDnd]),
    );
    expect(find.text(semDnd.texto), findsOneWidget);
    expect(corDaFaixa(tester), AppColors.accent);
  });

  testWidgets('sem problemas → não desenha nada', (tester) async {
    await pump(tester, AvisoToqueBanner(lerProblemas: () async => const []));
    expect(find.byKey(faixa), findsNothing);
  });

  testWidgets('fora de serviço → nem lê nem avisa', (tester) async {
    var leituras = 0;
    await pump(
      tester,
      AvisoToqueBanner(
        ativo: false,
        lerProblemas: () async {
          leituras++;
          return const [volumeZero];
        },
      ),
    );
    expect(leituras, 0);
    expect(find.byKey(faixa), findsNothing);
  });

  testWidgets('leitura falha → não desenha nada e não rebenta',
      (tester) async {
    await pump(
      tester,
      AvisoToqueBanner(lerProblemas: () async => throw Exception('sem ponte')),
    );
    expect(find.byKey(faixa), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('volta ao primeiro plano → lê outra vez', (tester) async {
    var leituras = 0;
    await pump(
      tester,
      AvisoToqueBanner(lerProblemas: () async {
        leituras++;
        return const [];
      }),
    );
    expect(leituras, 1);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
    expect(leituras, 2);
  });
}
