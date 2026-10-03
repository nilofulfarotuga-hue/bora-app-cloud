import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/order_edit.dart';

/// Loja PARCEIRA edita um pedido já feito (acrescentar / tirar produto).
///
/// Tudo o que é dinheiro é calculado e movido no SERVIDOR (`order_edit_quote`,
/// `partner_propose_order_edit`, `client_respond_order_edit`, Edge Function
/// `order-edit-settle`). A app só envia o que mudou e mostra o que o servidor
/// devolve — nunca calcula taxa, comissão nem markup (PADRAO 2.3).
///
/// Os botões só aparecem com `platform_settings.order_edit_enabled = true`.
class OrderEditService {
  OrderEditService._();
  static final instance = OrderEditService._();

  SupabaseClient get _db => Supabase.instance.client;

  bool? _ativo;
  DateTime? _lidoEm;

  /// Interruptor lido de `platform_settings` (cache de 2 minutos). Lista vazia
  /// (sem sessão) não conta como "desligado para sempre" — volta a tentar.
  Future<bool> ativo() async {
    final lido = _lidoEm;
    if (_ativo != null && lido != null && DateTime.now().difference(lido).inMinutes < 2) {
      return _ativo!;
    }
    try {
      final rows = await _db
          .from('platform_settings')
          .select('value')
          .eq('key', 'order_edit_enabled')
          .limit(1);
      final lista = (rows as List);
      if (lista.isEmpty) return false;
      final v = (lista.first as Map)['value'];
      _ativo = v == true || v == 'true';
      _lidoEm = DateTime.now();
      return _ativo!;
    } catch (e) {
      debugPrint('[OrderEditService] ativo(): $e');
      return false;
    }
  }

  /// Propostas do pedido, em tempo real (tabela na publicação supabase_realtime).
  Stream<List<OrderEditGrupo>> gruposDoPedido(String orderId) {
    return _db
        .from('order_edits')
        .stream(primaryKey: ['id'])
        .eq('order_id', orderId)
        .map((rows) => OrderEditGrupo.agrupar(
            rows.map((r) => OrderEditLinha.fromMap(r))));
  }

  /// Orçamento do servidor: totais antes/depois, sem mexer em nada.
  Future<Map<String, dynamic>> orcamento(
      String orderId, List<Map<String, dynamic>> alteracoes) async {
    final res = await _db.rpc('order_edit_quote', params: {
      'p_order_id': orderId,
      'p_alteracoes': alteracoes,
    });
    return (res as Map).cast<String, dynamic>();
  }

  /// Envia a alteração. Tirar aplica-se logo (e devolve o dinheiro);
  /// acrescentar fica à espera do cliente.
  Future<Map<String, dynamic>> propor(
      String orderId, List<Map<String, dynamic>> alteracoes) async {
    final res = await _db.rpc('partner_propose_order_edit', params: {
      'p_order_id': orderId,
      'p_alteracoes': alteracoes,
    });
    return (res as Map).cast<String, dynamic>();
  }

  /// Cliente aceita ou recusa. Se aceitou e o pedido é cartão/MB Way,
  /// devolve `precisa_pagamento: true` e a app chama [cobrarDiferenca].
  Future<Map<String, dynamic>> responder(String grupoId, bool aceitar) async {
    final res = await _db.rpc('client_respond_order_edit', params: {
      'p_grupo_id': grupoId,
      'p_aceitar': aceitar,
    });
    return (res as Map).cast<String, dynamic>();
  }

  /// Cobra a diferença (cartão guardado off-session, ou MB Way).
  /// Cartão com 3DS/recusa → `precisa_ecra: true` + `client_secret`.
  Future<Map<String, dynamic>> cobrarDiferenca(String grupoId) =>
      _settle({'action': 'charge', 'grupo_id': grupoId});

  /// Confirma o PI da diferença (depois da Payment Sheet ou do MB Way).
  Future<Map<String, dynamic>> confirmarPagamento(
          String grupoId, String paymentIntentId) =>
      _settle({
        'action': 'confirm',
        'grupo_id': grupoId,
        'payment_intent_id': paymentIntentId,
      });

