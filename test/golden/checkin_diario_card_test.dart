import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:bora_app/config/app_theme.dart';
import 'package:bora_app/l10n/bora_lang.dart';
import 'package:bora_app/services/checkin_service.dart';
import 'package:bora_app/services/wallet_service.dart';
import 'package:bora_app/widgets/home/checkin_diario_card.dart';

import 'fabrica_de_fotos.dart';

/// Cartão "Check-in diário" da home do cliente (Bora Todo Dia, 13/10/2026).
///
/// Regras do Danilo: 7 dias com 5,5,10,10,15,15,40 tokens; o dia de hoje
/// destacado; botão verde "Fazer check-in"; depois de feito, "Volta amanhã
/// para ganhar X tokens"; sem telemóvel, "Confirma o teu telemóvel para ganhar
/// tokens". O cartão nunca pode estourar no ecrã mais pequeno (320 px), nem em
/// inglês — o autoteste dos 3 perfis chumba qualquer overflow.
CheckinEstado _estado({
  bool enabled = true,
  bool eligible = true,
  String? reason,
  bool alreadyDone = false,
  int streakDay = 3,
  int? tokensAwarded,
  int? balance,
}) {
  const premios = [5, 5, 10, 10, 15, 15, 40];
  final proximo = alreadyDone ? (streakDay >= 7 ? 1 : streakDay + 1) : streakDay;
  return CheckinEstado(
    enabled: enabled,
    eligible: eligible,
    reason: reason,
    alreadyDone: alreadyDone,
    streakDay: streakDay,
    tokensToday: premios[streakDay - 1],
    nextDay: proximo,
    nextReward: premios[proximo - 1],
    rewards: premios,
    tokensAwarded: tokensAwarded,
    balance: balance,
  );
}

Widget _tela(CheckinDiarioCard cartao) => Scaffold(
      backgroundColor: const Color(0xFFF9FAFB),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Align(alignment: Alignment.topCenter, child: cartao),
      ),
    );

