// O AMIGO — a voz (missão m11-amigo-rosto, 09/11/2026).
//
// A voz é a do próprio telemóvel/navegador (pacote flutter_tts), SEMPRE em
// português de Portugal. A voz do protótipo do Dipsy (edge-tts, Raquel/Duarte)
// não serve na app: precisa de um servidor, não tem licença comercial e a
// alternativa oficial (Azure) é paga — decisão do Danilo, fica no relatório.
// No navegador Edge a voz "Microsoft Raquel (Natural) - Portuguese (Portugal)"
// aparece sozinha e é escolhida primeiro.
//
// Regra: se o aparelho não tiver uma voz pt-PT, o Amigo fala SÓ por legenda
// (a boca mexe-se ao ritmo da legenda). Nunca cai para pt-BR nem para inglês.
// O botão de som fica lembrado (SharedPreferences).
//
// A boca: cada frase vira uma [AmigoFala] (amigo_boca.dart) com tempos
// estimados, acertados em cada evento de palavra do motor de voz.

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../widgets/amigo/amigo_boca.dart';

/// Chave de SharedPreferences: som do Amigo ligado/desligado.
const String kAmigoSomKey = 'amigo.som_ligado';

/// Escolhe a voz pt-PT de uma lista de vozes do motor (puro, testado).
/// Devolve {name, locale} ou null. Nunca devolve pt-BR.
Map<String, String>? escolherVozPtPt(List<dynamic> vozes) {
  final pt = <Map<String, String>>[];
  for (final v in vozes) {
    if (v is! Map) continue;
    final nome = (v['name'] ?? '').toString();
    final locale = (v['locale'] ?? '').toString();
    final l = locale.toLowerCase().replaceAll('_', '-');
    final n = nome.toLowerCase();
    final ehPt = l == 'pt-pt' ||
        l.startsWith('pt-pt-') ||
        l == 'por-prt' ||
        (n.contains('portugal') && !n.contains('brasil') && !n.contains('brazil'));
    if (!ehPt) continue;
    if (l.contains('br') || n.contains('brasil') || n.contains('brazil')) continue;
    pt.add({'name': nome, 'locale': locale, ..._extras(v)});
  }
  if (pt.isEmpty) return null;
  int peso(Map<String, String> v) {
    final n = v['name']!.toLowerCase();
    var p = 0;
    if (n.contains('natural')) p += 50; // Edge: Raquel/Duarte Natural
    if (n.contains('raquel')) p += 20; // a voz do protótipo do Dipsy
    if (n.contains('joana') || n.contains('catarina')) p += 15; // iPhone
    if (v['network_required'] == 'false' || n.contains('local')) p += 10;
    if (v['quality'] == 'enhanced' || v['quality'] == 'premium') p += 8;
    return p;
  }

  pt.sort((a, b) => peso(b).compareTo(peso(a)));
  final v = pt.first;
  return {'name': v['name']!, 'locale': v['locale']!};
}

Map<String, String> _extras(Map v) => {
      if (v['network_required'] != null)
        'network_required': v['network_required'].toString() == '1' ||
                v['network_required'].toString() == 'true'
            ? 'true'
            : 'false',
      if (v['quality'] != null) 'quality': v['quality'].toString().toLowerCase(),
    };

/// O motor de voz por baixo (o do sistema; nos testes, um falso).
abstract class AmigoMotorVoz {
  /// Prepara e devolve o nome da voz pt-PT escolhida (null = não há).
  Future<String?> preparar(double velocidade);
  Future<void> falar(String texto);
  Future<void> parar();

  VoidCallback? aoComecar;
  void Function(int inicioLetra)? aoPalavra;
  VoidCallback? aoAcabar;
}

/// A voz do telemóvel/navegador (flutter_tts).
class AmigoMotorVozSistema extends AmigoMotorVoz {
  FlutterTts? _tts;

  bool get _ios => !kIsWeb && defaultTargetPlatform == TargetPlatform.iOS;

