import 'hora_lisboa.dart';

/// Atalho para o painel admin: `instante.toLisboa()` em vez de `toLocal()`.
/// O painel mostra SEMPRE a hora de Lisboa, seja qual for o fuso do navegador
/// (regra painel-admin-limpo). Devolve o "relógio de parede" de Lisboa, só para
/// MOSTRAR ou comparar dias — nunca para mandar de volta ao servidor.
extension HoraLisboaExt on DateTime {
  DateTime toLisboa() => horaLisboa(this);
}

/// Início do dia de HOJE em Lisboa, como instante UTC (para mandar ao
/// servidor nos contadores "de hoje" — nunca a meia-noite do navegador).
DateTime inicioDoDiaLisboaUtc([DateTime? agora]) {
  final nowUtc = (agora ?? DateTime.now()).toUtc();
  final l = horaLisboa(nowUtc);
  final desvio = DateTime.utc(l.year, l.month, l.day, l.hour, l.minute, l.second)
      .difference(DateTime.utc(nowUtc.year, nowUtc.month, nowUtc.day,
          nowUtc.hour, nowUtc.minute, nowUtc.second));
  return DateTime.utc(l.year, l.month, l.day).subtract(desvio);
}
