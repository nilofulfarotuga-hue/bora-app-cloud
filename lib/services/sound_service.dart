import 'dart:async';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';

/// Plays a looping alert tone until explicitly stopped.
/// Safe to call [playLoop] multiple times — idempotent while already playing.
///
/// Android/iOS: each instance uses a unique AudioPlayer so that multiple
/// SoundService instances (e.g. NotificationService + DriverHomeScreen) cannot
/// share state and override each other's release mode or interrupt each
/// other's playback.
///
/// [Web 07/10/2026] No navegador é ao contrário: todas as instâncias partilham
/// UM leitor. O Safari (iPhone e Mac) só deixa um elemento `<audio>` tocar
/// depois de esse MESMO elemento ter sido tocado dentro de um gesto do
/// utilizador — o desbloqueio é por leitor, não por página. Com um leitor por
/// instância, o painel do parceiro (`partner_dashboard_screen.dart`) e a oferta
/// TVDE (`tvde_offer_screen.dart`) criavam o seu leitor já depois do toque e
/// ficavam mudos; só o ecrã do estafeta tocava, porque chamava
/// [desbloquearAudioAposToque] no botão "Ficar online". Agora o leitor
/// partilhado é desbloqueado no PRIMEIRO toque em qualquer sítio da página
/// ([instalarDesbloqueioWeb], chamado no arranque) e serve toda a gente.
class SoundService {
  /// Leitor único da web (ver nota da classe). Nunca se chama `dispose` nele.
  static AudioPlayer? _leitorPartilhadoWeb;

  static AudioPlayer get _leitorWeb => _leitorPartilhadoWeb ??= AudioPlayer();

  /// Na web o leitor é partilhado; nos telemóveis cada instância tem o seu.
  final bool _partilhado;
  final AudioPlayer _player;
  final List<StreamSubscription<dynamic>> _subs = [];
  bool _isPlaying = false;

  bool get isPlaying => _isPlaying;

  /// Testes: `true` quando esta instância usa o leitor partilhado da web.
  @visibleForTesting
  bool get usaLeitorPartilhado => _partilhado;

  SoundService({bool? partilharLeitor})
      : _partilhado = partilharLeitor ?? kIsWeb,
        _player = (partilharLeitor ?? kIsWeb) ? _leitorWeb : AudioPlayer() {
    // Reset flag when the player stops naturally (e.g. end of single-shot).
    _subs.add(_player.onPlayerComplete.listen((_) {
      _isPlaying = false;
      debugPrint('SoundService: player completed naturally');
    }, onError: _onPlayerError));
    // Reset flag on any external stop (audio focus lost, phone call, background).
    // Without this, _isPlaying stays true after interruption and the next
    // playLoop() call returns early, silently missing the alert.
    _subs.add(_player.onPlayerStateChanged.listen((state) {
      if (state == PlayerState.stopped || state == PlayerState.completed) {
        if (_isPlaying) {
          _isPlaying = false;
          debugPrint('SoundService: player stopped externally — flag reset');
        }
      }
    }, onError: _onPlayerError));
  }

  /// Modo de fim de um toque único. Na web NUNCA `release`: libertar deita o
  /// elemento `<audio>` fora e o seguinte nasce por desbloquear (Safari).
  ReleaseMode get _modoToqueUnico =>
      _partilhado ? ReleaseMode.stop : ReleaseMode.release;

  // ── Desbloqueio global na web ─────────────────────────────────────────────

  static DesbloqueioAudioWeb? _desbloqueio;

  /// Liga o desbloqueio do leitor partilhado ao primeiro toque na página.
  /// Chama-se uma vez no arranque (`main.dart`); fora da web não faz nada.
  /// Idempotente.
  static void instalarDesbloqueioWeb() {
    if (!kIsWeb || _desbloqueio != null) return;
    final d = _desbloqueio = DesbloqueioAudioWeb(_tocarSilencioNoLeitorWeb);
    GestureBinding.instance.pointerRouter.addGlobalRoute(d.tratar);
  }

  /// Testes: `true` depois de o primeiro toque ter desbloqueado o leitor.
  @visibleForTesting
  static bool get audioWebDesbloqueado => _desbloqueio?.feito ?? false;

