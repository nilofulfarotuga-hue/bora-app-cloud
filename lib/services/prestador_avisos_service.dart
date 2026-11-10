import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Avisos legais que cada prestador tem de ler uma vez por versão
/// (missão fechar-tudo-2026-11-10, E4 — Diretiva (UE) 2024/2831, art. 9.º).
///
/// Servidor: tabela `prestador_avisos_lidos` (RLS: cada um lê/insere o seu,
/// admin lê tudo) e RPC `prestador_marcar_aviso_lido` (idempotente).
class PrestadorAvisos {
  PrestadorAvisos._();

  static const Duration tempoMaximo = Duration(seconds: 8);

  /// Decide se o ecrã aparece. Função pura (testável sem Supabase):
  /// - sem resposta do servidor (sem sessão, sem rede) → NÃO aparece
  ///   (falha aberta, como o `TermsGate`: um erro de rede nunca tranca
  ///   ninguém; volta a perguntar no próximo arranque);
  /// - já leu esta versão → não aparece;
  /// - nunca leu, ou só leu versões antigas → aparece (uma vez por versão).
  static bool precisaDeMostrar({
    required bool respondeu,
    required Iterable<String> versoesLidas,
    required String versaoAtual,
  }) =>
      respondeu && !versoesLidas.contains(versaoAtual);

  /// As versões do [aviso] que ESTA pessoa já leu. `respondeu` false = sem
  /// sessão ou erro. Filtra pelo próprio `user_id`: a RLS deixa o admin ver as
  /// linhas de todos, e um admin que também é prestador não pode passar à
  /// frente por causa da leitura de outra pessoa.
  static Future<({bool respondeu, Set<String> versoes})> versoesLidas(
      String aviso) async {
    try {
      final sb = Supabase.instance.client;
      final uid = sb.auth.currentUser?.id;
      if (uid == null) return (respondeu: false, versoes: <String>{});
      final rows = await sb
          .from('prestador_avisos_lidos')
          .select('versao')
          .eq('user_id', uid)
          .eq('aviso', aviso)
          .timeout(tempoMaximo);
      return (
        respondeu: true,
        versoes: {
          for (final r in (rows as List).whereType<Map>()) '${r['versao']}',
        },
      );
    } catch (e) {
      debugPrint('[PrestadorAvisos] ler $aviso: $e');
      return (respondeu: false, versoes: <String>{});
    }
  }

  /// Grava "Li e percebi". Lança se não gravar (o ecrã mostra o erro e fica).
  static Future<void> marcarLido({
    required String aviso,
    required String versao,
    String? papel,
  }) async {
    await Supabase.instance.client.rpc('prestador_marcar_aviso_lido', params: {
      'p_aviso': aviso,
      'p_versao': versao,
      'p_papel': papel,
      'p_plataforma': kIsWeb ? 'web' : defaultTargetPlatform.name,
    }).timeout(tempoMaximo);
  }

  /// O utilizador com sessão, ou null (sem Supabase iniciado, nos testes).
  static String? uidAtual() {
    try {
      return Supabase.instance.client.auth.currentUser?.id;
    } catch (_) {
      return null;
    }
  }
}
