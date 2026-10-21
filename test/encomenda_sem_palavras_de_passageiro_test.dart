import 'dart:io';

import 'package:bora_app/models/ride_kind.dart';
import 'package:bora_app/models/tvde_ride.dart';
import 'package:bora_app/screens/driver/tvde/tvde_ride_active_screen.dart';
import 'package:bora_app/widgets/tvde/tvde_offer_overlay_host.dart';
import 'package:bora_app/widgets/tvde/tvde_roundtrip_driver_notice.dart';
import 'package:flutter/material.dart';
import 'package:flutter/widgets.dart' as w;
import 'package:flutter_test/flutter_test.dart';

/// 21/10/2026 · fechar-pendencias A1 · ronda 1 do revisor.
///
/// Percorre os ecrãs e as frases que uma ENCOMENDA mostra (tipo
/// `ride_kind='encomendas'`) e falha se aparecer "corrida", "motorista",
/// "viagem", "passageiro", "boleia" ou "condutor". O mesmo ecrã com uma
/// corrida de passageiros continua a dizer as palavras de sempre (controlo:
/// prova que o teste vê mesmo o texto).
TvdeRide _ride(String status,
        {RideKind tipo = RideKind.encomendas,
        bool emFila = false,
        DateTime? marcada,
        DateTime? expira,
        DateTime? reservaExpira,
        bool pacoteVolta = false}) =>
    TvdeRide.fromMap({
      'id': 'r1',
      'client_id': 'c1',
      'status': status,
      'origin_lat': 40.5285,
      'origin_lng': -7.2516,
      'dest_lat': 40.5407,
      'dest_lng': -7.2677,
      'est_distance_km': 4.5,
      'est_fare_cents': 700,
      'driver_earn_cents': 520,
      'payment_method': 'cash',
      'origin_label': 'Rua Marquês de Pombal 12',
      'dest_label': 'Estação da Guarda',
      'ride_kind': tipo.db,
      if (emFila) 'is_queued': true,
      if (marcada != null) 'scheduled_at': marcada.toUtc().toIso8601String(),
      if (marcada != null) 'reservation_status': 'a_procurar',
      if (expira != null) 'offer_expires_at': expira.toUtc().toIso8601String(),
      if (reservaExpira != null)
        'reservation_offer_expires_at': reservaExpira.toUtc().toIso8601String(),
      if (pacoteVolta) 'roundtrip_credit_id': 'v1',
      if (pacoteVolta) 'is_return_leg': true,
    });

Widget _app(Widget filho) => MaterialApp(home: Scaffold(body: Center(child: filho)));

/// Todo o texto desenhado (Text e RichText).
List<String> _textos(WidgetTester t) {
  final out = <String>[];
  for (final e in find.byType(Text).evaluate()) {
    final x = e.widget as Text;
    out.add(x.data ?? x.textSpan?.toPlainText() ?? '');
  }
  for (final e in find.byType(w.RichText).evaluate()) {
    out.add((e.widget as w.RichText).text.toPlainText());
  }
  return out;
}

List<String> _sujos(List<String> textos) =>
    textos.where((s) => kPalavrasDePassageiro.hasMatch(s)).toSet().toList();

