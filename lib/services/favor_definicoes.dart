import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../utils/favor_passos.dart' show kMaxSacosPelletsPorFavor;

/// Valores do Favor que aparecem em texto ao cliente (08/10/2026): quanto
/// custa a paragem em casa e até quanto o estafeta adianta numa compra.
///
/// A verdade é `platform_settings` — as MESMAS chaves que o servidor usa:
///  - `errand_home_stop_fee_cents` (`pricing_calculate_errand`, hoje 200);
///  - `errand_max_advance_cents` (`create_order`, hoje 4000);
///  - `favor_pellets_max_sacos` (limite só da app, 20/10/2026, hoje 2).
/// Sem leitura (sem rede), ficam os valores de recurso iguais aos de hoje.
/// Nunca lança. Mesmo molde do `LimiteDinheiroService`.
class FavorDefinicoes {
  FavorDefinicoes._();

  static int _paragemCasaCents = 200;
  static int _adiantamentoMaxCents = 4000;
  static int _pelletsMaxSacos = kMaxSacosPelletsPorFavor;
  static bool _carregado = false;

  static int get paragemCasaCents => _paragemCasaCents;
  static int get adiantamentoMaxCents => _adiantamentoMaxCents;

  /// Máximo de sacos de pellets por Favor (painel admin → Configurações,
  /// `favor_pellets_max_sacos`). Sem leitura: 2.
  static int get pelletsMaxSacos => _pelletsMaxSacos;

  /// "2 €" / "2,50 €".
  static String get paragemCasaTexto => _euros(_paragemCasaCents);

  /// "40 €".
  static String get adiantamentoMaxTexto => _euros(_adiantamentoMaxCents);

  static Future<void> carregar({bool forcar = false}) async {
    if (_carregado && !forcar) return;
    try {
      final linhas = await Supabase.instance.client
          .from('platform_settings')
          .select('key, value')
          .inFilter('key', [
            'errand_home_stop_fee_cents',
            'errand_max_advance_cents',
            'favor_pellets_max_sacos',
          ]);
      final lista = (linhas as List).cast<Map<String, dynamic>>();
      for (final l in lista) {
        final v = l['value'];
        final n = v is num ? v : num.tryParse('$v'.replaceAll('"', ''));
        if (n == null || n.isNaN || n < 0) continue;
        if (l['key'] == 'errand_home_stop_fee_cents') {
          _paragemCasaCents = n.round();
        } else if (l['key'] == 'errand_max_advance_cents' && n > 0) {
          _adiantamentoMaxCents = n.round();
        } else if (l['key'] == 'favor_pellets_max_sacos' && n >= 1) {
          _pelletsMaxSacos = n.round();
        }
      }
      if (lista.isNotEmpty) _carregado = true;
    } catch (e) {
      debugPrint('[FavorDefinicoes] falhou a ler: $e');
    }
  }

  static String _euros(int cents) {
    final eur = cents / 100.0;
    final s = eur == eur.roundToDouble()
        ? eur.toStringAsFixed(0)
        : eur.toStringAsFixed(2).replaceAll('.', ',');
    return '$s €';
  }

  @visibleForTesting
  static void definirParaTeste(
      {int? paragemCasaCents, int? adiantamentoMaxCents, int? pelletsMaxSacos}) {
    if (paragemCasaCents != null) _paragemCasaCents = paragemCasaCents;
    if (adiantamentoMaxCents != null) _adiantamentoMaxCents = adiantamentoMaxCents;
    if (pelletsMaxSacos != null) _pelletsMaxSacos = pelletsMaxSacos;
    _carregado = true;
  }
}
