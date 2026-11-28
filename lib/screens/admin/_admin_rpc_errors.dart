import 'package:supabase_flutter/supabase_flutter.dart';

import '../../services/prestador_suspensao_service.dart';

/// Translates server-side `RAISE EXCEPTION` messages from `admin_*` RPCs
/// into user-facing Portuguese (PT-BR) strings. Shared by every admin screen
/// that calls those RPCs so error wording stays consistent.
///
/// Error vocabulary defined in:
///   - migration `20260428000003_admin_driver_rpcs.sql`
///   - plan         `2026-04-28-fase2A-bug1-plan.md` §3.4
///
/// [15/11/2026] Painel em PT-BR e, além das marcas das RPCs, as falhas do
/// próprio servidor (função por instalar, função repetida, sem permissão de
/// leitura), das Edge Functions e da rede. Sem `dart:io` (o painel é web).
String humanizeAdminRpcError(Object error) {
  if (error is PostgrestException) {
    final msg = error.message;
    final code = error.code ?? '';
    if (_ehGuardaDeAdmin(msg)) {
      return 'Sem permissão de admin para esta ação.';
    }
    // [15/11/2026] `admin_loja_decidir_reserva`: recusar uma reserva já paga
    // não devolve os 3 € — o caminho é Cancelar reserva, que devolve.
    if (msg.contains('reserva_paga') || code.contains('reserva_paga')) {
      return kErroReservaPaga;
    }
    if (msg.startsWith('driver_not_found')) {
      return 'Entregador não encontrado. Atualize a lista.';
    }
    if (msg.startsWith('driver_already_approved')) {
      return 'Este entregador já estava aprovado.';
    }
    if (msg.startsWith('driver_already_rejected')) {
      return 'Este entregador já estava rejeitado.';
    }
    if (msg.startsWith('missing_docs:')) {
      final list = msg.substring('missing_docs:'.length).trim();
      return 'Faltam documentos: $list';
    }
    if (msg.startsWith('justification_required')) {
      return 'Preencha a justificativa (mínimo 3 caracteres).';
    }
    if (msg.startsWith('reason_required')) {
      return 'Preencha o motivo (mínimo 3 caracteres).';
    }
    // Conformidade legal (D3/D4, 2026-09-23): `admin_conformidade_legal`,
    // `admin_dac7_export` e o gatilho `fn_conformidade_antes_de_ativar`.
    if (msg.startsWith('not_admin')) {
      return 'Sem permissão de administrador (a sessão não é de admin).';
    }
    if (msg.contains('conformidade_incompleta')) {
      return humanizeConformidadeIncompleta(msg);
    }
    if (msg.contains('atividade_por_aprovar')) return kErroAtividadePorAprovar;
    // [18/11/2026] `admin_aprovar_prestador_excecao` e
    // `admin_pedir_documentos_em_falta` / `admin_provider_atividade_decidir`.
    if (msg.contains('motivo_excecao_curto')) {
      return 'Escreva o motivo da exceção (mínimo 10 letras).';
    }
    if (msg.contains('prestador_nao_encontrado')) {
      return 'Cadastro não encontrado. Atualize a lista.';
    }
    if (msg.contains('motivo_obrigatorio')) {
      return 'Escreva o motivo (a pessoa vai ler).';
    }
    if (msg.contains('sem_documento')) {
      return 'Esta pessoa ainda não enviou o comprovativo.';
    }
    if (msg.startsWith('cleaner_not_found')) {
      return 'Profissional não encontrada. Atualize a lista.';
    }
    // [01/11/2026 · B8] Gatilho `fn_suspensao_so_com_humano` e
    // `admin_suspender_prestador` (Diretiva 2024/2831): motivo ≥ 10 letras,
    // decisão de uma pessoa, sem pedido em curso.
    if (msg.contains('SUSPENSAO_') ||
        msg.contains('prestador_com_pedido_em_curso')) {
      final t = traduzirErroSuspensaoOuNull(error);
      if (t != null) return t;
    }
    // [15/11/2026] Falhas do servidor que não são regra de negócio. Vêm
    // depois das marcas: `_admin_op_guard` também usa o código 42501, mas com
    // a marca `admin_required`, que já foi tratada acima.
    if (code == 'PGRST202' || msg.contains('Could not find the function')) {
      return 'Esta parte ainda não foi instalada no servidor.';
    }
    if (code == 'PGRST203') {
      return 'O servidor tem duas versões desta função; a equipe técnica '
          'precisa corrigir.';
    }
    if (code == '42501' || msg.toLowerCase().contains('permission denied')) {
      return 'O servidor não deixa o painel ler isto (falta permissão de admin).';
    }
    return 'Erro do servidor: $msg';
  }
  if (error is FunctionException) return _humanizarErroDeFuncao(error);
  if (_pareceErroDeRede(error)) return _kSemConexao;
  return 'Erro inesperado: $error';
}

