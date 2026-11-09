// O AMIGO — tocador da voz do servidor no navegador (pendências 09/11/2026, bloco I).
//
// Um só elemento <audio> para todas as falas. O Safari do iPhone só deixa tocar um
// elemento que já tocou dentro de um toque da pessoa: no primeiro toque/clique/tecla
// em qualquer sítio da página, esse mesmo elemento toca 0,1 s de silêncio (com som,
// porque tocar mudo não conta) e fica desbloqueado; as falas seguintes já saem.
// Se uma fala for recusada antes disso, o ecrã mostra "Toca para ouvir" (como a voz
// do aparelho) e o toque seguinte desbloqueia e repete a frase.
// (Mesma técnica do amigo_voz_desbloqueio_web.dart, que desbloqueia o speechSynthesis.)
import 'dart:async';
import 'dart:convert';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';
import 'dart:typed_data';

import 'amigo_tocador.dart';

AmigoTocador criarAmigoTocadorPlataforma() => _TocadorWeb();

JSObject? _elemento;
int _geracao = 0;
bool _aTocar = false;
bool _desbloqueado = false;
bool _ouvinteInstalado = false;
const _eventos = ['touchend', 'pointerup', 'click', 'keydown'];

/// 0,1 s de silêncio em WAV (8 kHz, 8 bits, mono).
String _silencio() {
  const n = 800;
  final b = ByteData(44 + n);
  void txt(int o, String s) {
    for (var i = 0; i < 4; i++) {
      b.setUint8(o + i, s.codeUnitAt(i));
    }
  }

  txt(0, 'RIFF');
  b.setUint32(4, 36 + n, Endian.little);
  txt(8, 'WAVE');
  txt(12, 'fmt ');
  b.setUint32(16, 16, Endian.little);
  b.setUint16(20, 1, Endian.little); // PCM
  b.setUint16(22, 1, Endian.little); // mono
  b.setUint32(24, 8000, Endian.little);
  b.setUint32(28, 8000, Endian.little);
  b.setUint16(32, 1, Endian.little);
  b.setUint16(34, 8, Endian.little);
  txt(36, 'data');
  b.setUint32(40, n, Endian.little);
  for (var i = 0; i < n; i++) {
    b.setUint8(44 + i, 128);
  }
  return 'data:audio/wav;base64,${base64Encode(b.buffer.asUint8List())}';
}

JSObject? _audio() {
  final ja = _elemento;
  if (ja != null) return ja;
  try {
    if (!globalContext.has('Audio')) return null;
    final criar = globalContext['Audio'] as JSFunction;
    final a = criar.callAsConstructor<JSObject>();
    a['preload'] = 'auto'.toJS;
    a['playsInline'] = true.toJS;
    _elemento = a;
    globalContext['__amigoAudio'] = a; // as provas (Playwright) leem daqui
    _instalarDesbloqueio(a);
    return a;
  } catch (_) {
    return null;
  }
}

void _limpar(JSObject a) {
  a['onplaying'] = null;
  a['onended'] = null;
  a['onerror'] = null;
}

void _instalarDesbloqueio(JSObject a) {
  if (_ouvinteInstalado) return;
  _ouvinteInstalado = true;
  try {
    final doc = globalContext['document'] as JSObject?;
    if (doc == null) return;
    late final JSFunction ouvinte;
    void tirar() {
      for (final t in _eventos) {
        doc.callMethod('removeEventListener'.toJS, t.toJS, ouvinte, true.toJS);
      }
    }

    ouvinte = ((JSAny? _) {
      if (_desbloqueado || _aTocar) {
        _desbloqueado = true;
        tirar();
        return;
      }
      try {
        // corre DENTRO do gesto: é isto que o Safari exige
        _geracao++;
        _limpar(a);
        a['src'] = _silencio().toJS;
        final p = a.callMethod<JSObject?>('play'.toJS);
        // o Safari desbloqueia o elemento no play() chamado DENTRO do gesto (mesmo que a
        // fala do Amigo o interrompa a seguir): as provas leem este contador
        globalContext['__amigoAudioToques'] =
            (((globalContext['__amigoAudioToques'] as JSNumber?)?.toDartInt ?? 0) + 1).toJS;
        unawaited(_esperar(p).then((erro) {
          // erro = este evento não contou como gesto (ex.: pointerup): tenta no seguinte
          if (erro != null) return;
          _desbloqueado = true;
          globalContext['__amigoAudioDesbloqueado'] = true.toJS;
          tirar();
        }));
      } catch (_) {}
    }).toJS;
    for (final t in _eventos) {
      doc.callMethod('addEventListener'.toJS, t.toJS, ouvinte, true.toJS);
    }
  } catch (_) {
    // sem isto só a 1.ª fala pode precisar de um toque
  }
}

