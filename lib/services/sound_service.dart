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
    });
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
    });
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