  @override
  Future<String?> preparar(double velocidade) async {
    final tts = _tts ??= FlutterTts();
    try {
      await tts.awaitSpeakCompletion(false);
      tts.setStartHandler(() => aoComecar?.call());
      tts.setProgressHandler((texto, inicio, fim, palavra) => aoPalavra?.call(inicio));
      tts.setCompletionHandler(() => aoAcabar?.call());
      tts.setCancelHandler(() => aoAcabar?.call());
      tts.setErrorHandler((_) => aoAcabar?.call());
      // No navegador a lista chega depois do "voiceschanged" — no Chrome do
      // Android (emulador, 09/11) demorou mais de 1,5 s: tenta durante ~4 s.
      List<dynamic> vozes = const [];
      for (var i = 0; i < 16; i++) {
        final v = await tts.getVoices;
        if (v is List && v.isNotEmpty) {
          vozes = v;
          break;
        }
        await Future<void>.delayed(const Duration(milliseconds: 250));
      }
      final voz = escolherVozPtPt(vozes);
      if (voz == null) return null;
      await tts.setLanguage(voz['locale']!);
      await tts.setVoice(voz);
      // flutter_tts: Android multiplica por 2 e o iPhone usa 0,5 como normal;
      // no navegador 1 é normal.
      await tts.setSpeechRate(kIsWeb ? velocidade : 0.5 * velocidade);
      await tts.setPitch(1.05);
      await tts.setVolume(1);
      return voz['name'];
    } catch (e) {
      debugPrint('[AmigoVoz] preparar: $e');
      return null;
    }
  }

  @override
  Future<void> falar(String texto) async {
    final tts = _tts;
    if (tts == null) return;
    if (_ios) {
      // Depois do microfone a sessão de áudio fica em gravação: força o
      // altifalante para a voz não sair baixinho pelo auscultador.
      try {
        await tts.setIosAudioCategory(
          IosTextToSpeechAudioCategory.playAndRecord,
          [
            IosTextToSpeechAudioCategoryOptions.defaultToSpeaker,
            IosTextToSpeechAudioCategoryOptions.allowBluetooth,
            IosTextToSpeechAudioCategoryOptions.allowBluetoothA2DP,
            IosTextToSpeechAudioCategoryOptions.mixWithOthers,
          ],
          IosTextToSpeechAudioMode.defaultMode,
        );
      } catch (_) {}
    }
    await tts.speak(texto);
  }

  @override
  Future<void> parar() async {
    try {
      await _tts?.stop();
    } catch (_) {}
  }
}

enum AmigoVozEstado { calado, aFalar }

/// A voz do Amigo: fala, legenda e boca. Um por ecrã.
class AmigoVoz {
  AmigoVoz({
    AmigoMotorVoz? motor,
    double velocidade = 1,
    bool somPorDefeito = true,
    double Function()? relogio,
  })  : _motor = motor ?? AmigoMotorVozSistema(),
        _velocidade = velocidade,
        _relogioExterno = relogio,
        somLigado = ValueNotifier<bool>(somPorDefeito);

  /// Relógio (ms) trocável: o vídeo das provas grava imagem a imagem com
  /// tempo exato; na app é o relógio real.
  final double Function()? _relogioExterno;

  final AmigoMotorVoz _motor;
  double _velocidade;
  final Stopwatch _relogio = Stopwatch()..start();

  /// Som ligado (lembrado entre aberturas).
  final ValueNotifier<bool> somLigado;

  /// O texto que está a ser dito (legenda) e a palavra atual (karaoke).
  final ValueNotifier<String> legenda = ValueNotifier<String>('');
  final ValueNotifier<int> palavraAtual = ValueNotifier<int>(-1);
  final ValueNotifier<AmigoVozEstado> estado =
      ValueNotifier<AmigoVozEstado>(AmigoVozEstado.calado);

  /// Nome da voz pt-PT escolhida; null = sem voz pt-PT (só legenda).
  String? nomeVoz;
  bool _preparada = false;
  Future<void>? _aPreparar;

