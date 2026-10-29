import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/promocao.dart';
import 'definicoes_publicas.dart';

/// Promoções com preço riscado (adendo 5 · item 4, 29/10/2026).
///
/// Duas coisas vivem aqui:
///  1. [PromocoesLoja]: o que a app do cliente lê (as promoções ativas de cada
///     loja, com o preço mais baixo dos 30 dias), guardado 2 minutos.
///  2. [PromocoesApi]: o que o parceiro e o admin chamam (criar, terminar,
///     ligar, desligar, listar, auditar). Uma porta de mentira nos testes.
///
/// Tudo é tolerante: sem rede, sem a migração aplicada, com o interruptor
/// desligado ou com o servidor ainda sem aplicar a promoção, a leitura devolve
/// vazio e a app mostra os preços como sempre.

typedef BuscarPromocoes = Future<List<Map<String, dynamic>>> Function(
    String restaurantId);

/// Promoções ativas por loja, para os cartões e a ficha do produto.
class PromocoesLoja extends ChangeNotifier {
  PromocoesLoja({BuscarPromocoes? buscar, DateTime Function()? relogio})
      : _buscar = buscar ?? _buscarNoServidor,
        _relogio = relogio ?? DateTime.now;

  /// A instância da app. Os testes trocam-na com [usarParaTeste].
  static PromocoesLoja instance = PromocoesLoja();

  @visibleForTesting
  static void usarParaTeste(PromocoesLoja p) => instance = p;

  static const Duration _validade = Duration(minutes: 2);

  final BuscarPromocoes _buscar;
  final DateTime Function() _relogio;
  final Map<String, Map<String, PromocaoProduto>> _porLoja = {};
  final Map<String, DateTime> _lidoEm = {};
  final Map<String, Future<void>> _aLer = {};
  bool _descartado = false;

  static Future<List<Map<String, dynamic>>> _buscarNoServidor(
      String restaurantId) async {
    final r = await Supabase.instance.client
        .rpc('store_active_promotions', params: {'p_restaurant_id': restaurantId});
    return (r as List)
        .whereType<Map>()
        .map((m) => Map<String, dynamic>.from(m))
        .toList();
  }

  /// Lê as promoções da loja se a leitura tiver mais de 2 minutos. Nunca lança.
  Future<void> garantir(String restaurantId) {
    if (restaurantId.isEmpty) return Future<void>.value();
    final lido = _lidoEm[restaurantId];
    if (lido != null && _relogio().difference(lido) < _validade) {
      return Future<void>.value();
    }
    // O corpo com chavetas é de propósito: Map.remove devolve o próprio Future e
    // um whenComplete que devolve um Future fica à espera dele (ficaria à espera de si).
    return _aLer[restaurantId] ??= _ler(restaurantId).whenComplete(() {
      _aLer.remove(restaurantId);
    });
  }

  Future<void> _ler(String restaurantId) async {
    final mapa = <String, PromocaoProduto>{};
    try {
      final linhas = await _buscar(restaurantId);
      for (final l in linhas) {
        final p = PromocaoProduto.fromRow(l);
        if (p != null) mapa[p.productId] = p;
      }
    } catch (e) {
      debugPrint('[PromocoesLoja] leitura de $restaurantId falhou: $e');
    }
    _lidoEm[restaurantId] = _relogio();
    final antes = _porLoja[restaurantId];
    _porLoja[restaurantId] = mapa;
    if (!_descartado && !mapEquals(antes ?? const {}, mapa)) notifyListeners();
  }

  /// A promoção ativa deste produto, ou null (sem promoção, já acabou, ou
  /// ainda não foi lida). Síncrona: lê só o que já está guardado.
  PromocaoProduto? de(String restaurantId, String productId) {
    final p = _porLoja[restaurantId]?[productId];
    if (p == null || !p.aindaValida(_relogio())) return null;
    return p;
  }

