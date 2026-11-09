// Depósito Volta (09/11/2026, ramo ai/2026-11-09-volta-deposito-kfc) — a
// lógica pura do painel admin (PT-BR): filtros, dinheiro, CSV, relatório
// mensal e o cartão do pedido. Sem Flutter nem Supabase, para se testar à
// parte (test/admin_volta_screen_test.dart).
//
// O depósito é 0,10 € por embalagem (latas e garrafas de plástico até 3 L).
// O servidor cobra-o ao cliente numa linha à parte (fora do subtotal, sem
// margem, taxas nem tokens). Parceiro: vai 100% para a loja no acerto
// semanal. Não-parceiro: fica com a Bora (o estafeta pagou-o no balcão).

/// Mensagem quando a função/coluna do servidor ainda não foi publicada.
const String kVoltaFuncaoNaoPublicada = 'Função ainda não está no servidor';

/// Máximo de embalagens com depósito num produto/opção (ex.: pack de 48 latas).
const int kVoltaUnidadesMax = 48;

/// Os quatro filtros da lista de produtos e opções.
enum FiltroVolta { todos, com, sem, rever }

/// Valor de `p_filtro` da RPC `admin_volta_produtos`.
String filtroVoltaParaRpc(FiltroVolta f) => switch (f) {
      FiltroVolta.todos => 'todos',
      FiltroVolta.com => 'com',
      FiltroVolta.sem => 'sem',
      FiltroVolta.rever => 'rever',
    };

/// Rótulo do chip (PT-BR).
String rotuloFiltroVolta(FiltroVolta f) => switch (f) {
      FiltroVolta.todos => 'Todos',
      FiltroVolta.com => 'Com Volta',
      FiltroVolta.sem => 'Sem Volta',
      FiltroVolta.rever => 'Rever',
    };

/// 10 → '0,10 €'; -20 → '-0,20 €'; com [comSinal], 20 → '+0,20 €'.
String eurosDeCentimos(num? centimos, {bool comSinal = false}) {
  final c = (centimos ?? 0).round();
  final valor = (c.abs() / 100).toStringAsFixed(2).replaceAll('.', ',');
  final sinal = c < 0 ? '-' : (comSinal && c > 0 ? '+' : '');
  return '$sinal$valor €';
}

/// Número vindo do servidor (`numeric` pode chegar como número ou texto).
num? numVolta(Object? v) => v is num ? v : num.tryParse('${v ?? ''}');

/// Preço em euros (a RPC devolve `numeric` em euros). null → '—'.
String precoVolta(num? euros) =>
    euros == null ? '—' : eurosDeCentimos(euros * 100);

/// De onde veio o número de embalagens (`deposit_origem`).
String rotuloOrigemVolta(String? origem) => switch (origem) {
      null || '' => 'sem origem',
      'admin' => 'painel',
      _ => origem,
    };

/// Texto do campo de embalagens → inteiro 0..[kVoltaUnidadesMax], ou null.
int? validarUnidadesVolta(String texto) {
  final n = int.tryParse(texto.trim());
  if (n == null || n < 0 || n > kVoltaUnidadesMax) return null;
  return n;
}

/// Um campo de CSV: vai entre aspas quando tem ';', ',', aspas ou quebra de
/// linha; as aspas de dentro dobram-se.
String campoCsvVolta(Object? valor) {
  final s = (valor ?? '').toString();
  return RegExp(r'[;,"\r\n]').hasMatch(s) ? '"${s.replaceAll('"', '""')}"' : s;
}

/// Cabeçalho do CSV dos produtos e opções.
const List<String> kCabecalhoCsvVolta = [
  'tipo', 'id', 'loja', 'nome', 'categoria', 'preco', //
  'deposit_units', 'rever', 'origem',
];

/// CSV (separador ';', o que o Excel em português abre em colunas; preço com
/// vírgula decimal) das linhas devolvidas por `admin_volta_produtos`.
String csvDepositoVolta(List<Map<String, dynamic>> linhas) {
  final saida = <String>[kCabecalhoCsvVolta.join(';')];
  for (final r in linhas) {
    final preco = numVolta(r['preco']);
    saida.add([
      r['tipo'],
      r['id'],
      r['loja_nome'] ?? r['loja_id'],
      r['nome'],
      r['categoria'],
      preco == null ? '' : preco.toStringAsFixed(2).replaceAll('.', ','),
      numVolta(r['deposit_units'])?.toInt() ?? 0,
      r['deposit_review'] == true ? 'sim' : 'não',
      r['deposit_origem'],
    ].map(campoCsvVolta).join(';'));
  }
  return saida.join('\r\n');
}

