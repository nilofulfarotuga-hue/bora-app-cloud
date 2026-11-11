import 'package:flutter/material.dart';

import '../../config/app_colors.dart';
import '../../config/business_rules.dart' show BRBusiness;
import '../../l10n/tr.dart';
import '../../models/order_model.dart';
import '../../utils/euros.dart';
import 'collect_badge.dart';

/// pagar-na-loja (10/11/2026, business_rules 2.4.2).
///
/// O SERVIDOR decide o que o estafeta faz na loja e grava-o no pedido
/// (`orders.loja_pagamento_estado` + `orders.loja_pagar_valor`, gatilho
/// `zzzz_orders_loja_pagamento`). Esta app só MOSTRA — nunca calcula dinheiro:
///
/// * `pagar_loja`  — app + loja parceira + dinheiro: paga o preço de balcão à
///   loja na recolha e cobra o total ao cliente (R1);
/// * `ja_pago`     — loja parceira com cartão/MB Way: não paga nem cobra (R2);
/// * `fazer_compra`— loja não parceira: faz a compra, como sempre (R3);
/// * `parceiro_chamou` — 2.4.1, fica como estava (R4);
/// * `ir_buscar`   — takeaway, sem estafeta (R5).
enum LojaPagamento { pagarLoja, jaPago, fazerCompra, parceiroChamou, irBuscar }

LojaPagamento? lojaPagamentoDe(String? valor) {
  switch (valor) {
    case 'pagar_loja':
      return LojaPagamento.pagarLoja;
    case 'ja_pago':
      return LojaPagamento.jaPago;
    case 'fazer_compra':
      return LojaPagamento.fazerCompra;
    case 'parceiro_chamou':
      return LojaPagamento.parceiroChamou;
    case 'ir_buscar':
      return LojaPagamento.irBuscar;
  }
  return null;
}

extension LojaPagamentoDoPedido on OrderModel {
  /// O que o estafeta faz na loja (null = pedido sem loja ou pedido antigo).
  LojaPagamento? get lojaPagamento => lojaPagamentoDe(lojaPagamentoEstado);
}

/// O estafeta ainda vai a caminho da loja / está na loja.
bool estafetaAntesDaRecolha(OrderModel o) =>
    o.status == OrderStatus.preparing ||
    o.status == OrderStatus.callingDriver ||
    o.status == OrderStatus.driverAccepted;

/// O estafeta já recolheu e vai a caminho do cliente.
bool estafetaAoCliente(OrderModel o) =>
    o.status == OrderStatus.pickedUp || o.status == OrderStatus.onTheWay;

/// Valor estimado da compra numa loja NÃO parceira — o mesmo número que a app
/// já mostrava ("Pagar ao balcão"): preço da loja sem os 15 %. Só leitura.
double? estimativaCompraLoja(OrderModel o) {
  if (o.items.isEmpty) return null;
  return o.items.fold<double>(
      0,
      (s, i) =>
          s +
          (i.basePrice ?? i.price / (1 + BRBusiness.NON_PARTNER_MARKUP_RATIO)) *
              i.quantity);
}

/// Linha curta e igual em todo o lado: cartão da oferta e lista de pedidos (a
/// notificação recebe a mesma frase pronta do servidor). null = pedido sem loja
/// (fica o que já havia).
String? linhaDinheiroEstafeta(OrderModel o) {
  final cobrar = eur(o.totalToCollectCash);
  switch (o.lojaPagamento) {
    case LojaPagamento.pagarLoja:
      return 'Pagas {0} na loja · Cobras {1}'
          .trArgs([eur(o.lojaPagarValor), cobrar]);
    case LojaPagamento.jaPago:
      return 'Já pago — não pagas nem cobras nada'.tr;
    case LojaPagamento.fazerCompra:
      return 'Fazes a compra'.tr;
    case LojaPagamento.parceiroChamou:
      return 'Pagas {0} na loja · Cobras {1}'.trArgs([cobrar, cobrar]);
    case LojaPagamento.irBuscar:
    case null:
      return null;
  }
}

/// Resumo do dinheiro para a lista e o cartão da oferta. Pedido com loja: a
/// linha nova. Pedido sem loja (favor, levar/enviar): o [CollectBadge] de
/// sempre, sem mudar nada.
class LojaDinheiroResumo extends StatelessWidget {
  const LojaDinheiroResumo({
    super.key,
    required this.order,
    this.approx = false,
    this.dense = false,
  });

  final OrderModel order;
  final bool approx;
  final bool dense;

