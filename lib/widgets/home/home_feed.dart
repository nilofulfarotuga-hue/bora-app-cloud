import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../config/app_colors.dart';
import '../../config/app_spacing.dart';
import '../../config/ios_launch_flags.dart';
import '../../l10n/tr.dart';
import '../../models/restaurant_model.dart';
import '../../screens/restaurants_screen.dart' show RestaurantTile;
import '../../services/home_feed_service.dart';
import '../../stores/restaurant_store.dart';
import '../../utils/cozinhas.dart';
import '../../utils/home_destino.dart';
import '../bora/coming_soon.dart';

/// Cor '#RRGGBB' → Color. Inválida → verde Bora.
Color corDeHex(String? hex, {Color seFalhar = AppColors.primary}) {
  final h = (hex ?? '').replaceAll('#', '').trim();
  if (h.length != 6) return seFalhar;
  final v = int.tryParse(h, radix: 16);
  return v == null ? seFalhar : Color(0xFF000000 | v);
}

// ─── Carrossel de faixas ───────────────────────────────────────────────────

/// Carrossel das faixas da home (`home_banners`). Vazio ou com erro → mostra
/// [fallback] (o banner antigo): a home nunca fica vazia nem quebra.
class HomeBannerCarousel extends StatefulWidget {
  const HomeBannerCarousel({super.key, required this.fallback});

  final Widget fallback;

  @override
  State<HomeBannerCarousel> createState() => _HomeBannerCarouselState();
}

class _HomeBannerCarouselState extends State<HomeBannerCarousel> {
  final _page = PageController();
  List<HomeBanner>? _faixas; // null = a carregar
  bool _falhou = false;
  int _atual = 0;
  Timer? _auto;

  @override
  void initState() {
    super.initState();
    _carregar();
  }

  Future<void> _carregar() async {
    try {
      final f = await HomeFeedService.instance.faixas();
      if (!mounted) return;
      setState(() {
        _faixas = f;
        _falhou = false;
        _atual = 0;
      });
      if (_page.hasClients) _page.jumpToPage(0);
      _marcarVista(0);
      _ligarAuto();
    } catch (e) {
      debugPrint('[home_banners] $e');
      if (mounted) setState(() => _falhou = true);
    }
  }

  void _ligarAuto() {
    _auto?.cancel();
    final n = _faixas?.length ?? 0;
    if (n < 2) return;
    _auto = Timer.periodic(const Duration(seconds: 6), (_) {
      if (!mounted || !_page.hasClients) return;
      _page.animateToPage(
        (_atual + 1) % n,
        duration: const Duration(milliseconds: 450),
        curve: Curves.easeInOut,
      );
    });
  }

  void _marcarVista(int i) {
    final f = _faixas;
    if (f == null || i >= f.length) return;
    HomeFeedService.instance.evento(f[i].id, 'view');
  }

  Future<void> _tocar(HomeBanner b) async {
    if (!b.clicavel) return;
    HomeFeedService.instance.evento(b.id, 'click');
    await abrirDestino(context, tipo: b.tipoDestino, destino: b.destino!);
    // Depois de um código, a faixa pode ter de desaparecer (já usado).
    if (mounted && b.tipoDestino == 'codigo') _carregar();
  }

  @override
  void dispose() {
    _auto?.cancel();
    _page.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final f = _faixas;
    if (_falhou || (f != null && f.isEmpty)) return widget.fallback;
    if (f == null) return const _Esqueleto(altura: 120);
    return Column(
      children: [
        SizedBox(
          height: 120,
          child: PageView.builder(
            controller: _page,
            itemCount: f.length,
            onPageChanged: (i) {
              setState(() => _atual = i);
              _marcarVista(i);
            },
            itemBuilder: (_, i) => Padding(
              padding: const EdgeInsets.symmetric(horizontal: 2),
              child: _FaixaCard(faixa: f[i], onTap: () => _tocar(f[i])),
            ),
          ),
        ),
        if (f.length > 1) ...[
          const SizedBox(height: Spacing.sm),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              for (var i = 0; i < f.length; i++)
                AnimatedContainer(
                  duration: const Duration(milliseconds: 250),
                  margin: const EdgeInsets.symmetric(horizontal: 3),
                  width: i == _atual ? 18 : 6,
                  height: 6,
                  decoration: BoxDecoration(
                    color: i == _atual
                        ? AppColors.primary
                        : AppColors.dividerStrong,
                    borderRadius: BorderRadius.circular(Radii.pill),
                  ),
                ),
            ],
          ),
        ],
      ],
    );
  }
}

class _FaixaCard extends StatelessWidget {
  const _FaixaCard({required this.faixa, required this.onTap});