  /// O preço de catálogo que o servidor vai cobrar por este produto: o
  /// promocional se houver promoção ativa, senão [normal].
  double precoDeCatalogo(String restaurantId, String productId, double normal) =>
      de(restaurantId, productId)?.precoPromocional ?? normal;

  /// Esquece tudo (após ligar/desligar uma promoção ou mudar de conta).
  void esquecer() {
    _porLoja.clear();
    _lidoEm.clear();
    notifyListeners();
  }

  @override
  void dispose() {
    _descartado = true;
    super.dispose();
  }
}

// ─── Parceiro e admin ───────────────────────────────────────────────────────

/// A promoção guardada num produto (para o parceiro ver e mudar).
class PromocaoDefinida {
  const PromocaoDefinida({
    this.precoPromocional,
    this.inicio,
    this.fim,
    this.ativada = true,
  });

  final double? precoPromocional;
  final DateTime? inicio;
  final DateTime? fim;
  final bool ativada;

  bool get existe => precoPromocional != null;
}

/// O interruptor geral e se o servidor já aplica a promoção.
class EstadoPromocoes {
  const EstadoPromocoes({required this.ligado, required this.servidorPronto});
  final bool ligado;
  final bool servidorPronto;
}

/// Uma linha da lista do painel (`admin_promotions_list`).
class PromocaoAdmin {
  const PromocaoAdmin({
    required this.productId,
    required this.produto,
    required this.restaurantId,
    required this.loja,
    required this.lojaParceira,
    required this.preco,
    required this.precoPromocional,
    this.inicio,
    this.fim,
    this.ativada = true,
    this.criadaPor,
    this.maisBaixo30d,
    this.aoPeso = false,
  });

  final String productId;
  final String produto;
  final String restaurantId;
  final String loja;
  final bool lojaParceira;
  final double preco;
  final double precoPromocional;
  final DateTime? inicio;
  final DateTime? fim;
  final bool ativada;
  final String? criadaPor;
  final double? maisBaixo30d;
  final bool aoPeso;

  EstadoPromocao estado(DateTime agora) => estadoDaPromocao(
        preco: preco,
        precoPromocional: precoPromocional,
        ativada: ativada,
        inicio: inicio,
        fim: fim,
        agora: agora,
      );

  static PromocaoAdmin? fromRow(Map<String, dynamic> m) {
    final id = (m['product_id'] ?? '').toString();
    final preco = _n(m['price']);
    final promo = _n(m['discount_price']);
    if (id.isEmpty || preco == null || promo == null) return null;
    final email = (m['created_by_email'] ?? '').toString().trim();
    return PromocaoAdmin(
      productId: id,
      produto: (m['product_name'] ?? '').toString(),
      restaurantId: (m['restaurant_id'] ?? '').toString(),
      loja: (m['restaurant_name'] ?? '').toString(),
      lojaParceira: m['is_partner'] == true,
      preco: preco,
      precoPromocional: promo,
      inicio: _d(m['starts_at']),
      fim: _d(m['ends_at']),
      ativada: m['enabled'] != false,
      criadaPor: email.isEmpty ? null : email,
      maisBaixo30d: _n(m['lowest_price_30d']),
      aoPeso: m['sold_by_weight'] == true,
    );
  }
}

/// Uma linha da auditoria (`admin_promotions_audit`).
class AuditoriaPromocao {
  const AuditoriaPromocao({
    required this.quando,
    required this.quem,
    required this.acao,
    this.produto,
    this.detalhes = const {},
  });

  final DateTime? quando;
  final String quem;
  final String acao;
  final String? produto;
  final Map<String, dynamic> detalhes;

  /// "Criou a promoção", "Desligou a promoção"… em português do Brasil (painel).
  String get descricao {
    switch (acao) {
      case 'promotion_set':
        return 'Criou ou mudou a promoção';
      case 'promotion_cleared':
        return 'Terminou a promoção';
      case 'promotion_enabled':
        return 'Ligou a promoção';
      case 'promotion_disabled':
        return 'Desligou a promoção';
      case 'platform_setting_updated':
        final novo = detalhes['new'];
        return novo == true
            ? 'Ligou o interruptor geral das promoções'
            : 'Desligou o interruptor geral das promoções';
      default:
        return acao;
    }
  }

