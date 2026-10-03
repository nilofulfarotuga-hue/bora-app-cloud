import 'package:flutter/foundation.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// LAVAGEM AUTO — fotos do carro.
///
/// Bucket `carwash-photos` é PRIVADO (padrão do `order-photos`). Guardamos o
/// PATH, nunca um URL público; para mostrar a foto pede-se um signed URL.
///
/// Caminho canónico — tem de bater certo com as policies de Storage, que
/// leem o booking_id do primeiro segmento:
///   <booking_id>/<before|after|client>/<ficheiro>
class CarwashUploadService {
  static const bucket = 'carwash-photos';

  static SupabaseClient get _sb => Supabase.instance.client;

  /// Envia uma foto e devolve o PATH no bucket. Lança em erro real.
  static Future<String> upload(
    XFile file, {
    required String bookingId,
    required String kind, // before | after | client
    required String tag, // frente | tras | esquerda | direita | livre
  }) async {
    final bytes = await file.readAsBytes();
    // Bytes vazios davam 400 sem causa clara → mensagem própria.
    if (bytes.isEmpty) throw StateError('empty_file');

    // Content-type VÁLIDO por extensão ('image/jpg' não é MIME válido).
    final ext = file.name.split('.').last.toLowerCase();
    final (safeExt, mime) = switch (ext) {
      'png' => ('png', 'image/png'),
      'webp' => ('webp', 'image/webp'),
      _ => ('jpg', 'image/jpeg'),
    };

    final path =
        '$bookingId/$kind/${tag}_${DateTime.now().millisecondsSinceEpoch}.$safeExt';

    try {
      // Sem upsert: o path tem timestamp, nunca há conflito — e o upsert
      // obrigaria o Postgres a avaliar também as policies de SELECT/UPDATE.
      await _sb.storage.from(bucket).uploadBinary(
            path,
            bytes,
            fileOptions: FileOptions(contentType: mime),
          );
    } on StorageException catch (e) {
      debugPrint('[CarwashUpload] falhou status=${e.statusCode} '
          'error=${e.error} msg=${e.message}');
      rethrow;
    }
    debugPrint('[CarwashUpload] ok ($mime): $path');
    return path;
  }

  /// Signed URL para mostrar uma foto do bucket privado.
  static Future<String?> signedUrl(String path, {int expiresSeconds = 3600}) async {
    if (path.isEmpty) return null;
    try {
      return await _sb.storage.from(bucket).createSignedUrl(path, expiresSeconds);
    } catch (e) {
      debugPrint('[CarwashUpload] signedUrl falhou ($path) => $e');
      return null;
    }
  }
}
