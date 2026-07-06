import 'package:flutter/foundation.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// LIMPEZA — uploads da profissional. Reutiliza os padrões existentes:
///   • foto de perfil  → bucket `avatars` (público, `$uid/avatar.jpg`)
///   • documentos KYC  → bucket `cleaner-documents` (privado, `$uid/<tag>_<ts>.jpg`)
/// Sem service central de upload no projeto — cada fluxo faz uploadBinary
/// direto (RLS: pasta = auth.uid). O admin lê os docs por signed URL.
class CleanerUploadService {
  static SupabaseClient get _sb => Supabase.instance.client;

  /// Envia a foto de perfil para o bucket público `avatars` e devolve o URL
  /// versionado (cache-bust). null se não houver sessão.
  static Future<String?> uploadAvatar(XFile file) async {
    final uid = _sb.auth.currentUser?.id;
    if (uid == null) return null;
    final bytes = await file.readAsBytes();
    final path = '$uid/avatar.jpg';
    await _sb.storage.from('avatars').uploadBinary(
          path,
          bytes,
          fileOptions: const FileOptions(upsert: true, contentType: 'image/jpeg'),
        );
    final publicUrl = _sb.storage.from('avatars').getPublicUrl(path);
    return '$publicUrl?v=${DateTime.now().millisecondsSinceEpoch}';
  }

  /// Envia um documento KYC para o bucket privado `cleaner-documents`.
  /// [tag] ex.: 'id_doc' | 'address_proof'. Devolve o PATH (não URL — o
  /// admin assina depois). null se não houver sessão.
  static Future<String?> uploadDocument(XFile file, String tag) async {
    final uid = _sb.auth.currentUser?.id;
    if (uid == null) return null;
    final bytes = await file.readAsBytes();
    // Bytes vazios (imagem ilegível) davam 400 sem causa clara → mensagem própria.
    if (bytes.isEmpty) {
      throw StateError('empty_file');
    }
    // BUG do 400: o content-type era 'image/$safeExt' → 'image/jpg', que NÃO é um
    // MIME válido (o correto é 'image/jpeg'). O Storage compara o content-type
    // declarado com os bytes reais (JPEG) → mismatch → 400. O avatar funciona
    // porque envia 'image/jpeg'. Mapeamos a extensão a um MIME VÁLIDO.
    final ext = file.name.split('.').last.toLowerCase();
    final (safeExt, mime) = switch (ext) {
      'png' => ('png', 'image/png'),
      'webp' => ('webp', 'image/webp'),
      _ => ('jpg', 'image/jpeg'), // jpg/jpeg/desconhecido → jpeg (padrão do avatar)
    };
    final path = '$uid/${tag}_${DateTime.now().millisecondsSinceEpoch}.$safeExt';
    try {
      await _sb.storage.from('cleaner-documents').uploadBinary(
            path,
            bytes,
            fileOptions: FileOptions(upsert: true, contentType: mime),
          );
    } on StorageException catch (e) {
      // Erro REAL do Storage (status/error/message) — em vez do 400 opaco.
      debugPrint('[CleanerUploadService] doc upload 4xx '
          'status=${e.statusCode} error=${e.error} msg=${e.message}');
      rethrow;
    }
    debugPrint('[CleanerUploadService] doc uploaded ($mime): $path');
    return path;
  }
}
