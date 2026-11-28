// 28/11/2026 (missão balcao-real, pedido KFC 14658088): talão de 13,60 €
// quando a app mostrava ao estafeta "ao balcão 15,67 €" (13,23 do Box Meal
// Mix + 2,44 da maçaroca extra). O servidor carimba `balcaoReal` (base SEM
// extras, lida no último talão mais barato) e o ecrã do estafeta passa a
// mostrar balcaoReal + opções. O preço do cliente (`price`) não muda.
// Fonte única: lib/services/preco_balcao.dart.

import 'package:bora_app/models/cart_item.dart';
import 'package:bora_app/screens/admin/admin_correcoes_preco_screen.dart';
import 'package:bora_app/screens/admin/admin_product_prices_dialog.dart';
import 'package:bora_app/services/preco_balcao.dart';
import 'package:bora_app/widgets/driver_item_options.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, dynamic> _boxMealMix({double? balcaoReal, int quantidade = 1}) => {
      'productId': 'kfc-box-meal-mix',
      'name': 'Box Meal Mix',
      'price': 18.03,
      'basePrice': 13.23,
      'quantity': quantidade,
      if (balcaoReal != null) 'balcaoReal': balcaoReal,
      'selected_options': [
        {
          'group': 'Extras',
          'items': ['Maçaroca']
        }
      ],
      'selected_options_priced': [
        {
          'group': 'Extras',
          'items': [
            {'name': 'Maçaroca', 'price_add': 2.44}
          ]
        }
      ],
    };

void main() {
  test('com balcaoReal: usa o balcão real + opções (13,60 €, não 15,67 €)',
      () {
    final i = CartItem.fromJson(_boxMealMix(balcaoReal: 11.16));
    expect(i.balcaoReal, 11.16);
    expect(precoBalcaoUnidade(i), closeTo(13.60, 0.0001));
    expect(precoBalcaoLinha(i), closeTo(13.60, 0.0001));
    // O preço do cliente fica exatamente igual.
    expect(i.price, 18.03);
  });

  test('sem balcaoReal: igual a hoje (basePrice + opções = 15,67 €)', () {
    final i = CartItem.fromJson(_boxMealMix());
    expect(i.balcaoReal, isNull);
    expect(precoBalcaoUnidade(i), closeTo(15.67, 0.0001));
  });

  test('parceiro: ignora balcaoReal, igual a hoje', () {
    final i = CartItem.fromJson(_boxMealMix(balcaoReal: 11.16));
    expect(precoBalcaoUnidade(i, parceiro: true), closeTo(15.67, 0.0001));
    final semBase = CartItem.fromJson({
      'productId': 'menu-parceiro',
      'name': 'Menu Parceiro',
      'price': 9.5,
      'quantity': 1,
      'balcaoReal': 7.0,
    });
    expect(precoBalcaoUnidade(semBase, parceiro: true), 9.5);
  });

  test('quantidade 2: linha = (balcaoReal + opções) × 2', () {
    final i = CartItem.fromJson(_boxMealMix(balcaoReal: 11.16, quantidade: 2));
    expect(precoBalcaoLinha(i), closeTo(27.20, 0.0001));
    final sem = CartItem.fromJson(_boxMealMix(quantidade: 2));
    expect(totalBalcao([i, sem]), closeTo(27.20 + 31.34, 0.0001));
  });

  test('balcaoReal a 0 ou inválido não conta (cai no basePrice)', () {
    final i = CartItem.fromJson(_boxMealMix(balcaoReal: 0));
    expect(precoBalcaoUnidade(i), closeTo(15.67, 0.0001));
  });

  test('produto ao quilo: ignora balcaoReal (a balança valida sobre o basePrice)',
      () {
    final i = CartItem.fromJson({
      'productId': 'continente-banana',
      'name': 'Banana',
      'price': 1.49,
      'basePrice': 1.30,
      'quantity': 1,
      'variable_weight': true,
      'balcaoReal': 1.10,
    });
    expect(precoBalcaoUnidade(i), 1.30);
  });

  test('toJson e cópia da lista do estafeta preservam o balcaoReal', () {
    final i = CartItem.fromJson(_boxMealMix(balcaoReal: 11.16));
    expect(i.toJson()['balcaoReal'], 11.16);
    expect(CartItem.fromJson(_boxMealMix()).toJson().containsKey('balcaoReal'),
        isFalse);
    final copia = copyOrderItemsForDriverSheet([i]).single;
    expect(copia.balcaoReal, 11.16);
    expect(precoBalcaoUnidade(copia), closeTo(13.60, 0.0001));
    final relido = CartItem.fromJson(copia.toJson());
    expect(precoBalcaoUnidade(relido), closeTo(13.60, 0.0001));
  });

  group('painel admin (PT-BR)', () {
    test('estado estafeta tem nome próprio e texto do cliente igual', () {
      expect(rotuloSituacaoCorrecao('estafeta'), 'Só estafeta');
      expect(rotuloSituacaoCorrecao('pending'), 'Pendente');
      expect(textoCorrigidoSoEstafeta,
          'Corrigido só para o estafeta (o cliente continua a pagar o mesmo)');
    });

    test('aprovar mais barato mostra a resposta so_estafeta', () {
      expect(
          textoRespostaCorrecao(
              {'ok': true, 'so_estafeta': true, 'balcao_real': 11.16},
              'Preço aprovado'),
          '$textoCorrigidoSoEstafeta — balcão €11.16 ✅');
      expect(
          textoRespostaCorrecao(
              {'ok': true, 'preco_novo': 14.5}, 'Preço aprovado'),
          'Preço aprovado ✅');
      expect(
          textoRespostaCorrecao(
              {'ok': true, 'balcao_real': null}, 'Preço revertido'),
          startsWith('Balcão real tirado'));
    });

    test('erro da RPC admin_preco_balcao_real em português', () {
      expect(
          erroBalcaoRealPt('balcao_real_tem_de_ser_menor_que_o_preco',
              preco: 13.23),
          contains('tem de ser MENOR que o preço do catálogo (€13.23)'));
      expect(erroBalcaoRealPt('not_found'), 'Produto não encontrado.');
    });
  });
}
