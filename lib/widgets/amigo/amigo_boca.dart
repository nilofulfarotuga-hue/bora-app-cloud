// O AMIGO — a boca a acompanhar a voz (missão m11-amigo-rosto, 09/11/2026).
//
// Porta para Dart da "boca sincronizada" do protótipo do Dipsy (amigo.js):
// cada palavra vira uma lista de formas de boca (visemas) a partir das letras
// portuguesas, com regras do português de Portugal ("ão" longo, "e" final
// quase mudo). Cada palavra tem um tempo; a duração divide-se pelas formas; a
// boca prepara a forma seguinte perto do fim de cada uma (coarticulação) e
// antecipa 35 ms, como os animadores fazem.
//
// Na app a voz é a do telemóvel/navegador. Os tempos de cada palavra são
// ESTIMADOS a partir do texto e ACERTADOS em cada evento de palavra do motor
// de voz (Android onRangeStart, iPhone willSpeakRange, web onboundary): o
// relógio da boca salta para o início da palavra que o motor diz estar a
// dizer, e a velocidade ajusta-se à velocidade real da voz. Sem eventos (ou
// sem som), a boca segue a estimativa — mexe-se ao ritmo da legenda.

import 'dart:math' as math;

/// Uma forma de boca: abertura (o), largura (w) e arredondado (r).
class AmigoBocaForma {
  const AmigoBocaForma(this.o, this.w, this.r, {this.vol = 0});
  final double o;
  final double w;
  final double r;

  /// Força da voz neste instante (0..1), para os gestos da cabeça.
  final double vol;

  @override
  String toString() => 'Boca(o=${o.toStringAsFixed(2)}, w=${w.toStringAsFixed(2)}, '
      'r=${r.toStringAsFixed(2)})';
}

/// Os visemas (formas de boca por som).
const Map<String, AmigoBocaForma> kAmigoVisemas = {
  'A': AmigoBocaForma(1, 1.05, 0),
  'E': AmigoBocaForma(.62, 1.12, 0),
  'I': AmigoBocaForma(.36, 1.18, 0),
  'O': AmigoBocaForma(.74, .62, .9),
  'U': AmigoBocaForma(.38, .46, 1),
  'M': AmigoBocaForma(0, .92, 0), // m, b, p — boca fechada
  'F': AmigoBocaForma(.14, 1, 0), // f, v
  'L': AmigoBocaForma(.34, .98, 0), // l, n, d, t
  'S': AmigoBocaForma(.2, 1.1, 0), // s, z, j, x, ç, ch
  'C': AmigoBocaForma(.3, .9, .1), // outras consoantes
  'R': AmigoBocaForma(.4, .85, .25),
  'X': AmigoBocaForma(0, 1, 0), // repouso
};

const Map<String, String> _vogal = {
  'a': 'A', 'á': 'A', 'à': 'A', 'â': 'A', 'ã': 'A', //
  'e': 'E', 'é': 'E', 'ê': 'E',
  'i': 'I', 'í': 'I', 'y': 'I',
  'o': 'O', 'ó': 'O', 'ô': 'O', 'õ': 'O',
  'u': 'U', 'ú': 'U', 'ü': 'U',
};

const Map<String, String> _numero = {
  '0': 'zero', '1': 'um', '2': 'dois', '3': 'três', '4': 'quatro', //
  '5': 'cinco', '6': 'seis', '7': 'sete', '8': 'oito', '9': 'nove',
};

final RegExp _naoLetra = RegExp(r'[^a-zà-ÿç]');

