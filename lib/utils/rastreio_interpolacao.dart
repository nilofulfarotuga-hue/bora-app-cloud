/// [Rastreio em tempo real · 07/10/2026] O condutor EXACTO no mapa do cliente
/// — matemática PURA (sem Flutter, sem mapa, sem rede, sem relógio escondido).
///
/// **A cicatriz:** o carro do cliente animava 12 passos × 80 ms fixos entre
/// duas leituras que chegavam de 4-5 s em 4-5 s: deslizava 1 s e ficava 3 s
/// parado; uma leitura atrasada (resposta velha do servidor a chegar depois
/// de uma mais nova) fazia-o andar PARA TRÁS; e com o `heading` a zero
/// (telemóvel parado ou sem bússola) o carro apontava para norte a andar
/// para sul.
///
/// Aqui vive a regra toda, para ser a mesma no mapa da corrida TVDE, no
/// rastreio da entrega e no pontinho azul do cliente no mapa do condutor:
///  - uma amostra com `em` mais antigo do que a última aceite é IGNORADA —
///    o marcador nunca anda para trás no tempo;
///  - o rumo vem do `heading` do aparelho quando ele anda; com heading nulo ou
///    a zero e velocidade > 0 calcula-se o rumo entre os dois últimos pontos;
///    parado, mantém-se o rumo anterior (não gira à toa);
///  - a animação dura o intervalo REAL entre amostras (com chão e tecto), não
///    um número fixo;
///  - com rota desenhada, anda POR CIMA dela (`passosSobreRota`); sem rota,
///    linha recta — e nunca salta.
library;

import 'dart:math' as math;

import 'package:latlong2/latlong.dart';

import 'route_deviation.dart' show distanciaEntrePontosMetros;
import 'tvde_route_walk.dart';

/// Uma leitura de posição vinda do servidor (ou do GPS de outro telemóvel).
class AmostraPosicao {
  const AmostraPosicao({
    required this.ponto,
    required this.em,
    this.heading,
    this.velocidadeKmh,
  });

  final LatLng ponto;

  /// Hora da leitura (do SERVIDOR quando existe — é ela que ordena).
  final DateTime em;

  /// Rumo do aparelho em graus (0 = norte), se existir.
  final double? heading;

  final double? velocidadeKmh;
}

/// Normaliza um ângulo para [0, 360).
double normalizaRumo(double graus) => ((graus % 360) + 360) % 360;

/// Rumo (bearing) de [a] para [b], em graus, 0 = norte, 90 = este.
double rumoEntre(LatLng a, LatLng b) {
  const rad = math.pi / 180.0;
  final lat1 = a.latitude * rad;
  final lat2 = b.latitude * rad;
  final dLng = (b.longitude - a.longitude) * rad;
  final y = math.sin(dLng) * math.cos(lat2);
  final x = math.cos(lat1) * math.sin(lat2) -
      math.sin(lat1) * math.cos(lat2) * math.cos(dLng);
  return normalizaRumo(math.atan2(y, x) / rad);
}

/// Suaviza a rotação (novo×[peso] + antigo×(1-[peso])) pelo caminho mais curto
/// do círculo — passar de 359° para 1° não dá uma pirueta.
double suavizaRumo(double? anterior, double novo, {double peso = 0.3}) {
  final n = normalizaRumo(novo);
  if (anterior == null) return n;
  var delta = (n - anterior) % 360;
  if (delta > 180) delta -= 360;
  if (delta < -180) delta += 360;
  return normalizaRumo(anterior + delta * peso);
}

/// Velocidade abaixo da qual o aparelho conta como PARADO (ruído de GPS).
const double kVelocidadeParadoKmh = 1.5;

