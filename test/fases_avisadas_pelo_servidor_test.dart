// Missão chaves-varredura-2026-10-31 (B1): a app deixou de avisar o cliente nas
// fases que o servidor já avisa (gatilho trg_push_cliente_fase_pedido). Se esta
// lista e a do gatilho se desencontrarem, o cliente fica sem aviso ou recebe dois.
import 'package:bora_app/models/order_model.dart';
import 'package:bora_app/services/notification_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('as fases do gatilho do servidor são exatamente estas', () {
    // Igual ao IF do fn_push_cliente_fase_pedido (migração 20261031122421).
    expect(fasesAvisadasPeloServidor, {
      'preparing',
      'readyForPickup',
      'driverAccepted',
      'pickedUp',
      'onTheWay',
      'delivered',
    });
  });

  test('callingDriver continua a ser avisado pela app (o servidor não o cobre)', () {
    expect(fasesAvisadasPeloServidor.contains(OrderStatus.callingDriver.name), isFalse);
  });

  test('os nomes batem com o enum OrderStatus (a app manda status.name)', () {
    final nomes = OrderStatus.values.map((s) => s.name).toSet();
    for (final f in fasesAvisadasPeloServidor) {
      expect(nomes.contains(f), isTrue, reason: '$f não existe em OrderStatus');
    }
  });
}
