// Planos de limpeza (casas e Bora Empresas) — missão limpeza-planos-empresas-2026-11-28.
//
// Os preços vêm SEMPRE do servidor (cleaning_plan_quote / cleaning_plan_prices); aqui só se
// leem e mostram. Planos só com cartão: cobra-se cada limpeza 24 h antes, e só com a
// profissional confirmada ("A cada limpeza"), ou o mês de uma vez.

int _int(Object? v, [int fallback = 0]) {
  if (v is int) return v;
  if (v is num) return v.round();
  return int.tryParse('${v ?? ''}') ?? fallback;
}

double _dbl(Object? v, [double fallback = 0]) {
  if (v is num) return v.toDouble();
  return double.tryParse('${v ?? ''}') ?? fallback;
}

DateTime? _data(Object? v) => v == null ? null : DateTime.tryParse('$v')?.toUtc();

/// Uma linha da escada de preços ("Preço por hora" a descer com a frequência).
class CleaningPlanLadderStep {
  const CleaningPlanLadderStep({required this.frequency, required this.label, required this.clientCentsPerHour});
  final String frequency;
  final String label;
  final int clientCentsPerHour;

  factory CleaningPlanLadderStep.fromJson(Map<String, dynamic> j) => CleaningPlanLadderStep(
        frequency: '${j['frequency'] ?? ''}',
        label: '${j['label'] ?? ''}',
        clientCentsPerHour: _int(j['client_cents_per_hour']),
      );
}

/// O preço de um plano, como o servidor o calcula (cleaning_plan_quote).
class CleaningPlanQuote {
  const CleaningPlanQuote({
    required this.segment,
    required this.frequency,
    required this.label,
    required this.hours,
    required this.teamSize,
    required this.clientCentsPerHour,
    required this.proCentsPerHour,
    required this.laborCents,
    required this.productsCents,
    required this.productsIncluded,
    required this.travelFeeCents,
    required this.travelDistanceKm,
    required this.totalPerVisitCents,
    required this.proEarningsCents,
    required this.visitsPerMonth,
    required this.approxMonthCents,
    required this.minHours,
    required this.ladder,
  });

  final String segment;
  final String frequency;
  final String label;
  final double hours;
  final int teamSize;
  final int clientCentsPerHour;
  final int proCentsPerHour;
  final int laborCents;
  final int productsCents;
  final bool productsIncluded;
  final int travelFeeCents;
  final double? travelDistanceKm;
  final int totalPerVisitCents;
  final int proEarningsCents;
  final double visitsPerMonth;
  final int approxMonthCents;
  final double minHours;
  final List<CleaningPlanLadderStep> ladder;

  factory CleaningPlanQuote.fromJson(Map<String, dynamic> j) {
    final travel = j['travel'];
    final km = travel is Map ? travel['distance_km'] : null;
    return CleaningPlanQuote(
      segment: '${j['segment'] ?? ''}',
      frequency: '${j['frequency'] ?? ''}',
      label: '${j['label'] ?? ''}',
      hours: _dbl(j['hours']),
      teamSize: _int(j['team_size'], 1),
      clientCentsPerHour: _int(j['client_cents_per_hour']),
      proCentsPerHour: _int(j['pro_cents_per_hour']),
      laborCents: _int(j['labor_cents']),
      productsCents: _int(j['products_cents']),
      productsIncluded: j['products_included'] == true,
      travelFeeCents: _int(j['travel_fee_cents']),
      travelDistanceKm: km == null ? null : _dbl(km),
      totalPerVisitCents: _int(j['total_per_visit_cents']),
      proEarningsCents: _int(j['pro_earnings_cents']),
      visitsPerMonth: _dbl(j['visits_per_month']),
      approxMonthCents: _int(j['approx_month_cents']),
      minHours: _dbl(j['min_hours'], 1),
      ladder: [
        for (final s in (j['ladder'] as List? ?? const []))
          if (s is Map) CleaningPlanLadderStep.fromJson(Map<String, dynamic>.from(s)),
      ],
    );
  }
}

