import 'package:bora_app/models/restaurant_model.dart';
import 'package:flutter_test/flutter_test.dart';

/// SELO "FRESCURA GARANTIDA" (2026-09-03).
///
/// O selo estava em `MarketStoreTab` **sem condição nenhuma** — aparecia em
/// qualquer loja. A Wells (farmácia) e a Worten (electrónica) apareciam a
/// prometer frescura. Apanhado nas capturas de ecrã para o filme do Bora.
///
/// A regra que o Danilo deu: o selo só em **Restaurantes, Supermercados e
/// Sobremesas**; nunca em Farmácia, Lojas, Beleza ou Festas.
///
/// Os dados abaixo são as linhas REAIS em produção (confirmadas por SQL a
/// 2026-09-03), não exemplos inventados.
RestaurantModel _loja({
  required String id,
  required String nome,
  required String categoria,
  List<String> extras = const [],
}) {
  final principal = BusinessCategory.values.firstWhere(
    (c) => c.name == categoria,
    orElse: () => BusinessCategory.restaurant,
  );
  return RestaurantModel(
    id: id,
    name: nome,
    phone: '',
    address: '',
    email: '',
    photoUrl: '',
    cuisineType: '',
    isPartner: false,
    category: principal,
    extraCategories: RestaurantModel.parseExtraCategories(extras, principal),
  );
}

void main() {
  group('MOSTRA o selo — onde há mesmo comida fresca', () {
    test('restaurante (McDonald\'s, KFC, Burger King)', () {
      for (final nome in ['McDonald\'s', 'KFC', 'Burger King']) {
        final loja = _loja(id: nome, nome: nome, categoria: 'restaurant');
        expect(loja.podeAnunciarFrescura, isTrue, reason: nome);
      }
    });

    test('supermercado (Continente, Auchan, Pingo Doce, Intermarché)', () {
      for (final nome in ['Continente', 'Auchan', 'Pingo Doce', 'Intermarché']) {
        final loja = _loja(id: nome, nome: nome, categoria: 'supermarket');
        expect(loja.podeAnunciarFrescura, isTrue, reason: nome);
      }
    });

    test('Goola Açaí — restaurante E sobremesa, pelas extra_categories', () {
      final goola = _loja(
        id: 'goola-acai-guarda',
        nome: 'Goola Açaí',
        categoria: 'restaurant',
        extras: ['sobremesa'],
      );
      expect(goola.podeAnunciarFrescura, isTrue);
    });

    test('Sabores de Casa — restaurante E mercado', () {
      final sabores = _loja(
        id: '12aa2cbb-01bd-443b-a17e-633c169d4864',
        nome: 'Sabores de Casa Açaí',
        categoria: 'restaurant',
        extras: ['supermarket'],
      );
      expect(sabores.podeAnunciarFrescura, isTrue);
    });

    test('loja só de sobremesas, sem ser restaurante', () {
      final so = _loja(id: 'x', nome: 'Gelataria', categoria: 'sobremesa');
      expect(so.podeAnunciarFrescura, isTrue);
    });
  });

  group('NÃO mostra o selo — era aqui que estava a mentir', () {
    test('farmácia (Wells) — o caso que apareceu no filme', () {
      final wells =
          _loja(id: 'wells-guarda', nome: 'Wells', categoria: 'pharmacy');
      expect(wells.podeAnunciarFrescura, isFalse);
    });

    test('loja (Worten, Kiwoko, Leroy Merlin, Zippy)', () {
      for (final nome in ['Worten', 'Kiwoko', 'Leroy Merlin', 'Zippy']) {
        final loja = _loja(id: nome, nome: nome, categoria: 'store');
        expect(loja.podeAnunciarFrescura, isFalse, reason: nome);
      }
    });

    test('festas por encomenda (Sabores do Brasil - Keli Barbosa)', () {
      final keli = _loja(
        id: 'sabores-brasil-guarda',
        nome: 'Sabores do Brasil - Keli Barbosa',
        categoria: 'festas',
      );
      expect(keli.podeAnunciarFrescura, isFalse);
    });

    test('beleza', () {
      final beleza = _loja(id: 'b', nome: 'Salão', categoria: 'beauty');
      expect(beleza.podeAnunciarFrescura, isFalse);
    });
  });

  test('a regra cobre TODAS as categorias — nenhuma fica por decidir', () {
    const mostram = {
      BusinessCategory.restaurant,
      BusinessCategory.supermarket,
      BusinessCategory.sobremesa,
    };
    for (final c in BusinessCategory.values) {
      final loja = _loja(id: c.name, nome: c.name, categoria: c.name);
      expect(
        loja.podeAnunciarFrescura,
        mostram.contains(c),
        reason: 'categoria ${c.name}: se for nova, decide de que lado fica',
      );
    }
  });
}
