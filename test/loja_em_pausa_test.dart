import 'package:bora_app/models/restaurant_model.dart';
import 'package:bora_app/stores/favorite_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// LOJA EM PAUSA (04/10/2026) — `restaurants.pausa_ate`.
///
/// O parceiro carrega em "pausa": até à hora marcada a loja aparece como
/// "Fechada temporariamente — volta às HH:MM" e não se mete no carrinho
/// (o carrinho trava pelo `isOpenNow()`, o mesmo de fora de horário).
RestaurantModel _loja({DateTime? pausaAte}) => RestaurantModel(
      id: 'loja-1',
      name: 'Loja Teste',
      phone: '',
      address: '',
      email: '',
      photoUrl: '',
      cuisineType: '',
      isPartner: true,
      category: BusinessCategory.restaurant,
      // Sem horário definido = sempre aberta (DayHours por omissão).
      pausaAte: pausaAte,
    );

void main() {
  group('pausa do parceiro', () {
    test('sem pausa, a loja segue o horário normal', () {
      final l = _loja();
      expect(l.emPausa(), isFalse);
      expect(l.statusLabel().contains('temporariamente'), isFalse);
    });

    test('pausa a correr: fechada, com a hora de volta', () {
      final agora = DateTime.utc(2026, 1, 15, 12, 0); // inverno: Lisboa = UTC
      final l = _loja(pausaAte: DateTime.utc(2026, 1, 15, 12, 45));
      expect(l.emPausa(agora), isTrue);
      expect(l.isOpenNow(agora), isFalse);
      expect(l.pausaVoltaAs, '12:45');
      expect(l.statusLabel(agora),
          'Fechada temporariamente — volta às 12:45');
    });

    test('pausa que já acabou não fecha a loja', () {
      final agora = DateTime.utc(2026, 1, 15, 13, 0);
      final l = _loja(pausaAte: DateTime.utc(2026, 1, 15, 12, 45));
      expect(l.emPausa(agora), isFalse);
    });

    test('a hora de volta é a de Lisboa (verão = UTC+1)', () {
      final l = _loja(pausaAte: DateTime.utc(2026, 7, 10, 18, 30));
      expect(l.pausaVoltaAs, '19:30');
    });

    test('lê a coluna de forma tolerante', () {
      expect(RestaurantModel.parsePausaAte(null), isNull);
      expect(RestaurantModel.parsePausaAte('lixo'), isNull);
      expect(RestaurantModel.parsePausaAte('2026-10-04T18:00:00+00:00'),
          DateTime.utc(2026, 10, 4, 18));
    });

    test('copyWith não perde a pausa', () {
      final ate = DateTime.utc(2030, 1, 1);
      expect(_loja(pausaAte: ate).copyWith(name: 'Outra').pausaAte, ate);
    });
  });

  group('favoritos guardados pelo id da loja', () {
    setUp(() => SharedPreferences.setMockInitialValues({}));

    test('a chave é o id, não o nome', () {
      expect(FavoriteStore.storeKey('abc-123'), 'store_abc-123');
    });

    test('migra os favoritos antigos (por nome) para o id', () async {
      SharedPreferences.setMockInitialValues({
        'bora_favorites_v1': ['restaurant_Pizzaria X', 'produto-9'],
      });
      final f = FavoriteStore();
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(f.legacyStoreNames, ['Pizzaria X']);

      f.migrateLegacyStores({'Pizzaria X': 'id-42'});

      expect(f.isFavoriteStore('id-42'), isTrue);
      expect(f.legacyStoreNames, isEmpty);
      expect(f.favoriteStoreIds, ['id-42']);
      // Favoritos de produto não mexem.
      expect(f.isFavorite('produto-9'), isTrue);
    });
  });
}
