import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// "Quando chamamos o estafeta?" (17/11/2026): aceitar um pedido de uma loja
/// que não é de comida com a HORA em que fica pronto (3 h, amanhã, 2 dias, dia
/// e hora — até 14 dias). O servidor (`partner_aceitar_pedido` com
/// `p_pronto_em`, migração 20261117130000) grava `ready_at_promised` e o
/// despacho chama o estafeta 8 min antes. Os minutos curtos continuam pelo
/// `OrderStore.restaurantAcceptOrder` de sempre.
///
/// Fica aqui e não no `OrderStore` porque esse ficheiro é zona vermelha
/// (`finalizePurchase`); isto não mexe em dinheiro.
Future<({bool ok, String? erro})> aceitarPedidoProntoEm(
  String orderId,
  DateTime prontoEm, {
  SupabaseClient? cliente,
}) async {
  try {
    final r = await (cliente ?? Supabase.instance.client)
        .rpc('partner_aceitar_pedido', params: {
      'p_order_id': orderId,
      'p_prep_minutes': null,
      'p_pronto_em': prontoEm.toUtc().toIso8601String(),
    });
    if (r is Map && r['ok'] == true) return (ok: true, erro: null);
    return (
      ok: false,
      erro: (r is Map ? r['error'] : null)?.toString() ?? 'resposta_invalida'
    );
  } catch (e) {
    debugPrint('[QuandoChamar] partner_aceitar_pedido: $e');
    return (ok: false, erro: e.toString());
  }
}