void main() {
  group('frases do modelo numa encomenda', () {
    const estados = [
      'aguarda_pagamento', 'solicitada', 'sem_motorista', 'motorista_atribuido',
      'motorista_a_caminho', 'motorista_chegou', 'em_andamento', 'finalizada',
      'cancelada_cliente', 'cancelada_motorista', 'no_show',
    ];

    test('estado em palavras (statusLabel), todos os estados', () {
      for (final s in estados) {
        for (final fila in [false, true]) {
          final t = _ride(s, emFila: fila).statusLabel;
          expect(kPalavrasDePassageiro.hasMatch(t), isFalse, reason: '$s → "$t"');
        }
      }
      // controlo: passageiros igual a antes
      expect(_ride('solicitada', tipo: RideKind.passageiros).statusLabel,
          'À procura de motorista…');
      expect(_ride('em_andamento', tipo: RideKind.passageiros).statusLabel,
          'Viagem em curso');
    });

    test('título da fase do estafeta (driverPhaseTitle), com e sem nome', () {
      for (final s in estados) {
        for (final nome in [null, 'Maria']) {
          for (final fila in [false, true]) {
            final t = _ride(s, emFila: fila).driverPhaseTitle(passengerName: nome);
            expect(kPalavrasDePassageiro.hasMatch(t), isFalse, reason: '$s/$nome → "$t"');
          }
        }
      }
      expect(_ride('motorista_chegou', tipo: RideKind.passageiros).driverPhaseTitle(),
          'À espera do passageiro');
    });

    test('avisos ao estafeta fora dos ecrãs', () {
      expect(_sujos([
        textoDoAvisoDeCancelamento(null, rideKind: RideKind.encomendas),
        mensagemDeOfertaFalhada('x', rideKind: RideKind.encomendas),
        mensagemDeOfertaFalhada('queue_full', rideKind: RideKind.encomendas),
        mensagemDeOfertaFalhada('ride_conflict', rideKind: RideKind.encomendas),
        TvdeRoundtripDriverNotice.messageFor(_ride('motorista_a_caminho', pacoteVolta: true), 1760),
      ]), isEmpty);
    });
  });

  group('ecrã do estafeta numa encomenda', () {
    for (final s in ['motorista_a_caminho', 'motorista_chegou', 'em_andamento']) {
      testWidgets('cabeçalho e botão — $s', (tester) async {
        await tester.pumpWidget(_app(Column(children: [
          TvdeCorridaCabecalho(
            ride: _ride(s),
            passengerName: 'Maria',
            etaMin: 4,
            esperaSegundos: 75,
          ),
          TvdeCorridaBotaoPrincipal(ride: _ride(s), busy: false, onAtualizar: () {}),
        ])));
        final textos = _textos(tester);
        expect(textos, isNotEmpty);
        expect(_sujos(textos), isEmpty, reason: textos.join(' | '));
      });
    }

    testWidgets('espera na recolha com o "não compareceu" já liberto', (tester) async {
      await tester.pumpWidget(_app(TvdeCorridaCabecalho(
        ride: _ride('motorista_chegou'),
        esperaSegundos: 400,
        naoCompareceuLiberto: true,
      )));
      expect(_sujos(_textos(tester)), isEmpty, reason: _textos(tester).join(' | '));
    });

    testWidgets('em fila e reserva marcada', (tester) async {
      await tester.pumpWidget(_app(Column(children: [
        TvdeCorridaBotaoPrincipal(
            ride: _ride('motorista_atribuido', emFila: true), busy: false, onAtualizar: () {}),
        TvdeCorridaBotaoPrincipal(
            ride: _ride('motorista_atribuido',
                marcada: DateTime.now().add(const Duration(minutes: 15))),
            busy: false,
            onAtualizar: () {}),
      ])));
      expect(_sujos(_textos(tester)), isEmpty, reason: _textos(tester).join(' | '));
    });

    testWidgets('controlo: com passageiros o botão diz as palavras de sempre', (tester) async {
      await tester.pumpWidget(_app(TvdeCorridaBotaoPrincipal(
          ride: _ride('motorista_a_caminho', tipo: RideKind.passageiros),
          busy: false,
          onAtualizar: () {})));
      expect(find.text('Cheguei ao passageiro'), findsOneWidget);
    });
  });

  group('oferta ao estafeta numa encomenda', () {
    testWidgets('cartão da oferta: "Nova encomenda" e o ganho em grande', (tester) async {
      final agora = DateTime(2026, 10, 21, 12, 0, 0);
      await tester.pumpWidget(_app(TvdeOfferOverlayCard(
        offer: _ride('solicitada', expira: agora.add(const Duration(seconds: 30))),
        current: null,
        agora: () => agora,
        onAccept: () async {},
        onReject: () async {},
        onExpiredDismiss: () {},
      )));
      final textos = _textos(tester);
      expect(textos.any((t) => t.contains('Nova encomenda')), isTrue, reason: textos.join(' | '));
      expect(textos.any((t) => t.contains('5.20') || t.contains('5,20')), isTrue,
          reason: 'o ganho do estafeta (5,20 €) tem de estar no cartão');
      expect(_sujos(textos), isEmpty, reason: textos.join(' | '));
    });

    testWidgets('oferta expirada que foi para outro', (tester) async {
      final agora = DateTime(2026, 10, 21, 12, 0, 0);
      await tester.pumpWidget(_app(TvdeOfferOverlayCard(
        offer: _ride('solicitada', expira: agora.subtract(const Duration(seconds: 1))),
        current: null,
        agora: () => agora,
        tempoAteFechar: const Duration(seconds: 3),
        eMinha: () async => false,
        onAccept: () async {},
        onReject: () async {},
        onExpired: () {},
        onExpiredDismiss: () {},
      )));
      await tester.pump();
      await tester.pump();
      final textos = _textos(tester);
      expect(textos.any((t) => t.contains('encomenda')), isTrue, reason: textos.join(' | '));
      expect(_sujos(textos), isEmpty, reason: textos.join(' | '));
      await tester.pump(const Duration(seconds: 5));
    });

    testWidgets('oferta de encomenda marcada', (tester) async {
      final agora = DateTime(2026, 10, 21, 12, 0, 0);
      await tester.pumpWidget(_app(TvdeReservationOverlayCard(
        ride: _ride('agendada',
            marcada: agora.add(const Duration(hours: 3)),
            reservaExpira: agora.add(const Duration(minutes: 2))),
        agora: () => agora,
        onAccept: () {},
        onReject: () {},
        onExpiredDismiss: () {},
      )));
      expect(_sujos(_textos(tester)), isEmpty, reason: _textos(tester).join(' | '));
    });
  });

  test('os ecrãs do cliente e do estafeta não têm frases de passageiro soltas', () {
    // Ratchet: toda a literal com palavra de passageiro nestes ficheiros passa
    // pela camada de etiquetas (.trK/.trArgsK/.rk/.rkArgs) — ou está aqui,
    // com o motivo, na lista do que uma encomenda NUNCA mostra.
    const ficheiros = [
      'lib/screens/client/tvde/tvde_request_ride_screen.dart',
      'lib/screens/client/tvde/tvde_ride_tracking_screen.dart',
      'lib/screens/client/tvde/tvde_my_reservations_screen.dart',
      'lib/screens/client/tvde/tvde_rate_screen.dart',
      'lib/screens/client/tvde/tvde_schedule_ride_sheet.dart',
      'lib/screens/client/tvde/tvde_volta_sheet.dart',
      'lib/screens/client/tvde/ride_mbway_waiting_dialog.dart',
      'lib/screens/client/tvde/tvde_dest_change_sheet.dart',
      'lib/widgets/tvde/tvde_cancel_dialog.dart',
      'lib/widgets/tvde/recibo_viagem_sheet.dart',
      'lib/screens/driver/tvde/tvde_ride_active_screen.dart',
      'lib/screens/driver/tvde/tvde_driver_rate_screen.dart',
      'lib/screens/driver/tvde/tvde_offer_screen.dart',
      'lib/widgets/tvde/tvde_offer_overlay_host.dart',
      'lib/widgets/tvde/tvde_roundtrip_driver_notice.dart',
    ];
    // Literais que ficam, porque nunca aparecem numa encomenda:
    const permitidas = {
      // planos e marca do Bora Motorista (ecrã de planos, nome do separador)
      'Planos', 'Bora Motorista',
      // chave técnica do servidor, não é texto
      'motorista', 'tvde-recibo-viagem',
    };
    final lit = RegExp(r"""'((?:\\.|[^'\\\n])*)'""");
    final etiqueta = RegExp(r"""^\s*\.(trK|trArgsK|rk|rkArgs)\(""");
    final soltas = <String>[];
    for (final f in ficheiros) {
      final s = File(f).readAsStringSync();
      final linhas = s.split('\n');
      for (var i = 0; i < linhas.length; i++) {
        final l = linhas[i].trim();
        if (l.startsWith('//') || l.contains('debugPrint') || l.startsWith('import ')) continue;
        for (final m in lit.allMatches(linhas[i])) {
          final k = m.group(1)!;
          if (!kPalavrasDePassageiro.hasMatch(k)) continue;
          if (k.contains(r'$') || k.contains('_') && !k.contains(' ')) continue;
          if (permitidas.contains(k)) continue;
          final depois = linhas[i].substring(m.end) + (i + 1 < linhas.length ? linhas[i + 1] : '');
          if (etiqueta.hasMatch(depois)) continue;
          soltas.add('$f:${i + 1}: $k');
        }
      }
    }
    expect(soltas, isEmpty, reason: 'Frases de passageiro sem etiqueta:\n${soltas.join('\n')}');
  });
}
