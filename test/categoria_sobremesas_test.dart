import 'package:bora_app/models/restaurant_model.dart';
import 'package:flutter_test/flutter_test.dart';

/// CATEGORIA SOBREMESAS (2026-08-27).
///
/// A regra que o Danilo pediu: a Goola Açaí aparece em Sobremesas **E**
/// continua a aparecer em Restaurantes — pelo mesmo mecanismo que já põe o
/// Sabores de Casa dentro de Mercados (`extra_categories`), e **não** pelo
/// caminho das Festas, que ficou só numa categoria.
///
/// Os dados vêm da linha real em produção:
///   category = 'restaurant' · extra_categories = ['sobremesa']
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
    isPartner: true,
    category: principal,
    extraCategories:
        RestaurantModel.parseExtraCategories(extras, principal),
  );
}

void main() {
  final goola = _loja(
    id: 'goola-acai-guarda',
    nome: 'Goola Açaí',
    categoria: 'restaurant',
    extras: ['sobremesa'],
  );

  group('a Goola está nas duas secções ao mesmo tempo', () {
    test('aparece em SOBREMESAS (via extra_categories)', () {
      expect(goola.belongsTo(BusinessCategory.sobremesa), isTrue);
    });

    test('continua a aparecer em RESTAURANTES (categoria principal)', () {
      expect(goola.belongsTo(BusinessCategory.restaurant), isTrue);
    });

    test('não entra em secções onde não foi posta', () {
      expect(goola.belongsTo(BusinessCategory.supermarket), isFalse);
      expect(goola.belongsTo(BusinessCategory.festas), isFalse);
      expect(goola.belongsTo(BusinessCategory.pharmacy), isFalse);
    });
  });

  group('o mecanismo é o mesmo do Sabores de Casa, não o das Festas', () {
    test('Sabores de Casa: restaurante que também está em Mercados', () {
      final sabores = _loja(
        id: '12aa2cbb',
        nome: 'Sabores de Casa Açaí',
        categoria: 'restaurant',
        extras: ['supermarket'],
      );
      expect(sabores.belongsTo(BusinessCategory.restaurant), isTrue);
      expect(sabores.belongsTo(BusinessCategory.supermarket), isTrue);
    });

    test('Sabores do Brasil (festas): fica SÓ numa secção', () {
      final festas = _loja(
        id: 'sabores-brasil-guarda',
        nome: 'Sabores do Brasil - Keli Barbosa',
        categoria: 'festas',
      );
      expect(festas.belongsTo(BusinessCategory.festas), isTrue);
      expect(festas.belongsTo(BusinessCategory.restaurant), isFalse);
      expect(festas.belongsTo(BusinessCategory.sobremesa), isFalse);
    });
  });

  group('o slug e o nome que o cliente vê', () {
    test('slug técnico é `sobremesa` — igual ao que está na base', () {
      expect(BusinessCategory.sobremesa.name, 'sobremesa');
    });

    test('o cliente lê "Sobremesas" (PT-PT)', () {
      expect(BusinessCategory.sobremesa.label, 'Sobremesas');
    });

    test('um slug desconhecido é ignorado, não rebenta', () {
      final estranha = _loja(
        id: 'x',
        nome: 'X',
        categoria: 'restaurant',
        extras: ['categoria-que-nao-existe', 'sobremesa'],
      );
      expect(estranha.extraCategories, {BusinessCategory.sobremesa});
    });

    test('a categoria principal nunca se duplica nas extras', () {
      final repetida = _loja(
        id: 'y',
        nome: 'Y',
        categoria: 'sobremesa',
        extras: ['sobremesa'],
      );
      expect(repetida.extraCategories, isEmpty);
      expect(repetida.belongsTo(BusinessCategory.sobremesa), isTrue);
    });
  });
}
