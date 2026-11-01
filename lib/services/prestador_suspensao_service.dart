import 'package:supabase_flutter/supabase_flutter.dart';

/// SUSPENSÃO E REVISÃO HUMANA — Diretiva (UE) 2024/2831, art. 11.º.
///
/// Missão app-fechar-2026-11-01, bloco B8. Contratos do servidor (migração
/// `20261101230000_prestador_suspensoes_revisao_humana_2026_11_01.sql`,
/// confirmados em produção com `pg_get_functiondef` a 01/11/2026):
///
/// - `prestador_minha_suspensao()` → `{suspensa:false}` ou a última suspensão
///   decidida por uma pessoa e ainda em vigor (`id, tipo, tipo_conta, estado,
///   motivo, decidido_em, ate, decidido_por, revisao_*, pode_pedir_revisao,
///   contacto_whatsapp, contacto_email`).
/// - `prestador_pedir_revisao(p_motivo)` → `{ok, suspensao_id, prazo, mensagem}`
///   (mínimo 5 letras; erro `escreve_o_teu_lado`).
/// - vista `admin_fila_revisoes` + `admin_responder_revisao`,
///   `admin_decidir_proposta`, `admin_registar_pedido_revisao`,
///   `admin_suspender_prestador`, `admin_reativar_prestador`.
///
/// Nada aqui mexe em dinheiro. A app NUNCA suspende sozinha: só lê e pede
/// revisão; o painel só chama as funções do servidor, que exigem uma pessoa.

/// Mínimo de letras do pedido de revisão (igual ao servidor).
const int kMinLetrasRevisao = 5;

/// Mínimo de letras do motivo de uma suspensão (igual ao servidor e ao
/// gatilho `fn_suspensao_so_com_humano`).
const int kMinLetrasMotivoSuspensao = 10;

/// Tempo máximo de cada chamada (PADRAO_BORA 3.15 — 5).
const Duration kTempoSuspensao = Duration(seconds: 15);

/// Valida o texto do pedido de revisão (PT-PT, app do prestador).
/// Devolve a frase de erro, ou `null` se pode seguir.
String? validarPedidoRevisao(String texto) {
  if (texto.trim().length < kMinLetrasRevisao) {
    return 'Conta-nos o teu lado com pelo menos $kMinLetrasRevisao letras.';
  }
  return null;
}

/// Valida o motivo de uma suspensão (PT-BR, painel).
/// Devolve a frase de erro, ou `null` se pode seguir.
String? validarMotivoSuspensao(String texto) {
  if (texto.trim().length < kMinLetrasMotivoSuspensao) {
    return 'Escreva o motivo com pelo menos $kMinLetrasMotivoSuspensao letras '
        '— o prestador tem direito a recebê-lo por escrito.';
  }
  return null;
}

DateTime? _data(dynamic v) =>
    v == null ? null : DateTime.tryParse(v.toString())?.toLocal();

String? _texto(dynamic v) {
  final s = v?.toString().trim();
  return (s == null || s.isEmpty) ? null : s;
}

/// O que a app mostra no ecrã "A minha conta foi suspensa".
class SuspensaoInfo {
  const SuspensaoInfo({
    required this.suspensa,
    this.id,
    this.tipo,
    this.tipoConta,
    this.estado,
    this.motivo,
    this.decididoEm,
    this.ate,
    this.decididoPor,
    this.revisaoPedidaEm,
    this.revisaoPrazo,
    this.revisaoResposta,
    this.revistoEm,
    this.podePedirRevisao = false,
    this.contactoWhatsapp,
    this.contactoEmail,
  });

  /// `{suspensa:false}` → sem suspensão registada por uma pessoa.
  static const SuspensaoInfo semRegisto = SuspensaoInfo(suspensa: false);

  factory SuspensaoInfo.fromJson(Map<String, dynamic> j) {
    // O servidor só devolve a chave `suspensa` quando NÃO há suspensão; com
    // suspensão devolve o registo (com `id`).
    if (j['suspensa'] == false || j['id'] == null) return semRegisto;
    return SuspensaoInfo(
      suspensa: true,
      id: (j['id'] as num?)?.toInt() ?? int.tryParse('${j['id']}'),
      tipo: _texto(j['tipo']),
      tipoConta: _texto(j['tipo_conta']),
      estado: _texto(j['estado']),
      motivo: _texto(j['motivo']),
      decididoEm: _data(j['decidido_em']),
      ate: _data(j['ate']),
      decididoPor: _texto(j['decidido_por']),
      revisaoPedidaEm: _data(j['revisao_pedida_em']),
      revisaoPrazo: _data(j['revisao_prazo']),
      revisaoResposta: _texto(j['revisao_resposta']),
      revistoEm: _data(j['revisto_em']),
      podePedirRevisao: j['pode_pedir_revisao'] == true,
      contactoWhatsapp: _texto(j['contacto_whatsapp']),
      contactoEmail: _texto(j['contacto_email']),
    );
  }

