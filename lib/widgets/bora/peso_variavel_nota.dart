import 'package:flutter/material.dart';

import '../../l10n/tr.dart';

/// Nota pequena e discreta dos produtos ao quilo dos mercados NÃO-parceiros
/// (`products.variable_weight`, 31/10/2026): fruta, legumes, talho, peixaria.
///
/// O cliente continua a pedir por unidades ("4 bananas"); o preço mostrado é
/// aproximado e o estafeta pesa e escreve o valor da balança. Só desenha
/// alguma coisa quando [variableWeight] é true — nos outros produtos devolve
/// um `SizedBox.shrink()`, por isso pode ficar sempre na árvore.
///
/// Duas formas:
///   - normal (ficha do produto, carrinho): ícone de balança + a frase toda
///     "Preço aproximado · o valor final depende do peso". Usa um Expanded:
///     pôr numa coluna com largura limitada (nunca solta numa Row);
///   - [compacta] (selo por cima da foto dos cartões de altura fixa): ícone +
///     "Preço aproximado" numa pastilha branca, para não empurrar o cartão.
///
/// Não confundir com `sold_by_weight` (porções de 200 g dos parceiros, ver
/// `WeightPriceText`).
class PesoVariavelNota extends StatelessWidget {
  const PesoVariavelNota({
    super.key,
    required this.variableWeight,
    this.compacta = false,
    this.margem,
  });

  final bool variableWeight;
  final bool compacta;

  /// Espaço à volta da nota (só quando aparece).
  final EdgeInsetsGeometry? margem;

  /// A frase toda, já no idioma ativo.
  static String get texto =>
      'Preço aproximado · o valor final depende do peso'.tr;

  /// A frase curta do selo dos cartões, já no idioma ativo.
  static String get textoCurto => 'Preço aproximado'.tr;

  static const IconData icone = Icons.scale_outlined;

  @override
  Widget build(BuildContext context) {
    if (!variableWeight) return const SizedBox.shrink();
    final cor = Colors.grey.shade600;

    final Widget conteudo;
    if (compacta) {
      conteudo = Container(
        key: const Key('peso_variavel_selo'),
        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.92),
          borderRadius: BorderRadius.circular(4),
        ),
        // Sem Flexible de propósito: um Positioned só com right/bottom dá
        // largura sem limite ao filho, e um filho flexível aí rebenta. A
        // frase curta cabe sempre; o cartão corta o que passar (antiAlias).
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icone, size: 11, color: cor),
            const SizedBox(width: 3),
            Text(
              textoCurto,
              maxLines: 1,
              softWrap: false,
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w600,
                color: cor,
                height: 1.2,
              ),
            ),
          ],
        ),
      );
    } else {
      conteudo = Row(
        key: const Key('peso_variavel_nota'),
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 1),
            child: Icon(icone, size: 14, color: cor),
          ),
          const SizedBox(width: 4),
          Expanded(
            child: Text(
              texto,
              style: TextStyle(fontSize: 12, color: cor, height: 1.3),
            ),
          ),
        ],
      );
    }

    final m = margem;
    return m == null ? conteudo : Padding(padding: m, child: conteudo);
  }
}
