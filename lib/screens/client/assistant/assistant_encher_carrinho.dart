// BORA ASSISTENTE (07/10/2026) — "Encher o carrinho" a partir de uma proposta.
//
// Faz EXACTAMENTE o que a loja faz quando o cliente entra por ela:
//   1. abre a loja pelo caminho normal (`abrirLoja` → openBusiness), que já
//      pergunta se há carrinho de outra loja e configura a sessão do
//      CartStore (tipo de serviço, parceiro, coordenadas, loja fechada);
//   2. mete cada artigo com o MESMO CartItem dos ecrãs de produto
//      (price = PricingService.applyMarkup(base, isPartner); basePrice = puro);
//   3. abre o carrinho e guarda a proposta como pendente até o pedido nascer.
//
// Não recalcula nada do servidor: o markup é o mesmo dos call-sites actuais.

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../l10n/tr.dart';
import '../../../models/cart_item.dart';
import '../../../services/assistant_service.dart';
import '../../../services/pricing_service.dart';
import '../../../stores/cart_store.dart';
import '../../../utils/home_destino.dart';
import '../../../widgets/bora/coming_soon.dart';
import '../../cart_screen.dart';

void _aviso(BuildContext context, String msg) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(msg)));
}

/// Devolve `true` se o carrinho ficou cheio e o ecrã do carrinho abriu.
Future<bool> encherCarrinhoDaProposta(
  BuildContext context,
  AssistantProposal proposta,
) async {
  if (proposta.items.isEmpty) {
    _aviso(context, 'Esta proposta não tem artigos.'.tr);
    return false;
  }

  // Marca "abri o carrinho" sem esperar — a UI não depende disto.
  // ignore: unawaited_futures
  AssistantService.marcarProposta(proposta.proposalId, 'opened');

  final loja = await lojaPorId(context, proposta.restaurantId);
  if (!context.mounted) return false;
  if (loja == null) {
    _aviso(context, 'Esta loja não está disponível de momento.'.tr);
    return false;
  }

  // Caminho normal da loja: diálogo de carrinho activo + configureSession +
  // ecrã da loja por baixo (para o cliente poder acrescentar coisas).
  await abrirLoja(context, loja);
  if (!context.mounted) return false;

  final cart = context.read<CartStore>();
  // Se recusou trocar de carrinho, a loja não abriu — pára aqui.
  if (cart.vendorName != loja.name) return false;

  if (cart.lojaFechada) {
    showLojaFechadaSnackBar(context, cart.avisoLojaFechada);
    return false;
  }

  var metidos = 0;
  for (final it in proposta.items) {
    if (it.productId.isEmpty || it.productId.contains(' ')) continue;
    final base = it.basePrice;
    final price = base == null
        ? it.unitPrice
        : PricingService.applyMarkup(base, loja.isPartner);
    if (price <= 0) continue;
    try {
      cart.addItem(CartItem(
        productId: it.productId,
        name: it.name,
        price: price,
        basePrice: base,
        quantity: it.quantity,
      ));
      metidos++;
    } catch (e) {
      debugPrint('[Assistente] item ignorado ${it.productId}: $e');
    }
  }

  if (metidos == 0) {
    _aviso(context, 'Não consegui meter os artigos no carrinho.'.tr);
    return false;
  }

  await AssistantService.guardarPropostaPendente(proposta.proposalId);
  if (!context.mounted) return false;

  _aviso(context, '{0} artigos no carrinho'.trArgs([metidos]));
  await Navigator.push(
    context,
    MaterialPageRoute(builder: (_) => const CartScreen()),
  );
  return true;
}
