/// O prestador de limpeza ou de lavagem com a candidatura PENDENTE envia o que
/// lhe falta sem refazer o cadastro (ordem do Danilo, 22/10; missão
/// docs-reenvio-26-10). Mesmo desenho do estafeta
/// ([EstafetaDocumentosService]).
///
/// O que falta é a regra do painel ([documentosEmFaltaLimpeza] /
/// [documentosEmFaltaLavagem]). Cada envio grava onde o cadastro grava:
///   • foto de perfil → balde `avatars` ([ProviderUploadService.uploadAvatar]);
///     limpeza pela RPC `cleaner_set_profile(p_photo_url)`; lavagem na linha
///     do próprio em `washers.photo_url`.
///   • documentos da lavagem → balde `washer-documents`
///     ([ProviderUploadService.uploadDocument]) + `washers.docs`, juntando ao
///     que lá está (nunca apaga os outros).
///   • materiais da lavagem → `washers.docs.materials_ok/materials_list`.
///   • dados fiscais → `provider_update_legal_fields` (pelo
///     [LegalFieldsController], como no cadastro).
///   • comprovativo de atividade → o ecrã que já existe.
///
/// Lavagem: não há RPC de perfil do lavador e `washer_apply` recusa
/// candidaturas pendentes ('application_already_exists'); a linha é do
/// próprio (RLS `washers_update_own`), por isso grava-se nela, só com a
/// candidatura pendente e confirmando o que ficou gravado.
/// Limpeza: `cleaners.docs` só se escreve pela RPC `cleaner_reenviar_docs`
/// (26/10/2026: só a linha pendente da própria pessoa; junta sem apagar).
/// Casa (31/10/2026): documento → balde `handyman-documents` + RPC
/// `casa_registar_documento`; nunca o balde nem a linha da lavagem.
library;

import 'dart:async';

import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'atividade_service.dart';
import 'driver_documentos.dart' show DocEmFalta;
import 'prestador_documentos.dart';
import 'provider_upload_service.dart';

/// A linha do prestador e o que lhe falta (já com os dados legais juntos).
class EstadoReenvio {
  const EstadoReenvio({required this.linha, required this.falta});
  final Map<String, dynamic> linha;
  final List<DocEmFalta> falta;
}

class PrestadorReenvioService {
  PrestadorReenvioService._();

  static const Duration _tecto = Duration(seconds: 15);

  static const String colunas =
      'id, user_id, approval_status, photo_url, docs, legal_name, nif, '
      'address, birth_date, iban, dsa_self_certified_at';

  /// Regra 1.18: um caso por papel — a Casa nunca cai na tabela da limpeza.
  static String tabela(String papel) => switch (papel) {
        'washer' => 'washers',
        'handyman' => 'casa_profissionais',
        _ => 'cleaners',
      };

  static SupabaseClient get _sb => Supabase.instance.client;

  /// A linha do prestador com sessão (null sem sessão ou sem linha).
  ///
  /// Casa (31/10): os documentos não vivem em `docs` mas em `casa_documentos`
  /// (a política deixa cada um ler os seus); juntam-se em `documentos` para a
  /// regra [documentosEmFaltaCasa].
  static Future<Map<String, dynamic>?> minhaLinha(String papel) async {
    final uid = _sb.auth.currentUser?.id;
    if (uid == null) return null;
    final r = await _sb
        .from(tabela(papel))
        .select(colunas)
        .eq('user_id', uid)
        .maybeSingle()
        .timeout(const Duration(seconds: 10));
    if (r == null) return null;
    final linha = Map<String, dynamic>.from(r);
    if (papel == 'handyman') {
      final docs = await _sb
          .from('casa_documentos')
          .select('id, tipo, oficio, estado')
          .eq('profissional_id', linha['id'] ?? '')
          .timeout(const Duration(seconds: 10));
      linha['documentos'] = List<Map<String, dynamic>>.from(
          (docs as List).whereType<Map>().map(Map<String, dynamic>.from));
    }
    return linha;
  }

