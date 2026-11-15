// manha-15-11 bloco C2/C3 (autorizo do Danilo 15/11/2026 08:50).
//
// O erro: quando o servidor respondia 409 "Order already processed" ao pedir o
// MB WAY, a app cancelava o pedido como `payment_failed` — e esse pedido podia
// já estar PAGO. E quando o client-cancel-order recusa cancelar porque o
// pagamento entrou (`already_paid`), a app tratava isso como "sem rede".
// Estes testes provam como a app lê as duas respostas.

import 'package:bora_app/utils/mensagem_mbway.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('409 ao pedir o MB WAY = pedido já tratado, não se cancela', () {
    test('código 409 conta como já tratado', () {
      expect(mbwayJaTratado(status: 409), isTrue);
    });
    test('texto do servidor "Order already processed" conta', () {
      expect(mbwayJaTratado(status: 200, erro: 'Order already processed'),
          isTrue);
    });
    test('outras falhas não contam (cancela-se como antes)', () {
      expect(mbwayJaTratado(status: 400, erro: 'invalid phone'), isFalse);
      expect(mbwayJaTratado(status: 503, erro: 'mbway_disabled'), isFalse);
      expect(mbwayJaTratado(status: null, erro: 'SocketException'), isFalse);
      expect(mbwayJaTratado(), isFalse);
    });
  });

  group('client-cancel-order recusou por já estar pago', () {
    test('already_paid = o pedido segue pago (tokens descontados)', () {
      expect(cancelamentoRecusadoPorPagamento(409, 'already_paid'), isTrue);
    });
    test('already_finalized (já cancelado ou entregue) não é pago', () {
      expect(cancelamentoRecusadoPorPagamento(409, 'already_finalized'),
          isFalse);
    });
    test('outros erros do cancelamento não são pago', () {
      expect(cancelamentoRecusadoPorPagamento(503, 'payment_read_failed'),
          isFalse);
      expect(cancelamentoRecusadoPorPagamento(null, null), isFalse);
    });
  });
}
