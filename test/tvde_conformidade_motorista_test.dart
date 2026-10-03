import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:bora_app/services/tvde_conformidade_service.dart';
import 'package:bora_app/widgets/tvde/tvde_horas_servico_card.dart';

/// [Conformidade TVDE · Lei 59/2026] Lado do motorista.
///
/// O contador de horas é informativo (Lei 45/2018 art. 13.º): mostra as horas
/// das últimas 24 h contra o limite e só diz "atingiste o limite" quando o
/// servidor já aplica o limite (`limite_efetivo`). Com o interruptor
/// desligado — como está em produção — nunca aparece a mensagem.
///
/// As mensagens de erro do servidor (TVDE_BLOQUEADO, LIMITE_HORAS) têm de
/// chegar ao motorista em PT-PT, nunca como exceção crua.
Future<void> _pump(WidgetTester tester, Widget w) => tester.pumpWidget(
    MaterialApp(home: Scaffold(body: Padding(padding: const EdgeInsets.all(16), child: w))));

void main() {
  group('TvdeHorasServicoCard', () {
    testWidgets('mostra "X h de 10 h"', (tester) async {
      await _pump(
          tester, const TvdeHorasServicoCard(horasTotal: 4, limite: 10));
      expect(find.textContaining('4 h de 10 h'), findsOneWidget);
      expect(find.byType(LinearProgressIndicator), findsOneWidget);
    });

    testWidgets('horas com decimais usam vírgula', (tester) async {
      await _pump(
          tester, const TvdeHorasServicoCard(horasTotal: 7.5, limite: 10));
      expect(find.textContaining('7,5 h de 10 h'), findsOneWidget);
    });

    testWidgets('mostra as horas declaradas noutras plataformas',
        (tester) async {
      await _pump(
          tester,
          const TvdeHorasServicoCard(
              horasTotal: 6, limite: 10, horasOutras: 2));
      expect(find.textContaining('Noutras plataformas: 2 h (declarado)'),
          findsOneWidget);
    });

    testWidgets('limite efetivo e horas >= limite → mensagem do limite',
        (tester) async {
      await _pump(
          tester,
          const TvdeHorasServicoCard(
              horasTotal: 10, limite: 10, limiteEfetivo: true));
      expect(find.text('Atingiste o limite legal de 10 horas'), findsOneWidget);
    });

    testWidgets('usa o valor do limite vindo do servidor', (tester) async {
      await _pump(
          tester,
          TvdeHorasServicoCard.fromConformidade(const {
            'horas_total_24h': 9,
            'limite_horas': 8,
            'limite_efetivo': true,
            'horas_outras_plataformas': 0,
          }));
      expect(find.textContaining('9 h de 8 h'), findsOneWidget);
      expect(find.text('Atingiste o limite legal de 8 horas'), findsOneWidget);
    });

    testWidgets('limite NÃO efetivo → sem mensagem, mesmo acima do limite',
        (tester) async {
      await _pump(
          tester,
          const TvdeHorasServicoCard(
              horasTotal: 12, limite: 10, limiteEfetivo: false));
      expect(find.textContaining('Atingiste o limite legal'), findsNothing);
      expect(find.byKey(const Key('tvde_horas_limite_atingido')), findsNothing);
    });

    testWidgets('limite efetivo mas abaixo do limite → sem mensagem',
        (tester) async {
      await _pump(
          tester,
          const TvdeHorasServicoCard(
              horasTotal: 9.9, limite: 10, limiteEfetivo: true));
      expect(find.textContaining('Atingiste o limite legal'), findsNothing);
    });
  });

  group('mensagemErroConformidade', () {
    test('TVDE_BLOQUEADO traz os motivos em PT-PT', () {
      final m = mensagemErroConformidade(Exception(
          'PostgrestException(message: TVDE_BLOQUEADO: Sem operador; Seguro caducado, code: P0001)'));
      expect(m, startsWith('Não podes ficar online: '));
      expect(m, contains('Sem operador'));
      expect(m, isNot(contains('TVDE_BLOQUEADO')));
    });

    test('LIMITE_HORAS vira a frase do limite legal', () {
      final m = mensagemErroConformidade(
          Exception('PostgrestException(message: LIMITE_HORAS: 10.2 de 10)'));
      expect(m,
          'Atingiste o limite legal de horas de serviço nas últimas 24 horas.');
    });

    test('erro desconhecido não expõe a exceção crua', () {
      final m = mensagemErroConformidade(Exception('qualquer_coisa_interna'));
      expect(m, 'Não foi possível concluir. Tenta outra vez.');
    });
  });
}
