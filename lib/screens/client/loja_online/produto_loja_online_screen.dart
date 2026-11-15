// lib/screens/client/loja_online/produto_loja_online_screen.dart
//
// Ficha de um produto da Loja Online (15/11/2026, fechar-tudo-15-11 ponto E):
// fotografias, título, preço final (IVA e envio incluídos, já vem do servidor),
// o prazo em grande ("Chega pelo correio em X a Y dias úteis") e a descrição.
//
// Nesta primeira versão NÃO há pagamento (o dinheiro está só em relatório):
// o botão "Encomendar" fica desligado com a frase
// "Os pagamentos desta loja abrem em breve.". Quando a Claude.ai autorizar, o
// pagamento entra pelo mesmo caminho do Stripe já provado no delivery; aqui
// não se toca em preços, carrinho nem checkout.
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../../../config/app_colors.dart';
import '../../../config/app_spacing.dart';
import '../../../l10n/tr.dart';
import '../../../models/loja_online_produto.dart';
import '../../../widgets/bora/bora_screen_app_bar.dart';
import 'loja_online_screen.dart' show FotoLojaOnline;

class ProdutoLojaOnlineScreen extends StatefulWidget {
  const ProdutoLojaOnlineScreen({super.key, required this.produto});

  final LojaOnlineProduto produto;

  @override
  State<ProdutoLojaOnlineScreen> createState() =>
      _ProdutoLojaOnlineScreenState();
}

class _ProdutoLojaOnlineScreenState extends State<ProdutoLojaOnlineScreen> {
  final PageController _paginas = PageController();
  int _pagina = 0;

  @override
  void dispose() {
    _paginas.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = widget.produto;
    final prazo = p.prazoTexto;
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: BoraScreenAppBar(title: 'Loja Online'.tr),
      body: ListView(
        padding: const EdgeInsets.only(bottom: Spacing.xxl),
        children: [
          _Carrossel(
            imagens: p.imagens,
            controller: _paginas,
            pagina: _pagina,
            onPagina: (i) => setState(() => _pagina = i),
          ),
          Padding(
            padding: const EdgeInsets.all(Spacing.lg),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  p.titulo,
                  style: const TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textPrimary,
                  ),
                ),
                const SizedBox(height: Spacing.sm),
                Text(
                  p.precoTexto,
                  key: const Key('loja_online_preco'),
                  style: const TextStyle(
                    fontSize: 28,
                    fontWeight: FontWeight.w800,
                    color: AppColors.primary,
                  ),
                ),
                Text(
                  'Preço final, com IVA e envio incluídos'.tr,
                  style: const TextStyle(
                    fontSize: 13,
                    color: AppColors.textSecondary,
                  ),
                ),
                if (prazo.isNotEmpty) ...[
                  const SizedBox(height: Spacing.lg),
                  Container(
                    key: const Key('loja_online_prazo'),
                    padding: const EdgeInsets.all(Spacing.lg),
                    decoration: BoxDecoration(
                      color: AppColors.primaryWash,
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.local_shipping_outlined,
                            size: 28, color: AppColors.primary),
                        const SizedBox(width: Spacing.md),
                        Expanded(
                          child: Text(
                            prazo,
                            style: const TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w700,
                              color: AppColors.textPrimary,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
                if (p.descricao.isNotEmpty) ...[
                  const SizedBox(height: Spacing.xl),
                  Text(
                    'Sobre este produto'.tr,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  const SizedBox(height: Spacing.xs),
                  Text(
                    p.descricao,
                    style: const TextStyle(
                      fontSize: 15,
                      height: 1.4,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
              Spacing.lg, Spacing.sm, Spacing.lg, Spacing.lg),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                width: double.infinity,
                height: 52,
                child: FilledButton(
                  key: const Key('loja_online_encomendar'),
                  // Desligado de propósito: sem pagamento nesta versão.
                  onPressed: null,
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.accent,
                    disabledBackgroundColor: AppColors.divider,
                    disabledForegroundColor: AppColors.textSecondary,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14)),
                  ),
                  child: Text(
                    'Encomendar'.tr,
                    style: const TextStyle(
                        fontSize: 16, fontWeight: FontWeight.w700),
                  ),
                ),
              ),
              const SizedBox(height: Spacing.sm),
              Text(
                'Os pagamentos desta loja abrem em breve.'.tr,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 13,
                  color: AppColors.textSecondary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Carrossel extends StatelessWidget {
  const _Carrossel({
    required this.imagens,
    required this.controller,
    required this.pagina,
    required this.onPagina,
  });

  final List<String> imagens;
  final PageController controller;
  final int pagina;
  final ValueChanged<int> onPagina;

  @override
  Widget build(BuildContext context) {
    if (imagens.isEmpty) {
      return SizedBox(
        height: 260,
        child: Container(
          color: AppColors.primaryWash,
          alignment: Alignment.center,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.image_outlined,
                  size: 64,
                  color: AppColors.textSecondary.withValues(alpha: .5)),
              const SizedBox(height: Spacing.sm),
              Text(
                'Sem fotografia'.tr,
                style: const TextStyle(color: AppColors.textSecondary),
              ),
            ],
          ),
        ),
      );
    }
    return SizedBox(
      height: 300,
      child: Stack(
        children: [
          PageView.builder(
            controller: controller,
            itemCount: imagens.length,
            onPageChanged: onPagina,
            itemBuilder: (context, i) => CachedNetworkImage(
              imageUrl: imagens[i],
              fit: BoxFit.cover,
              placeholder: (_, __) => Container(color: AppColors.surface2),
              errorWidget: (_, __, ___) => const FotoLojaOnline(),
            ),
          ),
          if (imagens.length > 1)
            Positioned(
              left: 0,
              right: 0,
              bottom: Spacing.md,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  for (var i = 0; i < imagens.length; i++)
                    Container(
                      width: i == pagina ? 18 : 8,
                      height: 8,
                      margin: const EdgeInsets.symmetric(horizontal: 3),
                      decoration: BoxDecoration(
                        color: i == pagina
                            ? AppColors.primary
                            : Colors.white.withValues(alpha: .8),
                        borderRadius: BorderRadius.circular(999),
                      ),
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