  final HomeBanner faixa;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final img = faixa.imagemUrl;
    final temImg = img != null && img.isNotEmpty;
    final raio = BorderRadius.circular(Radii.lg);
    final conteudo = Container(
      decoration: BoxDecoration(
        borderRadius: raio,
        boxShadow: AppColors.shadowCard,
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [corDeHex(faixa.corInicio), corDeHex(faixa.corFim)],
        ),
      ),
      child: ClipRRect(
        borderRadius: raio,
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (temImg)
              CachedNetworkImage(
                imageUrl: img,
                fit: BoxFit.cover,
                memCacheWidth: 900,
                errorWidget: (_, __, ___) => const SizedBox.shrink(),
              ),
            if (temImg)
              DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.centerLeft,
                    end: Alignment.centerRight,
                    colors: [
                      Colors.black.withValues(alpha: 0.55),
                      Colors.black.withValues(alpha: 0.05),
                    ],
                  ),
                ),
              ),
            Padding(
              padding: const EdgeInsets.symmetric(
                  horizontal: Spacing.xl, vertical: Spacing.lg),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          faixa.titulo,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 20,
                            fontWeight: FontWeight.w800,
                            height: 1.1,
                          ),
                        ),
                        if ((faixa.subtitulo ?? '').isNotEmpty) ...[
                          const SizedBox(height: Spacing.xs),
                          Text(
                            faixa.subtitulo!,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.95),
                              fontSize: 14,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  if (faixa.clicavel)
                    const Icon(Icons.chevron_right_rounded,
                        color: Colors.white, size: 32),
                ],
              ),
            ),
          ],
        ),
      ),
    );
    return Semantics(
      button: faixa.clicavel,
      label: faixa.titulo,
      identifier: 'faixa_home',
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: raio,
          onTap: faixa.clicavel ? onTap : null,
          child: conteudo,
        ),
      ),
    );
  }
}

// ─── Secções de lojas ──────────────────────────────────────────────────────

/// Secções da home por baixo das faixas: Pede outra vez, Os mais pedidos,
/// Novidades, faixas por cozinha e Todas as lojas. Cada uma carrega por si e
/// esconde-se se falhar — uma não derruba as outras.
class HomeFeedSections extends StatefulWidget {
  const HomeFeedSections({super.key, required this.sessaoId});

  /// Muda quando entra/sai uma conta — recarrega o que depende do cliente.
  final String? sessaoId;

  @override
  State<HomeFeedSections> createState() => _HomeFeedSectionsState();
}

class _HomeFeedSectionsState extends State<HomeFeedSections> {
  List<HomeLojaRank>? _maisPedidos;
  List<HomeLojaRank>? _pedeOutraVez;
  List<String>? _novidades;
  int _todasVisiveis = 20;

  @override
  void initState() {
    super.initState();
    _carregar();
  }

  @override
  void didUpdateWidget(covariant HomeFeedSections old) {
    super.didUpdateWidget(old);
    if (old.sessaoId != widget.sessaoId) _carregarPedeOutraVez();
  }

  void _carregar() {
    final s = HomeFeedService.instance;
    s.maisPedidos().then((v) {
      if (mounted) setState(() => _maisPedidos = v);
    });
    s.novidades().then((v) {
      if (mounted) setState(() => _novidades = v);
    });
    _carregarPedeOutraVez();
  }

  void _carregarPedeOutraVez() {
    HomeFeedService.instance.pedeOutraVez().then((v) {
      if (mounted) setState(() => _pedeOutraVez = v);
    });
  }

