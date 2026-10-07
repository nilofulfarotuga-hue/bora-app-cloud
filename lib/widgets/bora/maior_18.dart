// Missão maiores-18 (07/10/2026) — tabaco e bebidas alcoólicas com verificação
// de idade na entrega, igual à Glovo e à Uber Eats.
//
// Três peças partilhadas por todos os ecrãs (cliente, estafeta):
//   - [Maior18Badge]  etiqueta pequena "+18" (fundo preto, texto branco) no
//                     canto da foto dos cartões de produto;
//   - [Maior18Aviso]  cartão âmbar persistente (carrinho, pagamento, favores);
//   - [Maior18Linha]  linha informativa na ficha do produto.
//
// Só skin: a marca `age_restricted` vem do servidor (trigger + classificador).
import 'package:flutter/material.dart';

import '../../l10n/tr.dart';

/// Etiqueta "+18" no canto da foto. Fundo preto, texto branco, como nas apps
/// de referência. [small] para miniaturas de 64 px.
class Maior18Badge extends StatelessWidget {
  const Maior18Badge({super.key, this.small = false});

  final bool small;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'Só para maiores de 18 anos'.tr,
      child: Container(
        padding: EdgeInsets.symmetric(
          horizontal: small ? 4 : 6,
          vertical: small ? 1 : 2,
        ),
        decoration: BoxDecoration(
          color: Colors.black,
          borderRadius: BorderRadius.circular(4),
        ),
        child: Text(
          '+18',
          style: TextStyle(
            fontSize: small ? 9 : 10,
            fontWeight: FontWeight.w800,
            color: Colors.white,
            letterSpacing: 0.3,
            height: 1.2,
          ),
        ),
      ),
    );
  }
}

/// Cartão âmbar persistente: "este pedido tem artigos para maiores de 18".
/// [texto] permite reutilizar nos Favores com a mesma frase ou noutra.
class Maior18Aviso extends StatelessWidget {
  const Maior18Aviso({super.key, this.texto, this.margin});

  final String? texto;
  final EdgeInsetsGeometry? margin;

  static String get textoPedido =>
      'Este pedido tem artigos para maiores de 18: terás de mostrar documento de identificação ao estafeta.'
          .tr;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: margin,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.amber.shade50,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.amber.shade300),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Maior18Badge(),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              texto ?? textoPedido,
              style: TextStyle(
                fontSize: 13,
                height: 1.35,
                color: Colors.brown.shade800,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Linha na ficha do produto: "Só para maiores de 18 anos. O estafeta pede
/// documento na entrega."
class Maior18Linha extends StatelessWidget {
  const Maior18Linha({super.key});

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Maior18Badge(),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            'Só para maiores de 18 anos. O estafeta pede documento na entrega.'
                .tr,
            style: TextStyle(
              fontSize: 13,
              height: 1.35,
              color: Colors.grey.shade800,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ],
    );
  }
}
