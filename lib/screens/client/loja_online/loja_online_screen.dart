// lib/screens/client/loja_online/loja_online_screen.dart
//
// Categoria **Loja Online** (15/11/2026, fechar-tudo-15-11 ponto E, caixa 10):
// os produtos da loja Shopify da Bora, enviados pelo correio pelo fornecedor,
// dentro da app. No topo a "Novidade da semana" (os destaques do nicho da
// semana) e por baixo cada nicho com os seus produtos em grelha.
//
// Só aparece com `loja_online_ativa` ligado no painel (nasce desligado). Com o
// interruptor desligado ou as tabelas por instalar mostra "Em breve", calmo.
// Nesta versão não há pagamento: a ficha do produto tem o botão desligado.
// Um laranja só: a etiqueta "Novidade da semana".
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../../../config/app_colors.dart';
import '../../../config/app_spacing.dart';
import '../../../l10n/tr.dart';
import '../../../models/loja_online_produto.dart';
import '../../../services/loja_online_service.dart';
import '../../../widgets/bora/bora_screen_app_bar.dart';
import 'produto_loja_online_screen.dart';

class LojaOnlineScreen extends StatefulWidget {
  const LojaOnlineScreen({super.key, this.service});

  /// Por omissão [LojaOnlineService.instance]. Existe para os testes.
  final LojaOnlineService? service;

  @override
  State<LojaOnlineScreen> createState() => _LojaOnlineScreenState();
}

class _LojaOnlineScreenState extends State<LojaOnlineScreen> {
  late final LojaOnlineService _service;
  late Future<LojaOnlineCatalogo> _futuro;

  @override
  void initState() {
    super.initState();
    _service = widget.service ?? LojaOnlineService.instance;
    _futuro = _service.carregar();
  }

  void _recarregar() {
    setState(() => _futuro = _service.carregar(forcar: true));
  }

  void _abrirProduto(LojaOnlineProduto p) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => ProdutoLojaOnlineScreen(produto: p)),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: BoraScreenAppBar(title: 'Loja Online'.tr),
      body: FutureBuilder<LojaOnlineCatalogo>(
        future: _futuro,
        builder: (context, snap) {
          if (snap.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          final catalogo = snap.data;
          if (catalogo == null || snap.hasError) {
            return _Aviso.erro(onTentar: _recarregar);
          }
          switch (catalogo.estado) {
            case LojaOnlineEstado.desligada:
            case LojaOnlineEstado.emBreve:
              return const _EmBreve();
            case LojaOnlineEstado.erro:
              return _Aviso.erro(onTentar: _recarregar);
            case LojaOnlineEstado.pronta:
              break;
          }
          final vitrine = catalogo.vitrine;
          if (vitrine.vazia) return const _Aviso.vazia();
          return _Vitrine(vitrine: vitrine, onAbrir: _abrirProduto);
        },
      ),
    );
  }
}

class _Vitrine extends StatelessWidget {
  const _Vitrine({required this.vitrine, required this.onAbrir});

  final LojaOnlineVitrine vitrine;
  final ValueChanged<LojaOnlineProduto> onAbrir;

  @override
  Widget build(BuildContext context) {
    final nichoSemana = vitrine.nichoDaSemana;
    return ListView(
      padding: const EdgeInsets.fromLTRB(
          Spacing.lg, Spacing.md, Spacing.lg, Spacing.xxl),
      children: [
        Text(
          'Produtos da nossa loja, enviados pelo correio para a tua casa.'.tr,
          style: const TextStyle(
            fontSize: 14,
            color: AppColors.textSecondary,
          ),
        ),
        if (vitrine.novidade.isNotEmpty && nichoSemana != null) ...[
          const SizedBox(height: Spacing.lg),
          _TituloNovidade(nicho: nichoSemana),
          const SizedBox(height: Spacing.md),
          SizedBox(
            height: 236,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: vitrine.novidade.length,
              separatorBuilder: (_, __) => const SizedBox(width: Spacing.md),
              itemBuilder: (context, i) => SizedBox(
                width: 164,
                child: _ProdutoCard(
                  produto: vitrine.novidade[i],
                  onTap: () => onAbrir(vitrine.novidade[i]),
                ),
              ),
            ),
          ),
        ],
        for (final grupo in vitrine.porNicho) ...[
          const SizedBox(height: Spacing.xl),
          Text(
            grupo.nicho.nome,
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w700,
              color: AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: Spacing.md),
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: grupo.produtos.length,
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2,
              mainAxisSpacing: Spacing.md,
              crossAxisSpacing: Spacing.md,
              childAspectRatio: 0.72,
            ),
            itemBuilder: (context, i) => _ProdutoCard(
              produto: grupo.produtos[i],
              onTap: () => onAbrir(grupo.produtos[i]),
            ),
          ),
        ],
      ],
    );
  }
}

