// Missão hermes-diretor-2026-11-20 (bloco B10) — modelos dos ecrãs do painel que o Danilo usa
// para ver e mandar no Hermes (o robô diretor): autorizações, sentinela (o vigia), casos de teste
// dos robôs, agentes e previsão do crédito do Claude.
// Esquema: supabase/migrations/20261122190000_hermes_diretor_tabelas.sql.
// Tudo aqui é puro (sem rede): lê mapas vindos do Supabase e aguenta campos em falta.

double? _num(Object? v) {
  if (v == null) return null;
  if (v is num) return v.toDouble();
  return double.tryParse('$v'.replaceAll(',', '.'));
}

int _int(Object? v, [int padrao = 0]) => (_num(v) ?? padrao).toInt();

DateTime? _data(Object? v) => v == null ? null : DateTime.tryParse('$v');

String _texto(Object? v) => v == null ? '' : '$v';

bool _bool(Object? v, {bool padrao = false}) {
  if (v is bool) return v;
  if (v == null) return padrao;
  final s = '$v'.toLowerCase();
  if (s == 'true') return true;
  if (s == 'false') return false;
  return padrao;
}

List<String> _listaTexto(Object? v) {
  if (v is! List) return const [];
  return [for (final e in v) '$e'];
}

// ── Autorizações ─────────────────────────────────────────────────────────────

/// Um pedido de autorização do Hermes (tabela `hermes_autorizacoes`).
class AutorizacaoHermes {
  const AutorizacaoHermes({
    required this.id,
    required this.acao,
    required this.estado,
    this.criadaEm,
    this.pedidaPor = 'hermes',
    this.porque = '',
    this.valorEur,
    this.operacao,
    this.expiraEm,
    this.decididaEm,
    this.decididaPor,
    this.via,
    this.textoLiteral,
    this.usadaEm,
    this.resultado,
    this.teste = false,
  });

  final int id;
  final DateTime? criadaEm;
  final String pedidaPor;
  final String acao;
  final String porque;
  final double? valorEur;
  final Object? operacao;
  final String estado; // pendente | autorizada | recusada | expirada | usada
  final DateTime? expiraEm;
  final DateTime? decididaEm;
  final String? decididaPor;
  final String? via; // painel | telegram | claude-ai | claude-code
  final String? textoLiteral;
  final DateTime? usadaEm;
  final String? resultado;
  final bool teste;

  factory AutorizacaoHermes.fromMap(Map<String, dynamic> m) => AutorizacaoHermes(
        id: _int(m['id']),
        criadaEm: _data(m['criada_em']),
        pedidaPor: _texto(m['pedida_por']).isEmpty ? 'hermes' : _texto(m['pedida_por']),
        acao: _texto(m['acao']),
        porque: _texto(m['porque']),
        valorEur: _num(m['valor_eur']),
        operacao: m['operacao'],
        estado: _texto(m['estado']).isEmpty ? 'pendente' : _texto(m['estado']),
        expiraEm: _data(m['expira_em']),
        decididaEm: _data(m['decidida_em']),
        decididaPor: m['decidida_por'] as String?,
        via: m['via'] as String?,
        textoLiteral: m['texto_literal'] as String?,
        usadaEm: _data(m['usada_em']),
        resultado: m['resultado'] as String?,
        teste: _bool(m['teste']),
      );

  /// Ainda à espera do Danilo (o servidor pode ainda não ter passado a "expirada").
  bool estaPendente(DateTime agora) =>
      estado == 'pendente' && (expiraEm == null || expiraEm!.isAfter(agora));

  /// O estado que se mostra: um pedido pendente cujo prazo passou conta como expirado.
  String estadoNaTela(DateTime agora) =>
      estado == 'pendente' && !estaPendente(agora) ? 'expirada' : estado;

  /// Minutos que faltam (arredondado para cima); 0 se já expirou.
  int minutosAteExpirar(DateTime agora) {
    if (expiraEm == null) return 0;
    final s = expiraEm!.difference(agora).inSeconds;
    if (s <= 0) return 0;
    return (s / 60).ceil();
  }

