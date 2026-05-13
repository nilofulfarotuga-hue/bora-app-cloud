// BUG #7 fix (2026-05-13) — OrderPhotoUploadService
//
// Upload de foto da encomenda (sendPackage / carryGroceries) via Edge
// Function `upload-order-photo` em vez de `storage.from('order-photos')`
// directo. Bypassa RLS storage com service_role server-side.
//
// Padrão idêntico a ReceiptUploadService (upload-receipt) que funciona em
// produção desde 2026-05-12.
//
// Feature flag `_useEdgeFn` para rollback rápido se necessário.

import 'dart:convert';
import 'dart:io';

import 'package:supabase_flutter/supabase_flutter.dart';

class OrderPhotoUploadService {
  // Feature flag — set false para rollback rápido se Edge Function falhar.
  // Quando false, lança UnimplementedError (legacy storage upload disabled).
  static const bool _useEdgeFn = true;

  /// Faz upload da foto da encomenda e retorna a URL pública.
  /// [pathPrefix] distingue 'package' (sendPackage) vs 'groceries' (carry).
  /// Throws Exception com mensagem PT-PT em qualquer falha.
  static Future<String> uploadOrderPhoto({
    required File photoFile,
    required String pathPrefix,
  }) async {
    if (_useEdgeFn) {
      return _uploadViaEdgeFunction(photoFile, pathPrefix);
    }
    throw UnimplementedError(
      'Legacy storage upload desactivado — use Edge Function via feature-flag.',
    );
  }

  static Future<String> _uploadViaEdgeFunction(
    File photoFile,
    String pathPrefix,
  ) async {
    final supabase = Supabase.instance.client;
    final bytes = await photoFile.readAsBytes();
    final base64Str = base64Encode(bytes);
    final fileName =
        '${pathPrefix}_${DateTime.now().millisecondsSinceEpoch}.jpg';

    final response = await supabase.functions.invoke(
      'upload-order-photo',
      body: {
        'fileBase64': base64Str,
        'fileName': fileName,
      },
    );

    if (response.data == null) {
      throw Exception('Upload falhou: resposta vazia do servidor.');
    }

    final data = response.data as Map<String, dynamic>;
    if (data['success'] != true) {
      final errorMsg = data['error'] as String? ?? 'unknown';
      final detail = data['detail'] as String? ?? '';

      if (errorMsg == 'file_too_large') {
        throw Exception(
          'Foto muito grande. Tira nova foto com menos qualidade.',
        );
      }
      if (errorMsg == 'invalid_base64') {
        throw Exception('Foto corrompida. Tira novamente.');
      }
      if (errorMsg == 'unauthorized') {
        throw Exception('Sessão expirada. Inicia sessão de novo.');
      }
      if (errorMsg == 'upload_failed') {
        throw Exception('Erro ao enviar foto. Tenta de novo.');
      }
      if (errorMsg == 'env_missing') {
        throw Exception('Configuração do servidor em falta. Contacte o suporte.');
      }

      throw Exception(
        'Upload falhou: $errorMsg${detail.isNotEmpty ? " ($detail)" : ""}',
      );
    }

    return data['url'] as String;
  }
}
