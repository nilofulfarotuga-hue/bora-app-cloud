import 'package:bora_app/models/tvde_ride.dart';
import 'package:bora_app/stores/tvde_store.dart';
import 'package:flutter_test/flutter_test.dart';

// [24/10/2026 · geral-sabado-24-10, bloco 4b] Reserva em que o cliente não
// apareceu: antes saía "cancelada" na app e "nao_compareceu" cru no painel.
void main() {
  TvdeRide reserva(String status, String reservationStatus) => TvdeRide.fromMap({
        'id': 'r1',
        'client_id': 'c',
        'status': status,
        'reservation_status': reservationStatus,
        'payment_method': 'mbway',
        'payment_status': 'succeeded',
        'scheduled_at': DateTime.utc(2026, 10, 20, 9).toIso8601String(),
        'dest_label': 'Hospital Sousa Martins, Guarda',
        'origin_label': 'Praça Luís de Camões, Guarda',
      });

  test('cliente não apareceu = "não compareceu" (não "cancelada")', () {
    expect(estadoReservaPt(reserva('no_show', 'nao_compareceu')), 'não compareceu');
  });

  test('só a reserva marcada como nao_compareceu também conta', () {
    expect(estadoReservaPt(reserva('agendada', 'nao_compareceu')), 'não compareceu');
  });

  test('cancelada continua cancelada', () {
    expect(estadoReservaPt(reserva('cancelada_cliente', 'cancelada')), 'cancelada');
  });

  test('concluída continua concluída', () {
    expect(estadoReservaPt(reserva('finalizada', 'ativada')), 'concluída');
  });
}
