import 'dart:async';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';

/// Plays a looping alert tone until explicitly stopped.
/// Safe to call [playLoop] multiple times — idempotent while already playing.
///
/// Each instance uses a unique AudioPlayer so that multiple SoundService
/// instances (e.g. NotificationService + DriverHomeScreen) cannot share state
/// and override each other's release mode or interrupt each other's playback.
class SoundService {
  final AudioPlayer _player = AudioPlayer();
  bool _isPlaying = false;

  bool get isPlaying => _isPlaying;

  SoundService() {
    // Reset flag when the player stops naturally (e.g. end of single-shot).
    _player.onPlayerComplete.listen((_) {
      _isPlaying = false;
      debugPrint('SoundService: player completed naturally');
    }, onError: _onPlayerError);
    // Reset flag on any external stop (audio focus lost, phone call, background).
    // Without this, _isPlaying stays true after interruption and the next
    // playLoop() call returns early, silently missing the alert.
    _player.onPlayerStateChanged.listen((state) {
      if (state == PlayerState.stopped || state == PlayerState.completed) {
        if (_isPlaying) {
          _isPlaying = false;
          debugPrint('SoundService: player stopped externally — flag reset');
        }
      }
    }, onError: _onPlayerError);
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
      await _player.setReleaseMode(ReleaseMode.release);
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
  Future<void> desbloquearAudioAposToque() async {
    try {
      await _player.stop();
      await _player.setReleaseMode(ReleaseMode.release);
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
    _player.dispose();
  }
}
