import 'dart:io';

import 'package:bora_app/screens/admin/admin_livro_reclamacoes_screen.dart';
import 'package:bora_app/utils/dias_uteis.dart';
import 'package:bora_app/widgets/admin/alerta_livro_reclamacoes_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Missão fechar-tudo-2026-11-10, bloco E2e — registo do Livro de
/// Reclamações com o prazo legal de 15 dias ÚTEIS (DL 156/2005, art. 5.º-B) e
/// aviso no painel quando faltam 3 ou menos, ou quando passou.
void main() {
  DateTime d(int a, int m, int dia) => DateTime(a, m, dia);

  group('feriados e dias úteis', () {
    test('Páscoa de 2026 é a 5 de abril; de 2027, a 28 de março', () {
      expect(domingoDePascoa(2026), d(2026, 4, 5));
      expect(domingoDePascoa(2027), d(2027, 3, 28));
    });

    test('feriados nacionais móveis e fixos', () {
      expect(eFeriadoNacional(d(2026, 4, 3)), isTrue, reason: 'Sexta-feira Santa');
      expect(eFeriadoNacional(d(2026, 6, 4)), isTrue, reason: 'Corpo de Deus');
      expect(eFeriadoNacional(d(2026, 12, 1)), isTrue);
      expect(eFeriadoNacional(d(2026, 12, 8)), isTrue);
      expect(eFeriadoNacional(d(2026, 11, 27)), isFalse,
          reason: 'o municipal da Guarda não conta (prazo nunca mais longo)');
    });

    test('sábado, domingo e feriado não são úteis', () {
      expect(eDiaUtil(d(2026, 11, 14)), isFalse); // sábado
      expect(eDiaUtil(d(2026, 11, 15)), isFalse); // domingo
      expect(eDiaUtil(d(2026, 12, 1)), isFalse); // feriado (terça)
      expect(eDiaUtil(d(2026, 11, 10)), isTrue); // terça
    });
  });

  group('prazo de 15 dias úteis', () {
    test('recebida terça 10/11/2026 → quarta 02/12/2026 (salta o 1 de dezembro)',
        () {
      expect(somarDiasUteis(d(2026, 11, 10), 15), d(2026, 12, 2));
    });

    test('recebida sexta 27/03/2026 → segunda 20/04/2026 (salta a Sexta-feira Santa)',
        () {
      expect(somarDiasUteis(d(2026, 3, 27), 15), d(2026, 4, 20));
    });

    test('recebida num sábado conta a partir de segunda', () {
      // 14/11 sábado → 1.º dia útil 16/11 … 14.º = 04/12, 15.º = segunda 07/12
      // (sem o 01/12).
      expect(somarDiasUteis(d(2026, 11, 14), 15), d(2026, 12, 7));
    });

    test('a hora da receção não muda o prazo', () {
      expect(somarDiasUteis(DateTime(2026, 11, 10, 23, 59), 15), d(2026, 12, 2));
    });
  });

  group('contagem e alerta', () {
    final prazo = d(2026, 12, 2);

    test('dias úteis que faltam (o prazo conta, hoje não)', () {
      expect(diasUteisAtePrazo(d(2026, 11, 20), prazo), 7);
      expect(diasUteisAtePrazo(d(2026, 11, 27), prazo), 2); // 30/11 e 02/12
      expect(diasUteisAtePrazo(prazo, prazo), 0);
      expect(diasUteisAtePrazo(d(2026, 12, 4), prazo), -2); // 03 e 04/12
    });

    test('em dia, alerta com 3 ou menos, vencido depois do prazo', () {
      expect(estadoDoPrazo(hoje: d(2026, 11, 20), prazo: prazo),
          EstadoPrazoReclamacao.emDia);
      expect(estadoDoPrazo(hoje: d(2026, 11, 26), prazo: prazo),
          EstadoPrazoReclamacao.alerta); // 27, 30/11 e 02/12 = 3
      expect(estadoDoPrazo(hoje: d(2026, 11, 25), prazo: prazo),
          EstadoPrazoReclamacao.emDia); // 4 dias úteis
      expect(estadoDoPrazo(hoje: prazo, prazo: prazo),
          EstadoPrazoReclamacao.alerta);
      expect(estadoDoPrazo(hoje: d(2026, 12, 3), prazo: prazo),
          EstadoPrazoReclamacao.vencido);
      expect(estadoDoPrazo(hoje: d(2026, 12, 3), prazo: prazo, respondida: true),
          EstadoPrazoReclamacao.respondida);
    });

    test('vencido mesmo que só tenha passado um fim de semana', () {
      // Prazo sexta 04/12; no sábado já passou, com 0 dias úteis de atraso.
      expect(estadoDoPrazo(hoje: d(2026, 12, 5), prazo: d(2026, 12, 4)),
          EstadoPrazoReclamacao.vencido);
    });

    test('resumo para o aviso do painel', () {
      final r = resumoPrazos(
          [d(2026, 12, 2), d(2026, 11, 30), d(2026, 12, 20), d(2026, 11, 26)],
          d(2026, 11, 27));
      expect(r.vencidas, 1); // 26/11
      expect(r.aVencer, 2); // 30/11 e 02/12
    });

    test('texto do prazo no painel', () {
      expect(textoDoPrazo(hoje: d(2026, 11, 20), prazo: prazo),
          'Faltam 7 dias úteis — prazo 02/12/2026');
      expect(textoDoPrazo(hoje: prazo, prazo: prazo),
          'Prazo termina HOJE (02/12/2026)');
      expect(textoDoPrazo(hoje: d(2026, 12, 4), prazo: prazo),
          'VENCIDA — o prazo era 02/12/2026 (2 dias úteis de atraso)');
      expect(
          textoDoPrazo(
              hoje: d(2026, 12, 4),
              prazo: prazo,
              respondida: true,
              respondidaEm: d(2026, 11, 30)),
          'Respondida em 30/11/2026');
    });
  });

  group('aviso no painel', () {
    testWidgets('sem nada urgente não ocupa espaço', (t) async {
      await t.pumpWidget(MaterialApp(
          home: Scaffold(
              body: AlertaLivroReclamacoesCard(
                  carregarPrazos: () async => [DateTime(2099, 1, 1)]))));
      await t.pumpAndSettle();
      expect(find.byKey(const ValueKey('alerta-livro-reclamacoes')), findsNothing);
    });

    testWidgets('prazo vencido: aviso vermelho com a contagem', (t) async {
      await t.pumpWidget(MaterialApp(
          home: Scaffold(
              body: AlertaLivroReclamacoesCard(
                  carregarPrazos: () async => [DateTime(2020, 1, 2)]))));
      await t.pumpAndSettle();
      expect(find.byKey(const ValueKey('alerta-livro-reclamacoes')), findsOneWidget);
      expect(find.textContaining('1 reclamação com prazo VENCIDO'), findsOneWidget);
    });

    testWidgets('sem tabela (migração por aplicar): não rebenta', (t) async {
      await t.pumpWidget(MaterialApp(
          home: Scaffold(
              body: AlertaLivroReclamacoesCard(
                  carregarPrazos: () async => throw StateError('42P01')))));
      await t.pumpAndSettle();
      expect(t.takeException(), isNull);
      expect(find.byKey(const ValueKey('alerta-livro-reclamacoes')), findsNothing);
    });

    test('no topo do painel e no menu', () {
      final painel = File('lib/screens/admin/admin_dashboard_screen.dart')
          .readAsStringSync();
      expect(painel, contains('const AlertaLivroReclamacoesCard()'));
      final menu = File('lib/screens/admin/admin_menu_registry.dart')
          .readAsStringSync();
      expect(menu, contains('builder: () => const AdminLivroReclamacoesScreen()'));
    });

    test('migração: só admin, ninguém apaga, prazo depois da receção', () {
      final sql = File(
              'supabase/migrations/20261110190200_livro_reclamacoes_registo.sql')
          .readAsStringSync();
      expect(sql, contains('FOR SELECT TO authenticated USING (public.is_admin())'));
      expect(sql, contains('FOR INSERT TO authenticated WITH CHECK (public.is_admin())'));
      expect(sql, isNot(contains('FOR DELETE')));
      expect(sql, isNot(contains('FOR ALL')));
      expect(sql, contains('CHECK (prazo > recebida_em)'));
      expect(sql.toLowerCase(), isNot(contains('current_user')));
    });
  });
}
