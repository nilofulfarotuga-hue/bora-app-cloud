import 'package:flutter/material.dart';

import '../l10n/tr.dart';
import '../models/promocao.dart';
import '../services/promocoes_service.dart';
import '../utils/euros.dart';

/// O preço de um produto quando tem promoção ativa (adendo 5 · item 4):
/// preço novo em destaque, o antigo riscado ao lado e, por baixo, em pequeno,
/// a linha da Diretiva Omnibus "Preço mais baixo dos últimos 30 dias: X €".
///
/// Sem promoção ativa devolve [semPromocao] — exatamente o preço de sempre. O
/// interruptor geral e a prontidão do servidor são verificados no servidor
/// (`store_active_promotions` só devolve linhas quando as duas coisas estão
/// certas), por isso aqui basta olhar para o que a loja devolveu.
///
/// Quando a promoção não representa uma descida real em relação ao preço mais
/// baixo dos 30 dias (ver [vistaDaPromocao]), mostra-se só o preço que se paga,
/// sem riscado nem linha legal: exibido = cobrado.
class PrecoComPromocao extends StatefulWidget {
  const PrecoComPromocao({
    super.key,
    required this.restaurantId,
    required this.productId,
    required this.isPartnerStore,
    required this.semPromocao,
    required this.estiloPreco,
    this.compacto = true,
  });

  final String restaurantId;
  final String productId;
  final bool isPartnerStore;

  /// O que se mostra quando não há promoção (o widget de preço de sempre).
  final Widget semPromocao;

  /// Estilo do preço que se paga; o riscado e a linha legal derivam dele.
  final TextStyle estiloPreco;

  /// Cartões pequenos (true) ou a ficha do produto (false).
  final bool compacto;

  @override
  State<PrecoComPromocao> createState() => _PrecoComPromocaoState();
}

class _PrecoComPromocaoState extends State<PrecoComPromocao> {
  late final PromocoesLoja _loja = PromocoesLoja.instance;

  @override
  void initState() {
    super.initState();
    _loja.garantir(widget.restaurantId);
  }

  @override
  void didUpdateWidget(covariant PrecoComPromocao old) {
    super.didUpdateWidget(old);
    if (old.restaurantId != widget.restaurantId) {
      _loja.garantir(widget.restaurantId);
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _loja,
      builder: (context, _) {
        final p = _loja.de(widget.restaurantId, widget.productId);
        if (p == null) return widget.semPromocao;
        final v = vistaDaPromocao(p, lojaParceira: widget.isPartnerStore);
        final tamanho = widget.estiloPreco.fontSize ?? 13;
        final riscadoStyle = widget.estiloPreco.copyWith(
          fontSize: tamanho - (widget.compacto ? 1.5 : 2),
          fontWeight: FontWeight.w400,
          color: Colors.grey.shade600,
          decoration: TextDecoration.lineThrough,
        );
        final legalStyle = TextStyle(
          fontSize: widget.compacto ? 9.5 : 12,
          height: 1.2,
          color: Colors.grey.shade600,
        );
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Wrap(
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 6,
              children: [
                Text(eur(v.atual),
                    key: const Key('promo_preco_atual'),
                    style: widget.estiloPreco),
                if (v.riscado != null)
                  Semantics(
                    label: 'Antes {0}'.trArgs([eur(v.riscado!)]),
                    child: ExcludeSemantics(
                      child: Text(eur(v.riscado!),
                          key: const Key('promo_preco_riscado'),
                          style: riscadoStyle),
                    ),
                  ),
              ],
            ),
            if (v.maisBaixo30d != null)
              Padding(
                padding: const EdgeInsets.only(top: 1),
                child: Text(
                  'Preço mais baixo dos últimos 30 dias: {0}'
                      .trArgs([eur(v.maisBaixo30d!)]),
                  key: const Key('promo_omnibus'),
                  style: legalStyle,
                ),
              ),
          ],
        );
      },
    );
  }
}

/// Altura de um carrossel de cartões: a normal, ou um pouco mais alta quando
/// algum produto da fila tem promoção ativa (a linha dos 30 dias ocupa mais
/// duas ou três linhas e o cartão não pode ficar cortado). Sem promoção devolve
/// exatamente a altura de sempre.
class AlturaCarrosselPromocao extends StatelessWidget {
  const AlturaCarrosselPromocao({
    super.key,
    required this.restaurantId,
    required this.produtosIds,
    required this.altura,
    required this.child,
    this.extra = 30,
  });

  final String restaurantId;
  final List<String> produtosIds;
  final double altura;
  final double extra;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final loja = PromocoesLoja.instance;
    return ListenableBuilder(
      listenable: loja,
      builder: (context, _) {
        final tem = produtosIds.any((id) => loja.de(restaurantId, id) != null);
        return SizedBox(height: altura + (tem ? extra : 0), child: child);
      },
    );
  }
}
