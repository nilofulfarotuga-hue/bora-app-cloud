// Missão fechar-tudo-2026-11-10, bloco F — barras de baixo do ESTAFETA e do
// PARCEIRO (pedido do Danilo: "igual ao padrão Uber/Glovo; nada de funções
// escondidas; tudo o que já existe continua a existir").
//
// Prova:
//  1. os 4 separadores e os rótulos certos (PT-PT) em cada papel, pela ordem;
//  2. o separador ativo a verde Bora #16A34A, os outros a cinzento, sem laranja;
//  3. cada entrada que vivia num botão só com ícone (estafeta: Perfil,
//     Trabalhar noutra coisa, Mudar modo; parceiro: Mudar modo, A minha
//     conta) e os botões soltos da página única do parceiro aparecem agora
//     com texto em "Conta" / "Loja" / "Ganhos", e cada uma chama o seu destino;
//  4. ecrã pequeno (360 x 640) com letra a 2× sem rebentar a barra;
//  5. pela fonte: os botões só com ícone saíram mesmo, e a app abre a casa
//     nova do estafeta (o Início continua a ser o DriverHomeScreen de sempre).
import 'dart:io';

import 'package:bora_app/config/app_colors.dart';
import 'package:bora_app/screens/driver_main_screen.dart';
import 'package:bora_app/screens/partner_dashboard_screen.dart';
import 'package:bora_app/widgets/bora/bora_barra_separadores.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

String _ler(String caminho) =>
    File(caminho).readAsStringSync().replaceAll(String.fromCharCode(13), '');

Widget _app(Widget filho, {double letra = 1.0}) => MaterialApp(
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context)
            .copyWith(textScaler: TextScaler.linear(letra)),
        child: child!,
      ),
      home: filho,
    );

Widget _barra(List<BoraSeparador> separadores, int atual,
        ValueChanged<int> aoMudar) =>
    Scaffold(
      body: const SizedBox.expand(),
      bottomNavigationBar: BoraBarraSeparadores(
        separadores: separadores,
        atual: atual,
        aoMudar: aoMudar,
      ),
    );

Color? _corDoIcone(WidgetTester t, IconData icone) =>
    t.widget<Icon>(find.byIcon(icone)).color;

