// Missão motor-claude-2026-10-31 (Bloco 5) — o crédito da API do Claude no painel /admin/motores.
// Modelos lidos de `platform_settings` (chaves claude_*), `ia_gastos` (livro de gastos) e
// `licoes_robos` (caderno de erros dos robôs). Esquema em
// supabase/migrations_pendentes/20261031_motor_claude_porteiro.sql.
//
// A regra do ritmo é a MESMA do porteiro (VPS porteiro.py e função ia_claude_pode):
//   resta      = crédito lido - gasto desde a leitura
//   parte/dia  = (resta + gasto de hoje) / dias até ao próximo crédito (mínimo 1)

/// Os dois modelos que o painel deixa escolher. Opus nunca aparece (nunca automático).
const String kModeloHaiku = 'claude-haiku-5-5';
const String kModeloSonnet = 'claude-sonnet-5-5';

const Map<String, String> kModelosClaude = {
  kModeloHaiku: 'Haiku 5.5 (rápido e barato)',
  kModeloSonnet: 'Sonnet 5.5 (mais esperto, mais caro)',
};

/// Chaves de `platform_settings` que este cartão lê.
const List<String> kChavesCreditoClaude = [
  'claude_credito_atual_usd',
  'claude_credito_lido_em',
  'claude_credito_validade',
  'claude_proximo_credito',
  'claude_credito_mensal_usd',
  'claude_robos',
];

double? _num(Object? v) {
  if (v == null) return null;
  if (v is num) return v.toDouble();
  return double.tryParse('$v'.replaceAll(',', '.'));
}

DateTime? _data(Object? v) => v == null ? null : DateTime.tryParse('$v');

/// Um lote de crédito promocional (Console > Billing > Créditos promocionais).
class LoteCreditoClaude {
  const LoteCreditoClaude({required this.usd, this.expira, this.origem = ''});

  final double usd;
  final DateTime? expira;
  final String origem;

  static List<LoteCreditoClaude> daLista(Object? v) {
    if (v is! List) return const [];
    final lotes = <LoteCreditoClaude>[];
    for (final e in v) {
      if (e is! Map) continue;
      lotes.add(LoteCreditoClaude(
        usd: _num(e['usd']) ?? 0,
        expira: _data(e['expira']),
        origem: '${e['origem'] ?? ''}',
      ));
    }
    lotes.sort((a, b) => (a.expira ?? DateTime(9999)).compareTo(b.expira ?? DateTime(9999)));
    return lotes;
  }
}

/// Um robô da chave `claude_robos` (interruptor "usar Claude" + modelo).
class RoboClaude {
  const RoboClaude({
    required this.chave,
    required this.nome,
    required this.usar,
    required this.modelo,
    required this.prioridade,
  });

  final String chave;
  final String nome;
  final bool usar;
  final String modelo;
  final int prioridade;

  /// `null` quando o modelo gravado não é Haiku nem Sonnet (ex.: Opus, que o porteiro troca por Sonnet).
  String? get modeloEscolhivel => kModelosClaude.containsKey(modelo) ? modelo : null;

  static List<RoboClaude> doMapa(Map<String, dynamic> robos) {
    final lista = <RoboClaude>[];
    robos.forEach((k, v) {
      if (v is! Map) return; // 'ligado' e outras chaves soltas
      lista.add(RoboClaude(
        chave: k,
        nome: '${v['nome'] ?? k}',
        usar: v['usar'] != false && v['usar'] != 'false',
        modelo: '${v['modelo'] ?? ''}',
        prioridade: (_num(v['prioridade']) ?? 3).toInt(),
      ));
    });
    lista.sort((a, b) {
      final p = a.prioridade.compareTo(b.prioridade);
      return p != 0 ? p : a.nome.compareTo(b.nome);
    });
    return lista;
  }
}

/// Gasto somado de um robô (coluna `robo`, ou `perfil` quando falta).
class GastoRoboClaude {
  GastoRoboClaude(this.robo);

  final String robo;
  double mesUsd = 0;
  double hojeUsd = 0;
  int chamadasMes = 0;
  int chamadasHoje = 0;
}

