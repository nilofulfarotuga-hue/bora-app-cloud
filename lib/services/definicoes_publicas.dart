import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Lê definições NÃO secretas de `platform_settings` mesmo sem sessão
/// (melhorias-paridade 26/10, item 3).
///
/// `platform_settings` só se lê autenticado pela tabela: sem sessão a resposta
/// é `HTTP 200` com `[]` e os ecrãs ficavam com valores de recurso (ex.: a taxa
/// de serviço). A função `get_setting` existe no servidor, está aberta a `anon`
/// e é por ela que o visitante lê os valores reais. Só se pedem aqui chaves
/// públicas (taxas mostradas ao cliente).
///
/// Devolve só as chaves que conseguiu ler (mapa vazio = nada lido). Nunca lança.
Future<Map<String, dynamic>> lerDefinicoesPublicas(List<String> chaves) async {
  final sb = Supabase.instance.client;
  try {
    final linhas =
        await sb.from('platform_settings').select('key, value').inFilter('key', chaves);
    final lista = (linhas as List).cast<Map<String, dynamic>>();
    if (lista.isNotEmpty) {
      return {for (final l in lista) l['key'] as String: l['value']};
    }
  } catch (e) {
    debugPrint('[DefinicoesPublicas] tabela falhou: $e');
  }
  // Sem sessão: uma chamada por chave à get_setting (aberta a anon).
  final out = <String, dynamic>{};
  for (final k in chaves) {
    try {
      final v = await sb.rpc('get_setting', params: {'p_key': k});
      if (v != null) out[k] = v;
    } catch (e) {
      debugPrint('[DefinicoesPublicas] get_setting($k) falhou: $e');
    }
  }
  return out;
}
