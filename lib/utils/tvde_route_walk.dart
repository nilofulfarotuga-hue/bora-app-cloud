/// [TVDE 2A · 05/09] Andar POR CIMA da rota — matemática PURA (sem Flutter,
/// sem mapa, sem rede, sem relógio).
///
/// **A cicatriz:** o carro do cliente era interpolado em LINHA RECTA entre duas
/// leituras de GPS. Como as leituras chegam de 50 em 50 metros, o carro cortava
/// esquinas e atravessava quarteirões — via-se o carro a passar por dentro dos
/// prédios enquanto a linha da rota passava pela rua ao lado.
///
/// Aqui projecta-se a leitura anterior e a nova sobre a polilinha que já está
/// desenhada (a mesma que o cliente vê) e devolvem-se os pontos intermédios
/// **em cima da linha**, espaçados por comprimento de arco. O carro passa a
/// dobrar as esquinas onde a estrada dobra.
///
/// Recusa-se a inventar quando não tem a certeza — devolve `null` e quem chama
/// volta ao movimento em linha recta (que continua a ser o recurso honesto):
/// - sem rota desenhada (ainda a carregar, ou o Directions falhou);
/// - carro longe da linha (fora de rota, ou a rota é de outra fase);
/// - carro a andar para TRÁS na linha (rota velha) — arrastá-lo ao contrário
///   seria pior do que o salto que se está a tentar corrigir.
library;

import 'package:latlong2/latlong.dart';
import 'route_deviation.dart';

/// Os pontos por onde o carro passa, já em cima da rota.
class PassosNaRota {
  const PassosNaRota({required this.pontos, required this.metros});

  /// Posições intermédias, do primeiro passo até ao destino projectado
  /// (o último ponto É o pé da perpendicular da leitura nova). Nunca vazio.
  final List<LatLng> pontos;

  /// Comprimento REAL percorrido ao longo da linha, em metros. É maior do que
  /// a distância a direito — e é esta que serve para acertar o ritmo da
  /// animação com a velocidade a que o carro anda de verdade.
  final double metros;
}

/// Pontos de animação de [de] até [para] **seguindo** [rota].
///
/// - [passos]: quantas posições intermédias devolver (o ecrã usa-as como
///   fotogramas). Menos de 1 → `null`.
/// - [toleranciaMetros]: a que distância da linha ainda se considera que o
///   carro está "em cima" dela. Acima disto não há caminho fiável para seguir.
///
/// `null` = **usa a linha recta**. É um resultado legítimo, não um erro.
PassosNaRota? passosSobreRota(
  List<LatLng> rota,
  LatLng de,
  LatLng para, {
  int passos = 12,
  double toleranciaMetros = 60,
}) {
  if (passos < 1 || rota.length < 2) return null;

  final a = projetarNaRota(rota, de);
  final b = projetarNaRota(rota, para);
  if (!a.distanciaMetros.isFinite || a.distanciaMetros > toleranciaMetros) {
    return null;
  }
  if (!b.distanciaMetros.isFinite || b.distanciaMetros > toleranciaMetros) {
    return null;
  }
  if (a.aFrente.isEmpty || b.aFrente.isEmpty) return null;

  final peA = a.aFrente.first;
  final peB = b.aFrente.first;

  // Para trás na linha → não há caminho para a frente que faça sentido.
  if (b.indiceSegmento < a.indiceSegmento) return null;
  if (b.indiceSegmento == a.indiceSegmento) {
    final inicio = rota[a.indiceSegmento];
    if (distanciaEntrePontosMetros(inicio, peB) <
        distanciaEntrePontosMetros(inicio, peA)) {
      return null;
    }
  }

  // Caminho = pé de partida + vértices pelo meio + pé de chegada.
  final caminho = <LatLng>[
    peA,
    ...rota.sublist(a.indiceSegmento + 1, b.indiceSegmento + 1),
    peB,
  ];

  // Comprimentos acumulados, para amostrar por arco (e não por índice: os
  // vértices da polilinha não estão igualmente espaçados).
  final acumulado = <double>[0];
  var total = 0.0;
  for (var i = 0; i < caminho.length - 1; i++) {
    total += distanciaEntrePontosMetros(caminho[i], caminho[i + 1]);
    acumulado.add(total);
  }
  if (total <= 0) return null; // parado: quem chama fixa a posição, sem animar

  final pontos = <LatLng>[];
  var seg = 0;
  for (var k = 1; k <= passos; k++) {
    final alvo = total * k / passos;
    while (seg < acumulado.length - 2 && acumulado[seg + 1] < alvo) {
      seg++;
    }
    final d0 = acumulado[seg];
    final d1 = acumulado[seg + 1];
    final t = d1 > d0 ? (alvo - d0) / (d1 - d0) : 1.0;
    final p0 = caminho[seg];
    final p1 = caminho[seg + 1];
    pontos.add(LatLng(
      p0.latitude + (p1.latitude - p0.latitude) * t,
      p0.longitude + (p1.longitude - p0.longitude) * t,
    ));
  }
  // O último passo é exactamente a leitura projectada — sem deriva acumulada.
  pontos[pontos.length - 1] = peB;

  return PassosNaRota(pontos: List<LatLng>.unmodifiable(pontos), metros: total);
}
