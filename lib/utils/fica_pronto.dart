/// "Fica pronto sexta, 21/11, às 15:00" (17/11/2026, missão
/// a3-parte2-quando-chamar-17-11): as lojas que não são de comida prometem o
/// pedido pronto daqui a horas ou dias, e a app diz o dia e a hora em vez de
/// "Chega em ~2900 min". Hora de Lisboa, nunca a do telemóvel.
library;

import 'hora_lisboa.dart';

const List<String> _dias = [
  'segunda', 'terça', 'quarta', 'quinta', 'sexta', 'sábado', 'domingo',
];

/// "hoje às 15:00", "amanhã às 15:00" ou "sexta, 21/11, às 15:00" — o dia e a
/// hora de Lisboa de [instante], vistos em [agora]. As mesmas palavras do
/// servidor (`_texto_dia_hora_lisboa`, migração 20261117130000).
String textoDiaHoraLisboa(DateTime instante, DateTime agora) {
  final p = paredeLisboa(instante);
  final a = paredeLisboa(agora);
  String dd(int n) => n.toString().padLeft(2, '0');
  final hora = '${dd(p.hour)}:${dd(p.minute)}';
  final emDias = DateTime.utc(p.year, p.month, p.day)
      .difference(DateTime.utc(a.year, a.month, a.day))
      .inDays;
  if (emDias == 0) return 'hoje às $hora';
  if (emDias == 1) return 'amanhã às $hora';
  return '${_dias[p.weekday - 1]}, ${dd(p.day)}/${dd(p.month)}, às $hora';
}

/// "Fica pronto sexta, 21/11, às 15:00".
String textoFicaPronto(DateTime instante, DateTime agora) =>
    'Fica pronto ${textoDiaHoraLisboa(instante, agora)}';

/// A partir de quanto tempo à frente a hora prometida deixa de ser um "chega
/// em ~X min" e passa a ser o dia e a hora.
const Duration kProntoLongeDe = Duration(hours: 1);

/// A loja prometeu o pedido pronto para mais de [kProntoLongeDe] à frente?
bool prontoLonge(DateTime? pronto, DateTime agora) =>
    pronto != null && pronto.isAfter(agora.add(kProntoLongeDe));
