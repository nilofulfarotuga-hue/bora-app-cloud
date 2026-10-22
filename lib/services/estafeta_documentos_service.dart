/// O estafeta com a conta em análise envia o que lhe falta sem refazer o
/// cadastro (missão cadastro-estafeta-fotos-22-10).
///
/// Grava pelo RPC do próprio cadastro, `driver_register_or_update`, que já é
/// do próprio estafeta (auth.uid()) e só preenche os campos que recebe
/// (COALESCE). Nome, telefone e veículo vão iguais aos que estão na linha,
/// por isso nada mais muda. Não mexe no estado da candidatura.
library;

import 'dart:async';

import 'package:supabase_flutter/supabase_flutter.dart';

import 'atividade_service.dart';
import 'driver_documentos.dart';

class EstafetaDocumentosService {
  EstafetaDocumentosService._();

  static const String colunas =
      'id, user_id, name, phone, vehicle_type, license_plate, photo_url, '
      'registration_selfie_url, document_photo_url, document_number, '
      'vehicle_photo_url, vehicle_doc_url, iban, approval_status';

  static SupabaseClient get _sb => Supabase.instance.client;

  /// A linha do estafeta com sessão (null sem sessão, sem linha ou sem rede).
  static Future<Map<String, dynamic>?> minhaLinha() async {
    final uid = _sb.auth.currentUser?.id;
    if (uid == null) return null;
    final r = await _sb
        .from('drivers')
        .select(colunas)
        .eq('user_id', uid)
        .maybeSingle()
        .timeout(const Duration(seconds: 10));
    return r == null ? null : Map<String, dynamic>.from(r);
  }

  /// O que falta a esta conta — a mesma regra do painel.
  static Future<List<DocEmFalta>?> emFalta() async {
    try {
      final linha = await minhaLinha();
      if (linha == null) return null;
      final atividade = await AtividadeService.carregar();
      final atividadeEmFalta =
          atividade != null && atividade.obrigatoria && atividade.precisaDeEnviar;
      return documentosEmFaltaEstafeta(linha,
          atividadeEmFalta: atividadeEmFalta);
    } catch (_) {
      return null; // falha aberta: sem lista, nada bloqueia
    }
  }

  /// Grava um item ([chave] de [DocEmFalta]) com [valor] (endereço da foto
  /// ou texto). Lança uma mensagem PT-PT quando não dá.
  static Future<void> gravar(String chave, String valor) async {
    final parametro = parametroDoRegisto(chave);
    if (parametro == null) {
      throw const EstafetaDocumentoException(
          'Isto não se envia por aqui. Fala connosco no Suporte.');
    }
    final linha = await minhaLinha();
    if (linha == null) {
      throw const EstafetaDocumentoException(
          'A tua sessão terminou. Entra outra vez na app e tenta de novo.');
    }
    final estado = linha['approval_status']?.toString();
    if (estado != 'pending' && estado != 'rejected') {
      throw const EstafetaDocumentoException(
          'A tua conta já foi analisada. Se precisas de mudar um documento, '
          'fala connosco no Suporte.');
    }
    final Object? r;
    try {
      r = await _sb.rpc('driver_register_or_update', params: {
        'p_name': linha['name'],
        'p_phone': linha['phone'],
        'p_vehicle_type': linha['vehicle_type'],
        parametro: valor,
      }).timeout(const Duration(seconds: 15));
    } on TimeoutException {
      throw const EstafetaDocumentoException(
          'A ligação está lenta. Tenta outra vez daqui a pouco.');
    } catch (_) {
      throw const EstafetaDocumentoException(
          'Não foi possível gravar. Verifica a ligação e tenta outra vez.');
    }
    if (r is! Map || r['success'] != true) {
      throw const EstafetaDocumentoException(
          'Não foi possível gravar. Tenta outra vez.');
    }
  }
}

class EstafetaDocumentoException implements Exception {
  const EstafetaDocumentoException(this.mensagem);
  final String mensagem;
  @override
  String toString() => mensagem;
}
