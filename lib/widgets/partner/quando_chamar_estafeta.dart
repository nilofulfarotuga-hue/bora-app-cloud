import 'package:flutter/material.dart';

import '../../config/app_colors.dart';
import '../../models/restaurant_model.dart';
import '../../utils/fica_pronto.dart';
import '../../utils/hora_lisboa.dart';

/// "QUANDO CHAMAMOS O ESTAFETA?" (17/11/2026, pedido do Danilo às 05:06 — a A3
/// tem trabalhos rápidos e trabalhos demorados: impressões, personalizados,
/// encomendas). Só nas lojas que não são de comida
/// ([RestaurantModel.lojaNaoComida]); os restaurantes continuam com o "fica
/// pronto em quanto tempo?" de 10 a 60 min.
///
/// O servidor (`partner_aceitar_pedido`, migração 20261117130000) guarda:
/// * até 2 h dentro do horário → minutos, como hoje (o estafeta é chamado em
///   aceite + minutos − 8);
/// * 3 h, amanhã, 2 dias, "escolher dia e hora" → a hora prometida
///   (`ready_at_promised`), até 14 dias; o estafeta é chamado 8 min antes.

/// Uma escolha da folha: minutos curtos ou um instante.
@immutable
class EscolhaChamada {
  const EscolhaChamada.minutos(int this.minutos) : instante = null;
  const EscolhaChamada.instante(DateTime this.instante) : minutos = null;

  final int? minutos;
  final DateTime? instante;

  /// O instante em que fica pronto, visto em [agora].
  DateTime prontoEm(DateTime agora) =>
      instante ?? agora.add(Duration(minutes: minutos ?? 0));

  @override
  bool operator ==(Object other) =>
      other is EscolhaChamada &&
      other.minutos == minutos &&
      other.instante == instante;

  @override
  int get hashCode => Object.hash(minutos, instante);

  @override
  String toString() => 'EscolhaChamada(minutos: $minutos, instante: $instante)';
}

/// As opções rápidas, pela ordem do Danilo (17/11 05:06).
const List<(String, Duration)> kOpcoesChamada = [
  ('10 min', Duration(minutes: 10)),
  ('15 min', Duration(minutes: 15)),
  ('20 min', Duration(minutes: 20)),
  ('30 min', Duration(minutes: 30)),
  ('1 h', Duration(hours: 1)),
  ('2 h', Duration(hours: 2)),
  ('3 h', Duration(hours: 3)),
  ('Amanhã (1 dia)', Duration(days: 1)),
  ('2 dias', Duration(days: 2)),
];

/// Até quantos dias de calendário se pode marcar (o servidor aceita 15 dias
/// para o último dia nunca ser recusado pela hora).
const int kDiasMaxChamada = 14;

/// "Escolher dia e hora" não aceita uma hora mais cedo do que isto (o estafeta
/// é chamado 8 min antes da hora).
const Duration kMinimoChamada = Duration(minutes: 10);

/// O primeiro instante a partir de [desde] em que a loja está dentro do
/// horário — o próprio [desde], se já estiver; senão o primeiro quarto de hora
/// (relógio de Lisboa) aberto. Null se não abrir nos próximos 15 dias.
DateTime? primeiroInstanteAberto(RestaurantModel loja, DateTime desde) {
  if (loja.dentroDoHorarioEm(desde)) return desde;
  final parede = paredeLisboa(desde);
  final base = desde.toUtc().subtract(Duration(
      seconds: parede.second,
      milliseconds: parede.millisecond,
      microseconds: parede.microsecond));
  var t = base.add(Duration(minutes: 15 - parede.minute % 15));
  final fim = desde.add(const Duration(days: kDiasMaxChamada + 1));
  while (t.isBefore(fim)) {
    if (loja.dentroDoHorarioEm(t)) return t;
    t = t.add(const Duration(minutes: 15));
  }
  return null;
}

/// O que uma opção rápida dá, vista em [agora]:
/// * menos de 1 h → minutos (a loja está a trabalhar agora);
/// * 1 h e 2 h dentro do horário → minutos, como hoje;
/// * fora do horário (ex.: "2 dias" num domingo fechado) → a primeira hora em
///   que a loja abre, para o estafeta nunca chegar a uma porta fechada;
/// * 3 h ou mais → o instante.
EscolhaChamada escolhaDaOpcao(
  Duration duracao, {
  required DateTime agora,
  required RestaurantModel loja,
}) {
  if (duracao < const Duration(hours: 1)) {
    return EscolhaChamada.minutos(duracao.inMinutes);
  }
  final alvo = agora.add(duracao);
  final aberto = primeiroInstanteAberto(loja, alvo) ?? alvo;
  if (identical(aberto, alvo) && duracao <= const Duration(minutes: 120)) {
    return EscolhaChamada.minutos(duracao.inMinutes);
  }
  return EscolhaChamada.instante(aberto);
}

