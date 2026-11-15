import 'dart:io';

import 'package:bora_app/screens/admin/admin_bora_motorista_fechado_screen.dart';
import 'package:bora_app/screens/admin/admin_dashboard_screen.dart';
import 'package:bora_app/screens/admin/admin_marcacoes_confirmacao_screen.dart';
import 'package:bora_app/screens/admin/admin_menu_accordion.dart';
import 'package:bora_app/screens/admin/admin_menu_registry.dart';
import 'package:bora_app/screens/admin/admin_notifications_inbox_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// [app-15-11 · auditoria S5 do painel] O que estes testes trancam (sem rede):
///
///  1. O sininho conta só o que pede ação (por ler, não arquivado, nível alto
///     ou crítico, últimos 7 dias) e mostra o número exato até 99, depois
///     "99+". Antes mostrava sempre "9+" ("100 não lidas") — eram 1789.
///  2. A busca do menu não liga a acentos nem a maiúsculas, diz a secção de
///     cada resultado e põe o arquivo no fim; cada secção diz "N telas"; o
///     badge 'novo' aparece; o arquivo do Bora Motorista desceu para o fim;
///     farmácias foram para Parceiros e a Stripe para "Mais dinheiro".
///  3. A caixa de avisos tem nome em português para os 48 tipos da base e
///     para o nível, e o aviso de chave roubada não abre outro painel.
///  4. As 3 rotas que os avisos usavam e não existiam.
///  5. Arquivo do Bora Motorista: coluna `at`, motoristas por `user_id`,
///     botões travados com a frase enquanto está fechado.
///  6. Sessão expirada: frase e botão "Sair".
void main() {
  String ler(String p) => File(p).readAsStringSync();

  group('sininho', () {
    test('número exato até 99, depois "99+"', () {
      expect(AdminSino.rotulo(1), '1');
      expect(AdminSino.rotulo(9), '9');
      expect(AdminSino.rotulo(10), '10');
      expect(AdminSino.rotulo(99), '99');
      expect(AdminSino.rotulo(100), '99+');
      expect(AdminSino.rotulo(152), '99+');
    });

    test('a dica diz o número exato e de onde vem', () {
      expect(AdminSino.dica(152),
          '152 avisos importantes por ler (últimos 7 dias)');
      expect(AdminSino.dica(2), '2 avisos importantes por ler (últimos 7 dias)');
      expect(AdminSino.dica(1), '1 aviso importante por ler (últimos 7 dias)');
      expect(AdminSino.dica(0),
          'Nenhum aviso importante por ler (últimos 7 dias)');
    });

    test('só conta alto e crítico dos últimos 7 dias', () {
      expect(AdminSino.severidades, ['high', 'critical']);
      expect(AdminSino.janela, const Duration(days: 7));
    });

    test('conta no servidor, ao número exato, sem baixar linhas (fonte)', () {
      final dash = ler('lib/screens/admin/admin_dashboard_screen.dart');
      expect(dash, contains('.count(CountOption.exact)'));
      expect(dash, contains(".inFilter('severity', AdminSino.severidades)"));
      expect(dash, contains(".gte('created_at', desde.toIso8601String())"));
      expect(dash, isNot(contains('.limit(100)')));
      expect(dash, isNot(contains("'9+'")));
    });
  });

  group('busca do menu sem acentos', () {
    final todos = adminMenuAllItems();
    List<String> ids(String q) =>
        todos.where((i) => i.matches(q)).map((i) => i.id).toList();

    test('as quatro palavras da auditoria acham as suas telas', () {
      expect(ids('farmacias'), contains('farmacias'));
      expect(ids('pendencias'), contains('operacao_pendencias'));
      expect(ids('edicoes'), contains('operacao_edicoes_pedidos'));
      expect(ids('diferencas'), contains('operacao_favor_diferencas'));
    });

    test('acentos e maiúsculas na busca também', () {
      expect(ids('FARMÁCIAS'), contains('farmacias'));
      expect(ids('Edições'), contains('operacao_edicoes_pedidos'));
      expect(ids('DIFERENÇAS'), contains('operacao_favor_diferencas'));
    });

    test('dos dois lados: título, descrição e palavra-chave', () {
      final item = AdminMenuItem(
        id: 'x',
        title: 'Ação Única',
        subtitle: 'Faz a gestão das inscrições',
        icon: Icons.abc,
        color: Colors.blue,
        builder: () => const SizedBox(),
        keywords: const ['Coração'],
      );
      for (final q in ['acao', 'ACAO', 'única', 'unica', 'gestao', 'inscricoes', 'coracao']) {
        expect(item.matches(q), isTrue, reason: q);
      }
      expect(item.matches('xyzzy'), isFalse);
      expect(item.matches('   '), isTrue);
    });
  });

  group('resultados da busca: secção e arquivo no fim', () {
    final sections = adminMenuSections();

    test('cada resultado diz a secção; o sub-menu também', () {
      final r = adminMenuBuscar(sections, 'stripe');
      final stripe = r.firstWhere((x) => x.item.id == 'operacao_stripe_contas');
      expect(stripe.onde, 'Dinheiro e acertos › Mais dinheiro');
      final farm = adminMenuBuscar(sections, 'farmacias')
          .firstWhere((x) => x.item.id == 'farmacias');
      expect(farm.onde, 'Parceiros');
    });

    test('os do "Arquivado" vêm depois dos outros', () {
      final r = adminMenuBuscar(sections, 'pagamentos');
      final arquivados = [
        for (var i = 0; i < r.length; i++)
          if (r[i].secao.archived) i
      ];
      final vivos = [
        for (var i = 0; i < r.length; i++)
          if (!r[i].secao.archived) i
      ];
      expect(arquivados, isNotEmpty);
      expect(vivos, isNotEmpty);
      expect(vivos.last, lessThan(arquivados.first));
      expect(r[arquivados.first].onde, 'Arquivado');
    });

    test('legenda "N telas" e a conta com os sub-menus', () {
      expect(legendaTelas(22), '22 telas');
      expect(legendaTelas(1), '1 tela');
      final din = sections.firstWhere((s) => s.id == 'dinheiro');
      final mais = din.items.firstWhere((i) => i.id == 'dinheiro_mais');
      expect(din.telas, din.items.length - 1 + mais.filhos.length);
    });
  });

  group('arrumação do menu', () {
    final sections = adminMenuSections();
    List<String> idsDe(String sec) =>
        sections.firstWhere((s) => s.id == sec).items.map((i) => i.id).toList();

    test('o arquivo do Bora Motorista fica no fim, antes do "Arquivado"', () {
      final ids = sections.map((s) => s.id).toList();
      expect(ids.last, 'arquivado');
      expect(ids[ids.length - 2], 'tvde');
    });

    test('farmácias em Parceiros, fora da Operação do dia, com os mesmos ids', () {
      for (final id in ['farmacias', 'farmacias_extrato', 'pedidos_receita']) {
        expect(idsDe('parceiros'), contains(id));
        expect(idsDe('operacao'), isNot(contains(id)));
      }
    });

    test('"Stripe — duas contas" em "Mais dinheiro", com o mesmo id', () {
      expect(idsDe('operacao'), isNot(contains('operacao_stripe_contas')));
      final din = sections.firstWhere((s) => s.id == 'dinheiro');
      expect(din.items.length, lessThanOrEqualTo(5));
      final mais = din.items.firstWhere((i) => i.id == 'dinheiro_mais');
      expect(mais.filhos.map((i) => i.id), contains('operacao_stripe_contas'));
    });

    test('"Contas claras" continua com o badge novo', () {
      final it = adminMenuAllItems().firstWhere((i) => i.id == 'dinheiro_contas_claras');
      expect(it.badge, 'novo');
    });
  });

  group('acordeão', () {
    AdminMenuItem item(String id, String titulo, {List<String> kw = const [], String? badge, String? motivo}) =>
        AdminMenuItem(
          id: id,
          title: titulo,
          subtitle: 'faz uma coisa útil',
          icon: Icons.abc,
          color: Colors.blue,
          builder: () => const SizedBox(),
          keywords: kw,
          badge: badge,
          archivedReason: motivo,
        );

    final secs = [
      AdminMenuSection(
        id: 'a',
        title: 'Secção A',
        subtitle: 'primeira',
        icon: Icons.abc,
        color: Colors.blue,
        items: [
          item('a_um', 'Ecrã Um', kw: const ['alfa'], badge: 'novo'),
          item('a_dois', 'Ecrã Dois'),
        ],
      ),
      AdminMenuSection(
        id: 'b',
        title: 'Secção B',
        subtitle: 'segunda',
        icon: Icons.abc,
        color: Colors.blue,
        items: [item('b_acao', 'Ação Beta', kw: const ['alfa'])],
      ),
      AdminMenuSection(
        id: 'arquivado',
        title: 'Arquivado',
        subtitle: 'velho',
        icon: Icons.inventory,
        color: Colors.grey,
        archived: true,
        items: [item('arq_alfa', 'Velho Alfa', motivo: 'duplica outro')],
      ),
    ];
    // O arquivo vem PRIMEIRO na lista de secções: a ordem tem de vir da
    // busca, não da posição.
    final secsArquivoPrimeiro = [secs[2], secs[0], secs[1]];

    Widget host(List<AdminMenuSection> s) => MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: AdminMenuAccordion(
                sections: s,
                favoritos: const [],
                onToggleFavorito: (_) {},
                onOpen: (_, __) {},
              ),
            ),
          ),
        );

    testWidgets('cada secção diz "N telas"', (t) async {
      await t.pumpWidget(host(secs));
      expect(find.text('2 telas'), findsOneWidget);
      expect(find.text('1 tela'), findsOneWidget);
    });

    testWidgets('o badge "novo" aparece como etiqueta', (t) async {
      await t.pumpWidget(host(secs));
      await t.tap(find.text('Secção A'));
      await t.pumpAndSettle();
      expect(find.byKey(const ValueKey('novo_a_um')), findsOneWidget);
      expect(find.text('novo'), findsOneWidget);
    });

    testWidgets('busca: secção em cada resultado e arquivo no fim', (t) async {
      await t.pumpWidget(host(secsArquivoPrimeiro));
      await t.enterText(find.byType(TextField), 'ALFA');
      await t.pumpAndSettle();
      final onde = find.byKey(const ValueKey('onde_a_um'));
      expect(onde, findsOneWidget);
      expect((t.widget<Text>(onde)).data, 'Secção A');
      expect((t.widget<Text>(find.byKey(const ValueKey('onde_arq_alfa')))).data,
          'Arquivado');
      final yBeta = t.getTopLeft(find.byKey(const ValueKey('item_b_acao'))).dy;
      final yVelho = t.getTopLeft(find.byKey(const ValueKey('item_arq_alfa'))).dy;
      final yUm = t.getTopLeft(find.byKey(const ValueKey('item_a_um'))).dy;
      expect(yVelho, greaterThan(yBeta));
      expect(yVelho, greaterThan(yUm));
    });

    testWidgets('busca sem acento acha título com acento', (t) async {
      await t.pumpWidget(host(secs));
      await t.enterText(find.byType(TextField), 'acao');
      await t.pumpAndSettle();
      expect(find.text('Ação Beta'), findsOneWidget);
    });
  });

  group('caixa de avisos', () {
    // Os 48 tipos que existiam em admin_notifications a 15/11/2026
    // (SELECT DISTINCT event_type).
    const tiposDaBase = [
      'robot_b_auto_fix', 'new_signup', 'tvde_ride_new', 'cortex_red_proposal',
      'new_order', 'tvde_reservation_new', 'robot_b_suggestion',
      'security_key_abuse', 'support_user_message', 'catalog_price_gap',
      'phone_order_call', 'funcao_sem_resposta', 'reimbursement_pending',
      'cleaning_booking_new', 'driver_application_pending', 'order_orphan',
      'robot_b_digest', 'weekly_closeout', 'tvde_payment_failed',
      'support_ticket_new', 'ledger_orphan', 'new_appointment',
      'provider_atividade_enviada', 'tvde_driver_application_pending',
      'cleaner_application_pending', 'pagamento_sem_etiqueta',
      'tvde_reservation_no_driver', 'dispatch_ttl_auto_cancel',
      'pedido_no_vermelho', 'cleaning_booking_cancelled',
      'order_driver_direct_update', 'teste_push_admin',
      'appointment_awaiting_confirmation', 'tvde_reembolso_falhou',
      'tvde_reservation_redispatch', 'catalogo_extra_mais_caro',
      'order_refund_needed', 'order_refund_auto', 'partner_application_pending',
      'pedido_reativado_pos_pagamento', 'order_cancel_mid_delivery',
      'cleaning_unpaid', 'service_provider_application_pending',
      'carwash_booking_new', 'system_report', 'test_alertas', 'teste',
      'teste_aviso_pedido',
    ];

    test('os 48 tipos da base têm nome em português', () {
      expect(tiposDaBase.toSet().length, 48);
      for (final t in tiposDaBase) {
        expect(AdminNotificationsInboxScreen.rotulosPorTipo, contains(t),
            reason: '$t sem nome em português');
        final r = AdminNotificationsInboxScreen.rotuloDoTipo(t);
        expect(r, isNot(contains('_')), reason: t);
        expect(r.trim(), isNotEmpty);
      }
      expect(AdminNotificationsInboxScreen.rotuloDoTipo('robot_b_auto_fix'),
          'Correção automática do robô');
      expect(AdminNotificationsInboxScreen.rotuloDoTipo('pedido_no_vermelho'),
          'Pedido no vermelho');
      // Tipo novo, ainda sem nome: não aparece cru.
      expect(AdminNotificationsInboxScreen.rotuloDoTipo('tipo_novo_x'),
          'Aviso: tipo novo x');
    });

    test('nível em português', () {
      expect(AdminNotificationsInboxScreen.nivelPtBr('critical'), 'Crítico');
      expect(AdminNotificationsInboxScreen.nivelPtBr('high'), 'Alto');
      expect(AdminNotificationsInboxScreen.nivelPtBr('medium'), 'Médio');
      expect(AdminNotificationsInboxScreen.nivelPtBr('low'), 'Baixo');
    });

    test('chave roubada vai para "Saúde das chaves"; "/admin" fica na caixa', () {
      expect(
          AdminNotificationsInboxScreen.rotaDoAviso('security_key_abuse', '/admin'),
          '/admin/system-health');
      expect(AdminNotificationsInboxScreen.rotaDoAviso('system_report', '/admin'),
          isNull);
      expect(
          AdminNotificationsInboxScreen.rotaDoAviso('catalogo_extra_mais_caro', null),
          isNull);
      expect(AdminNotificationsInboxScreen.rotaDoAviso('new_order', '/admin/orders'),
          '/admin/orders');
      expect(
          AdminNotificationsInboxScreen.rotaDoAviso(
              'support_ticket_new', '/admin/support'),
          '/admin/support');
    });

    test('"Arquivar" é um botão à vista e o nível já não vai em inglês (fonte)', () {
      final inbox = ler('lib/screens/admin/admin_notifications_inbox_screen.dart');
      expect(inbox, contains("label: const Text('Arquivar')"));
      expect(inbox, contains('onDismissed: (_) => _archive(r)'));
      expect(inbox, isNot(contains('severity.toUpperCase()')));
      expect(inbox, contains('AdminNotificationsInboxScreen.rotaDoAviso('));
    });
  });

  group('rotas dos avisos (fonte)', () {
    final main = ler('lib/main.dart');

    test('as 3 rotas que abriam "Página não encontrada"', () {
      expect(main, contains("'/admin/support': (_) => const AdminSupportTicketsScreen()"));
      expect(main,
          contains("'/admin/cancellations': (_) => const AdminCancellationsScreen()"));
      expect(main, contains("'/admin/tvde/corridas': (_) => const AdminTvdeRidesScreen()"));
      expect(main, contains("'/admin/system-health': (_) => const AdminSaudeChavesScreen()"));
    });
  });

  group('arquivo do Bora Motorista', () {
    test('histórico da reserva lê a coluna `at` (fonte)', () {
      final r = ler('lib/screens/admin/admin_tvde_reservas_screen.dart');
      expect(r, contains(".select('at, status, actor, meta')"));
      expect(r, contains(".order('at', ascending: false)"));
      expect(r, contains("e['at']"));
      expect(r, isNot(contains("'created_at, status, actor, meta'")));
    });

    test('dívidas: nomes por user_id (fonte)', () {
      final d = ler('lib/screens/admin/admin_tvde_driver_debts_screen.dart');
      expect(d, contains(".select('user_id, name, phone')"));
      expect(d, contains(".inFilter('user_id', ids)"));
      expect(d, contains("byId[d['user_id'].toString()]"));
      expect(d, isNot(contains(".inFilter('id', ids)")));
    });

    test('interruptor: frase simples e contas exatas (fonte)', () {
      final f = ler('lib/screens/admin/admin_bora_motorista_fechado_screen.dart');
      expect(f, contains('Liga ou desliga o Bora Motorista nas apps. Fica registrado quem mudou.'));
      expect(f, isNot(contains('Configuração tvde_app_visivel')));
      expect(f, contains("_sb.from('tvde_rides').count(CountOption.exact)"));
      expect(f, isNot(contains('limit(100000)')));
    });

    test('a frase dos botões travados e a leitura do interruptor', () {
      expect(kBotaoBoraMotoristaFechado,
          'Bora Motorista fechado: este botão volta quando reabrir.');
      expect(boraMotoristaAbertoDoValor(true), isTrue);
      expect(boraMotoristaAbertoDoValor('true'), isTrue);
      expect(boraMotoristaAbertoDoValor(' TRUE '), isTrue);
      expect(boraMotoristaAbertoDoValor(false), isFalse);
      expect(boraMotoristaAbertoDoValor('false'), isFalse);
      expect(boraMotoristaAbertoDoValor(null), isFalse);
    });

    test('os ecrãs com botões de ação leem o interruptor e mostram a frase (fonte)', () {
      for (final p in [
        'lib/screens/admin/admin_tvde_rides_screen.dart',
        'lib/screens/admin/admin_tvde_reservas_screen.dart',
        'lib/screens/admin/admin_tvde_balcao_screen.dart',
        'lib/screens/admin/admin_tvde_access_requests_screen.dart',
        'lib/screens/admin/admin_tvde_dest_change_dialog.dart',
      ]) {
        final s = ler(p);
        expect(s, contains('lerBoraMotoristaAberto()'), reason: p);
        expect(s, contains('AvisoBotaoBoraMotoristaFechado'), reason: p);
        expect(s, isNot(contains('TvdeVisibilidade.aberto')), reason: p);
      }
      final reservas = ler('lib/screens/admin/admin_tvde_reservas_screen.dart');
      for (final acao in ['_trocarMotorista(r)', '_forcarBusca(r)', '_mudarHora(r)', '_mudarDestino(r)']) {
        expect(reservas, contains('onPressed: _travado ? null : () => $acao'), reason: acao);
      }
      expect(
          RegExp(r"BotaoFlutuanteTravado\(\s*rotulo: 'Nova reserva'")
              .hasMatch(reservas),
          isTrue);
      expect(
          RegExp(r"BotaoFlutuanteTravado\(\s*rotulo: 'Nova corrida'")
              .hasMatch(ler('lib/screens/admin/admin_tvde_balcao_screen.dart')),
          isTrue);
    });

    testWidgets('a frase aparece por baixo e o botão flutuante fica travado', (t) async {
      await t.pumpWidget(const MaterialApp(
        home: Scaffold(
          body: AvisoBotaoBoraMotoristaFechado(),
          floatingActionButton:
              BotaoFlutuanteTravado(rotulo: 'Nova corrida', icone: Icons.add),
        ),
      ));
      expect(find.text(kBotaoBoraMotoristaFechado), findsNWidgets(2));
      final fab = t.widget<FloatingActionButton>(find.byType(FloatingActionButton));
      expect(fab.onPressed, isNull);
      expect(find.text('Nova corrida'), findsOneWidget);
    });
  });

  group('marcações por confirmar', () {
    test('estado do pagamento em português', () {
      expect(AdminMarcacoesConfirmacaoScreen.pagamentoPtBr('paid'), 'pago');
      expect(AdminMarcacoesConfirmacaoScreen.pagamentoPtBr('pending'), 'por pagar');
      expect(AdminMarcacoesConfirmacaoScreen.pagamentoPtBr('waived'), 'dispensado');
      expect(AdminMarcacoesConfirmacaoScreen.pagamentoPtBr('kept_test'), 'teste');
      expect(AdminMarcacoesConfirmacaoScreen.pagamentoPtBr(null), '—');
    });
  });

  group('sessão expirada', () {
    test('reconhece 401 / JWT expired e não confunde outros erros', () {
      expect(
          AdminSessaoExpirada.detectar(
              const PostgrestException(message: 'JWT expired', code: 'PGRST303')),
          isTrue);
      expect(
          AdminSessaoExpirada.detectar(
              const PostgrestException(message: 'x', code: 'PGRST301')),
          isTrue);
      expect(AdminSessaoExpirada.detectar(const PostgrestException(message: 'x', code: '401')),
          isTrue);
      expect(AdminSessaoExpirada.detectar(const AuthException('x', statusCode: '401')),
          isTrue);
      expect(AdminSessaoExpirada.detectar(Exception('JWT expired')), isTrue);
      expect(
          AdminSessaoExpirada.detectar(
              const PostgrestException(message: 'permission denied', code: '42501')),
          isFalse);
      expect(AdminSessaoExpirada.detectar(StateError('rede')), isFalse);
      expect(AdminSessaoExpirada.detectar(null), isFalse);
    });

    testWidgets('mostra a frase e o botão Sair', (t) async {
      await t.pumpWidget(
          const MaterialApp(home: Scaffold(body: AdminSessaoExpirada())));
      expect(find.text('Sua sessão expirou. Saia e entre de novo.'), findsOneWidget);
      expect(find.byKey(const Key('admin_sessao_expirada_sair')), findsOneWidget);
      expect(find.text('Sair'), findsOneWidget);
    });

    test('o painel usa o aviso quando as métricas falham por sessão (fonte)', () {
      final dash = ler('lib/screens/admin/admin_dashboard_screen.dart');
      expect(dash, contains('if (AdminSessaoExpirada.detectar(snapshot.error))'));
      expect(dash, contains("key: const Key('admin_acesso_negado_sair')"));
      expect(dash, contains('onPressed: () => AdminAcessoNegado.sair(context)'));
    });
  });
}
