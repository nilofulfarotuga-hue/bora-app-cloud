import 'package:image_picker/image_picker.dart';

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

  /// Passthrough para [ImagePicker.retrieveLostData] (Android pode matar a
  /// activity durante a câmara e devolver o resultado só depois).
  static Future<LostDataResponse> retrieveLostData() =>
      _picker.retrieveLostData();
}
