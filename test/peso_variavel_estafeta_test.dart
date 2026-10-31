// Peso variável — folha da balança do estafeta (31/10/2026).
//
// Cicatriz: pedido 48669acf (Continente, 31/10) — a melancia saiu 9,06 € na
// balança, estava na app a 7,14 € e o estafeta não tinha onde pôr o valor.
// Provas: o intervalo bate com o do servidor (CEIL/FLOOR em cêntimos), as
// respostas da RPC lêem-se certas, a folha não envia duas vezes, mostra o erro
// real com o intervalo do servidor e devolve o ajuste quando o servidor aceita.
import 'dart:async';

import 'package:bora_app/services/peso_variavel_estafeta_service.dart';
import 'package:bora_app/widgets/peso_variavel_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('PesoVariavelEstafetaService', () {
    test('intervalo igual ao do servidor (±30 %, CEIL/FLOOR)', () {
      // Banana 4 un. no pedido 11926093: previsto 1,12 → 0,79..1,45.
      expect(PesoVariavelEstafetaService.intervalo(112), (79, 145));
      // Frango previsto 4,75 € → aceite até 6,17 € (6,50 € é recusado).
      expect(PesoVariavelEstafetaService.intervalo(475), (333, 617));
      expect(PesoVariavelEstafetaService.intervalo(100), (70, 130));
    });

    test('euros em PT-PT', () {
      expect(PesoVariavelEstafetaService.euros(120), '1,20 €');
      expect(PesoVariavelEstafetaService.euros(906), '9,06 €');
      expect(PesoVariavelEstafetaService.euros(-2), '-0,02 €');
    });

    test('resposta ok vira ajuste com a diferença do cliente', () {
      final r = PesoVariavelEstafetaService.lerResposta('cont-1', {
        'ok': true,
        'estimado_caixa_cents': 98,
        'real_caixa_cents': 120,
        'estimado_cliente_cents': 112,
        'novo_cliente_cents': 137,
      });
      expect(r.ok, isTrue);
      expect(r.ajuste!.realCaixaCents, 120);
      expect(r.ajuste!.diferencaClienteCents, 25);
    });

    test('fora_do_limite traz o intervalo do servidor na mensagem', () {
      final r = PesoVariavelEstafetaService.lerResposta('cont-1', {
        'ok': false,
        'erro': 'fora_do_limite',
        'minimo_cents': 333,
        'maximo_cents': 617,
      });
      expect(r.ok, isFalse);
      expect(r.codigo, 'fora_do_limite');
      expect(r.mensagem, contains('Pesa outra vez'));
      expect(r.mensagem, contains('3,33 €'));
      expect(r.mensagem, contains('6,17 €'));
    });

    test('linha da tabela order_weight_adjustments', () {
      final a = AjustePesoEstafeta.daTabela({
        'product_id': 'cont-5050572',
        'est_base_cents': 714,
        'real_base_cents': 906,
        'est_client_cents': 821,
        'new_client_cents': 1042,
      });
      expect(a, isNotNull);
      expect(a!.diferencaClienteCents, 221);
      expect(AjustePesoEstafeta.daTabela({'product_id': ''}), isNull);
    });

    test('códigos conhecidos têm texto próprio', () {
      for (final c in [
        'compra_ja_fechada',
        'desligado',
        'sem_rede',
        'valor_invalido',
      ]) {
        expect(PesoVariavelEstafetaService.mensagemErro(c),
            isNot(contains('Código:')));
      }
      expect(PesoVariavelEstafetaService.mensagemErro('XPTO'),
          contains('Código: XPTO'));
    });
  });

  group('PesoVariavelSheet', () {
    Future<void> abrir(
      WidgetTester tester,
      Future<PesoVariavelResultado> Function(int) enviar,
      ValueChanged<AjustePesoEstafeta?> fim,
    ) async {
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (ctx) => ElevatedButton(
              onPressed: () async {
                fim(await PesoVariavelSheet.abrir(
                  ctx,
                  nomeLinha: 'Melancia × 1',
                  estimadoCaixaCents: 714,
                  enviar: enviar,
                ));
              },
              child: const Text('abrir'),
            ),
          ),
        ),
      ));
      await tester.tap(find.text('abrir'));
      await tester.pumpAndSettle();
    }

    testWidgets('mostra previsto e intervalo; aceita e devolve o ajuste',
        (tester) async {
      AjustePesoEstafeta? devolvido;
      final enviados = <int>[];
      await abrir(tester, (cents) async {
        enviados.add(cents);
        return PesoVariavelResultado.sucesso(const AjustePesoEstafeta(
          productId: 'cont-5050572',
          estimadoCaixaCents: 714,
          realCaixaCents: 906,
          estimadoClienteCents: 821,
          novoClienteCents: 1042,
        ));
      }, (a) => devolvido = a);

      expect(find.text('Quanto custou na etiqueta da balança?'), findsOneWidget);
      expect(find.byKey(const Key('peso_intervalo')), findsOneWidget);
      expect(find.textContaining('Previsto: 7,14 €'), findsOneWidget);
      expect(find.textContaining('aceite de 5,00 € a 9,28 €'), findsOneWidget);

      await tester.enterText(find.byKey(const Key('peso_campo')), '9,06');
      await tester.tap(find.byKey(const Key('peso_confirmar')));
      await tester.pumpAndSettle();

      expect(enviados, [906]);
      expect(devolvido?.realCaixaCents, 906);
      expect(find.byType(PesoVariavelSheet), findsNothing);
    });

    testWidgets('valor vazio não chama o servidor', (tester) async {
      var chamadas = 0;
      await abrir(tester, (_) async {
        chamadas++;
        return PesoVariavelResultado.erro('x');
      }, (_) {});
      await tester.tap(find.byKey(const Key('peso_confirmar')));
      await tester.pump();
      expect(chamadas, 0);
      expect(find.byKey(const Key('peso_erro')), findsOneWidget);
    });

    testWidgets('recusa do servidor fica na folha com o intervalo dele',
        (tester) async {
      await abrir(
        tester,
        (_) async => PesoVariavelResultado.erro('fora_do_limite',
            minimoCents: 500, maximoCents: 928),
        (_) {},
      );
      await tester.enterText(find.byKey(const Key('peso_campo')), '15');
      await tester.tap(find.byKey(const Key('peso_confirmar')));
      await tester.pumpAndSettle();
      expect(find.byType(PesoVariavelSheet), findsOneWidget);
      expect(find.textContaining('Pesa outra vez'), findsOneWidget);
    });

    testWidgets('toque duplo envia uma vez só', (tester) async {
      final c = Completer<PesoVariavelResultado>();
      var chamadas = 0;
      await abrir(tester, (_) {
        chamadas++;
        return c.future;
      }, (_) {});
      await tester.enterText(find.byKey(const Key('peso_campo')), '8');
      await tester.tap(find.byKey(const Key('peso_confirmar')));
      await tester.pump();
      await tester.tap(find.byKey(const Key('peso_confirmar')),
          warnIfMissed: false);
      await tester.pump();
      expect(chamadas, 1);
      c.complete(PesoVariavelResultado.erro('sem_rede'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Sem ligação'), findsOneWidget);
    });
  });
}
