/// PEDIDO AGENDADO no seguimento do cliente (30/10/2026).
///
/// Um pedido com `scheduled_for` mostra, em destaque, "Agendado para sáb
/// 01/11, 10:00–10:30". Enquanto espera pela hora (um pedido não parceiro fica
/// em `preparing`, sem estafeta, até 30 min antes) o título do estado diz
/// "Pedido agendado" e nunca "À procura de estafeta": a regra está em
/// [aEsperaDaHoraMarcada].
library;

import 'package:flutter/material.dart';

import '../config/app_colors.dart';
import '../l10n/tr.dart';
import '../models/order_model.dart';
import '../services/agendar_pedido.dart';

/// O título do estado no seguimento: "Pedido agendado" enquanto o pedido
/// espera pela hora marcada; senão o de sempre ([OrderStatusLabel.label]).
String tituloDoSeguimento(OrderModel o, DateTime agora) =>
    aEsperaDaHoraMarcada(o, agora) ? 'Pedido agendado'.tr : o.status.label;

class AvisoPedidoAgendado extends StatelessWidget {
  const AvisoPedidoAgendado({super.key, required this.order, this.agora});

  final OrderModel order;

  /// Só para testes: um relógio fixo.
  final DateTime? agora;

  @override
  Widget build(BuildContext context) {
    final quando = order.scheduledFor;
    if (quando == null) return const SizedBox.shrink();
    final espera = aEsperaDaHoraMarcada(order, agora ?? DateTime.now());
    return Container(
      key: const Key('pedido-agendado-aviso'),
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.primary.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.primary.withValues(alpha: 0.35)),
      ),
      child: Row(
        children: [
          const Icon(Icons.event, color: AppColors.primaryDark, size: 22),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  textoAgendadoPara(janelaDoInstante(quando)),
                  key: const Key('pedido-agendado-texto'),
                  style: const TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 15,
                    color: AppColors.primaryDark,
                  ),
                ),
                if (espera) ...[
                  const SizedBox(height: 2),
                  Text(
                    'Chamamos o estafeta perto da hora marcada.'.tr,
                    key: const Key('pedido-agendado-espera'),
                    style: const TextStyle(fontSize: 12.5, color: AppColors.textSecondary),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}
