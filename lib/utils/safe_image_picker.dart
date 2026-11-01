import 'package:flutter/foundation.dart';
import 'package:image_picker/image_picker.dart';

import 'io_compat.dart' show Platform;

/// Guarda global contra o erro `already_active` do `image_picker`.
///
/// O plugin nativo só permite **um** pedido de seleção ativo de cada vez em
/// toda a app. Toques repetidos no botão (ou dois botões seguidos) abrem um
/// segundo `pickImage` enquanto o primeiro ainda decorre e rebentam a app com
/// "already_active". Este wrapper mantém uma flag partilhada e ignora
/// (devolve `null`) qualquer chamada enquanto uma seleção está em curso.
/// A flag é sempre reposta num `finally`, mesmo em caso de erro.
class SafeImagePicker {
  SafeImagePicker._();

  static bool _isPicking = false;
  static final ImagePicker _picker = ImagePicker();

  /// True enquanto uma seleção nativa está a decorrer.
  static bool get isPicking => _isPicking;

  /// Igual a [ImagePicker.pickImage], mas ignora toques repetidos: se já houver
  /// um pick em curso devolve `null` imediatamente em vez de lançar
  /// `already_active`.
  static Future<XFile?> pickImage({
    required ImageSource source,
    double? maxWidth,
    double? maxHeight,
    int? imageQuality,
    CameraDevice preferredCameraDevice = CameraDevice.rear,
    bool requestFullMetadata = true,
  }) async {
    if (_isPicking) return null;
    _isPicking = true;
    try {
      return await _picker.pickImage(
        source: source,
        maxWidth: maxWidth,
        maxHeight: maxHeight,
        imageQuality: imageQuality,
        preferredCameraDevice: preferredCameraDevice,
        requestFullMetadata: requestFullMetadata,
      );
    } finally {
      _isPicking = false;
    }
  }

  /// Igual a [ImagePicker.pickMultiImage] (várias fotos da galeria de uma
  /// vez), com a mesma guarda contra toques repetidos: se já houver um pick em
  /// curso devolve uma lista vazia. [limit] é o máximo de fotos que o seletor
  /// nativo deixa escolher; a web e os Android antigos ignoram-no, por isso
  /// QUEM CHAMA tem de cortar o resultado (e pode avisar a pessoa).
  /// Missão app-fechar 01/11/2026 (assistente do cliente: várias fotos da
  /// lista ou do carrinho da Glovo/Uber).
  static Future<List<XFile>> pickMultiImage({
    double? maxWidth,
    double? maxHeight,
    int? imageQuality,
    int? limit,
    bool requestFullMetadata = true,
  }) async {
    if (_isPicking) return const <XFile>[];
    _isPicking = true;
    try {
      return await _picker.pickMultiImage(
        maxWidth: maxWidth,
        maxHeight: maxHeight,
        imageQuality: imageQuality,
        // limit < 1 rebenta com ArgumentError; sem limite útil, não se passa.
        limit: (limit != null && limit >= 2) ? limit : null,
        requestFullMetadata: requestFullMetadata,
      );
    } finally {
      _isPicking = false;
    }
  }

  /// Passthrough para [ImagePicker.retrieveLostData] (Android pode matar a
  /// activity durante a câmara e devolver o resultado só depois).
  ///
  /// [Paridade 2026-09-21] SÓ existe no Android: no iPhone e na web o plugin
  /// lança `UnimplementedError: getLostData() has not been implemented`
  /// (4× em debug_crash_logs, último 11/09) — e dois dos chamadores
  /// (driver_signup_screen, register_partner_screen) chamam isto no initState
  /// sem try/catch. Fora do Android devolve "nada perdido" e pronto.
  static Future<LostDataResponse> retrieveLostData() {
    if (kIsWeb || !Platform.isAndroid) {
      return Future.value(LostDataResponse.empty());
    }
    return _picker.retrieveLostData();
  }
}