  /// O que falta — a mesma regra do painel. Falha aberta: null (sem lista,
  /// nada bloqueia) sem rede, sem sessão ou sem linha.
  static Future<EstadoReenvio?> estado(String papel) async {
    try {
      final linha = await minhaLinha(papel);
      if (linha == null) return null;
      final atividade = await AtividadeService.carregar();
      final atividadeEmFalta = atividade != null &&
          atividade.obrigatoria &&
          atividade.precisaDeEnviar;
      return EstadoReenvio(
        linha: linha,
        falta: agruparDadosLegais(documentosEmFaltaPrestador(papel, linha,
            atividadeEmFalta: atividadeEmFalta)),
      );
    } catch (_) {
      return null;
    }
  }

  /// Foto de perfil ou foto de um documento ([item] com [ComoEnviar.foto]).
  static Future<void> enviarFoto(
      String papel, DocEmFalta item, XFile ficheiro) async {
    if (comoEnviarPrestador(papel, item.chave) != ComoEnviar.foto) {
      throw const ReenvioException(
          'Isto não se envia por aqui. Fala connosco no Suporte.');
    }
    final linha = await _linhaPendente(papel);
    try {
      if (item.chave == 'photo') {
        final url = await ProviderUploadService.uploadAvatar(ficheiro);
        if (url == null || url.isEmpty) throw StateError('not_authenticated');
        await _gravarFoto(papel, url);
      } else {
        // Regra 1.18: um balde por papel — a Casa nunca cai no da lavagem.
        final caminho = await ProviderUploadService.uploadDocument(
          ficheiro,
          item.chave,
          bucket: switch (papel) {
            'cleaner' => ProviderUploadService.bucketFaxineiro,
            'handyman' => ProviderUploadService.bucketCasa,
            _ => ProviderUploadService.bucketLavador,
          },
        );
        if (caminho == null || caminho.isEmpty) {
          throw StateError('not_authenticated');
        }
        if (papel == 'handyman') {
          await _registarDocumentoCasa(item.chave, caminho);
        } else {
          await _gravarDocs(papel, linha, {item.chave: caminho});
        }
      }
    } catch (e) {
      throw ReenvioException(mensagemDeErroReenvio(e));
    }
  }

  /// A pessoa confirmou que tem todos os [materiais] (lavagem).
  static Future<void> confirmarMateriais(
      String papel, List<String> materiais) async {
    if (comoEnviarPrestador(papel, 'materials') != ComoEnviar.materiais) {
      throw const ReenvioException(
          'Isto não se envia por aqui. Fala connosco no Suporte.');
    }
    final linha = await _linhaPendente(papel);
    try {
      await _gravarDocs(papel, linha, {
        'materials_ok': true,
        'materials_list': materiais,
      });
    } catch (e) {
      throw ReenvioException(mensagemDeErroReenvio(e));
    }
  }

  static Future<Map<String, dynamic>> _linhaPendente(String papel) async {
    final Map<String, dynamic>? linha;
    try {
      linha = await minhaLinha(papel);
    } catch (e) {
      throw ReenvioException(mensagemDeErroReenvio(e));
    }
    if (linha == null) {
      throw const ReenvioException(
          'A tua sessão terminou. Entra outra vez na app e tenta de novo.');
    }
    if (linha['approval_status']?.toString() != 'pending') {
      throw const ReenvioException(
          'A tua candidatura já foi analisada. Se precisas de mudar um '
          'documento, fala connosco no Suporte.');
    }
    return linha;
  }

