import 'dart:io';

import 'package:bora_app/models/tvde_ride.dart';
import 'package:flutter_test/flutter_test.dart';

/// [Missão 04/10 · Bloco 5 · corrida 0d979026] O ecrã da corrida do CLIENTE
/// desapareceu quando o motorista iniciou a viagem (`em_andamento`), e nas
/// duas corridas desse dia (0d979026 e 8c7f5ca6, perna de volta do pacote) a
/// avaliação nunca apareceu — `rated_by_client` ficou a false.
///
/// A regra que estes testes prendem:
///  1. do pedido até `em_andamento` o ecrã da corrida fica vivo — a viagem
///     começar NÃO é a corrida acabar;
///  2. só `finalizada` por avaliar leva o cliente à avaliação;
///  3. quem reabre a app a meio da viagem reencontra a corrida, e quem a
///     reabre depois do fim reencontra a avaliação que ficou por dar.
TvdeRide _corrida(String status, {bool avaliada = false, bool volta = false}) =>
    TvdeRide.fromMap(<String, dynamic>{
      'id': 'r1',
      'client_id': 'c1',
      'status': status,
      'payment_method': 'cash',
      'rated_by_client': avaliada,
      'is_return_leg': volta,
      if (volta) 'roundtrip_credit_id': 'vale1',
      if (volta && status == 'finalizada') 'final_fare_cents': 0,
    });

