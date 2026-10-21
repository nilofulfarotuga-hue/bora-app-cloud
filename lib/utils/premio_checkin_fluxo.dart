// lib/utils/premio_checkin_fluxo.dart
//
// Usar um prémio de produto do check-in (Bloco D, 21/10/2026), igual ao padrão
// dos grandes: o vale aplica-se no carrinho da loja certa.
//  1. reserva o vale no servidor (60 min) e recebe o artigo-prémio a 0 €;
//  2. abre a loja pelo caminho normal (pergunta se troca de carrinho);
//  3. abre a ficha do prémio para escolher sabores/acompanhamentos.
// O vale só fica "usado" quando o pedido nasce (gatilho no servidor).
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../l10n/tr.dart';
import '../services/checkin_premios_service.dart';
import '../stores/cart_store.dart';
import '../widgets/checkin/premio_opcoes_sheet.dart';
import 'home_destino.dart';

void _aviso(BuildContext context, String msg) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(msg)));
}

/// A partir de "Os meus prémios": abre a loja e a ficha do prémio.
Future<void> usarPremioProduto(BuildContext context, CheckinVale vale) async {
  ReservaPremio? reserva;
  try {
    reserva = await CheckinPremiosService.instance.reservar(vale.id);
  } catch (e) {
    if (context.mounted) _aviso(context, mensagemErroPremio(e));
    return;
  }
  if (!context.mounted) return;
  if (reserva == null) {
    _aviso(context, 'Este prémio já não está disponível.'.tr);
    return;
  }
  final loja = await lojaPorId(context, reserva.lojaId);
  if (!context.mounted) return;
  if (loja == null) {
    await CheckinPremiosService.instance.libertar(vale.id);
    if (context.mounted) _aviso(context, 'Esta loja não está disponível de momento.'.tr);
    return;
  }
  await abrirLoja(context, loja);
  if (!context.mounted) return;
  // O cliente não quis trocar de carrinho: a loja não abriu, o vale volta.
  if (context.read<CartStore>().vendorRestaurantId != loja.id &&
      context.read<CartStore>().vendorName != loja.name) {
    await CheckinPremiosService.instance.libertar(vale.id);
    return;
  }
  final ok = await mostrarPremioOpcoes(context, reserva, lojaParceira: loja.isPartner);
  if (!context.mounted) return;
  if (ok) {
    _aviso(context, 'Prémio no carrinho. Pagas só a entrega e as taxas.'.tr);
  } else {
    await CheckinPremiosService.instance.libertar(vale.id);
  }
}

/// A partir do carrinho da loja certa: "Tens um prémio — Aplicar".
Future<bool> aplicarPremioNoCarrinho(BuildContext context, CheckinVale vale) async {
  ReservaPremio? reserva;
  try {
    reserva = await CheckinPremiosService.instance.reservar(vale.id);
  } catch (e) {
    if (context.mounted) _aviso(context, mensagemErroPremio(e));
    return false;
  }
  if (!context.mounted) return false;
  if (reserva == null) {
    _aviso(context, 'Este prémio já não está disponível.'.tr);
    return false;
  }
  final cart = context.read<CartStore>();
  final ok = await mostrarPremioOpcoes(context, reserva, lojaParceira: cart.isPartnerStore);
  if (!ok) await CheckinPremiosService.instance.libertar(vale.id);
  return ok;
}
