// O AMIGO — o tocador do áudio da voz do servidor (pendências 09/11/2026, bloco I).
//
// Quando o aparelho não tem voz de Portugal (ex.: Safari do iPhone), a Edge
// amigo-voz devolve a frase em MP3 (Google, pt-PT) e este tocador toca-a:
//   - no navegador, um elemento <audio> (amigo_tocador_web.dart);
//   - no telemóvel, o audioplayers que já está no pubspec (amigo_tocador_io.dart).
// Nos testes troca-se por um falso.

import 'dart:typed_data';

import 'amigo_tocador_io.dart' if (dart.library.js_interop) 'amigo_tocador_web.dart'
    as plataforma;

/// Uma frase já em áudio (MP3).
class AmigoAudio {
  AmigoAudio({required this.bytes, required this.base64, this.origem = '', this.mime = 'audio/mpeg'});

  final Uint8List bytes;

  /// O mesmo áudio em base64 (o navegador toca-o como data: sem copiar).
  final String base64;

  /// Tipo do áudio (a Edge manda sempre MP3; a demo das provas manda WAV).
  final String mime;

  /// 'cache' ou 'google' (só para o registo).
  final String origem;
}

abstract class AmigoTocador {
  /// Toca [audio]. [aoComecar] recebe a duração real (ms) quando se sabe;
  /// [aoErro] recebe 'not-allowed' quando o navegador pede um toque.
  Future<void> tocar(
    AmigoAudio audio, {
    required void Function(double? duracaoMs) aoComecar,
    required void Function() aoAcabar,
    required void Function(String motivo) aoErro,
  });

  Future<void> parar();

  /// Liberta o leitor (o ecrã fechou).
  void libertar() {}
}

/// O tocador desta plataforma.
AmigoTocador criarAmigoTocador() => plataforma.criarAmigoTocadorPlataforma();
