import 'dart:io';

import 'package:bora_app/models/tvde_ride.dart';
import 'package:flutter_test/flutter_test.dart';

/// Corrida de balcão (missão `central-corridas-balcao-2026-09-18`): cliente
/// sem app, criada pelo admin por telefone. Regra de ouro do Danilo: o número
/// GRANDE que o motorista vê é sempre o que ele GANHA, e nunca se recalcula
/// por cima do valor combinado com o cliente.
///
/// Dois grupos:
///  1. o modelo `TvdeRide` — parsing e getters puros (sem Flutter);
///  2. regressão mecânica sobre o código-fonte dos ecrãs do motorista — trava
///     alguém a voltar a ler `ride.driverEarnCents` direto (perdendo o
///     combinado) ou a esquecer o selo "cliente sem app".
void main() {
  group('TvdeRide — campos da corrida de balcão', () {
    TvdeRide ride(Map<String, dynamic> extra) => TvdeRide.fromMap({
          'id': 'r1',
          'client_id': 'c1',
          'status': 'solicitada',
          'origin_lat': 40.5,
          'origin_lng': -7.26,
          'dest_lat': 40.6,
          'dest_lng': -7.3,
          'est_distance_km': 3.0,
          'est_fare_cents': 500,
          ...extra,
        });

    test('sem "source" no mapa ⇒ assume "app" (corrida normal)', () {
      final r = ride({});
      expect(r.source, 'app');
      expect(r.isCounterRide, isFalse);
    });

    test('source="balcao" ⇒ isCounterRide', () {
      final r = ride({'source': 'balcao'});
      expect(r.isCounterRide, isTrue);
    });

    test('agreed_fare_cents/agreed_driver_earn_cents são lidos do mapa', () {
      final r = ride({
        'source': 'balcao',
        'agreed_fare_cents': 500,
        'agreed_driver_earn_cents': 400,
      });
      expect(r.agreedFareCents, 500);
      expect(r.agreedDriverEarnCents, 400);
    });

    test(
        'netDriverEarnCents: o combinado manda quando existe, nunca soma '
        'nem recalcula por cima do driverEarnCents', () {
      final r = ride({
        'source': 'balcao',
        'agreed_driver_earn_cents': 400,
        'driver_earn_cents': 999, // se isto vencesse, seria o bug
      });
      expect(r.netDriverEarnCents, 400);
    });

    test(
        'netDriverEarnCents: sem combinado, usa driverEarnCents normal '
        '(corrida da app)', () {
      final r = ride({'driver_earn_cents': 450});
      expect(r.netDriverEarnCents, 450);
    });

    test('netDriverEarnCents: sem nenhum dos dois, 0 (nunca null/crash)', () {
      final r = ride({});
      expect(r.netDriverEarnCents, 0);
    });
  });

  group('ecrãs do motorista usam o valor combinado, nunca o recalculam', () {
    // Regex do "ganho em grande": `ride.netDriverEarnCents` ou
    // `<var>.netDriverEarnCents` (offer/queued usam nomes de variável
    // diferentes: ride, offer, queued).
    final ganhoGrande = RegExp(r'\.netDriverEarnCents\b');
    final ganhoCru = RegExp(r'\(([a-zA-Z_]+)\.driverEarnCents\s*\?\?\s*0\)');

    final ecrans = <String, List<String>>{
      'oferta ao motorista': [
        'lib/screens/driver/tvde/tvde_offer_screen.dart',
      ],
      'corrida ativa (painel de ação + fila)': [
        'lib/screens/driver/tvde/tvde_ride_active_screen.dart',
      ],
      'fim da corrida (avaliação)': [
        'lib/screens/driver/tvde/tvde_driver_rate_screen.dart',
      ],
    };

    for (final entry in ecrans.entries) {
      for (final path in entry.value) {
        test('${entry.key} ($path): usa netDriverEarnCents, não o cru', () {
          final fonte = File(path).readAsStringSync();
          expect(ganhoGrande.hasMatch(fonte), isTrue,
              reason: 'ficheiro $path: não usa ride.netDriverEarnCents — o '
                  'ganho em grande deixa de respeitar o valor combinado de '
                  'uma corrida de balcão.');
          expect(ganhoCru.hasMatch(fonte), isFalse,
              reason: 'ficheiro $path: ainda lê "X.driverEarnCents ?? 0" '
                  'direto — isso ignora o valor combinado (agreed_*) numa '
                  'corrida de balcão. Usa netDriverEarnCents.');
        });
      }
    }

    test('tvde_ride_active_screen.dart: também corrige a fila (queued)', () {
      final fonte = File('lib/screens/driver/tvde/tvde_ride_active_screen.dart')
          .readAsStringSync();
      expect(fonte, contains('queued.netDriverEarnCents'));
    });

    // [Oferta sobreposta 20/09] A faixa da oferta saiu do ecrã da corrida e
    // passou a ser o cartão global (por cima de qualquer ecrã). A regra é a
    // mesma — o valor combinado, nunca recalculado — só mudou de casa.
    test('tvde_offer_overlay_host.dart: a oferta sobreposta usa o combinado',
        () {
      final fonte = File('lib/widgets/tvde/tvde_offer_overlay_host.dart')
          .readAsStringSync();
      expect(fonte, contains('offer.netDriverEarnCents'));
    });
  });

  group('selo "cliente sem app" aparece só em corridas de balcão', () {
    final ecransComSelo = <String>[
      'lib/screens/driver/tvde/tvde_offer_screen.dart',
      'lib/screens/driver/tvde/tvde_ride_active_screen.dart',
      'lib/screens/driver/tvde/tvde_driver_rate_screen.dart',
    ];

    for (final path in ecransComSelo) {
      test('$path: TvdeCounterRideBadge está condicionado a isCounterRide',
          () {
        final fonte = File(path).readAsStringSync();
        expect(fonte, contains('TvdeCounterRideBadge'),
            reason: 'ficheiro $path: falta o selo "Cliente sem aplicação — '
                'liga-lhe"');
        // A regra é "SÓ corridas de balcão": o widget do selo tem de viver
        // dentro de um `if (<algo>.isCounterRide)`.
        expect(RegExp(r'if\s*\([a-zA-Z_.]*isCounterRide\)').hasMatch(fonte),
            isTrue,
            reason: 'ficheiro $path: o selo tem de estar condicionado a '
                '"ride.isCounterRide" (ou equivalente) — nunca aparecer numa '
                'corrida normal da app.');
      });
    }

    test('o selo em si não usa laranja (AppColors.accent) — audit-orange-rule',
        () {
      final fonte = File(
              'lib/widgets/tvde/tvde_counter_ride_badge.dart')
          .readAsStringSync();
      expect(fonte.contains('AppColors.accent'), isFalse,
          reason: 'a oferta e a corrida ativa já estão no limite da regra '
              '"1 laranja/ecrã" — o selo balcão tem de usar outra cor '
              '(AppColors.info)');
      expect(fonte, contains('AppColors.info'));
    });
  });

  group('fim de corrida não bloqueia à espera do cliente', () {
    test('tvde_driver_rate_screen.dart: sem gate de avaliação do cliente',
        () {
      final fonte = File(
              'lib/screens/driver/tvde/tvde_driver_rate_screen.dart')
          .readAsStringSync();
      // Cliente de balcão nunca avalia (não tem app) — o ecrã do motorista
      // não pode depender de `ratedByClient` para sair.
      expect(fonte.contains('ratedByClient'), isFalse,
          reason: 'o ecrã de fim de corrida do motorista não pode esperar '
              'uma ação do cliente (que, numa corrida de balcão, nunca '
              'existe)');
    });
  });
}
