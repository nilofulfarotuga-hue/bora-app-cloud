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
//
// ── CORREÇÃO 2 (2026-08-25, caso real Continente) ───────────────────────────
// O servidor respondeu 200 nas DUAS chamadas e mesmo assim a app voltou ao
// ecrã da câmara e obrigou o estafeta a repetir a foto 3 vezes. Causas
// possíveis, todas tratadas aqui:
//   a) corpo 200 com forma diferente do esperado (String em vez de Map, ou
//      sem `path`) — o `as Map`/`as String` rebentava e a UI lia isso como
//      "upload falhou";
//   b) a ligação morreu DEPOIS de o servidor ter processado (o log do
//      servidor diz 200, o cliente vê erro de rede).
// Regra nova: **qualquer 2xx é sucesso** (o `functions_client` só devolve
// FunctionResponse em 2xx — em >=400 lança FunctionException). O `path` é
// determinístico (`<orderId>.jpg`, upsert:true), logo é seguro derivá-lo
// quando o corpo não o traz. Erro de rede → UMA repetição automática (o
// upsert torna-a inofensiva); só depois é que é falha a sério.

import 'dart:async';
import 'dart:convert';
import '../utils/io_compat.dart';

import 'package:supabase_flutter/supabase_flutter.dart';

class ReceiptUploadService {
  // ⚠️ Feature flag — set false para rollback rápido se Edge Function falhar.
  // Quando false, lança UnimplementedError (legacy disabled).
  static const bool _useEdgeFn = true;

  /// Faz upload da foto do talão e retorna o `path` no bucket receipts.
  /// Throws Exception com mensagem PT-PT em qualquer falha (UI mostra dialog).
  static Future<String> uploadReceipt({
    required String orderId,
    required File photoFile,
    required int totalCents,
  }) async {
    if (_useEdgeFn) {
      return _uploadViaEdgeFunction(orderId, photoFile, totalCents);
    }
    return _uploadDirectToStorage(orderId, photoFile);
  }

  /// Path determinístico que a Edge Function usa (upsert:true). Serve de
  /// fallback quando o corpo do 200 não traz `path`.
  static String fallbackPathFor(String orderId) => '$orderId.jpg';

  static Future<String> _uploadViaEdgeFunction(
    String orderId,
    File photoFile,
    int totalCents,
  ) async {
    final supabase = Supabase.instance.client;
    final bytes = await photoFile.readAsBytes();
    final base64Str = base64Encode(bytes);
    final body = <String, dynamic>{
      'orderId': orderId,
      'fileBase64': base64Str,
      'totalCents': totalCents,
    };

    FunctionResponse response;
    try {
      response = await supabase.functions.invoke('upload-receipt', body: body);
    } catch (e) {
      if (_isNetworkFailure(e)) {
        // A ligação caiu — pode ter caído DEPOIS de o servidor gravar. O
        // upload é upsert no mesmo path, portanto repetir é inofensivo.
        try {
          response =
              await supabase.functions.invoke('upload-receipt', body: body);
        } catch (e2) {
          if (_isNetworkFailure(e2)) {
            throw Exception(
              'Sem ligação ao enviar o talão. Verifica a internet e tenta de novo — a foto ficou guardada.',
            );
          }
          throw _describe(e2);
        }
      } else {
        throw _describe(e);
      }
    }

    // Chegámos aqui ⇒ HTTP 2xx (o functions_client lança em >= 400).
    // A partir deste ponto NUNCA se devolve erro: o servidor aceitou.
    return _pathFrom(response.data, orderId);
  }

  /// Extrai o `path` de um corpo 2xx, tolerando qualquer forma de resposta.
  /// Nunca lança — em último caso devolve o path determinístico.
  static String _pathFrom(dynamic data, String orderId) {
    dynamic decoded = data;
    if (decoded is String) {
      final raw = decoded.trim();
      if (raw.startsWith('{')) {
        try {
          decoded = jsonDecode(raw);
        } catch (_) {
          return fallbackPathFor(orderId);
        }
      } else {
        return raw.isNotEmpty && raw.endsWith('.jpg')
            ? raw
            : fallbackPathFor(orderId);
      }
    }
    if (decoded is Map) {
      final path = decoded['path'];
      if (path is String && path.isNotEmpty) return path;
    }
    return fallbackPathFor(orderId);
  }

  /// Converte um erro do `functions.invoke` numa Exception PT-PT clara.
  /// Só é chamado quando a resposta NÃO foi 2xx (ou o erro não é de rede).
  static Exception _describe(Object e) {
    if (e is FunctionException) {
      final details = e.details;
      String code = '';
      if (details is Map) {
        code = (details['error'] as String?) ?? '';
      } else if (details is String && details.contains('"error"')) {
        try {
          final m = jsonDecode(details);
          if (m is Map) code = (m['error'] as String?) ?? '';
        } catch (_) {}
      }
      switch (code) {
        case 'not_your_order':
          return Exception('Este pedido não está atribuído a si.');
        case 'file_too_large':
          return Exception(
              'Foto muito grande. Tira nova foto com menos qualidade.');
        case 'order_not_found':
          return Exception('Pedido não encontrado. Refresca a app.');
        case 'unauthorized':
          return Exception('Sessão expirada. Inicia sessão de novo.');
      }
      return Exception(
        'O servidor recusou o talão (código ${e.status}${code.isNotEmpty ? " — $code" : ""}).',
      );
    }
    return Exception('Falha ao enviar o talão: $e');
  }

  /// Falha de transporte (não chegou resposta do servidor). Distinta de uma
  /// resposta com código de erro, que é decisão do servidor.
  static bool _isNetworkFailure(Object e) {
    if (e is FunctionException) return false;
    if (e is TimeoutException) return true;
    final s = e.toString().toLowerCase();
    return s.contains('socketexception') ||
        s.contains('clientexception') ||
        s.contains('httpexception') ||
        s.contains('failed host lookup') ||
        s.contains('connection') ||
        s.contains('handshake') ||
        s.contains('timeout') ||
        s.contains('network');
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
