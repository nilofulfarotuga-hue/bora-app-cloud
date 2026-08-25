import 'package:bora_app/models/tvde_plan_quote.dart';
import 'package:bora_app/models/tvde_subscription.dart';
import 'package:flutter_test/flutter_test.dart';

/// TVDE — plano com preço pela ROTA (2026-08-25).
///
/// A conta aberta que o cliente vê antes de pagar é montada a partir do que a
/// RPC `tvde_quote_plan` devolve. Estes testes fixam o contrato: os campos são
/// lidos do servidor (nada de 40/70/132 no código) e a conta fecha —
/// base + excesso = TOTAL, na ordem e no português que o Danilo pediu.
void main() {
  // O exemplo literal do pedido: plano semanal 40,00 € (10 viagens, 2/dia,
  // seg-sex) até 6 km; rota de 8 km ⇒ 2 km × 1,00 € × 10 viagens = 20,00 €;
  // TOTAL 60,00 €.
  Map<String, dynamic> semanal8km() => {
        'base_km': 6,
        'extra_km': 2,
        'rides_total': 10,
        'days': 5,
        'per_km_cents': 100,
        'base_price_cents': 4000,
        'extra_cents': 2000,
        'price_cents': 6000,
        'per_ride_cents': 600,
      };

  group('TvdePlanQuote.fromMap', () {
    test('lê todos os campos do servidor', () {
      final q = TvdePlanQuote.fromMap(semanal8km(), distanceKm: 8);
      expect(q.baseKm, 6);
      expect(q.extraKm, 2);
      expect(q.ridesTotal, 10);
      expect(q.days, 5);
      expect(q.perKmCents, 100);
      expect(q.basePriceCents, 4000);
      expect(q.extraCents, 2000);
      expect(q.priceCents, 6000);
      expect(q.perRideCents, 600);
      expect(q.distanceKm, 8);
    });

    test('campo em falta não rebenta — fica 0 (e o ecrã não acende o botão)',
        () {
      final q = TvdePlanQuote.fromMap(const {}, distanceKm: 3);
      expect(q.priceCents, 0);
      expect(q.ridesTotal, 0);
      expect(q.ridesPerDay, 0, reason: 'days=0 não pode dar divisão por zero');
      expect(q.hasExtra, isFalse);
    });

    test('viagens por dia vêm do servidor (10 viagens / 5 dias = 2)', () {
      final q = TvdePlanQuote.fromMap(semanal8km(), distanceKm: 8);
      expect(q.ridesPerDay, 2);
    });
  });

  group('conta aberta (PT-PT)', () {
    test('rota acima do incluído — base + excesso + TOTAL', () {
      final q = TvdePlanQuote.fromMap(semanal8km(), distanceKm: 8);
      final lines = q.breakdown('Plano Semanal');

      expect(lines.map((l) => '${l.label} ${l.value}').toList(), [
        'Plano Semanal 40,00 €',
        'Inclui 10 viagens 2 por dia, segunda a sexta',
        'Distância incluída até 6 km por viagem',
        'A tua rota 8 km',
        '2 km a mais × 1,00 € × 10 viagens 20,00 €',
        'TOTAL 60,00 €',
      ]);
      expect(lines.last.strong, isTrue, reason: 'o TOTAL vai a negrito');
    });

    test('a conta fecha: base + excesso = TOTAL', () {
      final q = TvdePlanQuote.fromMap(semanal8km(), distanceKm: 8);
      expect(q.basePriceCents + q.extraCents, q.priceCents);
    });

    test('rota dentro do incluído — sem linha de excesso', () {
      final q = TvdePlanQuote.fromMap({
        ...semanal8km(),
        'extra_km': 0,
        'extra_cents': 0,
        'price_cents': 4000,
      }, distanceKm: 5);
      final lines = q.breakdown('Plano Semanal');

      expect(q.hasExtra, isFalse);
      expect(lines.any((l) => l.label.contains('km a mais')), isFalse);
      expect(lines.last.label, 'TOTAL');
      expect(lines.last.value, '40,00 €');
    });
  });

  group('formatação PT-PT', () {
    test('euros com vírgula', () {
      expect(TvdePlanQuote.eur(4000), '40,00 €');
      expect(TvdePlanQuote.eur(100), '1,00 €');
      expect(TvdePlanQuote.eur(13250), '132,50 €');
      expect(TvdePlanQuote.eur(0), '0,00 €');
    });

    test('km sem casas decimais inúteis', () {
      expect(TvdePlanQuote.km(8), '8');
      expect(TvdePlanQuote.km(8.4), '8,4');
      expect(TvdePlanQuote.km(12.05), '12,1');
    });
  });

  group('TvdeSubscription — rota guardada', () {
    test('lê km incluídos e rota da subscrição', () {
      final sub = TvdeSubscription.fromMap(const {
        'id': 's1',
        'plan': 'semanal',
        'rides_total': 10,
        'rides_used': 3,
        'daily_included': 2,
        'price_cents': 6000,
        'km_included': 6,
        'distance_km': 8,
        'route_origin_label': 'Rua A, Guarda',
        'route_dest_label': 'Rua B, Guarda',
      });
      expect(sub.kmIncluded, 6);
      expect(sub.distanceKm, 8);
      expect(sub.hasRoute, isTrue);
      expect(sub.ridesLeft, 7);
    });

    test('subscrição antiga sem rota não finge ter uma', () {
      final sub = TvdeSubscription.fromMap(const {
        'id': 's2',
        'plan': 'mensal',
        'rides_total': 44,
        'rides_used': 0,
        'daily_included': 2,
        'price_cents': 13200,
      });
      expect(sub.kmIncluded, isNull);
      expect(sub.distanceKm, isNull);
      expect(sub.hasRoute, isFalse);
    });
  });
}
