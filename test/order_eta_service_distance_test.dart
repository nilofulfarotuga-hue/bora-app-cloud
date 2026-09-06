import 'package:bora_app/services/order_eta_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';

// Coordenadas reais confirmadas na DB (tabela restaurants, Guarda) em
// 2026-07-15 — investigação do bug "distância km errada nas listas de
// restaurantes". Objectivo: provar que OrderEtaService.distanceKmBetween
// calcula haversine real por-restaurante (não um valor fixo por categoria).
void main() {
  const client = LatLng(40.5402657, -7.2673597); // "Rua do Torreão 14, Guarda"
  const acai = LatLng(40.5369, -7.2681); // Sabores de Casa Açaí
  const paulista = LatLng(40.5402657, -7.2673597); // pizzaria Paulista
  const pizzaDanilo = LatLng(40.5402657, -7.2673597); // pizza danilo
  const kfc = LatLng(40.551987, -7.24888);
  const mcdonalds = LatLng(40.542704, -7.239618);
  const burgerKing = LatLng(40.534021, -7.243637);

  test('distanceKmBetween devolve null sem coordenadas', () {
    expect(OrderEtaService.distanceKmBetween(null, acai), isNull);
    expect(OrderEtaService.distanceKmBetween(client, null), isNull);
  });

  test('mesmo ponto (pizza danilo == pizzaria Paulista) dá 0.0 km real', () {
    // Ambos registados no mesmo endereço — 0.0 km é o valor correcto, não bug.
    expect(
      OrderEtaService.distanceKmBetween(client, paulista)!.toStringAsFixed(1),
      '0.0',
    );
    expect(
      OrderEtaService.distanceKmBetween(client, pizzaDanilo)!
          .toStringAsFixed(1),
      '0.0',
    );
  });

  test('restaurantes com coordenadas diferentes dão distâncias diferentes',
      () {
    final dAcai = OrderEtaService.distanceKmBetween(client, acai)!;
    final dKfc = OrderEtaService.distanceKmBetween(client, kfc)!;
    final dMcdonalds = OrderEtaService.distanceKmBetween(client, mcdonalds)!;
    final dBurgerKing =
        OrderEtaService.distanceKmBetween(client, burgerKing)!;

    // Nenhum destes deve colapsar para o mesmo valor fixo — cada par
    // cliente↔restaurante tem uma distância haversine própria.
    final distances = [dAcai, dKfc, dMcdonalds, dBurgerKing];
    expect(distances.toSet().length, distances.length,
        reason: 'distâncias não podem repetir-se entre restaurantes com '
            'coordenadas diferentes — indicaria valor fixo, não haversine');

    // Sanidade geográfica: Açaí é o mais próximo (~0.4 km), os 3 fast-food
    // ficam claramente mais longe (~1.9–2.4 km), nenhum é exactamente igual.
    expect(dAcai, lessThan(1.0));
    expect(dKfc, greaterThan(1.5));
    expect(dMcdonalds, greaterThan(1.5));
    expect(dBurgerKing, greaterThan(1.5));
  });
}
