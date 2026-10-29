import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Foto do prato numa avaliação (adendo 4 · item 7, 29/10/2026).
///
/// A foto sobe pela Edge Function `upload-order-photo` (balde privado
/// `order-photos`, pasta do próprio cliente) e cola-se à avaliação pela função
/// `rating_anexar_foto`, que confirma que a avaliação é dele. Não há prémio nem
/// tokens por enviar foto. A avaliação já está gravada antes de tudo isto: se
/// a foto falhar, a avaliação fica.
class FotoAvaliacaoService {
  FotoAvaliacaoService._();

  /// O nome do ficheiro tem de começar por `avaliacao_`: é o que a regra de
  /// leitura do balde (`order_photos_select_avaliacao`) e a função do servidor
  /// reconhecem.
  static String nomeDoFicheiro(String orderId, DateTime agora) =>
      'avaliacao_${orderId}_${agora.millisecondsSinceEpoch}.jpg';

  /// O `rating_id` que `submit_rating` devolveu (null se não veio).
  static String? idDaAvaliacao(Object? respostaDoSubmit) {
    if (respostaDoSubmit is! Map) return null;
    final id = respostaDoSubmit['rating_id']?.toString();
    return (id == null || id.isEmpty) ? null : id;
  }

  /// Envia a foto e cola-a à avaliação. Devolve `true` se ficou colada.
  /// Nunca lança.
  static Future<bool> enviar({
    required String orderId,
    required String ratingId,
    required Uint8List bytes,
    SupabaseClient? cliente,
    DateTime? agora,
  }) async {
    final db = cliente ?? Supabase.instance.client;
    try {
      final up = await db.functions.invoke('upload-order-photo', body: {
        'fileBase64': base64Encode(bytes),
        'fileName': nomeDoFicheiro(orderId, agora ?? DateTime.now()),
      }).timeout(const Duration(seconds: 40));
      final data = up.data;
      final url = (data is Map && data['success'] == true)
          ? data['url'] as String?
          : null;
      if (url == null) return false;
      final r = await db.rpc('rating_anexar_foto', params: {
        'p_rating_id': ratingId,
        'p_photo_url': url,
      }).timeout(const Duration(seconds: 10));
      return r is Map && r['ok'] == true;
    } catch (e) {
      debugPrint('[FotoAvaliacao] $e');
      return false;
    }
  }
}
