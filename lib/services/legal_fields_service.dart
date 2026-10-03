import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Erro já traduzido para quem está a usar a app (PT-PT). O `toString()`
/// devolve a própria mensagem, para os `catch (e)` genéricos dos ecrãs não
/// mostrarem lixo técnico se apanharem isto antes do `on` específico.
class LegalFieldsException implements Exception {
  const LegalFieldsException(this.message, {this.code});

  final String message;

  /// Código curto para diagnóstico (`timeout`, `42501`, `nif_invalido`…).
  final String? code;

  @override
  String toString() => message;
}

/// D3 — grava os dados legais e fiscais do próprio prestador
/// (`provider_update_legal_fields`, por `auth.uid()`).
///
/// Contrato do servidor (migração `20260923_ronda_d3_conformidade_prestadores`):
/// devolve `{ok, role, missing[], self_certified_at}`; com `ok=false` traz
/// `error='registo_nao_encontrado'`. Lança `nif_invalido`, `iban_invalido`,
/// `menor_de_idade`, `invalid_role` e `unauthenticated` (42501) como excepção.
class LegalFieldsService {
  LegalFieldsService._();

  static const Duration timeout = Duration(seconds: 15);

  /// Papéis aceites por `p_role`.
  static const Set<String> roles = {
    'driver',
    'partner',
    'cleaner',
    'washer',
    'provider',
  };

  static const String _rpc = 'provider_update_legal_fields';

  /// Grava os seis campos e só devolve quando o servidor confirma que não
  /// falta nada. Qualquer falha vem como [LegalFieldsException] com a
  /// mensagem pronta a mostrar.
  static Future<Map<String, dynamic>> saveLegalFields({
    required String role,
    required String legalName,
    required String nif,
    required String address,
    required String iban,
    required DateTime birthDate,
    required bool selfCertify,
  }) async {
    assert(roles.contains(role), 'papel desconhecido: $role');
    final params = <String, dynamic>{
      'p_role': role,
      'p_legal_name': legalName.trim(),
      'p_nif': nif.replaceAll(RegExp(r'\D'), ''),
      'p_address': address.trim(),
      'p_iban': iban.replaceAll(RegExp(r'\s'), '').toUpperCase(),
      'p_birth_date': _isoDate(birthDate),
      'p_self_certify': selfCertify,
    };
    try {
      final res = await Supabase.instance.client
          .rpc(_rpc, params: params)
          .timeout(timeout);
      final map =
          res is Map ? Map<String, dynamic>.from(res) : <String, dynamic>{};
      final missing = (map['missing'] as List?)
              ?.map((e) => e.toString())
              .where((e) => e.isNotEmpty)
              .toList() ??
          const <String>[];
      if (map['ok'] != true) {
        throw LegalFieldsException(_messageForResult(map, missing),
            code: map['error']?.toString() ?? 'nao_ok');
      }
      if (missing.isNotEmpty) {
        // PADRAO_BORA §3.5: verifica-se o efeito, não o invólucro. Se o
        // servidor ainda diz que falta algo depois de enviarmos tudo, não se
        // declara sucesso — a ativação ficaria bloqueada sem ninguém saber.
        throw LegalFieldsException(
          'O servidor diz que ainda falta: ${missing.map(_labelMissing).join(', ')}. '
          'Confere os campos e tenta de novo.',
          code: 'incompleto',
        );
      }
      return map;
    } on LegalFieldsException {
      rethrow;
    } catch (e) {
      debugPrint('LegalFieldsService.saveLegalFields($role) falhou => $e');
      throw LegalFieldsException(messageFor(e), code: _codeFor(e));
    }
  }

  /// Traduz qualquer erro da chamada para uma frase PT-PT.
  static String messageFor(Object error) {
    if (error is LegalFieldsException) return error.message;
    if (error is TimeoutException) {
      return 'A gravação dos dados fiscais demorou demasiado. Verifica a '
          'ligação à internet e tenta de novo.';
    }
    if (error is AuthException) {
      return 'A tua sessão expirou. Volta a entrar e tenta de novo.';
    }
    if (error is PostgrestException) {
      final m = '${error.code ?? ''} ${error.message} ${error.details ?? ''} '
              '${error.hint ?? ''}'
          .toLowerCase();
      if (m.contains('nif_invalido')) {
        return 'O NIF não foi aceite — confirma os 9 dígitos.';
      }
      if (m.contains('iban_invalido')) {
        return 'O IBAN não foi aceite — tem de ser PT seguido de 23 dígitos.';
      }
      if (m.contains('menor_de_idade')) {
        return 'Só podes trabalhar com a Bora a partir dos 18 anos.';
      }
      if (m.contains('invalid_role')) {
        return 'Tipo de conta inválido. Avisa o suporte.';
      }
      if (error.code == '42501' ||
          m.contains('unauthenticated') ||
          m.contains('jwt')) {
        return 'A tua sessão expirou. Volta a entrar e tenta de novo.';
      }
      if (error.code == 'PGRST202' ||
          m.contains('could not find the function')) {
        return 'A gravação dos dados fiscais ainda não está disponível. '
            'Tenta mais tarde — se continuar, avisa o suporte.';
      }
      return 'Não foi possível guardar os dados fiscais '
          '(${error.code ?? 'erro'}). Tenta de novo.';
    }
    final m = error.toString().toLowerCase();
    if (m.contains('socketexception') ||
        m.contains('clientexception') ||
        m.contains('failed host lookup') ||
        m.contains('connection')) {
      return 'Sem ligação à internet. Verifica a rede e tenta de novo.';
    }
    return 'Não foi possível guardar os dados fiscais. Tenta de novo — se '
        'continuar, avisa o suporte.';
  }

  static String _codeFor(Object error) {
    if (error is TimeoutException) return 'timeout';
    if (error is PostgrestException) return error.code ?? 'postgrest';
    if (error is AuthException) return 'auth';
    return 'unknown';
  }

  static String _messageForResult(
      Map<String, dynamic> map, List<String> missing) {
    final error = map['error']?.toString();
    if (error == 'registo_nao_encontrado') {
      return 'Ainda não encontrámos o teu registo de ${_roleLabel(map['role'])}. '
          'Tenta de novo daqui a instantes — se continuar, avisa o suporte.';
    }
    final semRegisto = missing.where((m) => m != 'registo').toList();
    if (semRegisto.isNotEmpty) {
      return 'Falta: ${semRegisto.map(_labelMissing).join(', ')}.';
    }
    return 'Não foi possível guardar os dados fiscais. Tenta de novo.';
  }

  /// Nomes que a pessoa lê — nunca os nomes técnicos (PADRAO_BORA §1.16).
  static String _roleLabel(Object? role) => switch (role?.toString()) {
        'driver' => 'estafeta',
        'partner' => 'parceiro',
        'cleaner' => 'profissional de limpeza',
        'washer' => 'lavador',
        'provider' => 'prestador de serviços',
        _ => 'prestador',
      };

  static String _labelMissing(String key) => switch (key) {
        'nome' => 'o nome completo',
        'nif' => 'o NIF',
        'morada' => 'a morada',
        'iban' => 'o IBAN',
        'data_nascimento' => 'a data de nascimento',
        'autocertificacao' => 'a declaração de veracidade',
        _ => key,
      };

  static String _isoDate(DateTime d) => '${d.year.toString().padLeft(4, '0')}-'
      '${d.month.toString().padLeft(2, '0')}-'
      '${d.day.toString().padLeft(2, '0')}';
}