  static AuditoriaPromocao fromRow(Map<String, dynamic> m) {
    final det = m['details'];
    return AuditoriaPromocao(
      quando: _d(m['created_at']),
      quem: (m['admin_email'] ?? '').toString(),
      acao: (m['action'] ?? '').toString(),
      produto: m['product_name']?.toString(),
      detalhes: det is Map ? Map<String, dynamic>.from(det) : const {},
    );
  }
}

/// Um produto encontrado na pesquisa do painel.
class ProdutoPesquisa {
  const ProdutoPesquisa({
    required this.id,
    required this.nome,
    required this.preco,
    required this.loja,
    this.lojaParceira = false,
    this.aoPeso = false,
  });

  final String id;
  final String nome;
  final double preco;
  final String loja;
  final bool lojaParceira;
  final bool aoPeso;
}

double? _n(Object? v) {
  if (v == null) return null;
  if (v is num) return v.toDouble();
  return double.tryParse(v.toString());
}

DateTime? _d(Object? v) => v == null ? null : DateTime.tryParse(v.toString())?.toLocal();

/// Tudo o que o parceiro e o admin fazem com promoções.
abstract class PromocoesApi {
  /// O interruptor geral está ligado? (só o parceiro precisa desta leitura)
  Future<bool> ligado();

  /// A promoção guardada neste produto; null se não tiver (ou se a migração
  /// ainda não foi aplicada).
  Future<PromocaoDefinida?> doProduto(String productId);

  /// Cria ou muda a promoção (parceiro dono ou admin). [precoPromocional] nulo
  /// termina a promoção. O preço é de catálogo (o mesmo sentido de `products.price`).
  Future<void> definir({
    required String productId,
    required double? precoPromocional,
    DateTime? inicio,
    DateTime? fim,
  });

  // ── Painel admin ──
  Future<EstadoPromocoes> estadoGeral();
  Future<List<PromocaoAdmin>> lista();
  Future<void> definirInterruptor(bool ligado);
  Future<void> ligarDesligar(String productId, bool ativada, {String? motivo});
  Future<List<AuditoriaPromocao>> auditoria({int limite = 60});
  Future<List<ProdutoPesquisa>> procurarProdutos(String texto);
}

class PromocoesApiSupabase implements PromocoesApi {
  PromocoesApiSupabase([SupabaseClient? client]) : _client = client;
  final SupabaseClient? _client;
  SupabaseClient get _sb => _client ?? Supabase.instance.client;

  @override
  Future<bool> ligado() async {
    final m = await lerDefinicoesPublicas(const ['promotions_enabled']);
    final v = m['promotions_enabled'];
    if (v is bool) return v;
    return v?.toString().replaceAll('"', '').trim().toLowerCase() == 'true';
  }

  @override
  Future<PromocaoDefinida?> doProduto(String productId) async {
    try {
      final r = await _sb
          .from('products')
          .select('discount_price,discount_starts_at,discount_ends_at,discount_enabled')
          .eq('id', productId)
          .maybeSingle();
      if (r == null || r['discount_price'] == null) return null;
      return PromocaoDefinida(
        precoPromocional: _n(r['discount_price']),
        inicio: _d(r['discount_starts_at']),
        fim: _d(r['discount_ends_at']),
        ativada: r['discount_enabled'] != false,
      );
    } catch (e) {
      debugPrint('[Promocoes] doProduto($productId) falhou: $e');
      return null;
    }
  }

  @override
  Future<void> definir({
    required String productId,
    required double? precoPromocional,
    DateTime? inicio,
    DateTime? fim,
  }) async {
    await _sb.rpc('partner_set_promotion', params: {
      'p_product_id': productId,
      'p_discount_price': precoPromocional,
      'p_starts_at': inicio?.toUtc().toIso8601String(),
      'p_ends_at': fim?.toUtc().toIso8601String(),
    });
    PromocoesLoja.instance.esquecer();
  }

