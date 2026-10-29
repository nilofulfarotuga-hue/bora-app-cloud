import 'package:flutter/material.dart';

import '../../config/app_colors.dart';
import '../../models/order_model.dart';
import '../../utils/conta_curta_dinheiro.dart';

/// 28/10/2026 (missao-geral, C3): a linha "Total · já pago com saldo/tokens ·
/// RECEBER" por baixo do valor a cobrar, nos cartões e painéis do estafeta.
/// Some sozinha quando não há nada pago antes ou não é dinheiro.
class ContaCurtaDinheiroTexto extends StatelessWidget {
  const ContaCurtaDinheiroTexto({
    super.key,
    required this.order,
    this.cor,
    this.tamanho = 12.5,
  });

  final OrderModel order;

  /// Cor do texto (ex.: branco por cima da faixa laranja).
  final Color? cor;
  final double tamanho;

  @override
  Widget build(BuildContext context) {
    final texto = contaCurtaDinheiro(order);
    if (texto == null) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Text(
        texto,
        key: const Key('conta_curta_dinheiro'),
        style: TextStyle(
          fontSize: tamanho,
          fontWeight: FontWeight.w600,
          height: 1.3,
          color: cor ?? AppColors.textSecondary,
        ),
      ),
    );
  }
}
