/// ENTREGA MARCADA para o estafeta (30/10/2026).
///
/// Um pedido agendado (`scheduled_for`) mostra na lista, na oferta e no
/// detalhe, em destaque: "Entrega marcada: 10:00–10:30" (com o dia quando não
/// é hoje). A app do estafeta é em português e não muda de idioma.
library;

import 'package:flutter/material.dart';

import '../config/app_colors.dart';
import '../models/order_model.dart';
import '../services/agendar_pedido.dart';

class EntregaMarcadaEstafeta extends StatelessWidget {
  const EntregaMarcadaEstafeta({
    super.key,
    required this.order,
    this.compacto = false,
    this.agora,
  });

  final OrderModel order;

  /// Na lista de pedidos disponíveis: letra um pouco mais pequena.
  final bool compacto;

  /// Só para testes: um relógio fixo.
  final DateTime? agora;

  @override
  Widget build(BuildContext context) {
    final texto = textoEntregaMarcada(order.scheduledFor, agora ?? DateTime.now());
    if (texto == null) return const SizedBox.shrink();
    return Container(
      key: const Key('entrega-marcada-estafeta'),
      width: double.infinity,
      padding: EdgeInsets.symmetric(horizontal: 12, vertical: compacto ? 6 : 10),
      decoration: BoxDecoration(
        color: AppColors.primary.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.primary.withValues(alpha: 0.45)),
      ),
      child: Row(
        children: [
          Icon(Icons.event, color: AppColors.primaryDark, size: compacto ? 18 : 22),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              texto,
              style: TextStyle(
                fontWeight: FontWeight.w800,
                fontSize: compacto ? 14 : 16,
                color: AppColors.primaryDark,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
