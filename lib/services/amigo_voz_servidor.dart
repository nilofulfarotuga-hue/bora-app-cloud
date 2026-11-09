// O AMIGO — a voz do servidor (missão missao-pendencias-2026-11-09, bloco I).
//
// O Amigo fala com a voz do aparelho quando há voz de Portugal (a M11 procura-a com
// espera, porque a lista chega tarde). Quando NÃO há (ex.: Safari do iPhone), e o
// painel tem a voz do servidor ligada (amigo_voz_servidor_ativo), pede a frase em
// MP3 à Edge amigo-voz (Google, sempre pt-PT) e toca-a; a boca segue a duração real
// do áudio. Se o servidor disser "usa o aparelho" (desligado, teto, sem chave, erro),
// fica a legenda, como antes, sem erro à vista: o botão passa a "Sem voz".

import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'amigo_tocador.dart';
import 'amigo_voz.dart';
import 'assistant_service.dart';

export 'amigo_tocador.dart' show AmigoAudio, AmigoTocador, criarAmigoTocador;

/// O nome que aparece como "voz" quando quem fala é o servidor.
const String kAmigoVozServidorNome = 'Voz pt-PT da Bora (servidor)';

/// Avisos do motor à [AmigoVoz]: esta frase fica sem som (segue a legenda) /
/// o servidor não dá voz neste ecrã (fica "Sem voz").
const String kAmigoSemVozFrase = 'amigo-sem-voz-frase';
const String kAmigoSemVozServidor = 'amigo-sem-voz-servidor';

/// Motivos do servidor que valem para o resto do ecrã (não adianta pedir outra vez).
const Set<String> kAmigoMotivosDefinitivos = {
  'desligado',
  'teto',
  'limite_utilizador',
  'sem_chave',
  'sem_sessao',
};

/// O que a Edge respondeu: áudio, ou "usa o aparelho" com o motivo.
class AmigoAudioResposta {
  const AmigoAudioResposta.audio(AmigoAudio this.audio)
      : motivo = null,
        definitivo = false;
  const AmigoAudioResposta.semVoz(String this.motivo, {this.definitivo = false}) : audio = null;

  final AmigoAudio? audio;
  final String? motivo;

  /// true = não voltar a pedir neste ecrã.
  final bool definitivo;

  bool get usarAparelho => audio == null;
}

/// Lê a resposta da Edge amigo-voz (puro, testado).
AmigoAudioResposta amigoRespostaDoServidor(Object? data) {
  if (data is! Map) return const AmigoAudioResposta.semVoz('resposta_invalida');
  final b64 = data['audio_base64'];
  if (data['ok'] == true && b64 is String && b64.isNotEmpty) {
    try {
      return AmigoAudioResposta.audio(AmigoAudio(
        bytes: base64Decode(b64),
        base64: b64,
        origem: '${data['origem'] ?? ''}',
        mime: data['formato'] == 'wav' ? 'audio/wav' : 'audio/mpeg',
      ));
    } catch (_) {
      return const AmigoAudioResposta.semVoz('resposta_invalida');
    }
  }
  final m = '${data['motivo'] ?? 'erro'}';
  return AmigoAudioResposta.semVoz(m, definitivo: kAmigoMotivosDefinitivos.contains(m));
}

/// Quem pede o áudio (trocável nos testes).
abstract class AmigoVozServidorCliente {
  Future<AmigoAudioResposta> pedir(String texto, {double velocidade = 1});
}

/// A Edge amigo-voz pelo Supabase (com a sessão do cliente).
class AmigoVozServidorSupabase implements AmigoVozServidorCliente {
  const AmigoVozServidorSupabase({this.tempo = const Duration(seconds: 8)});

  final Duration tempo;

  @override
  Future<AmigoAudioResposta> pedir(String texto, {double velocidade = 1}) async {
    try {
      final res = await Supabase.instance.client.functions
          .invoke('amigo-voz', body: {'texto': texto, 'velocidade': velocidade})
          .timeout(tempo);
      return amigoRespostaDoServidor(res.data);
    } on FunctionException catch (e) {
      debugPrint('[AmigoVoz] servidor ${e.status}');
      return AmigoAudioResposta.semVoz(e.status == 401 ? 'sem_sessao' : 'erro',
          definitivo: e.status == 401);
    } catch (e) {
      debugPrint('[AmigoVoz] servidor: $e');
      return const AmigoAudioResposta.semVoz('erro');
    }
  }
}

/// A voz do Amigo: a do aparelho quando há pt-PT; senão a do servidor (se ligada).
class AmigoMotorVozComServidor extends AmigoMotorVoz {
  AmigoMotorVozComServidor({
    AmigoMotorVoz? aparelho,
    AmigoVozServidorCliente? servidor,
    AmigoTocador Function()? tocador,
    Future<bool> Function()? servidorLigado,
  })  : _aparelho = aparelho ?? AmigoMotorVozSistema(),
        _servidor = servidor ?? const AmigoVozServidorSupabase(),
        _criarTocador = tocador ?? criarAmigoTocador,
        _servidorLigado = servidorLigado ?? _flagDoPainel;

