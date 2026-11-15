// Período das entregas do estafeta: a mesma conta no app (separador Pedidos)
// e no painel admin (ficha do estafeta). app-15-11.
import 'hora_lisboa.dart';

/// Período da lista de entregas do separador "Pedidos" (app-15-11, ordem do
/// Danilo de 15/11 10:14: "seletor de período, abrir/fechar e total").
/// Igual ao ecrã de ganhos da Uber Eats e da Glovo: abre na semana corrente.
enum PeriodoEntregas {
  hoje('Hoje'),
  estaSemana('Esta semana'),
  semanaPassada('Semana passada'),
  esteMes('Este mês');

  const PeriodoEntregas(this.rotulo);
  final String rotulo;
}

/// O dia (de Lisboa) em que [instante] cai, como data UTC à meia-noite —
/// serve só para comparar dias, nunca para mandar ao servidor.
DateTime diaLisboa(DateTime instante) {
  final l = paredeLisboa(instante);
  return DateTime.utc(l.year, l.month, l.day);
}

/// O primeiro dia (de Lisboa) de [periodo], visto a partir de [agora].
/// A semana começa à segunda-feira.
DateTime inicioDoPeriodo(PeriodoEntregas periodo, DateTime agora) {
  final hoje = diaLisboa(agora);
  final segunda = hoje.subtract(Duration(days: hoje.weekday - 1));
  switch (periodo) {
    case PeriodoEntregas.hoje:
      return hoje;
    case PeriodoEntregas.estaSemana:
      return segunda;
    case PeriodoEntregas.semanaPassada:
      return segunda.subtract(const Duration(days: 7));
    case PeriodoEntregas.esteMes:
      return DateTime.utc(hoje.year, hoje.month, 1);
  }
}

/// A entrega feita em [quando] conta para [periodo], visto a partir de
/// [agora]? Dias no relógio de Lisboa.
bool entregaNoPeriodo(
    DateTime quando, PeriodoEntregas periodo, DateTime agora) {
  final dia = diaLisboa(quando);
  final inicio = inicioDoPeriodo(periodo, agora);
  final fim = periodo == PeriodoEntregas.semanaPassada
      ? inicioDoPeriodo(PeriodoEntregas.estaSemana, agora)
          .subtract(const Duration(days: 1))
      : diaLisboa(agora);
  return !dia.isBefore(inicio) && !dia.isAfter(fim);
}
