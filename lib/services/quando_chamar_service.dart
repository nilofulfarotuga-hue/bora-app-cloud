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

/// A razão, em palavras da loja, de o servidor recusar o aceitar com hora
/// (" Motivo." com espaço à frente, ou vazio se não se sabe).
String motivoAceitarComHora(String? erro) => switch (erro) {
      'invalid_pronto_em' => ' A hora tem de ser daqui a pouco e no máximo a 14 dias.',
      'so_lojas_nao_comida' => ' Esta loja só pode escolher minutos.',
      'funcao_desligada' => ' Esta opção está desligada. Escolhe minutos.',
      'invalid_status' || 'concurrent_transition' =>
        ' O pedido já mudou de estado. Atualiza a lista.',
      _ => '',
    };
