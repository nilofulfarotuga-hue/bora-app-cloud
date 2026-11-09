import 'dart:io';

import 'package:bora_app/models/restaurant_model.dart';
import 'package:bora_app/screens/prestador/como_o_bora_decide_screen.dart';
import 'package:bora_app/services/app_update_service.dart';
import 'package:bora_app/services/tvde_visibilidade.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// M10 b2-textos (09/11/2026) — missão m10-noite-toda-sem-travas-2026-11-08.
///
/// Um grupo por item da missão. O repo testa muito pela fonte: aqui lê-se o
/// ficheiro .dart e confirma-se o que o ecrã faz, e onde dá, desenha-se o
/// widget.
String _ler(String caminho) => File(caminho).readAsStringSync();

/// Pedaço da fonte entre [inicio] (inclusive) e [fim] (exclusive).
String _entre(String src, String inicio, String fim) {
  final a = src.indexOf(inicio);
  expect(a, isNonNegative, reason: 'não encontrei "$inicio"');
  final b = src.indexOf(fim, a + inicio.length);
  expect(b, greaterThan(a), reason: 'não encontrei "$fim" depois de "$inicio"');
  return src.substring(a, b);
}

void main() {
  // ── 2.12 — reembolso ao cancelar no acompanhamento do pedido ──────────────
  group('M10 2.12 — cancelar no acompanhamento: o cliente escolhe o reembolso',
      () {
    // Lido dentro de cada teste: o expect() do _entre só vale num teste.
    late String cancelar;
    setUp(() {
      cancelar = _entre(_ler('lib/screens/order_tracking_screen.dart'),
          'Future<void> _confirmClientCancel', 'class _CodeDigit');
    });

    test('nada vem marcado à partida (antes: cartão por defeito)', () {
      expect(cancelar, isNot(contains("String refundTarget = 'card';")));
      expect(cancelar, contains('String? refundTarget;'));
    });

    test('saiu o texto antigo "80% saldo + 20% pontos" e os rádios pequenos',
        () {
      // O texto no ecrã (literal com .tr); o comentário que explica a mudança
      // pode citá-lo.
      expect(cancelar,
          isNot(contains("'Na carteira, imediato (80% saldo + 20% pontos)'")));
      expect(cancelar, isNot(contains("'De volta ao cartão (~5 dias úteis)'")));
      expect(cancelar, isNot(contains('RadioListTile')));
    });

    test('duas opções grandes, com os mesmos textos do RefundChoiceDialog', () {
      expect(cancelar, contains("Key('opcao_reembolso_wallet')"));
      expect(cancelar, contains("Key('opcao_reembolso_meio')"));
      expect(cancelar, contains("'Carteira Bora'.tr"));
      expect(cancelar, contains("'Devolver para a minha conta'.tr"));
      // MB Way na hora / cartão 5 a 10 dias úteis, conforme o meio do pedido.
      expect(
          cancelar,
          matches(RegExp(
              r'prazoDevolucaoAoMeio\(\s*widget\.order\.paymentMethod\.name\)')));
      // Tokens voltam como tokens.
      expect(cancelar, contains('voltam como tokens'));
    });

    test('os valores enviados ao servidor são os mesmos: wallet | card', () {
      expect(cancelar, contains("refundTarget = 'wallet'"));
      expect(cancelar, contains("refundTarget = 'card'"));
      expect(cancelar, contains("refundTarget: refundTarget ?? 'card'"));
      // A API do OrderStore não mudou.
      expect(_ler('lib/stores/order_store.dart'),
          contains("'refund_target': refundTarget"));
    });

    test('sem escolha feita, "Confirmar cancelamento" fica desligado', () {
      expect(cancelar, contains('(canChooseRefund && refundTarget == null)'));
      // Fechar o diálogo (ou "Não") nunca cancela.
      expect(cancelar,
          contains('if (confirmed != true || !context.mounted) return;'));
    });
  });

  // ── 2.11 — Bora Motorista fechado: sem "motorista"/TVDE nos ecrãs ─────────
  group('M10 2.11 — Bora Motorista fechado esconde motorista/TVDE', () {
    tearDown(() => TvdeVisibilidade.definirParaTeste(false));

    test('"Como o Bora decide": um só parágrafo é dos motoristas TVDE', () {
      final soTvde = [
        for (final (_, ps) in ComoOBoraDecide.seccoes)
          for (final p in ps)
            if (ComoOBoraDecide.soBoraMotorista(p)) p,
      ];
      expect(soTvde, hasLength(1));
      expect(soTvde.single, contains('documento caducado'));
    });

    Future<void> desenhar(WidgetTester tester) async {
      // Ecrã alto: o ListView desenha o texto todo de uma vez.
      tester.view.physicalSize = const Size(1200, 40000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
          const MaterialApp(home: ComoOBoraDecideScreen()));
      await tester.pump();
    }

    testWidgets('"Como o Bora decide" fechado: o parágrafo TVDE não aparece',
        (tester) async {
      TvdeVisibilidade.definirParaTeste(false);
      await desenhar(tester);
      // O resto da secção 3 está lá (prova de que o ecrã foi desenhado).
      expect(find.textContaining('Não deixar ficar online sem aprovação'),
          findsOneWidget);
      expect(find.textContaining('motoristas TVDE'), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('"Como o Bora decide" aberto: o parágrafo TVDE volta',
        (tester) async {
      TvdeVisibilidade.definirParaTeste(true);
      await desenhar(tester);
      expect(find.textContaining('motoristas TVDE'), findsOneWidget);
    });

    test('candidatura a estafeta: título e texto sem "motorista"/"viagens"', () {
      final s = _ler('lib/screens/driver/driver_role_apply_screen.dart');
      expect(s, isNot(contains("const BoraScreenAppBar(title: 'Ser estafeta / motorista')")));
      expect(
          s,
          matches(RegExp(r"TvdeVisibilidade\.aberto\s*\?\s*'Ser estafeta / motorista'"
              r"\s*:\s*'Ser estafeta'")));
      expect(s, contains("'Faz entregas quando quiseres — com a mesma conta. '"));
    });

    test('extrato do prestador: "corridas TVDE" só no painel ou com o TVDE aberto',
        () {
      final s = _ler('lib/widgets/extrato_prestador_section.dart');
      final i = s.indexOf('widget.admin || TvdeVisibilidade.aberto');
      expect(i, isNonNegative);
      final tvde = s.indexOf('as corridas TVDE entram', i);
      expect(tvde, greaterThan(i));
      expect(tvde - i, lessThan(200),
          reason: 'o texto das corridas TVDE tem de estar debaixo do controlo');
      expect(s, contains(": 'Os acertos fecham à segunda-feira.',"));
    });

    test('casa da limpeza: o convite fala só de Entregas com o TVDE fechado',
        () {
      final s = _ler('lib/screens/cleaner/cleaner_home_screen.dart');
      expect(s, contains(": 'Trabalha também em Entregas?',"));
      expect(s, contains(": 'As minhas Entregas',"));
      expect(s, contains('inviteTitle: TvdeVisibilidade.aberto'));
      expect(s, contains('activeTitle: TvdeVisibilidade.aberto'));
    });

    test('"certificado TVDE do IMT" (roles_service) só se vê pelo filtro', () {
      // A descrição vive em atividadesDisponiveis(); o único ecrã que a usa é
      // o "Trabalhar no Bora", que já tira a actividade 'driver' com o
      // Bora Motorista fechado (04/11).
      final usam = Directory('lib')
          .listSync(recursive: true)
          .whereType<File>()
          .where((f) => f.path.endsWith('.dart'))
          .where((f) => f.readAsStringSync().contains('atividadesDisponiveis('))
          .map((f) => f.path.replaceAll('\\', '/'))
          .toSet();
      expect(usam, {
        'lib/services/roles_service.dart',
        'lib/screens/trabalhar_no_bora_screen.dart',
      });
      expect(_ler('lib/screens/trabalhar_no_bora_screen.dart'),
          contains("if (a.papel != 'driver' || TvdeVisibilidade.aberto) a,"));
    });
  });

  // ── 2.14 ii — aviso de atualização opcional no máximo 1×/semana ──────────
  group('M10 2.14 ii — aviso opcional de atualização 1×/semana', () {
    final base = DateTime(2026, 11, 9, 10);

    test('regra pura: nunca mostrado → mostra; < 7 dias → não; 7 dias → sim',
        () {
      bool pode(DateTime? ultimo, DateTime agora) =>
          AppUpdateService.avisoOpcionalPodeAparecer(
              ultimo: ultimo, agora: agora);
      expect(pode(null, base), isTrue);
      expect(pode(base, base), isFalse);
      expect(pode(base, base.add(const Duration(days: 6, hours: 23))), isFalse);
      expect(pode(base, base.add(const Duration(days: 7))), isTrue);
      // Relógio que andou para trás: um dia não destrava, mais de 7 dias sim.
      expect(pode(base, base.subtract(const Duration(days: 1))), isFalse);
      expect(pode(base, base.subtract(const Duration(days: 8))), isTrue);
    });

    test('guarda a data no telemóvel e só volta 7 dias depois', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      expect(await AppUpdateService.reservarAvisoOpcional(agora: base), isTrue);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getInt(AppUpdateService.chaveUltimoAvisoOpcional),
          base.millisecondsSinceEpoch);
      // Arranques seguintes na mesma semana: nada.
      expect(
          await AppUpdateService.reservarAvisoOpcional(
              agora: base.add(const Duration(hours: 1))),
          isFalse);
      expect(
          await AppUpdateService.reservarAvisoOpcional(
              agora: base.add(const Duration(days: 6))),
          isFalse);
      // Uma semana depois: volta (e a data avança).
      final semana = base.add(const Duration(days: 7));
      expect(await AppUpdateService.reservarAvisoOpcional(agora: semana),
          isTrue);
      expect(prefs.getInt(AppUpdateService.chaveUltimoAvisoOpcional),
          semana.millisecondsSinceEpoch);
    });

    test('a atualização forçada não passa pelo limite semanal', () {
      final s = _ler('lib/services/app_update_service.dart');
      final check =
          _entre(s, 'static Future<void> checkAndPrompt', 'class AppUpdateGate');
      final forcada = check.indexOf("const Text('Atualização necessária')");
      final limite = check.indexOf('if (!await reservarAvisoOpcional()) return;');
      expect(forcada, isNonNegative);
      expect(limite, isNonNegative);
      expect(forcada, lessThan(limite),
          reason: 'o bloqueio da versão mínima vem antes e não é limitado');
      // Continua a ler as chaves da versão mínima (Android e _ios).
      expect(check, contains(r"'app_min_supported_version_code$sufixo'"));
      expect(s, contains("isIos ? '_ios' : ''"));
      // Só um sítio chama o limite: o aviso opcional.
      expect('reservarAvisoOpcional()'.allMatches(check), hasLength(1));
    });
  });

  // ── 2.13 — selo "Frescura garantida" fora da Mercadona de beleza ──────────
  group('M10 2.13 — selo "Frescura garantida"', () {
    RestaurantModel loja(String id, String nome) => RestaurantModel(
          id: id,
          name: nome,
          phone: '',
          address: '',
          email: '',
          photoUrl: '',
          cuisineType: '',
          isPartner: false,
          category: BusinessCategory.supermarket,
        );

    test('linha real (SQL 09/11/2026): Mercadona · Beleza e Higiene não mostra',
        () {
      expect(
          loja('mercadona-guarda', 'Mercadona · Beleza e Higiene')
              .podeAnunciarFrescura,
          isFalse);
    });

    test('critério pelo nome, não pelo id: a Mercadona reaberta com frescos '
        'volta a mostrar', () {
      // Página mercadona-reabrir-loja: se a loja voltar a ser supermercado
      // completo, muda o nome e o selo volta sozinho. Uma lista de ids
      // escondia-o para sempre.
      expect(loja('mercadona-guarda', 'Mercadona').podeAnunciarFrescura,
          isTrue);
    });

    test('o ecrã da loja só desenha o selo debaixo da regra do modelo', () {
      final s = _ler('lib/widgets/market/market_store_tab.dart');
      expect("'Frescura garantida'".allMatches(s), hasLength(1));
      final guarda = s.indexOf('if (restaurant.podeAnunciarFrescura)');
      final selo = s.indexOf("'Frescura garantida'");
      expect(guarda, isNonNegative);
      expect(selo, greaterThan(guarda));
      expect(selo - guarda, lessThan(600));
    });
  });

  // ── 2.14 iii — preços do estafeta e do parceiro em "2,50 €" ──────────────
  group('M10 2.14 iii — preços no formato de Portugal (estafeta e parceiro)',
      () {
    const ficheiros = [
      'lib/screens/driver_home_screen.dart',
      'lib/screens/ganhos_screen.dart',
      'lib/screens/partner_call_driver_screen.dart',
      'lib/screens/partner_earnings_screen.dart',
      'lib/screens/partner/reservations/partner_reservations_screen.dart',
      'lib/screens/partner/services/partner_agenda_screen.dart',
      'lib/screens/partner/services/partner_appointments_finance_screen.dart',
      'lib/widgets/driver_order_overlay.dart',
      'lib/widgets/payments/collect_badge.dart',
    ];
    // "€9.65" e "9.65 €": o número com ponto, sem o replaceAll da vírgula.
    final euroAntes = RegExp(r'€\$\{[^}]*toStringAsFixed\(2\)\}');
    final euroDepois = RegExp(r'toStringAsFixed\(2\)\}\s*€');

    for (final f in ficheiros) {
      test('$f: nenhum preço com ponto e usa o eur()', () {
        final s = _ler(f);
        expect(euroAntes.allMatches(s).map((m) => m.group(0)).toList(), isEmpty);
        expect(euroDepois.allMatches(s).map((m) => m.group(0)).toList(),
            isEmpty);
        expect(s, contains('utils/euros.dart'));
      });
    }

    test('driver_home: dívida, sacos e balcão com o mesmo helper', () {
      final s = _ler('lib/screens/driver_home_screen.dart');
      expect(s, contains("'↳ inclui \${eurCents(order.debtCollectedCents)} de dívida anterior'"));
      expect(s, contains(r"× ${eur(0.10)} = ${eur(bagFee)}"));
      expect(s, isNot(contains('€0.10')));
      expect(s, contains(r"'Pagar ao balcão: ${eur(order.items"));
    });
  });
}
