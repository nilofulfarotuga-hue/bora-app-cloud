import 'package:flutter/material.dart';

import '../../config/app_colors.dart';

/// Confirmação obrigatória antes de qualquer botão de dinheiro do painel
/// (marcar pago/recebido, reembolsar). Mostra SEMPRE o nome da pessoa/loja e
/// o valor, para o Danilo nunca marcar a linha errada (ronda 04/10, item 1).
///
/// Devolve `true` só se o Danilo carregar em [botao].
Future<bool> confirmarDinheiro(
  BuildContext context, {
  required String titulo,
  required String nome,
  required String valor,
  String? detalhe,
  String botao = 'Confirmar',
}) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(titulo),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(nome,
              style:
                  const TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
          const SizedBox(height: 4),
          Text(valor,
              style: const TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: 22,
                  color: AppColors.primary)),
          if (detalhe != null && detalhe.isNotEmpty) ...[
            const SizedBox(height: 12),
            Text(detalhe),
          ],
        ],
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar')),
        FilledButton(
            onPressed: () => Navigator.pop(ctx, true), child: Text(botao)),
      ],
    ),
  );
  return ok == true;
}
