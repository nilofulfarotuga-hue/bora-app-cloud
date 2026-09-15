import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../config/app_colors.dart';
import '../config/app_spacing.dart';
import '../models/restaurant_model.dart';
import '../stores/restaurant_store.dart';
import '../utils/business_opener.dart';
import '../widgets/bora/bora_screen_app_bar.dart';
import '../widgets/bora_support_fab.dart';
import 'restaurants_screen.dart' show RestaurantTile;

import '../l10n/tr.dart';

/// Categoria **Sobremesas** (2026-08-27) — açaí, gelados e doces.
///
/// É só um filtro visual: o fluxo de compra é o de entrega NORMAL, imediato.
/// Nada de calendário, nada de encomenda com antecedência — não copiar as
/// Festas.
///
/// Lista, com o MESMO filtro que já põe o Sabores de Casa dentro de Mercados,
/// os negócios com `category = 'sobremesa'` **ou** com `sobremesa` em
/// `extra_categories`. É por aqui que a Goola Açaí aparece nas Sobremesas sem
/// deixar de aparecer nos Restaurantes.
class SobremesasScreen extends StatelessWidget {
  const SobremesasScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final restaurantStore = context.watch<RestaurantStore>();
    final lojas = restaurantStore.restaurants
        .where((b) => b.belongsTo(BusinessCategory.sobremesa))
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
      appBar: BoraScreenAppBar(title: 'Sobremesas'.tr),
      body: lojas.isEmpty
          ? const _SemLojas()
          : ListView.builder(
              padding: const EdgeInsets.fromLTRB(
                  Spacing.lg, Spacing.md, Spacing.lg, Spacing.xxl),
              itemCount: lojas.length + 1,
              itemBuilder: (context, index) {
                if (index == 0) return const _Cabecalho();
                final loja = lojas[index - 1];
                // Mesmo cartão da lista de Restaurantes: logo, nome e selos.
                return RestaurantTile(
                  business: loja,
                  onTap: () => openBusiness(context, restaurantStore, loja),
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
        'Açaí, gelados e doces. Entrega normal, na hora.'.tr,
        style: const TextStyle(fontSize: 13, color: AppColors.textSecondary),
      ),
    );
  }
}

class _SemLojas extends StatelessWidget {
  const _SemLojas();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(Spacing.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.icecream_outlined,
                size: 56, color: AppColors.textSecondary.withValues(alpha: .4)),
            const SizedBox(height: Spacing.md),
            Text(
              'Ainda não há sobremesas por aqui.'.tr,
              textAlign: TextAlign.center,
              style: const TextStyle(color: AppColors.textSecondary),
            ),
          ],
        ),
      ),
    );
  }
}