  static String rotuloEstado(String estado) => switch (estado) {
        'pendente' => 'À espera de você',
        'autorizada' => 'Autorizada',
        'recusada' => 'Recusada',
        'expirada' => 'Expirada',
        'usada' => 'Usada',
        _ => estado,
      };

  static String rotuloVia(String? via) => switch (via) {
        'painel' => 'no painel',
        'telegram' => 'pelo Telegram',
        'claude-ai' => 'pela Claude.ai',
        'claude-code' => 'pelo Claude Code',
        _ => via == null || via.isEmpty ? '' : via,
      };
}

/// Resposta da RPC `admin_hermes_autorizacao_decidir`: `{ok, estado, erro?}`.
class ResultadoDecisao {
  const ResultadoDecisao({required this.ok, this.estado, this.erro});

  final bool ok;
  final String? estado;
  final String? erro;

  factory ResultadoDecisao.fromJson(Object? j) {
    if (j is Map) {
      return ResultadoDecisao(
        ok: j['ok'] == true,
        estado: j['estado'] as String?,
        erro: j['erro'] as String?,
      );
    }
    return const ResultadoDecisao(ok: false, erro: 'Resposta inesperada do servidor.');
  }
}

// ── Sentinela ────────────────────────────────────────────────────────────────

/// A tarefa do despacho que o Hermes abriu por causa de um evento (o "o que o Hermes fez").
class TarefaLigada {
  const TarefaLigada({required this.id, this.estado, this.resultado});

  final int id;
  final String? estado;
  final String? resultado;

  factory TarefaLigada.fromMap(Map<String, dynamic> m) => TarefaLigada(
        id: _int(m['id']),
        estado: m['estado'] as String?,
        resultado: m['resultado'] as String?,
      );
}

/// Um evento do vigia (tabela `sentinela_eventos`).
class EventoSentinela {
  const EventoSentinela({
    required this.id,
    required this.tipo,
    required this.gravidade,
    required this.titulo,
    this.criadoEm,
    this.dados = const {},
    this.despachoId,
    this.tratadoEm,
    this.tratadoPor,
    this.resultado,
  });

  final int id;
  final DateTime? criadoEm;
  final String tipo;
  final String gravidade; // urgente | normal | info
  final String titulo;
  final Map<String, dynamic> dados;
  final int? despachoId;
  final DateTime? tratadoEm;
  final String? tratadoPor;
  final String? resultado;

  bool get tratado => tratadoEm != null;

  factory EventoSentinela.fromMap(Map<String, dynamic> m) => EventoSentinela(
        id: _int(m['id']),
        criadoEm: _data(m['criado_em']),
        tipo: _texto(m['tipo']),
        gravidade: _texto(m['gravidade']).isEmpty ? 'info' : _texto(m['gravidade']),
        titulo: _texto(m['titulo']),
        dados: m['dados'] is Map ? Map<String, dynamic>.from(m['dados'] as Map) : const {},
        despachoId: m['despacho_id'] == null ? null : _int(m['despacho_id']),
        tratadoEm: _data(m['tratado_em']),
        tratadoPor: m['tratado_por'] as String?,
        resultado: m['resultado'] as String?,
      );

  static String rotuloTipo(String tipo) => switch (tipo) {
        'pedido_parado' => 'Pedido parado',
        'pagamento_estranho' => 'Pagamento estranho',
        'erro_repetido' => 'Erro repetido',
        'robo_em_apuros' => 'Robô em apuros',
        'carrinho_abandonado' => 'Carrinho abandonado',
        'sistema' => 'Sistema',
        _ => tipo,
      };

  static String rotuloGravidade(String g) => switch (g) {
        'urgente' => 'Urgente',
        'normal' => 'Normal',
        'info' => 'Informação',
        _ => g,
      };
}

// ── Casos de teste dos robôs ─────────────────────────────────────────────────