  final bool suspensa;
  final int? id;

  /// suspensao_temporaria | suspensao | encerramento | restricao
  final String? tipo;

  /// estafeta | motorista | limpeza | lavagem | casa | parceiro | servico
  final String? tipoConta;

  /// ativa | em_revisao | mantida | reduzida
  final String? estado;
  final String? motivo;
  final DateTime? decididoEm;
  final DateTime? ate;
  final String? decididoPor;
  final DateTime? revisaoPedidaEm;
  final DateTime? revisaoPrazo;
  final String? revisaoResposta;
  final DateTime? revistoEm;
  final bool podePedirRevisao;
  final String? contactoWhatsapp;
  final String? contactoEmail;

  bool get emRevisao => estado == 'em_revisao';
  bool get encerramento => tipo == 'encerramento';
  bool get restricao => tipo == 'restricao';

  /// Título do ecrã, em PT-PT.
  String get titulo => switch (tipo) {
        'encerramento' => 'A tua conta foi encerrada',
        'restricao' => 'A tua conta tem uma restrição',
        _ => 'A tua conta foi suspensa',
      };

  /// Texto do estado da revisão, em PT-PT (ou `null` se nunca foi pedida).
  String? get estadoRevisao => switch (estado) {
        'em_revisao' => 'Pediste revisão. Uma pessoa da equipa Bora está a '
            'ver o teu caso e responde por escrito'
            '${revisaoPrazo != null ? ' até ${diaSuspensao(revisaoPrazo!)}' : ''}.',
        'mantida' => 'A revisão foi feita e a decisão mantém-se.',
        'reduzida' => 'A revisão foi feita e a suspensão foi reduzida'
            '${ate != null ? ' até ${diaEHoraSuspensao(ate!)}' : ''}.',
        _ => null,
      };
}

/// Uma linha da vista `admin_fila_revisoes` (painel).
class RevisaoPendente {
  const RevisaoPendente({
    required this.id,
    required this.tipoConta,
    required this.entidadeTabela,
    required this.entidadeId,
    required this.tipo,
    required this.estado,
    required this.motivo,
    this.userId,
    this.motivoCodigo,
    this.factos = const {},
    this.decididoPorEmail,
    this.decididoEm,
    this.ate,
    this.revisaoPedidaEm,
    this.revisaoVia,
    this.revisaoTexto,
    this.revisaoPrazo,
    this.diasRestantes,
    this.atrasada = false,
    this.criadoEm,
  });

  factory RevisaoPendente.fromJson(Map<String, dynamic> j) => RevisaoPendente(
        id: (j['id'] as num?)?.toInt() ?? int.parse('${j['id']}'),
        tipoConta: '${j['tipo_conta'] ?? ''}',
        entidadeTabela: '${j['entidade_tabela'] ?? ''}',
        entidadeId: '${j['entidade_id'] ?? ''}',
        userId: _texto(j['user_id']),
        tipo: '${j['tipo'] ?? ''}',
        estado: '${j['estado'] ?? ''}',
        motivo: '${j['motivo'] ?? ''}',
        motivoCodigo: _texto(j['motivo_codigo']),
        factos: j['factos'] is Map
            ? Map<String, dynamic>.from(j['factos'] as Map)
            : const {},
        decididoPorEmail: _texto(j['decidido_por_email']),
        decididoEm: _data(j['decidido_em']),
        ate: _data(j['ate']),
        revisaoPedidaEm: _data(j['revisao_pedida_em']),
        revisaoVia: _texto(j['revisao_via']),
        revisaoTexto: _texto(j['revisao_texto']),
        revisaoPrazo: _data(j['revisao_prazo']),
        diasRestantes: j['dias_restantes'] == null
            ? null
            : double.tryParse('${j['dias_restantes']}'),
        atrasada: j['atrasada'] == true,
        criadoEm: _data(j['created_at']),
      );

  final int id;
  final String tipoConta;
  final String entidadeTabela;
  final String entidadeId;
  final String? userId;
  final String tipo;

