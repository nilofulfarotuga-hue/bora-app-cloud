// BLOCO C (2026-07-28) — horário semanal da vertical Serviços.
//
// FONTE DA VERDADE DOS SLOTS: `staff_availability` (por profissional ×
// day_of_week), lida pela RPC `get_available_slots`. O
// `service_providers.business_hours` é só a VITRINE da ficha do parceiro —
// mudar lá não muda um único horário disponível. Por isso quem grava tem de
// gravar nos dois sítios (ver PartnerAppointmentsStore.saveWeeklyHours).

/// Horário de UM dia da semana.
class DayHours {
  const DayHours({
    required this.isWorking,
    required this.start,
    required this.end,
    this.breakStart,
    this.breakEnd,
  });

  /// Dia fechado (`is_working = false`).
  final bool isWorking;

  /// 'HH:MM'.
  final String start;
  final String end;

  /// Pausa opcional (almoço). Ambos null = sem pausa (retrocompatível).
  final String? breakStart;
  final String? breakEnd;

  static const DayHours closed = DayHours(
    isWorking: false,
    start: '09:00',
    end: '18:00',
  );

  static const DayHours defaultOpen = DayHours(
    isWorking: true,
    start: '09:00',
    end: '18:00',
  );

  bool get hasBreak => breakStart != null && breakEnd != null;

  DayHours copyWith({
    bool? isWorking,
    String? start,
    String? end,
    String? breakStart,
    String? breakEnd,
    bool clearBreak = false,
  }) =>
      DayHours(
        isWorking: isWorking ?? this.isWorking,
        start: start ?? this.start,
        end: end ?? this.end,
        breakStart: clearBreak ? null : (breakStart ?? this.breakStart),
        breakEnd: clearBreak ? null : (breakEnd ?? this.breakEnd),
      );

  /// Valida o dia. Devolve null quando está ok, ou o erro em PT.
  /// [ptBr] escolhe a variante do painel admin (PT-BR).
  String? validate({bool ptBr = false}) {
    if (!isWorking) return null;
    final s = _minutes(start);
    final e = _minutes(end);
    if (s == null || e == null) {
      return ptBr ? 'Horário inválido.' : 'Horário inválido.';
    }
    if (e <= s) {
      return ptBr
          ? 'O fechamento tem de ser depois da abertura.'
          : 'O fecho tem de ser depois da abertura.';
    }
    if (breakStart == null && breakEnd == null) return null;
    if (breakStart == null || breakEnd == null) {
      return ptBr
          ? 'Preencha o início e o fim da pausa.'
          : 'Preenche o início e o fim da pausa.';
    }
    final bs = _minutes(breakStart!);
    final be = _minutes(breakEnd!);
    if (bs == null || be == null) return 'Pausa inválida.';
    if (be <= bs) {
      return ptBr
          ? 'O fim da pausa tem de ser depois do início.'
          : 'O fim da pausa tem de ser depois do início.';
    }
    if (bs < s || be > e) {
      return ptBr
          ? 'A pausa tem de ficar dentro do horário aberto.'
          : 'A pausa tem de ficar dentro do horário aberto.';
    }
    return null;
  }

  /// Linha de `staff_availability` (a que o motor de slots lê).
  Map<String, dynamic> toAvailabilityRow(String staffId, int dayOfWeek) => {
        'staff_id': staffId,
        'day_of_week': dayOfWeek,
        'is_working': isWorking,
        'start_time': '$start:00',
        'end_time': '$end:00',
        'break_start': breakStart == null ? null : '$breakStart:00',
        'break_end': breakEnd == null ? null : '$breakEnd:00',
      };

  /// Entrada do jsonb `service_providers.business_hours` (vitrine).
  Map<String, dynamic> toBusinessHoursEntry() => {
        'open': start,
        'close': end,
        'closed': !isWorking,
        if (breakStart != null) 'break_start': breakStart,
        if (breakEnd != null) 'break_end': breakEnd,
      };

  factory DayHours.fromAvailabilityRow(Map<String, dynamic> row) => DayHours(
        isWorking: (row['is_working'] as bool?) ?? false,
        start: _hhmm(row['start_time']) ?? '09:00',
        end: _hhmm(row['end_time']) ?? '18:00',
        breakStart: _hhmm(row['break_start']),
        breakEnd: _hhmm(row['break_end']),
      );

  /// 'HH:MM:SS' (Postgres `time`) → 'HH:MM'.
  static String? _hhmm(Object? v) {
    if (v == null) return null;
    final s = v.toString();
    if (s.length < 5) return null;
    return s.substring(0, 5);
  }

  static int? _minutes(String hhmm) {
    final parts = hhmm.split(':');
    if (parts.length < 2) return null;
    final h = int.tryParse(parts[0]);
    final m = int.tryParse(parts[1]);
    if (h == null || m == null) return null;
    return h * 60 + m;
  }
}

/// Nomes dos dias. Índice = `day_of_week` do Postgres (0 = Domingo).
const List<String> kWeekdayNamesPt = [
  'Domingo',
  'Segunda-feira',
  'Terça-feira',
  'Quarta-feira',
  'Quinta-feira',
  'Sexta-feira',
  'Sábado',
];

/// Chaves do jsonb `business_hours`, na mesma ordem (0 = Domingo).
const List<String> kBusinessHoursKeys = [
  'sun',
  'mon',
  'tue',
  'wed',
  'thu',
  'fri',
  'sat',
];

/// Ordem de apresentação: começa na segunda-feira, domingo no fim.
const List<int> kWeekdayDisplayOrder = [1, 2, 3, 4, 5, 6, 0];

/// Semana completa por defeito (usada quando o profissional ainda não tem
/// nenhuma linha em `staff_availability`).
Map<int, DayHours> defaultWeek() => {
      for (final d in kWeekdayDisplayOrder)
        d: d == 0 ? DayHours.closed : DayHours.defaultOpen,
    };
