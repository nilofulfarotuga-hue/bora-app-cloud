import 'package:flutter/material.dart';

import 'app_theme.dart';

/// Tokens de cor estendidos para o Bora App (design reference 2026-04-18).
///
/// Re-exporta os essenciais de [AppTheme] e acrescenta tokens semânticos
/// usados em contextos específicos (mapas, status, categorias). Ficheiros
/// de ecrã devem preferir estes tokens a valores hardcoded.
class AppColors {
  // Marca
  static const Color primary = AppTheme.primary;
  static const Color primaryDark = AppTheme.primaryDark;
  static const Color primaryDeep = AppTheme.primaryDeep;
  static const Color primaryMid = AppTheme.primaryMid; // verde médio (substitui antigo primaryLight)
  static const Color primaryLight = AppTheme.primaryLight; // tint suave (nova semântica 3.1A)
  static const Color primaryWash = AppTheme.primaryWash;
  static const Color accent = AppTheme.secondary;
  static const Color accentDark = AppTheme.secondaryDark;
  static const Color accentLight = AppTheme.secondaryLight; // legacy compat

  // Superfícies
  static const Color background = AppTheme.background;
  static const Color surface = AppTheme.surface;
  static const Color surface2 = AppTheme.surface2;
  static const Color card = AppTheme.cardBg;
  static const Color divider = AppTheme.divider;
  static const Color dividerStrong = AppTheme.dividerStrong;

  // Texto
  static const Color textPrimary = AppTheme.textPrimary;
  static const Color textSecondary = AppTheme.textSecondary;
  static const Color textSubtle = AppTheme.textSubtle;
  static const Color textOnPrimary = Colors.white;

  // Semânticos (status, mapas)
  static const Color success = Color(0xFF16A34A); // verde Bora
  static const Color warning = Color(0xFFF59E0B); // amarelo (era laranja antes de 3.1A)
  static const Color error = Color(0xFFDC2626);
  static const Color info = Color(0xFF2563EB);

  // Marcadores de mapa (BR §7 — driver flow)
  static const Color mapPickup = Color(0xFFF97316); // laranja
  static const Color mapDropoff = Color(0xFF1C6EF2); // azul

  // Elevation (3 níveis discretos + sombra topo de bottom nav).
  // Cor base: slate-900 (#0F172A) com alpha variável (6/8/12/6%).
  static const List<BoxShadow> shadowSm = [
    BoxShadow(color: Color(0x0F0F172A), offset: Offset(0, 1), blurRadius: 2),
  ];
  static const List<BoxShadow> shadowCard = [
    BoxShadow(color: Color(0x140F172A), offset: Offset(0, 2), blurRadius: 8),
  ];
  static const List<BoxShadow> shadowLg = [
    BoxShadow(color: Color(0x1F0F172A), offset: Offset(0, 8), blurRadius: 24),
  ];
  static const List<BoxShadow> shadowNav = [
    BoxShadow(color: Color(0x0F0F172A), offset: Offset(0, -4), blurRadius: 16),
  ];

  // Gradientes (delegam para AppTheme)
  static const LinearGradient headerGradient = AppTheme.headerGradient;
  static const LinearGradient promoGradient = AppTheme.promoGradient;

  // Categorias (tile cards) — paleta alinhada à referência visual.
  static const LinearGradient tileRestaurants = LinearGradient(
    colors: [Color(0xFFF97316), Color(0xFFFB923C)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );
  static const LinearGradient tileSupermarkets = LinearGradient(
    colors: [Color(0xFF16A34A), Color(0xFF22C55E)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );
  static const LinearGradient tilePharmacy = LinearGradient(
    colors: [Color(0xFF1C6EF2), Color(0xFF48CAE4)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );
  static const LinearGradient tileSendPackage = LinearGradient(
    colors: [Color(0xFFF97316), Color(0xFFFB923C)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );
  static const LinearGradient tileCarryGroceries = LinearGradient(
    colors: [Color(0xFF16A34A), Color(0xFF4ADE80)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );
  static const LinearGradient tileReserveTable = LinearGradient(
    colors: [Color(0xFF6A1B9A), Color(0xFF8E24AA)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );
  static const LinearGradient tileStores = LinearGradient(
    colors: [Color(0xFF455A64), Color(0xFF607D8B)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );
}