/// Para onde o marcador deve apontar com esta amostra. `null` = mantém o que
/// tinha (não há informação nova de confiança).
///
/// Regra: `heading` do aparelho manda quando existe, é diferente de zero e o
/// aparelho anda. Heading nulo/zero com velocidade > 0 (ou desconhecida) →
/// rumo entre a amostra anterior e esta, desde que se tenha andado pelo
/// menos [minimoMetros] (senão é ruído a rodar o carro no sítio).
double? rumoDaAmostra({
  required AmostraPosicao? anterior,
  required AmostraPosicao nova,
  double minimoMetros = 3,
}) {
  final v = nova.velocidadeKmh;
  final aMexer = v == null || v > kVelocidadeParadoKmh;
  final h = nova.heading;
  if (h != null && h.isFinite && h != 0 && aMexer) return normalizaRumo(h);
  if (anterior == null) return null;
  if (v != null && v <= kVelocidadeParadoKmh) return null;
  final d = distanciaEntrePontosMetros(anterior.ponto, nova.ponto);
  if (d < minimoMetros) return null;
  return rumoEntre(anterior.ponto, nova.ponto);
}

/// O que o ecrã tem de desenhar para uma amostra aceite.
class PlanoDeAnimacao {
  const PlanoDeAnimacao({
    required this.pontos,
    required this.duracao,
    required this.rumo,
    required this.sobreRota,
    required this.rumoPorPasso,
  });

  /// Fotogramas, do primeiro passo até à posição final (o último É a amostra,
  /// ou o pé dela na rota). Nunca vazio.
  final List<LatLng> pontos;

  /// Quanto tempo a animação inteira deve demorar. `Duration.zero` = assenta
  /// já (primeira posição, parado, ou sinal velho).
  final Duration duracao;

  /// Rumo (suavizado) a aplicar ao marcador. `null` = ainda não se sabe.
  final double? rumo;

  /// `true` quando os pontos seguem a polilinha da rota.
  final bool sobreRota;

  /// Rumo a usar em CADA passo — só difere de [rumo] a andar sobre a rota sem
  /// heading do aparelho: aí o carro aponta para onde a estrada vai, e é isso
  /// que o faz dobrar a esquina em vez de derrapar de lado.
  final List<double?> rumoPorPasso;

  /// Assentar sem animar.
  bool get imediato => duracao == Duration.zero || pontos.length == 1;
}

/// Guarda a última amostra aceite e a posição mostrada, e transforma cada
/// amostra nova num [PlanoDeAnimacao]. Um por marcador.
class InterpoladorDePosicao {
  InterpoladorDePosicao({
    this.chaoMs = 240,
    this.tetoMs = 8000,
    this.passosBase = 12,
    this.msPorPasso = 80,
    this.passosMax = 120,
    this.toleranciaRotaMetros = 60,
    this.saltoParadoMetros = 15,
  });

  /// Chão e tecto da duração de uma animação, em ms. O tecto protege de uma
  /// amostra que chegue depois de um buraco grande (60 s sem rede não podem
  /// virar 60 s de carro a deslizar).
  final int chaoMs;
  final int tetoMs;
  final int passosBase;
  final double msPorPasso;
  final int passosMax;
  final double toleranciaRotaMetros;

  /// Parado (velocidade ~0) com um salto menor do que isto = ruído: assenta.
  final double saltoParadoMetros;

  AmostraPosicao? _ultima;
  LatLng? _mostrada;
  double? _rumo;

  /// A última amostra ACEITE (a mais recente no tempo).
  AmostraPosicao? get ultimaAmostra => _ultima;

  /// Onde o marcador está desenhado neste momento.
  LatLng? get posicaoMostrada => _mostrada;

  /// Rumo actual (suavizado).
  double? get rumo => _rumo;

  /// O ecrã avisa onde pôs o marcador em cada fotograma, para a animação
  /// seguinte partir dali (sem salto) se a amostra nova chegar a meio.
  void mostrar(LatLng p) => _mostrada = p;

  /// Esquece tudo (nova corrida, outro condutor).
  void limpar() {
    _ultima = null;
    _mostrada = null;
    _rumo = null;
  }

