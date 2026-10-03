// Talão do NÃO-PARCEIRO — uma só chamada ao servidor (2026-09-13).
//
// Cicatriz (10/09, McDonald's, dez tentativas; 09/09, Continente, só à
// terceira): o estafeta tirava a foto, escrevia o valor, carregava em confirmar
// e o ecrã voltava ao mesmo sítio sem dizer porquê. A app gravava o talão numa
// RPC e depois ia por um caminho antigo que escrevia colunas financeiras do
// pedido — o servidor recusava (imutabilidade financeira, 403) e o erro era
// engolido.
//
// Agora: a RPC `finalizar_talao_nao_parceiro` faz tudo no servidor (talão em
// `order_receipts_v2`, totais com o bypass financeiro por dentro, acerto do
// estafeta pelo talão, estado onTheWay). Vale para TODO o não-parceiro
// (mercado, restaurante, loja, farmácia) e TODOS os meios de pagamento. A app
// não escreve uma única coluna financeira. O erro real (código + texto) chega ao
// ecrã e fica registado em `order_lifecycle_errors`.
//
// Porque é um serviço à parte e não um método do `OrderStore`: o `OrderStore` é
// zona protegida (contém `finalizePurchase`) e não se toca sem ordem.

import 'dart:async';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/cart_item.dart';

class TalaoResultado {
  const TalaoResultado._({
    required this.ok,
    this.dados,
    this.codigo,
    this.mensagem,
  });

  factory TalaoResultado.sucesso(Map<String, dynamic> dados) =>
      TalaoResultado._(ok: true, dados: dados);

  factory TalaoResultado.erro(String codigo, String mensagem) =>
      TalaoResultado._(ok: false, codigo: codigo, mensagem: mensagem);

  final bool ok;

  /// Resposta do servidor em sucesso (status, cash_total_due_cents, ...).
  final Map<String, dynamic>? dados;

  /// Código em maiúsculas (ex.: NOT_ASSIGNED_DRIVER, INVALID_STATUS).
  final String? codigo;

  /// Texto PT-PT pronto para o ecrã. Inclui sempre o código.
  final String? mensagem;
}

class TalaoNaoParceiroService {
  static const rpcFinalizar = 'finalizar_talao_nao_parceiro';
  static const rpcErro = 'registar_erro_ciclo_pedido';
  static const componente = 'app.talao_nao_parceiro';

  /// Monta a lista de itens no formato que o servidor grava em
  /// `order_purchase_items_v2` (o mesmo que os mercados já usavam).
  static List<Map<String, dynamic>> montarItens(
    List<CartItem> items,
    List<Map<String, dynamic>> itemsAdded,
  ) {
    final payload = <Map<String, dynamic>>[];
    for (final it in items) {
      final statusV2 = it.purchaseStatus == 'unavailable'
          ? 'unavailable'
          : 'purchased'; // 'bought' e 'pending' contam como comprado
      payload.add({
        'original_item_id': it.productId,
        'original_name': it.name,
        'original_price_cents': (it.price * 100).round(),
        'original_qty': it.quantity,
        'status': statusV2,
      });
    }
    for (final added in itemsAdded) {
      payload.add({
        'original_name': (added['name'] as String?) ?? '',
        'original_price_cents': 0,
        'original_qty': (added['qty'] as int?) ?? 1,
        'status': 'added',
        'actual_name': (added['name'] as String?) ?? '',
        'actual_price_cents': (added['price_base_cents'] as int?) ?? 0,
        'actual_qty': (added['qty'] as int?) ?? 1,
      });
    }
    return payload;
  }

  /// Fecha a compra do não-parceiro: talão + valor + itens + sacos.
  /// Nunca lança: devolve [TalaoResultado] com o erro real quando falha.
  static Future<TalaoResultado> finalizar({
    required String orderId,
    required String photoStoragePath,
    required int driverTypedTotalCents,
    List<CartItem> items = const [],
    List<Map<String, dynamic>> itemsAdded = const [],
    int? bagCount,
  }) async {
    final params = <String, dynamic>{
      'p_order_id': orderId,
      'p_receipt_photo_url': photoStoragePath,
      'p_driver_typed_total_cents': driverTypedTotalCents,
      'p_items': montarItens(items, itemsAdded),
      if (bagCount != null) 'p_bag_count': bagCount,
    };
    try {
      final res = await Supabase.instance.client.rpc(rpcFinalizar, params: params);
      final map = res is Map ? Map<String, dynamic>.from(res) : <String, dynamic>{};
      if (map['ok'] == true) return TalaoResultado.sucesso(map);
      final codigo = (map['error'] ?? 'RESPOSTA_INVALIDA').toString();
      final r = TalaoResultado.erro(codigo, mensagemParaCodigo(codigo, map.toString()));
      unawaited(registarErro(orderId: orderId, erro: r.mensagem!, contexto: {
        'rpc': rpcFinalizar,
        'total_cents': driverTypedTotalCents,
        'resposta': map,
      }));
      return r;
    } catch (e) {
      final texto = e.toString();
      final codigo = extrairCodigo(texto);
      final r = TalaoResultado.erro(codigo, mensagemParaCodigo(codigo, texto));
      unawaited(registarErro(orderId: orderId, erro: texto, contexto: {
        'rpc': rpcFinalizar,
        'total_cents': driverTypedTotalCents,
        'codigo': codigo,
      }));
      return r;
    }
  }

  /// Primeiro token em MAIÚSCULAS_COM_UNDERSCORE da mensagem do servidor
  /// (ex.: "INVALID_STATUS: preparing" -> INVALID_STATUS).
  static String extrairCodigo(String texto) {
    final m = RegExp(r'\b([A-Z][A-Z0-9_]{3,})\b').firstMatch(texto);
    return m?.group(1) ?? 'ERRO_DESCONHECIDO';
  }

  static String mensagemParaCodigo(String codigo, String detalhe) {
    final base = switch (codigo) {
      'NOT_ASSIGNED_DRIVER' => 'Este pedido não está atribuído a si.',
      'PARTNER_STORE_NO_RECEIPT' => 'Lojas parceiras não pedem talão.',
      'INVALID_TOTAL' => 'Valor do talão inválido. Confirme o total do talão.',
      'INVALID_BAG_COUNT' => 'Número de sacos inválido (0 a 99).',
      'ORDER_NOT_FOUND' => 'Pedido não encontrado. Actualize a app.',
      'UNAUTHENTICATED' => 'Sessão expirada. Inicie sessão de novo.',
      'INVALID_STATUS' =>
        'O pedido já não está num estado que permita fechar a compra.',
      'WRONG_SERVICE_TYPE' => 'Este tipo de pedido não tem talão.',
      'RECEIPT_URL_REQUIRED' => 'Falta a foto do talão.',
      'FINANCIAL_COLUMNS_IMMUTABLE' =>
        'O servidor recusou alterar os valores do pedido.',
      _ => 'Não foi possível fechar o talão.',
    };
    final det = detalhe.length > 220 ? '${detalhe.substring(0, 220)}…' : detalhe;
    return '$base\nCódigo: $codigo\n$det';
  }

  /// Regista o erro em `order_lifecycle_errors` (fire-and-forget, nunca lança).
  static Future<void> registarErro({
    String? orderId,
    required String erro,
    Map<String, dynamic> contexto = const {},
  }) async {
    try {
      await Supabase.instance.client.rpc(rpcErro, params: <String, dynamic>{
        'p_order_id': orderId,
        'p_component': componente,
        'p_error_message': erro,
        'p_context': contexto,
      });
    } catch (_) {
      // O registo do erro nunca pode esconder o erro original.
    }
  }
}
