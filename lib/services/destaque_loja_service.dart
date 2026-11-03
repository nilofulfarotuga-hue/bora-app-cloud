import 'package:supabase_flutter/supabase_flutter.dart';

/// "Hambúrguer do mês" (02/11/2026, missão boom-hamburguer-mes, bloco C): um
/// produto em destaque no topo da loja, padrão Glovo/Uber Eats.
/// Vive em `restaurants.produto_destaque_id` + `produto_destaque_rotulo`.
class DestaqueLoja {
  const DestaqueLoja({required this.produtoId, required this.rotulo});

  static const String rotuloPorDefeito = 'Hambúrguer do mês';

  final String produtoId;
  final String rotulo;

  /// A linha de `restaurants` (ou null). Sem produto = sem destaque.
  static DestaqueLoja? daLinha(Map<String, dynamic>? linha) {
    final id = (linha?['produto_destaque_id'] ?? '').toString().trim();
    if (id.isEmpty) return null;
    final rotulo = (linha?['produto_destaque_rotulo'] ?? '').toString().trim();
    return DestaqueLoja(
        produtoId: id, rotulo: rotulo.isEmpty ? rotuloPorDefeito : rotulo);
  }
}

/// Lê e grava o destaque. O parceiro só mexe na loja dele
/// (`parceiro_definir_destaque`); o admin em qualquer uma
/// (`admin_definir_destaque`, com auditoria). Produto nulo = tirar.
class DestaqueLojaService {
  DestaqueLojaService({SupabaseClient? client}) : _client = client;

  static final DestaqueLojaService instance = DestaqueLojaService();

  final SupabaseClient? _client;
  SupabaseClient get _sb => _client ?? Supabase.instance.client;

  /// O destaque da loja. Erro, sem rede ou sem destaque = null (a loja fica
  /// como antes — nunca parte o ecrã).
  Future<DestaqueLoja?> daLoja(String restaurantId) async {
    try {
      final linha = await _sb
          .from('restaurants')
          .select('produto_destaque_id, produto_destaque_rotulo')
          .eq('id', restaurantId)
          .maybeSingle();
      return DestaqueLoja.daLinha(linha);
    } catch (_) {
      return null;
    }
  }

  Future<void> definirComoParceiro(
          String restaurantId, String? produtoId, String? rotulo) =>
      _sb.rpc('parceiro_definir_destaque', params: {
        'p_restaurant_id': restaurantId,
        'p_produto_id': produtoId,
        'p_rotulo': rotulo,
      });

  Future<void> definirComoAdmin(
          String restaurantId, String? produtoId, String? rotulo) =>
      _sb.rpc('admin_definir_destaque', params: {
        'p_restaurant_id': restaurantId,
        'p_produto_id': produtoId,
        'p_rotulo': rotulo,
      });
}
