import 'package:flutter/foundation.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'driver_foto_upload.dart' show FotoPronta, prepararFotoParaEnvio;

/// PRESTADORES — uploads de quem se candidata a trabalhar (faxineiro, lavador).
///   • foto de perfil  → bucket `avatars` (público, `$uid/avatar.jpg`)
///   • documentos KYC  → bucket privado do papel, `$uid/<tag>_<ts>.jpg`
/// RLS: a pasta é o `auth.uid`. O admin lê os docs por signed URL.
///
/// Era `CleanerUploadService`, com o balde da limpeza cravado no corpo. Quando
/// a candidatura de lavador chegou (2026-08-29), copiar o ficheiro teria criado
/// gémeos: duas cópias da mesma lógica delicada de content-type e de erro do
/// Storage, uma delas a envelhecer em silêncio. O balde passou a argumento.
///
/// 22/10/2026 (documentos de todos os papéis): o tipo vem dos primeiros bytes
/// e uma foto HEIC do iPhone é convertida para JPEG antes de sair (antes saía
/// rotulada `image/jpeg` e o painel não a conseguia mostrar). Sem sessão já
/// não devolve null em silêncio — a candidatura gravava-se sem o documento.
class ProviderUploadService {
  /// Baldes privados por papel. Ambos com as MESMAS quatro políticas.
  static const bucketFaxineiro = 'cleaner-documents';
  static const bucketLavador = 'washer-documents';

  static SupabaseClient get _sb => Supabase.instance.client;

  /// Envia a foto de perfil para o bucket público `avatars` e devolve o URL
  /// versionado (cache-bust). null se não houver sessão.
  static Future<String?> uploadAvatar(XFile file) async {
    final uid = _sb.auth.currentUser?.id;
    if (uid == null) throw StateError('not_authenticated');
    final foto = await _preparar(await file.readAsBytes());
    final path = '$uid/avatar.jpg';
    await _sb.storage.from('avatars').uploadBinary(
          path,
          foto.bytes,
          fileOptions: FileOptions(upsert: true, contentType: foto.mime),
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
    if (uid == null) throw StateError('not_authenticated');
    // Tipo pelos bytes (o nome engana: o iPhone chama .jpg a fotos HEIC).
    final foto = await _preparar(await file.readAsBytes());
    final bytes = foto.bytes;
    final mime = foto.mime;
    final safeExt = switch (mime) {
      'image/png' => 'png',
      'image/webp' => 'webp',
      _ => 'jpg',
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

  /// Bytes vazios ou ilegíveis dão 'empty_file' (a candidatura já tem a frase
  /// certa para isso: "Não foi possível ler a imagem…").
  static Future<FotoPronta> _preparar(Uint8List bytes) async {
    if (bytes.isEmpty) throw StateError('empty_file');
    final foto = await prepararFotoParaEnvio(bytes);
    if (foto == null) throw StateError('empty_file: formato ilegivel');
    return foto;
  }
}
