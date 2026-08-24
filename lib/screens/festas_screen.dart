import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../config/app_colors.dart';
import '../config/app_spacing.dart';
import '../config/festas_preview.dart';
import '../models/restaurant_model.dart';
import '../stores/restaurant_store.dart';
import '../utils/business_opener.dart';
import '../widgets/bora/bora_screen_app_bar.dart';
import '../widgets/bora_support_fab.dart';
import 'festas_painel_loja_screen.dart';
import 'restaurants_screen.dart' show RestaurantTile;

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
      // Preview pública: comutador para o lado da loja, sem login.
      // Num build normal kFestasPreview é false e nada disto aparece.
      bottomNavigationBar: !kFestasPreview
          ? null
          : SafeArea(
              minimum: const EdgeInsets.fromLTRB(
                  Spacing.lg, 0, Spacing.lg, Spacing.sm),
              child: TextButton.icon(
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute(
                      builder: (_) => const FestasPainelLojaScreen()),
                ),
                icon: const Icon(Icons.storefront_rounded, size: 17),
                label: const Text('Painel da loja',
                    style: TextStyle(
                        fontSize: 12.5, fontWeight: FontWeight.w800)),
                style: TextButton.styleFrom(
                  foregroundColor: AppColors.textSecondary,
                ),
              ),
            ),
      body: casas.isEmpty
          ? const _SemCasas()
          : ListView.builder(
              padding: const EdgeInsets.fromLTRB(
                  Spacing.lg, Spacing.md, Spacing.lg, Spacing.xxl),
              itemCount: casas.length + 1,
              itemBuilder: (context, index) {
                if (index == 0) return const _Cabecalho();
                final casa = casas[index - 1];
                // Mesmo cartão da lista de Restaurantes: logo, nome e selos.
                // O que é próprio das Festas (aviso das 48h, sabores, data)
                // aparece dentro da loja, não na lista.
                return RestaurantTile(
                  business: casa,
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