  static Future<bool> _flagDoPainel() async {
    await AssistantFlags.carregar();
    return AssistantFlags.vozServidor.value;
  }

  final AmigoMotorVoz _aparelho;
  final AmigoVozServidorCliente _servidor;
  final AmigoTocador Function() _criarTocador;
  final Future<bool> Function() _servidorLigado;

  AmigoTocador? _tocadorCriado;
  AmigoTocador get _tocador => _tocadorCriado ??= _criarTocador();

  bool _usaServidor = false;
  bool _desistiu = false;
  int _falhasSeguidas = 0;
  int _falhasTocador = 0;
  int _geracao = 0;
  double _velocidade = 1;

  /// As últimas frases já em áudio: repetir ("Toca para ouvir") não volta ao servidor.
  final Map<String, AmigoAudio> _memoria = {};

  /// Quantas vezes se pediu ao servidor (provas e testes).
  int pedidosAoServidor = 0;

  /// O motivo da última vez que o servidor disse "usa o aparelho".
  String? ultimoMotivo;

  bool get usaServidor => _usaServidor;

  void _ligarAparelho() {
    _aparelho
      ..aoComecar = (() => aoComecar?.call())
      ..aoPalavra = ((i) => aoPalavra?.call(i))
      ..aoAcabar = (() => aoAcabar?.call())
      ..aoErro = ((m) => aoErro?.call(m))
      ..aoDuracao = ((ms) => aoDuracao?.call(ms));
  }

  @override
  Future<String?> preparar(double velocidade) async {
    _velocidade = velocidade;
    _ligarAparelho();
    final nome = await _aparelho.preparar(velocidade);
    if (nome != null) {
      _usaServidor = false;
      return nome;
    }
    if (_desistiu) return null;
    var ligado = false;
    try {
      ligado = await _servidorLigado();
    } catch (_) {}
    _usaServidor = ligado;
    if (!ligado) return null;
    _tocador; // cria já o tocador (no navegador fica à espera do 1.º toque para desbloquear)
    debugPrint('[AmigoVoz] sem voz pt-PT no aparelho: usa a voz do servidor');
    return kAmigoVozServidorNome;
  }

  @override
  Future<void> falar(String texto) async {
    if (!_usaServidor) return _aparelho.falar(texto);
    final g = ++_geracao;
    final chave = '${_velocidade.toStringAsFixed(2)}|$texto';
    var audio = _memoria[chave];
    if (audio == null) {
      pedidosAoServidor++;
      final r = await _servidor.pedir(texto, velocidade: _velocidade);
      if (g != _geracao) return; // calaram-no entretanto
      audio = r.audio;
      if (audio == null) {
        ultimoMotivo = r.motivo;
        _falhasSeguidas++;
        debugPrint('[AmigoVoz] servidor: usa o aparelho (${r.motivo})');
        if (r.definitivo || _falhasSeguidas >= 3) {
          _desistiu = true;
          _usaServidor = false;
          aoErro?.call(kAmigoSemVozServidor);
        } else {
          aoErro?.call(kAmigoSemVozFrase);
        }
        return;
      }
      _falhasSeguidas = 0;
      _memoria.remove(chave);
      _memoria[chave] = audio;
      while (_memoria.length > 12) {
        _memoria.remove(_memoria.keys.first);
      }
    }
    debugPrint('[AmigoVoz] a tocar a voz do servidor (${audio.origem}, ${audio.bytes.length} bytes)');
    await _tocador.tocar(
      audio,
      aoComecar: (ms) {
        if (g != _geracao) return;
        _falhasTocador = 0;
        debugPrint('[AmigoVoz] áudio do servidor a tocar: ${ms?.round() ?? '?'} ms');
        if (ms != null && ms > 0) aoDuracao?.call(ms);
        aoComecar?.call();
      },
      aoAcabar: () {
        if (g == _geracao) aoAcabar?.call();
      },
      aoErro: (m) {
        if (g != _geracao) return;
        debugPrint('[AmigoVoz] tocador: $m');
        if (m == 'not-allowed') {
          aoErro?.call('not-allowed'); // o ecrã mostra "Toca para ouvir"
          return;
        }
        // Este aparelho não toca o áudio: duas frases seguidas assim e deixa de pedir
        // ao servidor (não se gastam caracteres da Google para nada).
        _falhasTocador++;
        if (_falhasTocador >= 2) {
          _desistiu = true;
          _usaServidor = false;
          aoErro?.call(kAmigoSemVozServidor);
        } else {
          aoErro?.call(kAmigoSemVozFrase);
        }
      },
    );
  }

  @override
  Future<void> parar() async {
    _geracao++;
    try {
      await _tocadorCriado?.parar();
    } catch (_) {}
    await _aparelho.parar();
  }

  @override
  void libertar() {
    _geracao++;
    _tocadorCriado?.libertar();
    _aparelho.libertar();
  }
}
