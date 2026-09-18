import 'package:flutter/material.dart';

import '../../config/app_colors.dart';

/// Selo do motorista para corridas de BALCÃO (`tvde_rides.source='balcao'`):
/// cliente sem aplicação, criado pelo admin por telefone. Mostra-se da oferta
/// até ao fim da corrida (missão `central-corridas-balcao-2026-09-18`).
///
/// Cor semântica `AppColors.info` (azul) de propósito — o ecrã de oferta e o
/// de corrida ativa já estão no limite da regra "1 laranja/ecrã" (o botão
/// Aceitar já usa a cor de destaque da marca); um selo laranja aqui furava-a.
class TvdeCounterRideBadge extends StatelessWidget {
  const TvdeCounterRideBadge({super.key, this.dense = false});
  final bool dense;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(
          horizontal: dense ? 8 : 10, vertical: dense ? 3 : 5),
      decoration: BoxDecoration(
        color: AppColors.info.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.phone_in_talk,
              size: dense ? 12 : 14, color: AppColors.info),
          const SizedBox(width: 4),
          Text('Cliente sem aplicação — liga-lhe',
              style: TextStyle(
                  fontSize: dense ? 10.5 : 11.5,
                  fontWeight: FontWeight.w700,
                  color: AppColors.info)),
        ],
      ),
    );
  }
}
