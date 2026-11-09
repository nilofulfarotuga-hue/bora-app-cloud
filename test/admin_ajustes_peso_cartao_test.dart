// Painel admin — Ajustes de peso: o resumo das cobranças da diferença no
// cartão (02/11/2026, missão zerar-2026-11-02, B3). Sem rede.
import 'package:bora_app/screens/admin/admin_ajustes_peso_screen.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, dynamic> _linha(String pedido, int delta, String? via) => {
      'order_id': pedido,
      'delta_client_cents': delta,
      'settled_via': via,
    };

void main() {
  test('conta por pedido: cobrado, a cobrar e o que a Bora assumiu', () {
    final texto = resumoCobrancasCartaoPeso([
      _linha('p1', 192, 'cartao_cobrado'),
      _linha('p1', 118, 'cartao_cobrado'), // 2 produtos, o mesmo pedido
      _linha('p2', 90, 'cartao_pendente'),
      _linha('p3', 120, 'bora_assume'),
      _linha('p4', 50, 'dinheiro'),
      _linha('p5', -30, 'carteira'),
      _linha('p6', 40, null), // ainda não fechado
    ]);
    expect(texto,
        'Cartão: 1 pedido(s) cobrado(s) 3,10 € · 1 a cobrar 0,90 € · Bora assumiu 1,20 € (1)');
  });

  test('sem cobranças no cartão: zeros', () {
    expect(resumoCobrancasCartaoPeso(const []),
        'Cartão: 0 pedido(s) cobrado(s) 0,00 € · 0 a cobrar 0,00 € · Bora assumiu 0,00 € (0)');
  });

  test('o acerto novo tem nome em PT-BR', () {
    expect(textoAcertoPeso('cartao_cobrado'), 'Cartão — diferença cobrada');
    expect(textoAcertoPeso(null), 'Ainda não fechado');
  });
}