/// Espera pela promessa do play(): null = está a tocar; texto = nome do erro
/// (ex.: "NotAllowedError" quando o Safari ainda quer um toque).
Future<String?> _esperar(JSObject? p) {
  if (p == null) return Future.value(null); // navegadores antigos: play() sem promessa
  final c = Completer<String?>();
  try {
    p.callMethod(
      'then'.toJS,
      ((JSAny? _) {
        if (!c.isCompleted) c.complete(null);
      }).toJS,
      ((JSAny? erro) {
        var nome = 'erro';
        try {
          final n = (erro as JSObject?)?['name'];
          if (n != null) nome = (n as JSString).toDart;
        } catch (_) {}
        if (!c.isCompleted) c.complete(nome);
      }).toJS,
    );
  } catch (_) {
    return Future.value(null);
  }
  return c.future;
}

class _TocadorWeb extends AmigoTocador {
  _TocadorWeb() {
    _audio(); // cria já o elemento e o ouvinte do 1.º toque
  }

  @override
  Future<void> tocar(
    AmigoAudio audio, {
    required void Function(double? duracaoMs) aoComecar,
    required void Function() aoAcabar,
    required void Function(String motivo) aoErro,
  }) async {
    final a = _audio();
    if (a == null) {
      aoErro('sem-audio');
      return;
    }
    final g = ++_geracao;
    var avisado = false;
    // o play() recusado e o evento "error" do elemento chegam os dois: avisa uma vez
    void erroUmaVez(String m) {
      if (avisado || g != _geracao) return;
      avisado = true;
      _aTocar = false;
      aoErro(m);
    }

    _limpar(a);
    a['onplaying'] = ((JSAny? _) {
      if (g != _geracao) return;
      _aTocar = true;
      final s = (a['duration'] as JSNumber?)?.toDartDouble ?? double.nan;
      aoComecar(s.isFinite && s > 0 ? s * 1000 : null);
    }).toJS;
    a['onended'] = ((JSAny? _) {
      if (g != _geracao) return;
      _aTocar = false;
      aoAcabar();
    }).toJS;
    a['onerror'] = ((JSAny? _) => erroUmaVez('erro-audio')).toJS;
    a['src'] = 'data:${audio.mime};base64,${audio.base64}'.toJS;
    String? erro;
    try {
      erro = await _esperar(a.callMethod<JSObject?>('play'.toJS));
    } catch (e) {
      erro = '$e';
    }
    if (g != _geracao) return;
    if (erro == null) {
      _desbloqueado = true;
      globalContext['__amigoAudioDesbloqueado'] = true.toJS;
      return;
    }
    erroUmaVez(erro.contains('NotAllowed') ? 'not-allowed' : 'erro-audio: $erro');
  }

  @override
  Future<void> parar() async {
    final a = _elemento;
    _geracao++;
    _aTocar = false;
    if (a == null) return;
    _limpar(a);
    try {
      a.callMethod('pause'.toJS);
    } catch (_) {}
  }

  @override
  void libertar() {
    // o elemento fica para a próxima vez (já desbloqueado); só se cala
    _geracao++;
    _aTocar = false;
    final a = _elemento;
    if (a == null) return;
    _limpar(a);
    try {
      a.callMethod('pause'.toJS);
    } catch (_) {}
  }
}