  AmigoFala? _fala;
  AmigoFala? get falaAtual => _fala;
  Completer<void>? _fim;
  Timer? _seguranca;
  Timer? _arranqueRelogio;
  bool _comVoz = false;

  /// Motores sem eventos de palavra (o Chrome do Android, provado a 09/11):
  /// a boca vai pela estimativa do texto, por isso a voz aprende a velocidade
  /// real do aparelho no fim de cada frase e acerta as seguintes.
  double ajusteVelocidade = 1;
  double? _inicioReal;

  /// Desvios (ms) entre a estimativa e os eventos reais de palavra, da última
  /// frase — vão para o registo de provas.
  List<double> get desviosUltimaFrase => _fala?.desvios ?? const [];

  /// Provas (m11, 2.4): o atraso entre cada evento de palavra do motor de voz
  /// e a primeira imagem do rosto que já usa essa palavra, e todos os desvios
  /// da estimativa. Só números, sem texto.
  final List<double> atrasosEventoBoca = [];
  final List<double> desvios = [];
  int eventosDePalavra = 0;
  double? _eventoPendente;

  double get _agora => _relogioExterno?.call() ?? _relogio.elapsedMicroseconds / 1000;

  bool get temVozPtPt => nomeVoz != null;

  // Se a voz pt-PT ainda não tinha chegado, volta a procurá-la antes de
  // falar (até 3 vezes, de 2 em 2 s). Provado no Chrome do Android: a voz
  // "Portuguese Portugal" existe mas aparece tarde.
  int _tentativasVoz = 0;
  DateTime? _ultimaTentativa;

  Future<void> _procurarVozOutraVez() async {
    if (temVozPtPt || _tentativasVoz >= 3) return;
    final u = _ultimaTentativa;
    if (u != null && DateTime.now().difference(u) < const Duration(seconds: 2)) return;
    _tentativasVoz++;
    _ultimaTentativa = DateTime.now();
    nomeVoz = await _motor.preparar(_velocidade);
    debugPrint('[AmigoVoz] nova procura ($_tentativasVoz): ${nomeVoz ?? 'ainda sem voz pt-PT'}');
  }

  Future<void> preparar() => _aPreparar ??= _preparar();

  Future<void> _preparar() async {
    try {
      final p = await SharedPreferences.getInstance();
      final s = p.getBool(kAmigoSomKey);
      if (s != null) somLigado.value = s;
    } catch (_) {}
    _motor.aoComecar = _comecou;
    _motor.aoPalavra = _palavra;
    _motor.aoAcabar = _acabouNatural;
    nomeVoz = await _motor.preparar(_velocidade);
    _ultimaTentativa = DateTime.now();
    _preparada = true;
    debugPrint('[AmigoVoz] voz pt-PT: ${nomeVoz ?? 'nenhuma (só legenda)'}');
  }

  Future<void> alternarSom() async {
    somLigado.value = !somLigado.value;
    try {
      final p = await SharedPreferences.getInstance();
      await p.setBool(kAmigoSomKey, somLigado.value);
    } catch (_) {}
    if (!somLigado.value && _comVoz) {
      // calou a meio: a legenda e a boca seguem em silêncio até ao fim
      _comVoz = false;
      await _motor.parar();
      _armarSeguranca(silencio: true);
    }
  }

  /// Diz [texto] (ou só mostra a legenda, sem som/sem voz pt-PT). Termina
  /// quando acaba de falar ou quando alguém chama [parar].
  Future<void> falar(String texto) async {
    final t = texto.trim();
    if (t.isEmpty) return;
    if (!_preparada) await preparar();
    await _procurarVozOutraVez();
    await parar();
    final fala = AmigoFala(t, velocidade: _velocidade * ajusteVelocidade);
    _inicioReal = null;
    _fala = fala;
    legenda.value = t;
    palavraAtual.value = -1;
    estado.value = AmigoVozEstado.aFalar;
    final fim = _fim = Completer<void>();
    _comVoz = somLigado.value && temVozPtPt;
    if (_comVoz) {
      try {
        await _motor.falar(t);
      } catch (e) {
        debugPrint('[AmigoVoz] falar: $e');
        _comVoz = false;
      }
      // Alguns motores não avisam o início: arranca o relógio na mesma.
      _arranqueRelogio?.cancel();
      _arranqueRelogio = Timer(const Duration(milliseconds: 900), () {
        if (identical(_fala, fala) && !fala.comecada) fala.comecou(_agora);
      });
    } else {
      fala.comecou(_agora);
    }
    _armarSeguranca(silencio: !_comVoz);
    return fim.future;
  }