  @override
  Future<EstadoPromocoes> estadoGeral() async {
    final r = await _sb.rpc('promotions_status');
    final m = r is Map ? Map<String, dynamic>.from(r) : const <String, dynamic>{};
    return EstadoPromocoes(
      ligado: m['enabled'] == true,
      servidorPronto: m['server_ready'] == true,
    );
  }

  @override
  Future<List<PromocaoAdmin>> lista() async {
    final r = await _sb.rpc('admin_promotions_list');
    return (r as List)
        .whereType<Map>()
        .map((m) => PromocaoAdmin.fromRow(Map<String, dynamic>.from(m)))
        .whereType<PromocaoAdmin>()
        .toList();
  }

  @override
  Future<void> definirInterruptor(bool ligado) async {
    await _sb.rpc('admin_update_setting',
        params: {'p_key': 'promotions_enabled', 'p_value': ligado});
    PromocoesLoja.instance.esquecer();
  }

  @override
  Future<void> ligarDesligar(String productId, bool ativada, {String? motivo}) async {
    await _sb.rpc('admin_promotion_toggle', params: {
      'p_product_id': productId,
      'p_enabled': ativada,
      'p_reason': motivo,
    });
    PromocoesLoja.instance.esquecer();
  }

  @override
  Future<List<AuditoriaPromocao>> auditoria({int limite = 60}) async {
    final r = await _sb.rpc('admin_promotions_audit', params: {'p_limit': limite});
    return (r as List)
        .whereType<Map>()
        .map((m) => AuditoriaPromocao.fromRow(Map<String, dynamic>.from(m)))
        .toList();
  }

  @override
  Future<List<ProdutoPesquisa>> procurarProdutos(String texto) async {
    final t = texto.trim().replaceAll(RegExp(r'[%,()]'), ' ');
    if (t.length < 2) return const [];
    final linhas = await _sb
        .from('products')
        .select('id,name,price,restaurant_id,sold_by_weight')
        .ilike('name', '%$t%')
        .limit(20);
    final lista = (linhas as List).whereType<Map>().toList();
    final ids = lista.map((m) => m['restaurant_id'].toString()).toSet().toList();
    final lojas = <String, Map>{};
    if (ids.isNotEmpty) {
      final rs = await _sb
          .from('restaurants')
          .select('id,name,is_partner')
          .inFilter('id', ids);
      for (final l in (rs as List).whereType<Map>()) {
        lojas[l['id'].toString()] = l;
      }
    }
    return [
      for (final m in lista)
        if (_n(m['price']) != null)
          ProdutoPesquisa(
            id: m['id'].toString(),
            nome: (m['name'] ?? '').toString(),
            preco: _n(m['price'])!,
            loja: (lojas[m['restaurant_id'].toString()]?['name'] ?? '').toString(),
            lojaParceira: lojas[m['restaurant_id'].toString()]?['is_partner'] == true,
            aoPeso: m['sold_by_weight'] == true,
          ),
    ];
  }
}

/// Traduz o erro do servidor numa frase para quem usa o ecrã.
String mensagemErroPromocao(Object e) {
  final t = e is PostgrestException ? e.message : e.toString();
  if (t.contains('promo_preco_invalido')) {
    return 'O preço promocional tem de ser maior que zero e menor que o preço normal.';
  }
  if (t.contains('promo_datas_invalidas')) {
    return 'As datas não servem: o fim tem de ser depois do início e ainda não ter passado.';
  }
  if (t.contains('promo_nao_suporta_peso')) {
    return 'Produtos vendidos ao peso não levam preço promocional.';
  }
  if (t.contains('not_owner_nor_admin') || t.contains('admin_required')) {
    return 'Não tens permissão para mudar este produto.';
  }
  if (t.contains('product_not_found') || t.contains('promo_not_found')) {
    return 'Produto não encontrado. Atualiza a lista.';
  }
  return 'Não foi possível guardar. Tenta outra vez.';
}
