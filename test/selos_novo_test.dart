// Selo "Novo" nos atalhos da página inicial (17/11/2026).
import 'package:flutter_test/flutter_test.dart';

import 'package:bora_app/utils/selos_novo.dart';

void main() {
  group('chaveAtalho', () {
    test('os rótulos da página inicial dão as chaves do painel', () {
      // Rótulos tal como estão em client_home_screen.dart (_buildCategoryGrid).
      const rotulos = {
        'Restaurantes': 'restaurantes',
        'Supermercados': 'supermercados',
        'Farmácia': 'farmacia',
        'Lojas': 'lojas',
        'Enviar\nEncomenda': 'enviar encomenda',
        'Levar\nCompras': 'levar compras',
        'Favores': 'favores',
        'Reservar\nMesa': 'reservar mesa',
        'Beleza': 'beleza',
        'Limpeza': 'limpeza',
        'Festas': 'festas',
        'Sobremesas': 'sobremesas',
        'Lavagem Auto': 'lavagem auto',
        'Loja Online': 'loja online',
        'Bora\nMotorista': 'bora motorista',
      };
      rotulos.forEach((rotulo, chave) {
        expect(chaveAtalho(rotulo), chave, reason: rotulo);
        expect(kAtalhosHome.containsKey(chave), isTrue, reason: chave);
      });
      expect(chaveAtalho('Casa e\nManutenção'), 'casa e manutencao');
    });

    test('as chaves do painel não mudam ao passar pela própria função', () {
      for (final k in kAtalhosHome.keys) {
        expect(chaveAtalho(k), k);
      }
    });
  });

  group('lerSelosNovo', () {
    test('mapa, texto JSON e lixo', () {
      expect(lerSelosNovo({'farmacia': '2026-12-01'}),
          {'farmacia': '2026-12-01'});
      expect(lerSelosNovo('{"festas":"2026-11-30","lojas":""}'),
          {'festas': '2026-11-30'});
      expect(lerSelosNovo(null), isEmpty);
      expect(lerSelosNovo('não é json'), isEmpty);
      expect(lerSelosNovo(42), isEmpty);
    });
  });

  group('seloNovoNoAtalho', () {
    final selos = {'farmacia': '2026-12-01'};

    test('aparece até ao fim do dia marcado (Lisboa)', () {
      expect(seloNovoNoAtalho(selos, 'Farmácia', DateTime.utc(2026, 11, 17, 15)),
          isTrue);
      expect(seloNovoNoAtalho(selos, 'Farmácia', DateTime.utc(2026, 12, 1, 23)),
          isTrue);
      expect(seloNovoNoAtalho(selos, 'Farmácia', DateTime.utc(2026, 12, 2, 1)),
          isFalse);
    });

    test('atalho sem data não tem selo', () {
      expect(seloNovoNoAtalho(selos, 'Lojas', DateTime.utc(2026, 11, 17)),
          isFalse);
      expect(seloNovoNoAtalho(const {}, 'Farmácia', DateTime.utc(2026, 11, 17)),
          isFalse);
    });
  });
}