  /// Aceita (ou ignora) uma amostra.
  ///
  /// - `null` = IGNORADA: é mais antiga do que a última aceite. Nada muda.
  /// - [rota]: polilinha desenhada (vazia = linha recta).
  /// - [intervaloEsperadoMs]: cadência com que as amostras costumam chegar;
  ///   serve de duração quando ainda não há duas amostras para medir.
  /// - [animar] = false (sinal velho, por exemplo): assenta sem deslizar.
  PlanoDeAnimacao? aceitar(
    AmostraPosicao nova, {
    List<LatLng> rota = const [],
    int? intervaloEsperadoMs,
    bool animar = true,
  }) {
    final anterior = _ultima;
    // Mais antiga = ignorada (nunca anda para trás). IGUAL também: é a mesma
    // leitura a chegar por duas portas (Realtime e poll de reserva) — aceitá-la
    // assentava o carro no fim a meio da animação, um salto por cada poll.
    if (anterior != null && !nova.em.isAfter(anterior.em)) return null;

    final rumoNovo = rumoDaAmostra(anterior: anterior, nova: nova);
    if (rumoNovo != null) _rumo = suavizaRumo(_rumo, rumoNovo);

    final de = _mostrada;
    _ultima = nova;

    PlanoDeAnimacao assenta() {
      _mostrada = nova.ponto;
      return PlanoDeAnimacao(
        pontos: [nova.ponto],
        duracao: Duration.zero,
        rumo: _rumo,
        sobreRota: false,
        rumoPorPasso: [_rumo],
      );
    }

    if (de == null || !animar) return assenta();

    final recta = distanciaEntrePontosMetros(de, nova.ponto);
    if (recta < 0.5) return assenta();
    final v = nova.velocidadeKmh;
    if (v != null && v <= kVelocidadeParadoKmh && recta < saltoParadoMetros) {
      return assenta();
    }

    // Duração = intervalo REAL entre as duas amostras, com chão e tecto.
    var totalMs = anterior != null
        ? nova.em.difference(anterior.em).inMilliseconds
        : (intervaloEsperadoMs ?? tetoMs);
    if (totalMs <= 0) totalMs = intervaloEsperadoMs ?? chaoMs;
    final teto = intervaloEsperadoMs != null
        ? math.min(tetoMs, math.max(chaoMs, intervaloEsperadoMs * 2))
        : tetoMs;
    totalMs = totalMs.clamp(chaoMs, teto);
    final passos = (totalMs / msPorPasso).round().clamp(passosBase, passosMax);

    final sobreRota = rota.length >= 2
        ? passosSobreRota(rota, de, nova.ponto,
            passos: passos, toleranciaMetros: toleranciaRotaMetros)
        : null;

    final List<LatLng> pontos;
    if (sobreRota != null) {
      pontos = sobreRota.pontos;
    } else {
      pontos = List<LatLng>.generate(passos, (i) {
        final f = (i + 1) / passos;
        return LatLng(
          de.latitude + (nova.ponto.latitude - de.latitude) * f,
          de.longitude + (nova.ponto.longitude - de.longitude) * f,
        );
      });
    }

    // Rumo por passo: a andar sobre a rota SEM heading do aparelho, o carro
    // aponta para onde a estrada vai.
    final headingDoAparelho = nova.heading != null &&
        nova.heading!.isFinite &&
        nova.heading != 0 &&
        (v == null || v > kVelocidadeParadoKmh);
    final rumos = List<double?>.filled(pontos.length, _rumo);
    if (sobreRota != null && !headingDoAparelho) {
      var ant = de;
      var r = _rumo;
      for (var i = 0; i < pontos.length; i++) {
        final p = pontos[i];
        if (distanciaEntrePontosMetros(ant, p) >= 2) {
          r = suavizaRumo(r, rumoEntre(ant, p), peso: 0.5);
        }
        rumos[i] = r;
        ant = p;
      }
      _rumo = r;
    }

    _mostrada = pontos.last;
    return PlanoDeAnimacao(
      pontos: pontos,
      duracao: Duration(milliseconds: totalMs),
      rumo: _rumo,
      sobreRota: sobreRota != null,
      rumoPorPasso: rumos,
    );
  }
}
