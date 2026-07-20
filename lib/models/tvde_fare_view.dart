import 'tvde_ride.dart';

/// Fonte ÚNICA do preço de uma corrida TVDE — o que o cliente paga e o que o
/// motorista recolhe em mão. Existe porque os dois lados discordavam: o badge
/// do motorista (`TvdePayBadge`) e o ecrã do cliente (`TvdeRideTrackingScreen`)
/// calculavam cada um o seu número, e nenhum dos dois somava as paradas extra.
///
/// A regra subtil (é daqui que nascia o "€13"): a `tvde_finish_ride` faz
/// `IF v_prepaid THEN v_fare := v_stops_fee`. Ou seja, **numa perna do pacote
/// €8 o `final_fare_cents` é SÓ as paradas**, não a tarifa. Por isso ali soma-se
/// `pacote + final`, enquanto numa corrida normal o `final` já inclui as paradas
/// e somá-las outra vez seria dupla contagem.
///
/// Puro (sem Flutter) para poder ser testado sem widgets.
class TvdeFareView {
  const TvdeFareView({
    required this.clientTotalCents,
    required this.driverCollectCents,
    required this.clientLabel,
    required this.approx,
    required this.coveredByPlan,
    required this.isPaidOnline,
  });

  /// O que o CLIENTE paga por esta corrida (cêntimos), paradas incluídas.
  final int clientTotalCents;

  /// O que o MOTORISTA recolhe em mão (cêntimos). 0 quando a corrida foi paga
  /// no app — nesse caso as paradas também foram cobradas online.
  final int driverCollectCents;

  /// Texto para o cliente. Nas pernas do pacote explica o porquê do valor.
  final String clientLabel;

  /// Ainda é estimativa (antes do finish) — a UI mostra "~".
  final bool approx;

  final bool coveredByPlan;
  final bool isPaidOnline;

  static String _eur(int cents) => '€${(cents / 100).toStringAsFixed(2)}';

  /// [packageCents] = `tvde_roundtrip_price_cents` (lido por
  /// `TvdeRoundtripPrice.load`). Nunca hardcodar aqui.
  static TvdeFareView of(TvdeRide ride, {required int packageCents}) {
    final finalCents = ride.finalFareCents;
    final stopsCents = ride.extraStopsFeeCents;
    final paidOnline = ride.isPaidOnline;

    // Perna do pacote €8: a tarifa desta corrida NUNCA se cobra — está prepaga.
    // Depois do finish o `final` traz só as paradas; antes dele usamos o
    // acumulado das paradas já adicionadas.
    if (ride.isRoundtripLeg) {
      final stops = finalCents ?? stopsCents;
      final base = ride.isReturnLeg ? 0 : packageCents;
      final total = base + stops;
      final label = ride.isReturnLeg
          ? (stops > 0
              ? '${_eur(stops)} — volta incluída no pacote, só as paradas'
              : '€0,00 — incluída no pacote')
          : (stops > 0
              ? '${_eur(total)} (ida + volta + paradas)'
              : '${_eur(base)} (ida + volta)');
      return TvdeFareView(
        clientTotalCents: total,
        driverCollectCents: paidOnline ? 0 : total,
        clientLabel: label,
        // Preço do pacote é fixo e a parada tem taxa fixa — nada aqui é
        // estimativa, ao contrário da tarifa por km de uma corrida normal.
        approx: false,
        coveredByPlan: false,
        isPaidOnline: paidOnline,
      );
    }

    // Coberta pelo plano: a corrida não se cobra, as paradas sim.
    if (ride.usedSubscriptionRide) {
      final stops = finalCents ?? stopsCents;
      return TvdeFareView(
        clientTotalCents: stops,
        driverCollectCents: paidOnline ? 0 : stops,
        clientLabel: stops > 0
            ? '${_eur(stops)} — só as paradas (corrida coberta pelo plano)'
            : '€0,00 — coberta pelo plano',
        approx: false,
        coveredByPlan: true,
        isPaidOnline: paidOnline,
      );
    }

    // Corrida normal: depois do finish o `final` JÁ inclui as paradas.
    final total = finalCents ?? (ride.estFareCents + stopsCents);
    return TvdeFareView(
      clientTotalCents: total,
      driverCollectCents: paidOnline ? 0 : total,
      clientLabel: _eur(total),
      approx: finalCents == null,
      coveredByPlan: false,
      isPaidOnline: paidOnline,
    );
  }
}