/// Etiqueta laranja "Novidade da semana" + nome do nicho. O único laranja.
class _TituloNovidade extends StatelessWidget {
  const _TituloNovidade({required this.nicho});

  final LojaOnlineNicho nicho;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.symmetric(
              horizontal: Spacing.md, vertical: Spacing.xs),
          decoration: BoxDecoration(
            color: AppColors.accent,
            borderRadius: BorderRadius.circular(999),
          ),
          child: Text(
            'Novidade da semana'.tr,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        const SizedBox(width: Spacing.md),
        Expanded(
          child: Text(
            nicho.nome,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w700,
              color: AppColors.textPrimary,
            ),
          ),
        ),
      ],
    );
  }
}

class _ProdutoCard extends StatelessWidget {
  const _ProdutoCard({required this.produto, required this.onTap});

  final LojaOnlineProduto produto;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(16),
        boxShadow: AppColors.shadowCard,
      ),
      clipBehavior: Clip.antiAlias,
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          onTap: onTap,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(child: FotoLojaOnline(url: produto.fotoPrincipal)),
              Padding(
                padding: const EdgeInsets.all(10),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      produto.titulo,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 13,
                        height: 1.2,
                        fontWeight: FontWeight.w600,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    const SizedBox(height: Spacing.xs),
                    Text(
                      produto.precoTexto,
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: AppColors.primary,
                      ),
                    ),
                    const SizedBox(height: Spacing.xs),
                    Row(
                      children: [
                        const Icon(Icons.local_shipping_outlined,
                            size: 14, color: AppColors.textSecondary),
                        const SizedBox(width: Spacing.xs),
                        Expanded(
                          child: Text(
                            'Enviado pelo correio'.tr,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 11,
                              color: AppColors.textSecondary,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Fotografia do produto (cache) ou um fundo neutro com ícone quando não há.
/// Partilhada com a ficha do produto.
class FotoLojaOnline extends StatelessWidget {
  const FotoLojaOnline({super.key, this.url, this.tamanhoIcone = 40});

  final String? url;
  final double tamanhoIcone;

  @override
  Widget build(BuildContext context) {
    final u = url;
    final semFoto = Container(
      color: AppColors.primaryWash,
      alignment: Alignment.center,
      child: Icon(Icons.image_outlined,
          size: tamanhoIcone,
          color: AppColors.textSecondary.withValues(alpha: .5)),
    );
    if (u == null || u.isEmpty) return semFoto;
    return CachedNetworkImage(
      imageUrl: u,
      fit: BoxFit.cover,
      placeholder: (_, __) => Container(color: AppColors.surface2),
      errorWidget: (_, __, ___) => semFoto,
    );
  }
}

class _EmBreve extends StatelessWidget {
  const _EmBreve();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(Spacing.xxl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.storefront_outlined,
                size: 56, color: AppColors.textSecondary.withValues(alpha: .4)),
            const SizedBox(height: Spacing.md),
            Text(
              'Em breve'.tr,
              style: const TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w700,
                color: AppColors.textPrimary,
              ),
            ),
            const SizedBox(height: Spacing.sm),
            Text(
              'A Loja Online da Bora está quase pronta. Volta em breve.'.tr,
              textAlign: TextAlign.center,
              style: const TextStyle(color: AppColors.textSecondary),
            ),
          ],
        ),
      ),
    );
  }
}

class _Aviso extends StatelessWidget {
  const _Aviso.erro({required this.onTentar})
      : _icone = Icons.wifi_off_outlined,
        _vazia = false;

  const _Aviso.vazia()
      : onTentar = null,
        _icone = Icons.inventory_2_outlined,
        _vazia = true;

  final VoidCallback? onTentar;
  final IconData _icone;
  final bool _vazia;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(Spacing.xxl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(_icone,
                size: 56, color: AppColors.textSecondary.withValues(alpha: .4)),
            const SizedBox(height: Spacing.md),
            Text(
              _vazia
                  ? 'Ainda não há produtos nesta loja.'.tr
                  : 'Não foi possível carregar a loja. Tenta outra vez.'.tr,
              textAlign: TextAlign.center,
              style: const TextStyle(color: AppColors.textSecondary),
            ),
            if (onTentar != null) ...[
              const SizedBox(height: Spacing.lg),
              OutlinedButton(
                onPressed: onTentar,
                child: Text('Tentar outra vez'.tr),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
