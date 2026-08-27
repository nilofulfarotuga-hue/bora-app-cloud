import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/order_service_type.dart';

/// TAXA DE PEDIDO PEQUENO (2026-08-27).
///
/// Vale para TODAS as lojas e todas as categorias de ENTREGA: quando o
/// subtotal de produtos fica abaixo do mínimo, o cliente paga uma taxa, em
/// linha própria e visível.
///
/// **Os valores nunca estão no código.** Vêm de `platform_settings`
/// (`min_order_cents`, `small_order_fee_cents`, `small_order_fee_enabled`) e,
/// quando a loja tem acordo próprio, das colunas de override em `restaurants`.
/// A regra aqui é o espelho exacto da função `small_order_fee_calc` do
/// servidor — mudar uma obriga a mudar a outra, senão cliente e servidor
/// deixam de bater ao cêntimo.
@immutable
class SmallOrderFeeConfig {
  const SmallOrderFeeConfig({
    required this.enabled,
    required this.minCents,
    required this.feeCents,
  });

  /// Estado seguro: nada é cobrado e nada é mostrado.
  static const desligado =
      SmallOrderFeeConfig(enabled: false, minCents: 0, feeCents: 0);

  final bool enabled;
  final int minCents;
  final int feeCents;

  bool get _ativa => enabled && minCents > 0 && feeCents > 0;

  double get minEur => minCents / 100;
  double get feeEur => feeCents / 100;

  /// Só as categorias de entrega com subtotal de produtos.
  static bool _cobreServico(OrderServiceType t) =>
      t == OrderServiceType.restaurant || t == OrderServiceType.storeShopping;

  /// A taxa a cobrar por este subtotal, em euros. 0 quando não se aplica.
  double taxaPara(OrderServiceType serviceType, double subtotal) {
    if (!_ativa || !_cobreServico(serviceType) || subtotal <= 0) return 0;
    if ((subtotal * 100).round() >= minCents) return 0;
    return feeEur;
  }

  /// Quanto falta para deixar de pagar a taxa, em euros. 0 quando já não paga.
  /// É isto que a Uber e a Glovo mostram no carrinho — e é o que faz o ticket
  /// subir em vez de o cliente desistir.
  double faltaPara(OrderServiceType serviceType, double subtotal) {
    if (taxaPara(serviceType, subtotal) <= 0) return 0;
    return (minCents - (subtotal * 100).round()) / 100;
  }
}

/// Lê a configuração da taxa do servidor e guarda-a em memória.
///
/// Uma leitura por sessão para o global, mais uma por loja visitada. Sem
/// configuração lida (offline, erro), fica no estado seguro: taxa nenhuma.
class SmallOrderFeeService {
  SmallOrderFeeService._();

  static SmallOrderFeeConfig _global = SmallOrderFeeConfig.desligado;
  static final Map<String, SmallOrderFeeConfig> _porLoja = {};
  static bool _globalCarregado = false;

  static SmallOrderFeeConfig get global => _global;

  /// Configuração em vigor para uma loja: o override dela, se existir; senão
  /// o valor global.
  static SmallOrderFeeConfig para(String? restaurantId) {
    if (restaurantId == null) return _global;
    return _porLoja[restaurantId] ?? _global;
  }

  /// Lê as três chaves globais. Idempotente — repetir não custa nada.
  static Future<void> carregarGlobal({bool forcar = false}) async {
    if (_globalCarregado && !forcar) return;
    try {
      final linhas = await Supabase.instance.client
          .from('platform_settings')
          .select('key, value')
          .inFilter('key', const [
        'min_order_cents',
        'small_order_fee_cents',
        'small_order_fee_enabled',
      ]);

      final valores = <String, dynamic>{
        for (final l in (linhas as List).cast<Map<String, dynamic>>())
          l['key'] as String: l['value'],
      };

      _global = SmallOrderFeeConfig(
        enabled: _comoBool(valores['small_order_fee_enabled']),
        minCents: _comoInt(valores['min_order_cents']),
        feeCents: _comoInt(valores['small_order_fee_cents']),
      );
      _globalCarregado = true;
      debugPrint('[SmallOrderFee] global: enabled=${_global.enabled} '
          'min=${_global.minCents} fee=${_global.feeCents}');
    } catch (e) {
      // Estado seguro: sem leitura, não se inventa taxa nenhuma.
      debugPrint('[SmallOrderFee] falhou a ler as definições globais: $e');
    }
  }

  /// Lê o override desta loja. `null` nas colunas = herda o global.
  static Future<void> carregarLoja(String restaurantId) async {
    await carregarGlobal();
    if (_porLoja.containsKey(restaurantId)) return;
    try {
      final linha = await Supabase.instance.client
          .from('restaurants')
          .select('min_order_cents_override, small_order_fee_cents_override')
          .eq('id', restaurantId)
          .maybeSingle();
      if (linha == null) return;
      final min = (linha['min_order_cents_override'] as num?)?.toInt();
      final fee = (linha['small_order_fee_cents_override'] as num?)?.toInt();
      if (min == null && fee == null) return; // herda o global
      _porLoja[restaurantId] = SmallOrderFeeConfig(
        enabled: _global.enabled,
        minCents: min ?? _global.minCents,
        feeCents: fee ?? _global.feeCents,
      );
      debugPrint('[SmallOrderFee] override $restaurantId: '
          'min=${_porLoja[restaurantId]!.minCents} '
          'fee=${_porLoja[restaurantId]!.feeCents}');
    } catch (e) {
      debugPrint('[SmallOrderFee] falhou a ler o override de $restaurantId: $e');
    }
  }

  /// Usado pelo painel admin depois de gravar, para a app não ficar a mostrar
  /// o valor antigo.
  static void esquecerCache() {
    _globalCarregado = false;
    _porLoja.clear();
  }

  static int _comoInt(dynamic v) {
    if (v is num) return v.toInt();
    return int.tryParse('$v') ?? 0;
  }

  static bool _comoBool(dynamic v) {
    if (v is bool) return v;
    return '$v'.toLowerCase() == 'true';
  }
}
