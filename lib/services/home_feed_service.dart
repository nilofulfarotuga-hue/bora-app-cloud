import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Uma faixa da home (`public.home_banners`).
class HomeBanner {
  const HomeBanner({
    required this.id,
    required this.titulo,
    required this.subtitulo,
    required this.imagemUrl,
    required this.corInicio,
    required this.corFim,
    required this.tipoDestino,
    required this.destino,
  });

  final String id;
  final String titulo;
  final String? subtitulo;
  final String? imagemUrl;
  final String corInicio;
  final String corFim;

  /// loja | categoria | cozinha | produto | codigo | nenhum
  final String tipoDestino;
  final String? destino;

  bool get clicavel =>
      tipoDestino != 'nenhum' && (destino ?? '').trim().isNotEmpty;

  factory HomeBanner.fromRow(Map<String, dynamic> r) => HomeBanner(
        id: (r['id'] ?? '').toString(),
        titulo: (r['titulo'] ?? '').toString(),
        subtitulo: (r['subtitulo'] as String?)?.trim(),
        imagemUrl: (r['imagem_url'] as String?)?.trim(),
        corInicio: (r['cor_inicio'] as String?) ?? '#16A34A',
        corFim: (r['cor_fim'] as String?) ?? '#22C55E',
        tipoDestino: (r['tipo_destino'] as String?) ?? 'nenhum',
        destino: (r['destino'] as String?)?.trim(),
      );
}

/// Loja devolvida pelas RPCs da home (`home_mais_pedidos`,
/// `home_pede_outra_vez`). Só se usa o id para achar a loja no
/// `RestaurantStore` e o número de pedidos para o título.
class HomeLojaRank {
  const HomeLojaRank({required this.id, required this.pedidos});
  final String id;
  final int pedidos;
}

/// Leituras da home do cliente (05/10). Só LÊ: faixas, rankings, novidades.
/// Cada chamada falha sozinha — devolve vazio/null e a secção esconde-se.
class HomeFeedService {
  HomeFeedService._();
  static final HomeFeedService instance = HomeFeedService._();

  SupabaseClient get _db => Supabase.instance.client;

  /// Faixas que se viram nesta sessão — a 'view' conta uma vez só.
  final Set<String> _vistas = <String>{};

  /// Faixas activas dentro da janela (o RLS já filtra), por ordem, sem as do
  /// tipo `codigo` que este cliente não pode usar. Lança em falha de rede —
  /// quem chama cai no banner antigo.
  Future<List<HomeBanner>> faixas() async {
    final List<dynamic> rows =
        await _db.from('home_banners').select().order('ordem').limit(8);
    final todas = rows
        .map((r) => HomeBanner.fromRow((r as Map).cast<String, dynamic>()))
        .toList();
    final out = <HomeBanner>[];
    for (final b in todas) {
      if (b.tipoDestino == 'codigo') {
        if (!await _codigoDisponivel(b.destino ?? '')) continue;
      }
      out.add(b);
      if (out.length == 4) break;
    }
    return out;
  }

  /// Regra do Danilo (05/10): uma faixa de código só aparece a quem AINDA
  /// não o usou, e some quando o código esgota ou fica inactivo. Sem sessão
  /// não se consegue confirmar nada disso (o RLS de `promo_codes` é só para
  /// autenticados), por isso não se mostra. Na dúvida, esconde.
  /// Nunca se lê `value_cents` aqui — o texto da faixa vem do banco.
  Future<bool> _codigoDisponivel(String codigo) async {
    final uid = _db.auth.currentUser?.id;
    final code = codigo.trim().toUpperCase();
    if (uid == null || code.isEmpty) return false;
    try {
      final promo = await _db
          .from('promo_codes')
          .select('code,is_active,uses_count,max_uses,valid_until')
          .eq('code', code)
          .maybeSingle();
      if (promo == null) return false; // inexistente ou inactivo (RLS)
      if (promo['is_active'] != true) return false;
      final max = (promo['max_uses'] as num?)?.toInt();
      final usos = (promo['uses_count'] as num?)?.toInt() ?? 0;
      if (max != null && usos >= max) return false;
      final ate = DateTime.tryParse((promo['valid_until'] ?? '').toString());
      if (ate != null && ate.isBefore(DateTime.now())) return false;
      final List<dynamic> meus = await _db
          .from('promo_code_uses')
          .select('code')
          .eq('user_id', uid)
          .eq('code', code)
          .limit(1);
      return meus.isEmpty;
    } catch (e) {
      debugPrint('[home_feed] codigo $code: $e');
      return false;
    }
  }

  /// 'view' uma vez por sessão; 'click' sempre. Silencioso em falha.
  void evento(String bannerId, String tipo) {
    if (bannerId.isEmpty) return;
    if (tipo == 'view' && !_vistas.add(bannerId)) return;
    _db.rpc('banner_evento', params: {'p_banner': bannerId, 'p_tipo': tipo})
        .then((_) {}, onError: (Object e) {
      debugPrint('[home_feed] banner_evento $tipo: $e');
    });
  }

  Future<List<HomeLojaRank>> maisPedidos({int limit = 12}) =>
      _ranking('home_mais_pedidos', limit);

  /// Só com sessão; sem sessão devolve vazio (a função é fechada a anon).
  Future<List<HomeLojaRank>> pedeOutraVez({int limit = 10}) async {
    if (_db.auth.currentUser == null) return const [];
    return _ranking('home_pede_outra_vez', limit);
  }

  Future<List<HomeLojaRank>> _ranking(String fn, int limit) async {
    try {
      final res = await _db.rpc(fn, params: {'p_limit': limit});
      if (res is! List) return const [];
      return res
          .map((r) {
            final m = (r as Map).cast<String, dynamic>();
            final id = (m['id'] ?? m['restaurant_id'] ?? '').toString();
            final n = (m['pedidos_30d'] ?? m['pedidos'] ?? 0) as num;
            return HomeLojaRank(id: id, pedidos: n.toInt());
          })
          .where((l) => l.id.isNotEmpty)
          .toList();
    } catch (e) {
      debugPrint('[home_feed] $fn: $e');
      return const [];
    }
  }

  /// Ids das lojas criadas nos últimos 30 dias, mais recentes primeiro.
  Future<List<String>> novidades() async {
    try {
      final desde = DateTime.now()
          .toUtc()
          .subtract(const Duration(days: 30))
          .toIso8601String();
      final List<dynamic> rows = await _db
          .from('restaurants')
          .select('id')
          .gte('created_at', desde)
          .order('created_at', ascending: false)
          .limit(20);
      return rows
          .map((r) => ((r as Map)['id'] ?? '').toString())
          .where((id) => id.isNotEmpty)
          .toList();
    } catch (e) {
      debugPrint('[home_feed] novidades: $e');
      return const [];
    }
  }

  /// Pesquisa global (`cliente_pesquisar`): {lojas:[...], produtos:[...]}.
  Future<Map<String, List<Map<String, dynamic>>>> pesquisar(String q,
      {int limit = 30}) async {
    final res = await _db
        .rpc('cliente_pesquisar', params: {'p_q': q, 'p_limit': limit});
    List<Map<String, dynamic>> lista(dynamic v) => v is List
        ? v.map((e) => (e as Map).cast<String, dynamic>()).toList()
        : <Map<String, dynamic>>[];
    if (res is! Map) return {'lojas': [], 'produtos': []};
    return {'lojas': lista(res['lojas']), 'produtos': lista(res['produtos'])};
  }
}
