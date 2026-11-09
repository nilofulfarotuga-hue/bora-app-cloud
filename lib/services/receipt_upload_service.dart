// BUG #1 fix (sessão exec post-test 2026-05-12) — ReceiptUploadService
//
// Upload de foto de talão via Edge Function `upload-receipt` em vez de
// `storage.from('receipts').upload()` directo. Padrão idêntico a
// `upload-avatar` que funciona em produção.
//
// Vantagens:
// - Service_role bypass de rate limits storage
// - Validação server-side completa (order ownership, file size, mime)
// - Resposta erro estruturada com mensagens PT-PT por código
//
// Feature flag `_USE_EDGE_FN` para rollback rápido se necessário.

import 'dart:convert';
import '../utils/io_compat.dart';

import 'package:supabase_flutter/supabase_flutter.dart';

class ReceiptUploadService {
  // ⚠️ Feature flag — set false para rollback rápido se Edge Function falhar.
  // Quando false, lança UnimplementedError (legacy disabled).
  static const bool _useEdgeFn = true;

  /// Faz upload da foto do talão e retorna o `path` no bucket receipts.
  /// Throws Exception com mensagem PT-PT em qualquer falha (UI mostra dialog).
  ///
  /// M1 08/11/2026: [fotoId] é o MESMO em todas as tentativas da MESMA foto
  /// (o servidor grava AAAA/MM/<pedido>/<fotoId>.jpg sem substituir; repetir
  /// devolve o mesmo caminho). [tiradaEm] decide o mês da pasta. Os dois são
  /// opcionais: sem eles o pedido ao servidor fica igual ao de antes.
  static Future<String> uploadReceipt({
    required String orderId,
    required File photoFile,
    required int totalCents,
    String? fotoId,
    DateTime? tiradaEm,
  }) async {
    if (_useEdgeFn) {
      return _uploadViaEdgeFunction(
          orderId, photoFile, totalCents, fotoId, tiradaEm);
    }
    return _uploadDirectToStorage(orderId, photoFile);
  }

  static Future<String> _uploadViaEdgeFunction(
    String orderId,
    File photoFile,
    int totalCents,
    String? fotoId,
    DateTime? tiradaEm,
  ) async {
    final supabase = Supabase.instance.client;
    final bytes = await photoFile.readAsBytes();
    final base64Str = base64Encode(bytes);

    final response = await supabase.functions.invoke(
      'upload-receipt',
      body: {
        'orderId': orderId,
        'fileBase64': base64Str,
        'totalCents': totalCents,
        if (fotoId != null) 'fotoId': fotoId,
        if (tiradaEm != null) 'tiradaEm': tiradaEm.toUtc().toIso8601String(),
      },
    );

    if (response.data == null) {
      throw Exception('Upload falhou: resposta vazia do servidor.');
    }

    final data = response.data as Map<String, dynamic>;
    if (data['success'] != true) {
      final errorMsg = data['error'] as String? ?? 'unknown';
      final detail = data['detail'] as String? ?? '';

      // Mensagens específicas PT-PT por error code
      if (errorMsg == 'not_your_order') {
        throw Exception('Este pedido não está atribuído a si.');
      }
      if (errorMsg == 'file_too_large') {
        throw Exception(
          'Foto muito grande. Tira nova foto com menos qualidade.',
        );
      }
      if (errorMsg == 'order_not_found') {
        throw Exception('Pedido não encontrado. Refresca a app.');
      }
      if (errorMsg == 'unauthorized') {
        throw Exception('Sessão expirada. Inicia sessão de novo.');
      }

      throw Exception(
        'Upload falhou: $errorMsg${detail.isNotEmpty ? " ($detail)" : ""}',
      );
    }

    // M1 08/11/2026: o servidor novo confirma que o ficheiro existe e não
    // está vazio. Se responde com `confirmado`, tem de ser true; o servidor
    // antigo não manda o campo e fica tudo como antes.
    if (data.containsKey('confirmado') && data['confirmado'] != true) {
      throw Exception('Upload não confirmado pelo servidor');
    }

    return data['path'] as String;
  }

  static Future<String> _uploadDirectToStorage(
    String orderId,
    File photoFile,
  ) async {
    // Código legacy desactivado — feature-flag para rollback emergencial.
    // Implementação original em git history (commits e4179bb / 789b699).
    throw UnimplementedError(
      'Legacy storage upload desactivado — use Edge Function via feature-flag.',
    );
  }
}