void main() {
  test('o verde da casa é o #16A34A (e o cinzento dos inativos)', () {
    expect(AppColors.primary, const Color(0xFF16A34A));
    expect(AppColors.textSubtle, const Color(0xFF9CA3AF));
  });

  group('estafeta — barra de baixo', () {
    test('4 separadores: Início, Ganhos, Pedidos, Conta', () {
      expect(DriverMainScreen.separadores.map((s) => s.rotulo).toList(),
          ['Início', 'Ganhos', 'Pedidos', 'Conta']);
      expect(DriverMainScreen.inicio, 0);
      expect(DriverMainScreen.ganhos, 1);
      expect(DriverMainScreen.pedidos, 2);
      expect(DriverMainScreen.conta, 3);
    });

    testWidgets('mostra os 4 rótulos, o ativo a verde e diz qual se tocou',
        (t) async {
      final tocados = <int>[];
      await t.pumpWidget(_app(_barra(DriverMainScreen.separadores,
          DriverMainScreen.inicio, tocados.add)));

      for (final r in ['Início', 'Ganhos', 'Pedidos', 'Conta']) {
        expect(find.text(r), findsOneWidget, reason: r);
      }
      // Início ativo (ícone cheio, verde); os outros com o ícone de contorno.
      expect(_corDoIcone(t, Icons.map), AppColors.primary);
      expect(_corDoIcone(t, Icons.bar_chart_outlined), AppColors.textSubtle);
      expect(_corDoIcone(t, Icons.receipt_long_outlined), AppColors.textSubtle);
      expect(_corDoIcone(t, Icons.person_outline), AppColors.textSubtle);
      expect(
          find.byWidgetPredicate(
              (w) => w is Icon && w.color == AppColors.accent),
          findsNothing,
          reason: 'regra do laranja: a barra não gasta o laranja do ecrã');

      await t.tap(find.text('Ganhos'));
      await t.tap(find.text('Pedidos'));
      await t.tap(find.text('Conta'));
      await t.tap(find.text('Início'));
      expect(tocados, [1, 2, 3, 0]);
    });

    testWidgets('separador Conta: as 4 linhas com texto e cada uma chama o seu',
        (t) async {
      var mudarModo = 0;
      await t.pumpWidget(
          _app(ContaEstafetaScreen(aoMudarModo: () => mudarModo++)));

      expect(find.text('Conta'), findsOneWidget); // título do separador
      for (final chave in [
        'perfil',
        'minha_conta',
        'trabalhar_noutra_coisa',
        'mudar_modo',
      ]) {
        expect(find.byKey(Key('ligacao_$chave')), findsOneWidget,
            reason: chave);
      }
      // O que antes eram botões redondos só com ícone, agora com o nome.
      expect(find.text('Perfil'), findsOneWidget);
      expect(find.text('A minha conta'), findsOneWidget);
      expect(find.text('Trabalhar noutra coisa'), findsOneWidget);
      expect(find.text('Mudar modo'), findsOneWidget);

      await t.tap(find.text('Mudar modo'));
      expect(mudarModo, 1);
    });

    testWidgets('as linhas da Conta ligam cada uma ao seu destino', (t) async {
      final chamados = <String>[];
      await t.pumpWidget(_app(Scaffold(
        body: BoraListaLigacoes(
          ligacoes: ligacoesDaContaEstafeta(
            aoAbrirPerfil: () => chamados.add('perfil'),
            aoAbrirMinhaConta: () => chamados.add('minha_conta'),
            aoTrabalharNoutraCoisa: () => chamados.add('trabalhar'),
            aoMudarModo: () => chamados.add('modo'),
          ),
        ),
      )));
      for (final r in [
        'Perfil',
        'A minha conta',
        'Trabalhar noutra coisa',
        'Mudar modo',
      ]) {
        await t.tap(find.text(r));
      }
      expect(chamados, ['perfil', 'minha_conta', 'trabalhar', 'modo']);
    });

    testWidgets('separador Pedidos: sem nada e com pedidos em curso',
        (t) async {
      var abriuInicio = 0;
      await t.pumpWidget(_app(PedidosEstafetaCorpo(
        emCurso: 0,
        ofertas: 0,
        historico: const [],
        aoAbrirInicio: () => abriuInicio++,
      )));
      expect(find.text('Em curso'), findsOneWidget);
      expect(find.text('Histórico'), findsOneWidget);
      expect(find.text('Nenhum pedido em curso'), findsOneWidget);
      expect(find.text('Ainda não há entregas concluídas.'), findsOneWidget);

      await t.pumpWidget(_app(PedidosEstafetaCorpo(
        emCurso: 2,
        ofertas: 0,
        historico: const [],
        aoAbrirInicio: () => abriuInicio++,
      )));
      expect(find.text('2 pedidos em curso'), findsOneWidget);
      await t.tap(find.byKey(const Key('pedidos_estafeta_em_curso')));
      expect(abriuInicio, 1);
    });
  });

  group('parceiro — barra de baixo', () {
    test('4 separadores: Pedidos, Menu, Ganhos, Loja', () {
      expect(PartnerDashboardScreen.separadores.map((s) => s.rotulo).toList(),
          ['Pedidos', 'Menu', 'Ganhos', 'Loja']);
      expect(PartnerDashboardScreen.pedidos, 0);
      expect(PartnerDashboardScreen.menu, 1);
      expect(PartnerDashboardScreen.ganhos, 2);
      expect(PartnerDashboardScreen.loja, 3);
    });

    testWidgets('mostra os 4 rótulos, o ativo a verde e diz qual se tocou',
        (t) async {
      final tocados = <int>[];
      await t.pumpWidget(_app(_barra(PartnerDashboardScreen.separadores,
          PartnerDashboardScreen.loja, tocados.add)));
      for (final r in ['Pedidos', 'Menu', 'Ganhos', 'Loja']) {
        expect(find.text(r), findsOneWidget, reason: r);
      }
      expect(_corDoIcone(t, Icons.storefront), AppColors.primary);
      expect(_corDoIcone(t, Icons.receipt_long_outlined), AppColors.textSubtle);
      expect(
          _corDoIcone(t, Icons.restaurant_menu_outlined), AppColors.textSubtle);
      expect(_corDoIcone(t, Icons.bar_chart_outlined), AppColors.textSubtle);

      await t.tap(find.text('Pedidos'));
      await t.tap(find.text('Menu'));
      await t.tap(find.text('Ganhos'));
      expect(tocados, [0, 1, 2]);
    });

    testWidgets(
        'separador Loja: Mudar modo e A minha conta (eram ícones sem texto), '
        'Horários, Reservas Pro e Agenda de Marcações', (t) async {
      final chamados = <String>[];
      await t.pumpWidget(_app(Scaffold(
        body: SingleChildScrollView(
          child: BoraListaLigacoes(
            ligacoes: ligacoesDaLojaParceiro(
              reservasPro: true,
              agendaMarcacoes: true,
              aoAbrirHorarios: () => chamados.add('horarios'),
              aoAbrirReservasPro: () => chamados.add('reservas'),
              aoAbrirAgenda: () => chamados.add('agenda'),
              aoAbrirConta: () => chamados.add('conta'),
              aoMudarModo: () => chamados.add('modo'),
            ),
          ),
        ),
      )));
      for (final r in [
        'Horários de funcionamento',
        'Reservas Pro',
        'Agenda de Marcações',
        'A minha conta',
        'Mudar modo',
      ]) {
        expect(find.text(r), findsOneWidget, reason: r);
        await t.tap(find.text(r));
      }
      expect(chamados, ['horarios', 'reservas', 'agenda', 'conta', 'modo']);
    });

    testWidgets('Loja sem Reservas Pro nem serviços: só o que a loja tem',
        (t) async {
      await t.pumpWidget(_app(Scaffold(
        body: BoraListaLigacoes(
          ligacoes: ligacoesDaLojaParceiro(
            reservasPro: false,
            agendaMarcacoes: false,
            aoAbrirHorarios: () {},
            aoAbrirReservasPro: () {},
            aoAbrirAgenda: () {},
            aoAbrirConta: () {},
            aoMudarModo: () {},
          ),
        ),
      )));
      expect(find.text('Horários de funcionamento'), findsOneWidget);
      expect(find.text('A minha conta'), findsOneWidget);
      expect(find.text('Mudar modo'), findsOneWidget);
      expect(find.text('Reservas Pro'), findsNothing);
      expect(find.text('Agenda de Marcações'), findsNothing);
    });

    testWidgets('separador Ganhos: os 4 botões de dinheiro, com texto',
        (t) async {
      final chamados = <String>[];
      await t.pumpWidget(_app(Scaffold(
        body: BoraListaLigacoes(
          ligacoes: ligacoesDosGanhosParceiro(
            aoVerDetalhe: () => chamados.add('detalhe'),
            aoReceberPagamentos: () => chamados.add('receber'),
            aoVerExtrato: () => chamados.add('extrato'),
            aoDadosFiscais: () => chamados.add('fiscais'),
          ),
        ),
      )));
      for (final r in [
        'Ver detalhe de ganhos',
        'Receber pagamentos',
        'Extrato',
        'Dados fiscais',
      ]) {
        expect(find.text(r), findsOneWidget, reason: r);
        await t.tap(find.text(r));
      }
      expect(chamados, ['detalhe', 'receber', 'extrato', 'fiscais']);
    });
  });

  testWidgets('ecrã pequeno (360 x 640) com letra a 2×: a barra não rebenta',
      (t) async {
    t.view.physicalSize = const Size(360, 640);
    t.view.devicePixelRatio = 1.0;
    addTearDown(t.view.reset);

    for (final separadores in [
      DriverMainScreen.separadores,
      PartnerDashboardScreen.separadores,
    ]) {
      await t.pumpWidget(_app(_barra(separadores, 0, (_) {}), letra: 2.0));
      expect(t.takeException(), isNull);
      for (final s in separadores) {
        expect(find.text(s.rotulo), findsOneWidget, reason: s.rotulo);
      }
    }
  });

  group('pela fonte', () {
    test('o mapa do estafeta deixou os 4 botões redondos só com ícone', () {
      final home = _ler('lib/screens/driver_home_screen.dart');
      expect(home, isNot(contains('_FloatingIconButton(')));
      expect(home, isNot(contains("tooltip: 'Mudar modo'")));
      expect(home, isNot(contains('tooltip: "Ganhos"')));
      expect(home, isNot(contains("tooltip: 'Perfil'")));
      // O cartão do Online não soma a faixa duas vezes dentro da barra.
      expect(home, contains('(widget.dentroDaBarra ? 0 : faixa)'));
      // Nada escondido em menus de 3 pontos ou gavetas.
      expect(home, isNot(contains('PopupMenuButton')));
      expect(home, isNot(contains('drawer:')));
    });

    test('a casa do estafeta tem a barra e o Início é o DriverHomeScreen', () {
      final casa = _ler('lib/screens/driver_main_screen.dart');
      expect(casa, contains('const DriverHomeScreen(dentroDaBarra: true)'));
      expect(casa, contains('IndexedStack('));
      expect(casa, contains('BoraBarraSeparadores('));
      // Sem pushReplacement para ecrãs principais (regra do repo).
      expect(casa, isNot(contains('pushReplacement')));
      final main = _ler('lib/main.dart');
      expect(main,
          contains("TermsGate(audience: 'estafeta', child: DriverMainScreen())"));
      expect(main, isNot(contains('child: DriverHomeScreen()')));
    });

    test('o parceiro tem a barra e deixou os ícones sem texto no topo', () {
      final p = _ler('lib/screens/partner_dashboard_screen.dart');
      expect(p, contains('bottomNavigationBar: BoraBarraSeparadores('));
      expect(p, isNot(contains("tooltip: 'Mudar modo'")));
      expect(p, isNot(contains("tooltip: 'A minha conta'")));
      expect(p, contains('aoMudarModo: _handleTestMode'));
      expect(p, contains('builder: (_) => const ProfileScreen()'));
      expect(p, isNot(contains('PopupMenuButton')));
      expect(p, isNot(contains('drawer:')));
    });
  });
}
