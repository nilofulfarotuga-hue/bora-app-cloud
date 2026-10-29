import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Um prato no funil do parceiro: quantos clientes abriram a ficha e quantas
/// unidades se pediram no mesmo período.
class PratoNoFunil {
  const PratoNoFunil({
    required this.id,
    required this.nome,
    required this.aberturas,
    required this.pedidos,
  });

  final String id;
  final String nome;
  final int aberturas;
  final int pedidos;

  /// Pedidos por abertura (0 quando ninguém abriu a ficha).
  double get conversao => aberturas <= 0 ? 0 : pedidos / aberturas;

  factory PratoNoFunil.fromJson(Map<String, dynamic> j) => PratoNoFunil(
        id: '${j['product_id']}',
        nome: '${j['nome'] ?? ''}',
        aberturas: (j['aberturas'] as num?)?.toInt() ?? 0,
        pedidos: (j['pedidos'] as num?)?.toInt() ?? 0,
      );
}

/// "Prato muito visto e pouco pedido" (adendo 4 · item 8): pelo menos
/// [minAberturas] clientes abriram a ficha e menos de [maxConversao] pedidos
/// por abertura. Os mais vistos primeiro.
List<PratoNoFunil> muitoVistosEPoucoPedidos(
  Iterable<PratoNoFunil> pratos, {
  int minAberturas = 5,
  double maxConversao = 0.2,
}) {
  return pratos
      .where((p) => p.aberturas >= minAberturas && p.conversao < maxConversao)
      .toList()
    ..sort((a, b) {
      final c = b.aberturas.compareTo(a.aberturas);
      return c != 0 ? c : a.conversao.compareTo(b.conversao);
    });
}

/// Regista que o cliente abriu a ficha de um prato (uma por cliente, prato e
/// dia — a tabela `product_view_daily` recusa repetidas). Serve só o funil do
/// painel do parceiro: não guarda mais nada. Melhor esforço, nunca lança.
class PratoVisitasService {
  PratoVisitasService._();

  /// Já registados nesta sessão da app (evita uma chamada por cada abertura).
  static final Set<String> _vistosNestaSessao = <String>{};

  @visibleForTesting
  static void esquecerSessao() => _vistosNestaSessao.clear();

  static Future<void> registarAbertura(String productId,
      {SupabaseClient? cliente}) async {
    if (productId.isEmpty || !_vistosNestaSessao.add(productId)) return;
    try {
      final db = cliente ?? Supabase.instance.client;
      if (db.auth.currentUser == null) return; // só com sessão
      await db.rpc('registar_abertura_ficha', params: {'p_product_id': productId});
    } catch (e) {
      debugPrint('[PratoVisitas] $e');
    }
  }

  /// O funil de uma loja nos últimos [dias] dias (só o dono ou o admin).
  static Future<List<PratoNoFunil>> funil(String restaurantId,
      {int dias = 30, SupabaseClient? cliente}) async {
    final db = cliente ?? Supabase.instance.client;
    final r = await db.rpc('partner_funil_pratos',
        params: {'p_restaurant_id': restaurantId, 'p_dias': dias});
    return [
      for (final l in (r as List? ?? const []))
        PratoNoFunil.fromJson((l as Map).cast<String, dynamic>()),
    ];
  }
}
