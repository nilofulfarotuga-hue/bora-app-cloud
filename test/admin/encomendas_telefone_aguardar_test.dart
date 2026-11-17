import 'package:bora_app/widgets/admin/encomendas_telefone_aguardar_card.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('contagemAteChamar', () {
    final agora = DateTime.utc(2026, 11, 17, 20, 0, 0);

    test('mostra minutos e segundos que faltam', () {
      expect(contagemAteChamar(agora.add(const Duration(minutes: 14, seconds: 5)), agora), '14:05');
      expect(contagemAteChamar(agora.add(const Duration(seconds: 9)), agora), '00:09');
    });

    test('depois da hora diz que está a chamar', () {
      expect(contagemAteChamar(agora, agora), 'a chamar…');
      expect(contagemAteChamar(agora.subtract(const Duration(minutes: 1)), agora), 'a chamar…');
    });

    test('sem hora mostra traço', () {
      expect(contagemAteChamar(null, agora), '—');
    });
  });

  test('lista antiga: só fica o que ainda espera pelo entregador', () {
    final lista = EncomendaAguardar.daListaAntiga([
      {'order_id': 'a', 'loja': 'Jyosmi', 'estado_pedido': 'preparing', 'libertado_em': null, 'cancelado_em': null,
        'chama_estafeta_as': '2026-11-17T20:15:00Z'},
      {'order_id': 'b', 'loja': 'Jyosmi', 'estado_pedido': 'callingDriver', 'libertado_em': '2026-11-17T20:00:00Z',
        'cancelado_em': null},
      {'order_id': 'c', 'loja': 'Fuku', 'estado_pedido': 'preparing', 'libertado_em': null,
        'cancelado_em': '2026-11-17T20:00:00Z'},
      {'order_id': 'd', 'loja': 'Fuku', 'estado_pedido': 'cancelled', 'libertado_em': null, 'cancelado_em': null},
    ]);
    expect(lista.map((p) => p.orderId), ['a']);
    expect(lista.single.loja, 'Jyosmi');
    expect(lista.single.chamaEstafetaAs, DateTime.utc(2026, 11, 17, 20, 15));
  });

  test('resposta da função nova traz o cliente', () {
    final p = EncomendaAguardar.fromMap(const {
      'order_id': 'x1',
      'loja': 'Pôr do Sol',
      'cliente': 'Maria',
      'criado_em': '2026-11-17T19:50:00Z',
      'encomendado_em': null,
      'chama_estafeta_as': '2026-11-17T20:05:00Z',
    });
    expect(p.cliente, 'Maria');
    expect(p.encomendadoEm, isNull);
  });
}