/// Uma limpeza do plano (a vaga 1, que tem o preço).
class CleaningPlanVisit {
  const CleaningPlanVisit({
    required this.bookingId,
    required this.scheduledAt,
    required this.date,
    required this.status,
    required this.paymentStatus,
    required this.totalCents,
    required this.confirmed,
    required this.cleanerName,
    required this.canSkip,
  });
  final String bookingId;
  final DateTime scheduledAt;
  final String date; // AAAA-MM-DD (dia de Lisboa)
  final String status;
  final String paymentStatus;
  final int totalCents;
  final bool confirmed;
  final String? cleanerName;
  final bool canSkip;

  bool get paid => paymentStatus == 'held' || paymentStatus == 'released';

  factory CleaningPlanVisit.fromJson(Map<String, dynamic> j) => CleaningPlanVisit(
        bookingId: '${j['booking_id']}',
        scheduledAt: _data(j['scheduled_at']) ?? DateTime.now().toUtc(),
        date: '${j['date'] ?? ''}',
        status: '${j['status'] ?? ''}',
        paymentStatus: '${j['payment_status'] ?? ''}',
        totalCents: _int(j['total_cents']),
        confirmed: j['confirmed'] == true,
        cleanerName: j['cleaner_name'] as String?,
        canSkip: j['can_skip'] == true,
      );
}

/// Uma cobrança do plano (uma limpeza, ou o mês).
class CleaningPlanCharge {
  const CleaningPlanCharge({
    required this.id,
    required this.kind,
    required this.amountCents,
    required this.status,
    required this.chargeAfter,
    required this.paidAt,
    required this.cardLast4,
    required this.receiptUrl,
  });
  final String id;
  final String kind; // visit | month
  final int amountCents;
  final String status;
  final DateTime? chargeAfter;
  final DateTime? paidAt;
  final String? cardLast4;
  final String? receiptUrl;

  bool get needsAction => status == 'requires_action';
  bool get failed => status == 'failed' || status == 'failed_final';

  /// Texto curto do estado, para o histórico.
  String get statusLabel => switch (status) {
        'succeeded' => 'Pago',
        'scheduled' => 'Agendada',
        'waiting_cleaner' => 'À espera da profissional',
        'pending' || 'processing' => 'A cobrar',
        'failed' => 'Falhou — vamos tentar outra vez',
        'requires_action' => 'Confirma na app',
        'failed_final' => 'Não foi cobrado',
        'cancelled' => 'Sem cobrança',
        _ => status,
      };

  factory CleaningPlanCharge.fromJson(Map<String, dynamic> j) => CleaningPlanCharge(
        id: '${j['id']}',
        kind: '${j['kind'] ?? 'visit'}',
        amountCents: _int(j['amount_cents']),
        status: '${j['status'] ?? ''}',
        chargeAfter: _data(j['charge_after']),
        paidAt: _data(j['paid_at']),
        cardLast4: j['card_last4'] as String?,
        receiptUrl: j['receipt_url'] as String?,
      );
}

/// O plano do cliente, como cleaning_plan_mine() o devolve.
class CleaningPlan {
  const CleaningPlan({
    required this.id,
    required this.segment,
    required this.frequency,
    required this.label,
    required this.status,
    required this.daysOfWeek,
    required this.visitTime,
    required this.hours,
    required this.teamSize,
    required this.billingMode,
    required this.clientCentsPerHour,
    required this.totalPerVisitCents,
    required this.approxMonthCents,
    required this.monthPaidCents,
    required this.cardBrand,
    required this.cardLast4,
    required this.cleanerName,
    required this.companyName,
    required this.addressStreet,
    required this.nextVisits,
    required this.charges,
    required this.needsAction,
  });

  final String id;
  final String segment; // casa | empresa
  final String frequency;
  final String label;
  final String status; // pending_card | active | paused | cancelled | completed
  final List<int> daysOfWeek; // 1 = segunda ... 7 = domingo
  final String visitTime; // HH:MM:SS
  final int hours;
  final int teamSize;
  final String billingMode; // per_visit | monthly
  final int clientCentsPerHour;
  final int totalPerVisitCents;
  final int approxMonthCents;
  final int monthPaidCents;
  final String? cardBrand;
  final String? cardLast4;
  final String? cleanerName;
  final String? companyName;
  final String addressStreet;
  final List<CleaningPlanVisit> nextVisits;
  final List<CleaningPlanCharge> charges;
  final bool needsAction;

  bool get isActive => status == 'active';
  bool get isOpen => status == 'active' || status == 'paused' || status == 'pending_card';
  bool get isEmpresa => segment == 'empresa';
  String get horaCurta => visitTime.length >= 5 ? visitTime.substring(0, 5) : visitTime;

