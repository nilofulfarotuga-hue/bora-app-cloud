import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../config/app_colors.dart';
import '../config/app_spacing.dart';
import '../l10n/tr.dart';
import '../models/restaurant_model.dart';
import '../services/home_feed_service.dart';
import '../services/pricing_service.dart';
import '../stores/restaurant_store.dart';
import '../stores/tvde_store.dart';
import '../utils/cozinhas.dart';
import '../utils/home_destino.dart';
import '../widgets/bora/bora_screen_app_bar.dart';
import '../widgets/bora/coming_soon.dart';
import 'restaurants_screen.dart' show RestaurantTile;

/// A lupa da home (05/10): acha lojas de todas as secções e produtos.
///
/// Pesquisa no banco pela RPC `cliente_pesquisar` (ignora acentos e
/// maiúsculas, tolera erros). O que o banco não liga ao termo — ex.
/// 'hamburguer' não dá o McDonald's, que é 'Fast Food' — junta-se aqui pelas
/// cozinhas (`utils/cozinhas.dart`). Preço do produto pelo MESMO caminho do
/// resto da app (`PricingService.applyMarkup`) — nunca calculado à mão.
class GlobalSearchScreen extends StatefulWidget {
  const GlobalSearchScreen({super.key});

  @override
  State<GlobalSearchScreen> createState() => _GlobalSearchScreenState();
}

class _GlobalSearchScreenState extends State<GlobalSearchScreen> {
  static const _kRecentes = 'bora.pesquisa.recentes';

  final _ctrl = TextEditingController();
  Timer? _debounce;
  String _q = '';
  bool _aProcurar = false;
  bool _falhou = false;
  List<RestaurantModel> _lojas = const [];
  List<Map<String, dynamic>> _produtos = const [];
  List<String> _recentes = const [];
  int _pedido = 0; // descarta respostas antigas

