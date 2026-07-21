import 'package:flutter_test/flutter_test.dart';

import 'package:bora_app/stores/tvde_store.dart';

/// Corpo do `charge` da Edge Fn tvde-payment (Carteira Única, Parte 4).
/// A regra que interessa: o `saved_pm_id` só viaja quando o método é cartão.
void main() {
  Map<String, dynamic> body({
    required String method,
    String? savedPmId,
    String? mbwayPhone,
    int tokensUsed = 0,
  }) =>
      buildTvdeChargeBody(
        originLat: 40.5,
        originLng: -7.26,
        originLabel: 'Guarda',
        destLat: 40.6,
        destLng: -7.3,
        destLabel: 'Sé',
        distanceKm: 4.2,
        method: method,
        mbwayPhone: mbwayPhone,
        tokensUsed: tokensUsed,
        savedPmId: savedPmId,
      );

  test('cartão com cartão guardado envia saved_pm_id', () {
    final b = body(method: 'card', savedPmId: 'pm_visa');
    expect(b['saved_pm_id'], 'pm_visa');
    expect(b['method'], 'card');
    expect(b['action'], 'charge');
  });

  test('MB Way NUNCA envia saved_pm_id, mesmo havendo cartão guardado', () {
    final b = body(method: 'mbway', savedPmId: 'pm_visa', mbwayPhone: '912345678');
    expect(b.containsKey('saved_pm_id'), isFalse);
    expect(b['phone'], '912345678');
  });

  test('cartão sem cartão guardado omite o campo (PaymentSheet)', () {
    final b = body(method: 'card');
    expect(b.containsKey('saved_pm_id'), isFalse);
  });

  test('sem tokens, o campo tokens_used nem vai', () {
    expect(body(method: 'card').containsKey('tokens_used'), isFalse);
    expect(body(method: 'card', tokensUsed: 30)['tokens_used'], 30);
  });

  test('sem telemóvel, o campo phone nem vai', () {
    expect(body(method: 'card').containsKey('phone'), isFalse);
  });

  test('as coordenadas e a distância seguem intactas', () {
    final b = body(method: 'card');
    expect(b['origin_lat'], 40.5);
    expect(b['dest_lng'], -7.3);
    expect(b['distance_km'], 4.2);
  });
}
