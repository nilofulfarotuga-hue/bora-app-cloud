/// AGENDAR PEDIDOS (item 5 do adendo 5, 29/10/2026) — a lógica PURA: janelas de
/// 30 minutos dentro do horário da loja, textos e contas de tempo. Sem rede,
/// sem Supabase, sem ecrãs: por isso é fácil de provar (ver
/// `test/agendar_pedido_janelas_test.dart`, com o horário da Boom).
///
/// Tudo corre no relógio de LISBOA (a Bora só opera em Portugal e o servidor
/// decide pela hora de Lisboa): `inicio`/`fim` de uma [JanelaAgendada] são
/// "paredes" de Lisboa com marca UTC — servem para LER dia, hora e minuto e
/// nunca para comparar com instantes; o instante verdadeiro (o que se manda ao
/// servidor) sai de [JanelaAgendada.instante].
///
/// As regras são as do servidor (`scheduled_windows_for_store`, migração
/// 20261029200700): janelas de 30 min alinhadas às :00 e :30 que cabem INTEIRAS
/// dentro de cada período aberto (antes e depois da pausa do dia), com dias
/// especiais (feriados) por cima do dia da semana, antecedência mínima e
/// máximo de dias.
library;

import '../l10n/bora_lang.dart';
import '../l10n/tr.dart';
import '../models/restaurant_model.dart';
import '../utils/hora_lisboa.dart';

/// Largura de cada janela, em minutos.
const int kAgendarJanelaMinutos = 30;

/// Máximo de dias à frente (valor de origem; o servidor pode mudá-lo).
const int kAgendarMaxDiasPadrao = 7;

/// Antecedência mínima entre o pedido e o início da janela, em minutos.
const int kAgendarAntecedenciaPadraoMin = 60;

/// Aviso ao parceiro: quantos minutos antes da hora marcada.
const int kAgendarAvisoParceiroMin = 30;

/// Uma janela de entrega de 30 minutos.
class JanelaAgendada {
  const JanelaAgendada({required this.inicio, required this.fim});

  /// Relógio de Lisboa (marca UTC). Ver o cabeçalho do ficheiro.
  final DateTime inicio;
  final DateTime fim;

  /// O instante real do início (UTC), o que segue para o servidor.
  DateTime get instante => instanteDeLisboa(inicio);

  /// O dia (Lisboa) da janela, à meia-noite.
  DateTime get dia => DateTime.utc(inicio.year, inicio.month, inicio.day);

  /// "19:30–20:00". Uma janela que acaba à meia-noite mostra "24:00".
  String get horas {
    final fimTxt = (fim.day != inicio.day) ? '24:00' : _hhmm(fim);
    return '${_hhmm(inicio)}–$fimTxt';
  }

  @override
  bool operator ==(Object other) =>
      other is JanelaAgendada && other.inicio == inicio && other.fim == fim;

  @override
  int get hashCode => Object.hash(inicio, fim);

  @override
  String toString() => 'JanelaAgendada($inicio → $fim)';
}

String _dois(int n) => n.toString().padLeft(2, '0');
String _hhmm(DateTime d) => '${_dois(d.hour)}:${_dois(d.minute)}';

int? _minutos(String? hhmm) {
  if (hhmm == null) return null;
  final partes = hhmm.trim().split(':');
  if (partes.length != 2) return null;
  final h = int.tryParse(partes[0]);
  final m = int.tryParse(partes[1]);
  if (h == null || m == null || h < 0 || h > 24 || m < 0 || m > 59) return null;
  return h * 60 + m;
}

/// Só o dia (ano/mês/dia) de [d], em UTC à meia-noite.
DateTime _soDia(DateTime d) => DateTime.utc(d.year, d.month, d.day);

/// As janelas de UM dia de Lisboa ([dia]: só se lê ano/mês/dia).
///
/// * [agora] é um instante (o relógio do aparelho serve: a conta faz-se em
///   Lisboa por [paredeLisboa]).
/// * Fora de "hoje … hoje + [maxDias]" devolve vazio; janelas que começam
///   antes de [agora] + [antecedenciaMin], ou depois de [agora] + [maxDias]
///   dias, ficam de fora ("não deixa escolher no passado nem além de 7 dias").
/// * [pausaAte] é a pausa temporária do parceiro (`pausa_ate`): nada começa antes.
List<JanelaAgendada> janelasDoDia({
  required BusinessHours horas,
  required DateTime dia,
  required DateTime agora,
  int maxDias = kAgendarMaxDiasPadrao,
  int antecedenciaMin = kAgendarAntecedenciaPadraoMin,
  DateTime? pausaAte,
}) {
  final alvo = _soDia(dia);
  final hoje = _soDia(paredeLisboa(agora));
  if (alvo.isBefore(hoje) || alvo.isAfter(hoje.add(Duration(days: maxDias)))) {
    return const <JanelaAgendada>[];
  }

  final d = horas.diaEm(alvo);
  if (d.closed) return const <JanelaAgendada>[];
  final abre = _minutos(d.open);
  final fecha = _minutos(d.close);
  if (abre == null || fecha == null) return const <JanelaAgendada>[];
  // Horário que passa a meia-noite (ex.: 20:00–02:00): só se agenda até às 24:00.
  final fechaEf = fecha <= abre ? 1440 : fecha;

  final bs = _minutos(d.breakStart);
  final be = _minutos(d.breakEnd);
  final temPausa = bs != null && be != null && bs < be && bs > abre && be < fechaEf;
  final periodos = temPausa
      ? <(int, int)>[(abre, bs), (be, fechaEf)]
      : <(int, int)>[(abre, fechaEf)];

  final minimo = agora.add(Duration(minutes: antecedenciaMin));
  final maximo = agora.add(Duration(days: maxDias));

  final out = <JanelaAgendada>[];
  for (final (ini, fim) in periodos) {
    // Primeira marca :00 ou :30 dentro do período; a janela tem de caber inteira.
    var marca = ((ini + kAgendarJanelaMinutos - 1) ~/ kAgendarJanelaMinutos) *
        kAgendarJanelaMinutos;
    while (marca + kAgendarJanelaMinutos <= fim) {
      final inicio = DateTime.utc(alvo.year, alvo.month, alvo.day)
          .add(Duration(minutes: marca));
      final janela = JanelaAgendada(
        inicio: inicio,
        fim: inicio.add(const Duration(minutes: kAgendarJanelaMinutos)),
      );
      final instante = janela.instante;
      final cedo = instante.isBefore(minimo);
      final longe = instante.isAfter(maximo);
      final emPausa = pausaAte != null && instante.isBefore(pausaAte);
      if (!cedo && !longe && !emPausa) out.add(janela);
      marca += kAgendarJanelaMinutos;
    }
  }
  return out;
}

