// Dias úteis em Portugal (missão fechar-tudo-2026-11-10, bloco E2e).
//
// O Livro de Reclamações obriga a responder ao consumidor em 15 dias ÚTEIS
// (DL 156/2005, art. 5.º-B). Dia útil = de segunda a sexta, menos os feriados
// nacionais obrigatórios (Código do Trabalho, art. 234.º). O feriado municipal
// da Guarda NÃO entra de propósito: sem ele o prazo calculado fica, no máximo,
// um dia mais CURTO do que o legal — nunca mais longo.
//
// Só datas (sem horas): tudo se faz com DateTime(ano, mês, dia) locais, e
// soma-se dia a dia por DateTime(a, m, d + 1) para a mudança de hora não
// estragar as contas.

DateTime soData(DateTime d) => DateTime(d.year, d.month, d.day);

DateTime _diaSeguinte(DateTime d) => DateTime(d.year, d.month, d.day + 1);

/// Domingo de Páscoa (calendário gregoriano; algoritmo de Meeus/Jones/Butcher).
DateTime domingoDePascoa(int ano) {
  final a = ano % 19;
  final b = ano ~/ 100;
  final c = ano % 100;
  final d = b ~/ 4;
  final e = b % 4;
  final f = (b + 8) ~/ 25;
  final g = (b - f + 1) ~/ 3;
  final h = (19 * a + b - d - g + 15) % 30;
  final i = c ~/ 4;
  final k = c % 4;
  final l = (32 + 2 * e + 2 * i - h - k) % 7;
  final m = (a + 11 * h + 22 * l) ~/ 451;
  final n = h + l - 7 * m + 114;
  return DateTime(ano, n ~/ 31, (n % 31) + 1);
}

/// Feriados nacionais obrigatórios de [ano] (Código do Trabalho, art. 234.º).
Set<DateTime> feriadosNacionais(int ano) {
  final pascoa = domingoDePascoa(ano);
  return {
    DateTime(ano, 1, 1), // Ano Novo
    DateTime(pascoa.year, pascoa.month, pascoa.day - 2), // Sexta-feira Santa
    pascoa, // Páscoa
    DateTime(ano, 4, 25), // Dia da Liberdade
    DateTime(ano, 5, 1), // Dia do Trabalhador
    DateTime(pascoa.year, pascoa.month, pascoa.day + 60), // Corpo de Deus
    DateTime(ano, 6, 10), // Dia de Portugal
    DateTime(ano, 8, 15), // Assunção
    DateTime(ano, 10, 5), // Implantação da República
    DateTime(ano, 11, 1), // Todos os Santos
    DateTime(ano, 12, 1), // Restauração da Independência
    DateTime(ano, 12, 8), // Imaculada Conceição
    DateTime(ano, 12, 25), // Natal
  };
}

bool eFeriadoNacional(DateTime d) =>
    feriadosNacionais(d.year).contains(soData(d));

bool eDiaUtil(DateTime d) =>
    d.weekday != DateTime.saturday &&
    d.weekday != DateTime.sunday &&
    !eFeriadoNacional(d);

/// O [n]-ésimo dia útil DEPOIS de [inicio] (o dia da receção não conta).
/// Ex.: recebida a terça 10/11/2026 → 15 dias úteis → quarta 02/12/2026
/// (o 01/12 é feriado).
DateTime somarDiasUteis(DateTime inicio, int n) {
  var d = soData(inicio);
  var contados = 0;
  while (contados < n) {
    d = _diaSeguinte(d);
    if (eDiaUtil(d)) contados++;
  }
  return d;
}

/// Dias úteis de [hoje] (exclusive) até [prazo] (inclusive). 0 = o prazo é
/// hoje (ou só há fins de semana/feriados pelo meio). Negativo = dias úteis
/// já passados depois do prazo.
int diasUteisAtePrazo(DateTime hoje, DateTime prazo) {
  final h = soData(hoje);
  final p = soData(prazo);
  if (h == p) return 0;
  final (de, ate, sinal) = h.isBefore(p) ? (h, p, 1) : (p, h, -1);
  var n = 0;
  var d = de;
  while (d.isBefore(ate)) {
    d = _diaSeguinte(d);
    if (eDiaUtil(d)) n++;
  }
  return sinal * n;
}

/// Prazo de resposta ao Livro de Reclamações: 15 dias úteis.
const int kDiasUteisLivroReclamacoes = 15;

/// Faltando isto ou menos, o painel avisa.
const int kDiasUteisAlertaReclamacao = 3;

enum EstadoPrazoReclamacao { emDia, alerta, vencido, respondida }

EstadoPrazoReclamacao estadoDoPrazo({
  required DateTime hoje,
  required DateTime prazo,
  bool respondida = false,
}) {
  if (respondida) return EstadoPrazoReclamacao.respondida;
  if (soData(hoje).isAfter(soData(prazo))) return EstadoPrazoReclamacao.vencido;
  return diasUteisAtePrazo(hoje, prazo) <= kDiasUteisAlertaReclamacao
      ? EstadoPrazoReclamacao.alerta
      : EstadoPrazoReclamacao.emDia;
}

/// Quantas reclamações abertas estão vencidas e quantas a vencer (≤3 dias
/// úteis), para o aviso no painel.
({int vencidas, int aVencer}) resumoPrazos(
    Iterable<DateTime> prazosAbertos, DateTime hoje) {
  var vencidas = 0;
  var aVencer = 0;
  for (final p in prazosAbertos) {
    switch (estadoDoPrazo(hoje: hoje, prazo: p)) {
      case EstadoPrazoReclamacao.vencido:
        vencidas++;
      case EstadoPrazoReclamacao.alerta:
        aVencer++;
      case EstadoPrazoReclamacao.emDia:
      case EstadoPrazoReclamacao.respondida:
        break;
    }
  }
  return (vencidas: vencidas, aVencer: aVencer);
}
