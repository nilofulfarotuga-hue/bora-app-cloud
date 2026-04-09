import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';

/// Plays a looping alert tone until explicitly stopped.
/// Safe to call [playLoop] multiple times — idempotent while already playing.
class SoundService {
  final AudioPlayer _player = AudioPlayer(playerId: 'bora-alert');
  bool _isPlaying = false;

  SoundService() {
    // Reset flag when the player stops naturally (e.g. end of single-shot).
    _player.onPlayerComplete.listen((_) {
      _isPlaying = false;
      debugPrint('SoundService: player completed naturally');
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
