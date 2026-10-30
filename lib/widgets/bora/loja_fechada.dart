import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../config/app_colors.dart';
import '../../config/app_spacing.dart';
import '../../l10n/tr.dart';
import '../../models/restaurant_model.dart';
import '../../stores/cart_store.dart';
import '../../stores/restaurant_store.dart';
import '../../utils/home_destino.dart';

/// LOJA FECHADA (melhorias-paridade 26/10, item 4 — regra do Danilo de 27/08).
///
/// O cliente entra numa loja fechada e vê tudo. Esta faixa diz logo, no topo,
/// que está fechada e a que horas abre. O travão é só ao pôr no carrinho
/// (`CartStore.lojaFechada`), e aí oferece "Ver lojas abertas parecidas".
class FaixaLojaFechada extends StatelessWidget {
  const FaixaLojaFechada({super.key, required this.loja});

  final RestaurantModel loja;

  @override
  Widget build(BuildContext context) {
    // A pausa do parceiro já tem o BannerPausaLoja: não duplicar.
    if (!loja.fechadaParaCliente || loja.emPausa()) return const SizedBox.shrink();
    // Agendar (30/10/2026): se o servidor dá janelas a esta loja, o cliente
    // pode encomendar já, para quando abrir (só com "Agendar").
    final cart = context.watch<CartStore?>();
    final agenda = cart != null &&
        cart.vendorRestaurantId == loja.id &&
        cart.agendamentoObrigatorio;
    return Container(
      width: double.infinity,
      color: AppColors.textPrimary.withValues(alpha: 0.85),
      padding: const EdgeInsets.symmetric(horizontal: Spacing.lg, vertical: Spacing.sm),
      child: Row(
        children: [
          Icon(agenda ? Icons.event : Icons.schedule, color: Colors.white, size: 18),
          const SizedBox(width: Spacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  loja.faixaFechada,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                    fontSize: 14,
                  ),
                ),
                if (agenda)
                  Text(
                    'Loja fechada: agenda para quando abrir'.tr,
                    key: const Key('faixa-fechada-agendar'),
                    style: const TextStyle(color: Colors.white, fontSize: 13),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Lojas da mesma secção que estão abertas agora (no máximo [limite]),
/// excluindo a própria. Pura, para se poder testar.
List<RestaurantModel> lojasAbertasParecidas(
  List<RestaurantModel> todas,
  RestaurantModel fechada, {
  DateTime? agora,
  int limite = 5,
}) {
  final instante = agora ?? DateTime.now();
  return todas
      .where((r) =>
          r.id != fechada.id &&
          !r.comingSoon &&
          r.belongsTo(fechada.category) &&
          !r.fechadaParaClienteEm(instante))
      .take(limite)
      .toList();
}

/// Folha "Lojas abertas parecidas". Tocar numa abre essa loja.
Future<void> mostrarLojasAbertasParecidas(
  BuildContext context,
  String restaurantId,
) async {
  final store = context.read<RestaurantStore>();
  final fechada = store.restaurantById(restaurantId);
  if (fechada == null) return;
  final abertas = lojasAbertasParecidas(store.restaurants, fechada);
  await showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    builder: (sheetCtx) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(Spacing.lg, 0, Spacing.lg, Spacing.lg),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Lojas abertas parecidas'.tr,
              style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: Spacing.sm),
            if (abertas.isEmpty)
              Text(
                'De momento não há lojas parecidas abertas.'.tr,
                style: const TextStyle(color: AppColors.textSecondary),
              )
            else
              for (final r in abertas)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.storefront_outlined, color: AppColors.primary),
                  title: Text(r.name),
                  subtitle: Text('Aberto'.tr),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () {
                    Navigator.of(sheetCtx).pop();
                    abrirLoja(context, r);
                  },
                ),
          ],
        ),
      ),
    ),
  );
}
