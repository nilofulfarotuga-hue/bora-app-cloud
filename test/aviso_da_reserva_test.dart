import 'package:bora_app/models/tvde_ride.dart';
import 'package:flutter_test/flutter_test.dart';

/// [Fix 2026-08-20 — o painel do estado `motorista_atribuido`]
///
/// Entre os 20 e os 10 minutos da hora, a reserva fica em
/// `motorista_atribuido` e o painel do motorista não tinha ramo para esse
/// estado — caía no "A processar… toca para atualizar". Passou a ter um ramo
/// próprio, com esta linha a dizer a hora e o que falta.
void main() {
  // Hora fixa para os testes não dependerem do relógio da máquina.
  final agora = DateTime(2026, 8, 20, 23, 0);

  group('avisoDaReserva', () {
    test('faltam minutos → diz quantos', () {
      expect(
        avisoDaReserva(DateTime(2026, 8, 20, 23, 14), agora: agora),
        'Reserva às 23:14 · faltam 14 min',
      );
    });

    test('a janela que causou o bug (20 → 10 min) fica bem escrita', () {
      expect(avisoDaReserva(DateTime(2026, 8, 20, 23, 20), agora: agora),
          'Reserva às 23:20 · faltam 20 min');
      expect(avisoDaReserva(DateTime(2026, 8, 20, 23, 10), agora: agora),
          'Reserva às 23:10 · faltam 10 min');
    });

    test('mesmo à hora → "é agora", não "faltam 0 min"', () {
      expect(avisoDaReserva(DateTime(2026, 8, 20, 23, 0), agora: agora),
          'Reserva às 23:00 · é agora');
      expect(avisoDaReserva(DateTime(2026, 8, 20, 23, 1), agora: agora),
          'Reserva às 23:01 · é agora');
    });

    test('já passou da hora → também "é agora", nunca um número negativo', () {
      final msg = avisoDaReserva(DateTime(2026, 8, 20, 22, 50), agora: agora);
      expect(msg, 'Reserva às 22:50 · é agora');
      expect(msg, isNot(contains('-')));
    });

    test('mais de uma hora → horas e minutos', () {
      expect(avisoDaReserva(DateTime(2026, 8, 21, 1, 30), agora: agora),
          'Reserva às 01:30 · faltam 2h30min');
    });

    test('hora certa não escreve "0min" pendurado', () {
      expect(avisoDaReserva(DateTime(2026, 8, 21, 1, 0), agora: agora),
          'Reserva às 01:00 · faltam 2h');
    });

    test('a hora vem sempre com dois dígitos', () {
      expect(avisoDaReserva(DateTime(2026, 8, 21, 9, 5), agora: agora),
          contains('09:05'));
    });
  });
}
