/// TVDE — orçamento de um plano de assinatura para uma ROTA concreta.
///
/// Espelho 1:1 da RPC `tvde_quote_plan(p_plan, p_distance_km)`. **Todos** os
/// valores vêm do servidor — nada de preço, nº de viagens ou km incluídos
/// gravado no código do app (regra do Danilo: "nunca cravar 40/70/132").
///
/// A [distanceKm] não vem da RPC: é a distância da rota que o cliente escolheu
/// e que originou este orçamento — guardamo-la aqui só para a conta aberta
/// poder dizer "a tua rota tem 8 km".
class TvdePlanQuote {
  const TvdePlanQuote({
    required this.baseKm,
    required this.extraKm,
    required this.ridesTotal,
    required this.days,
    required this.perKmCents,
    required this.basePriceCents,
    required this.extraCents,
    required this.priceCents,
    required this.perRideCents,
    required this.distanceKm,
  });

  /// Km incluídos por viagem (acima disto paga-se o excesso).
  final int baseKm;

  /// Km acima do incluído, já arredondados pelo servidor.
  final int extraKm;

  /// Total de viagens do plano.
  final int ridesTotal;

  /// Dias úteis cobertos pelo plano.
  final int days;

  /// Preço de cada km a mais, por viagem (cêntimos).
  final int perKmCents;

  /// Preço-base do plano (sem excesso), em cêntimos.
  final int basePriceCents;

  /// Total do excesso (extraKm × perKmCents × ridesTotal), em cêntimos.
  final int extraCents;

  /// TOTAL a pagar (base + excesso), em cêntimos. É este o valor cobrado.
  final int priceCents;

  /// Preço médio por viagem, em cêntimos.
  final int perRideCents;

  /// Distância da rota escolhida pelo cliente (km).
  final double distanceKm;

  factory TvdePlanQuote.fromMap(Map<String, dynamic> m,
      {required double distanceKm}) {
    int i(String k) => (m[k] as num?)?.toInt() ?? 0;
    return TvdePlanQuote(
      baseKm: i('base_km'),
      extraKm: i('extra_km'),
      ridesTotal: i('rides_total'),
      days: i('days'),
      perKmCents: i('per_km_cents'),
      basePriceCents: i('base_price_cents'),
      extraCents: i('extra_cents'),
      priceCents: i('price_cents'),
      perRideCents: i('per_ride_cents'),
      distanceKm: distanceKm,
    );
  }

  /// Viagens por dia útil (ex.: 10 viagens ÷ 5 dias = 2 por dia).
  int get ridesPerDay => days > 0 ? (ridesTotal / days).round() : 0;

  bool get hasExtra => extraKm > 0 && extraCents > 0;

  /// A CONTA ABERTA, em PT-PT, linha a linha — é isto que o cliente vê antes
  /// de o botão de pagar acender. [planLabel] ex.: "Plano Semanal".
  List<TvdePlanQuoteLine> breakdown(String planLabel) {
    return [
      TvdePlanQuoteLine(planLabel, eur(basePriceCents)),
      TvdePlanQuoteLine(
        'Inclui $ridesTotal viagens',
        '$ridesPerDay por dia, segunda a sexta',
      ),
      TvdePlanQuoteLine('Distância incluída', 'até $baseKm km por viagem'),
      TvdePlanQuoteLine('A tua rota', '${km(distanceKm)} km'),
      if (hasExtra)
        TvdePlanQuoteLine(
          '$extraKm km a mais × ${eur(perKmCents)} × $ridesTotal viagens',
          eur(extraCents),
        ),
      TvdePlanQuoteLine('TOTAL', eur(priceCents), strong: true),
    ];
  }

  /// Formata cêntimos em euros PT-PT ("40,00 €").
  static String eur(int cents) =>
      '${(cents / 100).toStringAsFixed(2).replaceAll('.', ',')} €';

  /// Formata km PT-PT sem casas decimais inúteis ("8" / "8,4").
  static String km(double v) {
    final s = v == v.roundToDouble()
        ? v.toStringAsFixed(0)
        : v.toStringAsFixed(1);
    return s.replaceAll('.', ',');
  }
}

/// Uma linha da conta aberta: rótulo à esquerda, valor à direita.
class TvdePlanQuoteLine {
  const TvdePlanQuoteLine(this.label, this.value, {this.strong = false});
  final String label;
  final String value;

  /// TOTAL — destacado a negrito na UI.
  final bool strong;
}
