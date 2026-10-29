import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'fatura_nif_service.dart' show ChamadaRpc;

/// O que a loja parceira tem de saber para FATURAR um pedido ao cliente
/// (28/10/2026): o valor dos produtos ao preço de balcão e o NIF, se o
/// cliente o pediu. Vem de `partner_pedidos_fatura` — a loja só vê os pedidos
/// das suas lojas, e o NIF só existe se o cliente pediu fatura com NIF.
@immutable
class FaturaDoPedido {
  const FaturaDoPedido({
    required this.orderId,
    this.nif,
    this.nome,
    required this.valorCents,
  });

  final String orderId;
  final String? nif;
  final String? nome;

  /// O que a loja fatura ao cliente, em cêntimos (preço de balcão).
  final int valorCents;

  bool get temNif => nif != null && nif!.isNotEmpty;
  double get valorEur => valorCents / 100;

  /// Uma entrada do mapa que o servidor devolve:
  /// `{ "<pedido>": {nif, nome, valor_cents} }`.
  static FaturaDoPedido? deMapa(String orderId, dynamic m) {
    if (m is! Map) return null;
    String? limpo(dynamic v) {
      final t = (v ?? '').toString().trim();
      return t.isEmpty ? null : t;
    }

    final valor = m['valor_cents'];
    return FaturaDoPedido(
      orderId: orderId,
      nif: limpo(m['nif']),
      nome: limpo(m['nome']),
      valorCents: valor is num ? valor.round() : 0,
    );
  }
}

Future<dynamic> _rpcSupabase(String funcao, Map<String, dynamic> parametros) =>
    Supabase.instance.client.rpc(funcao, params: parametros);

/// Guarda a fatura de cada pedido da loja e mantém-na ao dia: pergunta ao
/// servidor pelos pedidos que ainda não conhece e ouve `order_invoice_requests`
/// em tempo real (o cliente pode pedir o NIF depois de a loja já ter o pedido).
///
/// Nunca lança: sem resposta, a linha da fatura simplesmente não aparece.
class PartnerFaturaService extends ChangeNotifier {
  PartnerFaturaService({ChamadaRpc? rpc}) : _rpc = rpc ?? _rpcSupabase;

  final ChamadaRpc _rpc;
  final Map<String, FaturaDoPedido> _dados = {};
  final Set<String> _pedidos = <String>{};
  RealtimeChannel? _canal;
  bool _libertado = false;

  /// A fatura do pedido, ou `null` enquanto não chega (ou se não é de loja
  /// parceira — o servidor não a devolve).
  FaturaDoPedido? de(String orderId) => _dados[orderId];

  /// Pergunta só pelos pedidos que ainda não foram pedidos.
  Future<void> carregar(Iterable<String> ids) async {
    final faltam = ids.where((id) => !_pedidos.contains(id)).toList();
    if (faltam.isEmpty) return;
    _pedidos.addAll(faltam);
    final ok = await _buscar(faltam);
    // Falhou (sem rede): fica por pedir, tenta-se na próxima.
    if (!ok) _pedidos.removeAll(faltam);
  }

  /// Volta a perguntar (o valor mudou: "marcar em falta", NIF novo…).
  Future<void> atualizar(Iterable<String> ids) async {
    final lista = ids.toList();
    if (lista.isEmpty) return;
    _pedidos.addAll(lista);
    await _buscar(lista);
  }

  /// Chamado quando `order_invoice_requests` muda (tempo real).
  void aoMudar(String? orderId) {
    if (orderId == null || orderId.isEmpty) return;
    unawaited(atualizar([orderId]));
  }

  Future<bool> _buscar(List<String> ids) async {
    try {
      final r = await _rpc('partner_pedidos_fatura', {'p_order_ids': ids});
      if (_libertado) return true;
      if (r is Map) {
        r.forEach((k, v) {
          final f = FaturaDoPedido.deMapa(k.toString(), v);
          if (f != null) _dados[f.orderId] = f;
        });
        notifyListeners();
        return true;
      }
      return false;
    } catch (e) {
      debugPrint('[PartnerFatura] partner_pedidos_fatura: $e');
      return false;
    }
  }

  /// Liga o tempo real. Idempotente.
  void ouvir(String restaurantId) {
    if (_canal != null) return;
    _canal = Supabase.instance.client
        .channel('partner_fatura_$restaurantId')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'order_invoice_requests',
          callback: (payload) {
            // No DELETE só vem a chave (order_id é a chave da tabela).
            final novo = payload.newRecord['order_id'];
            final velho = payload.oldRecord['order_id'];
            aoMudar((novo ?? velho)?.toString());
          },
        )
      ..subscribe();
  }

  @override
  void dispose() {
    _libertado = true;
    final c = _canal;
    _canal = null;
    if (c != null) unawaited(c.unsubscribe());
    super.dispose();
  }
}