/// O dia (só ano/mês/dia) abre? Lê o horário da loja, dias especiais incluídos.
bool diaAbre(RestaurantModel loja, DateTime dia) =>
    !loja.businessHours.diaEm(DateTime.utc(dia.year, dia.month, dia.day)).closed;

String _horarioDoDia(DayHours d) {
  final pausa = (d.breakStart != null && d.breakEnd != null)
      ? ' (pausa ${d.breakStart}–${d.breakEnd})'
      : '';
  return 'das ${d.open} às ${d.close}$pausa';
}

/// Valida um dia + hora escolhidos no calendário (relógio de Lisboa, como a
/// loja os vê). Devolve o instante, ou a frase a mostrar.
({DateTime? instante, String? erro}) validarDiaHora({
  required RestaurantModel loja,
  required DateTime dia,
  required int hora,
  required int minuto,
  required DateTime agora,
}) {
  final instante =
      instanteDeLisboa(DateTime(dia.year, dia.month, dia.day, hora, minuto));
  if (instante.isBefore(agora.add(kMinimoChamada))) {
    return (
      instante: null,
      erro: 'Escolha uma hora daqui a mais de ${kMinimoChamada.inMinutes} minutos.'
    );
  }
  if (instante.isAfter(agora.add(const Duration(days: kDiasMaxChamada + 1)))) {
    return (instante: null, erro: 'No máximo $kDiasMaxChamada dias.');
  }
  if (!loja.dentroDoHorarioEm(instante)) {
    final d = loja.businessHours.diaEm(DateTime.utc(dia.year, dia.month, dia.day));
    return (
      instante: null,
      erro: 'A loja está fechada a essa hora. Nesse dia abre ${_horarioDoDia(d)}.'
    );
  }
  return (instante: instante, erro: null);
}

/// Como se escolhe o dia (por defeito, o calendário do Material).
typedef EscolherDiaChamada = Future<DateTime?> Function(
  BuildContext context, {
  required DateTime inicial,
  required DateTime primeiro,
  required DateTime ultimo,
  required bool Function(DateTime) podeEscolher,
});

/// Como se escolhe a hora (por defeito, o relógio do Material em 24 h).
typedef EscolherHoraChamada = Future<TimeOfDay?> Function(
    BuildContext context, TimeOfDay inicial);

/// Como a folha inteira se abre (os testes do cartão trocam-na).
typedef EscolherChamada = Future<EscolhaChamada?> Function(
    BuildContext context, RestaurantModel loja, String titulo);

Future<DateTime?> _calendario(
  BuildContext context, {
  required DateTime inicial,
  required DateTime primeiro,
  required DateTime ultimo,
  required bool Function(DateTime) podeEscolher,
}) =>
    showDatePicker(
      context: context,
      initialDate: inicial,
      firstDate: primeiro,
      lastDate: ultimo,
      selectableDayPredicate: podeEscolher,
      helpText: 'Fica pronto em que dia?',
    );

Future<TimeOfDay?> _relogio24h(BuildContext context, TimeOfDay inicial) =>
    showTimePicker(
      context: context,
      initialTime: inicial,
      helpText: 'Fica pronto a que horas?',
      builder: (ctx, child) => MediaQuery(
        data: MediaQuery.of(ctx).copyWith(alwaysUse24HourFormat: true),
        child: child ?? const SizedBox.shrink(),
      ),
    );

/// Abre a folha "Quando chamamos o estafeta?". Devolve a escolha, ou null se a
/// loja fechar a folha sem escolher (então o pedido NÃO é aceite).
Future<EscolhaChamada?> escolherQuandoChamarEstafeta(
  BuildContext context, {
  required RestaurantModel loja,
  String titulo = 'Quando chamamos o estafeta?',
  DateTime? pedidoPara,
  DateTime Function()? agora,
  EscolherDiaChamada? escolherDia,
  EscolherHoraChamada? escolherHora,
}) {
  return showModalBottomSheet<EscolhaChamada>(
    context: context,
    isScrollControlled: true,
    builder: (_) => FolhaQuandoChamar(
      loja: loja,
      titulo: titulo,
      pedidoPara: pedidoPara,
      agora: agora,
      escolherDia: escolherDia,
      escolherHora: escolherHora,
    ),
  );
}

/// O conteúdo da folha (público para os testes de ecrã).
class FolhaQuandoChamar extends StatefulWidget {
  const FolhaQuandoChamar({
    super.key,
    required this.loja,
    this.titulo = 'Quando chamamos o estafeta?',
    this.pedidoPara,
    this.agora,
    this.escolherDia,
    this.escolherHora,
  });

  final RestaurantModel loja;
  final String titulo;

  /// A hora que o cliente marcou (encomenda agendada), para a loja ver.
  final DateTime? pedidoPara;
  final DateTime Function()? agora;
  final EscolherDiaChamada? escolherDia;
  final EscolherHoraChamada? escolherHora;