  /// em_revisao (o prestador pediu revisão) | pendente_decisao (proposta
  /// automática à espera de uma pessoa).
  final String estado;
  final String motivo;
  final String? motivoCodigo;
  final Map<String, dynamic> factos;
  final String? decididoPorEmail;
  final DateTime? decididoEm;
  final DateTime? ate;
  final DateTime? revisaoPedidaEm;
  final String? revisaoVia;
  final String? revisaoTexto;
  final DateTime? revisaoPrazo;
  final double? diasRestantes;
  final bool atrasada;
  final DateTime? criadoEm;

  bool get eProposta => estado == 'pendente_decisao';

  /// Nome do papel em PT-BR (painel).
  String get rotuloConta => rotuloTipoConta(tipoConta);

  /// Nome da decisão em PT-BR (painel).
  String get rotuloTipo => rotuloTipoSuspensao(tipo);

  /// Estado em PT-BR (painel).
  String get rotuloEstado => switch (estado) {
        'em_revisao' => 'Revisão pedida',
        'pendente_decisao' => 'Proposta automática',
        'ativa' => 'Em vigor',
        'mantida' => 'Mantida após revisão',
        'reduzida' => 'Reduzida após revisão',
        final o => o,
      };
}

/// Papel do prestador em PT-BR (painel).
String rotuloTipoConta(String tipoConta) => switch (tipoConta) {
      'estafeta' => 'Entregador',
      'motorista' => 'Motorista',
      'limpeza' => 'Limpeza',
      'lavagem' => 'Lavagem',
      'casa' => 'Casa',
      'parceiro' => 'Parceiro (loja)',
      'servico' => 'Serviço (barbearia)',
      final o => o,
    };

/// Tipo de decisão em PT-BR (painel).
String rotuloTipoSuspensao(String tipo) => switch (tipo) {
      'suspensao_temporaria' => 'Suspensão temporária',
      'suspensao' => 'Suspensão sem data de fim',
      'encerramento' => 'Encerramento da conta',
      'restricao' => 'Restrição',
      'proposta_automatica' => 'Proposta automática',
      final o => o,
    };

/// `dd/mm/aaaa`.
String diaSuspensao(DateTime d) {
  final l = d.toLocal();
  String dd(int n) => n.toString().padLeft(2, '0');
  return '${dd(l.day)}/${dd(l.month)}/${l.year}';
}

/// `dd/mm/aaaa às hh:mm`.
String diaEHoraSuspensao(DateTime d) {
  final l = d.toLocal();
  String dd(int n) => n.toString().padLeft(2, '0');
  return '${diaSuspensao(l)} às ${dd(l.hour)}:${dd(l.minute)}';
}

/// Traduz os erros do servidor destas funções. Devolve `null` se o erro não é
/// destas funções (o chamador usa então a sua própria tradução).
///
/// Os erros do lado do prestador saem em PT-PT; os do painel em PT-BR.
String? traduzirErroSuspensaoOuNull(Object erro) {
  final msg = erro is PostgrestException ? erro.message : erro.toString();
  bool tem(String c) => msg.contains(c);
  // ── prestador (app, PT-PT) ──
  if (tem('escreve_o_teu_lado')) {
    return 'Conta-nos o teu lado com pelo menos $kMinLetrasRevisao letras.';
  }
  if (tem('sem_suspensao_ativa')) {
    return 'Não encontrámos uma suspensão em vigor na tua conta. '
        'Se precisares, fala connosco pelo WhatsApp ou email.';
  }
  if (tem('sem_sessao')) {
    return 'A tua sessão terminou. Entra outra vez para pedir revisão.';
  }
  // ── painel (PT-BR) ──
  if (tem('SUSPENSAO_SEM_MOTIVO')) {
    return 'O servidor recusou: falta o motivo por escrito (mínimo '
        '$kMinLetrasMotivoSuspensao letras). O prestador tem direito a recebê-lo.';
  }
  if (tem('SUSPENSAO_SEM_HUMANO')) {
    return 'O servidor recusou: só uma pessoa da equipe (conta de admin) pode '
        'suspender ou encerrar. Entre de novo com a conta de admin.';
  }
  if (tem('prestador_com_pedido_em_curso')) {
    return 'Este entregador tem um pedido em curso. Espere que termine ou '
        'passe o pedido a outro entregador antes de suspender.';
  }
  if (tem('washer_has_open_jobs') || tem('tem_trabalhos_ativos')) {
    return 'Este prestador tem um trabalho em curso. Espere que termine '
        'antes de suspender.';
  }
  if (tem('suspensao_temporaria_precisa_de_data_futura')) {
    return 'Suspensão temporária precisa de uma data de fim no futuro.';
  }
  if (tem('reduzida_precisa_de_nova_data_futura')) {
    return 'Para reduzir, escolha a nova data de fim (no futuro).';
  }
  if (tem('resposta_obrigatoria')) {
    return 'A resposta tem de ser por escrito e explicada (mínimo '
        '$kMinLetrasMotivoSuspensao letras).';
  }
  if (tem('nao_esta_em_revisao')) {
    return 'Este caso já não está à espera de revisão. Atualize a lista.';
  }
  if (tem('nao_e_proposta_pendente')) {
    return 'Esta proposta já foi decidida. Atualize a lista.';
  }
  if (tem('estado_nao_permite_revisao')) {
    return 'Este caso não está numa suspensão ativa — não dá para registar '
        'pedido de revisão.';
  }
  if (tem('suspensao_nao_encontrada')) {
    return 'Registo de suspensão não encontrado. Atualize a lista.';
  }
  if (tem('prestador_nao_encontrado')) {
    return 'Prestador não encontrado. Atualize a lista.';
  }
  if (tem('ja_terminada')) return 'Esta suspensão já tinha terminado.';
  if (tem('nota_obrigatoria')) {
    return 'Escreva uma nota curta para reativar (mínimo 3 letras).';
  }
  if (tem('via_invalida')) return 'Escolha por onde chegou o pedido.';
  if (tem('decisao_invalida')) return 'Decisão inválida.';
  if (tem('tipo_invalido')) return 'Tipo de suspensão inválido.';
  if (tem('tabela_invalida')) return 'Tipo de prestador inválido.';
  if (tem('admin_required') || tem('not_admin') || tem('nao_admin')) {
    return 'Sem permissão de administrador para esta ação.';
  }
  return null;
}

