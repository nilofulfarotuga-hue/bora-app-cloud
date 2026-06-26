/// TVDE — Bora Motorista. Plano de assinatura do cliente + contador diário.
/// Na fase de testes a assinatura é concedida pelo admin (sem compra Stripe).
class TvdeSubscription {
  TvdeSubscription({
    required this.id,
    required this.plan,
    required this.ridesTotal,
    required this.ridesUsed,
    required this.dailyIncluded,
    required this.priceCents,
    this.endsAt,
  });

  final String id;
  final String plan; // semanal | quinzenal | mensal
  final int ridesTotal;
  final int ridesUsed;
  final int dailyIncluded;
  final int priceCents;
  final DateTime? endsAt;

  int get ridesLeft => (ridesTotal - ridesUsed).clamp(0, ridesTotal);

  String get planLabel {
    switch (plan) {
      case 'semanal':
        return 'Plano Semanal';
      case 'quinzenal':
        return 'Plano Quinzenal';
      case 'mensal':
        return 'Plano Mensal';
      default:
        return plan;
    }
  }

  factory TvdeSubscription.fromMap(Map<String, dynamic> m) {
    return TvdeSubscription(
      id: m['id'] as String,
      plan: m['plan'] as String? ?? 'mensal',
      ridesTotal: (m['rides_total'] as num?)?.toInt() ?? 0,
      ridesUsed: (m['rides_used'] as num?)?.toInt() ?? 0,
      dailyIncluded: (m['daily_included'] as num?)?.toInt() ?? 2,
      priceCents: (m['price_cents'] as num?)?.toInt() ?? 0,
      endsAt: m['ends_at'] == null
          ? null
          : DateTime.tryParse(m['ends_at'].toString()),
    );
  }
}
