import 'dart:math' as math;

import 'package:latlong2/latlong.dart';

/// [TVDE nav 05/09] Matemática de rota — PURA, sem Flutter, sem plugins, sem
/// rede. Serve o mapa do motorista (recálculo por desvio + rota que se apaga
/// atrás do carro) e é reutilizável pelo mapa do cliente.
///
/// Porquê ponto-a-SEGMENTO e não ponto-ao-ponto-mais-próximo: numa rua comprida
/// e direita, os pontos da polilinha podem estar a centenas de metros uns dos
/// outros. A distância ao vértice mais próximo dava um "desvio" enorme com o
/// carro EM CIMA da linha — falso positivo garantido. A distância perpendicular
/// ao segmento é a distância real à estrada desenhada.
///
/// Todas as funções deste ficheiro são determinísticas: mesma entrada, mesma
/// saída, sem relógio e sem estado global. Dá para testar sem mapa nem GPS.

/// Raio médio da Terra (IUGG), em metros.
const double _raioTerraM = 6371008.8;

/// Projeção plana local (equirretangular) de [p] em metros, relativa a [ref].
/// A escalas de rua (< alguns km) o erro é sub-métrico — mais do que suficiente
/// para decidir se o carro saiu da linha.
({double x, double y}) _paraPlanoLocal(LatLng p, LatLng ref) {
  const rad = math.pi / 180.0;
  final cosLat = math.cos(ref.latitude * rad);
  return (
    x: (p.longitude - ref.longitude) * rad * cosLat * _raioTerraM,
    y: (p.latitude - ref.latitude) * rad * _raioTerraM,
  );
}

/// Distância em metros entre dois pontos (mesma projeção local das restantes
/// funções — coerente com elas, e chega para distâncias de rua).
double distanciaEntrePontosMetros(LatLng a, LatLng b) {
  final p = _paraPlanoLocal(b, a);
  return math.sqrt(p.x * p.x + p.y * p.y);
}

/// Resultado interno: distância perpendicular ao segmento e a fração `t` do
/// pé da perpendicular dentro do segmento (0 = início, 1 = fim).
class _Pe {
  const _Pe(this.metros, this.t);
  final double metros;
  final double t;
}

_Pe _peNoSegmento(LatLng p, LatLng a, LatLng b) {
  // Origem do plano = o próprio ponto p, logo p = (0,0) e a distância ao
  // segmento é a distância da origem ao segmento [a,b].
  final pa = _paraPlanoLocal(a, p);
  final pb = _paraPlanoLocal(b, p);
  final dx = pb.x - pa.x;
  final dy = pb.y - pa.y;
  final comp2 = dx * dx + dy * dy;
  if (comp2 <= 0) {
    return _Pe(math.sqrt(pa.x * pa.x + pa.y * pa.y), 0.0);
  }
  var t = -(pa.x * dx + pa.y * dy) / comp2;
  if (t < 0) t = 0;
  if (t > 1) t = 1;
  final cx = pa.x + t * dx;
  final cy = pa.y + t * dy;
  return _Pe(math.sqrt(cx * cx + cy * cy), t);
}

/// Distância perpendicular, em metros, de [posicao] à polilinha [rota].
/// Rota vazia → `double.infinity` (sem linha não há desvio para medir; quem
/// chama trata esse caso à parte).
double distanciaARotaMetros(LatLng posicao, List<LatLng> rota) {
  if (rota.isEmpty) return double.infinity;
  if (rota.length == 1) {
    return distanciaEntrePontosMetros(posicao, rota.first);
  }
  var melhor = double.infinity;
  for (var i = 0; i < rota.length - 1; i++) {
    final d = _peNoSegmento(posicao, rota[i], rota[i + 1]).metros;
    if (d < melhor) melhor = d;
  }
  return melhor;
}

/// Onde o carro está em relação à rota, numa só passagem.
class ProgressoNaRota {
  const ProgressoNaRota({
    required this.aFrente,
    required this.indiceSegmento,
    required this.distanciaMetros,
  });