  @override
  Widget build(BuildContext context) {
    final linha = linhaDinheiroEstafeta(order);
    if (linha == null) {
      return CollectBadge(
        state: order.paymentMethod == PaymentMethod.cash
            ? CollectState.collectCash
            : CollectState.paidOnline,
        amountCents: (order.totalToCollectCash * 100).round(),
        approx: approx,
        dense: dense,
      );
    }
    final verde = order.lojaPagamento == LojaPagamento.jaPago;
    final cor = verde ? AppColors.primary : Colors.orange.shade900;
    final row = Row(
      key: const Key('loja_dinheiro_resumo'),
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(verde ? Icons.check_circle_outline : Icons.payments_outlined,
            size: dense ? 16 : 18, color: cor),
        const SizedBox(width: 6),
        Flexible(
          child: Text(
            linha,
            style: TextStyle(
                color: cor,
                fontSize: dense ? 14 : 15,
                fontWeight: FontWeight.w800),
          ),
        ),
      ],
    );
    if (dense) return row;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: verde
            ? AppColors.primary.withValues(alpha: 0.10)
            : Colors.orange.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(8),
      ),
      child: row,
    );
  }
}

/// O que a faixa grande mostra (pura, para os testes).
typedef ConteudoFaixaDinheiro = ({
  Color cor,
  IconData icone,
  String titulo,
  String? sub,
});

/// Faixa GRANDE do dinheiro, sempre visível no mapa do estafeta (não precisa
/// de abrir o painel). Na loja diz quanto paga à loja; no cliente diz quanto
/// cobra — os números vêm todos do servidor.
class FaixaDinheiroEstafeta extends StatelessWidget {
  const FaixaDinheiroEstafeta({super.key, required this.order});

  final OrderModel order;

  /// Há alguma coisa a mostrar para este pedido nesta fase?
  static bool temFaixa(OrderModel o) => conteudo(o) != null;

  static ConteudoFaixaDinheiro? conteudo(OrderModel o) {
    // Favor tem o seu próprio passo-a-passo (folha do favor) — não mexer.
    if (o.serviceType == OrderServiceType.errand) return null;
    final loja = o.lojaPagamento;

    if (estafetaAntesDaRecolha(o)) {
      switch (loja) {
        case LojaPagamento.pagarLoja:
          return (
            cor: AppColors.accent,
            icone: Icons.storefront,
            titulo: 'PAGA {0} À LOJA'.trArgs([eur(o.lojaPagarValor)]),
            sub: 'Preço de balcão. É só isto que pagas. Depois cobras ao cliente.'.tr,
          );
        case LojaPagamento.jaPago:
          return (
            cor: AppColors.primary,
            icone: Icons.check_circle,
            titulo: 'JÁ ESTÁ PAGO — não pagas nada na loja'.tr,
            sub: null,
          );
        case LojaPagamento.fazerCompra:
          final est = estimativaCompraLoja(o);
          return (
            cor: AppColors.accent,
            icone: Icons.shopping_cart,
            titulo: 'TENS DE FAZER A COMPRA'.tr,
            sub: est == null
                ? 'Paga na caixa e tira foto do talão.'.tr
                : 'Paga na caixa e tira foto do talão. Valor estimado: {0}'
                    .trArgs([eur(est)]),
          );
        case LojaPagamento.parceiroChamou:
          // 2.4.1 — o banner de sempre, com o mesmo texto.
          return (
            cor: AppColors.primary,
            icone: Icons.storefront,
            titulo: 'PAGAR ${eur(o.totalToCollectCash)} AO ESTABELECIMENTO',
            sub: 'O cliente paga-te depois o mesmo valor em dinheiro. Ficas empatado — a Bora paga a tua corrida no fecho semanal.',
          );
        case LojaPagamento.irBuscar:
        case null:
          return null;
      }
    }

    if (estafetaAoCliente(o)) {
      if (o.paymentMethod == PaymentMethod.cash) {
        return (
          cor: AppColors.accent,
          icone: Icons.payments,
          titulo: 'COBRA {0} AO CLIENTE'.trArgs([eur(o.totalToCollectCash)]),
          sub: o.hasCashDebt
              ? 'inclui +{0} de dívida anterior'
                  .trArgs([eur(o.debtCollectedCents / 100.0)])
              : null,
        );
      }
      return (
        cor: AppColors.primary,
        icone: Icons.check_circle,
        titulo: 'JÁ ESTÁ PAGO — não cobres nada'.tr,
        sub: null,
      );
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final c = conteudo(order);
    if (c == null) return const SizedBox.shrink();
    return Semantics(
      container: true,
      label: c.sub == null ? c.titulo : '${c.titulo}. ${c.sub}',
      child: Container(
        key: const Key('faixa_dinheiro_estafeta'),
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: c.cor,
          borderRadius: BorderRadius.circular(14),
          boxShadow: const [
            BoxShadow(
                color: Color(0x40000000), blurRadius: 10, offset: Offset(0, 3)),
          ],
        ),
        child: Row(
          children: [
            Icon(c.icone, color: Colors.white, size: 34),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    c.titulo,
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w900,
                      fontSize: 22,
                      height: 1.15,
                      letterSpacing: 0.2,
                    ),
                  ),
                  if (c.sub != null) ...[
                    const SizedBox(height: 4),
                    Text(
                      c.sub!,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w600,
                        fontSize: 14,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
