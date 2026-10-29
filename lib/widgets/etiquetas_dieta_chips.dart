import 'package:flutter/material.dart';

import '../config/app_colors.dart';
import '../l10n/tr.dart';
import '../models/etiquetas_dieta.dart';
import '../services/interruptores_app.dart';

/// As etiquetas do menu de um prato (vegetariano, picante, sem glúten) em
/// chips pequenos. Só aparecem com o interruptor `feature_etiquetas_menu`
/// ligado no painel admin e quando o prato tem etiquetas (adendo 4 · item 5).
class EtiquetasDietaChips extends StatefulWidget {
  const EtiquetasDietaChips({
    super.key,
    required this.etiquetas,
    this.compacto = false,
    this.margem = const EdgeInsets.only(top: 4),
  });

  final List<String> etiquetas;

  /// Na lista do menu os chips são mais pequenos (a ficha usa o tamanho normal).
  final bool compacto;
  final EdgeInsets margem;

  @override
  State<EtiquetasDietaChips> createState() => _EtiquetasDietaChipsState();
}

class _EtiquetasDietaChipsState extends State<EtiquetasDietaChips> {
  bool _ligado = true;

  @override
  void initState() {
    super.initState();
    InterruptoresApp.instance.ligado(InterruptoresApp.etiquetasMenu).then((v) {
      if (mounted && v != _ligado) setState(() => _ligado = v);
    });
  }

  static IconData _icone(String t) => switch (t) {
        'vegetariano' => Icons.eco_outlined,
        'picante' => Icons.local_fire_department_outlined,
        _ => Icons.grain,
      };

  @override
  Widget build(BuildContext context) {
    final tags = normalizarEtiquetas(widget.etiquetas);
    if (!_ligado || tags.isEmpty) return const SizedBox.shrink();
    final tamanho = widget.compacto ? 14.0 : 16.0;
    return Padding(
      padding: widget.margem,
      child: Wrap(
        key: const Key('etiquetas_dieta'),
        spacing: 6,
        runSpacing: 4,
        children: [
          for (final t in tags)
            Container(
              padding: EdgeInsets.symmetric(
                  horizontal: widget.compacto ? 6 : 8,
                  vertical: widget.compacto ? 2 : 3),
              decoration: BoxDecoration(
                color: AppColors.primary.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                    color: AppColors.primary.withValues(alpha: 0.35)),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(_icone(t), size: tamanho + 2, color: AppColors.primary),
                  const SizedBox(width: 3),
                  Text(
                    (kEtiquetasDietaTexto[t] ?? t).tr,
                    style: TextStyle(
                      fontSize: tamanho,
                      fontWeight: FontWeight.w600,
                      color: AppColors.primary,
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
