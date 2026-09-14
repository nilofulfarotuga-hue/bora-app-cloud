import 'dart:io';

import 'package:bora_app/screens/admin/admin_menu_accordion.dart';
import 'package:bora_app/screens/admin/admin_menu_registry.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// [painel-admin-limpo · 14/09/2026] O que estes testes trancam:
///
///  1. O menu do painel vive num registo único, por secções, sem ecrãs
///     duplicados no nível principal; os sete ecrãs antigos de dinheiro estão
///     arquivados e abrem o hub "Dinheiro e acertos" já no separador certo.
///  2. O acordeão nasce fechado, abre ao toque, tem busca, favoritos e a
///     secção "Arquivado" escondida por defeito.
///  3. As rotas que os avisos usam existem em `main.dart`, o toque no push do
///     fecho vai para `/admin/acertos-semana` com a semana, e o dashboard lê o
///     RPC novo (Lisboa, sem demo, por vertical).
///  4. A falta automática das marcações morreu: o cron só pergunta.
///
/// Cicatriz que originou tudo: às 00:18 de 14/09 o painel dizia "Pedidos hoje
/// 1" — era um pedido de demonstração, e ainda era "ontem" em UTC.
void main() {
  group('registo do menu', () {
    final sections = adminMenuSections();
    final all = adminMenuAllItems();

    test('as 11 secções pedidas existem, pela ordem, e "Arquivado" é a última',
        () {
      final ids = sections.map((s) => s.id).toList();
      expect(ids, [
        'operacao',
        'dinheiro',
        'entregas',
        'tvde',
        'servicos',
        'limpeza',
        'reservas',
        'clientes',
        'parceiros',
        'sistema',
        'robos',
        'arquivado',
      ]);
      expect(sections.last.archived, isTrue);
      expect(sections.where((s) => s.archived).length, 1);
    });

    test('nenhum id repetido e todos os itens têm descrição em português', () {
      final ids = all.map((i) => i.id).toList();
      expect(ids.toSet().length, ids.length,
          reason: 'ids repetidos: '
              '${ids.where((id) => ids.where((x) => x == id).length > 1).toSet()}');
      for (final i in all) {
        expect(i.subtitle.trim().length, greaterThan(12),
            reason: '${i.title} sem linha a dizer o que faz');
      }
      expect(all.length, greaterThanOrEqualTo(80));
    });

    test('cada ecrã arquivado diz porquê, e os de dinheiro reencaminham para o hub',
        () {
      final arq = sections.last.items;
      expect(arq.length, greaterThanOrEqualTo(12));
      for (final i in arq) {
        expect(i.archivedReason, isNotNull, reason: '${i.title} sem motivo');
        expect(i.archivedReason!.trim(), isNotEmpty);
      }
      final antigosDinheiro = [
        'Pagamentos',
        'Fechamento Semanal — Estafetas',
        'Repasses a Parceiros',
        'Acerto reservas parceiros',
        'Fechamento Semanal — Barbearias',
        'Fechamento Semanal — Limpeza',
        'Pagamentos Connect',
        'Acerto semanal por pessoa',
        'Ganho do dia por pessoa',
      ];
      for (final t in antigosDinheiro) {
        final it = arq.where((i) => i.title == t).toList();
        expect(it, hasLength(1), reason: '$t devia estar arquivado uma vez');
        expect(it.first.archivedReason, contains('hub'));
      }
      // Fora do arquivo nenhum título se repete (uma verdade, um ecrã).
      final vivos = sections.where((s) => !s.archived).expand((s) => s.items);
      final titulos = vivos.map((i) => i.title).toList();
      expect(titulos.toSet().length, titulos.length,
          reason: 'título repetido fora do arquivo');
    });

    test('o hub "Dinheiro e acertos" é o primeiro item da secção de dinheiro e tem badge',
        () {
      final din = sections.firstWhere((s) => s.id == 'dinheiro');
      expect(din.items.first.title, 'Dinheiro e acertos');
      expect(din.items.first.badge, 'acertos');
    });

    test('a busca encontra por nome, descrição e palavra-chave', () {
      expect(all.where((i) => i.matches('acertos')).map((i) => i.title),
          contains('Dinheiro e acertos'));
      expect(all.where((i) => i.matches('CORRIDAS')).map((i) => i.title),
          contains('Corridas'));
      expect(all.where((i) => i.matches('tokens')).map((i) => i.title),
          contains('Tokens'));
      expect(all.where((i) => i.matches('faltas')).map((i) => i.title),
          contains('Marcações por confirmar e faltas'));
      expect(all.where((i) => i.matches('xyzzy')), isEmpty);
    });
  });

  group('acordeão do menu', () {
    Widget host(List<AdminMenuSection> secs, {List<String> favs = const []}) =>
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: AdminMenuAccordion(
                sections: secs,
                favoritos: favs,
                onToggleFavorito: (_) {},
                onOpen: (_, __) {},
              ),
            ),
          ),
        );

    final secs = [
      AdminMenuSection(
        id: 'a',
        title: 'Secção A',
        subtitle: 'primeira',
        icon: Icons.abc,
        color: Colors.blue,
        items: [
          AdminMenuItem(
            id: 'a_um',
            title: 'Ecrã Um',
            subtitle: 'faz uma coisa',
            icon: Icons.looks_one,
            color: Colors.blue,
            builder: () => const SizedBox(),
            keywords: const ['alfa'],
          ),
        ],
      ),
      AdminMenuSection(
        id: 'arquivado',
        title: 'Arquivado',
        subtitle: 'velho',
        icon: Icons.inventory,
        color: Colors.grey,
        archived: true,
        items: [
          AdminMenuItem(
            id: 'arq_dois',
            title: 'Ecrã Velho',
            subtitle: 'não se usa',
            icon: Icons.looks_two,
            color: Colors.grey,
            builder: () => const SizedBox(),
            archivedReason: 'duplica outro',
          ),
        ],
      ),
    ];

    testWidgets('nasce fechado e abre ao toque', (tester) async {
      await tester.pumpWidget(host(secs));
      expect(find.text('Secção A'), findsOneWidget);
      expect(find.text('Ecrã Um'), findsNothing);
      await tester.tap(find.text('Secção A'));
      await tester.pumpAndSettle();
      expect(find.text('Ecrã Um'), findsOneWidget);
    });

    testWidgets('o arquivado fica escondido até se pedir', (tester) async {
      await tester.pumpWidget(host(secs));
      expect(find.text('Arquivado'), findsNothing);
      expect(find.text('Ecrã Velho'), findsNothing);
      await tester.tap(find.byKey(const ValueKey('btn_arquivado')));
      await tester.pumpAndSettle();
      expect(find.text('Arquivado'), findsOneWidget);
      await tester.tap(find.text('Arquivado'));
      await tester.pumpAndSettle();
      expect(find.textContaining('duplica outro'), findsOneWidget);
    });

    testWidgets('a busca lista o ecrã sem abrir secções', (tester) async {
      await tester.pumpWidget(host(secs));
      await tester.enterText(find.byType(TextField), 'alfa');
      await tester.pumpAndSettle();
      expect(find.text('Ecrã Um'), findsOneWidget);
      await tester.enterText(find.byType(TextField), 'nada disto');
      await tester.pumpAndSettle();
      expect(find.text('Nenhum ecrã com esse nome.'), findsOneWidget);
    });

    testWidgets('os favoritos aparecem em cima como fichas', (tester) async {
      await tester.pumpWidget(host(secs, favs: const ['a_um']));
      expect(find.text('Favoritos'), findsOneWidget);
      expect(find.widgetWithText(ActionChip, 'Ecrã Um'), findsOneWidget);
    });
  });

  group('rotas, toque no aviso e RPC novo (fonte)', () {
    final mainDart = File('lib/main.dart').readAsStringSync();
    final push = File('lib/services/admin_push_service.dart').readAsStringSync();
    // O ecrã carrega e navega; o desenho vive no conteúdo. Lê-se os dois.
    final dash =
        File('lib/screens/admin/admin_dashboard_screen.dart').readAsStringSync() +
            File('lib/screens/admin/admin_dashboard_content.dart')
                .readAsStringSync();
    final digest =
        File('supabase/functions/weekly-closeout-digest/index.ts').readAsStringSync();

    test('as rotas dos avisos estão registadas em main.dart', () {
      expect(mainDart, contains("'/admin/acertos-semana': (ctx) =>"));
      expect(mainDart, contains("'/admin/settlements': (_) => const AdminAcertosSemanaScreen()"));
      expect(mainDart, contains("'/admin/marcacoes-por-confirmar':"));
      expect(mainDart, contains("'/admin/dinheiro-retido-falta':"));
    });

    test('o toque no push do fecho abre a rota com a semana', () {
      // O digest manda route + ref; o serviço lê data.route e tira a semana do ref.
      expect(digest, contains("route: '/admin/acertos-semana'"));
      expect(digest, contains("ref: 'weekly_closeout_' + ws"));
      expect(push, contains("navigator.pushNamed(route, arguments: _argFor(msg))"));
      expect(push, contains("const marca = 'weekly_closeout_'"));
      expect(mainDart, contains('nav.pushNamed(rota, arguments: semana)'));
    });

    test('o dashboard lê o RPC v2 e já não soma o livro inteiro', () {
      expect(dash, contains("rpc('admin_dashboard_metrics_v2')"));
      expect(dash, isNot(contains("rpc('admin_dashboard_metrics')")));
      expect(dash, isNot(contains('drivers_payable')));
      expect(dash, contains('acerto_semana_fechada'));
      expect(dash, contains('admin_show_demo_data'));
    });

    test('o digest nunca escreve para contas de demonstração', () {
      expect(digest, contains("rpc('is_demo_email'"));
      expect(digest, contains('FORA DO FECHO POR SEREM DEMO'));
    });
  });

  group('marcações: a falta deixou de ser automática (fonte)', () {
    final mig = File(
            'supabase/migrations/20260913235830_marcacoes_por_confirmar_sem_falta_automatica.sql')
        .readAsStringSync();
    final agenda =
        File('lib/screens/partner/services/partner_agenda_screen.dart')
            .readAsStringSync();
    final notif = File('lib/services/notification_service.dart').readAsStringSync();

    test('o cron passa a "por confirmar" e nunca a falta', () {
      final cron = mig.substring(
          mig.indexOf('FUNCTION public._appointment_cron_auto_no_show'),
          mig.indexOf('FUNCTION public.partner_complete_appointment'));
      expect(cron, contains("SET status = 'awaiting_confirmation'"));
      expect(cron, isNot(contains("SET status='no_show'")));
      expect(cron, isNot(contains("status = 'no_show'")));
      expect(cron, isNot(contains("'retained'")),
          reason: 'o robô nunca pode reter dinheiro sozinho');
    });

    test('a falta só é definitiva pelo parceiro ou pelo admin, com Telegram', () {
      expect(mig, contains('FUNCTION public.partner_mark_no_show'));
      expect(mig, contains('FUNCTION public.admin_appointment_mark_no_show'));
      expect(mig, contains('FUNCTION public.admin_appointment_revert_no_show'));
      expect(RegExp(r'_telegram_admin\(').allMatches(mig).length,
          greaterThanOrEqualTo(3));
    });

    test('o parceiro vê os dois botões também na marcação por confirmar', () {
      expect(agenda, contains('AppointmentStatus.awaitingConfirmation'));
      expect(agenda, contains("'Foi feita? Diz-nos'"));
    });

    test('os avisos novos ao parceiro abrem a agenda', () {
      expect(notif, contains("'appointment_confirm_needed'"));
      expect(notif, contains("'appointment_no_show_reverted'"));
    });
  });
}
