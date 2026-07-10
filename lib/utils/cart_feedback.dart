import 'package:flutter/material.dart';

import '../config/app_colors.dart';

/// Confirmação compacta e não-bloqueante de "adicionado ao carrinho"
/// (padrão Uber Eats / Glovo).
///
/// Uma única linha (com reticências), flutuante junto ao fundo, fundo verde
/// da marca com ícone de check — substitui os SnackBars escuros/altos que
/// cobriam quase o ecrã e escondiam o item que acabou de entrar no carrinho.
/// Tocar apenas confirma; NUNCA navega automaticamente para o pagamento.
/// A ação opcional "Ver" leva ao carrinho quando o chamador a fornece.
void showAddedToCartSnack(
  BuildContext context,
  String message, {
  VoidCallback? onView,
}) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        content: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.check_circle, color: Colors.white, size: 18),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                message,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 13, color: Colors.white),
              ),
            ),
          ],
        ),
        backgroundColor: AppColors.primary,
        duration: const Duration(milliseconds: 1100),
        behavior: SnackBarBehavior.floating,
        margin: const EdgeInsets.only(bottom: 80, left: 16, right: 16),
        dismissDirection: DismissDirection.horizontal,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        action: onView == null
            ? null
            : SnackBarAction(
                label: 'Ver',
                textColor: Colors.white,
                onPressed: onView,
              ),
      ),
    );
}
