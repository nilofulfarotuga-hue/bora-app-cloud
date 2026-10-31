// Limpeza — 5 minutos sem taxa depois de marcar (31/10/2026).
// O servidor já não cobra (cleaning_cancel_grace_minutes = 5, migração
// 20261031195712); o ecrã de cancelar tem de dizer o mesmo. Conta igual à do
// servidor: now() - created_at <= minutos.
import 'package:bora_app/models/cleaning_models.dart';
import 'package:flutter_test/flutter_test.dart';

CleaningBooking _reserva({String? createdAt}) => CleaningBooking.fromSupabase({
      'id': 'b1',
      'client_user_id': 'u1',
      'scheduled_at': '2026-11-01T10:00:00Z',
      'status': 'pending',
      if (createdAt != null) 'created_at': createdAt,
    });

void main() {
  final marcada = DateTime.parse('2026-10-31T22:00:00Z');

  test('lê created_at da linha da base', () {
    final b = _reserva(createdAt: '2026-10-31T22:00:00Z');
    expect(b.createdAt, isNotNull);
    expect(b.createdAt!.isAtSameMomentAs(marcada), isTrue);
  });

  test('dentro dos 5 minutos: sem taxa', () {
    final b = _reserva(createdAt: '2026-10-31T22:00:00Z');
    expect(
        b.cancelaSemTaxaPorAcabarDeMarcar(
            marcada.add(const Duration(minutes: 4, seconds: 59)), 5),
        isTrue);
    expect(
        b.cancelaSemTaxaPorAcabarDeMarcar(
            marcada.add(const Duration(minutes: 5)), 5),
        isTrue);
  });

  test('depois dos 5 minutos, sem data ou com 0 minutos: regra de sempre', () {
    final b = _reserva(createdAt: '2026-10-31T22:00:00Z');
    expect(
        b.cancelaSemTaxaPorAcabarDeMarcar(
            marcada.add(const Duration(minutes: 5, seconds: 1)), 5),
        isFalse);
    expect(b.cancelaSemTaxaPorAcabarDeMarcar(marcada, 0), isFalse);
    expect(_reserva().cancelaSemTaxaPorAcabarDeMarcar(marcada, 5), isFalse);
  });
}
