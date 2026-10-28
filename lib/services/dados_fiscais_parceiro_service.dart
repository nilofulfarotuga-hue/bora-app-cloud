import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/dados_fiscais_parceiro.dart';

/// Leitura e correção dos dados fiscais de uma loja parceira (DAC7).
/// Missão boom-burger-2026-10-27, F3. As funções do servidor estão na
/// migração `20261027205938_dados_fiscais_do_parceiro_2026_10_27.sql`.
/// O próprio parceiro grava pelo `LegalFieldsController.save('partner')`
/// (`provider_update_legal_fields`), igual ao registo.
class DadosFiscaisParceiroService {
  DadosFiscaisParceiroService._();

  static const Duration timeout = Duration(seconds: 15);

  /// `parceiro_dados_fiscais`: o dono lê a sua loja; o admin lê qualquer uma.
  static Future<DadosFiscaisParceiro> ler(String? restaurantId) async {
    final r = await Supabase.instance.client.rpc('parceiro_dados_fiscais',
        params: {'p_restaurant_id': restaurantId}).timeout(timeout);
    if (r is! Map) {
      throw StateError('parceiro_dados_fiscais devolveu $r');
    }
    return DadosFiscaisParceiro.fromJson(Map<String, dynamic>.from(r));
  }

  /// `admin_parceiro_atualizar_dados_fiscais` (só admin). Um campo a null
  /// fica como está no servidor. Devolve `{ok, campos, em_falta}`.
  static Future<Map<String, dynamic>> adminAtualizar({
    required String restaurantId,
    String? legalName,
    String? nif,
    String? address,
    String? iban,
    String? birthDateIso,
    String? autocertificadoEmIso,
    String? autocertVersao,
    String? motivo,
  }) async {
    final r = await Supabase.instance.client
        .rpc('admin_parceiro_atualizar_dados_fiscais', params: {
      'p_restaurant_id': restaurantId,
      'p_legal_name': legalName,
      'p_nif': nif,
      'p_address': address,
      'p_iban': iban,
      'p_birth_date': birthDateIso,
      'p_autocertificado_em': autocertificadoEmIso,
      'p_autocert_versao': autocertVersao,
      'p_motivo': motivo,
    }).timeout(timeout);
    return r is Map ? Map<String, dynamic>.from(r) : <String, dynamic>{};
  }
}