const String _kSemConexao = 'Sem conexão com a internet. Tente de novo.';

/// [15/11/2026] Marca `reserva_paga` de `admin_loja_decidir_reserva`.
const String kErroReservaPaga =
    'Esta reserva já foi paga: para a recusar use Cancelar reserva, que devolve '
    'o dinheiro ao cliente.';

/// Marcas das guardas de admin nas RPCs (`RAISE EXCEPTION '<marca>'`;
/// varrimento às funções `admin_*` em produção a 15/11/2026). `not_admin` tem
/// frase própria, mais abaixo; `forbidden` só conta sozinho (`forbidden_field`
/// é outra coisa).
bool _ehGuardaDeAdmin(String msg) =>
    msg.startsWith('admin_required') ||
    msg.startsWith('so_admin') ||
    msg.startsWith('admin_only') ||
    msg.startsWith('forbidden_admin_only') ||
    msg == 'forbidden';

/// Marcas de "sem rede" (as mesmas de `models/falha_de_acao.dart`, mais a do
/// navegador). Lidas no nome do tipo e no texto, porque `dart:io` não existe
/// na web.
const _marcasSemRede = <String>[
  'SocketException',
  'ClientException',
  'Failed host lookup',
  'XMLHttpRequest error',
];

bool _pareceErroDeRede(Object error) {
  final tipo = error.runtimeType.toString();
  final texto = error.toString();
  return _marcasSemRede.any((m) => tipo.contains(m) || texto.contains(m));
}

/// Edge Functions (`functions.invoke`): o pacote lança `FunctionException`
/// com o código HTTP e o corpo da resposta em `details`; sem resposta nenhuma
/// (rede), o código é 0 (`FunctionsFetchException`). Versões antigas do
/// pacote lançavam o `ClientException` cru, que cai na regra geral de rede.
String _humanizarErroDeFuncao(FunctionException e) {
  if (e.status == 0) return _kSemConexao;
  if (e.status == 401 || e.status == 403) return 'Sem permissão de admin.';
  final texto = _textoDosDetalhes(e.details);
  if (e.status == 404) {
    // O 404 da Supabase (função que não existe) diz "Requested function was
    // not found"; uma função que responde 404 com o seu próprio `error`
    // (ex.: `driver_not_found`) mostra esse texto.
    final bruto = '${e.details ?? ''}';
    final semFuncao = texto == null ||
        bruto.contains('NOT_FOUND') ||
        bruto.toLowerCase().contains('requested function was not found') ||
        bruto.toLowerCase().contains('function not found');
    if (semFuncao) return 'Esta função do servidor não está instalada.';
  }
  if (texto == null) return 'Erro do servidor (código ${e.status}).';
  return 'Erro do servidor: $texto';
}

/// O texto útil do corpo de uma resposta de erro: `error`/`message` de um
/// JSON (com `details`, se vier), ou o texto tal e qual.
String? _textoDosDetalhes(Object? detalhes) {
  String? limpo(Object? v) {
    final t = v?.toString().trim() ?? '';
    return t.isEmpty ? null : t;
  }

  if (detalhes is Map) {
    final principal = limpo(detalhes['error']) ??
        limpo(detalhes['erro']) ??
        limpo(detalhes['message']) ??
        limpo(detalhes['mensagem']);
    final extra = limpo(detalhes['details']);
    if (principal == null) return extra ?? (detalhes.isEmpty ? null : '$detalhes');
    return (extra == null || extra == principal) ? principal : '$principal ($extra)';
  }
  return limpo(detalhes);
}

/// [20/10/2026] Gatilho `fn_atividade_antes_de_ativar`: candidatura nova sem o
/// comprovativo de atividade aprovado não passa a "aprovada".
const String kErroAtividadePorAprovar =
    'Falta aprovar o comprovativo de atividade desta pessoa. Abra a ficha e '
    'toque em "Aprovar comprovativo", ou use "Aprovar mesmo assim (exceção do '
    'admin)" com o motivo.';

/// A função do servidor ainda não existe (migração por aplicar): o painel
/// usa o caminho antigo em vez de falhar.
bool funcaoAindaNaoInstalada(Object error) =>
    error is PostgrestException &&
    ((error.code ?? '') == 'PGRST202' ||
        error.message.contains('Could not find the function'));

/// O mesmo, para ecrãs que mostram o erro cru (`Erro: $e`).
String? humanizeAtividadePorAprovar(Object error) =>
    error.toString().contains('atividade_por_aprovar') ? kErroAtividadePorAprovar : null;

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
