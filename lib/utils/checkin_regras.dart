// lib/utils/checkin_regras.dart
//
// Regras do check-in diário (Bloco G da missão fechar-tudo-2026-11-10) em funções
// puras. QUEM DECIDE É O SERVIDOR (supabase/migrations/20261110200*_checkin_g_*);
// estas funções dizem só o que o ecrã mostra e espelham as regras para os testes:
//  R2 todo o prémio espera 1 pedido pago ("Falta 1 pedido para desbloquear");
//  R3 "Quero este" recomeça a escada; a semana de tokens só com o interruptor;
//  R4 uma sugestão só: o prémio mais valioso a que já chegou, entre iguais a loja
//     onde mais pediu;
//  R5 perdão: 1 dia falhado por mês, só com compra;
//  R6 teto de custo do mês com aviso aos 80%;
//  R8 lembrete à hora habitual, no máximo 1 por dia, pára depois de 3 falhas.
import '../services/checkin_premios_service.dart';
import 'euros.dart';

/// Como se desenha um dia no caminho dos 30 dias.
enum EstadoDiaCaminho {
  /// Check-in feito (chama).
  feito,

  /// Dia falhado que o perdão do mês segurou (gelo).
  perdoado,

  /// Hoje, ainda por fazer (a brilhar).
  hoje,

  /// Ainda não chegou.
  futuro,
}

/// Estado do dia [dia] da escada. [feitoAte] = último dia já feito (inclui hoje
/// se o check-in de hoje está feito); [hoje] = o dia de hoje na escada.
EstadoDiaCaminho estadoDoDia({
  required int dia,
  required int feitoAte,
  required int hoje,
  List<int> perdoados = const [],
}) {
  if (dia <= feitoAte) {
    return perdoados.contains(dia) ? EstadoDiaCaminho.perdoado : EstadoDiaCaminho.feito;
  }
  if (dia == hoje) return EstadoDiaCaminho.hoje;
  return EstadoDiaCaminho.futuro;
}

/// Um prémio de verdade (produto, serviço ou desconto) — os tokens do Dia 7 não.
bool ehPremio(CheckinMarco m) => m.tipo != 'tokens';

const int _semValor = 0x7fffffff;

/// Valor para comparar: sem valor no painel conta como o maior (o prémio grande
/// do fim, a limpeza/lavagem do dia 30). Igual a `_checkin_marco_valor`.
int valorParaComparar(int? valorCents) =>
    (valorCents != null && valorCents > 0) ? valorCents : _semValor;

/// R4: a melhor sugestão, uma só. Entre os prémios a que já chegou
/// ([diaAtual] = último dia feito da escada), o mais valioso; entre iguais, o da
/// loja onde mais pediu ([pedidosPorLoja]); depois o do dia mais alto.
CheckinMarco? melhorSugestao(
  List<CheckinMarco> marcos,
  int diaAtual, {
  Map<String, int> pedidosPorLoja = const {},
}) {
  final candidatos = marcos.where((m) => ehPremio(m) && m.dia <= diaAtual).toList();
  if (candidatos.isEmpty) return null;
  candidatos.sort((a, b) {
    final v = valorParaComparar(b.valorCents).compareTo(valorParaComparar(a.valorCents));
    if (v != 0) return v;
    final p = (pedidosPorLoja[b.lojaId] ?? 0).compareTo(pedidosPorLoja[a.lojaId] ?? 0);
    if (p != 0) return p;
    return b.dia.compareTo(a.dia);
  });
  return candidatos.first;
}

/// O próximo prémio depois do último dia feito e quantos check-ins faltam.
/// `null` quando já passou o último prémio do ciclo.
({CheckinMarco marco, int faltam, double progresso})? proximoPremio(CheckinPremiosEstado e) {
  final feito = e.diasSeguidos > 0 ? e.diaMarco : 0;
  final premios = e.marcos.where(ehPremio).toList()..sort((a, b) => a.dia.compareTo(b.dia));
  CheckinMarco? proximo;
  var anterior = 0;
  for (final m in premios) {
    if (m.dia > feito) {
      proximo = m;
      break;
    }
    anterior = m.dia;
  }
  if (proximo == null) return null;
  final total = proximo.dia - anterior;
  final andado = (feito - anterior).clamp(0, total);
  return (
    marco: proximo,
    faltam: proximo.dia - feito,
    progresso: total <= 0 ? 0.0 : andado / total,
  );
}

/// "6,30 €" — vazio quando o prémio não tem valor no painel.
String valorEmEuros(int? cents) => (cents == null || cents <= 0) ? '' : eurCents(cents);

/// R2: o prémio ainda espera pelo pedido pago.
bool faltaPedido(CheckinVale v) => v.estado == 'a_espera_pedido';

/// R3: o que acontece amanhã depois de carregar "Quero este" hoje.
/// A escada dos prémios volta sempre ao dia 1; a semana de tokens só volta ao
/// Dia 1 se o interruptor `checkin_quero_este_recomeca_semana` estiver ligado.
({int diaEscadaAmanha, int diaSemanaAmanha}) depoisDeQueroEste({
  required int diaSemanaHoje,
  required bool recomecaSemana,
}) =>
    (
      diaEscadaAmanha: 1,
      diaSemanaAmanha: recomecaSemana ? 1 : (diaSemanaHoje >= 7 ? 1 : diaSemanaHoje + 1),
    );

/// R5: o servidor perdoa o dia falhado? Só 1 dia de cada vez, com o interruptor
/// ligado, com um pedido pago nos últimos 30 dias e com perdões por usar no mês.
bool perdaoPodeAplicar({
  required bool ativo,
  required bool temPedidoPago,
  required int usadosNoMes,
  required int porMes,
  required int diasFalhados,
}) =>
    ativo && temPedidoPago && usadosNoMes < porMes && diasFalhados == 1;

/// R6: como está o custo do mês contra o teto.
enum NivelTecto { semTecto, ok, aviso, esgotado }

({NivelTecto nivel, int? pct}) nivelTecto({
  required int custoCents,
  required int tectoCents,
  required int avisoPct,
  bool ativo = true,
}) {
  if (!ativo || tectoCents <= 0) return (nivel: NivelTecto.semTecto, pct: null);
  final pct = (custoCents * 100) ~/ tectoCents;
  if (custoCents >= tectoCents) return (nivel: NivelTecto.esgotado, pct: pct);
  if (pct >= avisoPct) return (nivel: NivelTecto.aviso, pct: pct);
  return (nivel: NivelTecto.ok, pct: pct);
}

/// R8: esta pessoa recebe hoje o lembrete? Não se já fez hoje, se desligou, se
/// já recebeu um hoje, ou se falhou [maxFalhas] dias seguidos (ou mais).
bool deveReceberLembrete({
  required DateTime? ultimoCheckin,
  required DateTime hoje,
  required int maxFalhas,
  bool desligado = false,
  bool jaRecebeuHoje = false,
}) {
  if (ultimoCheckin == null || desligado || jaRecebeuHoje) return false;
  final u = DateTime.utc(ultimoCheckin.year, ultimoCheckin.month, ultimoCheckin.day);
  final h = DateTime.utc(hoje.year, hoje.month, hoje.day);
  final falhas = h.difference(u).inDays - 1;
  if (falhas < 0) return false; // já fez hoje
  return falhas < maxFalhas;
}
