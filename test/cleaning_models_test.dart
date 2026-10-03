import 'package:bora_app/models/cleaning_models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('CleaningStatus.fromDb', () {
    test('mapeia todos os estados do CHECK de cleaning_bookings', () {
      expect(CleaningStatus.fromDb('scheduled'), CleaningStatus.scheduled);
      expect(CleaningStatus.fromDb('accepted'), CleaningStatus.accepted);
      expect(CleaningStatus.fromDb('on_the_way'), CleaningStatus.onTheWay);
      expect(CleaningStatus.fromDb('in_progress'), CleaningStatus.inProgress);
      expect(CleaningStatus.fromDb('done'), CleaningStatus.done);
      expect(CleaningStatus.fromDb('completed'), CleaningStatus.completed);
      expect(CleaningStatus.fromDb('cancelled_client'),
          CleaningStatus.cancelledClient);
      expect(CleaningStatus.fromDb('cancelled_cleaner'),
          CleaningStatus.cancelledCleaner);
    });

    test('desconhecido/null cai em scheduled (default seguro)', () {
      expect(CleaningStatus.fromDb(null), CleaningStatus.scheduled);
      expect(CleaningStatus.fromDb('???'), CleaningStatus.scheduled);
    });

    test('isCancelled / isActive coerentes', () {
      expect(CleaningStatus.cancelledClient.isCancelled, isTrue);
      expect(CleaningStatus.cancelledCleaner.isCancelled, isTrue);
      expect(CleaningStatus.completed.isActive, isFalse);
      expect(CleaningStatus.cancelledClient.isActive, isFalse);
      for (final s in const [
        CleaningStatus.scheduled,
        CleaningStatus.accepted,
        CleaningStatus.onTheWay,
        CleaningStatus.inProgress,
        CleaningStatus.done,
      ]) {
        expect(s.isActive, isTrue, reason: '$s devia ser ativa');
      }
    });
  });

  group('CleaningLabels', () {
    test('euro formata cents com vírgula PT', () {
      expect(CleaningLabels.euro(4500), '€45,00');
      expect(CleaningLabels.euro(0), '€0,00');
      expect(CleaningLabels.euro(12345), '€123,45');
    });

    test('labels cobrem os valores dos CHECKs', () {
      expect(CleaningLabels.types.keys,
          containsAll(['standard', 'deep', 'post_works']));
      expect(CleaningLabels.sizes.keys,
          containsAll(['t0_t1', 't2', 't3', 't4plus']));
      expect(CleaningLabels.recurrences.keys,
          containsAll(['single', 'weekly', 'biweekly']));
    });
  });

  group('CleaningBooking.fromSupabase', () {
    Map<String, dynamic> baseRow() => {
          'id': 'b-1',
          'client_user_id': 'u-1',
          'cleaner_id': 'c-1',
          'recurrence_group_id': null,
          'recurrence': 'weekly',
          'cleaning_type': 'deep',
          'pricing_mode': 'fixed',
          'home_size': 't2',
          'hours': null,
          'scheduled_at': '2026-07-10T09:00:00Z',
          'duration_min': 240,
          'address_street': 'Rua A 1',
          'address_city': 'Guarda',
          'address_postal': '6300-000',
          'notes': 'tenho um cão',
          'products_by': 'cleaner',
          'status': 'accepted',
          'payment_method': 'card',
          'payment_status': 'held',
          'base_cents': 4500,
          'type_surcharge_cents': 1800,
          'recurring_discount_cents': 630,
          'products_fee_cents': 300,
          'total_cents': 5970,
          'cleaner_earnings_cents': 5120,
          'bora_fee_cents': 850,
          'cancel_fee_cents': 0,
        };

    test('mapeia todas as colunas usadas pela UI', () {
      final b = CleaningBooking.fromSupabase(baseRow());
      expect(b.id, 'b-1');
      expect(b.status, CleaningStatus.accepted);
      expect(b.cleaningType, 'deep');
      expect(b.typeLabel, 'Profunda');
      expect(b.sizeLabel, 'T2');
      expect(b.isRecurring, isTrue);
      expect(b.recurrenceLabel, 'Semanal');
      expect(b.productsBy, 'cleaner');
      expect(b.totalCents, 5970);
      expect(b.cleanerEarningsCents, 5120);
      expect(b.paymentMethod, 'card');
      expect(b.paymentStatus, 'held');
      expect(b.scheduledAt.isUtc, isFalse, reason: 'convertido para local');
    });

    test('linha mínima não rebenta (defaults)', () {
      final b = CleaningBooking.fromSupabase({'id': 'b-2'});
      expect(b.status, CleaningStatus.scheduled);
      expect(b.recurrence, 'single');
      expect(b.isRecurring, isFalse);
      expect(b.totalCents, 0);
      expect(b.paymentMethod, 'cash');
      expect(b.notes, '');
    });

    test('modo por hora usa hours no sizeLabel', () {
      final row = baseRow()
        ..['pricing_mode'] = 'hourly'
        ..['hours'] = 3
        ..['home_size'] = null;
      final b = CleaningBooking.fromSupabase(row);
      expect(b.sizeLabel, '3h à hora');
    });
  });

  group('CleaningQuote.fromJson', () {
    test('mapeia breakdown da RPC cleaning_quote', () {
      final q = CleaningQuote.fromJson(const {
        'base_cents': 4500,
        'type_surcharge_cents': 1800,
        'recurring_discount_cents': 630,
        'products_fee_cents': 300,
        'total_cents': 5970,
        'duration_min': 240,
      });
      expect(q.baseCents, 4500);
      expect(q.typeSurchargeCents, 1800);
      expect(q.recurringDiscountCents, 630);
      expect(q.productsFeeCents, 300);
      expect(q.totalCents, 5970);
      expect(q.durationMin, 240);
    });

    test('mapa vazio usa defaults (duração 180)', () {
      final q = CleaningQuote.fromJson(const {});
      expect(q.totalCents, 0);
      expect(q.durationMin, 180);
    });
  });

  group('AvailableCleaner / CleanerSlot', () {
    test('AvailableCleaner.fromJson mapeia perfil público', () {
      final c = AvailableCleaner.fromJson(const {
        'id': 'c-1',
        'name': 'Maria',
        'photo_url': '',
        'bio': 'cuidadosa',
        'rating_avg': 4.8,
        'ratings_count': 12,
        'cleanings_done': 30,
        'is_favorite': true,
      });
      expect(c.name, 'Maria');
      expect(c.ratingAvg, 4.8);
      expect(c.isFavorite, isTrue);
    });

    test('CleanerSlot roundtrip fromSupabase/toJson', () {
      final s = CleanerSlot.fromSupabase(const {
        'weekday': 1,
        'start_time': '09:00:00',
        'end_time': '13:30:00',
      });
      expect(s.weekday, 1);
      expect(s.start, '09:00');
      expect(s.end, '13:30');
      expect(s.toJson(), {'weekday': 1, 'start': '09:00', 'end': '13:30'});
      expect(CleanerSlot.weekdaysPt.length, 7);
    });
  });
}
