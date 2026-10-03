// Regra de preço das lojas parceiras (missão parceiro-edita-preco, 2026-09-14).
//
// O parceiro escreve o balcão; a app soma a comissão por cima. Aqui prova-se a
// fórmula nos DOIS sentidos — balcão → preço do app → de volta ao balcão — com
// as percentagens a virem de um mapa igual ao que `platform_settings` devolve,
// e nunca cravadas: o mesmo código tem de acompanhar outra percentagem.
//
// Espelho de `public.partner_store_share(p_subtotal, p_restaurant_id)`:
//   share(price) = round(price × (1 − visível) ÷ (1 + oculto), 2)
//   ou, com restaurants.app_markup_pct > 0: round(price ÷ (1 + pct), 2).

import 'package:bora_app/services/partner_price_rules.dart';
import 'package:flutter_test/flutter_test.dart';

/// As linhas `key → value` tal como chegam de `platform_settings`.
Map<String, dynamic> settings({required Object visible, required Object hidden}) => {
      PartnerPriceRules.kVisibleCommissionKey: visible,
      PartnerPriceRules.kHiddenMarkupKey: hidden,
    };

/// O que o servidor faz: ROUND(numeric, 2) a partir de cêntimos exactos.
double round2(double v) => (v * 100 + (v >= 0 ? 1e-9 : -1e-9)).round() / 100;

void main() {
  group('PartnerPriceRules.fromSettings', () {
    test('lê as duas chaves e não adivinha quando falta uma', () {
      final ok = PartnerPriceRules.fromSettings(
          settings(visible: 0.10, hidden: 0.05));
      expect(ok, isNotNull);
      expect(ok!.visibleCommissionPct, 0.10);
      expect(ok.hiddenMarkupPct, 0.05);

      expect(
        PartnerPriceRules.fromSettings(
            {PartnerPriceRules.kVisibleCommissionKey: 0.10}),
        isNull,
        reason: 'sem markup oculto não há regra',
      );
      expect(PartnerPriceRules.fromSettings({}), isNull);
      // Valor jsonb pode chegar como texto — também se aceita.
      expect(
        PartnerPriceRules.fromSettings(
            {...settings(visible: '0.10', hidden: '0.05')})!.hiddenMarkupPct,
        0.05,
      );
    });
  });

  group('fórmula da plataforma (valores de hoje: 10 % visível, 5 % oculto)', () {
    final rules =
        PartnerPriceRules.fromSettings(settings(visible: 0.10, hidden: 0.05))!;

    test('exemplo real gravado: etiqueta 8,00 € → o cliente vê 9,33 €', () {
      expect(rules.appPriceFromShelf(8.00), 9.33);
      expect(rules.shelfFromAppPrice(9.33), 8.00,
          reason: 'o parceiro recebe 8,00 € certinho');
    });

    test('Goola: balcão 7,90 € → 9,22 € → 7,90 €', () {
      expect(rules.appPriceFromShelf(7.90), 9.22);
      expect(rules.shelfFromAppPrice(9.22), 7.90);
    });

    test('balcão → app → balcão fecha ao cêntimo para todos os preços '
        'de 0,01 € a 200,00 €', () {
      for (var cents = 1; cents <= 20000; cents++) {
        final shelf = cents / 100;
        final app = rules.appPriceFromShelf(shelf);
        // Abaixo de 3 cêntimos a comissão não chega a meio cêntimo e o
        // arredondamento devolve o mesmo valor (0,0117 → 0,01); a partir daí
        // o preço do cliente fica sempre por cima do balcão.
        expect(app, cents < 3 ? equals(shelf) : greaterThan(shelf),
            reason: 'a comissão soma-se por cima ($shelf)');
        expect(rules.shelfFromAppPrice(app), shelf,
            reason: 'balcão $shelf → app $app tem de voltar ao balcão');
      }
    });

    test('app → balcão → app é coerente pela leitura do servidor', () {
      // Quando o admin escreve o preço do app, o balcão derivado tem de ser
      // exactamente o que partner_store_share(price) devolve — e o preço do
      // app recomposto a partir desse balcão dá o mesmo balcão outra vez.
      for (var cents = 1; cents <= 20000; cents++) {
        final app = cents / 100;
        final shelf = rules.shelfFromAppPrice(app);
        final share = round2(app *
            (1 - rules.visibleCommissionPct) /
            (1 + rules.hiddenMarkupPct));
        expect(shelf, share, reason: 'partner_store_share($app)');
        expect(rules.shelfFromAppPrice(rules.appPriceFromShelf(shelf)), shelf);
      }
    });
  });

  group('as percentagens vêm das definições, não do código', () {
    test('com 12 % visível e 3 % oculto a fórmula acompanha', () {
      final rules =
          PartnerPriceRules.fromSettings(settings(visible: 0.12, hidden: 0.03))!;
      // 8,00 ÷ 0,88 × 1,03 = 9,3636… → 9,36
      expect(rules.appPriceFromShelf(8.00), 9.36);
      expect(rules.shelfFromAppPrice(9.36), 8.00);
      expect(rules.appPriceFromShelf(8.00),
          isNot(PartnerPriceRules.fromSettings(settings(visible: 0.10, hidden: 0.05))!
              .appPriceFromShelf(8.00)),
          reason: 'mudar a percentagem tem de mudar o preço');
    });

    test('com 0 % e 0 % o cliente vê exactamente o balcão', () {
      final rules =
          PartnerPriceRules.fromSettings(settings(visible: 0, hidden: 0))!;
      expect(rules.appPriceFromShelf(8.00), 8.00);
      expect(rules.shelfFromAppPrice(8.00), 8.00);
    });
  });

  group('loja com app_markup_pct ("comissão paga pelo cliente")', () {
    test('Leonidas: balcão 14,95 € + 10 % → 16,45 € → 14,95 €', () {
      final rules = PartnerPriceRules.fromSettings(
        settings(visible: 0.10, hidden: 0.05),
        appMarkupPct: 0.10,
      )!;
      expect(rules.usesStoreMarkup, isTrue);
      expect(rules.appPriceFromShelf(14.95), 16.45);
      expect(rules.shelfFromAppPrice(16.45), 14.95);
    });

    test('app_markup_pct nulo ou 0 cai na fórmula da plataforma', () {
      final base =
          PartnerPriceRules.fromSettings(settings(visible: 0.10, hidden: 0.05))!;
      expect(base.forStore(null).appPriceFromShelf(8.00), 9.33);
      expect(base.forStore(0).appPriceFromShelf(8.00), 9.33);
      expect(base.forStore(0.15).appPriceFromShelf(8.00), 9.20,
          reason: 'Mr Kebab: balcão + 15 %');
    });

    test('ida e volta fecha ao cêntimo também com markup da loja', () {
      final rules = PartnerPriceRules.fromSettings(
        settings(visible: 0.10, hidden: 0.05),
        appMarkupPct: 0.10,
      )!;
      for (var cents = 1; cents <= 20000; cents++) {
        final shelf = cents / 100;
        expect(rules.shelfFromAppPrice(rules.appPriceFromShelf(shelf)), shelf);
      }
    });
  });

  test('formatEurPt escreve à portuguesa', () {
    expect(formatEurPt(8), '8,00 €');
    expect(formatEurPt(9.33), '9,33 €');
    expect(formatEurPt(1234.5), '1234,50 €');
  });
}
