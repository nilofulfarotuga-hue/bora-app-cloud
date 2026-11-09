// O AMIGO — tocador da voz do servidor no telemóvel (pendências 09/11/2026, bloco I).
// Usa o audioplayers que já está no pubspec (nada de dependências novas). O MP3 vai
// para um ficheiro temporário porque o BytesSource do audioplayers 5 só funciona no
// Android; o ficheiro toca nos dois.
import 'dart:async';
import 'dart:io';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import 'amigo_tocador.dart';

AmigoTocador criarAmigoTocadorPlataforma() => _TocadorAparelho();

class _TocadorAparelho extends AmigoTocador {
  AudioPlayer? _p;
  StreamSubscription<void>? _fim;
  int _g = 0;

  @override
  Future<void> tocar(
    AmigoAudio audio, {
    required void Function(double? duracaoMs) aoComecar,
    required void Function() aoAcabar,
    required void Function(String motivo) aoErro,
  }) async {
    final g = ++_g;
    try {
      final p = _p ??= AudioPlayer();
      await _fim?.cancel();
      _fim = null;
      final dir = await getTemporaryDirectory();
      // dois ficheiros a alternar: nunca se escreve por cima do que está a tocar
      final f = File('${dir.path}${Platform.pathSeparator}amigo_voz_${g % 2}.mp3');
      await f.writeAsBytes(audio.bytes, flush: true);
      if (g != _g) return;
      if (defaultTargetPlatform == TargetPlatform.iOS) {
        // Depois do microfone a sessão fica em gravação: força o altifalante
        // (o mesmo que a voz do sistema faz em amigo_voz.dart).
        try {
          await p.setAudioContext(const AudioContext(
            iOS: AudioContextIOS(
              category: AVAudioSessionCategory.playAndRecord,
              options: [
                AVAudioSessionOptions.defaultToSpeaker,
                AVAudioSessionOptions.allowBluetooth,
                AVAudioSessionOptions.allowBluetoothA2DP,
                AVAudioSessionOptions.mixWithOthers,
              ],
            ),
          ));
        } catch (_) {}
      }
      _fim = p.onPlayerComplete.listen((_) {
        if (g == _g) aoAcabar();
      });
      await p.setSource(DeviceFileSource(f.path));
      if (g != _g) return;
      final d = await p.getDuration();
      await p.resume();
      if (g != _g) return;
      final ms = d?.inMilliseconds ?? 0;
      aoComecar(ms > 0 ? ms.toDouble() : null);
    } catch (e) {
      debugPrint('[AmigoTocador] $e');
      if (g == _g) aoErro('erro-audio');
    }
  }

  @override
  Future<void> parar() async {
    _g++;
    await _fim?.cancel();
    _fim = null;
    try {
      await _p?.stop();
    } catch (_) {}
  }

  @override
  void libertar() {
    _g++;
    unawaited(_fim?.cancel());
    _fim = null;
    final p = _p;
    _p = null;
    if (p != null) unawaited(p.dispose().catchError((_) {}));
  }
}