  @override
  Widget build(BuildContext context) {
    final store = context.watch<RestaurantStore>();
    final porId = {for (final r in store.restaurants) r.id: r};
    final aCarregar = !store.restaurantsLoadedOnce;

    List<RestaurantModel> lojas(Iterable<String> ids) =>
        [for (final id in ids) if (porId[id] != null) porId[id]!];

    final secoes = <Widget>[];

    // 1) Pede outra vez — só com sessão e com pedidos entregues.
    final pov = lojas((_pedeOutraVez ?? const []).map((e) => e.id));
    if (pov.isNotEmpty) {
      secoes.add(_Rail(
        titulo: 'Pede outra vez'.tr,
        lojas: pov,
        pequeno: true,
      ));
    }

    // 2) Os mais pedidos / Populares — com fallback sem números.
    final mp = _maisPedidos;
    if (mp == null || aCarregar) {
      secoes.add(const _RailEsqueleto());
    } else {
      final comPedidos = mp.where((e) => e.pedidos >= 1).length;
      final mostrarNumeros = comPedidos >= 4;
      final pedidosPorId = {for (final e in mp) e.id: e.pedidos};
      final lista = lojas(mp.map((e) => e.id));
      if (lista.isNotEmpty) {
        secoes.add(_Rail(
          titulo: mostrarNumeros
              ? 'Os mais pedidos da Guarda'.tr
              : 'Populares na Guarda'.tr,
          lojas: lista,
          linhaExtra: mostrarNumeros
              ? (r) {
                  final n = pedidosPorId[r.id] ?? 0;
                  if (n < 1) return null;
                  return n == 1
                      ? '1 pedido este mês'.tr
                      : '{0} pedidos este mês'.trArgs([n]);
                }
              : null,
        ));
      }
    }

    // 3) Novidades — lojas criadas nos últimos 30 dias.
    final nov = lojas(_novidades ?? const []);
    if (nov.isNotEmpty) {
      secoes.add(_Rail(titulo: 'Novidades'.tr, lojas: nov));
    }

    // 4) Faixas por tipo de comida (≥2 lojas online).
    if (!aCarregar) {
      for (final c in _cozinhasComLojas(store.restaurants)) {
        secoes.add(_Rail(
          titulo: nomeCozinha(c.key),
          lojas: c.value,
          verTudo: () => abrirCozinha(context, c.key),
        ));
      }
    }

    // 5) Todas as lojas — a tela nunca acaba vazia.
    final todas = _todasAsLojas(store.restaurants);
    if (aCarregar) {
      secoes.add(const _RailEsqueleto());
    } else if (todas.isNotEmpty) {
      secoes.add(Padding(
        padding: const EdgeInsets.only(bottom: Spacing.sm),
        child: _Titulo(texto: 'Todas as lojas'.tr),
      ));
      for (final r in todas.take(_todasVisiveis)) {
        secoes.add(RestaurantTile(
          business: r,
          onTap: () => abrirLoja(context, r),
        ));
      }
      if (todas.length > _todasVisiveis) {
        secoes.add(Center(
          child: TextButton(
            onPressed: () => setState(() => _todasVisiveis += 20),
            child: Text('Ver mais lojas'.tr),
          ),
        ));
      }
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final s in secoes) ...[s, const SizedBox(height: Spacing.lg)],
      ],
    );
  }

  static const _seccoesLoja = [
    BusinessCategory.restaurant,
    BusinessCategory.supermarket,
    BusinessCategory.store,
    BusinessCategory.pharmacy,
    BusinessCategory.festas,
    BusinessCategory.sobremesa,
  ];

  List<RestaurantModel> _todasAsLojas(List<RestaurantModel> todas) {
    final l = todas
        .where((r) => r.isOnline && _seccoesLoja.any(r.belongsTo))
        .toList()
      ..sort((a, b) {
        // Abertas primeiro, "Em breve" no fim, depois por nome.
        if (a.comingSoon != b.comingSoon) return a.comingSoon ? 1 : -1;
        final ao = a.isOpenNow(), bo = b.isOpenNow();
        if (ao != bo) return ao ? -1 : 1;
        return a.name.compareTo(b.name);
      });
    return l;
  }

  /// Cozinhas com pelo menos 2 lojas online (sem contar "Em breve"); as
  /// conhecidas (Sushi, Pizza, Hambúrguer, Açaí, Kebab) primeiro. Máx. 6.
  List<MapEntry<String, List<RestaurantModel>>> _cozinhasComLojas(
      List<RestaurantModel> todas) {
    final grupos = <String, List<RestaurantModel>>{};
    for (final r in todas) {
      if (!r.isOnline || !r.belongsTo(BusinessCategory.restaurant)) continue;
      for (final k in cozinhaChaves(r.cuisineType)) {
        grupos.putIfAbsent(k, () => []).add(r);
      }
    }
    const conhecidas = ['sushi', 'pizza', 'hamburguer', 'acai', 'kebab'];
    final ok = grupos.entries
        .where((e) => e.value.where((r) => !r.comingSoon).length >= 2)
        .toList()
      ..sort((a, b) {
        final ia = conhecidas.indexOf(a.key), ib = conhecidas.indexOf(b.key);
        if ((ia >= 0) != (ib >= 0)) return ia >= 0 ? -1 : 1;
        if (ia >= 0) return ia.compareTo(ib);
        return b.value.length.compareTo(a.value.length);
      });
    return ok.take(6).toList();
  }
}

class _Titulo extends StatelessWidget {
  const _Titulo({required this.texto, this.verTudo});

  final String texto;
  final VoidCallback? verTudo;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Text(
            texto,
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w800,
              color: AppColors.textPrimary,
            ),
          ),
        ),
        if (verTudo != null)
          TextButton(
            onPressed: verTudo,
            child: Text('Ver tudo'.tr,
                style: const TextStyle(fontWeight: FontWeight.w700)),
          ),
      ],
    );
  }
}

