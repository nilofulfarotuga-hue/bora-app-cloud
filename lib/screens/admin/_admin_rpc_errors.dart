import 'package:supabase_flutter/supabase_flutter.dart';

/// Translates server-side `RAISE EXCEPTION` messages from `admin_*` RPCs
/// into user-facing Portuguese strings. Shared by every admin screen that
/// calls those RPCs so error wording stays consistent.
///
/// Error vocabulary defined in:
///   - migration `20260428000003_admin_driver_rpcs.sql`
///   - plan         `2026-04-28-fase2A-bug1-plan.md` §3.4
String humanizeAdminRpcError(Object error) {
  if (error is PostgrestException) {
    final msg = error.message;
    if (msg.startsWith('admin_required')) {
      return 'Sem permissões de admin para esta acção.';
    }
    if (msg.startsWith('driver_not_found')) {
      return 'Entregador não encontrado. Refresca a lista.';
    }
    if (msg.startsWith('driver_already_approved')) {
      return 'Este entregador já estava aprovado.';
    }
    if (msg.startsWith('driver_already_rejected')) {
      return 'Este entregador já estava rejeitado.';
    }
    if (msg.startsWith('missing_docs:')) {
      final list = msg.substring('missing_docs:'.length).trim();
      return 'Documentos em falta: $list';
    }
    if (msg.startsWith('justification_required')) {
      return 'Tens de preencher a justificação (mínimo 3 caracteres).';
    }
    if (msg.startsWith('reason_required')) {
      return 'Tens de preencher o motivo (mínimo 3 caracteres).';
    }
    // Conformidade legal (D3/D4, 2026-09-23): `admin_conformidade_legal`,
    // `admin_dac7_export` e o gatilho `fn_conformidade_antes_de_ativar`.
    if (msg.startsWith('not_admin')) {
      return 'Sem permissão de administrador (a sessão não é de admin).';
    }
    if (msg.contains('conformidade_incompleta')) {
      return humanizeConformidadeIncompleta(msg);
    }
    return 'Erro do servidor: $msg';
  }
  return 'Erro inesperado: $error';
}

/// Rótulos PT-BR dos campos legais que o servidor devolve em `falta` /
/// `campos_em_falta` (`_conformidade_em_falta`, migration
/// `20260923131328_ronda_d3_conformidade_prestadores.sql`).
/// Um código desconhecido volta tal e qual, para não esconder nada.
String rotuloCampoLegal(String codigo) => switch (codigo.trim()) {
      'nif' => 'NIF',
      'morada' => 'Morada',
      'iban' => 'IBAN',
      'data_nascimento' => 'Data de nascimento',
      'autocertificacao' => 'Autocertificação DSA',
      'nome' => 'Nome legal',
      final outro => outro,
    };

/// `conformidade_incompleta: faltam nif, morada` →
/// "Ativação bloqueada: faltam dados legais (NIF, Morada)".
String humanizeConformidadeIncompleta(String msg) {
  final i = msg.indexOf('faltam');
  var lista = const <String>[];
  if (i >= 0) {
    // Só a lista: pára no primeiro ponto, parêntese ou quebra de linha, para
    // não apanhar palavras de uma HINT que venha colada à mensagem.
    final resto =
        msg.substring(i + 'faltam'.length).split(RegExp(r'[.(\n]')).first;
    lista = resto
        .split(',')
        .map((e) => e.trim())
        .where((e) => RegExp(r'^[a-z_]+$').hasMatch(e))
        .map(rotuloCampoLegal)
        .toList();
  }
  if (lista.isEmpty) return 'Ativação bloqueada: faltam dados legais.';
  return 'Ativação bloqueada: faltam dados legais (${lista.join(', ')}).';
}
