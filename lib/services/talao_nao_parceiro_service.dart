// Bloco C (2026-09-05) — talão obrigatório em TODOS os não-parceiros.
//
// Cicatriz: o pedido 29c1043a (Burger King, cliente Letícia, 05/09) foi
// entregue com `is_purchase_finalized = true` mas `final_purchase_value` a
// NULL e zero linhas em `order_receipts_v2` — porque o comprovativo estava
// preso a `service_type = 'storeShopping'`. Passa a decidir-se pelo parceiro.
//
// Porque é um serviço à parte e não um método do `OrderStore`:
//   1. `OrderStore` é zona protegida (contém `finalizePurchase`);
//   2. a RPC dos mercados não serve aqui — recusa `service_type != storeShopping`
//      e cobra o saco a €0,10 (regra de supermercado) em vez dos €0,30 do
//      restaurante, o que mudaria o valor cobrado ao cliente.
//
// Este serviço grava só o comprovativo. O dinheiro continua a correr pelo
// caminho já validado (`finalizePurchase` → `PricingService`), intocado.

import 'package:supabase_flutter/supabase_flutter.dart';

class TalaoNaoParceiroService {
  /// Grava o talão de um pedido de loja não-parceira.
  ///
  /// Devolve `null` em sucesso, ou a mensagem PT-PT a mostrar ao estafeta.
  static Future<String?> registar({
    required String orderId,
    required String photoStoragePath,
    required int driverTypedTotalCents,
  }) async {
    try {
      await Supabase.instance.client.rpc(
        'registar_talao_nao_parceiro',
        params: <String, dynamic>{
          'p_order_id': orderId,
          'p_receipt_photo_url': photoStoragePath,
          'p_driver_typed_total_cents': driverTypedTotalCents,
        },
      );
      return null;
    } catch (e) {
      final texto = e.toString();
      if (texto.contains('NOT_ASSIGNED_DRIVER')) {
        return 'Este pedido não está atribuído a si.';
      }
      if (texto.contains('PARTNER_STORE_NO_RECEIPT')) {
        return 'Lojas parceiras não pedem talão.';
      }
      if (texto.contains('INVALID_TOTAL')) {
        return 'Valor do talão inválido. Confirme o total do talão.';
      }
      if (texto.contains('ORDER_NOT_FOUND')) {
        return 'Pedido não encontrado. Actualize a app.';
      }
      if (texto.contains('UNAUTHENTICATED')) {
        return 'Sessão expirada. Inicie sessão de novo.';
      }
      return 'Não foi possível guardar o talão. Tente de novo.';
    }
  }
}