  @override
  void initState() {
    super.initState();
    _lerRecentes();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final store = context.read<RestaurantStore>();
      if (!store.restaurantsLoadedOnce && !store.restaurantsLoading) {
        store.loadRestaurantsFromSupabase();
      }
    });
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _ctrl.dispose();
    super.dispose();
  }

  Future<void> _lerRecentes() async {
    try {
      final p = await SharedPreferences.getInstance();
      if (mounted) setState(() => _recentes = p.getStringList(_kRecentes) ?? []);
    } catch (_) {}
  }

  Future<void> _guardarRecente(String q) async {
    final t = q.trim();
    if (t.length < 2) return;
    final l = [t, ..._recentes.where((r) => r.toLowerCase() != t.toLowerCase())]
        .take(8)
        .toList();
    setState(() => _recentes = l);
    try {
      final p = await SharedPreferences.getInstance();
      await p.setStringList(_kRecentes, l);
    } catch (_) {}
  }

  Future<void> _limparRecentes() async {
    setState(() => _recentes = const []);
    try {
      final p = await SharedPreferences.getInstance();
      await p.remove(_kRecentes);
    } catch (_) {}
  }

  void _mudou(String v) {
    setState(() => _q = v);
    _debounce?.cancel();
    if (v.trim().length < 2) {
      setState(() {
        _lojas = const [];
        _produtos = const [];
        _aProcurar = false;
        _falhou = false;
      });
      return;
    }
    _debounce = Timer(const Duration(milliseconds: 300), () => _procurar(v));
  }

  void _usarTermo(String t) {
    _ctrl.text = t;
    _ctrl.selection = TextSelection.collapsed(offset: t.length);
    _mudou(t);
  }

  Future<void> _procurar(String q) async {
    final n = ++_pedido;
    setState(() {
      _aProcurar = true;
      _falhou = false;
    });
    final store = context.read<RestaurantStore>();
    try {
      final res = await HomeFeedService.instance.pesquisar(q.trim());
      if (!mounted || n != _pedido) return;
      final porId = {for (final r in store.restaurants) r.id: r};
      final lojas = <RestaurantModel>[];
      for (final m in res['lojas']!) {
        final r = porId[(m['id'] ?? '').toString()];
        if (r != null && !lojas.contains(r)) lojas.add(r);
      }
      // Sinónimos que o banco não cobre: junta as lojas da mesma cozinha.
      final cozinha = cozinhaDaPesquisa(q);
      if (cozinha != null) {
        for (final r in store.restaurants) {
          if (!r.isOnline || lojas.contains(r)) continue;
          if (cozinhaChaves(r.cuisineType).contains(cozinha)) lojas.add(r);
        }
      }
      setState(() {
        _lojas = lojas;
        _produtos = res['produtos']!;
        _aProcurar = false;
      });
      _guardarRecente(q);
    } catch (e) {
      debugPrint('[pesquisa] $e');
      if (!mounted || n != _pedido) return;
      setState(() {
        _aProcurar = false;
        _falhou = true;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      resizeToAvoidBottomInset: true,
      appBar: BoraScreenAppBar(title: 'Pesquisar'.tr),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(
                Spacing.lg, Spacing.md, Spacing.lg, Spacing.sm),
            child: Container(
              height: 52,
              padding: const EdgeInsets.symmetric(horizontal: Spacing.lg),
              decoration: BoxDecoration(
                color: AppColors.surface2,
                borderRadius: BorderRadius.circular(Radii.pill),
                border: Border.all(color: AppColors.divider),
              ),
              child: Row(
                children: [
                  const Icon(Icons.search,
                      color: AppColors.textSecondary, size: 22),
                  const SizedBox(width: Spacing.sm),
                  Expanded(
                    child: TextField(
                      controller: _ctrl,
                      autofocus: true,
                      textInputAction: TextInputAction.search,
                      onChanged: _mudou,
                      onSubmitted: (v) {
                        _debounce?.cancel();
                        if (v.trim().length >= 2) _procurar(v);
                      },
                      decoration: InputDecoration(
                        hintText: 'Lojas, pratos, produtos…'.tr,
                        border: InputBorder.none,
                        isDense: true,
                      ),
                    ),
                  ),
                  if (_q.isNotEmpty)
                    IconButton(
                      icon: const Icon(Icons.close, size: 20),
                      tooltip: 'Limpar'.tr,
                      onPressed: () => _usarTermo(''),
                    ),
                ],
              ),
            ),
          ),
          Expanded(
            child: _q.trim().length < 2 ? _sugestoes() : _resultados(),
          ),
        ],
      ),
    );
  }

  // ─── Antes de escrever ─────────────────────────────────────────────────

  Widget _sugestoes() {
    final store = context.watch<RestaurantStore>();
    final contagem = <String, int>{};
    for (final r in store.restaurants) {
      if (!r.isOnline || !r.belongsTo(BusinessCategory.restaurant)) continue;
      for (final k in cozinhaChaves(r.cuisineType)) {
        contagem[k] = (contagem[k] ?? 0) + 1;
      }
    }
    final cozinhas = contagem.entries.where((e) => e.value >= 2).toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    return ListView(
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      padding: const EdgeInsets.fromLTRB(
          Spacing.lg, Spacing.sm, Spacing.lg, Spacing.xxxl),
      children: [
        if (_recentes.isNotEmpty) ...[
          Row(
            children: [
              Expanded(child: _Cabecalho(texto: 'Pesquisas recentes'.tr)),
              TextButton(
                onPressed: _limparRecentes,
                child: Text('Limpar'.tr),
              ),
            ],
          ),
          for (final r in _recentes)
            ListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.history, size: 20),
              title: Text(r),
              onTap: () => _usarTermo(r),
            ),
          const SizedBox(height: Spacing.md),
        ],
        _Cabecalho(texto: 'Categorias'.tr),
        const SizedBox(height: Spacing.sm),
        Wrap(
          spacing: Spacing.sm,
          runSpacing: Spacing.sm,
          children: [
            for (final e in categoriasDestino.entries)
              // Bora Motorista so aparece a quem tem acesso (regra 30/09).
              if (e.key != 'motorista' ||
                  context.watch<TvdeStore>().tvdeAccess)
              ActionChip(
                label: Text(e.value.tr),
                onPressed: () => abrirCategoria(context, e.key),
              ),
          ],
        ),
        if (cozinhas.isNotEmpty) ...[
          const SizedBox(height: Spacing.lg),
          _Cabecalho(texto: 'Cozinhas populares'.tr),
          const SizedBox(height: Spacing.sm),
          Wrap(
            spacing: Spacing.sm,
            runSpacing: Spacing.sm,
            children: [
              for (final c in cozinhas.take(12))
                ActionChip(
                  label: Text(nomeCozinha(c.key)),
                  onPressed: () => _usarTermo(nomeCozinha(c.key)),
                ),
            ],
          ),
        ],
      ],
    );
  }

  // ─── Resultados ────────────────────────────────────────────────────────

  Widget _resultados() {
    if (_aProcurar && _lojas.isEmpty && _produtos.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_falhou) {
      return _Vazio(
        texto: 'Não foi possível pesquisar agora. Verifica a ligação.'.tr,
        acao: TextButton(
          onPressed: () => _procurar(_q),
          child: Text('Tentar outra vez'.tr),
        ),
      );
    }
    if (_lojas.isEmpty && _produtos.isEmpty) {
      return _Vazio(
        texto: 'Não encontrámos "{0}" — tenta pizza, sushi, açaí…'
            .trArgs([_q.trim()]),
        acao: Wrap(
          spacing: Spacing.sm,
          children: [
            for (final s in const ['Pizza', 'Sushi', 'Açaí', 'Leite'])
              ActionChip(label: Text(s), onPressed: () => _usarTermo(s)),
          ],
        ),
      );
    }

    final restaurantes =
        _lojas.where((r) => r.category == BusinessCategory.restaurant ||
            r.category == BusinessCategory.festas ||
            r.category == BusinessCategory.sobremesa);
    final mercados =
        _lojas.where((r) => r.category == BusinessCategory.supermarket);
    final lojas = _lojas.where((r) => r.category == BusinessCategory.store);
    final farmacias =
        _lojas.where((r) => r.category == BusinessCategory.pharmacy);
    final servicos = _lojas.where((r) => r.category == BusinessCategory.beauty);

    final store = context.read<RestaurantStore>();
    final porId = {for (final r in store.restaurants) r.id: r};

    return ListView(
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      padding: const EdgeInsets.fromLTRB(
          Spacing.lg, Spacing.sm, Spacing.lg, Spacing.xxxl),
      children: [
        ..._grupo('Restaurantes'.tr, restaurantes),
        ..._grupo('Supermercados'.tr, mercados),
        ..._grupo('Lojas'.tr, lojas),
        ..._grupo('Farmácia'.tr, farmacias),
        ..._grupo('Beleza'.tr, servicos),
        if (_produtos.isNotEmpty) ...[
          _Cabecalho(texto: 'Produtos'.tr),
          const SizedBox(height: Spacing.sm),
          for (final p in _produtos)
            _ProdutoLinha(produto: p, loja: porId[p['restaurant_id']]),
        ],
      ],
    );
  }

  List<Widget> _grupo(String titulo, Iterable<RestaurantModel> lojas) {
    if (lojas.isEmpty) return const [];
    return [
      _Cabecalho(texto: titulo),
      const SizedBox(height: Spacing.sm),
      for (final r in lojas)
        RestaurantTile(business: r, onTap: () => abrirLoja(context, r)),
      const SizedBox(height: Spacing.md),
    ];
  }
}

