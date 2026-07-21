import 'package:flutter_test/flutter_test.dart';

import 'package:bora_app/services/admin/admin_payments_service.dart';

/// Modelo da aba admin "Pagamentos/Cartões" (Carteira Única, Parte 6).
/// A regra que mais importa: só se oferece "Estornar" no que foi mesmo cobrado
/// no cartão — oferecer num pedido em dinheiro seria prometer devolver algo que
/// a Stripe nunca recebeu.
void main() {
  AdminPaymentRow linha({
    String vertical = 'delivery',
    String? pi = 'pi_123',
    int amount = 1240,
    String? status = 'paid',
    String? metodo = 'card',
  }) =>
      AdminPaymentRow.fromMap({
        'vertical': vertical,
        'entity_id': 'ord_1',
        'user_id': 'u1',
        'payment_intent_id': pi,
        'amount_cents': amount,
        'status': status,
        'payment_method': metodo,
        'created_at': '2026-07-21T10:00:00Z',
      });

  group('podeEstornar', () {
    test('cobrança real no cartão pode ser estornada', () {
      expect(linha().podeEstornar, isTrue);
    });

    test('sem PaymentIntent não pode (dinheiro / MB Way por confirmar)', () {
      expect(linha(pi: null, metodo: 'cash').podeEstornar, isFalse);
    });

    test('PaymentIntent com formato estranho não pode', () {
      expect(linha(pi: 'ch_123').podeEstornar, isFalse);
      expect(linha(pi: '').podeEstornar, isFalse);
    });

    test('valor zero não pode ser estornado', () {
      expect(linha(amount: 0).podeEstornar, isFalse);
    });
  });

  group('apresentação', () {
    test('valor em euros com 2 casas', () {
      expect(linha(amount: 1240).valorFormatado, '€12.40');
      expect(linha(amount: 5).valorFormatado, '€0.05');
    });

    test('as 6 verticais têm rótulo PT-BR', () {
      for (final chave in AdminPaymentRow.rotulosVertical.keys) {
        final r = linha(vertical: chave).verticalRotulo;
        expect(r, isNotEmpty);
        expect(r, isNot(chave), reason: '$chave devia ter rótulo legível');
      }
      expect(AdminPaymentRow.rotulosVertical.length, 6);
    });

    test('vertical desconhecida não rebenta — mostra o valor cru', () {
      expect(linha(vertical: 'nova_coisa').verticalRotulo, 'nova_coisa');
    });
  });

  group('fromMap tolerante', () {
    test('campos em falta não rebentam', () {
      final p = AdminPaymentRow.fromMap(const {});
      expect(p.amountCents, 0);
      expect(p.podeEstornar, isFalse);
      expect(p.entityId, '');
    });

    test('data inválida vira null em vez de excepção', () {
      final p = AdminPaymentRow.fromMap(const {'created_at': 'nao-e-data'});
      expect(p.createdAt, isNull);
    });
  });

  group('AdminStuckIntent', () {
    test('converte o epoch da Stripe para data', () {
      final t = AdminStuckIntent.fromMap(const {
        'id': 'pi_x',
        'status': 'requires_action',
        'amount_cents': 300,
        'created': 1784646334,
        'metadata': {'reservation_id': 'r1'},
      });
      expect(t.id, 'pi_x');
      expect(t.amountCents, 300);
      expect(t.created?.year, 2026);
      expect(t.metadata['reservation_id'], 'r1');
    });

    test('sem created não rebenta', () {
      expect(AdminStuckIntent.fromMap(const {'id': 'pi_y'}).created, isNull);
    });
  });
}
