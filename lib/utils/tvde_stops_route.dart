/// [Paragens na rota · 05/09] Matemática das paragens adicionais do TVDE —
/// PURA: sem Flutter, sem rede, sem estado. Serve os DOIS mapas (motorista e
/// cliente) e o cálculo do tempo de chegada.
///
/// **A cicatriz:** o cliente paga `tvde_stop_fee_cents` (200 = 2 EUR) por cada
/// paragem e o motorista recebe `tvde_stop_driver_cents` (100), até
/// `tvde_max_stops` (2). Mas o ecrã de corrida carregava as paragens e nunca
/// as passava ao serviço de rotas — `fetchRoute` aceita `waypoints` desde
/// sempre e, em todo o `lib/`, só o mapa das ENTREGAS os passava. Resultado:
/// cobrava-se por uma paragem que o mapa ignorava, e o tempo de chegada
/// prometia um destino que não era possível.
///
/// Regra: só entram as paragens **ainda não alcançadas**. Assim que o
/// motorista marca chegada, a paragem sai dos waypoints e a rota refaz-se
/// para a seguinte — ou para o destino, se já não houver nenhuma.
library;

import 'package:latlong2/latlong.dart';

import '../models/tvde_ride.dart';

/// Paragens que ainda contam para a rota, por ordem de `seq`.
///
/// - descarta as já alcançadas (`reachedAt != null`);
/// - ordena por `seq` (a ordem por que o cliente as pediu e paga);
/// - respeita [maxStops]: se vierem mais do que o máximo (dados estranhos na
///   base, corrida antiga), fica com as primeiras e o excedente sai em
///   [stopsIgnoradas] em vez de rebentar a chamada ao Directions — a Google
///   também tem tecto de waypoints, e uma corrida sem rota é pior do que uma
///   rota com menos paragens.
List<TvdeRideStop> stopsPendentes(
  List<TvdeRideStop> stops, {
  int maxStops = 2,
}) {
  final porFazer = stops.where((s) => !s.reached).toList()
    ..sort((a, b) => a.seq.compareTo(b.seq));
  if (maxStops < 0) return const <TvdeRideStop>[];
  if (porFazer.length <= maxStops) return porFazer;
  return porFazer.sublist(0, maxStops);
}

/// As que ficaram DE FORA por excederem [maxStops] — para o relatório/log.
/// Nunca é silencioso: se isto vier não-vazio, há dados a mais na corrida.
List<TvdeRideStop> stopsIgnoradas(
  List<TvdeRideStop> stops, {
  int maxStops = 2,
}) {
  final porFazer = stops.where((s) => !s.reached).toList()
    ..sort((a, b) => a.seq.compareTo(b.seq));
  if (maxStops < 0) return porFazer;
  if (porFazer.length <= maxStops) return const <TvdeRideStop>[];
  return porFazer.sublist(maxStops);
}

/// Os pontos a passar ao `fetchRoute(waypoints: ...)`, já na ordem certa.
List<LatLng> waypointsDasStops(
  List<TvdeRideStop> stops, {
  int maxStops = 2,
}) =>
    stopsPendentes(stops, maxStops: maxStops)
        .map((s) => LatLng(s.lat, s.lng))
        .toList(growable: false);

/// Minutos parados que ainda faltam cumprir nas paragens por alcançar.
///
/// Cada paragem tem uma espera de cortesia de [stopTimerSeconds]
/// (`tvde_stop_timer_seconds`, 120 s por defeito). O tempo de chegada ao
/// destino TEM de somar isto: a rota da Google só conta a condução, e sem esta
/// parcela o cliente vê um destino que o carro não consegue cumprir.
///
/// Só conta as **não alcançadas** — quem já parou já gastou o tempo dele.
double minutosParadoPendente(
  List<TvdeRideStop> stops, {
  int stopTimerSeconds = 120,
  int maxStops = 2,
}) {
  if (stopTimerSeconds <= 0) return 0;
  final n = stopsPendentes(stops, maxStops: maxStops).length;
  return n * stopTimerSeconds / 60.0;
}

/// Chave de idempotência do pedido de rota: muda quando muda a fase OU quando
/// entra/sai uma paragem. É isto que faz uma paragem nova contar como "fase
/// nova" e furar a trava dos `tvde_nav_reroute_min_seconds` — sem isto, o
/// cliente acrescentava uma paragem e a linha só mudava 15 segundos depois.
String chaveFaseComStops(
  String rideId, {
  required bool emViagem,
  required List<TvdeRideStop> stops,
  int maxStops = 2,
}) {
  final ids = stopsPendentes(stops, maxStops: maxStops)
      .map((s) => '${s.seq}:${s.id}')
      .join(',');
  return '$rideId|${emViagem ? 'dest' : 'pickup'}|$ids';
}
