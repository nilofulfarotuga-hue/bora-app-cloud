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
      await _sb.storage.from('cleaner-documents').uploadBinary(
            path,
            bytes,
            fileOptions: FileOptions(contentType: mime),
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
