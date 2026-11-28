// Planos de limpeza (missão limpeza-planos-empresas-2026-11-28): o que a app lê do servidor.
import 'package:bora_app/models/cleaning_plan_models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('preço do plano semanal de 3 h como o servidor o devolve (prova e2e 17563)', () {
    final q = CleaningPlanQuote.fromJson({
      'segment': 'casa',
      'frequency': 'weekly',
      'label': 'Semanal',
      'hours': 3,
      'team_size': 1,
      'client_cents_per_hour': 1000,
      'pro_cents_per_hour': 918,
      'labor_cents': 3000,
      'products_cents': 0,
      'products_included': false,
      'travel_fee_cents': 0,
      'travel': {'distance_km': 2.5, 'travel_fee_cents': 0},
      'total_per_visit_cents': 3000,
      'pro_earnings_cents': 2754,
      'bora_fee_cents': 246,
      'visits_per_month': 4.33,
      'approx_month_cents': 12990,
      'min_hours': 2,
      'ladder': [
        {'frequency': 'once', 'label': 'Uma vez', 'client_cents_per_hour': 1200},
        {'frequency': 'biweekly', 'label': 'De 15 em 15 dias', 'client_cents_per_hour': 1100},
        {'frequency': 'weekly', 'label': 'Semanal', 'client_cents_per_hour': 1000},
        {'frequency': 'multi_weekly', 'label': 'Mais de uma vez por semana', 'client_cents_per_hour': 980},
      ],
    });
    expect(q.totalPerVisitCents, 3000);
    expect(q.proEarningsCents, 2754);
    expect(q.approxMonthCents, 12990);
    expect(q.travelDistanceKm, 2.5);
    expect(q.ladder.map((s) => s.clientCentsPerHour), [1200, 1100, 1000, 980]);
  });

  test('dias por semana iguais ao servidor', () {
    expect(CleaningPlanLabels.diasPorSemana('weekly'), (1, 1));
    expect(CleaningPlanLabels.diasPorSemana('biweekly'), (1, 1));
    expect(CleaningPlanLabels.diasPorSemana('multi_weekly'), (2, 7));
    expect(CleaningPlanLabels.diasPorSemana('weekly_2'), (2, 2));
    expect(CleaningPlanLabels.diasPorSemana('weekly_3plus'), (3, 7));
  });

  test('horas sugeridas pela tipologia; com 2 profissionais é metade', () {
    const d = {'t0_t1': 180, 't2': 240, 't3': 300, 't4plus': 360};
    expect(CleaningPlanLabels.horasSugeridas(d, 't2', 1), 4);
    expect(CleaningPlanLabels.horasSugeridas(d, 't3', 1), 5);
    expect(CleaningPlanLabels.horasSugeridas(d, 't3', 2), 3);
    expect(CleaningPlanLabels.horasSugeridas(d, 't0_t1', 2), 2); // nunca abaixo do mínimo de 2 h
    expect(CleaningPlanLabels.sugereEquipa('t3'), isTrue);
    expect(CleaningPlanLabels.sugereEquipa('t2'), isFalse);
  });

  test('o plano lê visitas, cobranças e o cartão', () {
    final p = CleaningPlan.fromJson({
      'id': 'p1',
      'segment': 'empresa',
      'frequency': 'weekly_1',
      'label': '1 vez por semana',
      'status': 'active',
      'days_of_week': [4],
      'visit_time': '20:00:00',
      'hours': 1,
      'team_size': 1,
      'billing_mode': 'per_visit',
      'client_cents_per_hour': 1400,
      'total_per_visit_cents': 1400,
      'approx_month_cents': 6067,
      'card_brand': 'visa',
      'card_last4': '4242',
      'company_name': 'Ótica Exemplo',
      'next_visits': [
        {'booking_id': 'b1', 'scheduled_at': '2026-12-03T20:00:00Z', 'date': '2026-12-03', 'status': 'accepted',
         'payment_status': 'held', 'total_cents': 1400, 'confirmed': true, 'cleaner_name': 'Ana', 'can_skip': true},
      ],
      'charges': [
        {'id': 'c1', 'kind': 'visit', 'amount_cents': 1400, 'status': 'requires_action', 'card_last4': '4242'},
      ],
      'needs_action': true,
    });
    expect(p.isEmpresa, isTrue);
    expect(p.horaCurta, '20:00');
    expect(p.nextVisits.single.paid, isTrue);
    expect(p.charges.single.needsAction, isTrue);
    expect(CleaningPlanLabels.dias(p.daysOfWeek), 'Qui');
  });
}