class _Cabecalho extends StatelessWidget {
  const _Cabecalho({required this.texto});
  final String texto;

  @override
  Widget build(BuildContext context) => Text(
        texto,
        style: const TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.w800,
          color: AppColors.textPrimary,
        ),
      );
}

class _Vazio extends StatelessWidget {
  const _Vazio({required this.texto, this.acao});
  final String texto;
  final Widget? acao;

  @override
  Widget build(BuildContext context) {
    return ListView(
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      padding: const EdgeInsets.all(Spacing.xxl),
      children: [
        Icon(Icons.search_off,
            size: 56, color: AppColors.textSecondary.withValues(alpha: 0.4)),
        const SizedBox(height: Spacing.md),
        Text(
          texto,
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 14, color: AppColors.textSecondary),
        ),
        if (acao != null) ...[
          const SizedBox(height: Spacing.md),
          Center(child: acao!),
        ],
      ],
    );
  }
}

class _ProdutoLinha extends StatelessWidget {
  const _ProdutoLinha({required this.produto, required this.loja});

  final Map<String, dynamic> produto;
  final RestaurantModel? loja;

  @override
  Widget build(BuildContext context) {
    final nome = (produto['name'] ?? '').toString();
    final lojaNome = loja?.name ??
        (produto['restaurant_name'] ?? '').toString();
    final foto = (produto['photo_url'] ?? '').toString();
    final base = (produto['price'] as num?)?.toDouble() ?? 0;
    final emBreve = loja?.comingSoon ?? (produto['coming_soon'] == true);
    // Preço exibido = cobrado: o mesmo caminho dos ecrãs das lojas.
    final preco = loja == null || base <= 0
        ? null
        : PricingService.applyMarkup(base, loja!.isPartner);

    return Padding(
      padding: const EdgeInsets.only(bottom: Spacing.sm),
      child: Material(
        color: Colors.white,
        borderRadius: BorderRadius.circular(Radii.md),
        child: InkWell(
          borderRadius: BorderRadius.circular(Radii.md),
          onTap: () => abrirProduto(context, (produto['id'] ?? '').toString()),
          child: Padding(
            padding: const EdgeInsets.all(Spacing.sm),
            child: Row(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(Radii.sm),
                  child: SizedBox(
                    width: 56,
                    height: 56,
                    child: foto.isEmpty
                        ? const ColoredBox(
                            color: AppColors.surface2,
                            child: Icon(Icons.fastfood_outlined,
                                color: AppColors.textSubtle),
                          )
                        : CachedNetworkImage(
                            imageUrl: foto,
                            fit: BoxFit.cover,
                            memCacheWidth: 168,
                            errorWidget: (_, __, ___) =>
                                const ColoredBox(color: AppColors.surface2),
                          ),
                  ),
                ),
                const SizedBox(width: Spacing.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(nome,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                              fontSize: 14, fontWeight: FontWeight.w600)),
                      const SizedBox(height: 2),
                      Text(lojaNome,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                              fontSize: 12, color: AppColors.textSecondary)),
                      if (emBreve) ...[
                        const SizedBox(height: 4),
                        const ComingSoonChip(dense: true),
                      ],
                    ],
                  ),
                ),
                if (preco != null)
                  Text(
                    '€${preco.toStringAsFixed(2)}',
                    style: const TextStyle(
                        fontSize: 14, fontWeight: FontWeight.w700),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