class _Rail extends StatelessWidget {
  const _Rail({
    required this.titulo,
    required this.lojas,
    this.verTudo,
    this.linhaExtra,
    this.pequeno = false,
  });

  final String titulo;
  final List<RestaurantModel> lojas;
  final VoidCallback? verTudo;
  final String? Function(RestaurantModel)? linhaExtra;
  final bool pequeno;

  @override
  Widget build(BuildContext context) {
    final largura = pequeno ? 120.0 : 160.0;
    final altura = pequeno ? 150.0 : 190.0;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _Titulo(texto: titulo, verTudo: verTudo),
        const SizedBox(height: Spacing.sm),
        SizedBox(
          height: altura,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: lojas.length,
            separatorBuilder: (_, __) => const SizedBox(width: Spacing.md),
            itemBuilder: (_, i) => _LojaCard(
              loja: lojas[i],
              largura: largura,
              extra: linhaExtra?.call(lojas[i]),
            ),
          ),
        ),
      ],
    );
  }
}

class _LojaCard extends StatelessWidget {
  const _LojaCard({required this.loja, required this.largura, this.extra});

  final RestaurantModel loja;
  final double largura;
  final String? extra;

  @override
  Widget build(BuildContext context) {
    final esconder = shouldHideStoreLogo(isPartner: loja.isPartner);
    final capa = (loja.heroImageUrl ?? '').isNotEmpty
        ? loja.heroImageUrl!
        : loja.photoUrl;
    final alturaImg = largura * 0.62;
    final subtitulo = extra ??
        (loja.cuisineType.split('·').first.trim().isNotEmpty
            ? loja.cuisineType.split('·').first.trim()
            : null);
    return SizedBox(
      width: largura,
      child: Material(
        color: Colors.white,
        borderRadius: BorderRadius.circular(Radii.md),
        child: InkWell(
          borderRadius: BorderRadius.circular(Radii.md),
          onTap: () => abrirLoja(context, loja),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ClipRRect(
                borderRadius:
                    const BorderRadius.vertical(top: Radius.circular(Radii.md)),
                child: SizedBox(
                  width: largura,
                  height: alturaImg,
                  child: capa.isNotEmpty && !esconder
                      ? CachedNetworkImage(
                          imageUrl: capa,
                          fit: BoxFit.cover,
                          memCacheWidth: (largura * 2.5).round(),
                          placeholder: (_, __) =>
                              const ColoredBox(color: AppColors.surface2),
                          errorWidget: (_, __, ___) => _Inicial(loja: loja),
                        )
                      : _Inicial(loja: loja),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(
                    Spacing.sm, Spacing.sm, Spacing.sm, 0),
                child: Text(
                  loja.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textPrimary,
                  ),
                ),
              ),
              if (loja.comingSoon)
                const Padding(
                  padding: EdgeInsets.fromLTRB(Spacing.sm, 2, Spacing.sm, 0),
                  child: ComingSoonChip(dense: true),
                )
              else if (subtitulo != null)
                Padding(
                  padding:
                      const EdgeInsets.fromLTRB(Spacing.sm, 2, Spacing.sm, 0),
                  child: Text(
                    subtitulo,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        fontSize: 12, color: AppColors.textSecondary),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Inicial extends StatelessWidget {
  const _Inicial({required this.loja});
  final RestaurantModel loja;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: AppColors.primaryLight,
      child: Center(
        child: Text(
          loja.name.isNotEmpty ? loja.name[0].toUpperCase() : '?',
          style: const TextStyle(
            fontSize: 28,
            fontWeight: FontWeight.w800,
            color: AppColors.primary,
          ),
        ),
      ),
    );
  }
}

class _Esqueleto extends StatelessWidget {
  const _Esqueleto({required this.altura, this.largura});
  final double altura;
  final double? largura;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: altura,
      width: largura,
      decoration: BoxDecoration(
        color: AppColors.surface2,
        borderRadius: BorderRadius.circular(Radii.lg),
      ),
    );
  }
}

class _RailEsqueleto extends StatelessWidget {
  const _RailEsqueleto();

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _Esqueleto(altura: 18, largura: 160),
        const SizedBox(height: Spacing.sm),
        // ListView e não Row: 3 cartões de 140 não cabem num telemóvel de
        // 380 px e a Row transbordava (autoteste Android #499 e iOS #165).
        // A lista corta o que sobra, como as faixas verdadeiras.
        SizedBox(
          height: 150,
          child: ListView(
            scrollDirection: Axis.horizontal,
            physics: const NeverScrollableScrollPhysics(),
            children: [
              for (var i = 0; i < 3; i++) ...[
                const _Esqueleto(altura: 150, largura: 140),
                const SizedBox(width: Spacing.md),
              ],
            ],
          ),
        ),
      ],
    );
  }
}
