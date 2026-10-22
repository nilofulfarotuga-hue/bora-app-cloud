/// ENVIO DAS FOTOS DO ESTAFETA (missão cadastro-estafeta-fotos-22-10).
///
/// Antes: o cadastro mandava `contentType: 'image/$ext'` (tirado do nome) e
/// engolia o erro — `.jpg` virava `image/jpg`, o bucket recusava (415) e o
/// estafeta ficava sem selfie, sem foto do documento e sem foto do veículo, sem
/// ninguém saber. Agora:
///   1. o tipo vem dos primeiros bytes; HEIC (iPhone) é convertido para JPEG
///      com o descodificador do sistema antes de sair do telemóvel;
///   2. cada foto tenta 3 vezes (a primeira + 2) quando a falha é de rede ou do
///      servidor;
///   3. se mesmo assim falhar, sobe uma [FotoEnvioException] com a frase para o
///      ecrã (PT-PT) e o erro real do servidor, que fica no `e2e_log`.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;
import 'package:supabase_flutter/supabase_flutter.dart';

import 'driver_documentos.dart';

/// Bytes prontos a enviar, com o tipo certo.
class FotoPronta {
  const FotoPronta(this.bytes, this.mime);
  final Uint8List bytes;
  final String mime;
}

/// Falha de envio: [mensagem] vai para o ecrã; [detalhe] é o erro do servidor.
class FotoEnvioException implements Exception {
  const FotoEnvioException(this.mensagem, {this.detalhe});
  final String mensagem;
  final String? detalhe;

  @override
  String toString() => detalhe == null ? mensagem : '$mensagem ($detalhe)';
}

/// Tamanho máximo aceite pelo bucket `driver-documents`.
const int kFotoEstafetaMaxBytes = 10 * 1024 * 1024;

/// Lado maior quando é preciso converter (HEIC → JPEG).
const int _ladoMaximo = 1600;

/// JPEG/PNG/WebP seguem como estão; HEIC ou formato desconhecido é lido pelo
/// descodificador do sistema (Android 9+, iOS, Safari) e regravado em JPEG.
/// Devolve null se não houver maneira de o ler.
Future<FotoPronta?> prepararFotoParaEnvio(Uint8List bytes) async {
  if (bytes.isEmpty) return null;
  final mime = mimeDaFoto(tipoDaFoto(bytes));
  if (mime != null) return FotoPronta(bytes, mime);
  ui.Codec? codec;
  ui.Image? imagem;
  try {
    final buffer = await ui.ImmutableBuffer.fromUint8List(bytes);
    codec = await ui.instantiateImageCodecWithSize(
      buffer,
      getTargetSize: (w, h) {
        final maior = w > h ? w : h;
        if (maior <= _ladoMaximo) return ui.TargetImageSize(width: w, height: h);
        final f = _ladoMaximo / maior;
        return ui.TargetImageSize(
            width: (w * f).round(), height: (h * f).round());
      },
    );
    final frame = await codec.getNextFrame();
    imagem = frame.image;
    final rgba = await imagem.toByteData(format: ui.ImageByteFormat.rawRgba);
    if (rgba == null) return null;
    final convertida = img.Image.fromBytes(
      width: imagem.width,
      height: imagem.height,
      bytes: rgba.buffer,
      numChannels: 4,
      order: img.ChannelOrder.rgba,
    );
    final jpg = Uint8List.fromList(img.encodeJpg(convertida, quality: 85));
    return FotoPronta(jpg, 'image/jpeg');
  } catch (e) {
    debugPrint('[driver_foto_upload] conversão falhou: $e');
    return null;
  } finally {
    imagem?.dispose();
    codec?.dispose();
  }
}

/// Erros que não melhoram a tentar de novo (pedido errado, ficheiro errado).
bool _naoVaiMelhorar(int? status) =>
    status != null &&
    status >= 400 &&
    status < 500 &&
    status != 408 &&
    status != 429;

class DriverFotoUpload {
  DriverFotoUpload._();

  /// A primeira tentativa + 2.
  static const int tentativas = 3;

  /// Envia uma foto para a Edge `upload-driver-document` e devolve o endereço
  /// a gravar na linha do estafeta (URL assinada; o painel volta a assinar).
  ///
  /// [rotulo] é o nome da foto em minúsculas ("foto do documento"), para a
  /// mensagem do ecrã.
  static Future<String> enviar({
    required Uint8List bytes,
    required String kind,
    required String rotulo,
    Duration espera = const Duration(seconds: 2),
  }) async {
    final pronta = await prepararFotoParaEnvio(bytes);
    if (pronta == null) {
      const msg = 'Esta foto está num formato que não conseguimos ler. '
          'Tira a foto com a câmara ou escolhe outra.';
      await registarFalha(kind, 'formato_ilegivel ${bytes.length} bytes');
      throw const FotoEnvioException(msg, detalhe: 'formato_ilegivel');
    }
    if (pronta.bytes.length > kFotoEstafetaMaxBytes) {
      await registarFalha(kind, 'grande_demais ${pronta.bytes.length} bytes');
      throw FotoEnvioException(
          'A $rotulo tem mais de 10 MB. Tira outra foto, por favor.',
          detalhe: 'file_too_large');
    }

    String? ultimoErro;
    for (var i = 1; i <= tentativas; i++) {
      int? status;
      try {
        final r = await Supabase.instance.client.functions
            .invoke('upload-driver-document', body: {
          'kind': kind,
          'fileBase64': base64Encode(pronta.bytes),
          'contentType': pronta.mime,
        }).timeout(const Duration(seconds: 60));
        status = r.status;
        final data = r.data;
        if (r.status == 200 && data is Map && data['success'] == true) {
          final url = (data['signed_url'] ?? data['url'] ?? data['path'])
              ?.toString();
          if (url != null && url.isNotEmpty) return url;
        }
        ultimoErro = 'HTTP ${r.status}: $data';
      } on FunctionException catch (e) {
        status = e.status;
        ultimoErro = 'HTTP ${e.status}: ${e.details ?? e.reasonPhrase}';
      } on TimeoutException {
        ultimoErro = 'timeout 60 s';
      } catch (e) {
        ultimoErro = e.toString();
      }
      if (_naoVaiMelhorar(status)) break;
      if (i < tentativas) await Future<void>.delayed(espera * i);
    }

    await registarFalha(kind, ultimoErro ?? 'desconhecido');
    throw FotoEnvioException(
        'Não conseguimos enviar a $rotulo. Tenta outra vez.',
        detalhe: ultimoErro);
  }

  /// Uma linha no `e2e_log` com o erro real do servidor. Sem nome nem
  /// telefone (a tabela é de leitura larga): só o início do user_id.
  /// Nunca falha para fora — o registo não pode estragar o envio.
  static Future<void> registarFalha(String kind, String detalhe) async {
    try {
      final sb = Supabase.instance.client;
      final uid = sb.auth.currentUser?.id ?? '';
      final curto = uid.length > 8 ? uid.substring(0, 8) : uid;
      final d = detalhe.length > 400 ? detalhe.substring(0, 400) : detalhe;
      await sb.from('e2e_log').insert({
        'fluxo': 'cadastro-estafeta-fotos',
        'passo': 'upload-$kind',
        'estado': 'falhou',
        'detalhe': 'uid=$curto $d',
        'device': kIsWeb ? 'web' : defaultTargetPlatform.name,
      }).timeout(const Duration(seconds: 8));
    } catch (e) {
      debugPrint('[driver_foto_upload] e2e_log: $e');
    }
  }
}
