import 'package:flutter/material.dart';

/// Variantes visuais do widget [BoraMascot].
///
/// Os assets vêm directamente do design handoff (decisão D4 da Fase 3.0:
/// crop dos assets de marca em vez de pedir render isolada da mascote).
enum BoraMascotVariant {
  /// Mascote sozinha (ícone quadrado 1024×1024). Usar para splash, empty
  /// states, avatares grandes e hero illustrations pequenas.
  icon,

  /// Logo horizontal completo (mascote + letras "BORA" em verde/laranja).
  /// Usar em onboarding, headers de marca e ecrã de login.
  logo,
}

/// Render da mascote BORA a partir dos assets de marca.
///
/// Para [BoraMascotVariant.icon], [size] define largura = altura.
/// Para [BoraMascotVariant.logo], [size] define apenas a altura — a largura
/// é proporcional ao aspect ratio nativo do logo horizontal (limitada a
/// `size * 2.5` por `ConstrainedBox` para não rebentar layouts).
///
/// Exemplo splash:
/// ```dart
/// const BoraMascot(variant: BoraMascotVariant.icon, size: 128)
/// ```
///
/// Exemplo header de login:
/// ```dart
/// const BoraMascot(variant: BoraMascotVariant.logo, size: 56)
/// ```
class BoraMascot extends StatelessWidget {
  const BoraMascot({
    super.key,
    this.variant = BoraMascotVariant.icon,
    this.size = 96,
    this.semanticLabel,
  });

  final BoraMascotVariant variant;

  /// Para [BoraMascotVariant.icon]: largura = altura.
  /// Para [BoraMascotVariant.logo]: apenas altura; largura segue aspect ratio.
  final double size;

  /// Label de acessibilidade. Default: "BORA App mascot".
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final Widget image;
    switch (variant) {
      case BoraMascotVariant.icon:
        image = Image.asset(
          'assets/branding/bora_app_icon.png',
          width: size,
          height: size,
          fit: BoxFit.contain,
        );
        break;
      case BoraMascotVariant.logo:
        image = ConstrainedBox(
          // Logo horizontal tem ratio ~3:1; limite generoso a 2.5×size para
          // proteger layouts que passem por engano um valor grande de `size`.
          constraints: BoxConstraints(maxWidth: size * 2.5),
          child: Image.asset(
            'assets/branding/bora_logo.png',
            height: size,
            fit: BoxFit.contain,
          ),
        );
        break;
    }

    return Semantics(
      label: semanticLabel ?? 'BORA App mascot',
      image: true,
      child: image,
    );
  }
}
