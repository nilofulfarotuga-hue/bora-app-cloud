import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart' as ll;
import 'package:share_plus/share_plus.dart';

import '../config/app_colors.dart';
import '../l10n/tr.dart';
import '../models/order_model.dart';
import '../services/order_eta_service.dart';
import '../utils/hora_lisboa.dart';

/// Texto para partilhar o seguimento do pedido (padrão Uber Eats "Partilhar
/// o estado", 04/10/2026): loja, estado e hora prevista em hora de Lisboa.
///
/// Função pura — [agora] e [minutos] vêm de fora para dar para testar.
String textoPartilhaSeguimento(
  OrderModel order, {
  required int? minutos,
  required DateTime agora,
}) {
  final loja = (order.vendorName ?? '').trim();
  final linhas = <String>[
    loja.isEmpty
        ? 'O meu pedido Bora ({0}): {1}.'.trArgs([order.orderCode, order.status.label])
        : 'O meu pedido Bora de {0} ({1}): {2}.'
            .trArgs([loja, order.orderCode, order.status.label]),
  ];
  if (minutos != null && minutos > 0) {
    final h = horaLisboa(agora.add(Duration(minutes: minutos)));
    String dd(int n) => n.toString().padLeft(2, '0');
    linhas.add('Chegada prevista por volta das {0}.'
        .trArgs(['${dd(h.hour)}:${dd(h.minute)}']));
  }
  return linhas.join('\n');
}

/// Botão "Partilhar" do ecrã de seguimento.
class BotaoPartilharSeguimento extends StatelessWidget {
  const BotaoPartilharSeguimento({super.key, required this.order, this.driverPos});

  final OrderModel order;
  final ll.LatLng? driverPos;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: 'Partilhar o seguimento'.tr,
      icon: const Icon(Icons.ios_share, color: AppColors.textSecondary),
      onPressed: () {
        final texto = textoPartilhaSeguimento(
          order,
          minutos: order.scheduledFor == null
              ? OrderEtaService.minutesRemaining(order, driverPos: driverPos)
              : null,
          agora: DateTime.now(),
        );
        Share.share(texto);
      },
    );
  }
}
