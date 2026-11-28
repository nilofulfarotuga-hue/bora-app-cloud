import 'package:flutter/material.dart';

import '../config/app_colors.dart';
import '../config/app_spacing.dart';
import '../l10n/tr.dart';

/// A primeira escolha da Limpeza (28/11/2026, redesenho didático): três cartões grandes,
/// com um título de gente e o preço grande. Devolve 'uma_vez', 'plano' ou 'empresa'.
/// Os preços "desde" são os mesmos que já estavam no ecrã (casa 12 €/h, plano 9,80 €/h,
/// empresas 12 €/h); o preço de cada marcação vem sempre do servidor.
class EscolhaTipoLimpeza extends StatelessWidget {
  const EscolhaTipoLimpeza({super.key, required this.onEscolha});
  final ValueChanged<String> onEscolha;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(Spacing.lg, 0, Spacing.lg, Spacing.lg),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text('Que limpeza queres?'.tr,
              style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w800, color: AppColors.textPrimary)),
          const SizedBox(height: Spacing.lg),
          _Cartao(
            key: const Key('limpeza-escolha-uma-vez'),
            icone: Icons.cleaning_services,
            titulo: 'Só uma vez'.tr,
            texto: 'Escolhes o dia. Pagas com cartão, MB Way ou dinheiro.'.tr,
            preco: 'desde 12 €/h'.tr,
            onTap: () => onEscolha('uma_vez'),
          ),
          const SizedBox(height: Spacing.md),
          _Cartao(
            key: const Key('limpeza-escolha-plano'),
            icone: Icons.event_repeat,
            titulo: 'Todas as semanas, mais barato'.tr,
            texto: 'A mesma profissional. Pagas no cartão e cancelas quando quiseres.'.tr,
            preco: 'desde 9,80 €/h'.tr,
            selo: 'Popular'.tr,
            onTap: () => onEscolha('plano'),
          ),
          const SizedBox(height: Spacing.md),
          _Cartao(
            key: const Key('limpeza-escolha-empresa'),
            icone: Icons.storefront,
            titulo: 'Para a minha loja ou empresa'.tr,
            texto: 'Lojas, escritórios, cafés. À hora que quiseres, com produtos incluídos.'.tr,
            preco: 'desde 12 €/h'.tr,
            onTap: () => onEscolha('empresa'),
          ),
        ]),
      );
}

class _Cartao extends StatelessWidget {
  const _Cartao({
    super.key,
    required this.icone,
    required this.titulo,
    required this.texto,
    required this.preco,
    required this.onTap,
    this.selo,
  });
  final IconData icone;
  final String titulo;
  final String texto;
  final String preco;
  final String? selo;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Semantics(
        button: true,
        child: Material(
          color: AppColors.card,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: const BorderSide(color: AppColors.dividerStrong, width: 1.5),
          ),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.all(Spacing.lg),
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Container(
                  width: 52,
                  height: 52,
                  decoration: const BoxDecoration(color: AppColors.primaryWash, shape: BoxShape.circle),
                  child: Icon(icone, color: AppColors.primary, size: 28),
                ),
                const SizedBox(width: Spacing.md),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Wrap(spacing: Spacing.sm, runSpacing: Spacing.xs, crossAxisAlignment: WrapCrossAlignment.center, children: [
                      Text(titulo, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: AppColors.textPrimary, height: 1.25)),
                      if (selo != null)
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: Spacing.sm, vertical: 2),
                          decoration: BoxDecoration(color: AppColors.accent, borderRadius: BorderRadius.circular(Radii.pill)),
                          child: Text(selo!, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: Colors.white)),
                        ),
                    ]),
                    const SizedBox(height: Spacing.xs),
                    Text(texto, style: const TextStyle(fontSize: 16, color: AppColors.textSecondary, height: 1.35)),
                    const SizedBox(height: Spacing.sm),
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerLeft,
                      child: Text(preco, maxLines: 1, softWrap: false,
                          style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: AppColors.primaryDark)),
                    ),
                  ]),
                ),
              ]),
            ),
          ),
        ),
      );
}
