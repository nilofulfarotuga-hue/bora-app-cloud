import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Regra de preço das lojas parceiras (decisão do Danilo, 2026-09-14).
///
/// O parceiro escreve o preço de balcão — o que ele quer receber. A app é
/// que soma a comissão por cima, sozinha; o parceiro nunca faz contas.
///
///   products.partner_shelf_price = o que o parceiro escreveu (balcão)
///   products.price = round(balcão ÷ (1 − comissão_visível) × (1 + markup_oculto), 2)
///
/// É o espelho exacto, lido ao contrário, de
/// `public.partner_store_share(p_subtotal, p_restaurant_id)` — a função do
/// servidor que diz quanto o parceiro recebe:
///   • loja com `restaurants.app_markup_pct` > 0 ("comissão paga pelo
///     cliente", ex.: Leonidas +10 %): price = round(balcão × (1 + pct), 2);
///   • qualquer outra loja parceira: a fórmula da plataforma acima.
///
/// As percentagens vêm SEMPRE de `platform_settings`
/// (`partner_visible_commission_pct`, `partner_hidden_markup_pct`). Nunca se
/// escreve 0,90 nem 1,05 à mão: se o Danilo mudar a percentagem, tudo
/// acompanha. Com os valores de hoje (0,10 e 0,05) dá balcão × 1,1667 —
/// etiqueta 8,00 € → o cliente vê 9,33 € → o parceiro recebe 8,00 € certinho.
///
/// Só vale para lojas parceiras (`restaurants.is_partner = true`). As
/// não-parceiras têm outra regra e não passam por aqui.
class PartnerPriceRules {
  const PartnerPriceRules({
    required this.visibleCommissionPct,
    required this.hiddenMarkupPct,
    this.appMarkupPct,
  });

  /// `platform_settings.partner_visible_commission_pct` (0,10 = 10 %).
  final double visibleCommissionPct;

  /// `platform_settings.partner_hidden_markup_pct` (0,05 = 5 %).
  final double hiddenMarkupPct;

  /// `restaurants.app_markup_pct` desta loja; null ou 0 = fórmula da plataforma.
  final double? appMarkupPct;

  static const String kVisibleCommissionKey = 'partner_visible_commission_pct';
  static const String kHiddenMarkupKey = 'partner_hidden_markup_pct';

  /// `true` quando a loja tem a sua própria percentagem por cima do balcão.
  bool get usesStoreMarkup => (appMarkupPct ?? 0) > 0;

  /// Preço que o cliente vê, a partir do balcão que o parceiro escreveu.
  double appPriceFromShelf(double shelfPrice) {
    if (usesStoreMarkup) {
      return _round2(shelfPrice * (1 + appMarkupPct!));
    }
    return _round2(
        shelfPrice / (1 - visibleCommissionPct) * (1 + hiddenMarkupPct));
  }

  /// Balcão (o que o parceiro recebe) a partir do preço que o cliente vê.
  /// É `partner_store_share(price, restaurant_id)` em Dart.
  double shelfFromAppPrice(double appPrice) {
    if (usesStoreMarkup) {
      return _round2(appPrice / (1 + appMarkupPct!));
    }
    return _round2(
        appPrice * (1 - visibleCommissionPct) / (1 + hiddenMarkupPct));
  }

  /// A mesma regra da plataforma, aplicada a outra loja.
  PartnerPriceRules forStore(double? storeAppMarkupPct) => PartnerPriceRules(
        visibleCommissionPct: visibleCommissionPct,
        hiddenMarkupPct: hiddenMarkupPct,
        appMarkupPct: storeAppMarkupPct,
      );

  /// Constrói a regra a partir das linhas `key → value` de `platform_settings`.
  /// Devolve null se faltar uma das duas chaves — nunca se adivinha uma
  /// percentagem.
  static PartnerPriceRules? fromSettings(
    Map<String, dynamic> settings, {
    double? appMarkupPct,
  }) {
    final visible = _asPct(settings[kVisibleCommissionKey]);
    final hidden = _asPct(settings[kHiddenMarkupKey]);
    if (visible == null || hidden == null) return null;
    if (visible >= 1) return null; // dividir por zero/negativo: definição inválida
    return PartnerPriceRules(
      visibleCommissionPct: visible,
      hiddenMarkupPct: hidden,
      appMarkupPct: appMarkupPct,
    );
  }

  /// Lê as duas percentagens do servidor (2 linhas). Devolve null quando não
  /// for possível — sem sessão, sem rede, chave apagada — e quem chama decide
  /// não gravar em vez de gravar um preço errado.
  static Future<PartnerPriceRules?> load({double? appMarkupPct}) async {
    try {
      final rows = await Supabase.instance.client
          .from('platform_settings')
          .select('key, value')
          .inFilter('key', const [kVisibleCommissionKey, kHiddenMarkupKey]);
      final settings = <String, dynamic>{
        for (final row in (rows as List).cast<Map<String, dynamic>>())
          row['key'] as String: row['value'],
      };
      final rules = fromSettings(settings, appMarkupPct: appMarkupPct);
      if (rules == null) {
        debugPrint('[PartnerPriceRules] chaves em falta em platform_settings: '
            '${settings.keys.toList()}');
      }
      return rules;
    } catch (e) {
      debugPrint('[PartnerPriceRules] falhou a ler as percentagens: $e');
      return null;
    }
  }

  static double? _asPct(dynamic raw) {
    if (raw == null) return null;
    final value = raw is num ? raw.toDouble() : double.tryParse('$raw');
    if (value == null || value < 0) return null;
    return value;
  }

  /// Arredonda a 2 casas como o `ROUND(numeric, 2)` do Postgres (meio para
  /// cima). O epsilon corrige o binário que fica um nada abaixo do meio
  /// cêntimo (9,345 a ler-se 9,3449999…).
  static double _round2(double value) {
    final epsilon = value >= 0 ? 1e-9 : -1e-9;
    return (value * 100 + epsilon).round() / 100;
  }
}

/// "8,00 €" — formato PT-PT para as linhas "Recebes" / "O cliente vê".
String formatEurPt(double value) =>
    '${value.toStringAsFixed(2).replaceAll('.', ',')} €';
