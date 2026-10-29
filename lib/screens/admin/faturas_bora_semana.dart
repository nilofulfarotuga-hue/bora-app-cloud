import '../../services/admin_export_service.dart';

/// Faturas da Bora por pedido (`bora_invoices_pending`, lidas pelo
/// `admin_bora_invoices_month`) no "Fecho do mês" do painel — missão
/// missao-geral-2026-10-28, H2 e N4.
///
///  - Filtro por SEMANA, de segunda a domingo (uma semana pode apanhar dois
///    meses: o ecrã junta as linhas dos dois).
///  - CSV (planilha para Excel, separador ';', vírgula nas casas decimais)
///    com data, pedido (id curto), cliente, NIF, valor, base e IVA 23%.
///
/// Regra do IVA, pela DATA da fatura:
///  - de 01/11/2026 em diante o valor já tem o IVA 23% incluído:
///    base = valor ÷ 1,23 (arredondada ao cêntimo) e IVA = valor − base;
///  - até 31/10/2026 (isenção do art. 53.º do CIVA, M10): base = valor, IVA 0.
/// As contas são feitas em cêntimos inteiros. Nada aqui envia nada a ninguém.
class FaturasBoraSemana {
  FaturasBoraSemana._();

  /// Primeiro dia com IVA 23% incluído nas faturas da Bora.
  static final DateTime inicioIvaNormal = DateTime(2026, 11, 1);

  /// Texto da coluna "Regime" quando a linha não traz o do servidor
  /// (`bora_invoices_pending.iva`).
  static const regimeIsento = 'IVA — regime de isenção (art. 53.º CIVA), M10';
  static const regimeNormal = 'IVA 23% incluído — regime normal';

  static const cabecalho = <String>[
    'Data',
    'Pedido',
    'Cliente',
    'NIF',
    'Valor (EUR)',
    'Base (EUR)',
    'IVA 23% (EUR)',
    'Regime',
    'Descrição',
    'Estado',
  ];

  // ─────────────────────────── semanas ───────────────────────────

  /// Segunda-feira da semana de [d] (só a data, sem horas).
  static DateTime segundaFeira(DateTime d) =>
      DateTime(d.year, d.month, d.day - (d.weekday - DateTime.monday));

  /// Domingo da semana que começa em [segunda].
  static DateTime domingo(DateTime segunda) =>
      DateTime(segunda.year, segunda.month, segunda.day + 6);

  /// As segundas-feiras das semanas que tocam o mês (a primeira pode começar
  /// no mês anterior e a última acabar no seguinte).
  static List<DateTime> semanasDoMes(int ano, int mes) {
    final ultimo = DateTime(ano, mes + 1, 0);
    final out = <DateTime>[];
    var s = segundaFeira(DateTime(ano, mes, 1));
    while (!s.isAfter(ultimo)) {
      out.add(s);
      s = DateTime(s.year, s.month, s.day + 7);
    }
    return out;
  }

  /// Os meses (ano, mês) por onde passa a semana — um ou dois.
  static List<(int, int)> mesesDaSemana(DateTime segunda) {
    final ini = segundaFeira(segunda);
    final fim = domingo(ini);
    return [
      (ini.year, ini.month),
      if (fim.month != ini.month || fim.year != ini.year) (fim.year, fim.month),
    ];
  }

  static String _dm(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}';

  /// "27/10 a 02/11".
  static String rotuloSemana(DateTime segunda) =>
      '${_dm(segunda)} a ${_dm(domingo(segunda))}';

  /// A data da linha ('AAAA-MM-DD' do servidor), ou null.
  static DateTime? dataDaLinha(Object? v) {
    final m = RegExp(r'^(\d{4})-(\d{2})-(\d{2})').firstMatch('${v ?? ''}');
    if (m == null) return null;
    return DateTime(
        int.parse(m.group(1)!), int.parse(m.group(2)!), int.parse(m.group(3)!));
  }

  /// As linhas da semana que começa em [segunda] (segunda a domingo, os dois
  /// dias incluídos), sem repetidas, por data.
  static List<Map<String, dynamic>> daSemana(
      Iterable<Map<String, dynamic>> linhas, DateTime segunda) {
    final ini = segundaFeira(segunda);
    final fim = domingo(ini);
    final vistos = <String>{};
    final out = <Map<String, dynamic>>[];
    for (final l in linhas) {
      final d = dataDaLinha(l['data']);
      if (d == null || d.isBefore(ini) || d.isAfter(fim)) continue;
      if (!vistos.add('${l['id'] ?? l['order_id']}')) continue;
      out.add(l);
    }
    String chave(Map<String, dynamic> l) => '${l['data']}|${l['created_at'] ?? ''}';
    out.sort((a, b) => chave(a).compareTo(chave(b)));
    return out;
  }