  void _armarSeguranca({required bool silencio}) {
    final fala = _fala;
    if (fala == null) return;
    _seguranca?.cancel();
    // Em silêncio acaba no tempo estimado; com voz, rede de segurança se o
    // motor nunca disser que acabou.
    final ms = silencio
        ? fala.duracaoEstimada - (fala.comecada ? fala.posicao(_agora) : 0)
        : fala.duracaoEstimada * 2.5 + 4000;
    _seguranca = Timer(Duration(milliseconds: ms.clamp(200, 120000).round()), () {
      if (identical(_fala, fala)) _acabou();
    });
  }

  void _comecou() {
    final f = _fala;
    _inicioReal = _agora;
    if (f != null && !f.comecada) f.comecou(_agora);
  }

  /// O motor disse que acabou (não foi interrompido): sem eventos de palavra,
  /// aprende quanto a estimativa falhou na duração.
  void _acabouNatural() {
    final f = _fala;
    final ini = _inicioReal;
    if (f != null && _comVoz && ini != null && f.desvios.isEmpty) {
      final real = _agora - ini;
      final est = f.duracaoEstimada;
      if (real > 400 && est > 400) {
        final r = (est / real).clamp(0.6, 1.6);
        ajusteVelocidade = (ajusteVelocidade * (1 + (r - 1) * 0.6)).clamp(0.5, 2.0);
      }
    }
    _acabou();
  }

  void _palavra(int inicioLetra) {
    final f = _fala;
    if (f == null) return;
    f.palavraComecou(inicioLetra, _agora);
    eventosDePalavra++;
    _eventoPendente = _agora;
    if (f.desvios.isNotEmpty) desvios.add(f.desvios.last);
    if (kDebugMode && f.desvios.isNotEmpty) {
      debugPrint('[AmigoVoz] palavra@$inicioLetra desvio ${f.desvios.last.toStringAsFixed(0)} ms');
    }
  }

  void _acabou() {
    _seguranca?.cancel();
    _seguranca = null;
    _arranqueRelogio?.cancel();
    _arranqueRelogio = null;
    _comVoz = false;
    _fala = null;
    palavraAtual.value = -1;
    estado.value = AmigoVozEstado.calado;
    final f = _fim;
    _fim = null;
    if (f != null && !f.isCompleted) f.complete();
  }

  /// Cala já (o cliente tocou no microfone, saiu do ecrã, interrompeu).
  Future<void> parar() async {
    if (_fala == null && _fim == null) return;
    final comVoz = _comVoz;
    _acabou();
    if (comVoz) await _motor.parar();
  }

  /// A boca neste instante (lida pelo rosto a cada imagem). Atualiza também
  /// a palavra da legenda.
  AmigoBocaForma? bocaAgora() {
    final f = _fala;
    if (f == null || !f.comecada) return null;
    final agora = _agora;
    final ev = _eventoPendente;
    if (ev != null) {
      atrasosEventoBoca.add(agora - ev);
      _eventoPendente = null;
    }
    final i = f.palavraEm(agora);
    if (i != palavraAtual.value) palavraAtual.value = i;
    return f.formaEm(agora);
  }

  set velocidade(double v) => _velocidade = v.clamp(0.5, 2.0).toDouble();

  void dispose() {
    _seguranca?.cancel();
    _arranqueRelogio?.cancel();
    unawaited(_motor.parar());
    legenda.dispose();
    palavraAtual.dispose();
    estado.dispose();
    somLigado.dispose();
  }
}
