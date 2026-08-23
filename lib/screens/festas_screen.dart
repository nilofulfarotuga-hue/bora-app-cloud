import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../config/app_colors.dart';
import '../config/app_spacing.dart';
import '../models/restaurant_model.dart';
import '../stores/restaurant_store.dart';
import '../utils/business_opener.dart';
import '../widgets/bora/bora_screen_app_bar.dart';
import '../widgets/bora_support_fab.dart';

/// Categoria **Festas** — casas que fazem salgados, doces e bolos por
/// encomenda, com aviso prévio. Lista os negócios com `category = 'festas'`
/// (ou com `festas` em `extra_categories`).
class FestasScreen extends StatelessWidget {
  const FestasScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final restaurantStore = context.watch<RestaurantStore>();
    final casas = restaurantStore.restaurants
        .where((b) => b.belongsTo(BusinessCategory.festas))
        .toList()
      ..sort((a, b) {
        final aOpen = a.isOpenNow();
        final bOpen = b.isOpenNow();
        if (aOpen != bOpen) return aOpen ? -1 : 1;
        return a.name.compareTo(b.name);
      });

    return Scaffold(
      backgroundColor: AppColors.background,
      floatingActionButton: const BoraSupportFab(),
      appBar: const BoraScreenAppBar(title: 'Festas'),
      body: casas.isEmpty
          ? const _SemCasas()
          : ListView.builder(
              padding: const EdgeInsets.fromLTRB(
                  Spacing.lg, Spacing.md, Spacing.lg, Spacing.xxl),
              itemCount: casas.length + 1,
              itemBuilder: (context, index) {
                if (index == 0) return const _Cabecalho();
                final casa = casas[index - 1];
                return _CasaDeFestas(
                  casa: casa,
                  onTap: () => openBusiness(context, restaurantStore, casa),
                );
              },
            ),
    );
  }
}

class _Cabecalho extends StatelessWidget {
  const _Cabecalho();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: Spacing.md),
      child: Text(
        'Salgados, doces e bolos por encomenda.',
        style: TextStyle(fontSize: 13, color: AppColors.textSecondary),
      ),
    );
  }
}

class _CasaDeFestas extends StatelessWidget {
  const _CasaDeFestas({required this.casa, required this.onTap});

  final RestaurantModel casa;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final capa = casa.heroImageUrl?.trim().isNotEmpty == true
        ? casa.heroImageUrl!.trim()
        : casa.photoUrl.trim();

    return Padding(
      padding: const EdgeInsets.only(bottom: Spacing.md),
      child: Material(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        clipBehavior: Clip.antiAlias,
        elevation: 0,
        child: InkWell(
          onTap: onTap,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (capa.isNotEmpty)
                SizedBox(
                  height: 130,
                  child: CachedNetworkImage(
                    imageUrl: capa,
                    fit: BoxFit.cover,
                    placeholder: (_, __) =>
                        Container(color: AppColors.background),
                    errorWidget: (_, __, ___) =>
                        Container(color: AppColors.background),
                  ),
                ),
              Padding(
                padding: const EdgeInsets.all(12),
                child: Row(
                  children: [
                    if (casa.photoUrl.trim().isNotEmpty)
                      ClipRRect(
                        borderRadius: BorderRadius.circular(11),
                        child: CachedNetworkImage(
                          imageUrl: casa.photoUrl.trim(),
                          width: 46,
                          height: 46,
                          fit: BoxFit.cover,
                          errorWidget: (_, __, ___) => const SizedBox(
                              width: 46, height: 46),
                        ),
                      ),
                    const SizedBox(width: 11),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            casa.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                                fontSize: 15, fontWeight: FontWeight.w800),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            casa.address,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                                fontSize: 12,
                                color: AppColors.textSecondary),
                          ),
                          const SizedBox(height: 6),
                          Wrap(
                            spacing: 6,
                            runSpacing: 4,
                            children: [
                              if (casa.comingSoon)
                                const _Selo(
                                  texto: 'Em breve',
                                  fundo: Color(0xFFFFEDD5),
                                  cor: Color(0xFFC2410C),
                                ),
                              _Selo(
                                texto:
                                    'Encomenda ${kFestasAvisoHoras}h',
                                fundo: const Color(0xFFDCFCE7),
                                cor: const Color(0xFF15803D),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    Icon(Icons.chevron_right_rounded,
                        color: AppColors.textSecondary),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Selo extends StatelessWidget {
  const _Selo({required this.texto, required this.fundo, required this.cor});

  final String texto;
  final Color fundo;
  final Color cor;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: fundo,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        texto,
        style: TextStyle(
            fontSize: 10.5, fontWeight: FontWeight.w800, color: cor),
      ),
    );
  }
}

class _SemCasas extends StatelessWidget {
  const _SemCasas();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(Spacing.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.celebration_outlined,
                size: 56, color: AppColors.textSecondary.withValues(alpha: .4)),
            const SizedBox(height: Spacing.md),
            Text(
              'Ainda não há casas de festa por aqui.',
              textAlign: TextAlign.center,
              style: TextStyle(color: AppColors.textSecondary),
            ),
          ],
        ),
      ),
    );
  }
}
