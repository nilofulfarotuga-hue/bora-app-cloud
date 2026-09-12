import 'package:bora_app/models/tvde_ride.dart';
import 'package:bora_app/utils/tvde_stops_route.dart';
import 'package:flutter_test/flutter_test.dart';

/// [Missão TVDE 05/09, parte 2] O cliente paga 2 euros por cada paragem que
/// acrescenta a meio da corrida (`tvde_stop_fee_cents` = 200), o motorista
/// recebe 1 euro (`tvde_stop_driver_cents` = 100), até duas por corrida
/// (`tvde_max_stops` = 2). Valores confirmados em `platform_settings`.
///
/// **A cicatriz:** o `DirectionsService.fetchRoute` aceita `waypoints` desde
/// sempre, mas em todo o `lib/` só o mapa das ENTREGAS os passava. O ecrã de
/// corrida do TVDE carregava as paragens e nunca as passava a lado nenhum.
/// Cobrava-se por uma paragem que o mapa ignorava — e o tempo de chegada
/// prometia um destino que o carro não conseguia cumprir.
///
/// Estes testes trancam as duas metades: a rota passa pelas paragens por
/// ordem e larga cada uma quando é alcançada; e o tempo de chegada soma o
/// tempo parado que ainda falta.
TvdeRideStop _stop(int seq, {bool alcancada = false, double lat = 40.53, double lng = -7.26}) =>
    TvdeRideStop(
      id: 's$seq',
      seq: seq,
      lat: lat,
      lng: lng,
      feeCents: 200,
      driverCents: 100,
      reachedAt: alcancada ? DateTime(2026, 9, 5, 12, 0) : null,
    );

void main() {
  group('a rota passa pelas paragens, por ordem de seq', () {
    test('duas paragens por alcançar entram as duas, na ordem pedida', () {
      // De propósito fora de ordem na lista: a ordem que manda é o `seq`,
      // porque é essa a ordem por que o cliente as pediu e paga.
      final stops = [_stop(2), _stop(1)];
      expect(stopsPendentes(stops).map((s) => s.seq).toList(), [1, 2]);
      expect(waypointsDasStops(stops).length, 2);
    });

    test('paragem alcançada SAI da rota — é o que faz a linha refazer-se', () {
      final stops = [_stop(1, alcancada: true), _stop(2)];
      expect(stopsPendentes(stops).map((s) => s.seq).toList(), [2],
          reason: 'a paragem já cumprida não pode continuar a desviar a rota');
      expect(waypointsDasStops(stops).length, 1);
    });

    test('todas alcançadas: a rota vai direita ao destino', () {
      final stops = [_stop(1, alcancada: true), _stop(2, alcancada: true)];
      expect(stopsPendentes(stops), isEmpty);
      expect(waypointsDasStops(stops), isEmpty);
    });

    test('sem paragens não há waypoints', () {
      expect(waypointsDasStops(const <TvdeRideStop>[]), isEmpty);
    });

    test('os waypoints saem nas coordenadas certas', () {
      final stops = [
        _stop(1, lat: 40.5400, lng: -7.2700),
        _stop(2, lat: 40.5500, lng: -7.2800),
      ];
      final w = waypointsDasStops(stops);
      expect(w[0].latitude, 40.5400);
      expect(w[0].longitude, -7.2700);
      expect(w[1].latitude, 40.5500);
    });
  });

  group('o tecto de paragens protege a chamada ao Directions', () {
    test('com mais paragens do que o máximo, ficam as primeiras por seq', () {
      final stops = [_stop(1), _stop(2), _stop(3), _stop(4)];
      expect(stopsPendentes(stops, maxStops: 2).map((s) => s.seq).toList(),
          [1, 2]);
      expect(stopsIgnoradas(stops, maxStops: 2).map((s) => s.seq).toList(),
          [3, 4],
          reason: 'o excedente tem de ser reportado, não desaparecer calado');
    });

    test('dentro do máximo não fica nada de fora', () {
      final stops = [_stop(1), _stop(2)];
      expect(stopsIgnoradas(stops, maxStops: 2), isEmpty);
    });

    test('o tecto conta só as por alcançar, não as já cumpridas', () {
      // Uma corrida com 2 paragens onde a primeira já foi feita ainda pode
      // aceitar a segunda — o tecto não deve gastar-se com histórico.
      final stops = [_stop(1, alcancada: true), _stop(2), _stop(3)];
      expect(stopsPendentes(stops, maxStops: 2).map((s) => s.seq).toList(),
          [2, 3]);
      expect(stopsIgnoradas(stops, maxStops: 2), isEmpty);
    });
  });

  group('o tempo de chegada soma o tempo parado que falta', () {
    test('duas paragens por fazer = 4 minutos parados (120 s cada)', () {
      final stops = [_stop(1), _stop(2)];
      expect(minutosParadoPendente(stops), 4.0);
    });

    test('a paragem já cumprida não conta — esse tempo já foi gasto', () {
      final stops = [_stop(1, alcancada: true), _stop(2)];
      expect(minutosParadoPendente(stops), 2.0);
    });

    test('sem paragens não soma nada', () {
      expect(minutosParadoPendente(const <TvdeRideStop>[]), 0.0);
    });

    test('o tempo de espera vem das definições, não está cravado', () {
      final stops = [_stop(1)];
      expect(minutosParadoPendente(stops, stopTimerSeconds: 300), 5.0);
      expect(minutosParadoPendente(stops, stopTimerSeconds: 0), 0.0);
    });

    test('um valor disparatado nas definições não produz tempo negativo', () {
      final stops = [_stop(1), _stop(2)];
      expect(minutosParadoPendente(stops, stopTimerSeconds: -60),
          greaterThanOrEqualTo(0));
    });
  });

  group('acrescentar uma paragem conta como fase nova', () {
    // Sem isto, o cliente acrescentava uma paragem e a linha do mapa só mudava
    // 15 segundos depois, por causa da trava `tvde_nav_reroute_min_seconds`.
    test('a chave muda quando entra uma paragem', () {
      final antes = chaveFaseComStops('r1', emViagem: true, stops: [_stop(1)]);
      final depois = chaveFaseComStops('r1',
          emViagem: true, stops: [_stop(1), _stop(2)]);
      expect(antes, isNot(depois));
    });

    test('a chave muda quando uma paragem é alcançada', () {
      final antes = chaveFaseComStops('r1',
          emViagem: true, stops: [_stop(1), _stop(2)]);
      final depois = chaveFaseComStops('r1',
          emViagem: true, stops: [_stop(1, alcancada: true), _stop(2)]);
      expect(antes, isNot(depois),
          reason: 'marcar chegada tem de refazer a rota para a seguinte');
    });

    test('a chave muda quando muda a fase da corrida', () {
      final recolha =
          chaveFaseComStops('r1', emViagem: false, stops: [_stop(1)]);
      final viagem =
          chaveFaseComStops('r1', emViagem: true, stops: [_stop(1)]);
      expect(recolha, isNot(viagem));
    });

    test('sem mudanças, a chave é a mesma — não pede rota à toa', () {
      final a = chaveFaseComStops('r1', emViagem: true, stops: [_stop(1)]);
      final b = chaveFaseComStops('r1', emViagem: true, stops: [_stop(1)]);
      expect(a, b);
    });

    test('corridas diferentes nunca partilham chave', () {
      expect(chaveFaseComStops('r1', emViagem: true, stops: const []),
          isNot(chaveFaseComStops('r2', emViagem: true, stops: const [])));
    });
  });
}
