import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../config/app_colors.dart';
import '../config/app_spacing.dart';
import '../stores/services_store.dart';
import 'client/services/provider_detail_screen.dart';
import 'market/market_store_screen.dart';

import '../l10n/tr.dart';

/// Ponto de entrada para links vindos de fora: o site, um QR, o WhatsApp.
///
/// URLs canónicas (o site depende delas — não renomear):
///   https://bora-app-web.pages.dev/#/loja/{restaurant_id}
///   https://bora-app-web.pages.dev/#/servico/{service_provider_id}
///
/// A leitura é pública: quem não tem sessão vê a ficha na mesma. Só ao tocar
/// em marcar/pedir é que é encaminhado para o registo — e aí o destino fica
/// guardado em [DestinoPendente] para voltar aqui e não à home.
class DeepLinkStoreScreen extends StatefulWidget {
  const DeepLinkStoreScreen({super.key, required this.tipo, required this.id});

  /// 'loja' (restaurants) ou 'servico' (service_providers).
  final String tipo;
  final String id;

  static const String prefixoLoja = '/loja/';
  static const String prefixoServico = '/servico/';

  @override
  State<DeepLinkStoreScreen> createState() => _DeepLinkStoreScreenState();
}

class _DeepLinkStoreScreenState extends State<DeepLinkStoreScreen> {
  late Future<Widget> _destino;

  @override
  void initState() {
    super.initState();
    _destino = _carregar();
  }

  Future<Widget> _carregar() async {
    if (widget.tipo == 'servico') {
      final p = await context.read<ServicesStore>().fetchProviderDetail(widget.id);
      if (p == null) return _naoEncontrado('Não encontrámos este serviço.'.tr);
      return ProviderDetailScreen(provider: p);
    }

    // Loja: o MarketStoreScreen só precisa de id, nome e se é parceiro —
    // não é preciso construir o modelo inteiro.
    final linha = await Supabase.instance.client
        .from('restaurants')
        .select('id, name, is_partner, approval_status')
        .eq('id', widget.id)
        .maybeSingle();

    if (linha == null || linha['approval_status'] != 'approved') {
      return _naoEncontrado('Não encontrámos esta loja.'.tr);
    }
    return MarketStoreScreen(
      restaurantId: widget.id,
      storeName: (linha['name'] ?? 'Loja').toString(),
      isPartnerStore: linha['is_partner'] == true,
    );
  }

  Widget _naoEncontrado(String mensagem) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(Spacing.lg),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.storefront_outlined,
                    size: 56, color: AppColors.textSecondary),
                const SizedBox(height: Spacing.md),
                Text(
                  mensagem,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textPrimary,
                  ),
                ),
                const SizedBox(height: Spacing.sm),
                Text(
                  'Pode ter mudado de morada ou já não estar disponível.'.tr,
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: AppColors.textSecondary),
                ),
                const SizedBox(height: Spacing.lg),
                FilledButton(
                  onPressed: () =>
                      Navigator.of(context).popUntil((r) => r.isFirst),
                  child: Text('Ver tudo o que há no Bora'.tr),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Widget>(
      future: _destino,
      builder: (context, snap) {
        if (snap.connectionState != ConnectionState.done) {
          return const Scaffold(
            backgroundColor: AppColors.surface,
            body: Center(
              child: CircularProgressIndicator(color: AppColors.primary),
            ),
          );
        }
        if (snap.hasError) {
          return _naoEncontrado('Não foi possível abrir esta página.'.tr);
        }
        return snap.data!;
      },
    );
  }
}
