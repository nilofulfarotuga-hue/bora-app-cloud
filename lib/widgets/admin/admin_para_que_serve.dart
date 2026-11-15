import 'package:flutter/material.dart';

import '../../config/app_colors.dart';

/// Faixa "Para que serve" por baixo de cada tela do painel aberta pelo menu
/// (15/11/2026, missão painel-admin-15-11: "o painel mais didático, uma frase
/// por tela"). A frase é o subtítulo da entrada do menu, a mesma que aparece
/// na lista, por isso não há uma segunda verdade para manter. Fica em baixo
/// para não mexer na barra de cima nem nos botões de cada tela.
class AdminTelaComProposito extends StatelessWidget {
  const AdminTelaComProposito({
    super.key,
    required this.proposito,
    required this.child,
  });

  /// O que a tela faz, em uma frase (subtítulo do menu).
  final String proposito;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final frase = proposito.trim();
    if (frase.isEmpty) return child;
    // Juiz 15/11: com o teclado aberto (telemóvel) a faixa sai, para a tela usar
    // a altura toda; sem teclado, a faixa trata da margem de baixo (SafeArea) e
    // a tela deixa de a contar outra vez. A árvore fica sempre igual (o
    // MediaQuery está sempre lá; só a faixa entra e sai), para a tela não perder
    // o que se está a escrever.
    final teclado = MediaQuery.viewInsetsOf(context).bottom > 0;
    return Column(
      children: [
        Expanded(
          child: MediaQuery.removePadding(
            context: context,
            removeBottom: !teclado,
            child: child,
          ),
        ),
        if (!teclado)
          Material(
          key: const Key('admin_para_que_serve'),
          color: AppColors.primaryLight,
          child: SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
              child: Row(
                children: [
                  const Icon(Icons.info_outline,
                      size: 16, color: AppColors.success),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Para que serve: $frase',
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 12,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}
