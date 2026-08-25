// CORREÇÃO 1 (2026-08-25, caso real Continente) — guarda de idempotência do
// "concluir a ida ao mercado".
//
// Caso real (entrega do Continente, 2026-08-25): o ecrã gravou a MESMA lista
// de 6 linhas DUAS vezes (18:03:12 e 18:03:38) e a Edge Function
// `notify-purchase-finalized` correu duas vezes — a cliente viu tudo
// repetido na app dela. A RPC `finalize_storeshopping_purchase_v2` não tem
// guarda de "já finalizado" (a v1 tem), portanto quem chama tem de a ter.
//
// Esta classe LÊ o estado real no servidor (nunca escreve). Serve para duas
// decisões do ecrã do estafeta:
//   1. antes de gravar   → se a lista e o talão já lá estão, não volta a
//      gravar nem a notificar: só avança;
//   2. depois de um erro → se a lista e o talão ficaram lá na mesma (erro a
//      seguir à escrita, ou barreira anti-duplicado do banco a recusar a
//      segunda escrita), avança em vez de mandar o estafeta repetir tudo.
//
// O estafeta tem política RLS `driver_rw_assigned_items` /
// `driver_rw_own_receipt` nas duas tabelas, portanto esta leitura funciona
// com a sessão dele. Read-only: nenhum campo de dinheiro é tocado.

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class StoreShoppingRecordState {
  const StoreShoppingRecordState({
    required this.known,
    required this.itemsCount,
    required this.hasReceipt,
  });

  /// false quando não foi possível ler o servidor (offline, RLS, timeout).
  /// Na dúvida NÃO se assume nada — o ecrã segue o caminho normal.
  final bool known;
  final int itemsCount;
  final bool hasReceipt;

  /// A ida ao mercado já está registada ponta-a-ponta neste pedido.
  bool get alreadyRecorded => known && itemsCount > 0 && hasReceipt;

  static const unknown =
      StoreShoppingRecordState(known: false, itemsCount: 0, hasReceipt: false);
}

class StoreShoppingFinalizeGuard {
  /// Lê o que já existe no servidor para este pedido. Nunca lança.
  static Future<StoreShoppingRecordState> read(String orderId) async {
    final supabase = Supabase.instance.client;
    try {
      final items = await supabase
          .from('order_purchase_items_v2')
          .select('id')
          .eq('order_id', orderId)
          .limit(200);
      final receipt = await supabase
          .from('order_receipts_v2')
          .select('id')
          .eq('order_id', orderId)
          .maybeSingle();
      return StoreShoppingRecordState(
        known: true,
        itemsCount: (items as List).length,
        hasReceipt: receipt != null,
      );
    } catch (e) {
      debugPrint('[bora-compra] guarda de idempotência não conseguiu ler: $e');
      return StoreShoppingRecordState.unknown;
    }
  }
}