/// Vai buscar todas as páginas de uma RPC paginada (`p_limite`/`p_offset`,
/// com `total` em cada linha). Para quando a página vem vazia ou curta,
/// quando já tem o `total`, ou no [maximo] (trava contra um ciclo sem fim).
Future<List<Map<String, dynamic>>> buscarTodasAsPaginasVolta(
  Future<List<Map<String, dynamic>>> Function(int offset, int limite) buscar, {
  int limite = 500,
  int maximo = 20000,
}) async {
  final todas = <Map<String, dynamic>>[];
  var offset = 0;
  while (todas.length < maximo) {
    final pagina = await buscar(offset, limite);
    if (pagina.isEmpty) break;
    todas.addAll(pagina);
    offset += pagina.length;
    final total = numVolta(pagina.first['total'])?.toInt();
    if (pagina.length < limite) break;
    if (total != null && todas.length >= total) break;
  }
  return todas.length > maximo ? todas.sublist(0, maximo) : todas;
}

/// As linhas do relatório mensal (`admin_volta_relatorio_mensal`), por ordem.
List<(String, String)> linhasRelatorioVolta(Map<String, dynamic> r) {
  int n(String k) => numVolta(r[k])?.round() ?? 0;
  return [
    ('Pedidos com depósito', '${n('pedidos')}'),
    ('Embalagens', '${n('embalagens')}'),
    ('Cobrado aos clientes', eurosDeCentimos(n('cobrado_cents'))),
    ('Acertos (talão/falta)', eurosDeCentimos(n('ajustes_cents'), comSinal: true)),
    ('Lido nos talões', eurosDeCentimos(n('talao_cents'))),
    ('Entregue aos parceiros', eurosDeCentimos(n('parceiros_cents'))),
    ('Fica com a Bora (não-parceiros)', eurosDeCentimos(n('bora_cents'))),
  ];
}

/// CSV do relatório mensal ('2026-11' → uma linha por rubrica).
String csvRelatorioVolta(String mes, Map<String, dynamic> r) => [
      'mes;rubrica;valor',
      for (final l in linhasRelatorioVolta(r))
        [mes, l.$1, l.$2].map(campoCsvVolta).join(';'),
    ].join('\r\n');

/// O que as chaves `volta_deposit_*` dizem hoje (linhas de
/// `admin_list_settings`). Valores que faltam ficam null.
({bool? ligado, int? centimos}) lerConfigVolta(List<Map<String, dynamic>> linhas) {
  bool? ligado;
  int? centimos;
  for (final s in linhas) {
    final v = s['value'];
    switch (s['key']) {
      case 'volta_deposit_enabled':
        ligado = v is bool ? v : (v == null ? null : '$v'.toLowerCase() == 'true');
      case 'volta_deposit_cents':
        centimos = v is num ? v.round() : int.tryParse('${v ?? ''}');
    }
  }
  return (ligado: ligado, centimos: centimos);
}

/// O depósito de UM pedido (as 4 colunas de `orders`), para o cartão do
/// detalhe do pedido no painel. `deposit_ajuste_cents` tem sinal: positivo =
/// diferença cobrada ao cliente; negativo = diferença devolvida.
class DepositoVoltaPedido {
  const DepositoVoltaPedido({
    required this.unidades,
    required this.cobradoCents,
    required this.ajusteCents,
    this.talaoCents,
  });

  final int unidades;
  final int cobradoCents;
  final int ajusteCents;
  final int? talaoCents;

  /// null quando o servidor ainda não tem as colunas (consulta falhou).
  static DepositoVoltaPedido? daLinha(Map<String, dynamic>? r) {
    if (r == null) return null;
    int? n(String k) => numVolta(r[k])?.round();
    return DepositoVoltaPedido(
      unidades: n('deposit_units') ?? 0,
      cobradoCents: n('deposit_cents') ?? 0,
      ajusteCents: n('deposit_ajuste_cents') ?? 0,
      talaoCents: n('deposit_from_receipt_cents'),
    );
  }

  /// Nada a mostrar: tudo a zero ou vazio.
  bool get vazio =>
      unidades == 0 &&
      cobradoCents == 0 &&
      ajusteCents == 0 &&
      (talaoCents ?? 0) == 0;

  int get totalFinalCents => cobradoCents + ajusteCents;

  /// '+0,20 € (diferença cobrada)' · '-0,10 € (diferença devolvida)'.
  String get acertoTexto => ajusteCents > 0
      ? '${eurosDeCentimos(ajusteCents, comSinal: true)} (diferença cobrada)'
      : ajusteCents < 0
          ? '${eurosDeCentimos(ajusteCents)} (diferença devolvida)'
          : '0,00 € (sem acertos)';
}