/// Um caso de teste da regressão (tabela `robos_casos_teste`).
class CasoTesteRobo {
  const CasoTesteRobo({
    required this.id,
    required this.robo,
    required this.pergunta,
    this.deveConter = const [],
    this.naoPodeConter = const [],
    this.ativo = true,
    this.ultimoResultado,
    this.ultimaResposta,
    this.ultimaCorridaEm,
  });

  final int id;
  final String robo;
  final String pergunta;
  final List<String> deveConter;
  final List<String> naoPodeConter;
  final bool ativo;
  final String? ultimoResultado; // passou | falhou | null
  final String? ultimaResposta;
  final DateTime? ultimaCorridaEm;

  factory CasoTesteRobo.fromMap(Map<String, dynamic> m) => CasoTesteRobo(
        id: _int(m['id']),
        robo: _texto(m['robo']),
        pergunta: _texto(m['pergunta']),
        deveConter: _listaTexto(m['deve_conter']),
        naoPodeConter: _listaTexto(m['nao_pode_conter']),
        ativo: _bool(m['ativo'], padrao: true),
        ultimoResultado: m['ultimo_resultado'] as String?,
        ultimaResposta: m['ultima_resposta'] as String?,
        ultimaCorridaEm: _data(m['ultima_corrida_em']),
      );
}

/// Resposta da RPC `robos_regressao_resumo(p_robo)`.
class ResumoRegressao {
  const ResumoRegressao({
    this.casos = 0,
    this.passaram = 0,
    this.falharam = 0,
    this.nuncaCorridos = 0,
    this.ultimaCorridaEm,
  });

  final int casos;
  final int passaram;
  final int falharam;
  final int nuncaCorridos;
  final DateTime? ultimaCorridaEm;

  factory ResumoRegressao.fromJson(Object? j) {
    if (j is! Map) return const ResumoRegressao();
    return ResumoRegressao(
      casos: _int(j['casos']),
      passaram: _int(j['passaram']),
      falharam: _int(j['falharam']),
      nuncaCorridos: _int(j['nunca_corridos']),
      ultimaCorridaEm: _data(j['ultima_corrida_em']),
    );
  }
}

// ── Agentes ──────────────────────────────────────────────────────────────────

/// Como o Danilo vê um agente.
enum EstadoAgente { relogio, aPedido, arquivado }

/// Uma linha de `agentes_estado`.
class AgenteEstado {
  const AgenteEstado({
    required this.agente,
    required this.ligado,
    required this.horarioLigado,
    this.arquivado = false,
    this.substituto,
    this.cadenciaMin,
    this.tetoDiaEur,
    this.departamento = '',
    this.papel = '',
    this.nota = '',
    this.ultimaCorrida,
    this.erro,
  });

  final String agente;
  final bool ligado;
  final bool horarioLigado;
  final bool arquivado;
  final String? substituto;
  final int? cadenciaMin;
  final double? tetoDiaEur;
  final String departamento;
  final String papel;
  final String nota;
  final DateTime? ultimaCorrida;
  final String? erro;

  /// "ligado ao relógio" = ligado e horario_ligado; "a pedido" = ligado sem horario_ligado;
  /// "arquivado" = arquivado. Um agente desligado (ligado=false) e não arquivado fica "a pedido"
  /// na etiqueta, mas com a nota "desligado" (ver [desligado]).
  EstadoAgente get estado {
    if (arquivado) return EstadoAgente.arquivado;
    if (ligado && horarioLigado) return EstadoAgente.relogio;
    return EstadoAgente.aPedido;
  }

  /// Desligado de todo (nem ao relógio nem a pedido): só mostra um aviso pequeno.
  bool get desligado => !arquivado && !ligado;

  factory AgenteEstado.fromMap(Map<String, dynamic> m) => AgenteEstado(
        agente: _texto(m['agente']),
        ligado: _bool(m['ligado']),
        horarioLigado: _bool(m['horario_ligado']),
        arquivado: _bool(m['arquivado']),
        substituto: m['substituto'] as String?,
        cadenciaMin: m['cadencia_min'] == null ? null : _int(m['cadencia_min']),
        tetoDiaEur: _num(m['teto_dia_eur']),
        departamento: _texto(m['departamento']),
        papel: _texto(m['papel']),
        nota: _texto(m['nota']),
        ultimaCorrida: _data(m['ultima_corrida']),
        erro: m['erro'] as String?,
      );

