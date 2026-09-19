import 'package:flutter/material.dart';

import '../../config/app_colors.dart';

/// CTA destaque laranja BORA.
///
/// Regra do design system: **1 elemento laranja por ecrã**. Usar APENAS na
/// acção principal de cada ecrã. Restantes botões usam o tema global (verde).
///
/// Estados visuais (alinhados com tokens 3.1A):
/// - default:           AppColors.accent     (#F97316)
/// - pressed/focused:   AppColors.accentDark (#EA580C)
/// - disabled:          bg 50% alpha + fg 70% alpha
class BoraAccentButton extends StatelessWidget {
  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final bool loading;
  final bool fullWidth;

  const BoraAccentButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
    this.loading = false,
    this.fullWidth = true,
  });

  @override
  Widget build(BuildContext context) {
    final Widget child = loading
        ? const SizedBox(
            height: 20,
            width: 20,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              valueColor: AlwaysStoppedAnimation(Colors.white),
            ),
          )
        : Row(
            mainAxisAlignment: MainAxisAlignment.center,
            mainAxisSize: MainAxisSize.min,
            children: [
              if (icon != null) ...[
                Icon(icon, size: 20),
                const SizedBox(width: 8),
              ],
              // Flexible+ellipsis: com fontes grandes (acessibilidade) um
              // label comprido estourava a Row para fora do botão (F-OLHO).
              Flexible(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          );

    final button = ElevatedButton(
      style: ButtonStyle(
        backgroundColor: WidgetStateProperty.resolveWith<Color>((states) {
          if (states.contains(WidgetState.disabled)) {
            return AppColors.accent.withValues(alpha: 0.5);
          }
          if (states.contains(WidgetState.pressed) ||
              states.contains(WidgetState.focused)) {
            return AppColors.accentDark;
          }
          return AppColors.accent;
        }),
        foregroundColor: WidgetStateProperty.resolveWith<Color>((states) {
          if (states.contains(WidgetState.disabled)) {
            return Colors.white.withValues(alpha: 0.7);
          }
          return Colors.white;
        }),
        minimumSize: WidgetStateProperty.all(const Size(88, 52)),
        shape: WidgetStateProperty.all(const RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(14)),
        )),
        textStyle: WidgetStateProperty.all(const TextStyle(
          fontFamily: 'Inter',
          fontSize: 16,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.3,
        )),
        elevation: WidgetStateProperty.all<double>(0),
      ),
      onPressed: (loading || onPressed == null) ? null : onPressed,
      child: child,
    );

    return fullWidth ? SizedBox(width: double.infinity, child: button) : button;
  }
}