  static Future<void> _tocarSilencioNoLeitorWeb() async {
    final p = _leitorWeb;
    try {
      await p.stop();
      await p.setReleaseMode(ReleaseMode.stop);
      await p.play(AssetSource('sounds/bora_alert.wav'), volume: 0.0);
      await Future<void>.delayed(const Duration(milliseconds: 300));
      await p.stop();
      await p.setVolume(1.0);
      debugPrint('SoundService: leitor partilhado da web desbloqueado');
    } catch (e) {
      debugPrint('SoundService: desbloqueio web => $e');
    }
  }

  /// [Paridade 2026-09-21] Erro vindo do MediaPlayer nativo pelo stream de
  /// eventos (ex.: `AndroidAudioError MEDIA_ERROR_UNKNOWN {what:-38}` = play
  /// chamado antes de o player estar preparado, Samsung A23, 3× a 19/09).
  /// Sem `onError` nas subscrições acima o erro subia como "não tratado" e
  /// ia parar a debug_crash_logs, e o alerta ficava mudo com _isPlaying a
  /// true. Agora: regista, liberta a bandeira e, se era o toque contínuo,
  /// tenta UMA vez mais passado meio segundo.
  bool _retrying = false;
  void _onPlayerError(Object e, [StackTrace? st]) {
    debugPrint('SoundService: erro do player => $e');
    final eraLoop = _isPlaying;
    _isPlaying = false;
    if (eraLoop && !_retrying && e.toString().contains('-38')) {
      _retrying = true;
      unawaited(Future<void>.delayed(const Duration(milliseconds: 500), () {
        _retrying = false;
        return playLoop();
      }));
    }
  }

  Future<void> playLoop() async {
    if (_isPlaying) return;
    _isPlaying = true;
    debugPrint('SoundService: starting loop playback');
    try {
      await _player.stop();
      await _player.setReleaseMode(ReleaseMode.loop);
      await _player.play(
        AssetSource('sounds/bora_alert.wav'),
        volume: 1.0,
      );
      debugPrint('SoundService: loop started');
    } catch (e) {
      _isPlaying = false;
      debugPrint('SoundService: playLoop error => $e');
    }
  }

  Future<void> playOnce() async {
    debugPrint('SoundService: playing once');
    try {
      await _player.stop();
      await _player.setReleaseMode(_modoToqueUnico);
      await _player.play(
        AssetSource('sounds/bora_alert.wav'),
        volume: 1.0,
      );
    } catch (e) {
      debugPrint('SoundService: playOnce error => $e');
    }
  }

  /// [Web 16/09] O iOS (e o Chrome) só deixam tocar som depois de um gesto do
  /// utilizador. Chama-se no toque de "Ficar online": toca o alerta em
  /// silêncio (volume 0) e pára — a partir daí a oferta pode tocar sozinha.
  /// (07/10: na web o leitor é o partilhado, logo desbloqueia toda a gente.)
  Future<void> desbloquearAudioAposToque() async {
    try {
      await _player.stop();
      await _player.setReleaseMode(_modoToqueUnico);
      await _player.play(AssetSource('sounds/bora_alert.wav'), volume: 0.0);
      await Future<void>.delayed(const Duration(milliseconds: 300));
      await _player.stop();
      debugPrint('SoundService: áudio desbloqueado após toque');
    } catch (e) {
      debugPrint('SoundService: desbloquear áudio => $e');
    }
  }

  Future<void> stop() async {
    _isPlaying = false;
    debugPrint('SoundService: stopping');
    try {
      await _player.stop();
    } catch (e) {
      debugPrint('SoundService: stop error => $e');
    }
  }

  void dispose() {
    for (final s in _subs) {
      s.cancel();
    }
    _subs.clear();
    // O leitor partilhado da web vive enquanto a página viver — libertá-lo
    // deixava o ecrã seguinte sem leitor desbloqueado.
    if (!_partilhado) _player.dispose();
  }
}

/// Porta do desbloqueio: só o PRIMEIRO toque (pointer down) dispara o toque
/// silencioso; movimentos, subidas e toques seguintes não fazem nada.
/// Separado do leitor para se poder provar sem navegador.
class DesbloqueioAudioWeb {
  DesbloqueioAudioWeb(this._tocarSilencio);

  final Future<void> Function() _tocarSilencio;
  bool _feito = false;

  bool get feito => _feito;

  /// Devolve `true` se este evento foi o que desbloqueou o leitor.
  bool tratar(PointerEvent evento) {
    if (_feito || evento is! PointerDownEvent) return false;
    _feito = true;
    unawaited(_tocarSilencio().catchError((Object e) {
      debugPrint('DesbloqueioAudioWeb: toque silencioso falhou => $e');
    }));
    return true;
  }
}
