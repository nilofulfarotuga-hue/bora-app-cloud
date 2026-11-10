import 'package:flutter/material.dart';

import '../l10n/tr.dart';
import '../models/partner_product.dart' show kCentimosPorEmbalagemVolta;
import '../utils/euros.dart';

/// DEPÓSITO VOLTA (09/11/2026) — o depósito português das latas e garrafas
/// de plástico até 3 L: 0,10 € por embalagem, devolvido nas máquinas Volta.
///
/// Por lei vai numa linha À PARTE: fora do subtotal, sem markup, sem taxas e
/// sem tokens. Quem calcula e cobra é o SERVIDOR (`quote_order_pricing` e
/// `create_order`); a app só o mostra. Este ficheiro junta os textos para os
/// ecrãs dizerem todos o mesmo.
///
/// [DepositoVoltaNota] é a nota pequena e cinzenta por baixo do preço (ficha
/// do produto, cartões, linha do carrinho): "+0,10 € depósito Volta", ou
/// "+0,60 € depósito Volta (6 embalagens)" num pack. Com [unidades] a 0 não
/// desenha nada, por isso pode ficar sempre na árvore.
///
/// [compacta] (cartões de altura fixa dos carrosséis e da grelha): uma linha
/// só, letra 10, sem o número de embalagens ("+0,60 € depósito Volta"), que
/// encolhe em vez de cortar ou de empurrar o cartão.
class DepositoVoltaNota extends StatelessWidget {
  const DepositoVoltaNota({
    super.key,
    required this.unidades,
    this.margem,
    this.tamanho = 12,
    this.compacta = false,
  });

  /// O [preco] de um cartão com a nota [compacta] por baixo. Sem depósito
  /// devolve o [preco] tal e qual — o cartão fica exatamente como era.
  static Widget porBaixoDoPreco({
    required Widget preco,
    required int unidades,
  }) {
    if (unidades <= 0) return preco;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        preco,
        DepositoVoltaNota(unidades: unidades, compacta: true),
      ],
    );
  }

  /// Embalagens com depósito em UMA unidade do produto (1 lata, 6 num pack).
  final int unidades;

  /// Espaço à volta da nota (só quando aparece).
  final EdgeInsetsGeometry? margem;

  final double tamanho;
  final bool compacta;

  /// "+0,10 € depósito Volta" · "+0,60 € depósito Volta (6 embalagens)".
  static String texto(int unidades) {
    return unidades == 1
        ? textoCurto(unidades)
        : '+{0} depósito Volta ({1} embalagens)'
            .trArgs([_valor(unidades), unidades]);
  }

  /// Sem o número de embalagens: "+0,60 € depósito Volta".
  static String textoCurto(int unidades) =>
      '+{0} depósito Volta'.trArgs([_valor(unidades)]);

  static String _valor(int unidades) =>
      eurCents(unidades * kCentimosPorEmbalagemVolta);

  /// O nome da linha nos resumos: "Depósito Volta (3 embalagens)".
  static String rotulo(int unidades) {
    if (unidades <= 0) return 'Depósito Volta'.tr;
    return unidades == 1
        ? 'Depósito Volta (1 embalagem)'.tr
        : 'Depósito Volta ({0} embalagens)'.trArgs([unidades]);
  }

  @override
  Widget build(BuildContext context) {
    if (unidades <= 0) return const SizedBox.shrink();
    final cor = Colors.grey.shade600;
    final Widget nota = compacta
        ? FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              textoCurto(unidades),
              key: const Key('deposito_volta_nota'),
              maxLines: 1,
              softWrap: false,
              style: TextStyle(fontSize: 10, color: cor, height: 1.3),
            ),
          )
        : Text(
            texto(unidades),
            key: const Key('deposito_volta_nota'),
            style: TextStyle(fontSize: tamanho, color: cor, height: 1.3),
          );
    return margem == null ? nota : Padding(padding: margem!, child: nota);
  }
}