/// As formas de boca de uma palavra, com o peso de cada uma (igual ao
/// protótipo do Dipsy, testado em amigo_boca_test.dart).
List<(String, double)> amigoFonemas(String palavra) {
  final s = palavra
      .toLowerCase()
      .split('')
      .map((c) => _numero[c] ?? c)
      .join()
      .replaceAll(_naoLetra, '');
  final out = <(String, double)>[];
  for (var i = 0; i < s.length; i++) {
    final c = s[i];
    final n = i + 1 < s.length ? s[i + 1] : '';
    final n2 = i + 2 < s.length ? s[i + 2] : '';
    if ((c == 'ã' || c == 'õ') && n == 'o') {
      out.add(('O', 1.8)); // ão
      i++;
      continue;
    }
    if ((c == 'ã' || c == 'õ') && n == 'e') {
      out
        ..add((_vogal[c]!, 1.2))
        ..add(('E', .8));
      i++;
      continue;
    }
    final v = _vogal[c];
    if (v != null) {
      // "e" final átono em PT-PT quase não se ouve.
      final fraco = c == 'e' && i == s.length - 1 && s.length > 2;
      out.add(fraco ? ('C', .5) : (v, 1.5));
      continue;
    }
    final dig = '$c$n';
    if (dig == 'ch' || dig == 'lh' || dig == 'nh') {
      out.add((dig == 'ch' ? 'S' : 'L', 1));
      i++;
      continue;
    }
    if (dig == 'rr' || dig == 'ss') {
      out.add((dig == 'rr' ? 'R' : 'S', 1));
      i++;
      continue;
    }
    if ((dig == 'qu' || dig == 'gu') && 'eiéêí'.contains(n2) && n2.isNotEmpty) {
      out.add(('C', 1));
      i++;
      continue;
    }
    if (c == 'h') continue;
    if ('mbp'.contains(c)) {
      out.add(('M', 1));
    } else if ('fv'.contains(c)) {
      out.add(('F', 1));
    } else if ('szjxç'.contains(c) ||
        (c == 'c' && n.isNotEmpty && 'eiéêí'.contains(n))) {
      out.add(('S', 1));
    } else if (c == 'r') {
      out.add(('R', .8));
    } else if ('lndt'.contains(c)) {
      out.add(('L', .9));
    } else {
      out.add(('C', .9));
    }
  }
  return out;
}

/// Uma palavra do texto falado, com a posição no texto e o tempo estimado.
class AmigoPalavra {
  AmigoPalavra(this.inicio, this.fim, this.texto);

  /// Posição (em letras) no texto falado — é isto que o motor de voz diz.
  final int inicio;
  final int fim;
  final String texto;

  /// Início e duração estimados (ms desde o início da fala).
  double t = 0;
  double d = 0;
}

class _Chave {
  _Chave(this.t0, this.t1, this.v);
  final double t0;
  final double t1;
  final String v;
}

/// Duração base de cada som (ms) à velocidade 1 — o português de Portugal
/// das vozes do sistema anda perto de 13 sons por segundo.
const double kAmigoMsPorSom = 74;

/// Pausa depois de uma palavra, pela pontuação que a segue.
double _pausaDepois(String palavra) {
  if (palavra.endsWith('…')) return 380;
  final u = palavra.isEmpty ? '' : palavra[palavra.length - 1];
  if ('.!?'.contains(u)) return 320;
  if (';:'.contains(u)) return 200;
  if (u == ',') return 140;
  return 0;
}

final RegExp _palavraRe = RegExp(r'\S+');

/// A fala de UMA frase: os tempos estimados das palavras, as chaves de boca
/// e o relógio que os eventos do motor de voz vão acertando.
class AmigoFala {
  AmigoFala(this.texto, {double velocidade = 1})
      : velocidade = velocidade.clamp(0.4, 2.5).toDouble() {
    _montar();
  }

  final String texto;
  final double velocidade;
  final List<AmigoPalavra> palavras = [];
  final List<_Chave> _chaves = [];
  int _i = 0;

  // Relógio: posição = âncora + (agora − âncoraAgora) × escala.
  double _ancoraPos = 0;
  double? _ancoraAgora;
  double _escala = 1;
  int _ultimaPalavraEvento = -1;
  double _ultimoEventoAgora = 0;

  /// Atrasos medidos (ms) entre o evento de palavra e a estimativa — o
  /// painel e os testes usam isto para saber se a boca vai certa.
  final List<double> desvios = [];

  /// Duração estimada total (ms).
  double get duracaoEstimada => palavras.isEmpty
      ? 0
      : palavras.last.t + palavras.last.d + _pausaDepois(palavras.last.texto);

  void _montar() {
    var t = 120.0; // as vozes do sistema demoram um instante a soar
    for (final m in _palavraRe.allMatches(texto)) {
      final p = AmigoPalavra(m.start, m.end, m.group(0)!);
      final f = amigoFonemas(p.texto);
      final peso = f.fold<double>(0, (s, x) => s + x.$2);
      p.t = t;
      p.d = math.max(110, peso * kAmigoMsPorSom) / velocidade;
      palavras.add(p);
      t = p.t + p.d + _pausaDepois(p.texto) / velocidade;
    }
    _recalcularChaves();
  }

