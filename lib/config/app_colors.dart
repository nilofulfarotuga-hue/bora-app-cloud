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
  static const Color primaryLight = AppTheme.primaryLight;
  static const Color accent = AppTheme.secondary;
  static const Color accentLight = AppTheme.secondaryLight;

  // Superfícies
  static const Color background = AppTheme.background;
  static const Color surface = AppTheme.surface;
  static const Color card = AppTheme.cardBg;
  static const Color divider = AppTheme.divider;

  // Texto
  static const Color textPrimary = AppTheme.textPrimary;
  static const Color textSecondary = AppTheme.textSecondary;
  static const Color textOnPrimary = Colors.white;

  // Semânticos (status, mapas)
  static const Color success = Color(0xFF1B5E20); // verde Bora
  static const Color warning = Color(0xFFE65100); // laranja Bora
  static const Color error = Color(0xFFC62828);
  static const Color info = Color(0xFF1A73E8);

  // Marcadores de mapa (BR §7 — driver flow)
  static const Color mapPickup = Color(0xFFF57C00); // laranja
  static const Color mapDropoff = Color(0xFF1C6EF2); // azul

  // Gradientes (delegam para AppTheme)
  static const LinearGradient headerGradient = AppTheme.headerGradient;
  static const LinearGradient promoGradient = AppTheme.promoGradient;

  // Categorias (tile cards) — paleta alinhada à referência visual.
  static const LinearGradient tileRestaurants = LinearGradient(
    colors: [Color(0xFFE65100), Color(0xFFF57C00)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );
  static const LinearGradient tileSupermarkets = LinearGradient(
    colors: [Color(0xFF2E7D32), Color(0xFF43A047)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );
  static const LinearGradient tilePharmacy = LinearGradient(
    colors: [Color(0xFF1C6EF2), Color(0xFF48CAE4)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );
  static const LinearGradient tileSendPackage = LinearGradient(
    colors: [Color(0xFFE65100), Color(0xFFFF9800)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );
  static const LinearGradient tileCarryGroceries = LinearGradient(
    colors: [Color(0xFF2E7D32), Color(0xFF66BB6A)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );
  static const LinearGradient tileReserveTable = LinearGradient(
    colors: [Color(0xFF6A1B9A), Color(0xFF8E24AA)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );
}