/// Como [traduzirErroSuspensaoOuNull], com uma frase genérica no fim.
String traduzirErroSuspensao(Object erro, {bool painel = true}) {
  final t = traduzirErroSuspensaoOuNull(erro);
  if (t != null) return t;
  final msg = erro is PostgrestException ? erro.message : erro.toString();
  if (msg.contains('TimeoutException') || msg.contains('SocketException')) {
    return painel
        ? 'Sem resposta do servidor. Verifique a internet e tente de novo.'
        : 'Sem resposta do servidor. Verifica a rede e tenta outra vez.';
  }
  return painel ? 'Erro do servidor: $msg' : 'Não deu: $msg';
}

/// Chamadas ao servidor. O cliente Supabase só é lido quando se chama (os
/// testes injetam funções falsas nos ecrãs e nunca chegam aqui).
class PrestadorSuspensaoService {
  const PrestadorSuspensaoService._();

  static SupabaseClient get _sb => Supabase.instance.client;

  static Map<String, dynamic> _mapa(dynamic r) =>
      r is Map ? Map<String, dynamic>.from(r) : <String, dynamic>{};

  // ── app do prestador ──────────────────────────────────────────────────────

  /// A suspensão da pessoa com sessão aberta (ou [SuspensaoInfo.semRegisto]).
  static Future<SuspensaoInfo> minha() async {
    final r =
        await _sb.rpc('prestador_minha_suspensao').timeout(kTempoSuspensao);
    return SuspensaoInfo.fromJson(_mapa(r));
  }

  /// Pede revisão. Devolve a mensagem do servidor (com o prazo).
  static Future<String> pedirRevisao(String motivo) async {
    final r = await _sb.rpc('prestador_pedir_revisao',
        params: {'p_motivo': motivo.trim()}).timeout(kTempoSuspensao);
    final m = _mapa(r);
    return _texto(m['mensagem']) ??
        'Pedido registado. Uma pessoa da equipa Bora responde por escrito em 7 dias.';
  }

  // ── painel ────────────────────────────────────────────────────────────────

  /// Fila de revisões pedidas e propostas automáticas.
  static Future<List<RevisaoPendente>> fila() async {
    final rows = await _sb
        .from('admin_fila_revisoes')
        .select()
        .limit(500)
        .timeout(kTempoSuspensao);
    return rows.map(RevisaoPendente.fromJson).toList();
  }

  /// Suspensões em vigor (decididas por uma pessoa, sem revisão pendente),
  /// para o painel registar um pedido de revisão chegado por WhatsApp/email
  /// ou reativar. Mesma forma de linha da fila.
  static Future<List<RevisaoPendente>> ativas() async {
    final rows = await _sb
        .from('prestador_suspensoes')
        .select('id, tipo_conta, entidade_tabela, entidade_id, user_id, tipo, '
            'estado, motivo, motivo_codigo, decidido_por_email, decidido_em, '
            'ate, revisao_pedida_em, revisao_via, revisao_texto, '
            'revisao_prazo, created_at')
        .eq('origem', 'admin')
        .inFilter('estado', const ['ativa', 'mantida', 'reduzida'])
        .order('created_at', ascending: false)
        .limit(300)
        .timeout(kTempoSuspensao);
    return rows.map(RevisaoPendente.fromJson).toList();
  }