  Future<Map<String, dynamic>> _settle(Map<String, dynamic> body) async {
    final res = await _db.functions.invoke('order-edit-settle', body: body);
    final data = res.data;
    if (data is Map) return data.cast<String, dynamic>();
    return {'ok': false, 'error': 'resposta_invalida'};
  }

  // ── Painel admin (PT-BR) ──────────────────────────────────────────────────

  Future<List<Map<String, dynamic>>> adminListar({
    String? restaurantId,
    String? estado,
    String? orderId,
    int limite = 300,
  }) async {
    final res = await _db.rpc('admin_list_order_edits', params: {
      'p_restaurant_id': restaurantId,
      'p_estado': estado,
      'p_order_id': orderId,
      'p_limit': limite,
    });
    return (res as List).cast<Map<String, dynamic>>();
  }

  Future<Map<String, dynamic>> adminCancelar(String grupoId, String motivo) async {
    final res = await _db.rpc('admin_cancel_order_edit',
        params: {'p_grupo_id': grupoId, 'p_motivo': motivo});
    return (res as Map).cast<String, dynamic>();
  }

  Future<Map<String, dynamic>> adminAprovar(String grupoId, String motivo) async {
    final res = await _db.rpc('admin_approve_order_edit',
        params: {'p_grupo_id': grupoId, 'p_motivo': motivo});
    return (res as Map).cast<String, dynamic>();
  }

  Future<Map<String, dynamic>> adminForcarEstorno(
      String grupoId, String motivo) async {
    final res = await _db.rpc('admin_force_refund_order_edit',
        params: {'p_grupo_id': grupoId, 'p_motivo': motivo});
    return (res as Map).cast<String, dynamic>();
  }
}

/// Erro do servidor → frase para a pessoa (PT-PT). O servidor lança códigos
/// em maiúsculas no início da mensagem (ex.: `LIMITE_DINHEIRO: ...`).
String mensagemErroEdicao(Object erro) {
  final s = erro is PostgrestException ? erro.message : erro.toString();
  if (s.contains('EDICAO_DESLIGADA')) return 'Esta função ainda não está ligada.';
  if (s.contains('NAO_E_A_TUA_LOJA')) return 'Este pedido não é da tua loja.';
  if (s.contains('JA_RECOLHIDO')) return 'O pedido já saiu da loja — já não dá para mudar.';
  if (s.contains('PAGAMENTO_POR_CONFIRMAR')) return 'O pagamento do pedido ainda não está confirmado.';
  if (s.contains('LIMITE_DINHEIRO')) return 'Pagamento em dinheiro só até 40 €. O total novo passava o limite.';
  if (s.contains('VALOR_MINIMO')) return 'A diferença a cobrar tem de ser pelo menos 0,50 €.';
  if (s.contains('JA_HA_PROPOSTA')) return 'Já há uma proposta à espera do cliente.';
  if (s.contains('PEDIDO_FICA_VAZIO')) return 'Não dá para tirar tudo. Para isso, rejeita/cancela o pedido.';
  if (s.contains('TIRA_MAIS_DO_QUE_HA')) return 'Estás a tirar mais unidades do que o cliente pediu.';
  if (s.contains('PRODUTO_INDISPONIVEL')) return 'Esse produto está marcado como indisponível.';
  if (s.contains('PRODUTO_NAO_E_DA_LOJA')) return 'Esse produto não é desta loja.';
  if (s.contains('MISTURA')) return 'Tirar e acrescentar vão em pedidos separados.';
  if (s.contains('NAO_E_O_TEU_PEDIDO')) return 'Este pedido não é teu.';
  if (s.contains('Could not find the function') || s.contains('PGRST202')) {
    return 'Esta função ainda não está ligada.';
  }
  return 'Não foi possível concluir. Tenta outra vez.';
}
