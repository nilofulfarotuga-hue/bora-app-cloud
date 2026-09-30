/// TVDE — cotação de MUDAR DESTINO a meio da corrida (2026-09-30).
///
/// Espelha o JSON de `tvde_dest_change_quote` / `tvde_dest_change_request`.
/// A app NUNCA calcula preço: só mostra o que o servidor devolveu. A regra
/// (fechada pelo Danilo a 30/09) vive toda no servidor:
///   novo total de km = km feitos desde a recolha + rota do carro ao destino;
///   mais longe → paga (preço novo − preço combinado), mínimo €2;
///   mais perto → não paga nada a mais nem recebe de volta.
///
/// Puro (sem Flutter) para poder ser testado sem widgets.
class TvdeDestChangeQuote {
  const TvdeDestChangeQuote({
    required this.kmDone,
    required this.kmRemaining,
    required this.kmNewTotal,
    required this.kmBefore,
    required this.priceBeforeCents,
    required this.priceNewCents,
    required this.priceAfterCents,
    required this.clientDiffCents,
    required this.minApplied,
    required this.minCents,
    required this.driverDiffCents,
    required this.longer,
    required this.needsPayment,
    required this.paymentMethod,
    this.baseFareCents,
    this.baseKm,
    this.perKmCents,
  });

  final double kmDone;
  final double kmRemaining;
  final double kmNewTotal;

  /// Distância combinada antes desta mudança.
  final double kmBefore;

  /// Preço combinado ATUAL (já com mudanças anteriores; sem paragens).
  final int priceBeforeCents;

  /// Preço da tabela para o novo total de km.
  final int priceNewCents;

  /// O que o cliente passa a pagar (sem paragens) se aceitar.
  final int priceAfterCents;

  /// O que o cliente paga a mais por esta mudança (0 se for mais perto).
  final int clientDiffCents;

  /// A diferença da tabela era menor que o mínimo e cobra-se o mínimo.
  final bool minApplied;
  final int minCents;

  /// O que o motorista ganha a mais (só para o registo; o cliente não vê).
  final int driverDiffCents;

  /// O novo total de km é maior que o combinado.
  final bool longer;

  /// Cartão/MB Way com diferença > 0 → cobra-se antes de mudar.
  final bool needsPayment;
  final String paymentMethod;

  // Fórmula (Lei 45/2018 art. 15.º n.º 4 — o cliente vê como se calcula).
  final int? baseFareCents;
  final int? baseKm;
  final int? perKmCents;

  bool get isFree => clientDiffCents <= 0;

  static double _d(dynamic v) =>
      v is num ? v.toDouble() : double.tryParse('${v ?? ''}') ?? 0;
  static int _i(dynamic v) =>
      v is num ? v.toInt() : int.tryParse('${v ?? ''}') ?? 0;
  static bool _b(dynamic v) => v == true || '$v' == 'true';

  factory TvdeDestChangeQuote.fromMap(Map<String, dynamic> m) {
    final f = m['formula'] is Map
        ? Map<String, dynamic>.from(m['formula'] as Map)
        : const <String, dynamic>{};
    return TvdeDestChangeQuote(
      kmDone: _d(m['km_done']),
      kmRemaining: _d(m['km_remaining']),
      kmNewTotal: _d(m['km_new_total']),
      kmBefore: _d(m['km_before']),
      priceBeforeCents: _i(m['price_before_cents']),
      priceNewCents: _i(m['price_new_cents']),
      priceAfterCents: _i(m['price_after_cents']),
      clientDiffCents: _i(m['client_diff_cents']),
      minApplied: _b(m['min_applied']),
      minCents: _i(m['min_cents']),
      driverDiffCents: _i(m['driver_diff_cents']),
      longer: _b(m['longer']),
      needsPayment: _b(m['needs_payment']),
      paymentMethod: (m['payment_method'] ?? 'cash').toString(),
      baseFareCents: f['tarifa_base_cents'] == null ? null : _i(f['tarifa_base_cents']),
      baseKm: f['km_incluidos'] == null ? null : _i(f['km_incluidos']),
      perKmCents:
          f['preco_km_extra_cents'] == null ? null : _i(f['preco_km_extra_cents']),
    );
  }

  static String eur(int cents) =>
      '€${(cents / 100).toStringAsFixed(2).replaceAll('.', ',')}';

  static String km(double v) => v.toStringAsFixed(1).replaceAll('.', ',');

  /// Há fórmula para mostrar (Lei 45/2018 art. 15.º n.º 4).
  bool get hasFormula =>
      baseFareCents != null && baseKm != null && perKmCents != null;
}