/// Os dias (Lisboa, à meia-noite UTC) que têm pelo menos uma janela livre.
List<DateTime> diasComJanelas({
  required BusinessHours horas,
  required DateTime agora,
  int maxDias = kAgendarMaxDiasPadrao,
  int antecedenciaMin = kAgendarAntecedenciaPadraoMin,
  DateTime? pausaAte,
}) {
  final hoje = _soDia(paredeLisboa(agora));
  final out = <DateTime>[];
  for (var i = 0; i <= maxDias; i++) {
    final dia = hoje.add(Duration(days: i));
    final js = janelasDoDia(
      horas: horas,
      dia: dia,
      agora: agora,
      maxDias: maxDias,
      antecedenciaMin: antecedenciaMin,
      pausaAte: pausaAte,
    );
    if (js.isNotEmpty) out.add(dia);
  }
  return out;
}

// ── Textos do cliente (traduzíveis) ─────────────────────────────────────────

const _diasPt = ['seg', 'ter', 'qua', 'qui', 'sex', 'sáb', 'dom'];
const _diasEn = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];

/// "sáb" (ou "Sat" em inglês) para um dia de calendário.
String diaDaSemanaCurto(DateTime dia) =>
    (BoraLang.isEnglish ? _diasEn : _diasPt)[dia.weekday - 1];

/// "01/11".
String dataCurta(DateTime dia) => '${_dois(dia.day)}/${_dois(dia.month)}';

/// "sáb 01/11".
String diaComData(DateTime dia) => '${diaDaSemanaCurto(dia)} ${dataCurta(dia)}';

/// "Hoje", "Amanhã" ou "sáb 01/11" (o dia visto de [agora], em Lisboa).
String rotuloDoDia(DateTime dia, DateTime agora) {
  final hoje = _soDia(paredeLisboa(agora));
  final diff = _soDia(dia).difference(hoje).inDays;
  if (diff == 0) return 'Hoje'.tr;
  if (diff == 1) return 'Amanhã'.tr;
  return diaComData(dia);
}

/// "Agendado para sáb 01/11, 19:30–20:00" (para o cliente, traduzível).
String textoAgendadoPara(JanelaAgendada j) => 'Agendado para {0}, {1}'
    .trArgs([diaComData(j.dia), j.horas]);

/// A mesma frase em português de Portugal, sem tradução: é a que segue na nota
/// do pedido para o parceiro ler ("Pedido AGENDADO para sáb 01/11, 19:30–20:00").
String notaAgendadoParaParceiro(JanelaAgendada j) {
  final sem = _diasPt[j.dia.weekday - 1];
  return 'Pedido AGENDADO para $sem ${dataCurta(j.dia)}, ${j.horas}';
}

// ── Contas de tempo do parceiro (português simples, sem tradução) ───────────

/// Minutos que faltam para [quando] (negativo = já passou). Arredonda para
/// baixo ao minuto cheio de forma estável (59 s ainda é "0 min").
int minutosPara(DateTime quando, DateTime agora) =>
    quando.difference(agora).inSeconds ~/ 60;

/// "faltam 45 min", "faltam 2 h 10 min", "faltam 1 dia 3 h", "é agora",
/// "passou há 10 min".
String faltaTexto(DateTime quando, DateTime agora) {
  final m = minutosPara(quando, agora);
  if (m <= -1) return 'passou há ${-m} min';
  if (m == 0) return 'é agora';
  if (m < 60) return 'faltam $m min';
  if (m < 24 * 60) {
    final h = m ~/ 60;
    final r = m % 60;
    return r == 0 ? 'faltam $h h' : 'faltam $h h $r min';
  }
  final dias = m ~/ (24 * 60);
  final h = (m % (24 * 60)) ~/ 60;
  final dTxt = dias == 1 ? '1 dia' : '$dias dias';
  return h == 0 ? 'faltam $dTxt' : 'faltam $dTxt $h h';
}

/// O parceiro deve ser avisado: faltam [kAgendarAvisoParceiroMin] min ou menos
/// (e o pedido ainda não passou há mais de 2 h).
bool deviaAvisarParceiro(DateTime quando, DateTime agora) {
  final m = minutosPara(quando, agora);
  return m <= kAgendarAvisoParceiroMin && m >= -120;
}
