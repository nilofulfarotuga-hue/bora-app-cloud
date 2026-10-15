import 'package:bora_app/services/receita_service.dart';
import 'package:bora_app/widgets/home/receita_do_dia_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Receita do Dia (Bora Todo Dia, 15/10/2026).
void main() {
  Map<String, dynamic> resposta({bool enabled = true}) => {
        'enabled': enabled,
        'dia': '2026-10-15',
        'aviso_disponivel': true,
        'aviso_hora': 10,
        'aviso_ligado': false,
        'receita': {
          'id': 'r1',
          'titulo': 'Bifanas no pão',
          'resumo': 'Sabor de tasca, feitas em casa.',
          'ingredientes': [
            {'nome': 'Bifanas de porco', 'quantidade': '600 g', 'pesquisa': 'bifanas de porco', 'unidades': 2},
            {'nome': 'Alho', 'quantidade': '4 dentes', 'unidades': 99},
            {'nome': '', 'quantidade': 'sem nome não conta'},
          ],
          'passos': ['Tempera as febras.', '  ', 'Frita.'],
          'tempo_min': 25,
          'doses': 4,
          'foto_url': '',
        },
      };

  group('ReceitaHoje.fromJson', () {
    test('desligada no servidor → não há cartão', () {
      expect(ReceitaHoje.fromJson(resposta(enabled: false)), isNull);
      expect(ReceitaHoje.fromJson({'enabled': true}), isNull);
    });

    test('lê a receita, limpa linhas vazias e usa o nome quando falta o termo', () {
      final h = ReceitaHoje.fromJson(resposta())!;
      expect(h.receita.titulo, 'Bifanas no pão');
      expect(h.receita.ingredientes.length, 2);
      expect(h.receita.ingredientes[1].pesquisa, 'Alho');
      // Embalagens para o carrinho: as do servidor, entre 1 e 20.
      expect(h.receita.ingredientes[0].unidades, 2);
      expect(h.receita.ingredientes[1].unidades, 20);
      expect(h.receita.passos, ['Tempera as febras.', 'Frita.']);
      expect(h.receita.fotoUrl, isNull);
      expect(h.avisoHora, 10);
      expect(h.avisoDisponivel, isTrue);
      expect(h.avisoLigado, isFalse);
      expect(h.copyWith(avisoLigado: true).avisoLigado, isTrue);
    });

    test('hora do aviso fora de 0-23 fica dentro', () {
      final m = resposta()..['aviso_hora'] = 99;
      expect(ReceitaHoje.fromJson(m)!.avisoHora, 23);
    });
  });

  group('ReceitaDoDiaCard', () {
    Widget app(Future<ReceitaHoje?> Function() carregar) => MaterialApp(
          home: Scaffold(body: ReceitaDoDiaCard(carregar: carregar)),
        );

    testWidgets('sem receita não ocupa espaço', (tester) async {
      await tester.pumpWidget(app(() async => null));
      await tester.pump();
      expect(find.byKey(const Key('receita_do_dia_card')), findsNothing);
    });

    testWidgets('mostra o título e quantos ingredientes tem', (tester) async {
      final h = ReceitaHoje.fromJson(resposta())!;
      await tester.pumpWidget(app(() async => h));
      await tester.pump();
      expect(find.byKey(const Key('receita_do_dia_card')), findsOneWidget);
      expect(find.text('Bifanas no pão'), findsOneWidget);
      expect(find.text('Receita do dia'), findsOneWidget);
      expect(find.text('25 min · 2 ingredientes'), findsOneWidget);
    });
  });
}
