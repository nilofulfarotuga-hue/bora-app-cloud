import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../config/business_rules.dart' show BRBusiness;

/// LIMITE DO PAGAMENTO EM DINHEIRO — uma só fonte (04/10/2026).
///
/// A verdade é `platform_settings.max_cash_amount_cents` (hoje 4000 = 40 €).
/// O gatilho `enforce_cash_payment_limit` no servidor lê a MESMA chave desde
/// 04/10 (antes tinha `> 40` escrito à mão), e a app lê-a aqui. Mudar o limite
/// = mudar a chave no painel admin; nenhum dos lados tem o número cravado.
///
/// "Ir buscar" (takeaway, "Pagar na loja") não tem limite: não há estafeta a
/// transportar o dinheiro — o servidor isenta-o pela mesma regra.
///
/// Sem leitura (sem rede/sessão) fica o valor de recurso
/// [BRBusiness.CASH_MAX_ORDER_VALUE_EUR], igual ao do servidor hoje. Nunca
/// lança; uma lista vazia (RLS sem sessão) não conta como carregado.
class LimiteDinheiroService {
  LimiteDinheiroService._();

  static const String kChave = 'max_cash_amount_cents';

  static int _maxCents = (BRBusiness.CASH_MAX_ORDER_VALUE_EUR * 100).round();
  static bool _carregado = false;

  /// Limite em cêntimos (lido do servidor ou o de recurso).
  static int get maxCents => _maxCents;

  /// Limite em euros.
  static double get maxEur => _maxCents / 100.0;

  /// `true` quando o valor veio mesmo do servidor. Só para diagnóstico.
  static bool get carregadoDoServidor => _carregado;

  /// Texto curto para o cliente: "40 €" / "37,50 €".
  static String get maxTexto {
    final eur = maxEur;
    final s = eur == eur.roundToDouble()
        ? eur.toStringAsFixed(0)
        : eur.toStringAsFixed(2).replaceAll('.', ',');
    return '$s €';
  }

  /// O total passa o limite? (ao cêntimo, como o gatilho do servidor)
  static bool passaLimite(double totalEur) =>
      (totalEur * 100).round() > _maxCents;

  /// Lê a chave. Idempotente. Nunca lança.
  static Future<void> carregar({bool forcar = false}) async {
    if (_carregado && !forcar) return;
    try {
      final linhas = await Supabase.instance.client
          .from('platform_settings')
          .select('key, value')
          .eq('key', kChave);
      final lista = (linhas as List).cast<Map<String, dynamic>>();
      if (lista.isEmpty) return;
      final v = lista.first['value'];
      final n = v is num ? v : num.tryParse('$v'.replaceAll('"', ''));
      if (n == null || n.isNaN || n <= 0) return;
      _maxCents = n.round();
      _carregado = true;
    } catch (e) {
      debugPrint('[LimiteDinheiro] falhou a ler $kChave: $e');
    }
  }

  /// Só para testes.
  @visibleForTesting
  static void definirParaTeste(int cents) {
    _maxCents = cents;
    _carregado = true;
  }
}