void main() {
  group('estado do servidor → o ecrã da corrida fica vivo?', () {
    const vivos = [
      'aguarda_pagamento',
      'solicitada',
      'motorista_atribuido',
      'motorista_a_caminho',
      'motorista_chegou',
      'em_andamento',
    ];
    const mortos = [
      'finalizada',
      'cancelada_cliente',
      'cancelada_motorista',
      'no_show',
      'sem_motorista',
      'agendada',
    ];

    for (final s in vivos) {
      test('$s mantém o ecrã vivo', () {
        expect(TvdeRide.estadoMantemEcraVivo(s), isTrue);
      });
    }
    for (final s in mortos) {
      test('$s não mantém o ecrã vivo', () {
        expect(TvdeRide.estadoMantemEcraVivo(s), isFalse);
      });
    }

    test('em_andamento é corrida VIVA, não terminal, e não pede avaliação',
        () {
      final r = _corrida('em_andamento');
      expect(r.isInProgress, isTrue);
      expect(r.isLive, isTrue,
          reason: 'é o `isLive` que reabre o ecrã da corrida ao voltar à app');
      expect(r.isTerminal, isFalse);
      expect(r.isCancelled, isFalse);
      expect(r.aguardaAvaliacaoCliente, isFalse,
          reason: 'a viagem começar não pode mandar o cliente para a '
              'avaliação nem tirá-lo do mapa');
    });

    test('do motorista atribuído ao fim da viagem, o `isLive` nunca cai', () {
      for (final s in const [
        'motorista_atribuido',
        'motorista_a_caminho',
        'motorista_chegou',
        'em_andamento',
      ]) {
        expect(_corrida(s).isLive, isTrue, reason: 'estado $s');
        expect(TvdeRide.estadoMantemEcraVivo(s), isTrue, reason: 'estado $s');
      }
    });

    test('a regra pura e o `isLive` dizem o mesmo numa corrida em dinheiro',
        () {
      for (final s in [...vivos, ...mortos]) {
        if (s == 'aguarda_pagamento') continue; // depende do payment_status
        expect(_corrida(s).isLive, TvdeRide.estadoMantemEcraVivo(s),
            reason: 'estado $s');
      }
    });
  });

  group('só finalizada por avaliar leva à avaliação', () {
    test('finalizada e não avaliada → avaliação', () {
      expect(_corrida('finalizada').aguardaAvaliacaoCliente, isTrue);
    });

    test('perna de volta do pacote (final 0 €) também pede avaliação', () {
      // Corrida 8c7f5ca6: is_return_leg=true, final_fare_cents=0.
      final r = _corrida('finalizada', volta: true);
      expect(r.finalFareCents, 0);
      expect(r.aguardaAvaliacaoCliente, isTrue);
    });

    test('finalizada já avaliada → não volta a pedir', () {
      expect(_corrida('finalizada', avaliada: true).aguardaAvaliacaoCliente,
          isFalse);
    });

    test('nenhum outro estado pede avaliação', () {
      for (final s in const [
        'solicitada',
        'motorista_atribuido',
        'motorista_a_caminho',
        'motorista_chegou',
        'em_andamento',
        'cancelada_cliente',
        'cancelada_motorista',
        'no_show',
        'sem_motorista',
      ]) {
        expect(_corrida(s).aguardaAvaliacaoCliente, isFalse,
            reason: 'estado $s');
      }
    });
  });

  group('regressão sobre o código-fonte', () {
    final store = File('lib/stores/tvde_store.dart').readAsStringSync();
    final ecra =
        File('lib/screens/client/tvde/tvde_ride_tracking_screen.dart')
            .readAsStringSync();
    final avaliar = File('lib/screens/client/tvde/tvde_rate_screen.dart')
        .readAsStringSync();

    /// Os estados que o `loadActiveRide` pede ao servidor.
    Set<String> estadosDoResume() {
      final inicio = store.indexOf('Future<void> loadActiveRide()');
      expect(inicio, isNot(-1), reason: 'loadActiveRide desapareceu do store');
      final filtro = store.indexOf(".inFilter('status'", inicio);
      expect(filtro, isNot(-1),
          reason: 'loadActiveRide já não filtra por status');
      final fim = store.indexOf('])', filtro);
      final bloco = store.substring(filtro + ".inFilter('status'".length, fim);
      return RegExp(r"'([a-z_]+)'")
          .allMatches(bloco)
          .map((m) => m.group(1)!)
          .toSet();
    }

    test('o resume (loadActiveRide) pede em_andamento e os estados com '
        'motorista', () {
      final estados = estadosDoResume();
      for (final s in const [
        'solicitada',
        'motorista_atribuido',
        'motorista_a_caminho',
        'motorista_chegou',
        'em_andamento',
      ]) {
        expect(estados, contains(s),
            reason: 'sem `$s` no filtro, reabrir a app a meio da corrida '
                'deixa o cliente sem o ecrã dela');
      }
    });

    test('o resume não pede nenhum estado que o ecrã não mantenha vivo', () {
      for (final s in estadosDoResume()) {
        expect(TvdeRide.estadoMantemEcraVivo(s), isTrue, reason: 'estado $s');
      }
    });

    test('o ecrã só vai para a avaliação pela regra única', () {
      expect(ecra, contains('ride.aguardaAvaliacaoCliente'),
          reason: 'o salto para a avaliação tem de sair de '
              '`TvdeRide.aguardaAvaliacaoCliente`, não de uma condição solta');
    });

    test('nenhum fecho do ecrã depende de a viagem ter começado', () {
      // Um `if (ride.isInProgress)` seguido de pop/clear seria o defeito de
      // volta: iniciar a viagem não fecha nada.
      final fechaEmViagem = RegExp(
          r'if\s*\(\s*ride\.isInProgress\s*\)\s*\{?\s*'
          r'(Navigator\.|store\.clearActiveRide|context\.read<TvdeStore>\(\)\.clearActiveRide)');
      expect(fechaEmViagem.hasMatch(ecra), isFalse);
    });

    test('ecrã aberto com o store vazio vai buscar a corrida ao servidor', () {
      expect(ecra, contains('store.loadActiveRide()'),
          reason: 'app recarregada a meio da corrida: sem isto o ecrã fica '
              'em "Sem corrida ativa" com a viagem a decorrer');
    });

    test('ao reabrir sem corrida viva, procura a finalizada por avaliar', () {
      expect(store, contains('_loadRideAwaitingRating(uid)'));
      expect(store, contains(".eq('rated_by_client', false)"));
      expect(store, contains('rideAwaitingRating'));
      expect(avaliar, contains('abrirSePendente'),
          reason: 'falta a porta que abre a avaliação pendente');
    });

    test('avaliação vista uma vez não é pedida outra vez', () {
      expect(avaliar, contains('dismissRideAwaitingRating'));
    });
  });
}
