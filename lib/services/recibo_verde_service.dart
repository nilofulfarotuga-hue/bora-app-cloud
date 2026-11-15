import 'dart:typed_data';

import 'package:supabase_flutter/supabase_flutter.dart';

/// Missão 12 recibos-verdes-15-11 (R2): o recibo verde do mês para TODOS os
/// prestadores (estafeta, limpeza, lavagem, Casa). Contrato do servidor em
/// `docs/propostas/recibos-verdes-15-11/CONTRATO.md` (secções 2 e 5).
///
/// A app não calcula nada: o total, as linhas, o adquirente e a trava vêm do
/// servidor. Aqui só se escolhe o caminho do ficheiro, se envia o ficheiro e
/// depois se marca o recibo (por esta ordem: repetir as duas é seguro).
class ReciboVerdeService {
  ReciboVerdeService._();

  static const bucket = 'recibos-verdes';

  /// 10 MB, como o bucket.
  static const tamanhoMaximo = 10 * 1024 * 1024;

  static const extensoes = ['pdf', 'jpg', 'jpeg', 'png'];

  /// `{user_id}/{ano}-{mês com 2 dígitos}.{ext}` — o único caminho que o
  /// servidor aceita em `driver_mark_invoice_issued(p_pdf_path)`.
  static String caminho(String userId, int ano, int mes, String nomeFicheiro) {
    final ext = extensao(nomeFicheiro);
    return '$userId/$ano-${mes.toString().padLeft(2, '0')}.$ext';
  }

  /// Extensão em minúsculas; desconhecida → null.
  static String? extensaoOuNull(String nomeFicheiro) {
    final i = nomeFicheiro.lastIndexOf('.');
    if (i < 0) return null;
    final e = nomeFicheiro.substring(i + 1).toLowerCase();
    return extensoes.contains(e) ? e : null;
  }

  static String extensao(String nomeFicheiro) =>
      extensaoOuNull(nomeFicheiro) ?? 'pdf';

  static String tipoMime(String ext) => switch (ext) {
        'png' => 'image/png',
        'jpg' || 'jpeg' => 'image/jpeg',
        _ => 'application/pdf',
      };

  /// true quando o servidor ainda não tem as funções novas (R1a por aplicar):
  /// a app volta ao cartão antigo, só com as entregas.
  static bool faltaFuncaoNoServidor(Object e) {
    final t = e.toString();
    return t.contains('PGRST202') ||
        t.contains('Could not find the function') ||
        (t.contains('does not exist') && t.contains('function'));
  }

  /// Frase simples (PT-PT) para cada erro do contrato.
  static String mensagemDoErro(Object e) {
    final t = e.toString();
    if (t.contains('numero_em_falta')) {
      return 'Escreve o número do recibo verde.';
    }
    if (t.contains('pdf_caminho_invalido') ||
        t.contains('pdf_nao_encontrado')) {
      return 'O ficheiro do recibo não chegou. Escolhe-o outra vez e volta a enviar.';
    }
    if (t.contains('ficheiro_grande') ||
        t.contains('Payload too large') ||
        t.contains('413')) {
      return 'O ficheiro tem mais de 10 MB. Escolhe um PDF ou uma foto mais pequena.';
    }
    if (t.contains('ficheiro_tipo')) {
      return 'Só se aceita PDF ou foto (JPG ou PNG).';
    }
    if (t.contains('mes_invalido')) {
      return 'Este mês não é válido. Atualiza a página e tenta outra vez.';
    }
    if (t.contains('sem_sessao')) {
      return 'A tua sessão terminou. Entra outra vez na app.';
    }
    if (t.contains('sem_permissao')) {
      return 'Só podes ver e enviar o teu próprio recibo.';
    }
    return 'Não foi possível enviar. Verifica a internet e tenta outra vez.';
  }

  static SupabaseClient get _sb => Supabase.instance.client;

  /// O recibo do mês da própria pessoa (`prestador`), ou null se não trabalhou.
  /// Devolve o resumo inteiro (adquirente, regras, prestador).
  static Future<Map<String, dynamic>> resumo(int ano, int mes) async {
    final r = await _sb.rpc('prestador_recibo_mensal_resumo',
        params: {'p_year': ano, 'p_month': mes});
    return r is Map ? Map<String, dynamic>.from(r) : <String, dynamic>{};
  }

  /// Se a pessoa está retida por falta de recibo (`retido`, `texto_app`,
  /// `por_pagar.total_cents`, `meses_em_falta`).
  static Future<Map<String, dynamic>> trava() async {
    final r = await _sb.rpc('prestador_recibo_trava');
    return r is Map ? Map<String, dynamic>.from(r) : <String, dynamic>{};
  }

  /// Envia o ficheiro e SÓ DEPOIS marca o recibo. Funções injetáveis para os
  /// testes (sem rede).
  static Future<Map<String, dynamic>> enviarEMarcar({
    required int ano,
    required int mes,
    required String numero,
    required Uint8List bytes,
    required String nomeFicheiro,
    DateTime? data,
    String? userId,
    Future<void> Function(String caminho, Uint8List bytes, String mime)? enviar,
    Future<dynamic> Function(Map<String, dynamic> params)? marcar,
  }) async {
    final n = numero.trim();
    if (n.isEmpty) throw StateError('numero_em_falta');
    final ext = extensaoOuNull(nomeFicheiro);
    if (ext == null) throw StateError('ficheiro_tipo');
    if (bytes.length > tamanhoMaximo) throw StateError('ficheiro_grande');
    final uid = userId ?? _sb.auth.currentUser?.id;
    if (uid == null) throw StateError('sem_sessao');
    final path = caminho(uid, ano, mes, nomeFicheiro);
    final mime = tipoMime(ext);

    await (enviar ??
        (p, b, m) => _sb.storage
            .from(bucket)
            .uploadBinary(p, b,
                fileOptions: FileOptions(contentType: m, upsert: true))
            .timeout(const Duration(seconds: 60)))(path, bytes, mime);

    final params = <String, dynamic>{
      'p_year': ano,
      'p_month': mes,
      'p_numero': n,
      'p_pdf_path': path,
      if (data != null)
        'p_data':
            '${data.year}-${data.month.toString().padLeft(2, '0')}-${data.day.toString().padLeft(2, '0')}',
    };
    final r = await (marcar ??
        (p) => _sb.rpc('driver_mark_invoice_issued', params: p))(params);
    return r is Map ? Map<String, dynamic>.from(r) : <String, dynamic>{};
  }
}
