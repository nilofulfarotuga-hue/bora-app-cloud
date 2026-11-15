// app-15-11 (bloco G, varredura do app de 15/11/2026): consertos do que o
// revisor de contexto limpo achou nos ecrãs do cliente e do parceiro.
import 'dart:io';

import 'package:bora_app/services/wallet_service.dart';
import 'package:flutter_test/flutter_test.dart';

String _ler(String caminho) =>
    File(caminho).readAsStringSync().replaceAll(String.fromCharCode(13), '');

WalletBalance _saldo(int cents) => WalletBalance(
      userId: 'u1',
      freeCents: cents,
      tokensBalance: 0,
      tokenValueCentsX100: 50,
      lastTransactions: const [],
    );

void main() {
  test('saldo da carteira no formato de Portugal (vírgula e € no fim)', () {
    expect(_saldo(1250).freeFormatted, '12,50 €');
    expect(_saldo(-150).freeFormatted, '-1,50 €');
    expect(_saldo(0).freeFormatted, '0,00 €');
  });

  test('parceiro nunca sai do _RootNavigator por pushReplacement', () {
    final pendente = _ler('lib/screens/pending_approval_screen.dart');
    expect(pendente, isNot(contains('pushReplacement')),
        reason: '"Voltar ao Login" termina a sessão como o Perfil');
    expect(pendente, contains('clearRole()'));
    final registo = _ler('lib/screens/register_partner_screen.dart');
    expect(registo, contains('aoSubmeter();'));
    final entrada = _ler('lib/screens/partner_entry_screen.dart');
    expect(entrada, contains('RegisterPartnerScreen(aoSubmeter: _recarregar)'));
    expect(entrada, contains('statusSnap.hasError'),
        reason: 'sem rede não se manda criar outra loja');
  });

  test('o estado da loja não engole erros de rede', () {
    final store = _ler('lib/stores/restaurant_store.dart');
    final i = store.indexOf('Future<String?> ownRestaurantApprovalStatus');
    final fim = store.indexOf('// ─── Load from Supabase', i);
    expect(store.substring(i, fim), contains('rethrow;'));
  });

  test('ao parceiro não vão erros técnicos ao aceitar ou marcar pronto', () {
    final painel = _ler('lib/screens/partner_dashboard_screen.dart');
    for (final antigo in [
      r"Text('Erro ao aceitar pedido: $e')",
      r"Text('Erro ao aceitar: $e')",
      r"Text('Erro a registar decisão: $e')",
    ]) {
      expect(painel, isNot(contains(antigo)), reason: antigo);
    }
  });

  test('detalhe do pedido diz o meio de pagamento por extenso', () {
    final detalhe = _ler('lib/screens/order_details_screen.dart');
    expect(detalhe, isNot(contains('paymentMethod.name.toUpperCase()')));
  });
}
