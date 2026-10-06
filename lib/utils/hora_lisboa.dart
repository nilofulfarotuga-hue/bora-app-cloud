/// Hora de Lisboa a partir de um instante (regra do painel admin: nunca o fuso
/// do navegador). Portugal continental: UTC+0 no inverno, UTC+1 no verão —
/// o verão vai do último domingo de março às 01:00 UTC ao último domingo de
/// outubro às 01:00 UTC (regra da UE).
DateTime horaLisboa(DateTime instante) {
  final l = paredeLisboa(instante);
  // devolve "wall clock" sem fuso, para formatar dia/hora directamente
  return DateTime(l.year, l.month, l.day, l.hour, l.minute, l.second);
}

/// O mesmo relógio de Lisboa que [horaLisboa], mas com a marca UTC: serve só
/// para LER dia da semana, hora e minuto. Um `DateTime` local cai no buraco da
/// mudança de hora do fuso do telemóvel (ex.: Chile, Austrália) e salta uma
/// hora; este não. Nunca para comparar com instantes nem mandar ao servidor.
DateTime paredeLisboa(DateTime instante) {
  final u = instante.toUtc();
  final inicio = DateTime.utc(u.year, 3, _ultimoDomingo(u.year, 3), 1);
  final fim = DateTime.utc(u.year, 10, _ultimoDomingo(u.year, 10), 1);
  final verao = !u.isBefore(inicio) && u.isBefore(fim);
  return u.add(Duration(hours: verao ? 1 : 0));
}

/// Instante (UTC) em que o relógio de Lisboa marca [parede] — o inverso de
/// [horaLisboa]. Só lê ano/mês/dia/hora/minuto/segundo de [parede]: o fuso do
/// telemóvel não entra. Para mandar ao servidor uma hora escolhida no relógio
/// da loja, em vez de `parede.toUtc()` (que usa o fuso do aparelho).
/// Na hora que se repete em outubro devolve a primeira (ainda de verão).
DateTime instanteDeLisboa(DateTime parede) {
  final comoUtc = DateTime.utc(parede.year, parede.month, parede.day,
      parede.hour, parede.minute, parede.second);
  final verao = comoUtc.subtract(const Duration(hours: 1));
  final l = paredeLisboa(verao);
  if (l.day == parede.day && l.hour == parede.hour) return verao;
  return comoUtc;
}

int _ultimoDomingo(int ano, int mes) {
  final ultimo = DateTime.utc(ano, mes + 1, 0); // último dia do mês
  return ultimo.day - (ultimo.weekday % 7); // weekday: domingo = 7
}

/// "22/09 19:05" em hora de Lisboa; "—" se não houver data.
String dataHoraLisboa(Object? iso) {
  final d = DateTime.tryParse('${iso ?? ''}');
  if (d == null) return '—';
  final l = horaLisboa(d);
  String dd(int n) => n.toString().padLeft(2, '0');
  return '${dd(l.day)}/${dd(l.month)} ${dd(l.hour)}:${dd(l.minute)}';
}

/// Instante UTC da meia-noite (Lisboa) do dia de Lisboa que contém [instante].
/// Para filtrar "hoje" em colunas timestamptz sem depender do fuso do telemóvel.
DateTime inicioDiaLisboaUtc(DateTime instante) {
  final u = instante.toUtc();
  final l = horaLisboa(u);
  final desvio = DateTime.utc(l.year, l.month, l.day, l.hour, l.minute, l.second)
      .difference(DateTime.utc(u.year, u.month, u.day, u.hour, u.minute, u.second));
  return DateTime.utc(l.year, l.month, l.day).subtract(desvio);
}
