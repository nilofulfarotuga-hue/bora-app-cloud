import 'dart:math' as math;
import 'dart:typed_data';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';

/// Plays a looping alert tone until explicitly stopped.
/// Safe to call [playLoop] multiple times — idempotent while already playing.
class SoundService {
  final AudioPlayer _player = AudioPlayer(playerId: 'bora-alert');
  bool _isPlaying = false;

  Future<void> playLoop() async {
    if (_isPlaying) return;
    _isPlaying = true;
    try {
      await _player.setReleaseMode(ReleaseMode.loop);
      await _player.play(AssetSource('bora_alert.wav'), volume: 0.8);
    } catch (_) {
      // Asset not bundled yet — fall back to generated tone.
      try {
        await _player.play(BytesSource(_generateAlertTone()), volume: 0.8);
      } catch (e) {
        _isPlaying = false;
        debugPrint('SoundService: playLoop error => $e');
      }
    }
  }

  Future<void> playOnce() async {
    try {
      await _player.setReleaseMode(ReleaseMode.release);
      await _player.play(AssetSource('bora_alert.wav'), volume: 0.8);
    } catch (_) {
      // Asset not bundled yet — fall back to generated tone.
      try {
        await _player.play(BytesSource(_generateAlertTone()), volume: 0.8);
      } catch (e) {
        debugPrint('SoundService: playOnce error => $e');
      }
    }
  }

  Future<void> stop() async {
    if (!_isPlaying) return;
    _isPlaying = false;
    try {
      await _player.stop();
    } catch (e) {
      debugPrint('SoundService: stop error => $e');
    }
  }

  void dispose() {
    _player.dispose();
  }

  Uint8List _generateAlertTone({
    double frequency = 880,
    double durationMs = 450,
    int sampleRate = 44100,
  }) {
    final sampleCount = (sampleRate * durationMs / 1000).round();
    final dataSize = sampleCount * 2;
    final builder = BytesBuilder();

    void writeString(String value) => builder.add(value.codeUnits);
    void writeInt32(int value) {
      final bytes = ByteData(4)..setInt32(0, value, Endian.little);
      builder.add(bytes.buffer.asUint8List());
    }

    void writeInt16(int value) {
      final bytes = ByteData(2)..setInt16(0, value, Endian.little);
      builder.add(bytes.buffer.asUint8List());
    }

    writeString('RIFF');
    writeInt32(36 + dataSize);
    writeString('WAVE');
    writeString('fmt ');
    writeInt32(16);
    writeInt16(1); // PCM
    writeInt16(1); // mono
    writeInt32(sampleRate);
    writeInt32(sampleRate * 2);
    writeInt16(2);
    writeInt16(16);
    writeString('data');
    writeInt32(dataSize);

    for (var i = 0; i < sampleCount; i++) {
      final t = i / sampleRate;
      final envelope = 1 - (i / sampleCount);
      final sample =
          (math.sin(2 * math.pi * frequency * t) * 32767 * envelope).round();
      writeInt16(sample);
    }

    return builder.takeBytes();
  }
}
