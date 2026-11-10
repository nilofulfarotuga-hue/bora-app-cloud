// lib/widgets/checkin/checkin_barra_proximo.dart
//
// Barra "Faltam X dias para o açaí" (Bloco G, 10/11/2026): a foto real do próximo
// prémio, quantos check-ins faltam, uma barra que enche e o valor em euros à vista.
// Sem pedido pago nos últimos 30 dias (R2), a linha de baixo avisa que o prémio
// fica guardado até haver um pedido.
import 'package:flutter/material.dart';

import '../../config/app_colors.dart';
import '../../l10n/tr.dart';
import '../../services/checkin_premios_service.dart';
import '../../utils/checkin_regras.dart';
import 'premio_foto.dart';

class CheckinBarraProximo extends StatelessWidget {
  const CheckinBarraProximo({
    super.key,
    required this.marco,
    required this.faltam,
    required this.progresso,
    this.precisaPedido = false,
  });

  final CheckinMarco marco;
  final int faltam;

  /// 0..1 desde o prémio anterior até este.
  final double progresso;
  final bool precisaPedido;

  @override
  Widget build(BuildContext context) {
    final titulo = marco.titulo.tr;
    final texto = faltam <= 0
        ? 'Hoje chegas a {0}!'.trArgs([titulo])
        : faltam == 1
            ? 'Falta 1 dia para {0}'.trArgs([titulo])
            : 'Faltam {0} dias para {1}'.trArgs([faltam, titulo]);
    final valor = valorEmEuros(marco.valorCents);
    final baixo = precisaPedido
        ? 'Falta 1 pedido para desbloquear o prémio'.tr
        : [
            if (valor.isNotEmpty) 'Vale {0}'.trArgs([valor]),
            if (marco.lojaNome != null) marco.lojaNome!,
          ].join(' · ');
    return Container(
      key: const Key('checkin_barra_proximo'),
      padding: const EdgeInsets.fromLTRB(8, 8, 10, 8),
      decoration: BoxDecoration(
        color: const Color(0xFFF0FDF4),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFBBF7D0)),
      ),
      child: Row(
        children: [
          PremioFoto(url: marco.fotoUrl ?? marco.lojaFotoUrl, tipo: marco.tipo, tamanho: 46),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  texto,
                  key: const Key('checkin_barra_texto'),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: AppColors.primaryDark),
                ),
                const SizedBox(height: 6),
                ClipRRect(
                  borderRadius: BorderRadius.circular(999),
                  child: LinearProgressIndicator(
                    key: const Key('checkin_barra_progresso'),
                    value: progresso.clamp(0.0, 1.0),
                    minHeight: 8,
                    backgroundColor: Colors.white,
                    color: AppColors.primary,
                  ),
                ),
                if (baixo.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(
                    baixo,
                    key: const Key('checkin_barra_valor'),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w600,
                      color: precisaPedido ? AppColors.textSecondary : AppColors.primaryDark,
                    ),
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
