// Escada de prémios do check-in (04/11/2026, missão checkin-escada-premios, blocos C e D):
//   - o estado lê a foto/loja de cada prémio, os tokens por dia e o próximo prémio;
//   - "Levantar" dentro dos 30 dias explica até quando o prémio fica guardado;
//   - o calendário mostra todos os dias: foto nos dias com prémio, tokens nos outros.
import 'package:bora_app/services/checkin_premios_service.dart';
import 'package:bora_app/widgets/checkin/checkin_mes_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, dynamic> _json({String? proximo}) => {
      'marcos_ativos': true,
      'ciclo_dias': 30,
      'dias_seguidos': 9,
      'dia_marco': 9,
      'hoje_feito': true,
      'tokens_por_dia': [5, 5, 10, 10, 15, 15, 40],
      'marcos': [
        {'chave': 'semana', 'dia': 7, 'tipo': 'tokens', 'titulo': 'os tokens do Dia 7', 'tokens': 40, 'atingido': true, 'faltam': 0},
        {
          'chave': 'salgados', 'dia': 14, 'tipo': 'produto', 'titulo': '2 salgados da Keli',
          'descricao': 'Na Sabores do Brasil', 'atingido': false, 'faltam': 5,
          'foto_url': 'https://exemplo.invalid/salgados.jpg', 'loja_nome': 'Sabores do Brasil',
        },
        {'chave': 'mes', 'dia': 30, 'tipo': 'servico', 'titulo': '2 horas de limpeza', 'atingido': false, 'faltam': 21},
      ],
      'escada': {
        'ativa': true,
        'texto': '',
        if (proximo != null) 'proximo_premio_em': proximo,
        'intervalo_dias': 30,
      },
    };

void main() {
  group('modelo', () {
    test('lê foto, loja, tokens por dia e próximo prémio', () {
      final e = CheckinPremiosEstado.fromJson(_json(proximo: '2099-11-28T11:12:07Z'));
      final salgados = e.marcos.firstWhere((m) => m.chave == 'salgados');
      expect(salgados.fotoUrl, 'https://exemplo.invalid/salgados.jpg');
      expect(salgados.lojaNome, 'Sabores do Brasil');
      expect(e.tokensDoDia(1), 5);
      expect(e.tokensDoDia(7), 40);
      expect(e.tokensDoDia(8), 5); // a semana recomeça
      expect(e.escada!.premioBloqueado(), isTrue);
      expect(e.escada!.intervaloDias, 30);
    });

    test('sem próximo prémio (ou no passado) não está bloqueado', () {
      expect(CheckinPremiosEstado.fromJson(_json()).escada!.premioBloqueado(), isFalse);
      expect(CheckinPremiosEstado.fromJson(_json(proximo: '2001-01-01T00:00:00Z')).escada!.premioBloqueado(), isFalse);
    });

    test('Levantar dentro dos 30 dias: mensagem com a data', () {
      final r = CheckinEscadaResultado.fromJson({
        'ok': false,
        'reason': 'intervalo',
        'proximo_premio_em': '2026-11-28T11:12:07Z',
      });
      expect(r.proximoPremioEm, isNotNull);
      final msg = mensagemErroEscada(r.reason, proximoPremioEm: r.proximoPremioEm);
      expect(msg, contains('28/11'));
      expect(msg, contains('fica guardado'));
      expect(mensagemErroEscada('intervalo'), contains('fica guardado'));
    });
  });

  group('calendário', () {
    testWidgets('mostra todos os dias, foto no dia do prémio e tokens nos outros', (t) async {
      final e = CheckinPremiosEstado.fromJson(_json(proximo: '2099-11-28T11:12:07Z'));
      await t.pumpWidget(MaterialApp(
        home: Scaffold(body: SingleChildScrollView(child: CalendarioPremios(estado: e))),
      ));
      await t.pump();
      expect(find.byKey(const Key('checkin_cal_dia_1')), findsOneWidget);
      expect(find.byKey(const Key('checkin_cal_dia_30')), findsOneWidget);
      // dia 14 tem a foto do prémio
      expect(find.descendant(of: find.byKey(const Key('checkin_cal_dia_14')), matching: find.byType(Image)),
          findsOneWidget);
      expect(find.descendant(of: find.byKey(const Key('checkin_cal_dia_14')), matching: find.text('2 salgados da Keli')),
          findsOneWidget);
      // dia 3 não tem prémio: mostra os tokens do dia
      expect(find.descendant(of: find.byKey(const Key('checkin_cal_dia_3')), matching: find.text('+10')),
          findsOneWidget);
      expect(find.byKey(const Key('checkin_proximo_premio_em')), findsOneWidget);
      expect(find.textContaining('fica guardado'), findsOneWidget);
    });

    testWidgets('sem bloqueio não mostra "próximo prémio disponível"', (t) async {
      final e = CheckinPremiosEstado.fromJson(_json());
      await t.pumpWidget(MaterialApp(
        home: Scaffold(body: SingleChildScrollView(child: CalendarioPremios(estado: e))),
      ));
      await t.pump();
      expect(find.byKey(const Key('checkin_proximo_premio_em')), findsNothing);
    });
  });
}
