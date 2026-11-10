import 'package:flutter/material.dart';

import '../config/app_colors.dart';
import '../l10n/tr.dart';

// Alergénios em falta (missão fechar-tudo-2026-11-10, E6).
//
// Reg. (UE) 1169/2011, art. 14.º e 44.º, e DL 26/2016: na venda à distância a
// informação sobre os 14 alergénios tem de estar disponível ANTES da compra;
// para comida não pré-embalada pode ser dada pela loja, desde que se diga ao
// cliente como a obter. Enquanto o prato não tem os alergénios preenchidos
// (`products.allergens` vazio), a app diz para contactar a loja antes de
// pagar — na ficha do produto e no carrinho. As frases ficam escritas no
// widget (com `.tr`) para o dicionário inglês as apanhar.

/// O produto ainda não tem os alergénios preenchidos.
bool alergeniosEmFalta(List<String>? allergens) =>
    allergens == null || allergens.isEmpty;

/// Algum artigo do carrinho está sem os alergénios preenchidos? Um artigo que
/// não aparece no menu carregado conta como "sem informação".
bool carrinhoComAlergeniosEmFalta(
  Iterable<String> idsDosArtigos,
  Map<String, List<String>> alergeniosPorProduto,
) =>
    idsDosArtigos.any((id) => alergeniosEmFalta(alergeniosPorProduto[id]));

class AvisoAlergenios extends StatelessWidget {
  const AvisoAlergenios({super.key, this.noCarrinho = false});

  /// No carrinho junta uma segunda frase (há pratos sem a lista).
  final bool noCarrinho;

  @override
  Widget build(BuildContext context) {
    return Container(
      key: const ValueKey('aviso-alergenios'),
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.warning.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.warning.withValues(alpha: 0.45)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.info_outline, size: 18, color: AppColors.textPrimary),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Alergénios: contacta a loja antes de pagar.'.tr,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textPrimary,
                  ),
                ),
                if (noCarrinho) ...[
                  const SizedBox(height: 2),
                  Text(
                    'Há pratos sem a lista dos 14 alergénios. Se tens alergias ou intolerâncias, confirma com a loja antes de pagar.'.tr,
                    style: const TextStyle(
                      fontSize: 12,
                      color: AppColors.textSecondary,
                      height: 1.35,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}
