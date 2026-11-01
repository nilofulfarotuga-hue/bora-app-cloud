import 'package:flutter/material.dart';

import '../config/app_colors.dart';
import '../config/app_spacing.dart';
import '../l10n/tr.dart';
import '../models/cleaning_models.dart';

/// "Semanal · próxima: 08/11 10:00" (hora de Lisboa); sem data, só
/// "Semanal". App do cliente (traduzido).
String linhaSerieLimpeza(CleaningBooking b, DateTime? proxima) {
  final tipo = b.recurrenceLabel.tr;
  if (proxima == null) return tipo;
  return '{0} · próxima: {1}'
      .trArgs([tipo, CleaningLabels.diaHoraLisboa(proxima)]);
}

/// Selo pequeno das limpezas (01/11/2026, S1/S3/S4): "Semanal · próxima:
/// 08/11 10:00", "Série parada", "Cliente habitual". Verde da marca; o texto
/// vem já pronto (e traduzido) de quem chama — a app da profissional não usa
/// o dicionário PT/EN. Letra de 16 px por defeito (adendo 4 · item 9: texto
/// novo do cliente nunca abaixo); a agenda da profissional passa [tamanho].
class SeloLimpeza extends StatelessWidget {
  const SeloLimpeza(
    this.texto, {
    super.key,
    this.icone = Icons.repeat,
    this.apagado = false,
    this.tamanho = 16,
  });

  final String texto;
  final IconData icone;

  /// Cinzento em vez de verde (ex.: "Série parada").
  final bool apagado;
  final double tamanho;

  @override
  Widget build(BuildContext context) {
    final cor = apagado ? AppColors.textSecondary : AppColors.primary;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: Spacing.sm, vertical: 3),
      decoration: BoxDecoration(
        color: apagado ? AppColors.divider : AppColors.primaryWash,
        borderRadius: BorderRadius.circular(Radii.md),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icone, size: tamanho, color: cor),
          const SizedBox(width: 4),
          Flexible(
            child: Text(
              texto,
              style: TextStyle(
                color: cor,
                fontSize: tamanho,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