/// A conta do ritmo, igual ao porteiro. Pura: testável sem banco.
class RitmoCreditoClaude {
  const RitmoCreditoClaude({
    required this.creditoLidoUsd,
    required this.gastoDesdeLeituraUsd,
    required this.gastoHojeUsd,
    required this.diasAteProximo,
  });

  final double creditoLidoUsd;
  final double gastoDesdeLeituraUsd;
  final double gastoHojeUsd;
  final int diasAteProximo;

  double get restaUsd => creditoLidoUsd - gastoDesdeLeituraUsd;

  double get parteDoDiaUsd {
    final base = restaUsd + gastoHojeUsd;
    return (base < 0 ? 0 : base) / diasAteProximo;
  }

  /// Dias de calendário (Lisboa) entre hoje e o próximo crédito, mínimo 1.
  static int diasEntre(DateTime hojeLisboa, DateTime? proximo) {
    if (proximo == null) return 30; // o porteiro usa hoje + 30 quando falta a data
    final h = DateTime.utc(hojeLisboa.year, hojeLisboa.month, hojeLisboa.day);
    final p = DateTime.utc(proximo.year, proximo.month, proximo.day);
    final d = p.difference(h).inDays;
    return d < 1 ? 1 : d;
  }
}

/// Tudo o que o cartão "Crédito Claude" mostra.
class EstadoCreditoClaude {
  const EstadoCreditoClaude({
    required this.settingsAtivos,
    required this.livroAtivo,
    this.creditoLidoUsd,
    this.lidoEm,
    this.lotes = const [],
    this.proximoCredito,
    this.mensalUsd,
    this.ligado = true,
    this.robos = const [],
    this.gastoDesdeLeituraUsd = 0,
    this.gastoHojeUsd = 0,
    this.gastoMesUsd = 0,
    this.chamadasHoje = 0,
    this.gastoPorRobo = const [],
    this.diasAteProximo = 30,
  });

  /// As chaves claude_* existem em platform_settings.
  final bool settingsAtivos;

  /// A tabela ia_gastos existe.
  final bool livroAtivo;

  final double? creditoLidoUsd;
  final DateTime? lidoEm;
  final List<LoteCreditoClaude> lotes;
  final DateTime? proximoCredito;
  final double? mensalUsd;
  final bool ligado;
  final List<RoboClaude> robos;
  final double gastoDesdeLeituraUsd;
  final double gastoHojeUsd;
  final double gastoMesUsd;
  final int chamadasHoje;
  final List<GastoRoboClaude> gastoPorRobo;
  final int diasAteProximo;

  bool get ativado => settingsAtivos && livroAtivo;

  RitmoCreditoClaude get ritmo => RitmoCreditoClaude(
        creditoLidoUsd: creditoLidoUsd ?? 0,
        gastoDesdeLeituraUsd: gastoDesdeLeituraUsd,
        gastoHojeUsd: gastoHojeUsd,
        diasAteProximo: diasAteProximo,
      );

  static double? numero(Object? v) => _num(v);
  static DateTime? data(Object? v) => _data(v);
}

/// Uma lição da tabela `licoes_robos`.
class LicaoRobo {
  const LicaoRobo({
    required this.id,
    required this.robo,
    required this.errou,
    required this.regra,
    this.criadaEm,
    this.origem = '',
    this.vezes = 1,
    this.ativa = true,
    this.arquivadaEm,
    this.arquivadaPor,
    this.editadaEm,
  });

  final int id;
  final String robo;
  final String errou;
  final String regra;
  final DateTime? criadaEm;
  final String origem;
  final int vezes;
  final bool ativa;
  final DateTime? arquivadaEm;
  final String? arquivadaPor;
  final DateTime? editadaEm;

  factory LicaoRobo.fromMap(Map<String, dynamic> m) => LicaoRobo(
        id: (_num(m['id']) ?? 0).toInt(),
        robo: '${m['robo'] ?? ''}',
        errou: '${m['errou'] ?? ''}',
        regra: '${m['regra'] ?? ''}',
        criadaEm: _data(m['criada_em']),
        origem: '${m['origem'] ?? ''}',
        vezes: (_num(m['vezes']) ?? 1).toInt(),
        ativa: m['ativa'] != false,
        arquivadaEm: _data(m['arquivada_em']),
        arquivadaPor: m['arquivada_por'] as String?,
        editadaEm: _data(m['editada_em']),
      );
}
