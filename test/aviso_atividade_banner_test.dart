// O aviso "Falta o comprovativo de atividade" NUNCA bloqueia o trabalho
// (Bloco C · 20/10/2026), e o ecrã de envio nunca fica preso a rodar.
import 'dart:async';

import 'package:bora_app/screens/shared/comprovativo_atividade_screen.dart';
import 'package:bora_app/services/atividade_service.dart';
import 'package:bora_app/widgets/aviso_atividade_banner.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

AtividadeEstado _estado(String status,
        {bool doc = false, bool prestador = true}) =>
    AtividadeEstado.fromJson({
      'e_prestador': prestador,
      'papeis': ['estafeta'],
      'atividade_status': status,
      'tem_documento': doc,
      'nif_sugerido': '245123458',
    });

/// Um ecrã de trabalho a fingir: o aviso em cima, o botão de trabalho em baixo.
Widget _ecraDeTrabalho(AvisoAtividadeBanner banner, VoidCallback trabalhar) =>
    MaterialApp(
      home: Scaffold(
        body: Column(children: [
          banner,
          ElevatedButton(
              onPressed: trabalhar, child: const Text('Aceitar entrega')),
        ]),
      ),
    );

void main() {
  // O "×" esconde o aviso na sessão (memória): cada teste começa do zero.
  setUp(() => AvisoAtividadeBanner.dispensadoNestaSessao = false);

  testWidgets(
      'compacto: uma linha + Enviar; o × esconde na sessão só onde é dispensável',
      (tester) async {
    Future<AtividadeEstado?> carregar() async => _estado('por_enviar');
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Column(children: [
          AvisoAtividadeBanner(
              key: const Key('a'),
              carregar: carregar,
              compacto: true,
              dispensavel: true),
          AvisoAtividadeBanner(key: const Key('b'), carregar: carregar),
          ElevatedButton(
              onPressed: () {}, child: const Text('Aceitar entrega')),
        ]),
      ),
    ));
    await tester.pump();
    expect(find.text('Falta o comprovativo de atividade'), findsNWidgets(2));
    // o compacto não traz o texto longo (só o não-compacto o mostra)
    expect(find.textContaining('Podes continuar a trabalhar'), findsOneWidget);
    expect(find.byKey(const Key('aviso-atividade-fechar')), findsOneWidget);

    await tester.tap(find.byKey(const Key('aviso-atividade-fechar')));
    await tester.pump();
    expect(find.text('Falta o comprovativo de atividade'), findsOneWidget,
        reason: 'o não-dispensável continua lá');
    expect(AvisoAtividadeBanner.dispensadoNestaSessao, isTrue);
    expect(find.text('Aceitar entrega'), findsOneWidget);
  });

  testWidgets(
      'em candidatura: texto próprio, sem "podes continuar a trabalhar"',
      (tester) async {
    await tester.pumpWidget(_ecraDeTrabalho(
      AvisoAtividadeBanner(
          carregar: () async => _estado('por_enviar'), emCandidatura: true),
      () {},
    ));
    await tester.pump();
    expect(find.textContaining('candidatura seguir'), findsOneWidget);
    expect(find.textContaining('continuar a trabalhar'), findsNothing);
  });

  testWidgets(
      'por enviar: aparece o aviso com Enviar e o trabalho continua a funcionar',
      (tester) async {
    var trabalhou = 0;
    var abriu = 0;
    await tester.pumpWidget(_ecraDeTrabalho(
      AvisoAtividadeBanner(
        carregar: () async => _estado('por_enviar'),
        abrir: (_) async => abriu++,
      ),
      () => trabalhou++,
    ));
    await tester.pump();
    expect(find.text('Falta o comprovativo de atividade'), findsOneWidget);
    expect(find.textContaining('Podes continuar a trabalhar'), findsOneWidget);

    await tester.tap(find.text('Aceitar entrega'));
    expect(trabalhou, 1, reason: 'o aviso não pode bloquear o trabalho');

    await tester.tap(find.byKey(const Key('aviso-atividade-enviar')));
    await tester.pump();
    expect(abriu, 1);
  });

  testWidgets(
      'aprovado, em análise com documento, ou sem ser prestador: nada aparece',
      (tester) async {
    for (final e in [
      _estado('aprovada', doc: true),
      _estado('em_analise', doc: true),
      _estado('por_enviar', prestador: false),
    ]) {
      await tester.pumpWidget(_ecraDeTrabalho(
          AvisoAtividadeBanner(key: UniqueKey(), carregar: () async => e),
          () {}));
      await tester.pump();
      expect(find.byKey(const Key('aviso-atividade')), findsNothing,
          reason: e.rotulo);
      expect(find.text('Aceitar entrega'), findsOneWidget);
    }
  });

  testWidgets('sem rede / erro: falha aberta, sem aviso e sem bloquear',
      (tester) async {
    await tester.pumpWidget(_ecraDeTrabalho(
      AvisoAtividadeBanner(carregar: () async => throw Exception('offline')),
      () {},
    ));
    await tester.pump();
    expect(find.byKey(const Key('aviso-atividade')), findsNothing);
    expect(find.text('Aceitar entrega'), findsOneWidget);
  });

  testWidgets(
      'em análise SEM documento (disse que tem): o aviso pede o comprovativo',
      (tester) async {
    await tester.pumpWidget(_ecraDeTrabalho(
        AvisoAtividadeBanner(carregar: () async => _estado('em_analise')),
        () {}));
    await tester.pump();
    expect(find.text('Falta o comprovativo de atividade'), findsOneWidget);
  });

  group('ecrã do comprovativo', () {
    testWidgets(
        'carregamento que nunca responde não prende o ecrã (tecto + Tentar outra vez)',
        (tester) async {
      final nunca = Completer<AtividadeEstado?>();
      await tester.pumpWidget(MaterialApp(
        home: ComprovativoAtividadeScreen(carregar: () => nunca.future),
      ));
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      await tester.pump(const Duration(seconds: 11));
      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(find.byKey(const Key('atividade-tentar')), findsOneWidget);
    });

    testWidgets(
        'NIF pré-preenchido; enviar sem ficheiro explica o que falta; NIF errado avisa',
        (tester) async {
      var envios = 0;
      await tester.pumpWidget(MaterialApp(
        home: ComprovativoAtividadeScreen(
          carregar: () async => _estado('por_enviar'),
          enviar: ({required nif, required bytes}) async {
            envios++;
            return const EnvioAtividade.falhou('x');
          },
        ),
      ));
      await tester.pump();
      expect(find.text('245123458'), findsOneWidget);
      expect(find.textContaining('Estado: Por enviar'), findsOneWidget);

      await tester.tap(find.byKey(const Key('atividade-enviar')));
      await tester.pump();
      expect(find.text('Escolhe primeiro a foto ou o PDF do comprovativo.'),
          findsOneWidget);

      await tester.enterText(
          find.byKey(const Key('atividade-nif')), '245123459');
      await tester.tap(find.byKey(const Key('atividade-enviar')));
      await tester.pump();
      expect(find.textContaining('não é válido'), findsOneWidget);
      expect(envios, 0,
          reason: 'nada vai ao servidor sem NIF válido e ficheiro');
    });

    testWidgets('aprovado: mostra o estado e não mostra o formulário',
        (tester) async {
      await tester.pumpWidget(MaterialApp(
        home: ComprovativoAtividadeScreen(
            carregar: () async => _estado('aprovada', doc: true)),
      ));
      await tester.pump();
      expect(find.textContaining('Estado: Aprovada'), findsOneWidget);
      expect(find.byKey(const Key('atividade-enviar')), findsNothing);
    });

    testWidgets(
        'em análise COM documento: espera a decisão, sem formulário (ronda 1)',
        (tester) async {
      await tester.pumpWidget(MaterialApp(
        home: ComprovativoAtividadeScreen(
            carregar: () async => _estado('em_analise', doc: true)),
      ));
      await tester.pump();
      expect(find.textContaining('Estado: Em análise'), findsOneWidget);
      expect(find.byKey(const Key('atividade-enviar')), findsNothing);
    });

    testWidgets('em análise SEM documento (caso Mayra): o formulário está lá',
        (tester) async {
      await tester.pumpWidget(MaterialApp(
        home: ComprovativoAtividadeScreen(
            carregar: () async => _estado('em_analise')),
      ));
      await tester.pump();
      expect(
          find.textContaining('Estado: Falta o comprovativo'), findsOneWidget);
      expect(find.byKey(const Key('atividade-enviar')), findsOneWidget);
    });

    testWidgets(
        'modo cadastro: título de último passo e "Fazer depois" fecha o ecrã',
        (tester) async {
      await tester.pumpWidget(MaterialApp(
        home: Builder(
          builder: (ctx) => Scaffold(
            body: Center(
              child: ElevatedButton(
                onPressed: () => Navigator.of(ctx).push(MaterialPageRoute<void>(
                  builder: (_) => ComprovativoAtividadeScreen(
                    modoCadastro: true,
                    carregar: () async => _estado('por_enviar'),
                  ),
                )),
                child: const Text('abrir'),
              ),
            ),
          ),
        ),
      ));
      await tester.tap(find.text('abrir'));
      await tester.pumpAndSettle();
      expect(
          find.text('Último passo: comprovativo de atividade'), findsOneWidget);
      await tester
          .ensureVisible(find.byKey(const Key('atividade-fazer-depois')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('atividade-fazer-depois')));
      await tester.pumpAndSettle();
      expect(find.text('abrir'), findsOneWidget);
    });
  });
}