  void _recalcularChaves() {
    _chaves.clear();
    var fim = 0.0;
    for (final p in palavras) {
      if (p.t - fim > 70) _chaves.add(_Chave(fim, p.t, 'X'));
      final f = amigoFonemas(p.texto);
      final tot = f.fold<double>(0, (s, x) => s + x.$2);
      var t = p.t;
      if (f.isEmpty || tot <= 0) {
        _chaves.add(_Chave(p.t, p.t + p.d, 'X'));
      } else {
        for (final (v, peso) in f) {
          final d = p.d * peso / tot;
          _chaves.add(_Chave(t, t + d, v));
          t += d;
        }
      }
      fim = p.t + p.d;
    }
    _chaves.add(_Chave(fim, fim + 600000, 'X'));
    _i = 0;
  }

  /// A voz começou agora (ms de um relógio qualquer, sempre o mesmo).
  void comecou(double agoraMs) {
    _ancoraAgora = agoraMs;
    _ancoraPos = palavras.isEmpty ? 0 : math.max(0, palavras.first.t - 60);
  }

  bool get comecada => _ancoraAgora != null;

  /// A duração real do áudio é conhecida (voz do servidor, sem eventos de
  /// palavra): a boca estica ou encolhe a estimativa para acabar com o som.
  void ajustarDuracao(double duracaoRealMs) {
    final est = duracaoEstimada;
    if (duracaoRealMs < 200 || est <= 0) return;
    _escala = (est / duracaoRealMs).clamp(0.4, 2.5).toDouble();
  }

  /// Posição na fala (ms do texto estimado) no instante [agoraMs].
  double posicao(double agoraMs) {
    final a = _ancoraAgora;
    if (a == null) return 0;
    return _ancoraPos + (agoraMs - a) * _escala;
  }

  /// Índice da palavra que começa na letra [inicioLetra] (ou a anterior).
  int palavraDaLetra(int inicioLetra) {
    var idx = -1;
    for (var i = 0; i < palavras.length; i++) {
      if (palavras[i].inicio <= inicioLetra) {
        idx = i;
      } else {
        break;
      }
    }
    return idx;
  }

  /// Evento do motor de voz: começou a palavra que está na letra
  /// [inicioLetra]. Acerta o relógio e a velocidade.
  void palavraComecou(int inicioLetra, double agoraMs) {
    final i = palavraDaLetra(inicioLetra);
    if (i < 0) return;
    if (_ancoraAgora == null) comecou(agoraMs);
    final estimada = posicao(agoraMs);
    desvios.add(estimada - palavras[i].t);
    if (_ultimaPalavraEvento >= 0 && i > _ultimaPalavraEvento) {
      final real = agoraMs - _ultimoEventoAgora;
      final est = palavras[i].t - palavras[_ultimaPalavraEvento].t;
      if (real > 40 && est > 40) {
        final nova = (est / real).clamp(0.5, 2.0);
        _escala = _escala * 0.5 + nova * 0.5;
      }
    }
    _ultimaPalavraEvento = i;
    _ultimoEventoAgora = agoraMs;
    _ancoraPos = palavras[i].t;
    _ancoraAgora = agoraMs;
  }

  /// A palavra a ser dita agora (para a legenda), ou -1 antes de começar.
  int palavraEm(double agoraMs) {
    if (_ancoraAgora == null) return -1;
    final pos = posicao(agoraMs);
    var idx = -1;
    for (var i = 0; i < palavras.length; i++) {
      if (palavras[i].t <= pos + 30) idx = i;
    }
    return idx;
  }

  /// A forma da boca no instante [agoraMs] (com antecipação de 35 ms).
  AmigoBocaForma formaEm(double agoraMs, {double antecipa = 35}) {
    if (_ancoraAgora == null || _chaves.isEmpty) return kAmigoVisemas['X']!;
    final tt = posicao(agoraMs) + antecipa;
    var i = _i;
    if (i >= _chaves.length || _chaves[i].t0 > tt) i = 0;
    while (i < _chaves.length - 1 && _chaves[i].t1 <= tt) {
      i++;
    }
    _i = i;
    final c = _chaves[i];
    final prox = i + 1 < _chaves.length ? _chaves[i + 1] : c;
    final fr = ((tt - c.t0) / math.max(1, c.t1 - c.t0)).clamp(0.0, 1.0);
    final a = kAmigoVisemas[c.v]!;
    final b = kAmigoVisemas[prox.v]!;
    final k = fr > .6 ? (fr - .6) / .4 * .45 : 0.0; // coarticulação
    double mix(double x, double y) => x + (y - x) * k;
    return AmigoBocaForma(mix(a.o, b.o), mix(a.w, b.w), mix(a.r, b.r),
        vol: c.v == 'X' ? 0 : .6);
  }
}
