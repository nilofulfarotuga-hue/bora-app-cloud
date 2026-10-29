import 'dart:convert';

import 'package:bora_app/stores/cart_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// [melhorias-paridade 26/10, adendo B] Carrinho guardado de loja NÃO
/// parceira: ao repor, nunca se assume parceira (era `isPartnerStore ?? true`,
/// e o cliente via a taxa de 5% de parceiro — 0,48 € num cesto de 9,65 € do
/// Burger King). Só muda o que se VÊ; o servidor calcula sempre pela loja.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Map<String, Object> guardado({bool? parceira}) => {
        'bora_cart_v1': jsonEncode({
          'items': [
            {'productId': 'bk1', 'name': 'Whopper', 'price': 9.65, 'quantity': 1}
          ],
          'serviceType': 'restaurant',
          if (parceira != null) 'isPartnerStore': parceira,
          'vendorName': 'Burger King',
        }),
      };

  test('carrinho antigo sem a marca: reposto como NÃO parceira', () async {
    SharedPreferences.setMockInitialValues(guardado());
    final c = CartStore()..lerParceiraParaTeste = (_, __) async => null;
    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect(c.items, isNotEmpty);
    expect(c.isPartnerStore, isFalse);
  });

  test('marca errada guardada: a loja manda (não parceira)', () async {
    SharedPreferences.setMockInitialValues(guardado(parceira: true));
    final c = CartStore();
    await Future<void>.delayed(const Duration(milliseconds: 50));
    c.lerParceiraParaTeste = (id, nome) async {
      expect(nome, 'Burger King');
      return false;
    };
    await c.confirmarParceiraDaLoja();
    expect(c.isPartnerStore, isFalse);
    // O carrinho passa a ser de não-parceiro: a taxa mostrada é a do
    // não-parceiro (lida do servidor), não os 5% do parceiro.
    expect(c.taxaServicoNaoParceiro, isNotNull);
  });

  test('resposta atrasada da loja antiga não mexe na loja nova', () async {
    SharedPreferences.setMockInitialValues(guardado(parceira: false));
    final c = CartStore();
    await Future<void>.delayed(const Duration(milliseconds: 50));
    c.lerParceiraParaTeste = (id, nome) async {
      // Enquanto o servidor responde, o cliente abre outra loja (parceira).
      c.configureSession(
        serviceType: c.serviceType,
        isPartnerStore: true,
        vendorName: 'Mr Kebab',
        vendorRestaurantId: 'mrkebab-guarda',
      );
      return false;
    };
    await c.confirmarParceiraDaLoja();
    expect(c.vendorName, 'Mr Kebab');
    expect(c.isPartnerStore, isTrue, reason: 'a resposta do Burger King chegou tarde');
  });
}