  // ─────────────────────────── valores ───────────────────────────

  /// Euros (número ou texto) → cêntimos inteiros.
  static int cents(Object? v) {
    final n = v is num ? v : num.tryParse('${v ?? ''}') ?? 0;
    return (n * 100).round();
  }

  /// Base e IVA, em cêntimos, de um valor com o IVA incluído.
  static ({int base, int iva}) baseEIva(int valorCents, DateTime data) {
    if (data.isBefore(inicioIvaNormal)) return (base: valorCents, iva: 0);
    final base = (valorCents / 1.23).round();
    return (base: base, iva: valorCents - base);
  }

  /// 1234 → "12,34" (vírgula decimal, como o Excel em português).
  static String eur(int cents) {
    final a = cents.abs();
    return '${cents < 0 ? '-' : ''}${a ~/ 100},${(a % 100).toString().padLeft(2, '0')}';
  }

  static String idCurto(Object? id) {
    final s = '${id ?? ''}';
    return s.length > 8 ? s.substring(0, 8) : s;
  }

  static String? nif(Map<String, dynamic> l) {
    final s = '${l['cliente_nif'] ?? ''}'.trim();
    return s.isEmpty ? null : s;
  }

  /// O nome da fatura, ou "Consumidor final".
  static String cliente(Map<String, dynamic> l) {
    final s = '${l['cliente_nome'] ?? ''}'.trim();
    return s.isEmpty ? 'Consumidor final' : s;
  }

  static bool ehTaxaCancelamento(Map<String, dynamic> l) =>
      '${l['descricao'] ?? ''}'.toLowerCase().startsWith('taxa de cancelamento');

  /// O regime que o servidor gravou na linha; sem ele, o da data.
  static String regime(Map<String, dynamic> l, DateTime data) {
    final s = '${l['iva'] ?? ''}'.trim();
    if (s.isNotEmpty) return s;
    return data.isBefore(inicioIvaNormal) ? regimeIsento : regimeNormal;
  }

  static String estado(Object? e) => switch ('${e ?? ''}') {
        'por_lancar' => 'por lançar',
        'lancada' => 'lançada',
        'sem_valor' => 'sem valor',
        final x => x,
      };

  /// Só as linhas que são fatura a emitir (as 'sem_valor' ficam de fora).
  static Iterable<Map<String, dynamic>> comValor(
          Iterable<Map<String, dynamic>> linhas) =>
      linhas.where((l) => l['estado'] != 'sem_valor');

  /// As linhas do CSV (sem o cabeçalho).
  static List<List<String>> linhasCsv(Iterable<Map<String, dynamic>> linhas) {
    final out = <List<String>>[];
    for (final l in comValor(linhas)) {
      final d = dataDaLinha(l['data']);
      if (d == null) continue;
      final v = cents(l['valor']);
      final b = baseEIva(v, d);
      out.add([
        '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}',
        idCurto(l['order_id']),
        cliente(l),
        nif(l) ?? '',
        eur(v),
        eur(b.base),
        eur(b.iva),
        regime(l, d),
        '${l['descricao'] ?? ''}',
        estado(l['estado']),
      ]);
    }
    return out;
  }

  /// O CSV inteiro (sem a marca BOM: o `exportCsvText` põe-na).
  static String csv(Iterable<Map<String, dynamic>> linhas) => [
        AdminExportService.linhaCsv(cabecalho),
        for (final r in linhasCsv(linhas)) AdminExportService.linhaCsv(r),
      ].join('\n');

  /// A nota do IVA que o `admin_monthly_closeout` devolve: a chave
  /// `nota_iva` quando o servidor a tiver; senão, a frase "IVA: ..." do
  /// texto "para as Finanças". Null se o servidor não disser nada.
  static String? notaIva(Map<String, dynamic> paraAsFinancas) {
    final n = '${paraAsFinancas['nota_iva'] ?? ''}'.trim();
    if (n.isNotEmpty) return n;
    final m = RegExp(r'IVA:.*$', dotAll: true)
        .firstMatch('${paraAsFinancas['texto'] ?? ''}');
    final s = m?.group(0)?.trim();
    return (s == null || s.isEmpty) ? null : s;
  }
}