  /// Troço que falta percorrer — é isto que se desenha. Começa no pé da
  /// perpendicular (mesmo à frente do carro), pelo que a linha "apaga-se"
  /// atrás dele à medida que avança.
  final List<LatLng> aFrente;

  /// Índice do segmento em que o carro está.
  final int indiceSegmento;

  /// Distância perpendicular à rota, em metros.
  final double distanciaMetros;
}

/// Projeta [posicao] sobre [rota] e devolve o troço que falta + a distância à
/// linha. Uma única varredura O(n) — sem alocações por segmento, sem rede.
ProgressoNaRota projetarNaRota(List<LatLng> rota, LatLng posicao) {
  if (rota.length < 2) {
    return ProgressoNaRota(
      aFrente: List<LatLng>.unmodifiable(rota),
      indiceSegmento: 0,
      distanciaMetros: rota.isEmpty
          ? double.infinity
          : distanciaEntrePontosMetros(posicao, rota.first),
    );
  }
  var melhorIdx = 0;
  var melhorDist = double.infinity;
  var melhorT = 0.0;
  for (var i = 0; i < rota.length - 1; i++) {
    final pe = _peNoSegmento(posicao, rota[i], rota[i + 1]);
    if (pe.metros < melhorDist) {
      melhorDist = pe.metros;
      melhorIdx = i;
      melhorT = pe.t;
    }
  }
  final a = rota[melhorIdx];
  final b = rota[melhorIdx + 1];
  final pe = LatLng(
    a.latitude + (b.latitude - a.latitude) * melhorT,
    a.longitude + (b.longitude - a.longitude) * melhorT,
  );
  final aFrente = <LatLng>[pe, ...rota.sublist(melhorIdx + 1)];
  return ProgressoNaRota(
    aFrente: List<LatLng>.unmodifiable(aFrente),
    indiceSegmento: melhorIdx,
    distanciaMetros: melhorDist,
  );
}

/// Deteta que o motorista SAIU da rota — e dispara UMA vez só.
///
/// Regra (afinável em `platform_settings`, categoria `tvde`):
/// fora da linha mais de [metrosLimite] (`tvde_nav_offroute_meters`) durante
/// [leiturasSeguidas] leituras SEGUIDAS (`tvde_nav_offroute_fixes`).
/// Uma leitura em cima da linha zera o contador — GPS a saltar não conta.
///
/// Não tem relógio lá dentro de propósito: o intervalo mínimo entre recálculos
/// (`tvde_nav_reroute_min_seconds`) é do ecrã, para isto continuar testável.
class OffRouteDetector {
  OffRouteDetector({
    this.metrosLimite = 45.0,
    this.leiturasSeguidas = 3,
  });

  /// Limite de desvio em metros. Mutável — vem de `platform_settings`.
  double metrosLimite;

  /// Leituras seguidas fora da linha necessárias para disparar.
  int leiturasSeguidas;

  int _seguidas = 0;

  /// Quantas leituras seguidas fora da linha já se acumularam.
  int get leiturasForaSeguidas => _seguidas;

  /// Esquece o histórico (fase da corrida mudou, rota nova desenhada, etc.).
  void reset() => _seguidas = 0;

  /// Alimenta o detetor com a distância já calculada à rota.
  /// `true` EXATAMENTE na leitura que fecha a contagem — e o contador reinicia,
  /// para não disparar outra vez na leitura seguinte.
  bool adicionarDistancia(double metros) {
    if (!metros.isFinite || metros <= metrosLimite) {
      _seguidas = 0;
      return false;
    }
    _seguidas++;
    if (_seguidas >= leiturasSeguidas) {
      _seguidas = 0;
      return true;
    }
    return false;
  }

  /// Igual ao anterior, mas calcula a distância a partir da rota. Sem rota
  /// desenhada não há desvio a medir (quem chama pede rota por outra razão).
  bool adicionarLeitura(LatLng posicao, List<LatLng> rota) {
    if (rota.length < 2) {
      _seguidas = 0;
      return false;
    }
    return adicionarDistancia(distanciaARotaMetros(posicao, rota));
  }
}
