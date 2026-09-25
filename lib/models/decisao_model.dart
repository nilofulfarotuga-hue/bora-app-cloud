// Missão jev-decisor-2026-09-23 — uma linha da tabela `decisoes` (o Decisor: Jev com
// Gemini de reserva). Só leitura no painel admin; quem escreve é a Edge Function `decidir`.

/// As quatro regras do decisor, pela ordem em que aparecem no painel.
const List<String> kRegrasDecisor = ['despacho', 'noshow', 'robotb', 'suporte'];

/// Nome que o Danilo lê para cada regra (PT-BR, painel admin).
String rotuloRegraDecisor(String regra) {
  switch (regra) {
    case 'despacho':
      return 'Escolha do entregador/motorista';
    case 'noshow':
      return 'Risco de falta na marcação';
    case 'robotb':
      return 'Robot B: vale abrir a sugestão?';
    case 'suporte':
      return 'Suporte: passar para humano?';
    default:
      return regra;
  }
}

/// Só o Robot B tem modo ativo ligado a uma ação (arquivar a sugestão). O despacho é
/// zona protegida; no-show e suporte ainda não têm ação definida — o servidor recusa.
bool regraAceitaAtivo(String regra) => regra == 'robotb';

class Decisao {
  final String id;
  final DateTime quando;
  final String tipo; // choice | score | noul
  final String pergunta;
  final String? estadoResumo;
  final String? resposta;
  final double? confianca;
  final Map<String, double> probabilidades;
  final String motor; // jev | gemini | fallback (regra determinística) | nenhum
  final String? modelo;
  final int? latenciaMs;
  final int? tokensEntrada;
  final double? custoUsd;
  final String usadoPor;
  final String? contextoId;
  final String modo; // sombra | ativo | teste
  final String? acaoTomada;
  final String? erro;
  final String? resultadoReal;

  const Decisao({
    required this.id,
    required this.quando,
    required this.tipo,
    required this.pergunta,
    this.estadoResumo,
    this.resposta,
    this.confianca,
    this.probabilidades = const {},
    required this.motor,
    this.modelo,
    this.latenciaMs,
    this.tokensEntrada,
    this.custoUsd,
    required this.usadoPor,
    this.contextoId,
    required this.modo,
    this.acaoTomada,
    this.erro,
    this.resultadoReal,
  });

  factory Decisao.fromMap(Map<String, dynamic> m) {
    final probs = <String, double>{};
    final raw = m['probabilidades'];
    if (raw is Map) {
      raw.forEach((k, v) {
        if (v is num) probs[k.toString()] = v.toDouble();
      });
    }
    return Decisao(
      id: m['id'].toString(),
      quando: DateTime.tryParse(m['quando']?.toString() ?? '')?.toLocal() ?? DateTime.now(),
      tipo: (m['tipo'] ?? '').toString(),
      pergunta: (m['pergunta'] ?? '').toString(),
      estadoResumo: m['estado_resumo']?.toString(),
      resposta: m['resposta']?.toString(),
      confianca: (m['confianca'] as num?)?.toDouble(),
      probabilidades: probs,
      motor: (m['motor'] ?? 'nenhum').toString(),
      modelo: m['modelo']?.toString(),
      latenciaMs: (m['latencia_ms'] as num?)?.toInt(),
      tokensEntrada: (m['tokens_entrada'] as num?)?.toInt(),
      custoUsd: (m['custo_usd'] as num?)?.toDouble(),
      usadoPor: (m['usado_por'] ?? '').toString(),
      contextoId: m['contexto_id']?.toString(),
      modo: (m['modo'] ?? 'sombra').toString(),
      acaoTomada: m['acao_tomada']?.toString(),
      erro: m['erro']?.toString(),
      resultadoReal: m['resultado_real']?.toString(),
    );
  }

  /// Resposta em palavras para o painel (PT-BR).
  String get respostaLegivel {
    if (motor == 'nenhum' || (resposta ?? '').isEmpty) return 'sem decisão';
    switch (tipo) {
      case 'noul':
        return resposta == 'sim' ? 'Sim' : 'Não';
      case 'score':
        return 'nota $resposta';
      default:
        return resposta!;
    }
  }

  /// Acertou? null enquanto não se sabe o que aconteceu (ou quando não há decisão).
  /// No-show: nota >= 2 (risco médio ou mais) acerta se a pessoa faltou.
  bool? get acertou {
    final real = resultadoReal;
    if (real == null || motor == 'nenhum' || resposta == null) return null;
    if (tipo == 'score') {
      final nota = double.tryParse(resposta!);
      if (nota == null) return null;
      return (nota >= 2) == (real == 'faltou');
    }
    return resposta == real;
  }
}

/// Custo total de hoje (USD) somando os motores do resumo do servidor
/// (`admin_decisor_resumo().hoje`).
double custoHojeUsd(Map<String, dynamic>? hoje) {
  if (hoje == null) return 0;
  var total = 0.0;
  for (final v in hoje.values) {
    if (v is Map && v['custo_usd'] is num) total += (v['custo_usd'] as num).toDouble();
  }
  return total;
}

/// Soma de um campo inteiro (chamadas, tokens_entrada...) em todos os motores de hoje.
int somaHoje(Map<String, dynamic>? hoje, String campo) {
  if (hoje == null) return 0;
  var total = 0;
  for (final v in hoje.values) {
    if (v is Map && v[campo] is num) total += (v[campo] as num).toInt();
  }
  return total;
}

/// Filtra a lista pelo que o Danilo escolheu nos chips (null = todos).
List<Decisao> filtrarDecisoes(List<Decisao> todas, {String? tipo, String? motor, String? usadoPor}) {
  return todas
      .where((d) =>
          (tipo == null || d.tipo == tipo) &&
          (motor == null || d.motor == motor) &&
          (usadoPor == null || d.usadoPor == usadoPor))
      .toList();
}

/// Quantas linhas ficaram pela regra determinística (motor 'fallback': os dois motores
/// falharam — Gemini 429/503, Jev sem chave). O painel mostra este número por cima dos
/// filtros para o Danilo ver quando o decisor andou "às escuras". (fecho-manha-2026-09-24)
int contarFallbacks(List<Decisao> todas) => todas.where((d) => d.motor == 'fallback').length;