void main() {
  setUpAll(() async {
    await carregaFonteInter();
    await carregaFontesSdk();
  });

  final estados = <String, CheckinEstado>{
    'por_fazer_dia3': _estado(),
    'feito_dia7': _estado(alreadyDone: true, streakDay: 7),
    'sem_telemovel': _estado(eligible: false, reason: 'sem_telemovel', streakDay: 1),
  };

  for (final MapEntry(key: nome, value: e) in estados.entries) {
    for (final t in kTamanhos) {
      testWidgets('desenha "$nome" sem estourar em ${t.$1}', (tester) async {
        await fotografaTela(
          tester,
          nome: 'checkin_diario_$nome',
          tamanho: t,
          tela: _tela(CheckinDiarioCard(carregar: () async => e)),
        );
        expect(find.byKey(const Key('checkin_diario_card')), findsOneWidget);
        for (var d = 1; d <= 7; d++) {
          expect(find.byKey(Key('checkin_dia_$d')), findsOneWidget);
        }
      });
    }
  }

  group('em inglês', () {
    setUp(() => BoraLang.notifier.value = AppLang.en);
    tearDown(() => BoraLang.notifier.value = AppLang.pt);

    for (final MapEntry(key: nome, value: e) in estados.entries) {
      testWidgets('"$nome" em inglês cabe em 320 px', (tester) async {
        await fotografaTela(
          tester,
          nome: 'en_checkin_diario_$nome',
          tamanho: ('pequeno', kEcraPequeno),
          tela: _tela(CheckinDiarioCard(carregar: () async => e)),
        );
        expect(find.text('Daily check-in'), findsOneWidget);
      });
    }
  });

  testWidgets('mostra os 7 prémios e o botão verde "Fazer check-in"', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: _tela(CheckinDiarioCard(carregar: () async => _estado())),
    ));
    await tester.pump();

    expect(find.text('Check-in diário'), findsOneWidget);
    for (final p in ['+5', '+10', '+15', '+40']) {
      expect(find.text(p), findsWidgets);
    }
    final botao = tester.widget<FilledButton>(find.byKey(const Key('btn_checkin')));
    expect(botao.onPressed, isNotNull);
    expect(botao.style?.backgroundColor?.resolve({}), const Color(0xFF16A34A));
    expect(find.text('Fazer check-in'), findsOneWidget);
  });

  testWidgets('o texto do botão é desenhado em Inter (tema da app)', (tester) async {
    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.lightTheme,
      home: _tela(CheckinDiarioCard(carregar: () async => _estado())),
    ));
    await tester.pump();
    final desenhado = tester.widget<RichText>(find.descendant(
      of: find.byKey(const Key('btn_checkin')),
      matching: find.byType(RichText),
    ));
    expect(desenhado.text.style?.fontFamily, 'Inter');
  });

  testWidgets('ao fazer check-in mostra os tokens a entrar, o saldo e "Volta amanhã"',
      (tester) async {
    final antes = WalletService.saldoMudou.value;
    var chamadas = 0;
    await tester.pumpWidget(MaterialApp(
      home: _tela(CheckinDiarioCard(
        carregar: () async => _estado(),
        fazer: () async {
          chamadas++;
          return _estado(alreadyDone: true, streakDay: 3, tokensAwarded: 10, balance: 125);
        },
      )),
    ));
    await tester.pump();

    await tester.tap(find.byKey(const Key('btn_checkin')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    // a meio da animação, os "+10 tokens" estão a subir
    expect(find.byKey(const Key('checkin_tokens_a_entrar')), findsOneWidget);
    await tester.pumpAndSettle();

    expect(chamadas, 1);
    expect(find.text('Ganhaste 10 tokens!'), findsOneWidget);
    expect(find.text('Volta amanhã para ganhar 10 tokens.'), findsOneWidget); // Dia 3 feito → amanhã Dia 4 = 10
    expect(find.text('Saldo: 125 tokens'), findsOneWidget);
    expect(find.byKey(const Key('btn_checkin')), findsNothing);
    // o saldo do perfil volta a ser lido
    expect(WalletService.saldoMudou.value, antes + 1);
  });

  testWidgets('toque repetido no mesmo dia não anima nem mexe no saldo', (tester) async {
    final antes = WalletService.saldoMudou.value;
    await tester.pumpWidget(MaterialApp(
      home: _tela(CheckinDiarioCard(
        carregar: () async => _estado(),
        fazer: () async => _estado(alreadyDone: true, tokensAwarded: 0, balance: 100),
      )),
    ));
    await tester.pump();
    await tester.tap(find.byKey(const Key('btn_checkin')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('checkin_tokens_a_entrar')), findsNothing);
    expect(find.textContaining('Ganhaste'), findsNothing);
    expect(find.text('Volta amanhã para ganhar 10 tokens.'), findsOneWidget); // Dia 3 feito → amanhã Dia 4 = 10
    expect(WalletService.saldoMudou.value, antes);
  });

  testWidgets('uma releitura lançada antes do check-in e chegada depois não repõe o botão',
      (tester) async {
    final atrasada = Completer<CheckinEstado?>();
    var leituras = 0;
    await tester.pumpWidget(MaterialApp(
      home: _tela(CheckinDiarioCard(
        carregar: () {
          leituras++;
          return leituras == 1 ? Future.value(_estado()) : atrasada.future;
        },
        fazer: () async => _estado(alreadyDone: true, tokensAwarded: 10, balance: 50),
      )),
    ));
    await tester.pump();
    // volta à app: começa uma releitura que fica pendurada
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
    expect(leituras, 2);

    await tester.tap(find.byKey(const Key('btn_checkin')));
    await tester.pumpAndSettle();
    // a releitura antiga chega agora, com o estado de antes do check-in
    atrasada.complete(_estado());
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('btn_checkin')), findsNothing);
    expect(find.text('Ganhaste 10 tokens!'), findsOneWidget);
  });

  testWidgets('ao voltar à app o saldo antigo some (pode ter gasto os tokens)', (tester) async {
    var leituras = 0;
    await tester.pumpWidget(MaterialApp(
      home: _tela(CheckinDiarioCard(
        carregar: () async {
          leituras++;
          return leituras == 1 ? _estado() : _estado(alreadyDone: true);
        },
        fazer: () async => _estado(alreadyDone: true, tokensAwarded: 10, balance: 45),
      )),
    ));
    await tester.pump();
    await tester.tap(find.byKey(const Key('btn_checkin')));
    await tester.pumpAndSettle();
    expect(find.text('Saldo: 45 tokens'), findsOneWidget);

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('checkin_saldo')), findsNothing);
    expect(find.textContaining('Ganhaste'), findsNothing);
    expect(find.text('Volta amanhã para ganhar 10 tokens.'), findsOneWidget);
  });

  testWidgets('tempo esgotado e nova tentativa já feita: o saldo do perfil volta a ser lido',
      (tester) async {
    final antes = WalletService.saldoMudou.value;
    var tentativas = 0;
    await tester.pumpWidget(MaterialApp(
      home: _tela(CheckinDiarioCard(
        carregar: () async => _estado(),
        fazer: () async {
          tentativas++;
          if (tentativas == 1) throw TimeoutException('15 s');
          // o servidor tinha gravado a primeira: agora vem 0 tokens
          return _estado(alreadyDone: true, tokensAwarded: 0, balance: 60);
        },
      )),
    ));
    await tester.pump();
    await tester.tap(find.byKey(const Key('btn_checkin')));
    await tester.pumpAndSettle();
    expect(find.text('Não foi possível fazer o check-in. Tenta de novo.'), findsOneWidget);

    await tester.tap(find.byKey(const Key('btn_checkin')));
    await tester.pumpAndSettle();

    expect(tentativas, 2);
    expect(find.byKey(const Key('checkin_feito')), findsOneWidget);
    expect(WalletService.saldoMudou.value, antes + 1);
  });

  testWidgets('falha do servidor: avisa e deixa tentar de novo', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: _tela(CheckinDiarioCard(
        carregar: () async => _estado(),
        fazer: () async => throw Exception('rede'),
      )),
    ));
    await tester.pump();
    await tester.tap(find.byKey(const Key('btn_checkin')));
    await tester.pumpAndSettle();

    expect(find.text('Não foi possível fazer o check-in. Tenta de novo.'), findsOneWidget);
    final botao = tester.widget<FilledButton>(find.byKey(const Key('btn_checkin')));
    expect(botao.onPressed, isNotNull);
  });

  testWidgets('sem telemóvel: pede confirmação e abre o ecrã certo', (tester) async {
    var abriu = 0;
    var leituras = 0;
    await tester.pumpWidget(MaterialApp(
      home: _tela(CheckinDiarioCard(
        carregar: () async {
          leituras++;
          return leituras == 1
              ? _estado(eligible: false, reason: 'sem_telemovel', streakDay: 1)
              : _estado(streakDay: 1);
        },
        confirmarTelemovel: (_) async => abriu++,
      )),
    ));
    await tester.pump();

    expect(find.text('Confirma o teu telemóvel para ganhar tokens'), findsOneWidget);
    expect(find.byKey(const Key('btn_checkin')), findsNothing);
    await tester.tap(find.byKey(const Key('btn_checkin_confirmar_telemovel')));
    await tester.pumpAndSettle();

    expect(abriu, 1);
    // depois de confirmar, relê o estado e já pode fazer check-in
    expect(find.byKey(const Key('btn_checkin')), findsOneWidget);
  });

  testWidgets('desligado, sem função no servidor ou sem papel de cliente: não aparece',
      (tester) async {
    for (final e in <CheckinEstado?>[
      null,
      _estado(enabled: false, eligible: false, reason: 'desligado'),
      _estado(eligible: false, reason: 'nao_cliente'),
    ]) {
      await tester.pumpWidget(MaterialApp(
        home: _tela(CheckinDiarioCard(key: UniqueKey(), carregar: () async => e)),
      ));
      await tester.pump();
      expect(find.byKey(const Key('checkin_diario_card')), findsNothing);
    }
  });

  test('lê a resposta do servidor (client_checkin_status / client_daily_checkin)', () {
    final e = CheckinEstado.fromJson({
      'enabled': true,
      'eligible': true,
      'reason': null,
      'today': '2026-10-13',
      'already_done': false,
      'streak_day': 6,
      'tokens_today': 15,
      'next_day': 6,
      'next_reward': 15,
      'rewards': [5, 5, 10, 10, 15, 15, 40],
      'streak_running': true,
      'require_phone': true,
    });
    expect(e.mostrarCartao, isTrue);
    expect(e.streakDay, 6);
    expect(e.tokensAwarded, isNull);

    final r = CheckinEstado.fromJson({
      'ok': true,
      'enabled': true,
      'eligible': true,
      'already_done': false,
      'streak_day': 7,
      'tokens_today': 40,
      'next_day': 1,
      'next_reward': 5,
      'rewards': [5, 5, 10, 10, 15, 15, 40],
      'tokens_awarded': 40,
      'balance': 140,
    });
    expect(r.tokensAwarded, 40);
    expect(r.balance, 140);
    expect(r.nextReward, 5);
    // check-in acabado de fazer: o de hoje fica feito (o botão desaparece)
    expect(r.alreadyDone, isTrue);

    final recusa = CheckinEstado.fromJson({
      'ok': false,
      'enabled': true,
      'eligible': false,
      'reason': 'sem_telemovel',
      'already_done': false,
      'streak_day': 1,
      'tokens_awarded': 0,
      'rewards': [5, 5, 10, 10, 15, 15, 40],
    });
    expect(recusa.alreadyDone, isFalse);
    expect(recusa.semTelemovel, isTrue);
  });
}
