import 'dart:io';

import 'package:bora_app/screens/admin/admin_avisos_prestadores_screen.dart';
import 'package:bora_app/screens/prestador/como_o_bora_decide_screen.dart';
import 'package:bora_app/services/prestador_avisos_service.dart';
import 'package:bora_app/widgets/como_o_bora_decide_gate.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Missão fechar-tudo-2026-11-10, bloco E4 — "Como o Bora decide" entregue a
/// cada prestador (Diretiva (UE) 2024/2831, art. 9.º; prazo 02/12/2026):
/// aparece uma vez por versão, "Li e percebi" grava, o painel conta quem leu.
void main() {
  const v = ComoOBoraDecide.versaoId;

  group('aparece uma vez por versão', () {
    test('nunca leu → aparece', () {
      expect(
          PrestadorAvisos.precisaDeMostrar(
              respondeu: true, versoesLidas: const {}, versaoAtual: v),
          isTrue);
    });

    test('já leu a versão em vigor → não aparece', () {
      expect(
          PrestadorAvisos.precisaDeMostrar(
              respondeu: true, versoesLidas: const {v}, versaoAtual: v),
          isFalse);
    });

    test('só leu uma versão antiga → aparece outra vez (versão nova)', () {
      expect(
          PrestadorAvisos.precisaDeMostrar(
              respondeu: true,
              versoesLidas: const {'2026-11-01'},
              versaoAtual: v),
          isTrue);
    });

    test('servidor não respondeu → não aparece (falha aberta)', () {
      expect(
          PrestadorAvisos.precisaDeMostrar(
              respondeu: false, versoesLidas: const {}, versaoAtual: v),
          isFalse);
    });

    test('a versão cabe na coluna (1 a 40 letras) e é a de 10/11', () {
      expect(v.length, inInclusiveRange(1, 40));
      expect(v, '2026-11-10');
      expect(ComoOBoraDecide.aviso, 'como_o_bora_decide');
    });
  });

  group('texto: as duas páginas do livro', () {
    test('7 secções da 1.ª página + resumo da política de suspensão', () {
      expect(ComoOBoraDecide.seccoes, hasLength(7));
      expect(ComoOBoraDecide.suspensoes, hasLength(2));
      final tudo = [
        for (final (t, ps) in [
          ...ComoOBoraDecide.seccoes,
          ...ComoOBoraDecide.suspensoes
        ]) ...[t, ...ps],
      ].join(' ');
      // O que obriga a Bora não pode ter caído no resumo.
      for (final obrigatorio in [
        'nunca suspende',
        'motivo por escrito',
        'quem decidiu',
        'no mesmo dia',
        'Pedir revisão',
        'quantas vezes tiver factos novos',
        'nunca pela app nem por um robô',
        '7 dias',
        'reativa a conta no mesmo dia',
        'compensa',
        'acaba sozinha na data marcada',
        'ACT ou à CNPD',
        '30 dias de aviso',
        'NIPC 519686233',
      ]) {
        expect(tudo, contains(obrigatorio), reason: 'falta: $obrigatorio');
      }
    });
  });

  group('portão', () {
    setUp(ComoOBoraDecideGate.limparSessaoParaTeste);

    Future<void> ecraAlto(WidgetTester t) async {
      t.view.physicalSize = const Size(1200, 40000);
      t.view.devicePixelRatio = 1.0;
      addTearDown(t.view.reset);
    }

    Widget portao({
      required LerVersoesAviso ler,
      MarcarAvisoLido? marcar,
      bool ativo = true,
      String? uid = 'u1',
      Key? key,
    }) =>
        MaterialApp(
          home: ComoOBoraDecideGate(
            key: key,
            ativo: ativo,
            papel: 'limpeza',
            uidAtual: () => uid,
            lerVersoes: ler,
            marcarLido: marcar ?? (_) async {},
            child: const Scaffold(body: Text('ECRA DE TRABALHO')),
          ),
        );

    testWidgets(
        'nunca leu: texto inteiro com "Li e percebi"; carregar grava e tira o '
        'aviso; na mesma sessão não volta a perguntar', (t) async {
      await ecraAlto(t);
      final gravados = <String?>[];
      var leituras = 0;
      Future<({bool respondeu, Set<String> versoes})> ler() async {
        leituras++;
        return (respondeu: true, versoes: <String>{});
      }

      await t.pumpWidget(portao(ler: ler, marcar: (p) async => gravados.add(p)));
      await t.pumpAndSettle();

      expect(find.text(ComoOBoraDecideScreen.textoBotaoLi), findsOneWidget);
      expect(find.text(ComoOBoraDecide.titulo), findsOneWidget);
      expect(find.text(ComoOBoraDecide.tituloSuspensoes), findsOneWidget);
      // O ecrã de trabalho continua montado por baixo.
      expect(find.text('ECRA DE TRABALHO'), findsOneWidget);

      await t.tap(find.byKey(const ValueKey('como-decide-li-e-percebi')));
      await t.pumpAndSettle();

      expect(gravados, ['limpeza']);
      expect(find.text(ComoOBoraDecideScreen.textoBotaoLi), findsNothing);
      expect(find.text('ECRA DE TRABALHO'), findsOneWidget);

      await t.pumpWidget(portao(ler: ler, key: UniqueKey()));
      await t.pumpAndSettle();
      expect(leituras, 1, reason: 'já resolvido nesta sessão');
      expect(find.text(ComoOBoraDecideScreen.textoBotaoLi), findsNothing);
      expect(t.takeException(), isNull);
    });

    testWidgets('já leu a versão em vigor: não mostra', (t) async {
      await ecraAlto(t);
      await t.pumpWidget(portao(
          ler: () async => (respondeu: true, versoes: <String>{v})));
      await t.pumpAndSettle();
      expect(find.text(ComoOBoraDecideScreen.textoBotaoLi), findsNothing);
      expect(find.text('ECRA DE TRABALHO'), findsOneWidget);
    });

    testWidgets('só leu a versão antiga: mostra outra vez', (t) async {
      await ecraAlto(t);
      await t.pumpWidget(portao(
          ler: () async =>
              (respondeu: true, versoes: <String>{'2026-11-01'})));
      await t.pumpAndSettle();
      expect(find.text(ComoOBoraDecideScreen.textoBotaoLi), findsOneWidget);
    });

    testWidgets('sem papel aprovado: nem pergunta ao servidor', (t) async {
      await ecraAlto(t);
      var leituras = 0;
      await t.pumpWidget(portao(
        ativo: false,
        ler: () async {
          leituras++;
          return (respondeu: true, versoes: <String>{});
        },
      ));
      await t.pumpAndSettle();
      expect(leituras, 0);
      expect(find.text(ComoOBoraDecideScreen.textoBotaoLi), findsNothing);
    });

    testWidgets('sem sessão: não pergunta nem tranca', (t) async {
      await ecraAlto(t);
      var leituras = 0;
      await t.pumpWidget(portao(
        uid: null,
        ler: () async {
          leituras++;
          return (respondeu: true, versoes: <String>{});
        },
      ));
      await t.pumpAndSettle();
      expect(leituras, 0);
      expect(find.text('ECRA DE TRABALHO'), findsOneWidget);
    });

    testWidgets('falha a gravar: o aviso fica e diz porquê', (t) async {
      await ecraAlto(t);
      await t.pumpWidget(portao(
        ler: () async => (respondeu: true, versoes: <String>{}),
        marcar: (_) async => throw StateError('sem rede'),
      ));
      await t.pumpAndSettle();
      await t.tap(find.byKey(const ValueKey('como-decide-li-e-percebi')));
      await t.pumpAndSettle();
      expect(find.textContaining('Não foi possível guardar'), findsOneWidget);
      expect(find.text(ComoOBoraDecideScreen.textoBotaoLi), findsOneWidget);
    });

    testWidgets('só leitura (Sobre / Informação legal): sem botão',
        (t) async {
      await ecraAlto(t);
      await t.pumpWidget(const MaterialApp(home: ComoOBoraDecideScreen()));
      await t.pump();
      expect(find.text(ComoOBoraDecideScreen.textoBotaoLi), findsNothing);
      expect(find.text(ComoOBoraDecide.tituloSuspensoes), findsOneWidget);
    });
  });

  group('painel admin', () {
    final linhas = <Map<String, dynamic>>[
      {'papel': 'estafeta', 'aprovacao': 'approved', 'ativo': true, 'lido_em': '2026-11-10T10:00:00Z'},
      {'papel': 'estafeta', 'aprovacao': 'approved', 'ativo': true, 'lido_em': null},
      {'papel': 'estafeta', 'aprovacao': 'pending', 'ativo': true, 'lido_em': null},
      {'papel': 'limpeza', 'aprovacao': 'approved', 'ativo': false, 'lido_em': null},
      {'papel': 'limpeza', 'aprovacao': 'approved', 'ativo': true, 'lido_em': '2026-11-10T11:00:00Z'},
    ];

    test('quem leu e quem falta por papel (só aprovados e ativos)', () {
      expect(LeiturasAviso.porPapel(linhas),
          {'estafeta': (1, 2), 'limpeza': (1, 1)});
    });

    test('com todos (também por aprovar e inativos)', () {
      expect(LeiturasAviso.porPapel(linhas, soAprovados: false),
          {'estafeta': (1, 3), 'limpeza': (1, 2)});
    });

    test('nomes dos papéis em PT-BR', () {
      expect(LeiturasAviso.nomePapel('estafeta'), 'Entregador');
      expect(LeiturasAviso.nomePapel('casa'), 'Casa');
      expect(LeiturasAviso.nomePapel('outro'), 'outro');
    });

    test('ecrã no menu do painel', () {
      final menu = File('lib/screens/admin/admin_menu_registry.dart')
          .readAsStringSync();
      expect(menu, contains('builder: () => const AdminAvisosPrestadoresScreen()'));
    });
  });

  group('migração', () {
    final sql = File(
            'supabase/migrations/20261110190000_prestador_avisos_lidos.sql')
        .readAsStringSync();

    test('funções novas fechadas a anon e guarda de admin por is_admin()', () {
      expect(
          sql,
          contains('REVOKE ALL ON FUNCTION public.prestador_marcar_aviso_lido'
              '(text, text, text, text) FROM public, anon;'));
      expect(
          sql,
          contains('REVOKE ALL ON FUNCTION public.admin_avisos_prestadores'
              '(text, text) FROM public, anon;'));
      expect(sql, contains('IF NOT public.is_admin() THEN'));
      expect(sql.toLowerCase(), isNot(contains('current_user')));
    });

    test('uma linha por pessoa e versão; RLS cada um o seu, admin tudo', () {
      expect(sql, contains('UNIQUE (user_id, aviso, versao)'));
      expect(sql, contains('ON CONFLICT (user_id, aviso, versao) DO NOTHING'));
      expect(sql, contains('USING (user_id = auth.uid() OR public.is_admin())'));
      expect(sql, contains('WITH CHECK (user_id = auth.uid())'));
      expect(sql, isNot(contains('FOR UPDATE')));
      expect(sql, isNot(contains('FOR DELETE')));
    });
  });
}
