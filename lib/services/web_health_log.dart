import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Diagnóstico de saúde da app (web principalmente) para o painel admin.
///
/// Nasceu na missão endereco-web-2026-08-31: uma cliente perdeu duas corridas
/// porque o autocomplete de morada morria em silêncio no browser dela, e só se
/// soube por telefonema. Agora cada falha real fica registada em
/// `web_health_events` e aparece no painel (PT-BR).
///
/// Fire-and-forget: nunca lança, nunca bloqueia a UI. Deduplica por
/// (motivo|ecra) dentro da sessão para não inundar a tabela.
class WebHealthLog {
  static final Set<String> _enviados = <String>{};
  static final Map<String, DateTime> _ultimoRepetido = <String, DateTime>{};

  /// [repetir] (missão tvde-pedir-nunca-trava, 14/10): eventos em que cada
  /// toque conta — `pedido_travado` — passam a dedução por sessão, porque o
  /// alarme ao admin dispara aos 3 do mesmo cliente em 10 min. Mesmo assim
  /// no máximo 1 por 5 s por (motivo|ecrã|detalhe), contra toques nervosos.
  static Future<void> log({
    required String motivo,
    String? ecra,
    String? detalhe,
    bool repetir = false,
  }) async {
    if (repetir) {
      final chave = '$motivo|${ecra ?? ''}|${detalhe ?? ''}';
      final agora = DateTime.now();
      final antes = _ultimoRepetido[chave];
      if (antes != null && agora.difference(antes) < const Duration(seconds: 5)) {
        return;
      }
      _ultimoRepetido[chave] = agora;
    } else {
      final chave = '$motivo|${ecra ?? ''}';
      if (!_enviados.add(chave)) return;
    }
    try {
      final client = Supabase.instance.client;
      await client.from('web_health_events').insert({
        'motivo': motivo,
        'ecra': ecra,
        'detalhe': detalhe,
        'plataforma': kIsWeb ? 'web' : defaultTargetPlatform.name,
        'user_id': client.auth.currentUser?.id,
      });
    } catch (_) {
      // Diagnóstico nunca pode partir a app — falhar a registar é aceitável.
    }
  }
}
