// Duas contas Stripe (missão stripe-empresa-2026-11-01): regras do lado da app, sem rede nem SDK.
import 'package:flutter_test/flutter_test.dart';
import 'package:bora_app/services/stripe_contas.dart';

void main() {
  setUp(() {
    StripeContas.chaveDeArranque = 'pk_live_arranque';
    StripeContas.ultimaConta = null;
  });

  test('marcar acrescenta a bandeira sem mexer no mapa original', () {
    final original = <String, dynamic>{'order_id': 'x'};
    final marcado = StripeContas.marcar(original);
    expect(marcado['stripe_contas_v2'], isTrue);
    expect(marcado['order_id'], 'x');
    expect(original.containsKey('stripe_contas_v2'), isFalse);
  });

  test('chaveDaResposta: publishable_key do servidor manda', () {
    final pk = StripeContas.chaveDaResposta({
      'stripe_account': 'empresa',
      'publishable_key': 'pk_live_empresa',
    });
    expect(pk, 'pk_live_empresa');
    expect(StripeContas.ultimaConta, 'empresa');
  });

  test('chaveDaResposta: sem publishable_key e conta pessoal → chave compilada da pessoal ou arranque', () {
    final pk = StripeContas.chaveDaResposta({'stripe_account': 'pessoal'});
    // sem --dart-define nos testes, a compilada está vazia → recurso = arranque
    expect(pk, 'pk_live_arranque');
  });

  test('chaveDaResposta: resposta antiga (sem conta) → null = chave do arranque', () {
    expect(StripeContas.chaveDaResposta({'clientSecret': 'pi_x_secret_y'}), isNull);
    expect(StripeContas.chaveDaResposta(null), isNull);
  });

  test('chaveDaResposta ignora publishable_key que não é pk_', () {
    final pk = StripeContas.chaveDaResposta({'stripe_account': 'empresa', 'publishable_key': 'lixo'});
    // empresa sem chave compilada → arranque (nunca uma string inválida)
    expect(pk, 'pk_live_arranque');
  });

  test('chavePara: empresa sem chave compilada cai na do arranque', () {
    expect(StripeContas.chavePara('empresa'), 'pk_live_arranque');
    expect(StripeContas.chavePara('pessoal'), 'pk_live_arranque');
    expect(StripeContas.chavePara(null), 'pk_live_arranque');
  });
}
