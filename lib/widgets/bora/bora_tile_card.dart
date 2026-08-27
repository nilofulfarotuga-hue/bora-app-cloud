import 'package:flutter/material.dart';

import '../../config/app_colors.dart';
import '../../config/app_spacing.dart';

/// Card categoria Bora — rounded 20, fundo gradiente, label bold.
///
/// Dois layouts disponíveis:
/// - **`BoraTileCard.image()`** (recomendado): Image.asset (PNG 3D cartoon
///   das categorias em `assets/categories/`) ocupando ~70% do tile, label
///   em baixo sobre o gradient verde.
/// - **Construtor default (`@Deprecated`)**: renderiza ícone Material ou
///   imagem em overlay full-bleed com gradient escurecido para contraste
///   do label. Mantido para preservar callers existentes — migrar na Fase 4.
class BoraTileCard extends StatelessWidget {
  /// Construtor legacy — preserva quem ainda passa IconData/icon custom.
  /// Será removido depois da migração dos ecrãs (Fase 4).
  @Deprecated('Use BoraTileCard.image() com PNG das categorias 3D cartoon.')
  const BoraTileCard({
    super.key,
    required this.label,
    required this.gradient,
    required this.onTap,
    this.icon,
    this.iconData,
    this.imageAsset,
    this.height = 140,
    this.compacto = false,
  }) : _useImageLayout = false;

  /// Construtor recomendado — usa PNG 3D cartoon (assets/categories/).
  const BoraTileCard.image({
    super.key,
    required this.label,
    required String this.imageAsset,
    required this.gradient,
    required this.onTap,
    this.height = 140,
    this.compacto = false,
  })  : icon = null,
        iconData = null,
        _useImageLayout = true;

  final String label;
  final Gradient gradient;
  final VoidCallback onTap;

  /// Widget de ícone custom (prioridade sobre iconData). Legacy.
  final Widget? icon;

  /// IconData simples, renderizado branco grande. Legacy.
  final IconData? iconData;

  /// Path de asset PNG/JPG.
  final String? imageAsset;

  final double height;

  /// Grelha de 4 colunas (home do cliente, 2026-08-27): a célula fica mais
  /// estreita, por isso o rótulo desce de tamanho e as margens apertam.
  /// Só muda a escala — cor, cantos e sombra ficam iguais.
  final bool compacto;

  /// Layout switch: true → 70% imagem em cima + label rodapé.
  final bool _useImageLayout;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(Radii.xl),
      child: Container(
        height: height,
        decoration: BoxDecoration(
          gradient: gradient,
          borderRadius: BorderRadius.circular(Radii.xl),
          boxShadow: AppColors.shadowCard,
        ),
        clipBehavior: Clip.antiAlias,
        child: _useImageLayout ? _buildImageLayout() : _buildLegacyLayout(),
      ),
    );
  }

  /// Layout novo — imagem full-bleed (BoxFit.cover) + overlay escuro no rodapé
  /// para contraste, label sobreposto em baixo. Espelha comp_tile_card.html:
  /// `object-fit: cover; opacity: 0.95` + gradient 180° transparente->preto 40%.
  ///
  /// Os assets em assets/categories/ são JPEG/WEBP opacos (sem alpha), por isso
  /// preenchem o tile inteiro (cover) em vez de flutuar sobre o gradient — o
  /// gradient passa a ser apenas moldura/fallback por trás da imagem.
  Widget _buildImageLayout() {
    return Stack(
      fit: StackFit.expand,
      children: [
        // Imagem full-bleed (tapa o seu próprio fundo e o gradient).
        Opacity(
          opacity: 0.95,
          child: Image.asset(imageAsset!, fit: BoxFit.cover),
        ),
        // Escurecimento no rodapé só para contraste do label.
        const DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.center,
              end: Alignment.bottomCenter,
              colors: [Color(0x00000000), Color(0x66000000)],
            ),
          ),
        ),
        // Label: ocupa toda a largura; FittedBox encolhe palavras longas
        // (ex.: "Restaurantes", "Supermercados") em vez de partir a meio.
        //
        // A caixa do rótulo tem ALTURA FIXA de duas linhas, mesmo quando o
        // nome só tem uma. É isso que faz todos os ladrilhos da grelha ficarem
        // exactamente iguais — e é o FittedBox que garante que nomes de duas
        // palavras nunca aparecem cortados nem com reticências: encolhem para
        // caber, não são truncados.
        Positioned(
          left: compacto ? 7 : 14,
          right: compacto ? 7 : 14,
          bottom: compacto ? 7 : 12,
          child: SizedBox(
            height: _alturaRotulo,
            child: FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(
                _rotuloEmLinhas,
                style: TextStyle(
                  color: Colors.white,
                  fontSize: compacto ? 12 : 16,
                  fontWeight: FontWeight.w800,
                  letterSpacing: compacto ? 0.02 : 0.16,
                  height: 1.12,
                  shadows: const [
                    Shadow(
                      color: Colors.black54,
                      blurRadius: 4,
                      offset: Offset(0, 1),
                    ),
                  ],
                ),
                maxLines: 2,
              ),
            ),
          ),
        ),
      ],
    );
  }

  /// Altura da caixa do rótulo: sempre duas linhas, para todos os ladrilhos
  /// da grelha terminarem à mesma altura.
  double get _alturaRotulo => (compacto ? 12 : 16) * 1.12 * 2;

  /// Na grelha estreita (4 colunas), um nome de duas palavras quebra na
  /// SEGUNDA linha em vez de encolher numa so — senao "Enviar Encomenda"
  /// aparecia em letra muito mais pequena que "Lojas", ao lado.
  ///
  /// A quebra e explicita de proposito: assim o FittedBox mede um bloco de
  /// duas linhas ja formado e limita-se a escala-lo para caber. Palavra
  /// unica comprida ("Supermercados") nao tem por onde quebrar — ai e so o
  /// FittedBox a encolher. Em nenhum dos casos ha corte nem reticencias.
  String get _rotuloEmLinhas {
    if (!compacto || label.contains('\n')) return label;
    final partes = label.split(' ');
    return partes.length == 2 ? '${partes[0]}\n${partes[1]}' : label;
  }

  /// Layout legacy — icon ou imageAsset com overlay full-bleed.
  Widget _buildLegacyLayout() {
    return Padding(
      padding: const EdgeInsets.all(Spacing.md),
      child: Stack(
        children: [
          if (imageAsset != null)
            Positioned.fill(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(Radii.xl),
                child: Opacity(
                  opacity: 0.9,
                  child: Image.asset(imageAsset!, fit: BoxFit.cover),
                ),
              ),
            ),
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(Radii.xl),
                gradient: LinearGradient(
                  colors: [
                    Colors.black.withValues(alpha: 0.0),
                    Colors.black.withValues(alpha: 0.35),
                  ],
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                ),
              ),
            ),
          ),
          Align(
            alignment: Alignment.topLeft,
            child: icon ??
                (iconData != null
                    ? Icon(iconData, color: Colors.white, size: 36)
                    : const SizedBox.shrink()),
          ),
          Align(
            alignment: Alignment.bottomLeft,
            child: Text(
              label,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.w800,
                letterSpacing: 0.2,
                shadows: [
                  Shadow(
                    color: Colors.black45,
                    blurRadius: 4,
                    offset: Offset(0, 1),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
