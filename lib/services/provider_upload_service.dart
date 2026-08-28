import 'package:flutter/foundation.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// PRESTADORES — uploads de quem se candidata a trabalhar (faxineiro, lavador).
///   • foto de perfil  → bucket `avatars` (público, `$uid/avatar.jpg`)
///   • documentos KYC  → bucket privado do papel, `$uid/<tag>_<ts>.jpg`
/// RLS: a pasta é o `auth.uid`. O admin lê os docs por signed URL.
///
/// Era `CleanerUploadService`, com o balde da limpeza cravado no corpo. Quando
/// a candidatura de lavador chegou (2026-08-29), copiar o ficheiro teria criado
/// gémeos: duas cópias da mesma lógica delicada de content-type e de erro do
/// Storage, uma delas a envelhecer em silêncio. O balde passou a argumento.
class ProviderUploadService {
  /// Baldes privados por papel. Ambos com as MESMAS quatro políticas.
  static const bucketFaxineiro = 'cleaner-documents';
  static const bucketLavador = 'washer-documents';

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

  /// Envia um documento KYC para o [bucket] privado do papel.
  /// [tag] ex.: 'id_doc' | 'address_proof'. Devolve o PATH (não URL — o
  /// admin assina depois). null se não houver sessão.
  static Future<String?> uploadDocument(
    XFile file,
    String tag, {
    String bucket = bucketFaxineiro,
  }) async {
    final uid = _sb.auth.currentUser?.id;
    if (uid == null) return null;
    final bytes = await file.readAsBytes();
    // Bytes vazios (imagem ilegível) davam 400 sem causa clara → mensagem própria.
    if (bytes.isEmpty) {
      throw StateError('empty_file');
    }
    // Content-type VÁLIDO por extensão ('image/jpg' não é MIME válido).
    final ext = file.name.split('.').last.toLowerCase();
    final (safeExt, mime) = switch (ext) {
      'png' => ('png', 'image/png'),
      'webp' => ('webp', 'image/webp'),
      _ => ('jpg', 'image/jpeg'), // jpg/jpeg/desconhecido → jpeg (padrão do avatar)
    };
    final path = '$uid/${tag}_${DateTime.now().millisecondsSinceEpoch}.$safeExt';
    try {
      // CAUSA REAL do 400 (2026-07-06): upsert:true faz o Postgres avaliar
      // também as policies de SELECT/UPDATE do bucket, e a policy de admin
      // consultava auth.users — tabela proibida ao role authenticated →
      // "permission denied for table users". Corrigido dos dois lados: a
      // policy passou a ler o claim do JWT (migration
      // 20260706224707_cleaner_docs_admin_policy_jwt) e o upsert saiu daqui
      // (o path tem timestamp — nunca há conflito, o upsert era inútil).
      await _sb.storage.from(bucket).uploadBinary(
            path,
            bytes,
            fileOptions: FileOptions(contentType: mime),
          );
    } on StorageException catch (e) {
      // Erro REAL do Storage (status/error/message) — em vez do 400 opaco.
      debugPrint('[ProviderUploadService] doc upload 4xx '
          'status=${e.statusCode} error=${e.error} msg=${e.message}');
      rethrow;
    }
    debugPrint('[ProviderUploadService] doc uploaded ($mime): $path');
    return path;
  }
}