  static String rotuloEstado(EstadoAgente e) => switch (e) {
        EstadoAgente.relogio => 'Ligado ao relógio',
        EstadoAgente.aPedido => 'A pedido',
        EstadoAgente.arquivado => 'Arquivado',
      };
}

/// Auditoria das últimas 24 h de um agente (vista `despacho_auditoria_24h`) ou o total
/// (RPC `despacho_auditoria_resumo()`).
class AuditoriaAgente {
  const AuditoriaAgente({
    this.terminadas = 0,
    this.precisavam = 0,
    this.auditadasOk = 0,
    this.devolvidas = 0,
    this.percentagem,
  });

  final int terminadas;
  final int precisavam;
  final int auditadasOk;
  final int devolvidas;
  final double? percentagem;

  factory AuditoriaAgente.fromMap(Map<String, dynamic> m) => AuditoriaAgente(
        terminadas: _int(m['terminadas']),
        precisavam: _int(m['precisavam']),
        auditadasOk: _int(m['auditadas_ok']),
        devolvidas: _int(m['devolvidas']),
        percentagem: _num(m['percentagem']),
      );
}

// ── Previsão do crédito do Claude ────────────────────────────────────────────

class TopGastoClaude {
  const TopGastoClaude({required this.robo, this.perfil = '', this.usd = 0, this.chamadas = 0});

  final String robo;
  final String perfil;
  final double usd;
  final int chamadas;

  factory TopGastoClaude.fromMap(Map<String, dynamic> m) => TopGastoClaude(
        robo: _texto(m['robo']),
        perfil: _texto(m['perfil']),
        usd: _num(m['usd']) ?? 0,
        chamadas: _int(m['chamadas']),
      );
}

/// Resposta da RPC `admin_credito_claude_previsao()`.
class PrevisaoClaude {
  const PrevisaoClaude({
    this.mes = '',
    this.gastoUsd = 0,
    this.creditoUsd = 0,
    this.previsaoUsd = 0,
    this.faltaUsd = 0,
    this.percentagem,
    this.diaDoMes = 1,
    this.diasNoMes = 30,
    this.estado = '',
    this.top = const [],
  });

  final String mes;
  final double gastoUsd;
  final double creditoUsd;
  final double previsaoUsd;
  final double faltaUsd;
  final double? percentagem;
  final int diaDoMes;
  final int diasNoMes;
  final String estado; // claude | poupanca | gratis
  final List<TopGastoClaude> top;

  factory PrevisaoClaude.fromJson(Object? j) {
    final m = j is Map ? Map<String, dynamic>.from(j) : <String, dynamic>{};
    return PrevisaoClaude(
      mes: _texto(m['mes']),
      gastoUsd: _num(m['gasto_usd']) ?? 0,
      creditoUsd: _num(m['credito_usd']) ?? 0,
      previsaoUsd: _num(m['previsao_usd']) ?? 0,
      faltaUsd: _num(m['falta_usd']) ?? 0,
      percentagem: _num(m['percentagem']),
      diaDoMes: _int(m['dia_do_mes'], 1),
      diasNoMes: _int(m['dias_no_mes'], 30),
      estado: _texto(m['estado']),
      top: [
        for (final e in (m['top'] is List ? m['top'] as List : const []))
          if (e is Map) TopGastoClaude.fromMap(Map<String, dynamic>.from(e)),
      ],
    );
  }

  static String rotuloEstado(String e) => switch (e) {
        'claude' => 'Claude ligado: os robôs usam o crédito.',
        'poupanca' => 'Modo poupança: só o que é importante usa o Claude.',
        'gratis' => 'Rotação grátis: o Claude está de fora até o próximo crédito.',
        _ => '',
      };
}