  static Future<Map<String, dynamic>> reativar({
    required int suspensaoId,
    required String nota,
  }) async {
    final r = await _sb.rpc('admin_reativar_prestador', params: {
      'p_suspensao_id': suspensaoId,
      'p_nota': nota.trim(),
    }).timeout(kTempoSuspensao);
    return _mapa(r);
  }

  static Future<Map<String, dynamic>> suspender({
    required String tabela,
    required String entidadeId,
    required String tipo,
    required String motivo,
    DateTime? ate,
    String? motivoCodigo,
    Map<String, dynamic>? factos,
  }) async {
    final r = await _sb.rpc('admin_suspender_prestador', params: {
      'p_entidade_tabela': tabela,
      'p_entidade_id': entidadeId,
      'p_tipo': tipo,
      'p_motivo': motivo.trim(),
      'p_ate': ate?.toUtc().toIso8601String(),
      'p_motivo_codigo': motivoCodigo,
      'p_factos': factos ?? const <String, dynamic>{},
    }).timeout(kTempoSuspensao);
    return _mapa(r);
  }

  /// decisao: mantida | reduzida | revertida.
  static Future<Map<String, dynamic>> responderRevisao({
    required int suspensaoId,
    required String decisao,
    required String resposta,
    DateTime? novaAte,
  }) async {
    final r = await _sb.rpc('admin_responder_revisao', params: {
      'p_suspensao_id': suspensaoId,
      'p_decisao': decisao,
      'p_resposta': resposta.trim(),
      'p_nova_ate': novaAte?.toUtc().toIso8601String(),
    }).timeout(kTempoSuspensao);
    return _mapa(r);
  }

  /// decisao: arquivar | suspensao_temporaria | suspensao | encerramento | restricao.
  static Future<Map<String, dynamic>> decidirProposta({
    required int suspensaoId,
    required String decisao,
    required String motivo,
    DateTime? ate,
  }) async {
    final r = await _sb.rpc('admin_decidir_proposta', params: {
      'p_suspensao_id': suspensaoId,
      'p_decisao': decisao,
      'p_motivo': motivo.trim(),
      'p_ate': ate?.toUtc().toIso8601String(),
    }).timeout(kTempoSuspensao);
    return _mapa(r);
  }

  /// via: whatsapp | email | telefone.
  static Future<Map<String, dynamic>> registarPedido({
    required int suspensaoId,
    required String via,
    required String texto,
  }) async {
    final r = await _sb.rpc('admin_registar_pedido_revisao', params: {
      'p_suspensao_id': suspensaoId,
      'p_via': via,
      'p_texto': texto.trim(),
    }).timeout(kTempoSuspensao);
    return _mapa(r);
  }

  /// Último registo ainda aberto (ativa, em revisão, mantida, reduzida) de
  /// um prestador, para o painel poder pedir revisão por WhatsApp ou reativar.
  static Future<int?> registoAberto(String tabela, String entidadeId) async {
    final rows = await _sb
        .from('prestador_suspensoes')
        .select('id')
        .eq('entidade_tabela', tabela)
        .eq('entidade_id', entidadeId)
        .inFilter(
            'estado', const ['ativa', 'em_revisao', 'mantida', 'reduzida'])
        .order('created_at', ascending: false)
        .limit(1)
        .timeout(kTempoSuspensao);
    if (rows.isEmpty) return null;
    final id = rows.first['id'];
    return id is num ? id.toInt() : int.tryParse('$id');
  }

  /// Fecha o registo aberto quando o painel reativa o prestador por um botão
  /// antigo (que muda a tabela mas não o registo). Melhor esforço: devolve
  /// `false` se não havia registo ou se o servidor recusou.
  static Future<bool> fecharRegistoAberto(
      String tabela, String entidadeId, String nota) async {
    try {
      final id = await registoAberto(tabela, entidadeId);
      if (id == null) return false;
      await _sb.rpc('admin_reativar_prestador', params: {
        'p_suspensao_id': id,
        'p_nota': nota.trim(),
      }).timeout(kTempoSuspensao);
      return true;
    } catch (_) {
      return false;
    }
  }
}