  @override
  State<FolhaQuandoChamar> createState() => _FolhaQuandoChamarState();
}

class _FolhaQuandoChamarState extends State<FolhaQuandoChamar> {
  String? _erro;
  bool _aEscolher = false;

  DateTime _agora() => widget.agora?.call() ?? DateTime.now();

  Future<void> _escolherDiaHora() async {
    setState(() {
      _erro = null;
      _aEscolher = true;
    });
    try {
      final agora = _agora();
      final hoje = horaLisboa(agora);
      final dias = [
        for (var i = 0; i <= kDiasMaxChamada; i++)
          DateTime(hoje.year, hoje.month, hoje.day + i),
      ];
      final abertos = dias.where((d) => diaAbre(widget.loja, d)).toList();
      if (abertos.isEmpty) {
        setState(() => _erro =
            'A loja não tem nenhum dia aberto nos próximos $kDiasMaxChamada dias.');
        return;
      }
      final dia = await (widget.escolherDia ?? _calendario)(
        context,
        inicial: abertos.first,
        primeiro: dias.first,
        ultimo: dias.last,
        podeEscolher: (d) => diaAbre(widget.loja, d),
      );
      if (dia == null || !mounted) return;

      final eHoje = dia.year == hoje.year &&
          dia.month == hoje.month &&
          dia.day == hoje.day;
      final abre = widget.loja.businessHours
          .diaEm(DateTime.utc(dia.year, dia.month, dia.day))
          .open;
      final partes = abre.split(':');
      final daquiAUmaHora = horaLisboa(agora.add(const Duration(hours: 1)));
      final inicial = eHoje
          ? TimeOfDay(hour: daquiAUmaHora.hour, minute: 0)
          : TimeOfDay(
              hour: int.tryParse(partes.first) ?? 12,
              minute: partes.length > 1 ? int.tryParse(partes[1]) ?? 0 : 0);
      final t = await (widget.escolherHora ?? _relogio24h)(context, inicial);
      if (t == null || !mounted) return;

      final r = validarDiaHora(
          loja: widget.loja,
          dia: dia,
          hora: t.hour,
          minuto: t.minute,
          agora: _agora());
      if (r.erro != null) {
        setState(() => _erro = r.erro);
        return;
      }
      Navigator.of(context).pop(EscolhaChamada.instante(r.instante!));
    } finally {
      if (mounted) setState(() => _aEscolher = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final agora = _agora();
    final pedidoPara = widget.pedidoPara;
    return SafeArea(
      child: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                widget.titulo,
                style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 4),
              const Text(
                'Quando fica pronto? Chamamos o estafeta perto dessa hora.',
                style: TextStyle(fontSize: 12.5, color: AppColors.textSecondary),
              ),
              if (pedidoPara != null) ...[
                const SizedBox(height: 6),
                Text(
                  'O cliente marcou para ${textoDiaHoraLisboa(pedidoPara, agora)}.',
                  style: const TextStyle(
                      fontSize: 13, fontWeight: FontWeight.w600),
                ),
              ],
              const SizedBox(height: 14),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final (rotulo, duracao) in kOpcoesChamada)
                    _ChipOpcao(
                      key: Key('opcao_chamada_$rotulo'),
                      rotulo: rotulo,
                      longa: duracao >= const Duration(hours: 1),
                      escolha:
                          escolhaDaOpcao(duracao, agora: agora, loja: widget.loja),
                      agora: agora,
                    ),
                ],
              ),
              const SizedBox(height: 14),
              OutlinedButton.icon(
                key: const Key('btn_escolher_dia_hora'),
                style: OutlinedButton.styleFrom(minimumSize: const Size(0, 48)),
                onPressed: _aEscolher ? null : _escolherDiaHora,
                icon: const Icon(Icons.calendar_month_outlined),
                label: const Text('Escolher dia e hora'),
              ),
              if (_erro != null) ...[
                const SizedBox(height: 8),
                Text(
                  _erro!,
                  key: const Key('erro_escolher_dia_hora'),
                  style: const TextStyle(color: AppColors.error, fontSize: 13),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _ChipOpcao extends StatelessWidget {
  const _ChipOpcao({
    super.key,
    required this.rotulo,
    required this.longa,
    required this.escolha,
    required this.agora,
  });

  final String rotulo;
  final bool longa;
  final EscolhaChamada escolha;
  final DateTime agora;

  @override
  Widget build(BuildContext context) {
    return ActionChip(
      onPressed: () => Navigator.of(context).pop(escolha),
      label: longa
          ? Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(rotulo, style: const TextStyle(fontWeight: FontWeight.w700)),
                Text(
                  textoDiaHoraLisboa(escolha.prontoEm(agora), agora),
                  style: const TextStyle(
                      fontSize: 11, color: AppColors.textSecondary),
                ),
              ],
            )
          : Text(rotulo, style: const TextStyle(fontWeight: FontWeight.w700)),
    );
  }
}