  factory CleaningPlan.fromJson(Map<String, dynamic> j) {
    final cleaner = j['cleaner'];
    return CleaningPlan(
      id: '${j['id']}',
      segment: '${j['segment'] ?? 'casa'}',
      frequency: '${j['frequency'] ?? ''}',
      label: '${j['label'] ?? ''}',
      status: '${j['status'] ?? ''}',
      daysOfWeek: [for (final d in (j['days_of_week'] as List? ?? const [])) _int(d)],
      visitTime: '${j['visit_time'] ?? ''}',
      hours: _dbl(j['hours']).round(),
      teamSize: _int(j['team_size'], 1),
      billingMode: '${j['billing_mode'] ?? 'per_visit'}',
      clientCentsPerHour: _int(j['client_cents_per_hour']),
      totalPerVisitCents: _int(j['total_per_visit_cents']),
      approxMonthCents: _int(j['approx_month_cents']),
      monthPaidCents: _int(j['month_paid_cents']),
      cardBrand: j['card_brand'] as String?,
      cardLast4: j['card_last4'] as String?,
      cleanerName: cleaner is Map ? cleaner['name'] as String? : null,
      companyName: j['company_name'] as String?,
      addressStreet: '${j['address_street'] ?? ''}',
      nextVisits: [
        for (final v in (j['next_visits'] as List? ?? const []))
          if (v is Map) CleaningPlanVisit.fromJson(Map<String, dynamic>.from(v)),
      ],
      charges: [
        for (final c in (j['charges'] as List? ?? const []))
          if (c is Map) CleaningPlanCharge.fromJson(Map<String, dynamic>.from(c)),
      ],
      needsAction: j['needs_action'] == true,
    );
  }
}

/// Textos fixos dos planos (PT-PT).
class CleaningPlanLabels {
  CleaningPlanLabels._();

  static const casaFrequencias = {
    'biweekly': 'De 15 em 15 dias',
    'weekly': 'Semanal',
    'multi_weekly': 'Mais de uma vez por semana',
  };

  static const empresaFrequencias = {
    'once': 'Uma vez',
    'weekly_1': '1 vez por semana',
    'weekly_2': '2 vezes por semana',
    'weekly_3plus': '3 ou mais vezes por semana',
  };

  static const espacos = {
    'loja': 'Loja',
    'farmacia': 'Farmácia',
    'otica': 'Ótica',
    'escritorio': 'Escritório',
    'clinica': 'Clínica',
    'cafe': 'Café / restaurante',
    'salao': 'Salão / barbearia',
    'outro': 'Outro',
  };

  static const tarefas = {
    'varrer_aspirar': 'Varrer e aspirar',
    'po': 'Tirar o pó',
    'casa_de_banho': 'Casa de banho',
    'lixo': 'Lixo',
    'vidros_montra': 'Vidros e montra',
    'copa': 'Copa / cozinha',
  };

  static const diasCurtos = {1: 'Seg', 2: 'Ter', 3: 'Qua', 4: 'Qui', 5: 'Sex', 6: 'Sáb', 7: 'Dom'};

  /// Quantos dias por semana a frequência pede: (mínimo, máximo). Igual ao servidor.
  static (int, int) diasPorSemana(String frequency) => switch (frequency) {
        'weekly_2' => (2, 2),
        'multi_weekly' => (2, 7),
        'weekly_3plus' => (3, 7),
        _ => (1, 1),
      };

  /// Horas sugeridas pela tipologia (platform_settings.cleaning_durations_min), por profissional.
  static int horasSugeridas(Map<String, int> duracoesMin, String homeSize, int equipa) {
    final min = duracoesMin[homeSize] ?? 180;
    final porPro = (min / 60 / (equipa < 1 ? 1 : equipa)).ceil();
    return porPro < 2 ? 2 : porPro;
  }

  /// Duas profissionais sugeridas na Profunda, Pós-obra e casas T3 ou maiores.
  static bool sugereEquipa(String homeSize) => homeSize == 't3' || homeSize == 't4plus';

  static String euroHora(int cents) => '${(cents / 100).toStringAsFixed(2).replaceAll('.', ',')} €/h';

  static String dias(List<int> dias) => dias.map((d) => diasCurtos[d] ?? '$d').join(', ');
}
