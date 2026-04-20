/// Grid de espaçamentos Bora (múltiplos de 4, com 4 como base).
///
/// Uso exclusivo em `EdgeInsets`, `SizedBox` e `gap` de `Column/Row`. Evita
/// valores soltos como `10`, `14`, `6`, `7` que quebram o ritmo visual.
class Spacing {
  Spacing._();

  static const double xxs = 2.0;
  static const double xs = 4.0;
  static const double sm = 8.0;
  static const double md = 12.0;
  static const double lg = 16.0;
  static const double xl = 20.0;
  static const double xxl = 24.0;
  static const double xxxl = 32.0;
  static const double huge = 48.0;
}

/// Radius canónicos — usar estes valores em `BorderRadius.circular`.
class Radii {
  Radii._();

  static const double sm = 8.0;
  static const double md = 12.0;
  static const double lg = 16.0;
  static const double xl = 20.0; // cards categoria
  static const double xxl = 24.0;
  static const double pill = 999.0;
}
