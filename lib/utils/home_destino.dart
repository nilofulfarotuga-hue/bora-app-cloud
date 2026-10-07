import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../l10n/tr.dart';
import '../models/restaurant_model.dart';
import '../screens/client/assistant/assistant_chat_screen.dart';
import '../screens/client/cleaning/cleaning_bookings_screen.dart';
import '../screens/client/services/services_category_screen.dart';
import '../screens/client/tvde/tvde_entrada_screen.dart';
import '../screens/client_promo_code_screen.dart';
import '../screens/festas_screen.dart';
import '../screens/product_detail_screen.dart';
import '../screens/restaurants_screen.dart';
import '../screens/sobremesas_screen.dart';
import '../screens/stores_screen.dart';
import '../stores/cart_store.dart';
import '../stores/restaurant_store.dart';
import 'business_opener.dart';
import 'cozinhas.dart';

/// Para onde leva um toque numa faixa ou cartão da home / pesquisa (05/10).
/// Cada destino aterra na página certa de venda; a localização nunca trava.

void _aviso(BuildContext context, String msg) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(msg)));
}

/// Garante a lista de lojas carregada e devolve a loja pelo id.
Future<RestaurantModel?> _lojaPorId(BuildContext context, String id) async {
  final store = context.read<RestaurantStore>();
  RestaurantModel? achar() {
    for (final r in store.restaurants) {
      if (r.id == id) return r;
    }
    return null;
  }

  final ja = achar();
  if (ja != null || store.restaurantsLoadedOnce) return ja;
  await store.loadRestaurantsFromSupabase();
  return achar();
}

/// Loja pelo id, com a lista carregada se preciso (o Bora Assistente usa
/// isto para encher o carrinho de uma proposta).
Future<RestaurantModel?> lojaPorId(BuildContext context, String id) =>
    _lojaPorId(context, id);

/// Abre uma loja pelo mesmo caminho das listas (layout da categoria
/// principal, loja fechada visitável, "Em breve" com selo).
Future<void> abrirLoja(BuildContext context, RestaurantModel loja) =>
    openBusiness(context, context.read<RestaurantStore>(), loja);

Future<void> abrirLojaPorId(BuildContext context, String id) async {
  final loja = await _lojaPorId(context, id);
  if (!context.mounted) return;
  if (loja == null) {
    _aviso(context, 'Esta loja não está disponível de momento.'.tr);
    return;
  }
  await abrirLoja(context, loja);
}

/// Abre a loja do produto e, por cima, o próprio produto. Loja "Em breve":
/// o produto abre mas o carrinho recusa (regra já do CartStore).
Future<void> abrirProduto(BuildContext context, String productId) async {
  final store = context.read<RestaurantStore>();
  final produto = await store.fetchProductById(productId);
  if (!context.mounted) return;
  if (produto == null) {
    _aviso(context, 'Este produto já não está disponível.'.tr);
    return;
  }
  final loja = await _lojaPorId(context, produto.restaurantId);
  if (!context.mounted) return;
  if (loja == null) {
    _aviso(context, 'Esta loja não está disponível de momento.'.tr);
    return;
  }
  await abrirLoja(context, loja);
  if (!context.mounted) return;
  // Se o cliente recusou trocar de carrinho, a loja não abriu — pára aqui.
  if (context.read<CartStore>().vendorName != loja.name) return;
  Navigator.push(
    context,
    MaterialPageRoute(
      builder: (_) => ProductDetailScreen(
        product: produto,
        isPartnerStore: loja.isPartner,
      ),
    ),
  );
}

void abrirCozinha(BuildContext context, String cozinha) {
  Navigator.push(
    context,
    MaterialPageRoute(builder: (_) => RestaurantsScreen(cozinha: cozinha)),
  );
}

/// Categorias que uma faixa pode abrir. Chave em minúsculas sem acentos.
const Map<String, String> categoriasDestino = {
  'restaurantes': 'Restaurantes',
  'supermercados': 'Supermercados',
  'farmacia': 'Farmácia',
  'lojas': 'Lojas',
  'festas': 'Festas',
  'sobremesas': 'Sobremesas',
  'servicos': 'Beleza',
  'limpeza': 'Limpeza',
  'motorista': 'Bora Motorista',
};

Widget? _ecraCategoria(String chave) {
  switch (chave) {
    case 'restaurantes':
    case 'restaurant':
      return const RestaurantsScreen();
    case 'supermercados':
    case 'supermercado':
    case 'mercados':
    case 'supermarket':
      return const StoresScreen(initialCategory: BusinessCategory.supermarket);
    case 'farmacia':
    case 'farmacias':
    case 'pharmacy':
      return const StoresScreen(initialCategory: BusinessCategory.pharmacy);
    case 'lojas':
    case 'loja':
    case 'store':
      return const StoresScreen(initialCategory: BusinessCategory.store);
    case 'festas':
      return const FestasScreen();
    case 'sobremesas':
    case 'sobremesa':
      return const SobremesasScreen();
    case 'servicos':
    case 'beleza':
      return const ServicesCategoryScreen();
    case 'limpeza':
      return const CleaningBookingsScreen();
    case 'motorista':
    case 'tvde':
      // Passa pela porta: sem acesso mostra a categoria por descobrir.
      return const TvdeEntradaScreen();
    case 'assistente':
      // Bora Assistente (07/10): a faixa da home vem com
      // tipo_destino='categoria' (o CHECK de home_banners não aceita
      // 'assistente' como tipo) e destino='assistente'.
      return const AssistantChatScreen();
  }
  return null;
}

void abrirCategoria(BuildContext context, String categoria) {
  final ecra = _ecraCategoria(normalizarTexto(categoria));
  if (ecra == null) {
    _aviso(context, 'Esta secção não está disponível de momento.'.tr);
    return;
  }
  Navigator.push(context, MaterialPageRoute(builder: (_) => ecra));
}

/// Destino genérico de uma faixa.
Future<void> abrirDestino(
  BuildContext context, {
  required String tipo,
  required String destino,
}) async {
  final d = destino.trim();
  if (d.isEmpty) return;
  switch (tipo) {
    case 'loja':
      await abrirLojaPorId(context, d);
    case 'produto':
      await abrirProduto(context, d);
    case 'cozinha':
      abrirCozinha(context, d);
    case 'categoria':
      abrirCategoria(context, d);
    case 'codigo':
      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => ClientPromoCodeScreen(initialCode: d),
        ),
      );
    case 'assistente':
      // Bora Assistente (07/10): o destino leva a primeira mensagem
      // ("lista" abre o chat vazio).
      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => AssistantChatScreen(
            mensagemInicial: d == 'lista' ? null : d,
          ),
        ),
      );
  }
}