  static Future<void> _gravarFoto(String papel, String url) async {
    // Casa: sem RPC de foto (vai pelo Suporte, ver comoEnviarPrestador). Nunca
    // cair na RPC da limpeza por omissão.
    if (papel == 'handyman') throw const _NaoGravou();
    final Object? r;
    if (papel == 'washer') {
      r = await _sb
          .from('washers')
          .update({'photo_url': url})
          .eq('user_id', _sb.auth.currentUser?.id ?? '')
          .eq('approval_status', 'pending')
          .select('photo_url')
          .maybeSingle()
          .timeout(_tecto);
    } else {
      // A mesma RPC do perfil da limpeza; só a foto muda (o resto é null →
      // COALESCE mantém).
      r = await _sb.rpc('cleaner_set_profile',
          params: {'p_photo_url': url}).timeout(_tecto);
    }
    // Sem falhas caladas: confirma que ficou gravado (0 linhas não é sucesso).
    if (r is! Map || r['photo_url'] != url) throw const _NaoGravou();
  }

  /// Casa (31/10): o documento grava-se pela RPC do contrato, que também serve
  /// para reenviar (`casa_registar_documento` → {id}). Sem id não é sucesso.
  static Future<void> _registarDocumentoCasa(
      String tipo, String caminho) async {
    final res = await _sb.rpc('casa_registar_documento', params: {
      'p_tipo': tipo,
      'p_oficio': null,
      'p_storage_path': caminho,
      'p_numero': null,
      'p_validade': null,
    }).timeout(_tecto);
    final id = res is Map ? res['id']?.toString() : null;
    if (id == null || id.isEmpty) throw const _NaoGravou();
  }

  static Future<void> _gravarDocs(String papel, Map<String, dynamic> linha,
      Map<String, dynamic> novos) async {
    if (papel == 'cleaner') {
      // [26/10/2026] RPC própria: a tabela não deixa a pessoa escrever em docs.
      final res = await _sb.rpc('cleaner_reenviar_docs',
          params: {'p_novos': novos}).timeout(_tecto);
      final docs = res is Map && res['ok'] == true && res['docs'] is Map
          ? Map<String, dynamic>.from(res['docs'] as Map)
          : null;
      if (docs == null ||
          novos.keys.any((k) => docs[k]?.toString() != novos[k]?.toString())) {
        throw const _NaoGravou();
      }
      return;
    }
    if (papel != 'washer') throw const _NaoGravou();
    final r = await _sb
        .from('washers')
        .update({'docs': docsCom(linha, novos)})
        .eq('user_id', _sb.auth.currentUser?.id ?? '')
        .eq('approval_status', 'pending')
        .select('docs')
        .maybeSingle()
        .timeout(_tecto);
    final gravados = r == null ? null : docsDe(r);
    if (gravados == null ||
        novos.keys.any((k) => gravados[k]?.toString() != novos[k]?.toString())) {
      throw const _NaoGravou();
    }
  }
}

/// Erro de envio já em PT-PT (o `toString()` é a própria frase).
class ReenvioException implements Exception {
  const ReenvioException(this.mensagem);
  final String mensagem;
  @override
  String toString() => mensagem;
}

class _NaoGravou implements Exception {
  const _NaoGravou();
}

/// Traduz qualquer falha do envio para uma frase PT-PT — com a causa real do
/// Storage quando é dele (nunca o genérico calado).
String mensagemDeErroReenvio(Object e) {
  if (e is ReenvioException) return e.mensagem;
  if (e is TimeoutException) {
    return 'A ligação está lenta. Tenta outra vez daqui a pouco.';
  }
  if (e is _NaoGravou) {
    return 'Não foi possível gravar. Tenta outra vez — se continuar, fala '
        'connosco no Suporte.';
  }
  if (e is StorageException) {
    return 'Falha ao enviar a foto [${e.statusCode}: ${e.message}]. '
        'Tenta escolher ou tirar a foto de novo.';
  }
  final s = e.toString();
  if (s.contains('not_authenticated') || s.contains('42501')) {
    return 'A tua sessão terminou. Entra outra vez na app e tenta de novo.';
  }
  if (s.contains('empty_file')) {
    return 'Não foi possível ler a imagem. Tira ou escolhe a foto de novo.';
  }
  return 'Não foi possível enviar. Verifica a ligação e tenta outra vez.';
}
