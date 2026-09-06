/// ETA que o CLIENTE vê num pedido TVDE.
///
/// Ficheiro de propósito puro: **sem Flutter, sem rede, sem estado**. Só
/// aritmética — para poder ser exercitado por um teste directo, sem device
/// nem mapa.
///
/// Regra do Danilo (2026-09-05): o número mostrado ao passageiro é ligeiramente
/// MENOR que o real — 10 minutos mostram 8. O corte tem um tecto absoluto para
/// não mentir grosso em viagens longas (30 min mostram 28, não 24) e um chão
/// para nunca aparecer "0 min" nem negativos.
///
/// ⚠️ Isto é SÓ apresentação. O ETA interno — o que decide o aviso "está quase
/// a chegar" — usa sempre o valor REAL, nunca este.
library;

/// Fallbacks de arranque/offline. A verdade vive em `platform_settings`
/// (categoria `eta`): `tvde_eta_client_discount_pct`,
/// `tvde_eta_client_discount_max_min`, `tvde_eta_client_floor_min`.
const int kTvdeEtaClientDiscountPct = 20;
const int kTvdeEtaClientDiscountMaxMin = 2;
const int kTvdeEtaClientFloorMin = 1;

/// Converte o ETA REAL em minutos no número a mostrar ao cliente.
///
/// ```
/// mostrado = real − min(real × pct/100, maxCorte)
/// mostrado = max(mostrado, chao)
/// ```
///
/// Com os valores por defeito (20 / 2 / 1): 10 → 8, 30 → 28, 3 → 2, 1 → 1.
///
/// Defensivo de propósito: um valor disparatado vindo das settings (pct
/// negativa, chão a zero) nunca pode produzir um ETA de 0 min, negativo, ou
/// maior do que o real.
int tvdeEtaShownMinutes(
  int realMinutes, {
  int discountPct = kTvdeEtaClientDiscountPct,
  int discountMaxMin = kTvdeEtaClientDiscountMaxMin,
  int floorMin = kTvdeEtaClientFloorMin,
}) {
  final chao = floorMin < 1 ? 1 : floorMin;
  if (realMinutes <= chao) return chao;

  final pct = discountPct < 0 ? 0 : (discountPct > 100 ? 100 : discountPct);
  final tecto = discountMaxMin < 0 ? 0 : discountMaxMin;

  final porPercentagem = realMinutes * pct / 100.0;
  final corte =
      porPercentagem < tecto ? porPercentagem : tecto.toDouble();

  final mostrado = (realMinutes - corte).round();
  return mostrado < chao ? chao : mostrado;
}
