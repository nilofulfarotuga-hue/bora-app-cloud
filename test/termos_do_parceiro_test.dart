import 'dart:io';

import 'package:bora_app/screens/admin/admin_menu_registry.dart';
import 'package:bora_app/screens/admin/admin_parceiros_termos_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show PostgrestException;

/// Missão boom-burger-2026-10-27, F4 — termos do parceiro (Regulamento UE
/// 2019/1150), parte do painel admin e a ligação no main.dart.
///
///  1. As linhas de `admin_parceiros_termos()` dizem "Pendente" ou "Aceitou a
///     versão X em dd/mm/aaaa hh:mm · via" (hora de Lisboa).
///  2. "Registrar aceite" pede a via e a nota e chama a função com elas; a
///     loja sem conta de dono não tem botão ativo.
///  3. O ecrã está no menu do admin, na secção Parceiros, fora do arquivo.
///  4. O painel do parceiro entra embrulhado em TermsGate('parceiro').
void main() {
  const atual = '2026-10-28';
  final linhas = [
    TermoParceiroLinha.fromJson(const {
      'restaurant_id': 'r-boom',
      'loja': 'Boom! Burger',
      'user_id': '00000000-0000-4000-8000-000000000001',
      'email': 'boom@exemplo.pt',
      'versao_atual': atual,
      'versao_aceite': null,
      'aceite_em': null,
      'via': null,
      'nota': null,
    }),
    TermoParceiroLinha.fromJson(const {
      'restaurant_id': 'r-goola',
      'loja': 'Goola Açaí',
      'user_id': '00000000-0000-4000-8000-000000000002',
      'email': 'goola@exemplo.pt',
      'versao_atual': atual,
      'versao_aceite': atual,
      'aceite_em': '2026-10-27T12:05:00+00:00',
      'via': 'whatsapp',
      'nota': 'respondeu Aceito',
    }),
    TermoParceiroLinha.fromJson(const {
      'restaurant_id': 'r-sem-dono',
      'loja': 'Loja Sem Dono',
      'user_id': null,
      'versao_atual': atual,
    }),
  ];

  group('funções puras', () {
    test('estado de cada linha', () {
      expect(estadoTermoParceiro(linhas[0]), 'Pendente');
      expect(estadoTermoParceiro(linhas[1]),
          'Aceitou a versão 2026-10-28 em 27/10/2026 12:05 · WhatsApp');
      final antiga = TermoParceiroLinha.fromJson(const {
        'restaurant_id': 'x',
        'loja': 'X',
        'versao_atual': '2026-10-28',
        'versao_aceite': '2026-01-01',
        'aceite_em': '2026-07-01T10:00:00Z',
      });
      expect(antiga.aceiteAtual, isFalse);
      // Julho = horário de verão: 10:00 UTC são 11:00 em Lisboa.
      expect(estadoTermoParceiro(antiga),
          'Pendente (aceitou a versão antiga 2026-01-01 em 01/07/2026 11:00)');
    });

    test('via em palavras', () {
      expect(rotuloViaTermos('whatsapp'), 'WhatsApp');
      expect(rotuloViaTermos('email'), 'email');
      expect(rotuloViaTermos('android'), 'no app (android)');
      expect(rotuloViaTermos(null), '—');
    });

    test('erros do servidor em PT-BR', () {
      String m(String s) =>
          mensagemErroTermosParceiro(PostgrestException(message: s));
      expect(m('admin_required'), 'Sem permissão de admin.');
      expect(m('via_invalida'), 'Escolha WhatsApp ou email.');
      expect(m('loja_sem_conta'), contains('não tem conta de dono'));
      expect(m('sem_versao_parceiro'), contains('Não há versão'));
      expect(m('xpto'), 'Erro do servidor: xpto');
    });
  });

  group('ecrã "Termos dos parceiros"', () {
    testWidgets('lista, resumo e registar aceite por email com nota',
        (tester) async {
      tester.view.physicalSize = const Size(800, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final chamadas = <(String, String, String)>[];
      var leituras = 0;
      await tester.pumpWidget(MaterialApp(
        home: AdminParceirosTermosScreen(
          carregar: () async {
            leituras++;
            return linhas;
          },
          registar: (id, via, nota) async {
            chamadas.add((id, via, nota));
            return {'ok': true, 'version': atual, 'ja_aceite': false};
          },
        ),
      ));
      await tester.pumpAndSettle();

      expect(find.text('Termos dos parceiros'), findsOneWidget);
      expect(find.text('Versão em vigor: 2026-10-28. 1 de 3 lojas aceitaram.'),
          findsOneWidget);
      expect(find.text('Pendente'), findsNWidgets(2));
      expect(find.textContaining('Aceitou a versão 2026-10-28'), findsOneWidget);
      expect(find.text('Nota: respondeu Aceito'), findsOneWidget);
      // Quem já aceitou não tem botão; a loja sem dono tem o botão desligado.
      expect(find.text('Registrar aceite'), findsOneWidget);
      final semDono = tester.widget<OutlinedButton>(find.ancestor(
          of: find.text('Loja sem conta de dono'),
          matching: find.byWidgetPredicate((w) => w is OutlinedButton)));
      expect(semDono.onPressed, isNull);

      await tester.tap(find.text('Registrar aceite'));
      await tester.pumpAndSettle();
      expect(find.text('Como o parceiro aceitou?'), findsOneWidget);
      await tester.tap(find.text('Email'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'email de 27/10 às 18h');
      await tester.tap(find.text('Registrar'));
      await tester.pumpAndSettle();

      expect(chamadas, [('r-boom', 'email', 'email de 27/10 às 18h')]);
      expect(find.text('Aceite registrado: Boom! Burger, versão 2026-10-28 (email).'),
          findsOneWidget);
      expect(leituras, 2, reason: 'depois de registar volta a ler');
    });

    testWidgets('cancelar o diálogo não chama o servidor', (tester) async {
      var chamou = false;
      await tester.pumpWidget(MaterialApp(
        home: AdminParceirosTermosScreen(
          carregar: () async => [linhas[0]],
          registar: (_, __, ___) async {
            chamou = true;
            return {};
          },
        ),
      ));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Registrar aceite'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cancelar'));
      await tester.pumpAndSettle();
      expect(chamou, isFalse);
    });

    testWidgets('erro de leitura humanizado + "Tentar de novo"', (tester) async {
      var n = 0;
      await tester.pumpWidget(MaterialApp(
        home: AdminParceirosTermosScreen(
          carregar: () async {
            n++;
            if (n == 1) {
              throw const PostgrestException(message: 'admin_required');
            }
            return const [];
          },
        ),
      ));
      await tester.pumpAndSettle();
      expect(find.text('Sem permissão de admin.'), findsOneWidget);
      await tester.tap(find.text('Tentar de novo'));
      await tester.pumpAndSettle();
      expect(find.text('Nenhuma loja parceira aprovada.'), findsOneWidget);
    });
  });

  group('ligações', () {
    test('"Termos dos parceiros" está no menu, secção Parceiros, fora do arquivo',
        () {
      final parceiros =
          adminMenuSections().firstWhere((s) => s.id == 'parceiros');
      final item = parceiros.items.where((i) => i.title == 'Termos dos parceiros');
      expect(item, hasLength(1));
      expect(item.single.id, 'parceiros_termos');
      expect(item.single.builder(), isA<AdminParceirosTermosScreen>());
      expect(adminMenuAllItems().where((i) => i.matches('termos')).map((i) => i.id),
          contains('parceiros_termos'));
    });

    test('main.dart embrulha o painel do parceiro em TermsGate(\'parceiro\')',
        () {
      final main = File('lib/main.dart').readAsStringSync();
      expect(
        RegExp(r"TermsGate\(\s*audience:\s*'parceiro',\s*child:\s*PartnerEntryScreen\(\)\)")
            .hasMatch(main),
        isTrue,
      );
      // Os dois de antes continuam.
      expect(main, contains("TermsGate(audience: 'cliente'"));
      expect(main, contains("TermsGate(audience: 'estafeta'"));
    });
  });
}
